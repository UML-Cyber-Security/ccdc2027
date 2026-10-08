#Requires -RunAsAdministrator
[CmdletBinding()]
param (
    [string]$RootPath = "C:\IR_Backup"
)
$ErrorActionPreference = "SilentlyContinue"
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ADDir = Join-Path $RootPath "ADBackup_$Timestamp"
New-Item -ItemType Directory -Path $ADDir -Force | Out-Null

$FlagFile = Join-Path $ADDir "AD_TRIAGE_FLAGS.txt"
"=== ACTIVE DIRECTORY TRIAGE FLAGS ($Timestamp) ===" | Out-File $FlagFile

# 1. NTDS Snapshot
Write-Host "[*] Creating NTDS Snapshot..." -ForegroundColor Yellow
ntdsutil snapshot "activate instance ntds" create quit quit | Out-File (Join-Path $ADDir "ntds_snapshot.log")

# 2. GPO & SYSVOL Scripts
Write-Host "[*] Backing up GPOs and SYSVOL scripts..." -ForegroundColor Yellow
$GpoDir = Join-Path $ADDir "GPOBackup"
New-Item -ItemType Directory -Path $GpoDir -Force | Out-Null
Backup-Gpo -All -Path $GpoDir | Out-Null

$SysvolScripts = Join-Path $ADDir "SYSVOL_Scripts"
New-Item -ItemType Directory -Path $SysvolScripts -Force | Out-Null
Copy-Item "$env:SystemRoot\SYSVOL\sysvol\*\Policies\*\*\Scripts" -Destination $SysvolScripts -Recurse -Force

$scripts = Get-ChildItem -Path "$env:SystemRoot\SYSVOL\sysvol" -Recurse -File -Include *.bat,*.cmd,*.ps1,*.vbs,*.exe
if ($scripts) {
    "`n[!] SCRIPTS FOUND IN SYSVOL (REVIEW FOR BACKDOORS):" | Out-File $FlagFile -Append
    $scripts | Select-Object FullName | Out-String | Out-File $FlagFile -Append
}

# 3. OUs and Access Control Lists
Write-Host "[*] Exporting OU structure and ACLs..." -ForegroundColor Yellow
$OUDir = Join-Path $ADDir "OUs"
New-Item -ItemType Directory -Path $OUDir -Force | Out-Null
Get-ADOrganizationalUnit -Filter * -Properties * |
    Select-Object Name, DistinguishedName, Description, BlockInheritance, ProtectedFromAccidentalDeletion, LinkedGroupPolicyObjects |
    Export-Csv (Join-Path $OUDir "OU_Structure.csv") -NoTypeInformation

$ouAclReport = [System.Collections.Generic.List[PSObject]]::new()
Get-ADOrganizationalUnit -Filter * | ForEach-Object {
    $ouDN = $_.DistinguishedName
    $ouAcl = Get-Acl -Path "AD:\$ouDN"
    foreach ($access in $ouAcl.Access) {
        $ouAclReport.Add([PSCustomObject]@{
            OU                    = $ouDN
            IdentityReference     = $access.IdentityReference.Value
            ActiveDirectoryRights = $access.ActiveDirectoryRights
            AccessControlType     = $access.AccessControlType
            IsInherited           = $access.IsInherited
            InheritanceType       = $access.InheritanceType
        })
    }
}
$ouAclReport | Export-Csv (Join-Path $OUDir "OU_ACLs.csv") -NoTypeInformation

$badOuAcls = $ouAclReport | Where-Object {
    $_.ActiveDirectoryRights -match 'GenericAll|WriteDacl|WriteOwner' -and
    $_.IdentityReference -notmatch 'ENTERPRISE DOMAIN CONTROLLERS|Domain Admins|Enterprise Admins|SYSTEM'
}
if ($badOuAcls) {
    "`n[!] SUSPICIOUS OU PERMISSIONS (GENERICALL / WRITEDACL):" | Out-File $FlagFile -Append
    $badOuAcls | Select-Object OU, IdentityReference, ActiveDirectoryRights | Out-String | Out-File $FlagFile -Append
}

# 4. Identity & Kerberos Risks
Write-Host "[*] Auditing Kerberos, SPNs, and AdminSDHolder..." -ForegroundColor Yellow
$asrep = Get-ADUser -Filter {DoesNotRequirePreAuth -eq $true} -Properties DoesNotRequirePreAuth
$asrep | Select-Object SamAccountName, DistinguishedName, Enabled | Export-Csv (Join-Path $ADDir "ASREP_Roastable_Users.csv") -NoTypeInformation
if ($asrep) {
    "`n[!] AS-REP ROASTABLE ACCOUNTS (DONT_REQ_PREAUTH):" | Out-File $FlagFile -Append
    $asrep | Select-Object SamAccountName, Enabled | Out-String | Out-File $FlagFile -Append
}

