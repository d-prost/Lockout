# v1.0.3 — Journal handle and Windows CI reliability

## Fixed

- Close journal file streams with explicit try/finally in both JSONL record reads and journal-tail verification, including if a corrupt event raises an exception.
- Resolve Windows Pester TestDrive cleanup failures caused by lingering JSONL file locks after expected exception tests.
- Add two targeted tests verifying that the journal file can be opened with FileShare.None and deleted immediately after both failure paths.
- Check the overall Pester run Result in CI, so container-level failures cannot be mistaken for successful assertions.

## CI-based release protection

The v1.0.2 tag was published while its Windows CI run failed. The release workflow for v1.0.3 therefore executes **only after the Windows PowerShell 5.1 CI workflow completes successfully on the current main commit**, and skips older or already-published commits.

## Verification boundaries

GitHub Windows PowerShell 5.1 CI runs Pester 5, PSScriptAnalyzer, parsing checks and 10,000/100,000 synthetic journal benchmarks. Live SMTP, multi-DC topology and least-privilege Scheduled Task integration remain environment-specific. The operator-reported live Domain Controller 4740 test for v1.0.2 remains applicable because this patch does not modify event interpretation.

## Compatibility

- No change to JSONL journal, cursor, outbox, configuration schema or AD policies.
- Existing records remain untouched.
- The previous v1.0.2 release and tag remain available for rollback.
