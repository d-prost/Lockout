#requires -Version 5.1
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Lockout.Storage.psm1') -Force

function Get-Fields {
    param([Parameter(Mandatory)]$Event)
    [xml]$xml = $Event.ToXml()
    $fields = @{}
    # InnerText ist auch fuer leere EventData-Werte unter StrictMode sicher.
    # XML-Namespace-unabhaengige Auswahl; Feldnamen nicht als Positionen interpretieren.
    foreach ($node in @($xml.SelectNodes('//*[local-name()="EventData"]/*[local-name()="Data"]'))) {
        if ($null -ne $node -and $null -ne $node.Attributes['Name']) {
            $fields[[string]$node.Attributes['Name'].Value] = [string]$node.InnerText
        }
    }
    return $fields
}

function Get-4740CallerEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Fields)
    # Originales Windows-4740-XML: "Caller Computer Name" steckt in TargetDomainName.
    # Manche normalisierten Quellen enthalten zusaetzlich CallerComputerName.
    $explicit = [string]$Fields['CallerComputerName']
    if (-not [string]::IsNullOrWhiteSpace($explicit)) {
        return [pscustomobject]@{ Computer = $explicit; Field = 'CallerComputerName' }
    }
    $native = [string]$Fields['TargetDomainName']
    if (-not [string]::IsNullOrWhiteSpace($native)) {
        return [pscustomobject]@{ Computer = $native; Field = 'TargetDomainName' }
    }
    return [pscustomobject]@{ Computer = ''; Field = 'NotAvailable' }
}

function ConvertTo-Record {
    param($Event,[string]$DomainController,[bool]$AlertEligible=$false)
    $data = Get-Fields $Event
    $dc = [string]$DomainController
    if (-not $dc) { $dc = [string]$Event.MachineName }
    $rid = [long]$Event.RecordId
    if ($rid -lt 1 -or -not $dc) { throw 'Invalid event identity.' }
    if ([string]::IsNullOrWhiteSpace([string]$data['TargetUserName'])) { throw 'Missing target account.' }
    $key = Get-SourceKey ($dc + '|' + $rid)
    $caller = Get-4740CallerEvidence -Fields $data
    return [ordered]@{
        Key = $key; DomainController = $dc; RecordId = $rid; EventId = 4740
        TimeUtc = $Event.TimeCreated.ToUniversalTime().ToString('o')
        # Ein 4740-TargetDomainName ist kein verlaesslicher Kontodomainname.
        # Zur Zuordnung TargetSid verwenden; Kontoname bleibt bewusst unqualifiziert.
        Account = [string]$data['TargetUserName']
        TargetSid = [string]$data['TargetSid']
        CallerComputer = [string]$caller.Computer
        CallerEvidence = ('Event4740' + [string]$caller.Field)
        SubjectDomainName = [string]$data['SubjectDomainName']
        RawTargetDomainName = [string]$data['TargetDomainName']
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

Export-ModuleMember -Function Get-Fields,Get-4740CallerEvidence,ConvertTo-Record,Send-Alert
