# Real Event 4740 lab verification on Proxmox

Target: isolated Windows Server Domain Controller and domain-joined Windows 11 VM with Windows PowerShell 5.1.

This is a **manual integration procedure**, not an automatic account-lockout generator. Never test bad passwords on production accounts or change company-wide password policy for this lab.

## 1. Confirm the lab environment

On Windows Server, in elevated Windows PowerShell 5.1:

    Get-WindowsFeature AD-Domain-Services
    Get-Service NTDS
    Import-Module ActiveDirectory
    (Get-ADDomain).PDCEmulator
    Get-ADDomainController -Filter * | Select-Object HostName,Site

A Windows Server VM is not necessarily a Domain Controller. Without AD DS configured and NTDS available, the full AD lockout integration scenario is not possible.

On Windows 11:

    Get-CimInstance Win32_ComputerSystem | Select-Object Name,Domain,PartOfDomain

PartOfDomain should be True and the domain must be the isolated LAB domain. Verify DNS, time sync, and network isolation.

## 2. Controlled lab-only lockout

Use an ordinary disposable lab-domain account, never an administrator or service account. Configure an appropriate lab-only lockout policy (fine-grained if required), then induce a lockout manually from domain-joined Windows 11 by using the deliberately wrong test password.

Do not run automated failed-authentication loops against company accounts. Keep all test hosts and credentials isolated from production.

## 3. Check a real Security Event 4740 on the DC

Substitute the actual lab DC FQDN:

    $dc = 'dc01.lab.invalid'
    Get-WinEvent -ComputerName $dc -FilterHashtable @{
        LogName='Security'
        Id=4740
        StartTime=(Get-Date).AddHours(-2)
    } -MaxEvents 5 | Select-Object TimeCreated,Id,RecordId,MachineName

If the event is absent, verify audit policy, PDC Emulator and which DC handled the authentication. A second DC is required to test actual multi-DC behavior.

## 4. Privacy-safe field mapping check

From the candidate PR branch, in Windows PowerShell 5.1 at the repository root:

    .\verification\Test-Lab4740.ps1 -DomainController $dc -ExpectedCaller 'WIN11-LAB'

The script reports field-presence flags and compares the observed caller against an expected lab host. It does **not** print the usernames, SIDs or computer names contained in the actual Security Event.

Expected for a native 4740 with a caller:

- TargetDomainNamePresent = True
- ExplicitCallerFieldPresent = False
- CallerEvidence = Event4740TargetDomainName
- CallerMatchesExpected = True
- AccountContainsCallerName = False
- SourceIpEstablished = False
- RootCause = Undetermined

If a caller value is blank, attribution is inconclusive. Look at 4771/4776 as separate evidence, not as certain root cause.

## 5. Test the actual monitor

With SMTP disabled and a new secure local NTFS lab data folder, configure real LAB DCs. Run the following from the project source root:

    .\LockoutMonitor.ps1 -ConfigPath 'C:\ProgramData\LockoutMonitor\config.psd1'
    .\Get-LockoutEvents.ps1 -Last 10
    .\Investigate-Lockout.ps1 -Account 'labuser' -DomainControllers $dc -Minutes 30

Check the matching RecordId, observed caller, no false WORKSTATION\USER prefix, and no duplicate event on the second run. Then test a Scheduled Task on the management VM using a least-privilege identity. Enable SMTP only after source coverage is confirmed.

## 6. Privacy and limitations

Share only the sanitized output from the lab verification script. Do not publish real production Security Event XML; it can disclose names, SIDs and domain identifiers.

- Event 4740 does not by itself establish a source IP or proven root cause.
- The monitor still fails closed on malformed events (poison pill), while the on-demand investigator skips malformed items with warnings.
- Existing v1.0.1 journal records are immutable and are not rewritten. Historical records can retain misleading WORKSTATION\USER labels. New records use corrected mapping. Investigate or archive old data with explicit provenance if needed.
- Installation on a VM alone does not prove live AD event collection.
