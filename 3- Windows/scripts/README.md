# Scripts

## AD_Installer.ps1
**Functionality:** Interactive menu for installing/uninstalling AD DS role, promoting/demoting domain controllers, and upgrading forest functional levels.

**Use Case During Event:** Setting up or restoring Active Directory on a new or recovered domain controller.

**Risk Assessment:** HIGH — Demotion of the last DC permanently destroys the domain. Forest promotion and functional level upgrades are irreversible.

## CA_Enterprise_Installer.ps1
**Functionality:** Installs, publishes, or uninstalls an Enterprise Root Certificate Authority including self-signed cert creation and AD PKI object management.

**Use Case During Event:** Standing up or recovering the domain's certificate infrastructure for internal TLS/auth.

**Risk Assessment:** MEDIUM — Uninstall deletes all cert and CRL infrastructure without per-item confirmation. Can orphan already-issued certificates.

## CreateFileWatcher.ps1
**Functionality:** Monitors `C:\Users` recursively and logs file creation/modification events to the console in real time.

**Use Case During Event:** Detecting red team file drops or unauthorized changes in user directories.

**Risk Assessment:** LOW — Read-only monitoring. May produce excessive output on busy systems.

## Enable-WinRM.ps1
**Functionality:** Enables WinRM with HTTPS listeners, configures authentication (Basic, CredSSP), creates self-signed certificates, and opens firewall ports 5985/5986.

**Use Case During Event:** Enabling remote management so Ansible can reach Windows hosts.

**Risk Assessment:** MEDIUM — Opens remote management ports on all firewall profiles. Sets LocalAccountTokenFilterPolicy=1, reducing UAC token filtering.

## enableRDP.ps1
**Functionality:** Enables Remote Desktop by activating firewall rules, creating an inbound rule for TCP 3389, and setting registry values to allow RDP connections.

**Use Case During Event:** Enabling remote desktop access to manage Windows machines during competition.

**Risk Assessment:** MEDIUM — Exposes port 3389. Creates duplicate firewall rules if run multiple times. No encryption or session timeout configured.

## exportScheduled.ps1
**Functionality:** Enumerates all Windows scheduled tasks and exports them to a CSV file with task names, paths, descriptions, commands, and arguments.

**Use Case During Event:** Auditing scheduled tasks to find red team persistence mechanisms.

**Risk Assessment:** LOW — Read-only enumeration. Output CSV may expose sensitive command-line arguments if leaked.

## GetOUPermissions.ps1
**Functionality:** Enumerates all OUs in the domain and exports their ACLs and AD permissions to a CSV file.

**Use Case During Event:** Auditing OU permissions to detect unauthorized delegation or privilege escalation paths.

**Risk Assessment:** LOW — Read-only. Output CSV contains sensitive permission data that should be protected.

## Harden-GPO.ps1
**Functionality:** Comprehensive domain hardening via GPO: audit policy, NIST password policy, SMB/Kerberos/LDAP encryption, credential protection (WDigest, anonymous SAM, LSA Protection/RunAsPPL), Defender enforcement, and network hardening. Supports `-Safe` and `-SuperSafe` modes to reduce breakage risk, plus `-NoLSAProtection` to skip RunAsPPL specifically.

**Use Case During Event:** Rapidly hardening the domain from a single DC after initial access. Primary defensive tool for GPO-based lockdown.

**Risk Assessment:** HIGH — Disabling SMB1 and enforcing AES-only Kerberos can break legacy services. `-Reset` flag deletes all custom GPOs. Password policy changes affect the entire domain. RunAsPPL requires reboot and can break unsigned SSPs/smart-card middleware (use `-NoLSAProtection` on those boxes). Always backs up GPOs before changes.

## IncidentResponse.ps1
**Functionality:** IR toolkit with 7 functions: detect recently created accounts, search security events, find failed logons, locate hidden executables, enumerate network connections, list recent processes, and block outbound IPs via firewall.

**Use Case During Event:** Primary detection and investigation tool during active incident response.

**Risk Assessment:** MEDIUM — Block-OutboundIP creates firewall rules without IP validation. Hidden file scan on full C: drive may be slow. Most functions are read-only.

## KillKnownMalwareProceses.ps1
**Functionality:** Force-terminates processes matching hardcoded known malware tool names (Mimikatz, Netcat, PowerSploit, Metasploit, etc.).

**Use Case During Event:** Quick kill of known offensive tools during active red team engagement.

**Risk Assessment:** MEDIUM — No confirmation before killing. Could terminate legitimate tools with similar names. No logging of terminated processes.

## DeterministicPassRotation-Local.ps1
**Functionality:** Resets every enabled local user's password to `SHA256("<master_hash>:<username>\n")`, byte-for-byte matching a Linux counterpart script. Master hash is prompted interactively as `SecureString`, never written to disk or any managed string; derived passwords live only as `SecureString` in zeroed byte buffers. Preview + confirmation flow, no file output, PSReadLine history scrubbed.

**Use Case During Event:** Rotating local passwords such that every user gets a unique password but only one master hash needs to be remembered to recover any of them. Same master hash + username produces identical passwords on Linux and Windows.

**Risk Assessment:** HIGH — Resets Administrator by default (excluding only `DefaultAccount`, `WDAGUtilityAccount`, `blackteam`, `black-team`, `svcroot` variants). Irreversible without the master hash. No rollback possible — if the master hash is forgotten, every rotated account is locked out.

## Derive-Passwords-Bulk.ps1
**Functionality:** Bulk-derives plaintext passwords from the same master hash used by the `DeterministicPassRotation-*` scripts. Takes a whitespace-separated list of usernames (paste-friendly — auto-filters non-username tokens), prompts for the master hash as `SecureString`, and writes a CSV of `username,password` pairs to a mandatory `-OutPath`. Refuses OneDrive/Documents/UNC/mapped-network paths. Locks output ACL to current user + SYSTEM + Administrators after write.

**Use Case During Event:** Run on a **separate trusted/offline machine** to recover plaintext for any subset of users whose passwords were rotated. Primary way to actually log in as a rotated user — rotation script doesn't reveal passwords anywhere.

**Risk Assessment:** CRITICAL — Output file is a complete key to every listed account. Must be run only on a protected machine, stored on encrypted/removable media, and wiped immediately after use via `cipher /w:<dir>`. Script refuses common sync paths but cannot catch every exfiltration vector.

## DeterministicPassRotation-AD.ps1
**Functionality:** AD-wide equivalent of `DeterministicPassRotation-Local.ps1` — resets every enabled AD user's password via `Set-ADAccountPassword` using the same deterministic derivation. Targets the PDC emulator for fast replication. Same OpSec properties: `SecureString` hash input, no disk output, memory zeroed.

**Use Case During Event:** Domain-wide password rotation after initial access to lock out any compromised credentials, while preserving recoverability via the master hash.

**Risk Assessment:** CRITICAL — Resets every enabled domain user except `krbtgt`, `Guest`, built-ins, `blackteam`, `black-team`, and `svcroot` variants. Administrator IS reset by default. Fires 4724/4738 on the DC (expected). No rollback without the master hash.

## Strip-Groups-Nuclear.ps1
**Functionality:** Removes ALL group memberships from every domain user except configured exclusions, then rebuilds only the specified privileged groups to match desired state. Creates backup CSV before changes.

**Use Case During Event:** Nuclear option to reset all AD group memberships if red team has planted unauthorized privilege escalation.

**Risk Assessment:** CRITICAL — Permanently removes all custom groups (department, application, resource groups). Manual recovery from backup is complex. Users lose all resource access during execution.
