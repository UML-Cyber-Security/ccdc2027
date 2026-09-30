# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  SURGICAL GROUP & GPO CLEANUP                                              ║
# ║  - Only touches privileged groups (Domain Admins, Enterprise Admins, etc.) ║
# ║  - Leaves custom/business groups alone (HR Admins, Finance, etc.)          ║
# ║  - Unlinks (does NOT delete) non-default GPOs for manual review            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Our team users — added to all privileged groups
$ourUsers = @(

)

# Users to NEVER remove from any group (e.g. scoring accounts, service accounts)
$excludeUsers = @(
    "blackteam"
    "black-team"
    "krbtgt"
)

# ── Privileged groups: who belongs and who doesn't ───────────────────────────

# Which users belong in which privileged groups
$defaultUsers = @{
    "Domain Admins"          = $ourUsers
    "Enterprise Admins"      = $ourUsers
    "Schema Admins"          = $ourUsers
    "Administrators"         = $ourUsers
    "Group Policy Creator Owners" = $ourUsers
    "Server Operators"       = @()
    "Account Operators"      = @()
    "Backup Operators"       = @()
    "Print Operators"        = @()
    "DnsAdmins"              = @()
    "Denied RODC Password Replication Group" = @("krbtgt")
}

# Which groups should be nested in which privileged groups
$defaultGroupNesting = @{
    "Administrators" = @()
    "Denied RODC Password Replication Group" = @(
        "Domain Admins", "Enterprise Admins", "Schema Admins",
        "Read-only Domain Controllers", "Domain Controllers",
        "Cert Publishers", "Group Policy Creator Owners"
    )
    "Group Policy Creator Owners" = @()
    "Schema Admins"          = @()
    "Domain Admins"          = @()
    "Enterprise Admins"      = @()
    "Server Operators"       = @()
    "Account Operators"      = @()
    "Backup Operators"       = @()
    "Print Operators"        = @()
}

# GPOs that should stay linked (everything else gets unlinked, not deleted)
$allowedGPOs = @(
    "Default Domain Policy"
    "Default Domain Controllers Policy"
    "Hardening"
)

$DomainDN = (Get-ADDomain).DistinguishedName
$skipUsers = @($excludeUsers) + @($ourUsers) + @("krbtgt")

# ── Step 0: Create our users if they don't exist ─────────────────────────────
foreach ($u in $ourUsers) {
    try {
        Get-ADUser -Identity $u -ErrorAction Stop | Out-Null
    } catch {
        $cred = Get-Credential -UserName $u -Message "Set password for new AD user: $u"
        New-ADUser -Name $u -SamAccountName $u -AccountPassword $cred.Password -Enabled $true -PasswordNeverExpires $false -ChangePasswordAtLogon $false
        Write-Host "  CREATED user $u" -ForegroundColor Green
    }
}

# ── Step 1: Backup ALL group memberships + GPO link state ────────────────────
$backupFile = "C:\ad-groups-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$backupRows = @()
foreach ($group in (Get-ADGroup -Filter *)) {
    try {
        $members = Get-ADGroupMember -Identity $group -ErrorAction Stop
        foreach ($m in $members) {
            $backupRows += [PSCustomObject]@{
                Group      = $group.Name
                Member     = $m.SamAccountName
                MemberType = $m.objectClass
                MemberDN   = $m.distinguishedName
            }
        }
    } catch {}
}
$backupRows | Export-Csv -Path $backupFile -NoTypeInformation
Write-Host "[+] Backed up group memberships to $backupFile" -ForegroundColor Green

