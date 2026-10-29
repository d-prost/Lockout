# Contributing

The project targets Windows PowerShell 5.1 and minimum operational dependencies. PRs should preserve read-only Active Directory behavior, explicit evidence/attribution boundaries, and durable journal-before-checkpoint ordering.

For behavior changes, add relevant Pester coverage, including failure and restart
cases affected by the change. Documentation-only or formatting changes do not
need new behavior tests, separate briefs, handoffs or success reports. Use one
implementer for routine changes; request independent review for security,
permissions, retention, recovery or journal/checkpoint changes, covering the final
diff and SHA. Operational changes need an appropriate rollback and functional
verification; applying them to a real domain requires explicit authorization.
Open a PR when publishing and keep the `validate` Windows Actions job required
for syntax, PSScriptAnalyzer, reliability tests and synthetic performance.
Network or SMTP integration claims still require evidence from a controlled test
environment. See [maintenance policy](docs/MAINTENANCE.md).

Do not include real usernames, workstation names, Domain Controller identifiers, event logs, IP addresses, credentials or internal company data in public issues, tests or PRs. Use synthetic anonymized fixtures.

Do not copy code from other repositories without documenting compatible licenses and attribution. The project itself is MIT-licensed.

Keep changes small, comprehensible and backward-compatible when possible; document retention, task/credential implications and rollback when making operational changes.
