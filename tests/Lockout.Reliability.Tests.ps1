#requires -Version 5.1
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\Lockout.Core.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '..\src\Lockout.Runner.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '..\src\Lockout.Storage.psm1') -Force

    function New-TestEvent {
        param([long]$RecordId, [string]$DomainController='dc01.example.test', [string]$Account='testuser')
        $xml = '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event"><EventData>' +
            '<Data Name="TargetDomainName">EXAMPLE</Data><Data Name="TargetUserName">' + $Account + '</Data>' +
            '<Data Name="TargetSid">S-1-5-21-123</Data><Data Name="CallerComputerName">WS-TEST</Data>' +
            '</EventData></Event>'
        $record = [pscustomobject]@{
            RecordId = $RecordId; MachineName = $DomainController
            TimeCreated = [datetime]::UtcNow.AddMinutes(-1); XmlText = $xml
        }
        $record | Add-Member -MemberType ScriptMethod -Name ToXml -Value { return $this.XmlText }
        return $record
    }

    function New-TestRecord {
        param([long]$RecordId,[string]$DomainController,[bool]$AlertEligible=$false)
        return [pscustomobject][ordered]@{
            Key='test';DomainController=$DomainController;RecordId=$RecordId;EventId=4740
            TimeUtc=[datetime]::UtcNow.ToString('o');Account='EXAMPLE\testuser'
            CallerComputer='WS-TEST';AlertEligible=$AlertEligible;RootCause='Undetermined'
        }
    }

    function Get-TestRows {
        param([string]$Root, [string]$DomainController)
        $key = Get-SourceKey -Name $DomainController
        $all = New-Object 'System.Collections.Generic.List[object]'
        foreach ($segment in @(Get-JournalSegments -DataDirectory $Root -SourceKey $key)) {
            foreach ($record in @(Read-JournalSegment -Path $segment.FullName)) { [void]$all.Add($record) }
        }
        return @($all.ToArray())
    }

    function Get-TestCursor {
        param([string]$Root, [string]$DomainController)
        $key = Get-SourceKey -Name $DomainController
        return (Read-Json -Path (Join-Path (Join-Path $Root 'state') ($key + '.json')) -Default $null)
    }
}

