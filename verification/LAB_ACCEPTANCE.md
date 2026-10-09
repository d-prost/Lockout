# Lab acceptance

Updated: 9 October 2026  
Release: [v1.0.4](https://github.com/d-prost/Lockout/releases/tag/v1.0.4)  
Commit: `0ae46e7d4e5599717f6dd1e0b7d50265a23048c0`

The following results are from an isolated Windows Server 2025 lab Domain Controller, using Windows PowerShell 5.1 and a disposable domain test account. They were recorded during manual lab runs, not collected by GitHub Actions. The lab did not use a separate client as the lockout source.

## v1.0.4 — live DC acceptance

| Check | Result | Notes |
| --- | --- | --- |
| Pester suite on Windows PowerShell 5.1 | PASS | 49 passed, 0 failed |
| Test account locked out | PASS | Disposable lab account |
| Real Security Event 4740 present | PASS | Latest test event observed |
| 4740 caller from TargetDomainName | PASS | Matches the lab DC |
| No false account prefix, source IP or root-cause attribution | PASS | IP absent, RootCause = Undetermined |
| Monitor healthy after two runs | PASS | Status = OK |
| No duplicate RecordIds | PASS | Three distinct 4740 records |
| Newest real 4740 collected | PASS | Third lockout included |
| Account label unqualified | PASS | No workstation/domain prefix |
| Read-only history viewer | PASS | Three records returned |
| Investigator returned 4740 and 4771 evidence | PASS | Seven evidence rows |
| Investigator preserved root-cause uncertainty | PASS | RootCause = Undetermined |
| Data directory could be deleted after execution | PASS | No remaining open file handles |

**Live acceptance: 13/13 PASS.** The canonical journal retained all three observed lockouts once each. The previous `Invalid segment range` failure with multiple events in one poll did not recur with the released storage-only fix.

The Kerberos client address was the IPv6 loopback address `::1`, consistent with authentication attempts originating on the DC itself. The caller in 4740 identified the same lab DC. Neither field proves an external source IP or a root cause.

## Windows CI for the release

[Windows PowerShell 5.1 CI for commit 0ae46e7](https://github.com/d-prost/Lockout/actions/runs/37864885314):

- PowerShell parsing: PASS
- PSScriptAnalyzer Error-level findings: 0
- Pester: 49 passed, 0 failed
- Synthetic journal and retention benchmarks: 10,000 and 100,000 events PASS

The [v1.0.4 release workflow](https://github.com/d-prost/Lockout/actions/runs/37865326163) also passed. CI uses synthetic events; the checks above are separate live-lab observations.

## Earlier findings and resolution

- **v1.0.2:** real Event 4740 parsing and caller field mapping were confirmed. Empty XML fields and false `WORKSTATION\USER` prefixes had been corrected.
- **v1.0.3:** JSONL reader handles are disposed after errors. The v1.0.4 live run also confirmed that the data directory was releasable.
- **v1.0.4:** the official, unmodified storage-only fix collected multiple real 4740 records in one poll, wrote them in ascending numeric RecordId order, and did not duplicate them after a second run.
- **4776 investigation:** the five earlier 4776 entries were successful (`0x0`) and belonged to a different account. Failure auditing was initially off. Once enabled, six 4771 failures and the 4740 event were returned for the lab account, with `RootCause = Undetermined`. This explains the old discrepancy; [Issue #4](https://github.com/d-prost/Lockout/issues/4) is closed.

Previous release test counts (44/44 for v1.0.2 and 46/46 for v1.0.3) remain historical results, not the current acceptance baseline.

## Not yet tested

- Lockout originating from a **separate domain-joined Windows 11 workstation**.
- Scheduled Task running under a dedicated least-privilege account, including unattended operation.
- SMTP delivery, failed-send retry and cooldown against an actual test relay.
- Two live DCs, including per-DC cursor isolation and temporary loss of one DC.

These checks are tracked in [Issue #7](https://github.com/d-prost/Lockout/issues/7). Do not infer them from the successful single-DC run.

## Handling of lab evidence

Only summarized, sanitized results belong in this public repository. Do not commit raw Security Event XML, usernames, SIDs, actual domain names, workstation addresses, credentials or copied runtime journal data. Lockout generation and account cleanup were limited to the isolated lab.

**Decision:** v1.0.4 passes single-DC live acceptance for collection, cursor/deduplication, 4740/4771 evidence handling and file cleanup. Full production integration is not yet signed off.
