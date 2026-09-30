$isDC = (Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue).DomainRole -ge 4
$adShares = @("NETLOGON", "SYSVOL")

# ── Backup current shares ──────────────────────────────────────────────────
$backupFile = "C:\shares-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$shares = Get-SmbShare -ErrorAction SilentlyContinue
$shares | Select-Object Name, Path, Description, ScopeName | Export-Csv -Path $backupFile -NoTypeInformation
Write-Host "[+] Backed up share list to $backupFile" -ForegroundColor Green

# ── Show all shares ────────────────────────────────────────────────────────
Write-Host "`n=== SMB Shares ===" -ForegroundColor Cyan
$toRemove = @()
foreach ($s in $shares) {
    if ($s.Name -match '^\w\$$|^ADMIN\$$|^IPC\$$') {
        Write-Host "  [ADMIN] $($s.Name) -> $($s.Path)" -ForegroundColor DarkGray
        continue
    }
    if ($isDC -and $s.Name -in $adShares) {
        Write-Host "  [AD-OK] $($s.Name) -> $($s.Path)" -ForegroundColor DarkGray
        continue
    }
    $access = Get-SmbShareAccess -Name $s.Name -ErrorAction SilentlyContinue
    $perms = ($access | ForEach-Object { "$($_.AccountName):$($_.AccessRight)" }) -join ", "
    Write-Host "  [FOUND] $($s.Name) -> $($s.Path)  ($perms)" -ForegroundColor Yellow
    $toRemove += $s
}

# ── Show mapped drives ────────────────────────────────────────────────────
Write-Host "`n=== Mapped Drives ===" -ForegroundColor Cyan
$mapped = net use 2>&1 | Where-Object { $_ -match "^\s*(OK|Disconnected|Unavailable)" }
if ($mapped) {
    $mapped | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
} else {
    Write-Host "  No mapped drives" -ForegroundColor Green
}

# ── Confirm before deleting ────────────────────────────────────────────────
$totalChanges = $toRemove.Count + $(if ($mapped) { 1 } else { 0 })
if ($totalChanges -eq 0) {
    Write-Host "`n[OK] Nothing to clean up." -ForegroundColor Green
    return
}

Write-Host ""
$confirm = Read-Host "Remove $($toRemove.Count) share(s) and disconnect mapped drives? (y/n)"
if ($confirm -ne 'y') { Write-Host "  Aborted." -ForegroundColor Red; return }

foreach ($s in $toRemove) {
    try {
        Remove-SmbShare -Name $s.Name -Force -ErrorAction Stop
        Write-Host "  [REMOVED] $($s.Name)" -ForegroundColor Green
    } catch {
        Write-Host "  [FAILED] $($s.Name) — $_" -ForegroundColor Red
    }
}

if ($mapped) {
    net use * /delete /yes 2>&1 | Out-Null
    Write-Host "  [+] All mapped drives disconnected" -ForegroundColor Green
}

Write-Host "`n  Backup: $backupFile" -ForegroundColor Gray