# Pester 5 tests; intentionally no AD connection or SMTP required.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\Lockout.Core.psm1') -Force
    $script:xml = @'
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
<EventData>
<Data Name="TargetUserName">someone</Data>
<Data Name="TargetDomainName">EXAMPLE</Data>
<Data Name="TargetSid">S-1-5-21-1</Data>
<Data Name="CallerComputerName">WS-42</Data>
</EventData></Event>
'@
}
Describe 'Event 4740 parser' {
    It 'extracts named XML fields without relying on array indexes' {
        $e = [pscustomobject]@{
            MachineName = 'DC01.example.org'
            RecordId = [long]42
            TimeCreated = [datetime]'2026-10-08T09:00:00Z'
        }
        $e | Add-Member -MemberType ScriptMethod -Name ToXml -Value { return $script:xml }
        # XML wird durch den synthetischen Wrapper ohne entfernte Systeme geprueft.
        $values = Get-Fields $e
        $values['TargetUserName'] | Should -Be 'someone'
        $values['CallerComputerName'] | Should -Be 'WS-42'
    }
    It 'does not claim caller IP or root cause' {
        $source = @'
<Event><EventData><Data Name="TargetUserName">someone</Data><Data Name="TargetDomainName">EXAMPLE</Data><Data Name="CallerComputerName">WS-42</Data></EventData></Event>
'@
        $e = [pscustomobject]@{MachineName='dc01';RecordId=[long]42;TimeCreated=[datetime]'2026-10-08'}
        $e | Add-Member -MemberType ScriptMethod -Name ToXml -Value { return '<Event><EventData><Data Name="TargetUserName">someone</Data><Data Name="TargetDomainName">EXAMPLE</Data><Data Name="CallerComputerName">WS-42</Data></EventData></Event>' }
        $r = ConvertTo-Record $e
        $r.SourceIp | Should -BeNullOrEmpty
        $r.RootCause | Should -Be 'Undetermined'
        $r.CallerComputer | Should -Be 'WS-42'
    }
    It 'rejects malformed identity rather than silently inventing data' {
        $e = [pscustomobject]@{MachineName='dc01';RecordId=[long]0;TimeCreated=[datetime]'2026-10-08'}
        $e | Add-Member -MemberType ScriptMethod -Name ToXml -Value { return '<Event><EventData><Data Name="TargetUserName">a</Data></EventData></Event>' }
        { ConvertTo-Record $e } | Should -Throw
    }
}
