#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet(10000,100000)][int]$EventCount = 10000,
    [ValidateRange(50,2000)][int]$BatchRecords = 500,
    [string]$OutputDirectory = '',
    [switch]$KeepData
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\Lockout.Storage.psm1') -Force
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) ('LockoutBench-' + [guid]::NewGuid().ToString('N'))
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if ([IO.Directory]::Exists($OutputDirectory) -and @(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count -gt 0) {
    throw 'Benchmark output directory must be empty; refusing to overwrite existing data.'
}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$dc = 'benchmark-dc.example.test'
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$measured = [ordered]@{ EventCount = $EventCount; BatchRecords = $BatchRecords }
try {
    $buffer = New-Object 'System.Collections.Generic.List[object]'
    $now = [datetime]::UtcNow
    for ($n=1; $n -le $EventCount; $n++) {
        $record = [pscustomobject][ordered]@{
            Key = ('synthetic-{0}' -f $n)
            DomainController = $dc
            ReportedMachine = $dc
            RecordId = [long]$n
            EventId = 4740
            TimeUtc = $now.AddSeconds(-$EventCount + $n).ToString('o')
            Account = 'BENCH\user0001'
            TargetSid = 'S-1-5-21-1-2-3-1000'
            CallerComputer = 'BENCH-WORKSTATION'
            CallerEvidence = 'Event4740CallerComputerName'
            SourceIp = $null
            RootCause = 'Undetermined'
            AlertEligible = $false
        }
        [void]$buffer.Add($record)
        if ($buffer.Count -ge $BatchRecords) {
            [void](Write-JournalSegment -DataDirectory $OutputDirectory -DomainController $dc -Records @($buffer.ToArray()) -CollectedUtc $now)
            $buffer.Clear()
        }
    }
    if ($buffer.Count -gt 0) {
        [void](Write-JournalSegment -DataDirectory $OutputDirectory -DomainController $dc -Records @($buffer.ToArray()) -CollectedUtc $now)
    }
    $stopwatch.Stop()
    $measured.IngestSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds,3)
    $source = Get-SourceKey $dc
    $stopwatch.Restart()
    $highest = Get-LastJournalRecordId -DataDirectory $OutputDirectory -SourceKey $source
    Repair-JournalTextLogs -DataDirectory $OutputDirectory -SourceKey $source
    $stopwatch.Stop()
    if ($highest -ne $EventCount) { throw "Cursor mismatch: $highest vs $EventCount" }
    $measured.EmptyPollMaintenanceSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds,3)

    $segments = @(Get-JournalSegments -DataDirectory $OutputDirectory -SourceKey $source)
    $lineCount = [long]0
    $byteCount = [long]0
    foreach ($segment in $segments) {
        $byteCount += [long]$segment.Length
        foreach ($line in [IO.File]::ReadLines($segment.FullName)) {
            if (-not [string]::IsNullOrWhiteSpace($line)) { $lineCount++ }
        }
    }
    if ($lineCount -ne $EventCount) { throw "Journal record count mismatch: $lineCount" }
    $expectedSegments = [int][math]::Ceiling($EventCount / [double]$BatchRecords)
    if ($segments.Count -ne $expectedSegments) { throw "Segment count mismatch: $($segments.Count) vs $expectedSegments" }
    $measured.Segments = $segments.Count
    $measured.JournalBytes = $byteCount
    $measured.VerifiedRecords = $lineCount

    $stopwatch.Restart()
    $result = Invoke-JournalRetention -DataDirectory $OutputDirectory -RetentionDays 30 -NowUtc ($now.AddDays(45))
    $stopwatch.Stop()
    $measured.RetentionSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds,3)
    $measured.RemovedSegments = $result.Removed
    $remaining = @(Get-JournalSegments -DataDirectory $OutputDirectory -SourceKey $source).Count
    if ($result.Removed -ne $expectedSegments -or $remaining -ne 0 -or $result.Blocked -ne 0) {
        throw "Retention mismatch: removed=$($result.Removed) remaining=$remaining blocked=$($result.Blocked)"
    }
    $measured.Result = 'PASS'
    Write-Output ('BENCH_RESULT ' + (ConvertTo-Json -InputObject $measured -Compress))
} finally {
    if (-not $KeepData -and [IO.Directory]::Exists($OutputDirectory)) {
        [IO.Directory]::Delete($OutputDirectory,$true)
    }
}
