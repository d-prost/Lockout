#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Account,
    [string[]]$DomainControllers,
    [int]$Minutes = 15,
    [int]$MaxEventsPerDc = 500
)
$ErrorActionPreference = 'Stop'
if ($Minutes -lt 1 -or $Minutes -gt 1440) { throw 'Minutes must be between 1 and 1440.' }
if ($MaxEventsPerDc -lt 1 -or $MaxEventsPerDc -gt 5000) { throw 'Invalid MaxEventsPerDc.' }
if (-not $DomainControllers -or $DomainControllers.Count -eq 0) { throw 'Specify at least one DC explicitly.' }
Import-Module (Join-Path $PSScriptRoot 'src\Lockout.Core.psm1') -Force
$start = (Get-Date).AddMinutes(-$Minutes)
$matches = @()
foreach ($dc in $DomainControllers) {
    foreach ($id in @(4740,4625,4771,4776)) {
        try {
            $events = @(Get-WinEvent -ComputerName $dc -FilterHashtable @{ LogName='Security'; Id=$id; StartTime=$start } -MaxEvents $MaxEventsPerDc -ErrorAction Stop)
        } catch {
            if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { continue }
            Write-Warning ("Could not read {0} from {1}: {2}" -f $id,$dc,$_.Exception.Message)
            continue
        }
        foreach ($event in $events) {
            $f = Get-Fields $event
            $user = switch ($id) {
                4740 { [string]$f['TargetUserName'] }
                4625 { [string]$f['TargetUserName'] }
                4771 { [string]$f['TargetUserName'] }
                4776 { [string]$f['TargetUserName'] }
            }
            $short = ($Account -split '\\')[-1]
            if (-not [string]::Equals($short,$user,[StringComparison]::OrdinalIgnoreCase)) { continue }
            $ip = $null; $hostName = $null; $role = 'UnverifiedObservation'
            switch ($id) {
                4740 { $hostName = [string]$f['CallerComputerName']; $role = 'LockoutCallerField' }
                4625 { $ip = [string]$f['IpAddress']; $hostName = [string]$f['WorkstationName']; $role = 'FailedLogonObservation' }
                4771 { $ip = [string]$f['IpAddress']; $role = 'KerberosClientAddress' }
                4776 { $hostName = [string]$f['Workstation']; $role = 'NtlmSourceWorkstation' }
            }
            $matches += [pscustomobject]@{
                EventId = $id
                DomainController = $dc
                EventTimeUtc = $event.TimeCreated.ToUniversalTime().ToString('o')
                Account = $user
                HostField = $hostName
                IpField = $ip
                EvidenceType = $role
                RecordId = [long]$event.RecordId
                RootCause = 'Undetermined'
            }
        }
    }
}
$matches | Sort-Object EventTimeUtc,DomainController,RecordId
