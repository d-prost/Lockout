#requires -Version 5.1
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\Lockout.Core.psm1') -Force
    function New-4740Fixture {
        param([string]$Payload,[long]$RecordId=42)
        $event = [pscustomobject]@{
            MachineName = 'dc01.lab.invalid'
            RecordId = [long]$RecordId
            TimeCreated = [datetime]'2026-10-08T10:00:00Z'
            Payload = $Payload
        }
        $event | Add-Member -MemberType ScriptMethod -Name ToXml -Value { return $this.Payload }
        return $event
    }
}
Describe 'Native Event 4740 XML and empty fields (Windows PowerShell 5.1)' {
    It 'reads empty Data nodes without a StrictMode exception' {
        $xml = '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><EventData>' +
            '<Data Name="TargetUserName">labuser</Data><Data Name="TargetDomainName"></Data>' +
            '<Data Name="TargetSid">S-1-5-21-1-2-3-1001</Data></EventData></Event>'
        $fields = Get-Fields -Event (New-4740Fixture -Payload $xml)
        $fields['TargetUserName'] | Should -Be 'labuser'
        $fields.ContainsKey('TargetDomainName') | Should -BeTrue
        $fields['TargetDomainName'] | Should -Be ''
    }

    It 'maps TargetDomainName to observed caller for native 4740 XML, not account domain' {
        $xml = '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><EventData>' +
            '<Data Name="TargetUserName">labuser</Data>' +
            '<Data Name="TargetDomainName">WIN11-LAB</Data>' +
            '<Data Name="TargetSid">S-1-5-21-1-2-3-1001</Data>' +
            '<Data Name="SubjectDomainName">LAB</Data>' +
            '<Data Name="SubjectLogonId">0x3e7</Data>' +
            '</EventData></Event>'
        $r = ConvertTo-Record -Event (New-4740Fixture -Payload $xml)
        $r.Account | Should -Be 'labuser'
        $r.Account | Should -Not -Be 'WIN11-LAB\labuser'
        $r.CallerComputer | Should -Be 'WIN11-LAB'
        $r.CallerEvidence | Should -Be 'Event4740TargetDomainName'
        $r.SubjectDomainName | Should -Be 'LAB'
        $r.RawTargetDomainName | Should -Be 'WIN11-LAB'
        $r.TargetSid | Should -Be 'S-1-5-21-1-2-3-1001'
        $r.SourceIp | Should -BeNullOrEmpty
        $r.RootCause | Should -Be 'Undetermined'
    }

    It 'prefers an explicit caller field when a normalized source includes one' {
        $xml = '<Event><EventData>' +
            '<Data Name="TargetUserName">labuser</Data>' +
            '<Data Name="TargetDomainName">LAB</Data>' +
            '<Data Name="CallerComputerName">CLIENT-42</Data>' +
            '</EventData></Event>'
        $r = ConvertTo-Record -Event (New-4740Fixture -Payload $xml)
        $r.CallerComputer | Should -Be 'CLIENT-42'
        $r.CallerEvidence | Should -Be 'Event4740CallerComputerName'
        $r.Account | Should -Be 'labuser'
    }

    It 'does not invent a caller when the native field is empty' {
        $xml = '<Event><EventData><Data Name="TargetUserName">labuser</Data>' +
            '<Data Name="TargetDomainName"/><Data Name="CallerComputerName"/></EventData></Event>'
        $r = ConvertTo-Record -Event (New-4740Fixture -Payload $xml)
        $r.CallerComputer | Should -Be ''
        $r.CallerEvidence | Should -Be 'Event4740NotAvailable'
    }

    It 'raises the meaningful missing-account exception on empty target name' {
        $xml = '<Event><EventData><Data Name="TargetUserName"/><Data Name="TargetDomainName">CLIENT-A</Data></EventData></Event>'
        { ConvertTo-Record -Event (New-4740Fixture -Payload $xml) } | Should -Throw '*Missing target account*'
    }

    It 'returns empty named fields even when other fields are absent' {
        $xml = '<Event><EventData><Data Name="WorkstationName"/><Data Name="IpAddress"></Data></EventData></Event>'
        $fields = Get-Fields -Event (New-4740Fixture -Payload $xml)
        $fields.Count | Should -Be 2
        $fields['WorkstationName'] | Should -Be ''
        $fields['IpAddress'] | Should -Be ''
    }
}
