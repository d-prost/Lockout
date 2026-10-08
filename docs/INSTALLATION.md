# Installation and Upgrade (Windows PowerShell 5.1)

This guide applies to a dedicated domain-joined Windows management host. The application does not need to run directly on Domain Controllers.

## 1. Prerequisites

- Elevated Windows PowerShell 5.1 for installation; approved read-only service identity for the scheduled job.
- Allowed remote Security event log read access to every configured DC and required network firewall rules.
- Security audit policy on relevant DCs already records event 4740. Do not modify audit policy merely to make a demo work.
- Windows ScheduledTasks module, local Program Files and ProgramData volumes using NTFS.
- Backup and monitoring responsibility assigned. Make privacy/retention decisions before production use.

Check read access before setup:

    Get-WinEvent -ComputerName dc01.example.org -LogName Security -MaxEvents 1

Access Denied indicates missing permission; it does not justify adding Domain Admin. Use approved Event Log Readers or narrowly delegated Security log permissions as supported by your environment.

## 2. Install with preview first

Download a reviewed tagged source, inspect the source code, and run from its root:

    .\Install-LockoutMonitor.ps1 -RunAs 'EXAMPLE\svc-lockout'

Preview must create no directories, tasks or credentials. For first-time staging, run an elevated PowerShell 5.1:

    .\Install-LockoutMonitor.ps1 -RunAs 'DOMAIN\svc-lockout' -DomainControllers dc01.corp.example,dc02.corp.example -Apply

This is the recommended one-command path for a new installation. It stages immutable source files under Program Files and creates the private config with the explicit DCs only if it does not already exist. Verify RetentionDays and Mail.Enabled before scheduling, and keep email disabled until checked.

Alternatively omit -DomainControllers: the installer creates an example config and stops before registering a task until you replace the placeholders. It requests the scheduled task account password only when Task Scheduler registration is required; no password is committed to Git.

When an existing config contains different DCs, the installer intentionally refuses to replace it automatically. Edit the private config under change control, then rerun.

Only newly created DataDirectory ACLs are set by the installer. For existing directories, review ACLs manually. Expected rights: SYSTEM/Administrators full, service identity modify; no broad Authenticated Users or Everyone write grants. Application code is required to live under Program Files to avoid ordinary-user modification.

## 3. Task definition

The task runs Windows PowerShell 5.1 with -NoProfile and -NonInteractive; no ExecutionPolicy bypass flag.

- Indefinite repetition, five-minute interval by default (configurable 1/2/5/10/15/30/60 minutes).
- MultipleInstancesPolicy = IgnoreNew.
- LeastPrivilege run level, specified dedicated account.
- ExecutionTimeLimit = 10 minutes. A terminated task recovers from durable journal on the next run.
- Absolute paths for script and private config; logs/state are local.
- No interactive workstation session is required.

Check the resulting task:

    Get-ScheduledTask -TaskName AD-LockoutMonitor
    Get-ScheduledTaskInfo -TaskName AD-LockoutMonitor

Manually run it only after verifying the DC list and service identity:

    Start-ScheduledTask -TaskName AD-LockoutMonitor

Health:

    Get-Content C:\ProgramData\LockoutMonitor\heartbeat.json -Raw

## 4. Safe re-execution and upgrades

The installed release path is a fingerprint of source files, so repeating the same installer version verifies copied file hashes instead of overwriting live code. Private config, journal, outgoing offsets and state are not overwritten.

A different release fingerprint changes the task action and requires explicit approval:

    .\Install-LockoutMonitor.ps1 -RunAs 'EXAMPLE\svc-lockout' -Apply -UpdateTask

Before replacement, the old Task Scheduler XML is saved under DataDirectory\task-backups. The previous code release remains on disk. Review task XML and actual configuration before updating.

Do not change the data directory, source DC names, state schema or retention abruptly without a migration plan. Switching versions while a task is active should be done during a controlled maintenance window.

## 5. Rollback

Disable the Scheduled Task first:

    Disable-ScheduledTask -TaskName AD-LockoutMonitor

Preserve all current journal, state and private config for diagnosis. To restore the previous release, use the last saved Task XML and the original account credential with an approved manual Register-ScheduledTask change. Do not erase old journal files merely to reset counters.

After rollback, check task status, writer.lock behavior, heartbeat age, cursor continuity and pending outbox files before enabling the task.

## 6. SMTP

Disabled by default. Configure a sanctioned SMTP relay and approved recipients in the private config. For a DPAPI-bound credential, use the actual task identity on the actual host:

    Get-Credential | Export-Clixml -Path 'C:\ProgramData\LockoutMonitor\smtp-cred.xml'

Restrict that file's ACL and set CredentialFile. Import-Clixml is bound to the Windows account/host, not portable to another run identity. SmtpClient supports STARTTLS; implicit TLS/SMTPS port 465 is not supported by that legacy API.

The monitor does not guarantee exactly-once SMTP delivery. Review pending backlog and cooldown behavior before enabling notification in production.

## 7. Operational caution

The user has elected to waive mandatory live Windows Server and CI certification as release gates. This does not prove those tests have been performed. Check at least task success, heartbeat, DC read permissions, audit policy, log free space and SMTP relay behavior in each deployment. Do not confuse publishing an artifact with an operational sign-off.

## 8. Readable lockout history

Use a single command to display all DCs together without copying journal files to a new persistent log:

    & 'C:\Program Files\LockoutMonitor\releases\<fingerprint>\Get-LockoutEvents.ps1' -Last 50

If running from the downloaded source directory, simply execute Get-LockoutEvents.ps1 there. To restrict output to one account, use -Account 'EXAMPLE\alice'. Use -DataDirectory for non-default storage locations.

The command is read-only; local NTFS access rights still apply. Do not expose real Security events in public support tickets.
