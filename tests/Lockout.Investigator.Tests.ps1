#requires -Version 5.1
BeforeAll {
    $script:investigator = Join-Path $PSScriptRoot '..\Investigate-Lockout.ps1'
    function New-InvestigationFixture {
        param([int]$EventId,[long]$RecordId,[string]$Payload)
        $item = [pscustomobject]@{
            Id = $EventId
            RecordId = [long]$RecordId
            MachineName = 'dc01.lab.invalid'
            TimeCreated = [datetime]'2026-10-08T10:00:00Z'
            XmlText = $Payload
        }
        $item | Add-Member -MemberType ScriptMethod -Name ToXml -Value { return $this.XmlText }
        return $item
    }
}
Describe 'Investigator tolerates malformed entries and uses native 4740 caller evidence' {
    It 'continues after malformed 4740 XML and returns later valid evidence' {
        $script:bad = New-InvestigationFixture -EventId 4740 -RecordId 11 -Payload '<Event><EventData><Data'
        $script:valid = New-InvestigationFixture -EventId 4740 -RecordId 12 -Payload (
            '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><EventData>' +
            '<Data Name="TargetUserName">labuser</Data><Data Name="TargetDomainName">WIN11-LAB</Data>' +
            '<Data Name="TargetSid">S-1-5-21-1-2-3-1001</Data><Data Name="SubjectDomainName">LAB</Data>' +
            '</EventData></Event>'
        )
        $script:krb = New-InvestigationFixture -EventId 4771 -RecordId 13 -Payload (
            '<Event><EventData><Data Name="TargetUserName">labuser</Data>' +
            '<Data Name="IpAddress">192.0.2.17</Data></EventData></Event>'
        )
        Mock -CommandName Get-WinEvent -MockWith {
            if ($FilterHashtable.Id -eq 4740) { return @($script:bad,$script:valid) }
            if ($FilterHashtable.Id -eq 4771) { return @($script:krb) }
            return @()
        }
        $warnings = @()
        $found = @(& $script:investigator -Account 'LAB\labuser' -DomainControllers @('dc01.lab.invalid') -Minutes 15 -WarningVariable warnings)
        $found.Count | Should -Be 2
        $lockout = @($found | Where-Object { $_.EventId -eq 4740 })[0]
        $lockout.HostField | Should -Be 'WIN11-LAB'
        $lockout.EvidenceType | Should -Be 'LockoutCallerField:TargetDomainName'
        $lockout.RootCause | Should -Be 'Undetermined'
        $kerberos = @($found | Where-Object { $_.EventId -eq 4771 })[0]
        $kerberos.IpField | Should -Be '192.0.2.17'
        $warnings.Count | Should -BeGreaterThan 0
    }
}
