# Security policy and operational boundaries

## Reporting vulnerabilities

Do not publish private domain controller names, usernames, raw Security events, passwords, secrets or infrastructure details in a public issue. Use a private maintainer contact or GitHub private vulnerability reporting if enabled.

## Threat model

This utility is a read-only collector, not endpoint protection, a SIEM, or a root-cause oracle. An attacker who can change DC event logs, compromise the collector account or modify runtime state can falsify observations.

## Least privilege

- Run from a dedicated Windows management host with a dedicated service identity.
- Allow remote Security log reads only for relevant Domain Controllers.
- Never require Domain Admin or AD write permissions.
- Restrict script directories, config and runtime DataDirectory with NTFS ACL.
- Apply internal code signing and change approval.
- Limit firewall access to designated management hosts.
- Protect credentials using Windows DPAPI tied to the scheduled task account and host.

## Personal data

Security events may expose account names, SIDs, computer names and user-linked activity. The organization operating the software is responsible for notice, access control, lawful processing and an agreed retention period. By default, the application retains canonical journal segments for 30 days from collection, unless eligible SMTP notices remain unacknowledged. An approved archive, disk-capacity and privacy policy remains mandatory for long-term deployment.

## Mail caveat

Legacy SmtpClient supports STARTTLS but not implicit TLS port 465, and message delivery cannot be made transactional with local state. An interrupted send can cause duplicate email. Do not send sensitive details to unapproved recipients or external mail systems.

## Incident response

If source event continuity cannot be established, heartbeat becomes stale, or a Security log resets, investigate the missing evidence and notify the responsible operator. Do not silently overwrite cursors to suppress errors. Store forensic evidence in approved locations and maintain chain of custody if applicable.

## Writer locking and code integrity

The local NTFS writer.lock handle prevents concurrent writers across Windows sessions on a single host. It is not distributed. Installer-managed release directories must be beneath Program Files so the scheduled account cannot trivially rewrite its own script. An existing data directory is never silently re-ACLed; operators must inspect permissions before use.

## Release assurance

The production-oriented publication process can be authorized without live Windows Server integration certification. GitHub Actions synthetic tests and automated static analysis do not replace a genuinely independent human security review. Known environmental test gaps remain in docs/TESTING.md.
