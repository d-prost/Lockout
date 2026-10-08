#requires -Version 5.1
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Lockout.Storage.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Lockout.Core.psm1') -Force

function Get-EventBounds {
    param([string]$DomainController)
    # Die Security-Loggrenzen werden vor jedem Abruf geprueft.
    $newest = Get-WinEvent -ComputerName $DomainController -LogName Security -MaxEvents 1 -ErrorAction Stop
    $oldest = Get-WinEvent -ComputerName $DomainController -LogName Security -Oldest -MaxEvents 1 -ErrorAction Stop
    return [pscustomobject]@{ Oldest = [long]$oldest.RecordId; Latest = [long]$newest.RecordId }
}

function Get-LockoutWindow {
    param([string]$DomainController,[long]$AfterId,[long]$UntilId,[datetime]$SinceUtc=[datetime]::MinValue)
    $xpath = "Event[System[(EventID=4740) and (EventRecordID > $AfterId) and (EventRecordID <= $UntilId)"
    if ($SinceUtc -gt [datetime]::MinValue) {
        $stamp = $SinceUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
        $xpath += " and TimeCreated[@SystemTime >= '$stamp']"
    }
    $xpath += ']]'
    try {
        return @(Get-WinEvent -ComputerName $DomainController -LogName Security -FilterXPath $xpath -ErrorAction Stop)
    } catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { return @() }
        throw
    }
}

function Save-DcState {
    param([string]$Path,$Value)
    Write-JsonAtomic -Path $Path -Value $Value
}

function Commit-LockoutEvents {
    param([string]$DataDirectory,[string]$DomainController,[object[]]$Events,
          $State,[string]$StatePath,[int]$BatchRecords,[bool]$AlertEligible)
    # Abfragen vor dem Commit vollstaendig materialisieren. Bei Netzwerkfehler kein Cursor-Vorschub.
    $ordered = @($Events | Sort-Object RecordId)
    $seen = @{}
    $batch = New-Object 'System.Collections.Generic.List[object]'
    foreach ($event in $ordered) {
        $id = [long]$event.RecordId
        if ($id -le [long]$State.Cursor) { continue }
        $record = ConvertTo-Record -Event $event -DomainController $DomainController -AlertEligible $AlertEligible
        $json = ConvertTo-Json -InputObject $record -Compress -Depth 10
        if ($seen.ContainsKey([string]$id)) {
            if ($seen[[string]$id] -cne $json) { throw "Conflicting duplicate RecordId $id" }
            continue
        }
        $seen[[string]$id] = $json
        [void]$batch.Add($record)
        if ($batch.Count -ge $BatchRecords) {
            $slice = @($batch.ToArray())
            [void](Write-JournalSegment -DataDirectory $DataDirectory -DomainController $DomainController -Records $slice)
            $State.Cursor = [long]$slice[-1].RecordId
            Save-DcState -Path $StatePath -Value $State
            $batch.Clear()
        }
    }
    if ($batch.Count -gt 0) {
        $slice = @($batch.ToArray())
        [void](Write-JournalSegment -DataDirectory $DataDirectory -DomainController $DomainController -Records $slice)
        $State.Cursor = [long]$slice[-1].RecordId
        Save-DcState -Path $StatePath -Value $State
    }
}

function Assert-LockoutConfig {
    param([hashtable]$Config)
    foreach ($name in @('DataDirectory','DomainControllers','InitialLookbackMinutes','RetentionDays','RecordWindowSize','MaxWindowsPerRun','BatchRecords','Mail')) {
        if (-not $Config.ContainsKey($name)) { throw "Missing configuration: $name" }
    }
    foreach ($constraint in @(
        @('InitialLookbackMinutes',1,1440),@('RetentionDays',1,3650),
        @('RecordWindowSize',100,100000),@('MaxWindowsPerRun',1,500),@('BatchRecords',1,2000)
    )) {
        $value = [int]$Config[$constraint[0]]
        if ($value -lt $constraint[1] -or $value -gt $constraint[2]) { throw "Invalid setting: $($constraint[0])" }
    }
    $sources = @($Config.DomainControllers)
    if ($sources.Count -lt 1 -or $sources.Count -gt 100) { throw 'Specify 1..100 Domain Controllers.' }
    $unique = @{}
    foreach ($value in $sources) {
        $dc = [string]$value
        if ($dc -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,252}$') { throw 'Invalid DC name.' }
        $name = $dc.ToLowerInvariant()
        if ($unique.ContainsKey($name)) { throw "Duplicate Domain Controller: $dc" }
        $unique[$name] = $true
    }
    if (-not ($Config.Mail -is [hashtable])) { throw 'Mail must be a hashtable.' }
    if ([int]$Config.Mail.CooldownMinutes -lt 0 -or [int]$Config.Mail.CooldownMinutes -gt 10080) { throw 'Invalid cooldown.' }
    if ($Config.Mail.Enabled) {
        if (-not $Config.Mail.From -or -not $Config.Mail.Server -or @($Config.Mail.To).Count -lt 1) { throw 'Incomplete SMTP configuration.' }
        if ([int]$Config.Mail.Port -lt 1 -or [int]$Config.Mail.Port -gt 65535) { throw 'Invalid SMTP port.' }
    }
    $root = [IO.Path]::GetFullPath([string]$Config.DataDirectory)
    if (-not [IO.Path]::IsPathRooted($root) -or $root.StartsWith('\\')) { throw 'Use an absolute local DataDirectory.' }
    return $root
}

