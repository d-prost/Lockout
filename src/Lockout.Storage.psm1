#requires -Version 5.1
Set-StrictMode -Version Latest

function Get-SourceKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $inputBytes = [Text.Encoding]::UTF8.GetBytes($Name.Trim().ToLowerInvariant())
        return (([BitConverter]::ToString($sha.ComputeHash($inputBytes))).Replace('-','').Substring(0,24).ToLowerInvariant())
    } finally { $sha.Dispose() }
}

function Write-AtomicText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [AllowEmptyString()][string]$Text, [switch]$Immutable)
    $parent = Split-Path -Parent $Path
    [void][IO.Directory]::CreateDirectory($parent)
    $utf8 = New-Object Text.UTF8Encoding($false)
    if ($Immutable -and [IO.File]::Exists($Path)) {
        if ([IO.File]::ReadAllText($Path, $utf8) -cne $Text) { throw "Journal collision or corruption: $Path" }
        return
    }
    $temporary = Join-Path $parent ([guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, $Text, $utf8)
        if ([IO.File]::Exists($Path)) {
            if ($Immutable) {
                if ([IO.File]::ReadAllText($Path, $utf8) -cne $Text) { throw "Journal collision or corruption: $Path" }
            } else {
                [IO.File]::Replace($temporary, $Path, $null)
            }
        } else {
            [IO.File]::Move($temporary, $Path)
        }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Write-JsonAtomic {
    param([string]$Path, $Value)
    Write-AtomicText -Path $Path -Text (ConvertTo-Json -InputObject $Value -Depth 10 -Compress)
}

function Read-Json {
    param([string]$Path, $Default)
    if (-not [IO.File]::Exists($Path)) { return $Default }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
}

function Get-JournalSegments {
    param([string]$DataDirectory, [string]$SourceKey)
    $path = Join-Path (Join-Path $DataDirectory 'journal') $SourceKey
    if (-not [IO.Directory]::Exists($path)) { return }
    Get-ChildItem -LiteralPath $path -Filter '*.jsonl' -File -Recurse | Sort-Object FullName
}

function Get-LastJournalRecordId {
    param([string]$DataDirectory, [string]$SourceKey)
    [long]$last = 0
    foreach ($file in @(Get-JournalSegments -DataDirectory $DataDirectory -SourceKey $SourceKey)) {
        if ($file.BaseName -notmatch '^\d{20}-(\d{20})$') { throw "Unexpected journal segment name: $($file.Name)" }
        $endId = [long]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
        if ($endId -gt $last) { $last = $endId }
    }
    return $last
}

function Get-JournalPaths {
    param([string]$DataDirectory, [string]$SourceKey, [datetime]$CollectedUtc, [long]$FirstId, [long]$LastId)
    if ($FirstId -lt 1 -or $LastId -lt $FirstId) { throw 'Invalid segment range.' }
    $day = $CollectedUtc.ToUniversalTime().ToString('yyyyMMdd')
    $fileName = ('{0:D20}-{1:D20}' -f $FirstId,$LastId)
    return [pscustomobject]@{
        Journal = Join-Path (Join-Path (Join-Path (Join-Path $DataDirectory 'journal') $SourceKey) $day) ($fileName + '.jsonl')
        Text = Join-Path (Join-Path (Join-Path (Join-Path $DataDirectory 'logs') $SourceKey) $day) ($fileName + '.log')
    }
}

function ConvertTo-HumanLine {
    param($Record)
    $account = ([string]$Record.Account) -replace '[\r\n\t]', ' '
    $caller = ([string]$Record.CallerComputer) -replace '[\r\n\t]', ' '
    return ('{0} account={1} caller-observed={2} dc={3} record={4} root-cause=Undetermined' -f $Record.TimeUtc,$account,$caller,$Record.DomainController,$Record.RecordId)
}

function Write-JournalSegment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DataDirectory,
        [Parameter(Mandatory)][string]$DomainController,
        [Parameter(Mandatory)][object[]]$Records,
        [datetime]$CollectedUtc = [datetime]::UtcNow
    )
    if ($Records.Count -eq 0) { throw 'Empty journal segment not allowed.' }
    $ordered = @($Records | Sort-Object -Property RecordId)
    $ids = @{}
    foreach ($record in $ordered) {
        $id = [long]$record.RecordId
        if ($id -lt 1) { throw 'Invalid event RecordId.' }
        if ($ids.ContainsKey([string]$id)) { throw "Duplicate RecordId in segment: $id" }
        $ids[[string]$id] = $true
        if ([string]$record.DomainController -ine $DomainController) { throw 'DC mismatch in journal record.' }
    }
    $source = Get-SourceKey $DomainController
    $paths = Get-JournalPaths -DataDirectory $DataDirectory -SourceKey $source -CollectedUtc $CollectedUtc -FirstId ([long]$ordered[0].RecordId) -LastId ([long]$ordered[-1].RecordId)
    $nl = [Environment]::NewLine
    $json = (@($ordered | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress -Depth 10 }) -join $nl) + $nl
    $human = (@($ordered | ForEach-Object { ConvertTo-HumanLine $_ }) -join $nl) + $nl
    # Das JSONL-Journal wird zuerst dauerhaft geschrieben, danach die reparierbare Textprojektion.
    Write-AtomicText -Path $paths.Journal -Text $json -Immutable
    Write-AtomicText -Path $paths.Text -Text $human -Immutable
    return $paths.Journal
}

