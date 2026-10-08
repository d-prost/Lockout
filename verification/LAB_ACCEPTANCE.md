# Live lab acceptance — Event 4740 field mapping

## Evidence classification

This document records an **operator-reported** controlled lab execution of the candidate v1.0.2 patch. Results were provided by the operator, not independently reproduced through a direct connection by repository maintainers. No raw Security Event XML, secrets, private IP address or personnel data is stored here.

## Environment

- Isolated Proxmox-hosted Windows Server 2025 VM, promoted to a lab Domain Controller.
- Windows PowerShell 5.1; account lockout audit success configured for the lab.
- Disposable non-privileged test user; lab-only policy: three failed attempts / 30-minute lockout.
- Lockout achieved via failed LDAP authentication attempts on the **DC itself**, not via a separate Windows 11 client.
- After an audit delay, a real Security Event ID 4740 was observed.

## Operator-observed acceptance

| Scenario | Result | Interpretation |
| --- | --- | --- |
| Parser Pester, Windows PowerShell 5.1 | 44 / 44 PASS | Matches independently observed GitHub Actions results |
| Real Event 4740 parsed | PASS | Data fields processed without empty-node exception |
| Caller evidence | Event4740TargetDomainName | Native event exposed the reported caller in TargetDomainName |
| Caller compared with expected lab host | TRUE | The reported caller was the DC itself |
| Account incorrectly prefixed with caller | FALSE | Stored Account is the unqualified test username |
| Source IP established | FALSE | No unsupported IP inference |
| Root cause | Undetermined | No automatic causality inference |
| Two sequential monitor runs | OK / OK | One canonical event stored, no replay |
| Read-only history viewer | PASS | Test event shown correctly |
| Investigation Event 4740 | PASS | Expected caller observation shown |

The operator reported the actual lockout account attribute as LockedOut=True before the event appeared.

## Independently verifiable GitHub CI

[Windows PowerShell 5.1 Action #37838548231](https://github.com/d-prost/Lockout/actions/runs/37838548231) passed:

- PowerShell parser and PSScriptAnalyzer (no Error-level findings)
- 44 / 44 Pester unit/regression tests
- 10,000 / 100,000 synthetic journal/retention benchmarks

These tests verify the candidate code, not the operator's real-DC environment.

## Unresolved investigations and production gaps

1. Five 4776 events existed in the lab DC Security log, but no matching 4776 rows appeared in the account-filtered Investigator. Confirm exact EventData.TargetUserName values, EventTime, authentication status and search window using sanitized diagnostics; avoid claiming missing audit events or a broken parser without this evidence.
2. The lab exercise did not verify a caller on a **separate domain-joined Windows 11 host**.
3. No second DC, SMTP relay, or real Scheduled Task execution under a delegated service account was used.
4. Synthetic tests did not characterize Security log rollover on a real DC, or disruption of a production network.
5. Existing v1.0.1 journal events with incorrectly qualified account names are preserved as originally recorded. This patch does not retroactively rewrite journal data.

## Acceptance decision

**PASS:** native Event 4740 parsing and basic single-DC monitor/investigator operation for the tested Windows Server 2025 lab scenario.

**NOT YET VERIFIED:** cross-host caller fidelity, multi-DC collection, SMTP, least-privilege scheduled deployment and the unmatched 4776 evidence.

The limited lab PASS is not equivalent to all-feature production certification. Detailed reproduction steps: [PROXMOX_AD_LAB.md](PROXMOX_AD_LAB.md).