$gpoBackupFile = "C:\gpo-links-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$gpoRows = @()
foreach ($ou in (Get-ADOrganizationalUnit -Filter * | Select-Object -ExpandProperty DistinguishedName)) {
    try {
        $links = (Get-GPInheritance -Target $ou).GpoLinks
        foreach ($link in $links) {
            $gpoRows += [PSCustomObject]@{
                Target    = $ou
                GPOName   = $link.DisplayName
                Enabled   = $link.Enabled
                Enforced  = $link.Enforced
                Order     = $link.Order
            }
        }
    } catch {}
}
# Also capture domain-level links
$domainLinks = (Get-GPInheritance -Target $DomainDN).GpoLinks
foreach ($link in $domainLinks) {
    $gpoRows += [PSCustomObject]@{
        Target    = $DomainDN
        GPOName   = $link.DisplayName
        Enabled   = $link.Enabled
        Enforced  = $link.Enforced
        Order     = $link.Order
    }
}
$gpoRows | Export-Csv -Path $gpoBackupFile -NoTypeInformation
Write-Host "[+] Backed up GPO link state to $gpoBackupFile" -ForegroundColor Green

# ── Step 2: Audit privileged groups (ONLY these — custom groups untouched) ───
$toRemoveUsers  = @()
$toRemoveGroups = @()
$toAdd          = @()

foreach ($groupName in ($defaultUsers.Keys + $defaultGroupNesting.Keys | Sort-Object -Unique)) {
    try { $currentMembers = @(Get-ADGroupMember -Identity $groupName -ErrorAction Stop) } catch { continue }

    $allowedUsers  = if ($defaultUsers.ContainsKey($groupName))        { $defaultUsers[$groupName] }        else { @() }
    $allowedGroups = if ($defaultGroupNesting.ContainsKey($groupName)) { $defaultGroupNesting[$groupName] } else { @() }

    # Find unauthorized users in privileged groups
    foreach ($m in $currentMembers) {
        if ($m.objectClass -eq 'user' -and $m.SamAccountName -notin $allowedUsers -and $m.SamAccountName -notin $skipUsers) {
            $toRemoveUsers += [PSCustomObject]@{ Group=$groupName; Member=$m.SamAccountName; DN=$m.distinguishedName }
        }
        if ($m.objectClass -eq 'group' -and $m.SamAccountName -notin $allowedGroups -and $m.Name -notin $allowedGroups) {
            $toRemoveGroups += [PSCustomObject]@{ Group=$groupName; Member=$m.Name; DN=$m.distinguishedName }
        }
    }

    # Find missing members that should be added
    $currentGroupNames = $currentMembers | Where-Object { $_.objectClass -eq 'group' } | ForEach-Object { $_.Name }
    foreach ($g in $allowedGroups) {
        if ($g -notin $currentGroupNames) {
            $toAdd += [PSCustomObject]@{ Group=$groupName; Member=$g; Type='group' }
        }
    }
    $currentNames = $currentMembers | ForEach-Object { $_.SamAccountName }
    foreach ($u in $allowedUsers) {
        if ($u -notin $currentNames) {
            $toAdd += [PSCustomObject]@{ Group=$groupName; Member=$u; Type='user' }
        }
    }
}

# ── Step 3: Find GPOs to unlink ──────────────────────────────────────────────
$gpoTargets = @($DomainDN) + @(Get-ADOrganizationalUnit -Filter * | Select-Object -ExpandProperty DistinguishedName)
$toUnlink = @()
foreach ($target in $gpoTargets) {
    try {
        $links = (Get-GPInheritance -Target $target).GpoLinks
        foreach ($link in $links) {
            if ($link.DisplayName -notin $allowedGPOs -and $link.Enabled -eq "Yes") {
                $toUnlink += [PSCustomObject]@{ Target=$target; GPOName=$link.DisplayName }
            }
        }
    } catch {}
}

# ── Step 4: Show dry run ─────────────────────────────────────────────────────
Write-Host "`n=== PRIVILEGED GROUP CHANGES ===" -ForegroundColor Cyan
if ($toRemoveUsers.Count -eq 0 -and $toRemoveGroups.Count -eq 0 -and $toAdd.Count -eq 0) {
    Write-Host "  Privileged groups already clean." -ForegroundColor Green
} else {
    foreach ($r in $toRemoveUsers)  { Write-Host "  REMOVE [user]  $($r.Member) from $($r.Group)" -ForegroundColor Yellow }
    foreach ($r in $toRemoveGroups) { Write-Host "  REMOVE [group] $($r.Member) from $($r.Group)" -ForegroundColor Yellow }
    foreach ($a in $toAdd)          { Write-Host "  ADD    [$($a.Type)] $($a.Member) to $($a.Group)" -ForegroundColor Cyan }
}

