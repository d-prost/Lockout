#requires -Version 5.1
Set-StrictMode -Version Latest

function Get-Fields {
    param($Event)
    [xml]$xml = $Event.ToXml()
    $fields = @{}
    foreach ($node in @($xml.Event.EventData.Data)) {
        if ($null -ne $node -and $node.Name) { $fields[[string]$node.Name] = [string]$node.'#text' }
    }
    return $fields
}

function Write-JsonAtomic {
    param([string]$Path, $Value)
    $tmp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $utf8 = New-Object Text.UTF8Encoding($false)
    try {
        [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $Value -Depth 10 -Compress), $utf8)
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp,$Path,$null) }
        else { [IO.File]::Move($tmp,$Path) }
    } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }
}

function Read-Json {
    param([string]$Path, $Default)
    if (-not (Test-Path -LiteralPath $Path)) { return $Default }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function ConvertTo-Record {
    param($Event)
    $data = Get-Fields $Event
    $dc = [string]$Event.MachineName
    $rid = [long]$Event.RecordId
    if ($rid -lt 1 -or -not $dc) { throw 'Invalid event identity.' }
    if (-not $data['TargetUserName']) { throw 'Missing target account.' }
    $identity = ($dc.ToLowerInvariant() + '|' + $rid)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $key = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity)))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
    return [ordered]@{
        Key = $key; DomainController = $dc; RecordId = $rid; EventId = 4740
        TimeUtc = $Event.TimeCreated.ToUniversalTime().ToString('o')
        Account = (([string]$data['TargetDomainName']) + '\' + ([string]$data['TargetUserName']))
        TargetSid = [string]$data['TargetSid']
        CallerComputer = [string]$data['CallerComputerName']
        CallerEvidence = 'Event4740CallerComputerName'
        SourceIp = $null; RootCause = 'Undetermined'
    }
}

function Send-Alert {
    param($Record, [hashtable]$Settings)
    $m = New-Object Net.Mail.MailMessage
    $client = $null
    try {
        $m.From = [string]$Settings.From
        foreach ($to in @($Settings.To)) { [void]$m.To.Add([string]$to) }
        $m.Subject = '[AD Lockout] ' + [string]$Record.Account
        $m.IsBodyHtml = $true
        $m.BodyEncoding = [Text.Encoding]::UTF8
        $m.SubjectEncoding = [Text.Encoding]::UTF8
        $a = [Net.WebUtility]::HtmlEncode([string]$Record.Account)
        $c = [Net.WebUtility]::HtmlEncode([string]$Record.CallerComputer)
        $d = [Net.WebUtility]::HtmlEncode([string]$Record.DomainController)
        $m.Body = '<html><body><h3>Account lockout</h3><p>Account: ' + $a + '</p><p>Caller computer (unverified): ' + $c + '</p><p>DC: ' + $d + '</p><p>No verified source IP. Root cause undetermined.</p></body></html>'
        $client = New-Object Net.Mail.SmtpClient([string]$Settings.Server,[int]$Settings.Port)
        $client.UseDefaultCredentials = $false
        $client.EnableSsl = [bool]$Settings.StartTls
        $client.Timeout = 15000
        if ($Settings.CredentialFile) {
            $credential = Import-Clixml -LiteralPath $Settings.CredentialFile
            $client.Credentials = $credential.GetNetworkCredential()
        }
        $client.Send($m)
    } finally {
        $m.Dispose()
        if ($null -ne $client) { $client.Dispose() }
    }
}

