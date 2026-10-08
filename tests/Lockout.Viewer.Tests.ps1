#requires -Version 5.1
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\Lockout.Storage.psm1') -Force
    $script:viewer = Join-Path $PSScriptRoot '..\Get-LockoutEvents.ps1'
    function New-ViewerRecord {
        param([long]$Id,[string]$Dc,[string]$Utc,[string]$Account)
        return [pscustomobject][ordered]@{
            Key="fixture-$Id";DomainController=$Dc;RecordId=$Id;EventId=4740
            Account=$Account;CallerComputer='WS-SYNTHETIC';RootCause='Undetermined'
            TimeUtc=$Utc;AlertEligible=$false
        }
    }
}
Describe 'Simple read-only cross-DC history viewer' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $a = @(
            (New-ViewerRecord 10 'dc01.example.test' '2026-10-08T09:00:00.0000000Z' 'EXAMPLE\alice'),
            (New-ViewerRecord 20 'dc01.example.test' '2026-10-08T09:02:00.0000000Z' 'EXAMPLE\bob')
        )
        $b = @(
            (New-ViewerRecord 40 'dc02.example.test' '2026-10-08T09:01:00.0000000Z' 'EXAMPLE\alice')
        )
        [void](Write-JournalSegment -DataDirectory $script:root -DomainController 'dc01.example.test' -Records $a)
        [void](Write-JournalSegment -DataDirectory $script:root -DomainController 'dc02.example.test' -Records $b)
    }
    It 'shows the last events from multiple DCs, newest first' {
        $result = @(& $script:viewer -DataDirectory $script:root -Last 2)
        $result.Count | Should -Be 2
        $result[0].Account | Should -Be 'EXAMPLE\bob'
        $result[1].DomainController | Should -Be 'dc02.example.test'
    }
    It 'allows case-insensitive account filtering and does not create state files' {
        $result = @(& $script:viewer -DataDirectory $script:root -Account 'ALICE' -Last 10)
        $result.Count | Should -Be 2
        (Test-Path -LiteralPath (Join-Path $script:root 'state')) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $script:root 'writer.lock')) | Should -BeFalse
    }
    It 'filters by UTC timestamp without deleting old journal segments' {
        $result = @(& $script:viewer -DataDirectory $script:root -Last 50 -Since ([datetime]'2026-10-08T09:01:30Z'))
        $result.Count | Should -Be 1
        $result[0].RecordId | Should -Be 20
        @(Get-ChildItem -LiteralPath (Join-Path $script:root 'journal') -File -Filter '*.jsonl' -Recurse).Count | Should -Be 2
    }
}
