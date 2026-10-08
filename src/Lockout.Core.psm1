#requires -Version 5.1
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Lockout.Storage.psm1') -Force

function Get-Fields {
    param($Event)
    [xml]$xml = $Event.ToXml()
    $fields = @{}
    foreach ($node in @($xml.Event.EventData.Data)) {
        if ($null -ne $node -and $node.Name) { $fields[[string]$node.Name] = [string]$node.'#text' }
    }
    return $fields
}

function ConvertTo-Record {
    param($Event,[string]$DomainController,[bool]$AlertEligible=$false)
    $data = Get-Fields $Event
    $dc = [string]$DomainController
    if (-not $dc) { $dc = [string]$Event.MachineName }
    $rid = [long]$Event.RecordId
    if ($rid -lt 1 -or -not $dc) { throw 'Invalid event identity.' }
    if (-not $data['TargetUserName']) { throw 'Missing target account.' }
    $key = Get-SourceKey ($dc + '|' + $rid)
    return [ordered]@{
        Key = $key; DomainController = $dc; RecordId = $rid; EventId = 4740
        TimeUtc = $Event.TimeCreated.ToUniversalTime().ToString('o')
        Account = (([string]$data['TargetDomainName']) + '\' + ([string]$data['TargetUserName']))
        TargetSid = [string]$data['TargetSid']
        CallerComputer = [string]$data['CallerComputerName']
        CallerEvidence = 'Event4740CallerComputerName'
        SourceIp = $null; RootCause = 'Undetermined'; AlertEligible = $AlertEligible
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
        $client = New-Object -TypeName Net.Mail.SmtpClient -ArgumentList @([string]$Settings.Server,[int]$Settings.Port)
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

Export-ModuleMember -Function Get-Fields,ConvertTo-Record,Send-Alert
