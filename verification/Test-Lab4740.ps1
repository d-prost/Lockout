#requires -Version 5.1
<#
.SYNOPSIS
    Prueft ein echtes 4740-Ereignis im isolierten AD-Labor, ohne personenbezogene Namen auszugeben.
.DESCRIPTION
    Reiner Lesezugriff. Veraendert weder AD-Konten noch Richtlinien und erzeugt keinen Lockout.
.EXAMPLE
    .\verification\Test-Lab4740.ps1 -DomainController 'LAB-DC.lab.invalid' -ExpectedCaller 'WIN11-LAB'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DomainController,
    [string]$ExpectedCaller = '',
    [ValidateRange(1,168)][int]$LookbackHours = 24,
    [ValidateRange(1,20)][int]$MaxEvents = 5
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\Lockout.Core.psm1') -Force

try {
    $events = @(Get-WinEvent -ComputerName $DomainController -FilterHashtable @{
        LogName='Security'
        Id=4740
        StartTime=(Get-Date).AddHours(-$LookbackHours)
    } -MaxEvents $MaxEvents -ErrorAction Stop)
} catch {
    if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
        Write-Warning 'No Event 4740 found during the selected interval. No field-mapping conclusion is possible.'
        return
    }
    throw
}

foreach ($event in $events) {
    $f = Get-Fields -Event $event
    $record = ConvertTo-Record -Event $event -DomainController $DomainController
    $match = $null
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCaller)) {
        $match = [string]::Equals([string]$record.CallerComputer,$ExpectedCaller,[StringComparison]::OrdinalIgnoreCase)
    }
    # Namen, SIDs und private Domain-Daten absichtlich nicht ausgeben.
    [pscustomobject]@{
        TimeUtc = $event.TimeCreated.ToUniversalTime().ToString('o')
        EventId = 4740
        RecordId = [long]$event.RecordId
        TargetUserNamePresent = -not [string]::IsNullOrWhiteSpace([string]$f['TargetUserName'])
        TargetSidPresent = -not [string]::IsNullOrWhiteSpace([string]$f['TargetSid'])
        TargetDomainNamePresent = -not [string]::IsNullOrWhiteSpace([string]$f['TargetDomainName'])
        ExplicitCallerFieldPresent = -not [string]::IsNullOrWhiteSpace([string]$f['CallerComputerName'])
        SubjectDomainNamePresent = -not [string]::IsNullOrWhiteSpace([string]$f['SubjectDomainName'])
        CallerEvidence = [string]$record.CallerEvidence
        CallerMatchesExpected = $match
        AccountContainsCallerName = (-not [string]::IsNullOrWhiteSpace([string]$record.CallerComputer) -and [string]$record.Account -like ('*' + [string]$record.CallerComputer + '*'))
        SourceIpEstablished = -not [string]::IsNullOrWhiteSpace([string]$record.SourceIp)
        RootCause = [string]$record.RootCause
    }
}
