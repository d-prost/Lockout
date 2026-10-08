# Engineering review — 2026-10-08

## Scope
Baseline: user-supplied LockoutMonitor.ps1 archive. Target: Windows PowerShell 5.1, domain-joined Windows management host, built-in Security Event Logs, no DB/cloud, no AD writes. This review is source-level; it is not a Windows/AD integration certification.

## Audit findings

| Priority | Original behavior | Impact | Candidate treatment |
| --- | --- | --- | --- |
| CRITICAL | Single local DC | Incomplete domain coverage | Explicit configured multi-DC polling |
| CRITICAL | 30-minute lookback | Event loss after longer downtime | Separate per-DC RecordID cursor; retain DC logs and monitor liveness |
| CRITICAL | SMTP errors only in log | No automatic alert retry | Persist per-event outgoing status and retry |
| HIGH | One RecordID per process | Not valid across DCs | Per-source cursor |
| HIGH | Text/JSONL before cursor update | Crash could duplicate exported rows | Canonical event store; regenerate projections |
| HIGH | No log continuity guard | Silent retention gaps | Compare oldest/latest source RecordIDs; error on discontinuity |
| HIGH | Infinite growing output | Storage exhaustion | Explicit release limitation; archive/retention procedure required |
| HIGH | Script contains config | Unsafe editing and secret exposure | Private PSD1 config; ignore private config |
| HIGH | Notification source ambiguous | False blame of users/devices | Separate observed caller/source IP/root-cause fields |
| RECOMMENDED | No tests or CI | Regression risks | Synthetic Pester and Windows PS 5.1 CI |
| RECOMMENDED | No self-monitoring | Silent failure | Heartbeat and nonzero error exit |
| OPTIONAL | Automatic correlation | False attribution/performance risks | Bounded on-demand investigation instead |

## Reliability model

1. Read one DC at a time, track its cursor.
2. Write canonical event JSON under deterministic DC+RecordId key.
3. Update cursor after durable event creation.
4. Rebuild log projections from event store.
5. Attempt mail; write sent state only after send succeeds.
6. Report source and SMTP errors and update heartbeat.

**Honest guarantee:** durable local events use idempotent keys under a single writer, not end-to-end exactly-once semantics. Security events deleted by DC retention are unrecoverable. SMTP may deliver twice after a crash.

## Competitor comparison

| Project | Scope | Stack | License status | Differentiator here |
| --- | --- | --- | --- | --- |
| Brets0150/AD-PowerAdmin | Broad AD cybersecurity auditing, breach checks and ACL analysis | PowerShell | No root LICENSE verified | Smaller dedicated lockout tool |
| wgerade/direnix | Daily AD identity operational insights | C#/.NET | MIT verified | No application server/DB required here |
| Microsoft Account Lockout and Management Tools | Diagnostic utilities (LockoutStatus, etc.) | Windows utilities | Microsoft distribution terms | Scheduled open-source event evidence spool |
| Account_Lockout.ps1 | Multiple unrelated scripts share this name | Varies | Not verifiable by filename | No unsourced feature claims |

Source pointers: https://github.com/Brets0150/AD-PowerAdmin , https://github.com/wgerade/direnix , https://www.microsoft.com/en-us/download/details.aspx?id=18465 . These are comparisons of declared scope, not formal vulnerability or maintenance audits. No external code has been copied.

## Explicit release blockers

1. CI pass on the final head commit.
2. Windows Server integration tests on at least two reachable DCs with real or lab 4740 events.
3. Validate account-read permissions, event log wrap/clear, network interruption, Task Scheduler non-overlap and SMTP retry.
4. Retention/archive procedure, alert for stale heartbeat, review of personal-data handling and NTFS ACL.
5. Validate expected throughput; current projections rebuild from all canonical events on each run and are unsuitable for unbounded history.

## Rollback

Disable scheduled task and mail, preserve event files and state for diagnosis, then redeploy previous approved version. No AD policy or user-account changes are performed by this software.
