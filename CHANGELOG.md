# Changelog

## v1.0.4 — 2026-10-09

- Fix collection failure (`Invalid segment range`) when more than one native Event 4740 is returned in a single poll, including newest-first EventRecordId ordering.
- Sort canonical journal records by an explicit numeric `[long] RecordId` expression. This handles the OrderedDictionary values produced by the XML converter.
- Add three Pester regression tests covering descending multi-event journals, numeric RecordId sorting, and an end-to-end newest-first single-batch monitor run with cursor persistence and no duplicate replay.
- Keep `Lockout.Runner.psm1` unchanged: a storage-only patch passed the same regression tests in isolation, so the additional raw-event sort change was not necessary for this verified scenario.
- No changes to immutable JSONL records, cursor or outbox formats, account fields, credentials or Active Directory permissions.

Evidence: red regression on unpatched v1.0.3 ([CI](https://github.com/d-prost/Lockout/actions/runs/37863112331)), followed by 49/49 Pester tests and 10k/100k synthetic benchmarks after the storage-only patch ([CI](https://github.com/d-prost/Lockout/actions/runs/37863383209)).

The operator also reported correct two-event behavior on a real lab DC after changing both ordering sites; that manual observation does **not** independently prove the storage-only patch on a live DC. The regression suite isolates it under simulated Windows events.

## v1.0.3 — 2026-10-09

- Close JSONL StreamReader handles deterministically using try/finally, including on corrupted event records and journal tail validation errors.
- Prevent Windows Pester TestDrive cleanup failures from locked JSONL files.
- Add regression tests that reopen failed journal files with exclusive Windows file access and then delete them.
- Fail CI if Pester reports any failed test container, not only assertion failures.
- Gate automatic GitHub release publication on successful Windows PowerShell 5.1 CI for the current main commit. The v1.0.2 release remains immutable.

No journal schema, account-lockout event mapping, SMTP behavior or Active Directory configuration changes.

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
