#requires -Version 5.1
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\Lockout.Storage.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '..\src\Lockout.Deployment.psm1') -Force
    function New-QualityRecord {
        param([long]$Id, [string]$Dc='dc01.example.test')
        return [pscustomobject][ordered]@{
            Key = "test-$Id"; DomainController = $Dc; RecordId = $Id; EventId = 4740
            Account = 'EXAMPLE\test'; CallerComputer = 'WS-01'; RootCause = 'Undetermined'
            TimeUtc = [datetime]::UtcNow.ToString('o'); AlertEligible = $false
        }
    }
}
Describe 'Journal recovery rejects untrusted segment metadata' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:dc = 'dc01.example.test'
        $script:key = Get-SourceKey -Name $script:dc
    }
    It 'accepts a valid segment and derives high water mark from verified records' {
        $items = @((New-QualityRecord 10 $script:dc),(New-QualityRecord 12 $script:dc),(New-QualityRecord 14 $script:dc))
        [void](Write-JournalSegment -DataDirectory $script:root -DomainController $script:dc -Records $items)
        (Get-LastJournalRecordId -DataDirectory $script:root -SourceKey $script:key) | Should -Be 14
    }
    It 'rejects a truncated segment instead of adopting the misleading filename cursor' {
        $items = @((New-QualityRecord 10 $script:dc),(New-QualityRecord 14 $script:dc))
        $path = Write-JournalSegment -DataDirectory $script:root -DomainController $script:dc -Records $items
        $lines = @([IO.File]::ReadAllLines($path))
        [IO.File]::WriteAllText($path, $lines[0] + [Environment]::NewLine)
        { Get-LastJournalRecordId -DataDirectory $script:root -SourceKey $script:key } |
            Should -Throw '*Invalid journal segment*'
    }
    It 'rejects a mismatched source identity in the journal payload' {
        $path = Write-JournalSegment -DataDirectory $script:root -DomainController $script:dc -Records @((New-QualityRecord 10 $script:dc))
        $content = [IO.File]::ReadAllText($path)
        [IO.File]::WriteAllText($path, $content.Replace('dc01.example.test','dc02.example.test'))
        { Get-LastJournalRecordId -DataDirectory $script:root -SourceKey $script:key } |
            Should -Throw '*DomainController does not match*'
    }
    It 'rejects malformed JSON rather than silently recovering a cursor' {
        $path = Write-JournalSegment -DataDirectory $script:root -DomainController $script:dc -Records @((New-QualityRecord 10 $script:dc))
        [IO.File]::WriteAllText($path, '{"RecordId":')
        { Get-LastJournalRecordId -DataDirectory $script:root -SourceKey $script:key } |
            Should -Throw '*Invalid journal segment*'
    }
    It 'releases the journal handle after a failed tail validation' {
        $path = Write-JournalSegment -DataDirectory $script:root -DomainController $script:dc -Records @((New-QualityRecord 10 $script:dc))
        [IO.File]::WriteAllText($path,'{"RecordId":')
        { Get-LastJournalRecordId -DataDirectory $script:root -SourceKey $script:key } |
            Should -Throw '*Invalid journal segment*'
        # Unter Windows darf kein StreamReader nach einem Fehler weiter sperren.
        $exclusive = [IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try { $exclusive.CanWrite | Should -BeTrue }
        finally { $exclusive.Dispose() }
        [IO.File]::Delete($path)
        (Test-Path -LiteralPath $path) | Should -BeFalse
    }
    It 'releases the journal handle after a failed record read' {
        $path = Write-JournalSegment -DataDirectory $script:root -DomainController $script:dc -Records @((New-QualityRecord 10 $script:dc))
        [IO.File]::WriteAllText($path,'{"RecordId":')
        { @(Read-JournalSegment -Path $path) } | Should -Throw
        $exclusive = [IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try { $exclusive.CanRead | Should -BeTrue }
        finally { $exclusive.Dispose() }
        [IO.File]::Delete($path)
        (Test-Path -LiteralPath $path) | Should -BeFalse
    }
    It 'rejects overlapping ranges even when they are in different collection dates' {
        $day = [datetime]::UtcNow.AddDays(-2)
        [void](Write-JournalSegment -DataDirectory $script:root -DomainController $script:dc -Records @((New-QualityRecord 10 $script:dc),(New-QualityRecord 12 $script:dc)) -CollectedUtc $day)
        [void](Write-JournalSegment -DataDirectory $script:root -DomainController $script:dc -Records @((New-QualityRecord 12 $script:dc),(New-QualityRecord 14 $script:dc)) -CollectedUtc $day.AddDays(1))
        { Get-LastJournalRecordId -DataDirectory $script:root -SourceKey $script:key } |
            Should -Throw '*Overlapping journal*'
    }
}
Describe 'Task comparisons fail closed on security drift' {
    BeforeAll {
        $script:taskParams = @{
            RunAs='EXAMPLE\svc-lockout'
            Executable='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
            ScriptPath='C:\Program Files\LockoutMonitor\releases\abc\LockoutMonitor.ps1'
            ConfigurationPath='C:\ProgramData\LockoutMonitor\config.psd1'
            IntervalMinutes=5
            StartTime=[datetime]'2026-10-08T12:00:00'
        }
    }
    It 'recognizes identical configuration when only StartBoundary changes' {
        $expected = New-LockoutTaskXml @script:taskParams
        $script:taskParams.StartTime = $script:taskParams.StartTime.AddHours(1)
        (Test-LockoutTaskDefinition -ExistingXml $expected -DesiredXml (New-LockoutTaskXml @script:taskParams)) | Should -BeTrue
    }
    It 'detects escalation of RunLevel' {
        $expected = New-LockoutTaskXml @script:taskParams
        [xml]$changed = $expected
        $changed.Task.Principals.Principal.RunLevel = 'HighestAvailable'
        (Test-LockoutTaskDefinition -ExistingXml $changed.OuterXml -DesiredXml $expected) | Should -BeFalse
    }
    It 'detects changed LogonType' {
        $expected = New-LockoutTaskXml @script:taskParams
        [xml]$changed = $expected
        $changed.Task.Principals.Principal.LogonType = 'S4U'
        (Test-LockoutTaskDefinition -ExistingXml $changed.OuterXml -DesiredXml $expected) | Should -BeFalse
    }
    It 'detects additional malicious action' {
        $expected = New-LockoutTaskXml @script:taskParams
        [xml]$changed = $expected
        $copy = $changed.Task.Actions.Exec.CloneNode($true)
        [void]$changed.Task.Actions.AppendChild($copy)
        (Test-LockoutTaskDefinition -ExistingXml $changed.OuterXml -DesiredXml $expected) | Should -BeFalse
    }
    It 'detects additional trigger and disabled original trigger' {
        $expected = New-LockoutTaskXml @script:taskParams
        [xml]$changed = $expected
        [void]$changed.Task.Triggers.AppendChild($changed.Task.Triggers.TimeTrigger.CloneNode($true))
        (Test-LockoutTaskDefinition -ExistingXml $changed.OuterXml -DesiredXml $expected) | Should -BeFalse
        [xml]$disabled = $expected
        $disabled.Task.Triggers.TimeTrigger.Enabled = 'false'
        (Test-LockoutTaskDefinition -ExistingXml $disabled.OuterXml -DesiredXml $expected) | Should -BeFalse
    }
    It 'detects task disabled or extra repetition duration' {
        $expected = New-LockoutTaskXml @script:taskParams
        [xml]$disabled = $expected
        $disabled.Task.Settings.Enabled = 'false'
        (Test-LockoutTaskDefinition -ExistingXml $disabled.OuterXml -DesiredXml $expected) | Should -BeFalse
        [xml]$changed = $expected
        $namespace = $changed.DocumentElement.NamespaceURI
        $node = $changed.CreateElement('Duration',$namespace)
        $node.InnerText = 'PT30M'
        [void]$changed.Task.Triggers.TimeTrigger.Repetition.AppendChild($node)
        (Test-LockoutTaskDefinition -ExistingXml $changed.OuterXml -DesiredXml $expected) | Should -BeFalse
    }
}
