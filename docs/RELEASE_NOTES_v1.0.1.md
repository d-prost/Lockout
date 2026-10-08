# v1.0.1 — Quality & Simplification

Maintenance release for the Windows PowerShell 5.1 AD Account Lockout Monitor & Investigator.

## Reliability and security fixes

- Deduplicated JSON state I/O helpers; a single implementation owns atomic writes.
- Cursor recovery now checks the latest journal segment's actual payload, source and RecordId bounds; overlapping segment ranges are rejected rather than silently accepted.
- Idempotent Scheduled Task comparisons now detect privilege and LogonType changes, additional triggers/actions, disabled tasks and other critical safety-setting drift.

## Easier everyday operation

- Provide Domain Controllers in a single first-install command using -DomainControllers; existing private settings are not silently overwritten.
- View recent collected lockouts across all Domain Controllers using Get-LockoutEvents.ps1 -Last 50, with optional -Account and -Since.
- Use the existing segmented JSONL journal; there is no duplicate combined log, database or web server.

## Compatibility

- Windows PowerShell 5.1 and Windows Task Scheduler remain supported.
- The on-disk journal, checkpoints, configuration keys and SMTP-outbox schemas remain unchanged.
- Old v1.0.0 installation and release are preserved for rollback. Installing this version creates a new immutable code release path; updating the existing task still requires explicit -UpdateTask.

## Validation and limitations

Pester regression tests, PSScriptAnalyzer and 10k/100k synthetic Windows benchmarks are executed in GitHub Actions. Live Active Directory, Security Event Log RPC, Scheduled Task registration and SMTP delivery are not tested against customer production environments. RecordId history lost from DC log retention cannot be recovered. SMTP is at-least-once, not exactly-once. See docs/TESTING.md and SECURITY.md.
