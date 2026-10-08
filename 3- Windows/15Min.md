# Windows First 15 Minutes - CCDC 2027

## First 15 Minutes DC
- [ ] Run Admin Error / Trap Detection Script (./pre-flight-audit.ps1)
- [ ] Add Team Accounts & Verify Access 
- [ ] Note Logged-in Users & Baseline Time (./show-all-active-sessions.ps1)
- [ ] Run Backup Script (./Backup-AD.ps1) (./Backup-Base.ps1)
- [ ] Rotate & Disable Default Administrator & Guest
- [ ] Secure default privileged groups (Secure-GPO-OU.ps1)
- [ ] Reset DNS host file & check forwarders (./reset-host-file.ps1)
- [ ] Install sysinternals (./Install-Sysinternals.ps1)
- [ ] Check & Harden Surface: Firewall, RDP, and SMBS
- [ ] Disable LLMNR and NetBIOS over TCP/IP

## First 15 Other machines
- [ ] Note Logged-in Users & Baseline Time (./show-all-active-sessions.ps1)
- [ ] Verify New Admin access
- [ ] Run local backup script (./Backup-Base.ps1)
- [ ] Rotate & Disable Default Administrator & Guest 
- [ ] Reset DNS host file (./reset-host-file.ps1)
- [ ] Install sysinternals (./Install-Sysinternals.ps1)
- [ ] Check & Harden Surface: Firewall, RDP, and SMB (./remove-non-default-shares.ps1)
- [ ] Disable LLMNR and NetBIOS over TCP/IP
- [ ] Dump local running services, scheduled tasks, & active network connections

## Post 15
- [ ] Install Toolkit (./install-firefox.ps1) (./Install-Nmap.ps1) (./Install-Wireshark.ps1) (./Install-Chainsaw.ps1)
- [ ] Deploy forest-wide baseline GPO (./Harden-GPO.ps1)
- [ ] Check services
- [ ] Rotate all credentials if necessary (./Reset-LocalPasswords.ps1) (./Reset-ADPasswords.ps1) (./Export-DerivedPasswords.ps1)
- [ ] Rotate Kerberos (krbtgt) twice if necessary