Describe 'Restart and source failures' {
    BeforeEach {
        $script:dcA = 'dc01.example.test'
        $script:dcB = 'dc02.example.test'
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $global:LockoutFixture = @{
            Events = @{}; Latest = @{}; Oldest = @{}
            Failed = ''; FailedQuery = ''; MailFailed = $false; MailSent = 0
            CrashOnState = $false
        }
        foreach ($dc in @($script:dcA,$script:dcB)) {
            $global:LockoutFixture.Events[$dc] = @()
            $global:LockoutFixture.Latest[$dc] = [long]1
            $global:LockoutFixture.Oldest[$dc] = [long]1
        }
        $script:config = @{
            DataDirectory = $script:root; DomainControllers = @($script:dcA)
            InitialLookbackMinutes = 15; RetentionDays = 30
            RecordWindowSize = 100; MaxWindowsPerRun = 10; BatchRecords = 2
            Mail = @{
                Enabled = $false; From='monitor@example.test'; To=@('admin@example.test')
                Server='localhost'; Port=25; StartTls=$false; CredentialFile=''
                CooldownMinutes=0
            }
        }
        Mock -ModuleName Lockout.Runner -CommandName Get-EventBounds {
            if ($global:LockoutFixture.Failed -eq $DomainController) { throw 'Simulated network failure on bounds' }
            return [pscustomobject]@{
                Oldest = [long]$global:LockoutFixture.Oldest[$DomainController]
                Latest = [long]$global:LockoutFixture.Latest[$DomainController]
            }
        }
        Mock -ModuleName Lockout.Runner -CommandName Get-LockoutWindow {
            if ($global:LockoutFixture.FailedQuery -eq $DomainController) { throw 'Simulated RPC loss mid-query' }
            return @($global:LockoutFixture.Events[$DomainController] | Where-Object {
                [long]$_.RecordId -gt [long]$AfterId -and [long]$_.RecordId -le [long]$UntilId
            })
        }
    }

    AfterEach { Remove-Variable -Name LockoutFixture -Scope Global -ErrorAction SilentlyContinue }

    It 'does not advance checkpoint on an RPC failure during event query and catches up after reconnect' {
        $global:LockoutFixture.Events[$script:dcA] = @(New-TestEvent 1 $script:dcA)
        Invoke-LockoutMonitor -Config $script:config
        $global:LockoutFixture.Events[$script:dcA] += @(New-TestEvent 2 $script:dcA)
        $global:LockoutFixture.Latest[$script:dcA] = [long]2
        $global:LockoutFixture.FailedQuery = $script:dcA
        { Invoke-LockoutMonitor -Config $script:config } | Should -Throw '*Simulated RPC loss mid-query*'
        (Get-TestCursor $script:root $script:dcA).Cursor | Should -Be 1
        $global:LockoutFixture.FailedQuery = ''
        Invoke-LockoutMonitor -Config $script:config
        (Get-TestCursor $script:root $script:dcA).Cursor | Should -Be 2
        @(Get-TestRows $script:root $script:dcA).Count | Should -Be 2
    }

    It 'collects two real-shaped 4740 events arriving newest-first in a single batch' {
        # Eine RPC-Abfrage enthaelt mehrere RecordIds (wie im echten DC-Labor).
        $global:LockoutFixture.Events[$script:dcA] = @(
            (New-TestEvent 3753 $script:dcA 'labuser'),
            (New-TestEvent 3523 $script:dcA 'labuser')
        )
        $global:LockoutFixture.Latest[$script:dcA] = [long]3753
        $global:LockoutFixture.Oldest[$script:dcA] = [long]3523
        $script:config.BatchRecords = 2
        $script:config.RecordWindowSize = 1000
        Invoke-LockoutMonitor -Config $script:config
        $rows = @(Get-TestRows $script:root $script:dcA)
        $rows.Count | Should -Be 2
        [long]$rows[0].RecordId | Should -Be 3523
        [long]$rows[1].RecordId | Should -Be 3753
        (Get-TestCursor $script:root $script:dcA).Cursor | Should -Be 3753
        $sourceKey = Get-SourceKey -Name $script:dcA
        @(Get-JournalSegments -DataDirectory $script:root -SourceKey $sourceKey).Count | Should -Be 1
        (Read-Json -Path (Join-Path $script:root 'heartbeat.json') -Default $null).Status | Should -Be 'OK'
        Invoke-LockoutMonitor -Config $script:config
        @(Get-TestRows $script:root $script:dcA).Count | Should -Be 2
        (Get-TestCursor $script:root $script:dcA).Cursor | Should -Be 3753
    }

    It 'restarts from persisted cursor without duplicating events' {
        $global:LockoutFixture.Events[$script:dcA] = @(New-TestEvent 1 $script:dcA)
        Invoke-LockoutMonitor -Config $script:config
        $global:LockoutFixture.Events[$script:dcA] += @(New-TestEvent 2 $script:dcA)
        $global:LockoutFixture.Latest[$script:dcA] = [long]2
        Invoke-LockoutMonitor -Config $script:config
        Invoke-LockoutMonitor -Config $script:config
        @(Get-TestRows $script:root $script:dcA).Count | Should -Be 2
        (Get-TestCursor $script:root $script:dcA).Cursor | Should -Be 2
    }

    It 'deduplicates repeated RecordId in one successful query' {
        $one = New-TestEvent 1 $script:dcA
        $global:LockoutFixture.Events[$script:dcA] = @($one,$one)
        Invoke-LockoutMonitor -Config $script:config
        @(Get-TestRows $script:root $script:dcA).Count | Should -Be 1
    }

    It 'does not advance a failed DC while progressing a healthy one' {
        $script:config.DomainControllers = @($script:dcA,$script:dcB)
        $global:LockoutFixture.Events[$script:dcA] = @(New-TestEvent 1 $script:dcA)
        $global:LockoutFixture.Events[$script:dcB] = @(New-TestEvent 1 $script:dcB)
        Invoke-LockoutMonitor -Config $script:config
        $global:LockoutFixture.Events[$script:dcA] += @(New-TestEvent 2 $script:dcA)
        $global:LockoutFixture.Events[$script:dcB] += @(New-TestEvent 2 $script:dcB)
        $global:LockoutFixture.Latest[$script:dcA] = [long]2
        $global:LockoutFixture.Latest[$script:dcB] = [long]2
        $global:LockoutFixture.Failed = $script:dcA
        { Invoke-LockoutMonitor -Config $script:config } | Should -Throw '*Simulated network failure*'
        (Get-TestCursor $script:root $script:dcA).Cursor | Should -Be 1
        (Get-TestCursor $script:root $script:dcB).Cursor | Should -Be 2
        $global:LockoutFixture.Failed = ''
        Invoke-LockoutMonitor -Config $script:config
        @(Get-TestRows $script:root $script:dcA).Count | Should -Be 2
        @(Get-TestRows $script:root $script:dcB).Count | Should -Be 2
    }

    It 'recovers cursor from already committed journal after checkpoint loss' {
        $global:LockoutFixture.Events[$script:dcA] = @(New-TestEvent 1 $script:dcA)
        Invoke-LockoutMonitor -Config $script:config
        $global:LockoutFixture.Events[$script:dcA] += @(New-TestEvent 2 $script:dcA)
        $global:LockoutFixture.Latest[$script:dcA] = [long]2
        Invoke-LockoutMonitor -Config $script:config
        $key = Get-SourceKey $script:dcA
        $path = Join-Path (Join-Path $script:root 'state') ($key + '.json')
        $old = Get-TestCursor $script:root $script:dcA
        $old.Cursor = [long]1
        Write-JsonAtomic -Path $path -Value $old
        Invoke-LockoutMonitor -Config $script:config
        (Get-TestCursor $script:root $script:dcA).Cursor | Should -Be 2
        @(Get-TestRows $script:root $script:dcA).Count | Should -Be 2
    }

    It 'recovers after crash between segment commit and checkpoint write' {
        $global:LockoutFixture.Events[$script:dcA] = @(New-TestEvent 1 $script:dcA)
        Invoke-LockoutMonitor -Config $script:config
        $global:LockoutFixture.Events[$script:dcA] += @(New-TestEvent 2 $script:dcA)
        $global:LockoutFixture.Latest[$script:dcA] = [long]2
        $global:LockoutFixture.CrashOnState = $true
        Mock -ModuleName Lockout.Runner -CommandName Save-DcState {
            if ($global:LockoutFixture.CrashOnState) {
                $global:LockoutFixture.CrashOnState = $false
                throw 'Simulated process failure after journal commit'
            }
            Write-JsonAtomic -Path $Path -Value $Value
        }
        { Invoke-LockoutMonitor -Config $script:config } | Should -Throw '*Simulated process failure*'
        (Get-TestCursor $script:root $script:dcA).Cursor | Should -Be 1
        Invoke-LockoutMonitor -Config $script:config
        @(Get-TestRows $script:root $script:dcA).Count | Should -Be 2
        (Get-TestCursor $script:root $script:dcA).Cursor | Should -Be 2
    }

    It 'retries failed SMTP and never silently acknowledges a failed send' {
        $script:config.Mail.Enabled = $true
        $global:LockoutFixture.Events[$script:dcA] = @(New-TestEvent 1 $script:dcA)
        $global:LockoutFixture.MailFailed = $true
        Mock -ModuleName Lockout.Runner -CommandName Send-Alert {
            if ($global:LockoutFixture.MailFailed) { throw 'Simulated SMTP failure' }
            $global:LockoutFixture.MailSent++
        }
        { Invoke-LockoutMonitor -Config $script:config } | Should -Throw '*SMTP*'
        $global:LockoutFixture.MailFailed = $false
        Invoke-LockoutMonitor -Config $script:config
        Invoke-LockoutMonitor -Config $script:config
        $global:LockoutFixture.MailSent | Should -Be 1
    }

    It 'does not coalesce equal account names from different SIDs into one cooldown' {
        $script:config.DomainControllers = @($script:dcA,$script:dcB)
        $script:config.Mail.Enabled = $true
        $script:config.Mail.CooldownMinutes = 15
        $one = New-TestEvent 1 $script:dcA
        $two = New-TestEvent 1 $script:dcB
        $two.XmlText = $two.XmlText.Replace('S-1-5-21-123','S-1-5-21-999')
        $global:LockoutFixture.Events[$script:dcA] = @($one)
        $global:LockoutFixture.Events[$script:dcB] = @($two)
        Mock -ModuleName Lockout.Runner -CommandName Send-Alert {
            $global:LockoutFixture.MailSent++
        }
        Invoke-LockoutMonitor -Config $script:config
        $global:LockoutFixture.MailSent | Should -Be 2
    }

    It 'prevents concurrent writers from another session through exclusive file lock' {
        [void][IO.Directory]::CreateDirectory($script:root)
        $lockPath = Join-Path $script:root 'writer.lock'
        $handle = [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try {
            { Invoke-LockoutMonitor -Config $script:config } | Should -Throw '*writer lock*'
        } finally { $handle.Dispose() }
        $global:LockoutFixture.Events[$script:dcA] = @(New-TestEvent 1 $script:dcA)
        Invoke-LockoutMonitor -Config $script:config
        @(Get-TestRows $script:root $script:dcA).Count | Should -Be 1
    }

    It 'reconstructs a missing text log from canonical JSONL' {
        $global:LockoutFixture.Events[$script:dcA] = @(New-TestEvent 1 $script:dcA)
        Invoke-LockoutMonitor -Config $script:config
        $src = Get-SourceKey $script:dcA
        $log = @(Get-ChildItem -LiteralPath (Join-Path (Join-Path $script:root 'logs') $src) -Filter '*.log' -Recurse -File)[0]
        Remove-Item -LiteralPath $log.FullName -Force
        Invoke-LockoutMonitor -Config $script:config
        (Test-Path -LiteralPath $log.FullName) | Should -BeTrue
    }

    It 'refuses rollback of the source Security record number' {
        $global:LockoutFixture.Latest[$script:dcA] = [long]2
        $global:LockoutFixture.Events[$script:dcA] = @(New-TestEvent 2 $script:dcA)
        Invoke-LockoutMonitor -Config $script:config
        $global:LockoutFixture.Latest[$script:dcA] = [long]1
        { Invoke-LockoutMonitor -Config $script:config } | Should -Throw '*reset*'
        (Get-TestCursor $script:root $script:dcA).Cursor | Should -Be 2
    }

    It 'fails closed on a Security log retention gap' {
        $global:LockoutFixture.Events[$script:dcA] = @(New-TestEvent 1 $script:dcA)
        Invoke-LockoutMonitor -Config $script:config
        $global:LockoutFixture.Latest[$script:dcA] = [long]200
        $global:LockoutFixture.Oldest[$script:dcA] = [long]100
        { Invoke-LockoutMonitor -Config $script:config } | Should -Throw '*retention gap*'
        (Get-TestCursor $script:root $script:dcA).Cursor | Should -Be 1
    }
}

Describe 'Journal retention protects pending alerts' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:dc = 'dc01.example.test'
    }
    It 'deletes old non-alert journal and text projection' {
        $record = New-TestRecord -RecordId 7 -DomainController $script:dc
        $path = Write-JournalSegment -DataDirectory $script:root -DomainController $script:dc -Records @($record) -CollectedUtc ([datetime]::UtcNow.AddDays(-60))
        (Invoke-JournalRetention -DataDirectory $script:root -RetentionDays 30).Removed | Should -Be 1
        (Test-Path -LiteralPath $path) | Should -BeFalse
    }
    It 'keeps old events while SMTP acknowledgement is missing' {
        $record = New-TestRecord -RecordId 7 -DomainController $script:dc -AlertEligible $true
        $path = Write-JournalSegment -DataDirectory $script:root -DomainController $script:dc -Records @($record) -CollectedUtc ([datetime]::UtcNow.AddDays(-60))
        $r = Invoke-JournalRetention -DataDirectory $script:root -RetentionDays 30
        $r.Blocked | Should -Be 1
        (Test-Path -LiteralPath $path) | Should -BeTrue
        $state = Join-Path (Join-Path (Join-Path $script:root 'outbox') (Get-SourceKey $script:dc)) ([IO.Path]::GetFileNameWithoutExtension($path) + '.json')
        Write-JsonAtomic -Path $state -Value @{Offset=1}
        (Invoke-JournalRetention -DataDirectory $script:root -RetentionDays 30).Removed | Should -Be 1
    }
}
