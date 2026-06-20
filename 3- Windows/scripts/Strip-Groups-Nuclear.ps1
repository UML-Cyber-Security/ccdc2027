# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  NUCLEAR GROUP STRIP — removes ALL group memberships from every user       ║
# ║  then rebuilds only privileged groups to desired state.                     ║
# ║                                                                            ║
# ║  WARNING: This destroys custom/business groups (HR Admins, Finance, etc.)  ║
# ║  Use the surgical version in 15Min.md unless you need a full reset.        ║
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

# Which users belong in which groups
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

# Which groups should be nested in which groups
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

# ── Step 1: Backup ALL AD group memberships ──────────────────────────────────
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
Write-Host "[+] Backed up current state to $backupFile" -ForegroundColor Green

# ── Step 2: Strip ALL group memberships from every user (except excluded) ────
$skipUsers = @($excludeUsers) + @($ourUsers) + @("krbtgt")
$allUsers = @(Get-ADUser -Filter * -Properties MemberOf | Where-Object { $_.SamAccountName -notin $skipUsers -and $_.MemberOf })

Write-Host "`n=== PHASE 1: STRIP all group memberships ===" -ForegroundColor Cyan
Write-Host "  Protected users: $($skipUsers -join ', ')" -ForegroundColor Green
foreach ($u in $allUsers) {
    $groups = ($u.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace 'CN=' } | Where-Object {
        $_ -ne 'Remote Desktop Users' -and -not ($u.SamAccountName -eq 'Administrator' -and $_ -eq 'Administrators')
    }) -join ', '
    if ($groups) { Write-Host "  $($u.SamAccountName) — $groups" -ForegroundColor Yellow }
}

# ── Step 3: Dry run — privileged group changes ───────────────────────────────
$toRemove = @()
$toAdd    = @()

foreach ($groupName in ($defaultUsers.Keys + $defaultGroupNesting.Keys | Sort-Object -Unique)) {
    try { $currentMembers = @(Get-ADGroupMember -Identity $groupName -ErrorAction Stop) } catch { continue }

    $allowedUsers  = if ($defaultUsers.ContainsKey($groupName))        { $defaultUsers[$groupName] }        else { @() }
    $allowedGroups = if ($defaultGroupNesting.ContainsKey($groupName)) { $defaultGroupNesting[$groupName] } else { @() }

    foreach ($m in $currentMembers) {
        if ($m.objectClass -eq 'group' -and $m.SamAccountName -notin $allowedGroups -and $m.Name -notin $allowedGroups) {
            $toRemove += [PSCustomObject]@{ Group=$groupName; Member=$m.Name; Type='group'; DN=$m.distinguishedName }
        }
    }

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

Write-Host "`n=== PHASE 2: PRIVILEGED GROUP CHANGES ===" -ForegroundColor Cyan
Write-Host "  Groups to fix: $($toRemove.Count) removals, $($toAdd.Count) additions" -ForegroundColor Yellow
foreach ($r in $toRemove) { Write-Host "  REMOVE [$($r.Type)] $($r.Member) from $($r.Group)" -ForegroundColor Yellow }
foreach ($a in $toAdd)    { Write-Host "  ADD    [$($a.Type)] $($a.Member) to $($a.Group)" -ForegroundColor Cyan }

if ($allUsers.Count -eq 0 -and $toRemove.Count -eq 0 -and $toAdd.Count -eq 0) {
    Write-Host "`n[OK] Everything already matches desired state." -ForegroundColor Green
    return
}

Write-Host ""
$confirm = Read-Host "Proceed? (y/n)"
if ($confirm -ne 'y') { Write-Host "  Aborted." -ForegroundColor Red; return }

# ── Step 4: Execute strip ────────────────────────────────────────────────────
$groupMap = @{}
foreach ($u in $allUsers) {
    foreach ($g in $u.MemberOf) {
        $gName = ($g -split ',')[0] -replace 'CN='
        if ($gName -eq 'Remote Desktop Users') { continue }
        if (-not $groupMap[$g]) { $groupMap[$g] = @() }; $groupMap[$g] += $u.SamAccountName
    }
}
foreach ($g in @($groupMap.Keys)) {
    $name = ($g -split ',')[0] -replace 'CN='
    # Skip built-in groups that won't allow removal of built-in accounts
    $groupMap[$g] = @($groupMap[$g] | Where-Object { -not ($_ -eq 'Administrator' -and $name -eq 'Administrators') })
    if ($groupMap[$g].Count -eq 0) { continue }
    try {
        Remove-ADGroupMember -Identity $g -Members $groupMap[$g] -Confirm:$false
        Write-Host "  STRIPPED $name — removed: $($groupMap[$g] -join ', ')" -ForegroundColor Green
    } catch {
        Write-Host "  FAILED to strip ${name}: $($_)" -ForegroundColor Red
    }
}

# ── Step 5: Execute privileged group removals ────────────────────────────────
foreach ($r in $toRemove) {
    try {
        Remove-ADGroupMember -Identity $r.Group -Members $r.DN -Confirm:$false
        Write-Host "  REMOVED [$($r.Type)] $($r.Member) from $($r.Group)" -ForegroundColor Green
    } catch {
        Write-Host "  FAILED to remove $($r.Member) from $($r.Group): $_" -ForegroundColor Red
    }
}

# ── Step 6: Execute privileged group additions (rebuild desired state) ───────
foreach ($a in $toAdd) {
    try {
        Add-ADGroupMember -Identity $a.Group -Members $a.Member -ErrorAction Stop
        Write-Host "  ADDED [$($a.Type)] $($a.Member) to $($a.Group)" -ForegroundColor Green
    } catch {
        Write-Host "  FAILED to add $($a.Member) to $($a.Group): $_" -ForegroundColor Red
    }
}

# ── Step 7: Add de-privileged users to Remote Desktop Users ─────────────────
Write-Host "`n=== REMOTE DESKTOP ACCESS ===" -ForegroundColor Cyan
foreach ($u in $allUsers) {
    try {
        Add-ADGroupMember -Identity "Remote Desktop Users" -Members $u.SamAccountName -ErrorAction Stop
        Write-Host "  ADDED $($u.SamAccountName) to Remote Desktop Users" -ForegroundColor Green
    } catch {
        if ($_.Exception.Message -match "already a member") {
            Write-Host "  OK $($u.SamAccountName) already in Remote Desktop Users" -ForegroundColor Gray
        } else {
            Write-Host "  FAILED to add $($u.SamAccountName) to Remote Desktop Users: $_" -ForegroundColor Red
        }
    }
}

Write-Host "`n  Done. Backup: $backupFile" -ForegroundColor Cyan