function Read-JournalSegment {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    foreach ($line in [IO.File]::ReadLines($Path)) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { ConvertFrom-Json -InputObject $line -ErrorAction Stop }
    }
}

function Repair-JournalTextLogs {
    param([string]$DataDirectory, [string]$SourceKey)
    foreach ($segment in @(Get-JournalSegments $DataDirectory $SourceKey)) {
        $relative = $segment.FullName.Substring((Join-Path $DataDirectory 'journal').Length).TrimStart('\','/')
        $target = Join-Path (Join-Path $DataDirectory 'logs') ([IO.Path]::ChangeExtension($relative, '.log'))
        if ([IO.File]::Exists($target)) { continue }
        $rows = @(Read-JournalSegment -Path $segment.FullName)
        if ($rows.Count -eq 0) { throw "Empty journal: $($segment.FullName)" }
        $text = (@($rows | ForEach-Object { ConvertTo-HumanLine $_ }) -join [Environment]::NewLine) + [Environment]::NewLine
        Write-AtomicText -Path $target -Text $text -Immutable
    }
}

function Invoke-JournalRetention {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DataDirectory, [int]$RetentionDays, [datetime]$NowUtc = [datetime]::UtcNow)
    if ($RetentionDays -lt 1 -or $RetentionDays -gt 3650) { throw 'RetentionDays must be 1..3650.' }
    $result = [ordered]@{ Removed = 0; Blocked = 0; Checked = 0 }
    $base = Join-Path $DataDirectory 'journal'
    if (-not [IO.Directory]::Exists($base)) { return [pscustomobject]$result }
    $cutoff = $NowUtc.ToUniversalTime().Date.AddDays(-$RetentionDays)
    foreach ($sourceDir in @(Get-ChildItem -LiteralPath $base -Directory)) {
        foreach ($dayDir in @(Get-ChildItem -LiteralPath $sourceDir.FullName -Directory)) {
            [datetime]$segmentDate = [datetime]::MinValue
            if (-not [datetime]::TryParseExact($dayDir.Name,'yyyyMMdd',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$segmentDate)) { continue }
            if ($segmentDate -ge $cutoff) { continue }
            foreach ($segment in @(Get-ChildItem -LiteralPath $dayDir.FullName -Filter '*.jsonl' -File)) {
                $result.Checked++
                $mailStateFile = Join-Path (Join-Path (Join-Path $DataDirectory 'outbox') $sourceDir.Name) ($segment.BaseName + '.json')
                $rows = @(Read-JournalSegment $segment.FullName)
                $eligible = @($rows | Where-Object { $_.AlertEligible -eq $true })
                $progress = Read-Json -Path $mailStateFile -Default ([pscustomobject]@{ Offset = 0 })
                if ($eligible.Count -gt 0 -and [int]$progress.Offset -lt $rows.Count) {
                    $result.Blocked++
                    continue
                }
                $textPath = Join-Path (Join-Path (Join-Path (Join-Path $DataDirectory 'logs') $sourceDir.Name) $dayDir.Name) ($segment.BaseName + '.log')
                [IO.File]::Delete($segment.FullName)
                if ([IO.File]::Exists($textPath)) { [IO.File]::Delete($textPath) }
                if ([IO.File]::Exists($mailStateFile)) { [IO.File]::Delete($mailStateFile) }
                $result.Removed++
            }
            if (@(Get-ChildItem -LiteralPath $dayDir.FullName -Force).Count -eq 0) { [IO.Directory]::Delete($dayDir.FullName) }
        }
    }
    return [pscustomobject]$result
}

Export-ModuleMember -Function Get-SourceKey,Write-JsonAtomic,Read-Json,Write-JournalSegment,Read-JournalSegment,Get-JournalSegments,Get-LastJournalRecordId,Repair-JournalTextLogs,Invoke-JournalRetention
