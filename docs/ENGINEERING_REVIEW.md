# Engineering Review (2026-10-08)

## Provenance and scope

The original user-provided ZIP contained a single-host PowerShell lockout monitor. This review is a source-level evaluation; no production Active Directory, DC Security event logs or SMTP credentials were available to this repository authoring session. Windows Server integration behavior is **not** certified. No external project code was copied.

## Original critical and high-risk findings

| Severity | Prior problem | Impact | Revised solution |
| --- | --- | --- | --- |
| CRITICAL | Local DC only | Missed lockouts on other DCs | Explicit multi-DC polling and per-source state |
| CRITICAL | Fixed small lookback | Gaps after scheduler outages | RecordId-bounded continuation |
| CRITICAL | Failed SMTP not queued | Missed notifications | Per-segment outbox offsets with retry |
| HIGH | One global RecordId | Invalid across DCs | Checkpoint per source |
| HIGH | Nontransactional text/JSON state | Duplicates or missing rows | Immutable journal before cursor, regenerable text logs |
| HIGH | No log lifecycle checks | Silent log-wrap data loss | Fail on known retention gaps/record rollback |
| HIGH | Unbounded log accumulation | Storage exhaustion | Size-rotated JSONL, date-based retention |
| HIGH | Config embedded in code | Unsafe updates | Private PSD1 outside installed code |
| HIGH | Caller computer treated as cause | Unreliable attribution | Observed caller, source evidence, undetermined root cause |
| HIGH | Concurrency uncertain across sessions | Concurrent state updates | Exclusive local NTFS writer.lock handle |
| RECOMMENDED | No test suite | Undetected regressions | Pester, AST parsing, PSScriptAnalyzer, synthetic benchmarks |
| OPTIONAL | Automatic causal correlation | False positives and complexity | Bounded, on-demand read-only investigator |

## Current architecture

1. Installer puts hash-verified executable files under protected Program Files, private config and state under ProgramData.
2. Scheduled Task runs every five minutes using a dedicated non-admin identity.
3. Runner opens writer.lock exclusively for the duration of work.
4. For each DC, load and validate checkpoint; scan journal range; attempt crash recovery from already committed segments.
5. Read Security log bounds and query at most MaxWindowsPerRun windows, each at most RecordWindowSize source RecordIds.
6. Convert 4740 XML by named fields; append immutable JSONL segment; write text projection; only then commit cursor.
7. Process alert-eligible journal segments through persistent offset and cooldown state. Failed sends are retried. Completed segments are skipped.
8. Expire historical journal segments according to collection date, unless email remains pending.
9. Update heartbeat with OK/BACKLOG/ERROR and details. Any detected stage failure exits nonzero.

Journal data is deliberately simple local files; no SQL database or cloud dependency.

## Test evidence

- Synthetic Pester suite: restart, duplicate records, failed remote source, cursor replay, committed journal recovery, SMTP retry, retention, no-overlap and task definition.
- Windows Server 2022 runner benchmark at 500 records/segment: 10,000 events 2.215s; 100,000 events 21.139s for synthetic ingestion. Retention 1.096s and 10.636s respectively.
- Evidence: https://github.com/d-prost/Lockout/actions/runs/37752814361
- Current branch also runs PSScriptAnalyzer 1.25.0; see final HEAD Actions status for results.

These are synthetic tests only. No claim of live DC query validation, SMTP live delivery or real Scheduled Task registration.

## Residual risks

| Priority | Residual risk | Treatment |
| --- | --- | --- |
| HIGH | DC Security events rolled off before query | Detected gaps fail closed; missing data cannot be recovered |
| HIGH | Security log clears/reuses IDs faster than polling | Cannot guarantee detection; external audit and incident process required |
| HIGH | SMTP exactly-once delivery not feasible | At-least-once with documented duplicate window |
| HIGH | Large pending email backlog may extend retention | Heartbeat error, operator action and disk alert required |
| HIGH | Local code or state compromised by privileged attacker | Least-privilege ACL, signed deployment, infrastructure audit |
| RECOMMENDED | Live DC, RPC, Event Log ACL, XML Task registration untested | Deployment owner verification |
| RECOMMENDED | Independent human code review not yet documented | Obtain reviewer approval independently of authoring assistant |
| OPTIONAL | Advanced multi-domain identity correlation | Deferred; explicit evidence-only investigator |

## Release decision

The maintainer explicitly requested a **production-oriented release without making live Windows Server integration testing or successful CI mandatory hard gates**. This waiver concerns publication policy only; it is not a proof of safety or a claim of having performed those tests. Independent static-analysis rules are automated and should not be misrepresented as an independent human reviewer.

Before relying operationally on alerts, deployers should inspect their own domain permissions, task registration, stale heartbeat, source Security log size and SMTP relay behavior.

## Comparison

| Existing product | Focus | Difference |
| --- | --- | --- |
| Brets0150/AD-PowerAdmin | Broad PowerShell AD security audit | This utility focuses narrowly on lockout data durability |
| wgerade/direnix | Broader C# identity-operations automation | This utility uses Windows PowerShell and local files |
| Microsoft Account Lockout and Management Tools | Classic troubleshooting utilities | This utility continuously journals new lockouts |

AD-PowerAdmin root LICENSE could not be independently verified; no source is borrowed. Direnix advertises an MIT license. A filename alone such as Account_Lockout.ps1 is too ambiguous for an accurate license and maintenance comparison.

## Rollback

Disable the task, preserve private data and journal, restore prior Task Scheduler XML if available, and inspect checkpoint and outbox consistency before restarting. No domain policy or account changes are made by this utility.
