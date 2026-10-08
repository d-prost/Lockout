# AD Account Lockout Monitor & Investigator

A lightweight, read-only Active Directory account lockout monitor and investigator for **Windows PowerShell 5.1**. No database, web server, cloud subscription, PowerShell 7, or AD writes.

**Production-oriented v1.0.x.** Windows CI with synthetic events and storage benchmarks is available. Live Windows Server, DC Security Log, Scheduled Task and SMTP integration have **not** been verified in a real customer environment. Deployers must authorize and assess their own environment; a release is not a security certification.

## Scope

- Monitor Security Event ID **4740** on multiple explicitly named Domain Controllers
- One checkpoint per DC, bounded event-record windows and per-run workload caps
- Immutable JSONL segments plus regenerable human-readable log projections
- Read-only cross-DC history command; no duplicated combined log files
- Crash-safe journal-before-checkpoint ordering and recovery from interrupted state writes
- Explicit detection of source log rollback and known retention gaps
- Local date-based retention (30 days by default), preserving segments with pending eligible emails
- Optional HTML SMTP with persistent retry, durable offsets and account-specific cooldown
- On-demand read-only investigator for events **4740 / 4625 / 4771 / 4776**
- No external runtime modules, SQL database, SIEM or cloud services
- Repeatable installation with dry-run, immutable code releases and protected private configuration

**Root-cause policy:** the native Windows 4740 XML exposes the reported caller in `TargetDomainName` (a separate `CallerComputerName` may appear in normalized input). That field is **not** a trusted account-domain name, and it does not prove the root cause or IP. The stored `Account` is deliberately unqualified; `TargetSid` remains available for identification and SMTP cooldown. The 4625/4771/4776 workstation/IP values are observations only. `RootCause` stays `Undetermined`.

## Requirements

Windows Server or Windows management workstation, PowerShell 5.1, built-in ScheduledTasks module, local NTFS volume, and authorized read access to relevant DC Security event logs. Use a dedicated least-privilege identity, never Domain Admin for this purpose. Configure auditing and network rules separately through approved administration procedures. This tool does not modify audit policy, user accounts or domain configuration.

## Installation and upgrade

Detailed procedure: [docs/INSTALLATION.md](docs/INSTALLATION.md)

Preview, no changes:

    .\Install-LockoutMonitor.ps1 -RunAs 'EXAMPLE\svc-lockout'

One-command first install in elevated Windows PowerShell 5.1 (replace both DCs and the service identity):

    .\Install-LockoutMonitor.ps1 -RunAs 'DOMAIN\svc-lockout' -DomainControllers dc01.corp.example,dc02.corp.example -Apply

The installer initializes C:\ProgramData\LockoutMonitor\config.psd1 only when it does not exist. If -DomainControllers is omitted on a fresh installation, edit the generated placeholders and rerun. If an existing private config differs from requested DCs, installation stops instead of silently overwriting it. The installer copies code into fingerprinted immutable directories under Program Files; existing private config and journal are not overwritten. Replacing a different Scheduled Task requires explicit -UpdateTask and saves its former XML definition. An unchanged second run is a no-op.

## Configuration

Template: [config/config.example.psd1](config/config.example.psd1).

| Key | Default | Notes |
| --- | --- | --- |
| DataDirectory | C:\ProgramData\LockoutMonitor | Must be local NTFS |
| DomainControllers | Example FQDNs | Replace before task registration |
| InitialLookbackMinutes | 15 | Only first bootstrapping |
| RecordWindowSize | 10000 | Max Security RecordId span per query |
| MaxWindowsPerRun | 20 | Bounded work per run |
| BatchRecords | 500 | Records per durable JSONL segment |
| RetentionDays | 30 | Based on local collection date |
| Mail.Enabled | false | Optional and off by default |
| Mail.CooldownMinutes | 15 | Suppress repeated account notifications |

Data layout:

    DataDirectory/
      config.psd1
      state/<DC-hash>.json
      journal/<DC-hash>/YYYYMMDD/<firstId>-<lastId>.jsonl
      logs/<DC-hash>/YYYYMMDD/<firstId>-<lastId>.log
      outbox/<DC-hash>/<segment>.json
      cooldown.json
      heartbeat.json
      writer.lock
      task-backups/

The file-based exclusive writer lock applies across local Windows sessions. It does not coordinate separate servers.

## Read the latest events across all DCs

