# v1.0.2 — Native Windows Event 4740 correctness

Critical correctness release for Security Event 4740 parsing. No AD writes, auto-unlocking, database, web server or cloud dependency.

## Changes

- Parse empty EventData XML elements with InnerText under StrictMode and Windows PowerShell 5.1.
- Interpret native 4740 TargetDomainName as the event's reported caller-computer field, not as the locked account's verified domain. An explicit normalized CallerComputerName is still supported.
- Preserve TargetSid for identity and use it for SMTP cooldown when available. Account is stored as unqualified TargetUserName. Keep separate SubjectDomainName and RawTargetDomainName evidence.
- Skip malformed events individually during on-demand Investigation, with a warning.
- Support qualified and unqualified account name searches of historical and new journal entries.
- Add Pester regression tests and a read-only live-lab field verification script.

## Verification

**Independently checked GitHub CI:** [Run #37838548231](https://github.com/d-prost/Lockout/actions/runs/37838548231) passed Windows PowerShell 5.1 parsing, PSScriptAnalyzer Error-level checks, 44 of 44 Pester tests, and 10k/100k synthetic journal benchmarks.

**Operator-reported live-lab test (maintainers did not remotely inspect raw event XML):**

- Isolated Windows Server 2025 Domain Controller; dedicated disposable lab-domain test account.
- Real Security Event 4740 appeared following deliberate failed lab authentication attempts.
- Sanitized verifier reported CallerEvidence = Event4740TargetDomainName; CallerMatchesExpected = True; AccountContainsCallerName = False; SourceIpEstablished = False; RootCause = Undetermined.
- Two monitor runs returned Status = OK; exactly one canonical event was stored. Read-only history and 4740 investigator displayed expected evidence.
- Lockout was triggered on the DC itself, so the caller was the DC. Cross-host caller attribution from domain-joined Windows 11 has NOT yet been verified.

See [Lab acceptance](../verification/LAB_ACCEPTANCE.md) and [Proxmox lab procedure](../verification/PROXMOX_AD_LAB.md).

## Remaining limitations

- The operator saw five Event 4776 entries but no matching 4776 rows in the account-filtered investigator results. Account identity and time-window filtering need separate investigation; no root cause has been confirmed.
- Distinct Windows 11 caller, second DC, real least-privilege Scheduled Task and SMTP integration remain unverified.
- Old v1.0.1 journal entries are immutable and may retain historically wrong WORKSTATION\USER account prefixes. The patch does not rewrite past forensic evidence.
- Event 4740 cannot by itself prove the originating IP or underlying root cause; that stays Undetermined.
- Exactly-once SMTP and lossless recovery after source Security log rollover are not guaranteed.

This version is production-oriented but is not company-specific production acceptance or end-to-end integration certification.
