# Contributing

The project targets Windows PowerShell 5.1 and minimum operational dependencies. PRs should preserve read-only Active Directory behavior, explicit evidence/attribution boundaries, and durable journal-before-checkpoint ordering.

Before proposing changes, add Pester coverage for failure and restart cases. Run the repository's Windows Actions workflow for syntax, PSScriptAnalyzer, reliability tests and synthetic performance. Network or SMTP integration claims require documented evidence from a controlled test environment.

Do not include real usernames, workstation names, Domain Controller identifiers, event logs, IP addresses, credentials or internal company data in public issues, tests or PRs. Use synthetic anonymized fixtures.

Do not copy code from other repositories without documenting compatible licenses and attribution. The project itself is MIT-licensed.

Keep changes small, comprehensible and backward-compatible when possible; document retention, task/credential implications and rollback when making operational changes.