Run a single read-only command to see recent collected lockouts without creating another combined LOG file:

    .\Get-LockoutEvents.ps1 -Last 50
    .\Get-LockoutEvents.ps1 -Account 'EXAMPLE\alice' -Last 20

The history viewer reads the retained JSONL files, orders events by TimeUtc and does not modify the journal, checkpoints or mail state. On large stores, an on-demand full history scan can take longer than a scheduled monitoring pass. It does not attempt to attribute a root cause.

## Investigation

    .\Investigate-Lockout.ps1 -Account 'EXAMPLE\alice' -DomainControllers dc01.example.org,dc02.example.org -Minutes 15

| Event | Field | Evidence only |
| --- | --- | --- |
| 4740 | TargetDomainName in native XML, or explicit CallerComputerName in normalized sources | Reported caller only; not the locked account's domain |
| 4625 | IpAddress, WorkstationName | Failed logon observation |
| 4771 | IpAddress | Kerberos client address in event |
| 4776 | Workstation | NTLM reported source workstation |

Investigation matches an account name within a bounded time window. It does not establish SID-level correlation or a confirmed root cause. An individual malformed event is skipped with a warning rather than aborting all investigation results. Qualifying -Account with a domain does not authenticate that domain against a native 4740 record.

## Lab validation status

**Operator-reported Windows Server 2025 Domain Controller test:** a real Security Event 4740 was successfully parsed by the patch; a second consecutive monitoring run stored no duplicate event. Windows PowerShell 5.1 Pester checks passed 44/44 both in the operator report and independently on [GitHub Actions #37838548231](https://github.com/d-prost/Lockout/actions/runs/37838548231).

The lab lockout originated **on the DC itself**, so independent Windows 11 caller attribution, 4776/4771 account correlation, multi-DC retrieval, SMTP and actual least-privilege task registration are not yet established. See [sanitized lab acceptance report](verification/LAB_ACCEPTANCE.md) and [open 4776 investigation](https://github.com/d-prost/Lockout/issues/4). This is a verified single-DC scenario, not full production certification.

## Proxmox / Windows Server live lab

A **Windows Server VM is not automatically a Domain Controller**. To test real 4740 collection, use an isolated lab DC with AD DS and a domain-joined Windows 11 VM. Consult [the lab integration guide](verification/PROXMOX_AD_LAB.md) and run the read-only, privacy-safe [4740 field verifier](verification/Test-Lab4740.ps1) after inducing a lockout manually for a disposable lab-only account.

The previous v1.0.1 journal is intentionally immutable. Previously recorded WORKSTATION\USER labels may be misleading and are **not automatically rewritten**. A native 4740 account identifier is intentionally not domain-qualified without separate evidence; use TargetSid for unique identity where available.

## Guarantees and limits

- Canonical journal segments are written before DC checkpoints and have immutable event ID ranges. Startup recovery detects an already-written segment after an interrupted checkpoint write.
- Security log retention can erase source events permanently. Detected gaps or record-number rollback cause errors rather than advancing the cursor silently; unusual log resets that reuse IDs may evade detection.
- SMTP is at-least-once, not exactly-once. A crash immediately after a successful send may cause a duplicate message.
- Alert-eligible segments stay on disk until the outgoing offset acknowledges them. A stuck email backlog delays expiration and raises an error.
- Journal size is bounded by batch rotation plus retention; administrators should monitor free disk space, task status and heartbeat health.
- Event records contain potentially personal data; organizations must set approved storage permissions and retention policies.

## References

- [Installation](docs/INSTALLATION.md)
- [Troubleshooting and recovery](docs/TROUBLESHOOTING.md)
- [Tests and 10k/100k benchmarks](docs/TESTING.md)
- [Quality and simplification release](CHANGELOG.md)
- [Security policy](SECURITY.md)
- [Engineering review](docs/ENGINEERING_REVIEW.md)
- [Microsoft Get-WinEvent](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.diagnostics/get-winevent?view=powershell-5.1)

## Competing products

[AD-PowerAdmin](https://github.com/Brets0150/AD-PowerAdmin) covers broader AD security auditing. [Direnix](https://github.com/wgerade/direnix) is a broader C# identity operations tool. [Microsoft Account Lockout and Management Tools](https://www.microsoft.com/en-us/download/details.aspx?id=18465) provide traditional diagnostics. This repo targets small, maintainable, journal-backed monitoring without a new server platform. No competitor code has been copied.

License: MIT. See [LICENSE](LICENSE).
