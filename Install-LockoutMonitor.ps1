#requires -Version 5.1
<#
.SYNOPSIS
    Installiert den Monitor wiederholbar; ohne -Apply nur Vorschau.
.DESCRIPTION
    Releases bleiben unveraenderlich. Private Konfiguration und Laufzeitdaten
    werden nie ueberschrieben. Eine vorhandene abweichende Aufgabe erfordert
    -UpdateTask und wird vorher als XML gesichert.
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:ProgramFiles 'LockoutMonitor'),
    [string]$DataDirectory = (Join-Path $env:ProgramData 'LockoutMonitor'),
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9 _.-]{1,100}$')][string]$TaskName = 'AD-LockoutMonitor',
    [ValidateSet(1,2,5,10,15,30,60)][int]$IntervalMinutes = 5,
    [string]$RunAs = '',
    [pscredential]$Credential,
    [switch]$Apply,
    [switch]$UpdateTask
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\Lockout.Deployment.psm1') -Force
if (-not [IO.Path]::IsPathRooted($InstallRoot) -or -not [IO.Path]::IsPathRooted($DataDirectory) -or
    $InstallRoot.StartsWith('\\') -or $DataDirectory.StartsWith('\\')) {
    throw 'InstallRoot and DataDirectory must be absolute local paths.'
}
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$DataDirectory = [IO.Path]::GetFullPath($DataDirectory).TrimEnd('\')
if ($InstallRoot -ieq $DataDirectory -or
    $InstallRoot.StartsWith(($DataDirectory + '\'),[StringComparison]::OrdinalIgnoreCase) -or
    $DataDirectory.StartsWith(($InstallRoot + '\'),[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Installation and data directories must be separate.'
}
$fingerprint = Get-ReleaseFingerprint -SourceRoot $PSScriptRoot
$release = Join-Path (Join-Path $InstallRoot 'releases') $fingerprint
$configPath = Join-Path $DataDirectory 'config.psd1'
$executable = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
[pscustomobject]@{
    Mode = $(if ($Apply) {'Apply'} else {'Preview'})
    CodeRelease = $release
    Configuration = $configPath
    Task = $TaskName
    RunAs = $RunAs
    IntervalMinutes = $IntervalMinutes
}
if (-not $Apply) {
    Write-Host 'PREVIEW only. Specify -Apply and -RunAs to install.'
    return
}
if (-not $RunAs) { throw '-RunAs required for -Apply.' }
# Program Files ist standardmaessig gegen Veraenderung durch normale Benutzer geschuetzt.
$programFiles = [IO.Path]::GetFullPath([string]$env:ProgramFiles).TrimEnd('\')
if (-not $InstallRoot.StartsWith(($programFiles + '\'),[StringComparison]::OrdinalIgnoreCase)) {
    throw 'For -Apply, InstallRoot must be under Program Files to protect scheduled code from user modification.'
}
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Installer requires elevated Windows PowerShell 5.1.'
}
$accountSid = ([Security.Principal.NTAccount]::new($RunAs)).Translate([Security.Principal.SecurityIdentifier])

$files = @(
    'LockoutMonitor.ps1','Investigate-Lockout.ps1',
    'src\Lockout.Core.psm1','src\Lockout.Runner.psm1','src\Lockout.Storage.psm1'
)
[void][IO.Directory]::CreateDirectory((Join-Path $InstallRoot 'releases'))
if ([IO.Directory]::Exists($release)) {
    foreach ($name in $files) {
        $srcHash = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash
        $target = Join-Path $release $name
        if (-not [IO.File]::Exists($target) -or
            (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne $srcHash) {
            throw "Existing release was modified; refusing overwrite: $target"
        }
    }
} else {
    $staging = Join-Path (Join-Path $InstallRoot 'releases') ('.staging-' + [guid]::NewGuid().ToString('N'))
    try {
        [void][IO.Directory]::CreateDirectory($staging)
        foreach ($name in $files) {
            $dest = Join-Path $staging $name
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $dest))
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $dest -ErrorAction Stop
        }
        [IO.Directory]::Move($staging,$release)
    } finally {
        if ([IO.Directory]::Exists($staging)) { [IO.Directory]::Delete($staging,$true) }
    }
}

$newDirectory = -not [IO.Directory]::Exists($DataDirectory)
[void][IO.Directory]::CreateDirectory($DataDirectory)
if ($newDirectory) {
    # Neue Datenablage nur fuer Administratoren, SYSTEM und Task-Identitaet.
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    $inherit = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    foreach ($sidText in @('S-1-5-18','S-1-5-32-544')) {
        $sid = [Security.Principal.SecurityIdentifier]::new($sidText)
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            $sid,[Security.AccessControl.FileSystemRights]::FullControl,$inherit,
            [Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
        [void]$acl.AddAccessRule($rule)
    }
    $rule = [Security.AccessControl.FileSystemAccessRule]::new(
        $accountSid,[Security.AccessControl.FileSystemRights]::Modify,$inherit,
        [Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
    [void]$acl.AddAccessRule($rule)
    [IO.Directory]::SetAccessControl($DataDirectory,$acl)
} else {
    Write-Warning 'Existing data directory ACLs are preserved: verify they meet least-privilege requirements.'
}

if (-not [IO.File]::Exists($configPath)) {
    $template = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config\config.example.psd1') -Raw -Encoding UTF8
    $template = $template.Replace('C:\ProgramData\LockoutMonitor', $DataDirectory.Replace("'","''"))
    [IO.File]::WriteAllText($configPath,$template,(New-Object Text.UTF8Encoding($false)))
    Write-Warning 'Configuration created. Replace the example DCs before continuing.'
}
$config = Import-PowerShellDataFile -LiteralPath $configPath
if (@($config.DomainControllers) -match '\.example\.(com|org|test)$') {
    throw 'Example Domain Controllers remain in config.psd1. Edit the file and run the installer again.'
}
if ([IO.Path]::GetFullPath([string]$config.DataDirectory).TrimEnd('\') -ine $DataDirectory) {
    throw 'DataDirectory in config does not match installation arguments.'
}

$taskXml = New-LockoutTaskXml -RunAs $RunAs -Executable $executable -ScriptPath (Join-Path $release 'LockoutMonitor.ps1') -ConfigurationPath $configPath -IntervalMinutes $IntervalMinutes
Import-Module ScheduledTasks -ErrorAction Stop
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($null -ne $existing) {
    $existingXml = Export-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    if (Test-LockoutTaskDefinition -ExistingXml $existingXml -DesiredXml $taskXml) {
        Write-Host 'UNCHANGED: release and Scheduled Task already match.'
        return
    }
    if (-not $UpdateTask) {
        throw 'Existing Scheduled Task differs. Use -UpdateTask for reviewed replacement and XML backup.'
    }
    $backupDirectory = Join-Path $DataDirectory 'task-backups'
    [void][IO.Directory]::CreateDirectory($backupDirectory)
    $backupPath = Join-Path $backupDirectory ($TaskName + '-' + [datetime]::UtcNow.ToString('yyyyMMddTHHmmssfffffff') + '.xml')
    [IO.File]::WriteAllText($backupPath,$existingXml,(New-Object Text.UTF8Encoding($false)))
    Write-Host "Existing task definition backed up: $backupPath"
}

if (-not $Credential) {
    $Credential = Get-Credential -UserName $RunAs -Message 'Scheduled Task identity; password never saved to repository'
}
if ($Credential.UserName -ine $RunAs) { throw 'Provided credential identity does not match -RunAs.' }
$password = $Credential.GetNetworkCredential().Password
try {
    if ($null -eq $existing) {
        Register-ScheduledTask -TaskName $TaskName -Xml $taskXml -User $RunAs -Password $password -ErrorAction Stop | Out-Null
    } else {
        Register-ScheduledTask -TaskName $TaskName -Xml $taskXml -User $RunAs -Password $password -Force -ErrorAction Stop | Out-Null
    }
} finally { $password = $null }
Write-Host "INSTALLED: $TaskName -> $release"
Write-Host 'No changes to Active Directory accounts or audit policies.'