function Invoke-PendingMail {
    param([string]$DataDirectory,[string[]]$DomainControllers,[hashtable]$Mail)
    if (-not [bool]$Mail.Enabled) { return @() }
    $errors = New-Object 'System.Collections.Generic.List[string]'
    $cooldownPath = Join-Path $DataDirectory 'cooldown.json'
    $saved = Read-Json -Path $cooldownPath -Default ([pscustomobject]@{ LastByAccount = [pscustomobject]@{} })
    $last = @{}
    foreach ($entry in $saved.LastByAccount.PSObject.Properties) { $last[$entry.Name] = [string]$entry.Value }
    foreach ($dc in $DomainControllers) {
        $source = Get-SourceKey $dc
        foreach ($segment in @(Get-JournalSegments -DataDirectory $DataDirectory -SourceKey $source)) {
            $offsetPath = Join-Path (Join-Path (Join-Path $DataDirectory 'outbox') $source) ($segment.BaseName + '.json')
            $state = Read-Json -Path $offsetPath -Default ([pscustomobject]@{Offset=0})
            $offset = [int]$state.Offset
            $rows = @(Read-JournalSegment -Path $segment.FullName)
            if ($offset -lt 0 -or $offset -gt $rows.Count) { throw "Invalid SMTP offset: $offsetPath" }
            for ($i=$offset; $i -lt $rows.Count; $i++) {
                $item = $rows[$i]
                if ([bool]$item.AlertEligible) {
                    $account = ([string]$item.Account).ToLowerInvariant()
                    $skip = $false
                    if ($last.ContainsKey($account)) {
                        $previous = [datetime]::Parse($last[$account],[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
                        $skip = (([datetime]::UtcNow - $previous.ToUniversalTime()).TotalMinutes -lt [int]$Mail.CooldownMinutes)
                    }
                    if (-not $skip) {
                        try { Send-Alert -Record $item -Settings $Mail }
                        catch {
                            [void]$errors.Add("SMTP $($item.Key): $($_.Exception.Message)")
                            break
                        }
                        $last[$account] = [datetime]::UtcNow.ToString('o')
                        Write-JsonAtomic -Path $cooldownPath -Value ([ordered]@{LastByAccount=$last})
                    }
                }
                Write-JsonAtomic -Path $offsetPath -Value ([ordered]@{Offset=($i+1)})
            }
        }
    }
    return @($errors.ToArray())
}

function Invoke-LockoutMonitor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)
    $root = Assert-LockoutConfig $Config
    [void][IO.Directory]::CreateDirectory($root)
    [void][IO.Directory]::CreateDirectory((Join-Path $root 'state'))
    $mutex = [Threading.Mutex]::new($false,('Local\ADLockout-' + (Get-SourceKey $root)))
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(10000) }
        catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw 'Another monitor instance owns this directory.' }
        $issues = New-Object 'System.Collections.Generic.List[string]'
        $backlog = New-Object 'System.Collections.Generic.List[string]'
        foreach ($inputDc in @($Config.DomainControllers)) {
            $dc = [string]$inputDc
            $source = Get-SourceKey $dc
            $statePath = Join-Path (Join-Path $root 'state') ($source + '.json')
            try {
                $state = Read-Json -Path $statePath -Default $null
                $durable = Get-LastJournalRecordId -DataDirectory $root -SourceKey $source
                if ($null -eq $state) {
                    if ($durable -gt 0) { throw 'Checkpoint is missing while a journal exists; operator recovery required.' }
                    $bounds = Get-EventBounds -DomainController $dc
                    $state = [pscustomobject]@{
                        Version=2; DomainController=$dc; Mode='bootstrap'; Cursor=[long]0
                        BootstrapLatest=[long]$bounds.Latest
                        BootstrapSinceUtc=[datetime]::UtcNow.AddMinutes(-[int]$Config.InitialLookbackMinutes).ToString('o')
                    }
                    Save-DcState -Path $statePath -Value $state
                }
                if ([int]$state.Version -ne 2 -or [string]$state.DomainController -ine $dc) { throw 'Checkpoint schema/source mismatch.' }
                if ($durable -gt [long]$state.Cursor) {
                    # Journal nach Absturz bereits geschrieben; nie hinter dessen letzten RecordID fallen.
                    $state.Cursor = $durable
                    Save-DcState -Path $statePath -Value $state
                }
                $bounds = Get-EventBounds -DomainController $dc
                if ([long]$bounds.Latest -lt [long]$state.Cursor) { throw 'Security log reset detected.' }
                if ([string]$state.Mode -eq 'bootstrap') {
                    if ([long]$state.BootstrapLatest -gt [long]$bounds.Latest) { throw 'Bootstrap snapshot no longer available.' }
                    $since = [datetime]::Parse([string]$state.BootstrapSinceUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
                    $items = @(Get-LockoutWindow -DomainController $dc -AfterId ([long]$state.Cursor) -UntilId ([long]$state.BootstrapLatest) -SinceUtc $since)
                    Commit-LockoutEvents -DataDirectory $root -DomainController $dc -Events $items -State $state -StatePath $statePath -BatchRecords ([int]$Config.BatchRecords) -AlertEligible ([bool]$Config.Mail.Enabled)
                    $state.Cursor = [long]$state.BootstrapLatest
                    $state.Mode = 'steady'
                    Save-DcState -Path $statePath -Value $state
                }
                if ([string]$state.Mode -ne 'steady') { throw 'Unsupported checkpoint mode.' }
                if ([long]$bounds.Oldest -gt ([long]$state.Cursor + 1)) { throw 'Security event log retention gap; operator review required.' }
                $windows = 0
                while ([long]$state.Cursor -lt [long]$bounds.Latest -and $windows -lt [int]$Config.MaxWindowsPerRun) {
                    $limit = [Math]::Min([long]$bounds.Latest,[long]$state.Cursor + [long]$Config.RecordWindowSize)
                    $events = @(Get-LockoutWindow -DomainController $dc -AfterId ([long]$state.Cursor) -UntilId $limit)
                    Commit-LockoutEvents -DataDirectory $root -DomainController $dc -Events $events -State $state -StatePath $statePath -BatchRecords ([int]$Config.BatchRecords) -AlertEligible ([bool]$Config.Mail.Enabled)
                    $state.Cursor = [long]$limit
                    Save-DcState -Path $statePath -Value $state
                    $windows++
                }
                Repair-JournalTextLogs -DataDirectory $root -SourceKey $source
                if ([long]$state.Cursor -lt [long]$bounds.Latest) { [void]$backlog.Add($dc) }
            } catch { [void]$issues.Add(('{0}: {1}' -f $dc,$_.Exception.Message)) }
        }
        foreach ($err in @(Invoke-PendingMail -DataDirectory $root -DomainControllers @($Config.DomainControllers) -Mail $Config.Mail)) {
            if ($err) { [void]$issues.Add([string]$err) }
        }
        $cleanup = Invoke-JournalRetention -DataDirectory $root -RetentionDays ([int]$Config.RetentionDays)
        if ($cleanup.Blocked -gt 0) { [void]$issues.Add(('Retention blocked by {0} pending SMTP segment(s).' -f $cleanup.Blocked)) }
        $status = if ($issues.Count -gt 0) { 'ERROR' } elseif ($backlog.Count -gt 0) { 'BACKLOG' } else { 'OK' }
        Write-JsonAtomic -Path (Join-Path $root 'heartbeat.json') -Value ([ordered]@{
            TimeUtc=[datetime]::UtcNow.ToString('o');Status=$status
            Errors=@($issues.ToArray());BacklogDomainControllers=@($backlog.ToArray());Retention=$cleanup
        })
        if ($issues.Count) { throw ($issues -join '; ') }
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
Export-ModuleMember -Function Invoke-LockoutMonitor