$spns = Get-ADUser -Filter {ServicePrincipalName -like "*"} -Properties ServicePrincipalName, MemberOf, adminCount
$spns | Select-Object SamAccountName, DistinguishedName, ServicePrincipalName, adminCount, Enabled | Export-Csv (Join-Path $ADDir "Kerberoastable_SPNs.csv") -NoTypeInformation
if ($spns) {
    "`n[!] KERBEROASTABLE SPN ACCOUNTS:" | Out-File $FlagFile -Append
    $spns | Select-Object SamAccountName, adminCount, ServicePrincipalName | Out-String | Out-File $FlagFile -Append
}

$delegation = Get-ADObject -Filter {msDS-AllowedToDelegateTo -like "*" -or TrustedForDelegation -eq $true} -Properties msDS-AllowedToDelegateTo, TrustedForDelegation
$delegation | Select-Object Name, DistinguishedName, ObjectClass, TrustedForDelegation, msDS-AllowedToDelegateTo | Export-Csv (Join-Path $ADDir "Kerberos_Delegation.csv") -NoTypeInformation
if ($delegation) {
    "`n[!] KERBEROS DELEGATION DETECTED:" | Out-File $FlagFile -Append
    $delegation | Select-Object Name, TrustedForDelegation, msDS-AllowedToDelegateTo | Out-String | Out-File $FlagFile -Append
}

$rootDSE = Get-ADRootDSE
$adminSDHolderDN = "CN=AdminSDHolder,CN=System,$($rootDSE.defaultNamingContext)"
$adminSdHolderAcl = (Get-Acl -Path "AD:\$adminSDHolderDN").Access
$adminSdHolderAcl | Select-Object IdentityReference, ActiveDirectoryRights, AccessControlType, IsInherited | Export-Csv (Join-Path $ADDir "AdminSDHolder_ACL.csv") -NoTypeInformation

$badAdminSD = $adminSdHolderAcl | Where-Object {
    $_.IdentityReference -notmatch 'Domain Admins|Enterprise Admins|SYSTEM|Administrators' -and
    $_.ActiveDirectoryRights -match 'GenericAll|WriteDacl|WriteOwner'
}
if ($badAdminSD) {
    "`n[!] SUSPICIOUS RIGHTS ON ADMINSDHOLDER:" | Out-File $FlagFile -Append
    $badAdminSD | Select-Object IdentityReference, ActiveDirectoryRights | Out-String | Out-File $FlagFile -Append
}

$adminCountUsers = Get-ADUser -Filter {adminCount -eq 1} -Properties adminCount, MemberOf
$adminCountUsers | Select-Object SamAccountName, DistinguishedName, MemberOf | Export-Csv (Join-Path $ADDir "AdminCount_Users.csv") -NoTypeInformation

Get-ADServiceAccount -Filter * -Properties * |
    Select-Object Name, DNSHostName, Enabled, PrincipalsAllowedToRetrieveManagedPassword |
    Export-Csv (Join-Path $ADDir "gMSA_Accounts.csv") -NoTypeInformation

# 5. DNS Zones & Static Records
if (Get-Service -Name "DNS" -ErrorAction SilentlyContinue) {
    Write-Host "[*] Exporting DNS Zones and Records..." -ForegroundColor Yellow
    $DnsDir = Join-Path $ADDir "DNS"
    New-Item -ItemType Directory -Path $DnsDir -Force | Out-Null
    Get-DnsServerZone | ForEach-Object {
        Export-DnsServerZone -Name $_.ZoneName -FileName "$($_.ZoneName).zone.bak" -ErrorAction SilentlyContinue
    }
    Get-DnsServerZone | Where-Object { -not $_.IsAutoCreated } | ForEach-Object {
        $zName = $_.ZoneName
        Get-DnsServerResourceRecord -ZoneName $zName |
            Select-Object HostName, RecordType, RecordData, TimeToLive |
            Export-Csv (Join-Path $DnsDir "${zName}_records.csv") -NoTypeInformation
    }
}

# 6. DSRM & LDAPS
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v DsrmAdminLogonBehavior > (Join-Path $ADDir "DSRM_LogonBehavior.txt") 2>&1
$dsrm = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "DsrmAdminLogonBehavior" -ErrorAction SilentlyContinue
if ($dsrm.DsrmAdminLogonBehavior -eq 2) {
    "`n[!] DSRM LOGON BEHAVIOR SET TO 2 (PASS-THE-HASH RISK VIA DSRM OVER NETWORK)" | Out-File $FlagFile -Append
}

reg export "HKLM\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" (Join-Path $ADDir "NTDS_LDAP_Settings.reg") /y | Out-Null

Write-Host "[+] AD Backup & Anomaly Flags Completed: $ADDir" -ForegroundColor Green
