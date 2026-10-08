#requires -Version 5.1
Set-StrictMode -Version Latest

function New-LockoutTaskXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunAs,
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$ConfigurationPath,
        [ValidateSet(1,2,5,10,15,30,60)][int]$IntervalMinutes = 5,
        [datetime]$StartTime = (Get-Date).AddMinutes(1)
    )
    # XML-Sonderzeichen und Task-Parameter werden explizit maskiert.
    $escape = { param([string]$InputText) [Security.SecurityElement]::Escape($InputText) }
    $user = & $escape $RunAs
    $exe = & $escape $Executable
    $argsText = ('-NoProfile -NonInteractive -File "{0}" -ConfigPath "{1}"' -f $ScriptPath,$ConfigurationPath)
    $argsXml = & $escape $argsText
    $working = & $escape ([IO.Path]::GetDirectoryName($ScriptPath))
    $boundary = $StartTime.ToString('yyyy-MM-ddTHH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)
    $interval = 'PT' + $IntervalMinutes + 'M'
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Read-only AD Account Lockout Monitor</Description></RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <Repetition><Interval>$interval</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>
      <StartBoundary>$boundary</StartBoundary><Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author"><UserId>$user</UserId><LogonType>Password</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec><Command>$exe</Command><Arguments>$argsXml</Arguments><WorkingDirectory>$working</WorkingDirectory></Exec>
  </Actions>
</Task>
"@
    [xml]$verified = $xml
    if (-not $verified.DocumentElement) { throw 'Invalid task XML generated.' }
    return $xml
}

function Test-LockoutTaskDefinition {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ExistingXml,[Parameter(Mandatory)][string]$DesiredXml)
    [xml]$current = $ExistingXml
    [xml]$desired = $DesiredXml
    $queries = @(
        '//*[local-name()="Exec"]/*[local-name()="Command"]',
        '//*[local-name()="Exec"]/*[local-name()="Arguments"]',
        '//*[local-name()="Exec"]/*[local-name()="WorkingDirectory"]',
        '//*[local-name()="Principal"]/*[local-name()="UserId"]',
        '//*[local-name()="TimeTrigger"]/*[local-name()="Repetition"]/*[local-name()="Interval"]',
        '//*[local-name()="Settings"]/*[local-name()="MultipleInstancesPolicy"]',
        '//*[local-name()="Settings"]/*[local-name()="ExecutionTimeLimit"]'
    )
    foreach ($query in $queries) {
        $left = $current.SelectSingleNode($query)
        $right = $desired.SelectSingleNode($query)
        if ($null -eq $left -or $null -eq $right) { return $false }
        if ($left.InnerText -ine $right.InnerText) { return $false }
    }
    return $true
}

function Get-ReleaseFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourceRoot)
    $files = @(
        'LockoutMonitor.ps1','Investigate-Lockout.ps1',
        'src\Lockout.Core.psm1','src\Lockout.Runner.psm1',
        'src\Lockout.Storage.psm1'
    )
    $parts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($file in $files) {
        $location = Join-Path $SourceRoot $file
        if (-not [IO.File]::Exists($location)) { throw "Missing release source: $file" }
        [void]$parts.Add($file + ':' + (Get-FileHash -LiteralPath $location -Algorithm SHA256).Hash)
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($parts.ToArray() -join '|'))
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').Substring(0,16).ToLowerInvariant()
    } finally { $sha.Dispose() }
}

Export-ModuleMember -Function New-LockoutTaskXml,Test-LockoutTaskDefinition,Get-ReleaseFingerprint
