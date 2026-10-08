#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config\config.psd1'),
    [switch]$Once
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\Lockout.Core.psm1') -Force
try {
    $config = Import-PowerShellDataFile -LiteralPath $ConfigPath
    Invoke-LockoutMonitor -Config $config
}
catch {
    [Console]::Error.WriteLine("Lockout monitor failed: $($_.Exception.Message)")
    exit 1
}
