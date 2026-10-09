# v1.0.4 — Multiple Lockout Events in One Poll

This release fixes a monitoring availability bug affecting Event ID 4740 when more than one lockout is returned by a single poll.

## Problem and impact

In Windows Server lab testing, the operator reported `Invalid segment range` with two valid Security Event 4740 records, such as RecordIds 3523 and 3753. `Get-WinEvent` commonly yields the newest record first. Under the affected implementation, an unsorted canonical JSONL batch could be rejected, leaving the DC cursor unchanged and the monitor in an error state until repaired.

This does not establish that events were irretrievably lost; the cursor deliberately did not advance. Actual recoverability depends on whether the Security event log still retains the affected events when polling resumes.

## Minimal fix

`Write-JournalSegment` now explicitly sorts by numeric RecordId:

    Sort-Object -Property { [long]$_.RecordId }

The `Lockout.Runner.psm1` raw-event ordering was **not** changed. Under a controlled regression using two newest-first synthetic Windows event records, the isolated Storage fix was sufficient.

No changes to state, outbox, journal format, Event 4740 evidence semantics, or domain policy. Already persisted journal segments are not rewritten.

## Reproducible test evidence

**Before fix:** [CI #37863112331](https://github.com/d-prost/Lockout/actions/runs/37863112331) failed the newest-first two-event regression with `Invalid segment range`. One additional synthetic test failure was caused by an incomplete fixture and subsequently corrected.

**After Storage-only fix:** [CI #37863383209](https://github.com/d-prost/Lockout/actions/runs/37863383209) passed Windows PowerShell 5.1 parsing, PSScriptAnalyzer Error-level checks, **49/49 Pester tests**, and synthetic 10,000/100,000-event ingestion/retention benchmarks.

**Operator-reported live DC observation:** On a lab Windows Server DC, a two-event test collected both events once and reported `Status=OK` after the operator patched **both** Storage and Runner. The separate synthetic CI experiment isolated Storage as sufficient for that replicated case; the exact Storage-only patch has not yet been verified on the physical lab DC.

## Operational guidance

- Deploy after successful main-branch CI using the existing versioned installer and approved task update procedure.
- Preserve and inspect current cursor, journal and heartbeat first; do not delete state files merely to clear an earlier error.
- After upgrading, allow the monitor to re-collect missing entries only while retained in the source Security event log. Compare journal RecordIds, verify no duplicate entries and confirm the heartbeat returns to OK.
- A separate issue for root-cause investigation may be opened by repository maintainers; tests and evidence are preserved here and in PR #6.

## Remaining limits

A single event's CallerComputerName/TargetDomainName is evidence, not a proven root cause. Actual multi-DC, SMTP delivery and scheduled-task permissions require environment-specific validation. No automatic account unlocking, AD policy changes or database were added.
