# Changelog

## v1.0.2 candidate — Native Event 4740 correctness

- Fix StrictMode exceptions on empty EventData nodes using XML InnerText.
- Read native 4740 caller name from TargetDomainName while preserving explicit normalized CallerComputerName when present.
- Stop mislabeling caller workstation as the domain of the locked account; preserve TargetSid and raw subject/caller evidence.
- Use TargetSid for cross-domain SMTP cooldown identification when available.
- Make on-demand Investigator skip malformed XML events with warnings, preserving subsequent results.
- Support qualified/unqualified historical account filters without claiming native domain validation.
- Add Pester regression fixtures and an isolated Proxmox Windows Server/Windows 11 real-event verification guide.

Live lab integration remains pending; the historical journal is not rewritten automatically.

## v1.0.1 — 2026-10-08

Quality & Simplification maintenance release; no changes to the canonical event, state or outbox file schemas.

- Remove duplicate JSON read/write implementations; Storage owns persistence.
- Validate the latest journal segment's contents, source identity and RecordId boundaries before cursor recovery; reject overlapping journal ranges.
- Detect Scheduled Task privilege escalation, changed LogonType, additional actions/triggers and altered safety settings during idempotent installation checks.
- Support passing DCs to the initial installer with -DomainControllers while protecting any existing private configuration.
- Add Get-LockoutEvents.ps1 for unified, read-only lockout history across DCs without a second persistent combined log.
- Add Pester regression tests for journal corruption, task-definition drift and journal viewing.
- Keep installation, troubleshooting and test documentation aligned with the actual behavior.

Live Domain Controller, SMTP and registered-task integration validation remain deployment-specific and are not claimed by this release.

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
