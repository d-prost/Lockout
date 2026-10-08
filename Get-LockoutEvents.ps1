#requires -Version 5.1
<#
.SYNOPSIS
    Zeigt die letzten Account-Lockout-Ereignisse DC-uebergreifend an.
.DESCRIPTION
    Liest vorhandene JSONL-Journale ohne neue Dateien oder Zustandsaenderungen.
    Die Ausgabe ist eine Anzeige, keine zweite persistente Protokolldatei.
.EXAMPLE
    .\Get-LockoutEvents.ps1 -Last 30
.EXAMPLE
    .\Get-LockoutEvents.ps1 -Account 'EXAMPLE\alice' -Last 20
#>
[CmdletBinding()]
param(
    [string]$DataDirectory = (Join-Path $env:ProgramData 'LockoutMonitor'),
    [ValidateRange(1,1000)][int]$Last = 50,
    [string]$Account = '',
    [datetime]$Since
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\Lockout.Storage.psm1') -Force

$journal = Join-Path $DataDirectory 'journal'
if (-not [IO.Directory]::Exists($journal)) { return }

# Das Journal wird ausschliesslich gelesen. Filtern und Formatierung erfolgen bei Bedarf.
$collected = New-Object 'System.Collections.Generic.List[object]'
foreach ($file in @(Get-ChildItem -LiteralPath $journal -Filter '*.jsonl' -File -Recurse)) {
    foreach ($record in @(Read-JournalSegment -Path $file.FullName)) {
        if ($Account) {
            $actual = [string]$record.Account
            $wanted = [string]$Account
            $candidate = if ($wanted.Contains('\')) { $actual } else { ($actual -split '\\')[-1] }
            if (-not [string]::Equals($candidate,$wanted,[StringComparison]::OrdinalIgnoreCase)) { continue }
        }
        if ($PSBoundParameters.ContainsKey('Since')) {
            $timestamp = [datetime]::Parse([string]$record.TimeUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
            if ($timestamp.ToUniversalTime() -lt $Since.ToUniversalTime()) { continue }
        }
        [void]$collected.Add([pscustomobject]@{
            TimeUtc = [string]$record.TimeUtc
            Account = [string]$record.Account
            CallerComputer = [string]$record.CallerComputer
            DomainController = [string]$record.DomainController
            RecordId = [long]$record.RecordId
            RootCause = 'Undetermined'
        })
    }
}
$collected.ToArray() |
    Sort-Object -Property TimeUtc,DomainController,RecordId -Descending |
    Select-Object -First $Last
