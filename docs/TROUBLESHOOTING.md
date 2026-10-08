# Troubleshooting and Recovery

## Start here

Check Windows Task Scheduler history and the JSON heartbeat:

    Get-ScheduledTaskInfo -TaskName AD-LockoutMonitor
    Get-Content C:\ProgramData\LockoutMonitor\heartbeat.json -Raw

Status OK means the last application loop had no detected errors; BACKLOG means the configured per-run record windows did not complete; ERROR means one or more DC queries, SMTP or retention actions encountered errors. Heartbeat freshness must be monitored outside this tool.

## Access denied while reading Security event log

Verify the scheduled identity and remote Event Log permissions. Check RPC access from the management host, firewall policy and name resolution. Security Event Log reader permissions vary by host configuration and GPO. Do not grant Domain Admin as a troubleshooting shortcut.

## Missing 4740 events

Identify which DC logged the account lockout, verify DC audit policy and Security log capacity, and confirm that the target event is within the initial lookback or recorded cursor range. EventRecordId is DC-specific and cannot be compared across different computers.

## Network disconnect or failed RPC

The failing DC does not advance its cursor. Other available DCs continue. The task exits nonzero and heartbeat lists errors. Restore connectivity and let the next Task Scheduler cycle retry. Never manually fast-forward a cursor to suppress the error.

## Security log retention gap or reset

The monitor stops that source if the observed oldest RecordId exceeds the checkpoint gap or the newest ID goes backward. Some log clear/replacement cases can reuse record IDs and cannot be detected reliably, so correlate with operational event log lifecycle evidence.

Recovery must be approved and documented:

1. Disable the scheduled task.
2. Preserve the affected source's journal, state and outbox on secured storage.
3. Determine which DC event interval was missed, whether audit log records still exist elsewhere and whether incident response is necessary.
4. Decide whether to re-bootstrap that DC under a new source identity or reset its old source state and journal together. Never delete cursor alone and assume its retained event history is complete.
5. Re-enable the task and check heartbeat, source progression and deduplication.

This project intentionally does not provide a destructive auto-reset command.

## Journal integrity errors during cursor recovery

If the monitor reports a malformed latest JSONL segment, a source mismatch, or overlapping RecordId ranges, it intentionally does not advance that DC checkpoint. The filename alone is no longer treated as sufficient proof of a completed segment.

1. Disable the Scheduled Task and preserve the entire DataDirectory, including state, journal, outbox, and heartbeat, in an approved secured location.
2. Compare the indicated journal file with a trusted backup. Check the first/last RecordId and Domain Controller identity; note any overlap with other collection dates.
3. Do not rename files, delete cursor.json/state files or fast-forward RecordIds to suppress a corruption warning.
4. Have an operator determine whether a complete source event interval can be re-collected. Restore or migrate under documented change control and verify no pending mail records are lost.
5. Resume the task and confirm healthy checkpoint progression and no duplicate journal ranges.

A valid tail check does not cryptographically attest every historical record; stronger forensic integrity or tamper detection must be supplied by an approved external log system if required.

## Scheduled Task security drift

The installer refuses to consider a task unchanged when privileges, LogonType, trigger/action count, execution settings or non-overlap policy differ. Before using -UpdateTask, review the exported XML and the affected service account; do not blindly overwrite a task that an administrator or attacker modified.

## SMTP errors or repeated mail

SMTP failures leave the corresponding segment outbox offset pending for a later run. A crash after successful send but before offset persistence may yield a duplicate email. Review relay TLS mode, credentials, recipient restrictions, alert eligibility and cooldown. Check SMTP delivery reports before resetting an outbox.

## Disk usage and retention

Journal JSONL and text logs are segment files, each with a maximum of BatchRecords events. The retention date is the **local collection date** in the directory name, not the source event date. A segment containing pending eligible mail is not deleted. A prolonged SMTP outage can delay deletion beyond RetentionDays and raises an ERROR.

Back up operational evidence according to retention policy, and inspect disk free space. Never delete outstanding journal segments merely to unblock retention. The application does not enforce a hard disk quota.

## Corrupted state or journal

Do not edit event JSONL or cursor JSON by hand while the Scheduled Task runs. Disable the task, preserve a forensics copy, and compare state with journal ranges. The application refuses to auto-initialize a missing DC checkpoint when durable journal segments exist.

## Scheduled Task will not run

- Check the executable path is Windows PowerShell 5.1.
- Confirm the account is authorized for batch logon and password state is valid.
- Confirm source release files are protected against non-admin writes.
- Check Task Scheduler last result and local/event log access under the **task identity**, not just an administrator's interactive shell.
- Verify execution policy and script signing requirements; do not disable enterprise protections as a default workaround.

## 4740 has a caller but Account looks like WORKSTATION\USER

Older v1.0.1 records may incorrectly concatenate the native TargetDomainName field (a reported workstation) with TargetUserName. This patch preserves old canonical JSONL without rewriting historical evidence. New native 4740 events keep Account = TargetUserName, CallerComputer = TargetDomainName, and the TargetSid when supplied.

A blank CallerComputer is a valid observation, not proof of missing logging or a particular root cause. The investigator warns and skips malformed individual XML events. The continuous monitor deliberately fails closed on malformed source entries; repeated poison events require a separately reviewed operator recovery design.

Use the isolated lab verification script to check real field mapping. Do not publish unsanitized Security XML from company Domain Controllers.