Write-Host "`n=== GPO UNLINK (not delete) ===" -ForegroundColor Cyan
if ($toUnlink.Count -eq 0) {
    Write-Host "  No non-default GPOs linked." -ForegroundColor Green
} else {
    foreach ($u in $toUnlink) { Write-Host "  UNLINK '$($u.GPOName)' from $($u.Target)" -ForegroundColor Yellow }
    Write-Host "  (GPOs will NOT be deleted — review in gpmc.msc)" -ForegroundColor Gray
}

$totalChanges = $toRemoveUsers.Count + $toRemoveGroups.Count + $toAdd.Count + $toUnlink.Count
if ($totalChanges -eq 0) {
    Write-Host "`n[OK] Everything already matches desired state." -ForegroundColor Green
    return
}

Write-Host ""
$confirm = Read-Host "Proceed? (y/n)"
if ($confirm -ne 'y') { Write-Host "  Aborted." -ForegroundColor Red; return }

# ── Step 5: Execute privileged group removals ────────────────────────────────
foreach ($r in ($toRemoveUsers + $toRemoveGroups)) {
    try {
        Remove-ADGroupMember -Identity $r.Group -Members $r.DN -Confirm:$false
        Write-Host "  REMOVED $($r.Member) from $($r.Group)" -ForegroundColor Green
    } catch {
        Write-Host "  FAILED to remove $($r.Member) from $($r.Group): $_" -ForegroundColor Red
    }
}

# ── Step 6: Execute privileged group additions ───────────────────────────────
foreach ($a in $toAdd) {
    try {
        Add-ADGroupMember -Identity $a.Group -Members $a.Member -ErrorAction Stop
        Write-Host "  ADDED [$($a.Type)] $($a.Member) to $($a.Group)" -ForegroundColor Green
    } catch {
        Write-Host "  FAILED to add $($a.Member) to $($a.Group): $_" -ForegroundColor Red
    }
}

# ── Step 7: Unlink non-default GPOs (disable link, do NOT delete) ────────────
foreach ($u in $toUnlink) {
    try {
        Set-GPLink -Name $u.GPOName -Target $u.Target -LinkEnabled No -ErrorAction Stop
        Write-Host "  UNLINKED '$($u.GPOName)' from $($u.Target)" -ForegroundColor Green
    } catch {
        Write-Host "  FAILED to unlink '$($u.GPOName)': $_" -ForegroundColor Red
    }
}

# ── Step 8: Add de-privileged users to Remote Desktop Users ─────────────────
Write-Host "`n=== REMOTE DESKTOP ACCESS ===" -ForegroundColor Cyan
foreach ($r in $toRemoveUsers) {
    if ($r.Group -in @("Domain Admins","Administrators","Enterprise Admins")) {
        try {
            Add-ADGroupMember -Identity "Remote Desktop Users" -Members $r.Member -ErrorAction Stop
            Write-Host "  ADDED $($r.Member) to Remote Desktop Users (was in $($r.Group))" -ForegroundColor Green
        } catch {
            if ($_.Exception.Message -match "already a member") {
                Write-Host "  OK $($r.Member) already in Remote Desktop Users" -ForegroundColor Gray
            } else {
                Write-Host "  FAILED to add $($r.Member) to Remote Desktop Users: $_" -ForegroundColor Red
            }
        }
    }
}

Write-Host "`n  Done. Backups:" -ForegroundColor Cyan
Write-Host "    Groups: $backupFile" -ForegroundColor Gray
Write-Host "    GPOs:   $gpoBackupFile" -ForegroundColor Gray
Write-Host "    Review unlinked GPOs in gpmc.msc — delete manually if malicious" -ForegroundColor Gray