# Maintenance

Current baseline: **v1.0.4**. Single-DC live acceptance and Windows PowerShell 5.1 CI have passed. Keep the scope focused on reliability, security and documented deployment checks. No new features until the remaining integration checklist in [Issue #7](https://github.com/d-prost/Lockout/issues/7) is completed.

## Changes and reviews

- Use a pull request for changes to `main`.
- Add a regression test before changing behavior to fix an incident.
- Require Windows CI (`validate` job) to pass, including Pester and both journal benchmarks.
- Keep fixes small and preserve journal, cursor and outbox compatibility.
- Never include real Security Event XML, internal network details or credentials in public issues or commits.

## Protect main in GitHub

Configure a branch ruleset in [repository Rules settings](https://github.com/d-prost/Lockout/settings/rules):

1. Create a **branch ruleset**, target `main`, set enforcement to **Active**.
2. Require a pull request before merging.
3. Require status checks to pass. Select the `validate` check from **Windows PowerShell 5.1 tests**, and require an up-to-date check before merging when supported.
4. Block force pushes and deletion of `main`.
5. For a solo-maintained repository, do not require another person's approval. Leave bypass rights as restrictive as practical.

**Important:** writing this file does not activate a GitHub ruleset. Confirm protection in GitHub settings and verify a PR with failed CI cannot merge. This setting requires repository administration rights.

## Releases

- Keep published tags immutable. Documentation housekeeping does not warrant a new release.
- The `v1.0.4` release workflow already checks that Windows CI succeeded on the current `main` commit and skips publication when that tag exists.
- For a future code release, update the versioned release workflow and release notes in the same PR. Do not replace an existing tag.
- After a release, record real integration evidence separately from CI results in [LAB_ACCEPTANCE.md](../verification/LAB_ACCEPTANCE.md).

## Current integration work

The verified scope is single-DC Event 4740 collection, journal recovery/deduplication, 4740/4771 investigation and file-handle cleanup. Continue with the independent Windows 11 caller, unattended least-privilege Scheduled Task, SMTP/retry and two-DC scenarios in [Issue #7](https://github.com/d-prost/Lockout/issues/7).

[Issue #4](https://github.com/d-prost/Lockout/issues/4), concerning missing 4776 matches, is closed: the original records were successful events for a different account, and failure auditing was initially disabled. Do not reopen unless new contradictory evidence is found.
