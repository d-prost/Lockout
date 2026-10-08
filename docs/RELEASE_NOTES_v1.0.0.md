# v1.0.0 — Production-oriented initial release

A minimal MIT-licensed Windows PowerShell 5.1 lockout monitor with explicit evidence boundaries. This is the first public release of the repository.

## Features

- Read-only multi-Domain Controller polling of Security Event ID 4740.
- Independent per-DC checkpoints and bounded RecordId queries.
- Immutable segmented JSONL event journal with reproducible text logs.
- Restart recovery when journal commit succeeds but checkpoint persistence is interrupted.
- Retention by collection date with safeguards for pending SMTP alerts.
- Optional HTML email with per-account cooldown, retry offsets and at-least-once delivery.
- On-demand evidence gathering from 4740, 4625, 4771 and 4776; root cause remains Undetermined.
- Idempotent preview/apply installer, protected code releases in Program Files, private configuration in ProgramData and Scheduled Task with indefinite non-overlapping repetition.
- Pester tests, PSScriptAnalyzer static checks and GitHub Actions performance benchmarks.

## Benchmark results

Synthetic, local, Windows Server 2022 GitHub Actions runner (500 records per segment):

- 10,000 records: ingestion 2.215 s, retention 1.096 s.
- 100,000 records: ingestion 21.139 s, retention 10.636 s.
- Recorded test run: https://github.com/d-prost/Lockout/actions/runs/37752814361

No claim is made about live DC/RPC or SMTP performance.

## Release assurance and waiver

This version is **production-oriented**, but it has **not been end-to-end validated against live Active Directory or SMTP in this authoring session**. The maintainer explicitly waived mandatory live Windows Server integration testing and final CI success as blockers for publishing. The waiver does not establish security certification or production acceptance by any enterprise.

Independent human code review is distinct from automated PSScriptAnalyzer and Pester; no completed human review is asserted without an actual reviewer record.

Operators must verify least privilege, Event Log access, scheduled-task identity, privacy/retention policy and operational alerting before reliance on this tool.

## Known limits

- Source Security log events lost to log wrapping cannot be recreated.
- Log resets that reuse record ranges may not be detected.
- Email delivery is at-least-once and can result in duplicate notices after abrupt failure.
- Retention can be extended by unresolved outbound notifications; ensure disk-capacity monitoring.
- Investigation attributes observed evidence fields, never a confirmed root cause.
- No cross-host distributed state lock, SQL database, dashboard, webhook or cloud dependencies.

## Start here

Read README.md, docs/INSTALLATION.md, docs/TESTING.md, docs/TROUBLESHOOTING.md and SECURITY.md. Preview installer before applying.
