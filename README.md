# AD Account Lockout Monitor & Investigator

A small read-only Active Directory account lockout monitoring and investigation tool for **Windows PowerShell 5.1**. No database, no web server, no cloud service and no Active Directory writes.

**Status: PILOT / release candidate. Production deployment requires a Windows Server integration test and successful CI.**

## Features

- Monitor Security Event ID 4740 on explicitly configured Domain Controllers.
- Maintain a separate high-water mark per DC in cursor.json.
- Store lockouts as durable, deduplicated canonical event JSON files.
- Reconstruct lockouts.jsonl and lockouts.log from that event store.
- Optional HTML SMTP alerting with cooldown and persisted send state.
- Interactive read-only investigation using Security Events 4740, 4625, 4771 and 4776.
- Root cause remains Undetermined; the 4740 caller is an observed host field, never a validated origin IP.

## Installation

1. Copy the repository to a controlled Windows management host.
2. Copy config/config.example.psd1 to config/config.psd1 and set the DC FQDNs.
3. Leave Mail.Enabled set to false for first tests.
4. Protect the configured DataDirectory (default C:\ProgramData\LockoutMonitor) with NTFS ACL allowing SYSTEM, administrators and the monitoring account. Use a local directory, not UNC.
5. Run from the repository root using Windows PowerShell 5.1:

    powershell.exe -NoProfile -File .\LockoutMonitor.ps1

6. Verify cursor.json, heartbeat.json, events/, lockouts.jsonl and lockouts.log.
7. Create a Scheduled Task every 1-5 minutes under an approved least-privilege identity. Use an explicit action path and non-overlap setting. The script additionally has a named mutex.
8. Enable SMTP only after assessing historical event backlog.

Task action:

    C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -File "C:\Tools\Lockout\LockoutMonitor.ps1"

The monitoring account needs permission to read Security event logs on each configured DC. Do not give it Domain Admin and do not open remote event log access beyond trusted management systems. Follow enterprise code-signing policy; do not bypass execution policy by default.

## Investigation

Example:

    powershell.exe -NoProfile -File .\Investigate-Lockout.ps1 -Account 'EXAMPLE\alice' -DomainControllers dc01.example.org,dc02.example.org -Minutes 15

Event evidence:

| Event | Data examined | Interpretation |
| --- | --- | --- |
| 4740 | CallerComputerName | Named caller in lockout event, not proven culprit |
| 4625 | IpAddress, WorkstationName | Failed logon observation |
| 4771 | IpAddress | Kerberos client address reported by the event |
| 4776 | Workstation | NTLM source workstation field |

Correlation is temporal only. A matching account name is not a validated SID/domain association, and a reported workstation or IP is not a proven root cause. The investigator is intentionally capped by time and event count.

## SMTP

Config is a PowerShell data file. HTML field values are encoded. Optional SMTP credentials may be stored with Windows DPAPI under the same task identity and host:

    Get-Credential | Export-Clixml -Path 'C:\ProgramData\LockoutMonitor\smtp-cred.xml'

Set the CredentialFile path in private config; do not commit private credentials. Use an approved SMTP relay. SmtpClient supports STARTTLS, not implicit port-465 TLS. SMTP is at-least-once: if delivery succeeds but the process crashes before mail-state.json updates, the message may be sent twice. Failed sends retry on later runs. Cooldown applies after successful sends. Enabling mail may notify for old events in the store.

## Reliability and limitations

- Canonical event files are written before the per-DC cursor. A crash can replay events, while the same DC+record ID is stored only once.
- Security log reset to a lower record ID is treated as an error and requires manual investigation.
- Source log retention can cause permanent gaps after prolonged downtime. No tool can recover events that the DC discarded; monitor heartbeat and retention.
- DCs must have event-auditing enabled and be reachable. One failing DC is reported without preventing reads from other DCs.
- The generated output is rebuilt on each run. Establish a retention/archive policy for long-running installations; performance will degrade for very large stores. Do not delete canonical event files without an approved archive/rebuild procedure.
- The local mutex does not coordinate multiple running hosts. Run a single writer per configured data directory.
- The script never unlocks AD accounts or changes domain policies.
- Logs contain personal data and should have bounded retention and least-privilege NTFS access.
- No exactly-once SMTP or universal forensic attribution claims are made.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Access denied | Check task identity, per-DC Security log ACL and network/RPC restrictions |
| No events | Check audit policy, DC, initial lookback window and Security log |
| Task failed | Check stderr, Task Scheduler history and heartbeat.json |
| SMTP errors | Check relay, recipient restrictions, STARTTLS and DPAPI identity |
| Security log reset | Preserve old state and logs, investigate and reinitialize under change control |
| Historical mail storm | Leave mail disabled until old store is archived or eligibility is reviewed |

## Tests and release gate

.github/workflows/test.yml parses all scripts in Windows PowerShell 5.1 and runs Pester unit tests. The tests use synthetic event XML. This is not a substitute for Windows integration testing of DC permissions, log rotation/reset, connectivity loss, SMTP, scheduled execution and stress behavior.

## Alternatives

- [AD-PowerAdmin](https://github.com/Brets0150/AD-PowerAdmin): broader PowerShell AD security auditing. No verifiable license file was found in its root during initial review.
- [Direnix](https://github.com/wgerade/direnix): broader C# identity operations product under MIT; larger operational scope.
- [Microsoft Account Lockout and Management Tools](https://www.microsoft.com/en-us/download/details.aspx?id=18465): established classic account lockout diagnostics.
- A filename alone (Account_Lockout.ps1) does not identify a unique GitHub project for a responsible comparison.

No competitor source code is copied. MIT License; see LICENSE.

## Microsoft documentation

- https://learn.microsoft.com/en-us/windows/security/threat-protection/auditing/event-4740
- https://learn.microsoft.com/en-us/windows/security/threat-protection/auditing/event-4625
- https://learn.microsoft.com/en-us/windows/security/threat-protection/auditing/event-4771
- https://learn.microsoft.com/en-us/windows/security/threat-protection/auditing/event-4776
