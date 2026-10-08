#requires -Version 5.1
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\Lockout.Deployment.psm1') -Force
}
Describe 'Task Scheduler definition' {
    BeforeEach {
        $script:params = @{
            RunAs='EXAMPLE\svc-lockout'
            Executable='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
            ScriptPath='C:\Program Files\LockoutMonitor\releases\abc\LockoutMonitor.ps1'
            ConfigurationPath='C:\ProgramData\LockoutMonitor\config.psd1'
            IntervalMinutes=5
            StartTime=[datetime]'2026-10-08T12:00:00'
        }
    }
    It 'generates a nonexpiring repetition task with no overlap and least privilege' {
        [xml]$task = New-LockoutTaskXml @script:params
        $task.Task.Triggers.TimeTrigger.Repetition.Interval | Should -Be 'PT5M'
        $task.Task.Triggers.TimeTrigger.Repetition.Duration | Should -BeNullOrEmpty
        $task.Task.Settings.MultipleInstancesPolicy | Should -Be 'IgnoreNew'
        $task.Task.Principals.Principal.RunLevel | Should -Be 'LeastPrivilege'
        $task.Task.Principals.Principal.UserId | Should -Be 'EXAMPLE\svc-lockout'
    }
    It 'escapes XML metacharacters in account identity' {
        $script:params.RunAs = 'EXAMPLE\service&ops'
        [xml]$task = New-LockoutTaskXml @script:params
        $task.Task.Principals.Principal.UserId | Should -Be 'EXAMPLE\service&ops'
    }
    It 'considers changed schedule or executable different, but ignores start boundary drift' {
        $baseline = New-LockoutTaskXml @script:params
        $script:params.StartTime = [datetime]'2026-10-08T13:00:00'
        $same = New-LockoutTaskXml @script:params
        (Test-LockoutTaskDefinition -ExistingXml $baseline -DesiredXml $same) | Should -BeTrue
        $script:params.IntervalMinutes = 15
        $changed = New-LockoutTaskXml @script:params
        (Test-LockoutTaskDefinition -ExistingXml $baseline -DesiredXml $changed) | Should -BeFalse
    }
}
Describe 'Installation safety' {
    It 'prints a preview without touching filesystem or Scheduled Tasks' {
        $codeDir = Join-Path $TestDrive 'code'
        $dataDir = Join-Path $TestDrive 'private'
        $installer = Join-Path $PSScriptRoot '..\Install-LockoutMonitor.ps1'
        $output = & $installer -InstallRoot $codeDir -DataDirectory $dataDir -RunAs 'EXAMPLE\svc-lockout'
        (Test-Path -LiteralPath $codeDir) | Should -BeFalse
        (Test-Path -LiteralPath $dataDir) | Should -BeFalse
        $output.Mode | Should -Be 'Preview'
    }
    It 'makes a repeatable release fingerprint from source hashes' {
        $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        $x = Get-ReleaseFingerprint -SourceRoot $root
        $y = Get-ReleaseFingerprint -SourceRoot $root
        $x | Should -Be $y
        $x | Should -Match '^[0-9a-f]{16}$'
    }
}
