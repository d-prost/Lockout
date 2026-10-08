# Changelog

## v1.0.0 — 2026-10-08

- Initial public production-oriented Windows PowerShell 5.1 release.
- Multi-Domain Controller Event 4740 polling with separate checkpoints and bounded RecordId windows.
- Immutable local JSONL segments and text log repair.
- Restart-safe durable journal commit and cursor recovery.
- Explicit detection of known Security log retention gaps and rollbacks.
- Configurable local retention with protection for unacknowledged email alerts.
- HTML email, persistent retry and per-account cooldown.
- On-demand read-only 4740/4625/4771/4776 evidence investigator.
- Idempotent preview/apply installation and Windows Task Scheduler configuration.
- Pester reliability suite, PSScriptAnalyzer review and 10k/100k synthetic benchmarks.

This release does not claim completed live Windows Server, Active Directory or SMTP integration validation; see docs/TESTING.md.