function Invoke-LockoutMonitor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)
    foreach ($name in @('DataDirectory','DomainControllers','InitialLookbackMinutes','Mail')) {
        if (-not $Config.ContainsKey($name)) { throw ('Missing config: ' + $name) }
    }
    if ([int]$Config.InitialLookbackMinutes -lt 1) { throw 'Invalid lookback.' }
    $root = [IO.Path]::GetFullPath([string]$Config.DataDirectory)
    if ($root.StartsWith('\\')) { throw 'DataDirectory must be local.' }
    $eventsDir = Join-Path $root 'events'
    foreach ($p in @($root,$eventsDir)) {
        if (-not (Test-Path -LiteralPath $p)) { [void](New-Item -Path $p -ItemType Directory -Force) }
    }
    $mutex = New-Object Threading.Mutex($false,'Local\ADLockoutMonitor')
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(10000) }
        catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw 'Another instance is running.' }
        $statePath = Join-Path $root 'cursor.json'
        $state = Read-Json $statePath ([pscustomobject]@{Version=1;Controllers=[pscustomobject]@{}})
        if ([int]$state.Version -ne 1) { throw 'Unsupported state version.' }
        $positions = @{}
        foreach ($p in $state.Controllers.PSObject.Properties) { $positions[$p.Name] = [long]$p.Value }
        $errors = @()
        foreach ($name in @($Config.DomainControllers)) {
            $dc = [string]$name
            if (-not $dc) { throw 'Empty DC name.' }
            $index = $dc.ToLowerInvariant()
            $after = [long]0
            if ($positions.ContainsKey($index)) { $after = $positions[$index] }
            try {
                $newest = Get-WinEvent -ComputerName $dc -LogName Security -MaxEvents 1 -ErrorAction Stop
                if ($after -gt 0 -and [long]$newest.RecordId -lt $after) { throw 'Security log reset; manual recovery required.' }
                if ($after -gt 0) {
                    $xpath = 'Event[System[(EventID=4740) and (EventRecordID > ' + $after + ')]]'
                } else {
                    $time = [datetime]::UtcNow.AddMinutes(-[int]$Config.InitialLookbackMinutes).ToString('o')
                    $xpath = "Event[System[(EventID=4740) and TimeCreated[@SystemTime >= '$time']]]"
                }
                $items = @()
                try { $items = @(Get-WinEvent -ComputerName $dc -LogName Security -FilterXPath $xpath -ErrorAction Stop) }
                catch {
                    if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw }
                }
                foreach ($item in @($items | Sort-Object RecordId)) {
                    $record = ConvertTo-Record $item
                    $file = Join-Path $eventsDir ($record.Key + '.json')
                    if (-not (Test-Path -LiteralPath $file)) { Write-JsonAtomic $file $record }
                    $after = [Math]::Max($after,[long]$item.RecordId)
                }
                $positions[$index] = $after
                Write-JsonAtomic $statePath ([ordered]@{Version=1;Controllers=$positions})
            } catch { $errors += ($dc + ': ' + $_.Exception.Message) }
        }
        # Jeder Durchlauf rekonstruiert die lesbaren Protokolle aus der unveraenderlichen Ereignisablage.
        $records = @(Get-ChildItem -LiteralPath $eventsDir -Filter '*.json' -File |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } |
            Sort-Object TimeUtc,DomainController,RecordId)
        $utf8 = New-Object Text.UTF8Encoding($false)
        $jsonLines = @($records | ForEach-Object { ConvertTo-Json -InputObject $_ -Depth 10 -Compress })
        $textLines = @($records | ForEach-Object { $_.TimeUtc + ' ' + $_.Account + ' caller=' + $_.CallerComputer + ' dc=' + $_.DomainController })
        foreach ($out in @(@('lockouts.jsonl',$jsonLines),@('lockouts.log',$textLines))) {
            $destination = Join-Path $root $out[0]
            $tmp = Join-Path $root ([IO.Path]::GetRandomFileName())
            try {
                [IO.File]::WriteAllText($tmp,($out[1] -join [Environment]::NewLine),$utf8)
                if (Test-Path -LiteralPath $destination) { [IO.File]::Replace($tmp,$destination,$null) }
                else { [IO.File]::Move($tmp,$destination) }
            } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item $tmp -Force } }
        }
        if ([bool]$Config.Mail.Enabled) {
            $mailPath = Join-Path $root 'mail-state.json'
            $mailState = Read-Json $mailPath ([pscustomobject]@{Sent=[pscustomobject]@{};Last=[pscustomobject]@{}})
            $sent = @{}; $last = @{}
            foreach ($p in $mailState.Sent.PSObject.Properties) { $sent[$p.Name] = $true }
            foreach ($p in $mailState.Last.PSObject.Properties) { $last[$p.Name] = [string]$p.Value }
            foreach ($record in $records) {
                if ($sent.ContainsKey([string]$record.Key)) { continue }
                $account = ([string]$record.Account).ToLowerInvariant()
                $skip = $false
                if ($last.ContainsKey($account)) {
                    $then = [datetime]::Parse($last[$account],[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
                    $skip = (([datetime]::UtcNow-$then.ToUniversalTime()).TotalMinutes -lt [int]$Config.Mail.CooldownMinutes)
                }
                if (-not $skip) {
                    try { Send-Alert $record $Config.Mail }
                    catch { $errors += ('SMTP: ' + $_.Exception.Message); continue }
                    $last[$account] = [datetime]::UtcNow.ToString('o')
                }
                $sent[[string]$record.Key] = $true
                Write-JsonAtomic $mailPath ([ordered]@{Sent=$sent;Last=$last})
            }
        }
        Write-JsonAtomic (Join-Path $root 'heartbeat.json') ([ordered]@{TimeUtc=[datetime]::UtcNow.ToString('o');Errors=$errors})
        if ($errors.Count -gt 0) { throw ($errors -join '; ') }
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
Export-ModuleMember -Function Get-Fields,ConvertTo-Record,Invoke-LockoutMonitor
