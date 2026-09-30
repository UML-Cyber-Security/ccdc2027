Set-StrictMode -Off

# ── Phase 0: Preflight checks ────────────────────────────────────────────────
Write-Host "=== Preflight ===" -ForegroundColor Cyan

# Binaries exist?
# WinDefend service exists?
$defSvc = Get-Service WinDefend -ErrorAction SilentlyContinue
if (-not $defSvc) {
    Write-Host "  WinDefend service:       MISSING" -ForegroundColor Red
    Write-Host ""
    Write-Host "[!] Defender is not installed. Run these manually (slow, may impact services):" -ForegroundColor Red
    Write-Host "      Install-WindowsFeature -Name Windows-Defender -IncludeManagementTools  # Server only" -ForegroundColor Yellow
    Write-Host "      sfc /scannow" -ForegroundColor Yellow
    Write-Host "      DISM /Online /Cleanup-Image /RestoreHealth" -ForegroundColor Yellow
    Write-Host "    Then re-run this script." -ForegroundColor Red
    Write-Host ""
    return
}
Write-Host "  WinDefend service:       Present ($($defSvc.Status))" -ForegroundColor $(if($defSvc.Status -eq 'Running'){'Green'}else{'Yellow'})

# Engine binary exists? (check actual path from service, not hardcoded)
$imgPath = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend" -Name ImagePath -EA SilentlyContinue).ImagePath -replace '"',''
$engExists = $imgPath -and (Test-Path $imgPath)
Write-Host "  Engine binary:           $(if($engExists){'OK'}else{'MISSING'}) ($imgPath)" -ForegroundColor $(if($engExists){'Green'}else{'Red'})
if (-not $engExists) {
    Write-Host ""
    Write-Host "[!] Defender binary missing or corrupted. Run these manually (slow, may impact services):" -ForegroundColor Red
    Write-Host "      sfc /scannow" -ForegroundColor Yellow
    Write-Host "      DISM /Online /Cleanup-Image /RestoreHealth" -ForegroundColor Yellow
    Write-Host "    Then re-run this script." -ForegroundColor Red
    Write-Host ""
    return
}

# Feature installed? (Server only — silently skips on workstations)
$feat = Get-WindowsFeature -Name Windows-Defender* -ErrorAction SilentlyContinue
if ($feat -and $feat.InstallState -ne 'Installed') {
    Write-Host "  Windows-Defender feature: $($feat.InstallState)" -ForegroundColor Red
    Write-Host ""
    Write-Host "[!] Defender feature not installed. Run manually (may require reboot):" -ForegroundColor Red
    Write-Host "      Install-WindowsFeature -Name Windows-Defender -IncludeManagementTools" -ForegroundColor Yellow
    Write-Host "    Then re-run this script." -ForegroundColor Red
    Write-Host ""
    return
} elseif ($feat) {
    Write-Host "  Windows-Defender feature: $($feat.InstallState)" -ForegroundColor Green
}

# Services
foreach ($sn in @("WinDefend","WdNisSvc")) {
    $st = (sc.exe query $sn 2>&1 | Select-String "STATE").ToString().Trim()
    Write-Host "  ${sn}: $st" -ForegroundColor $(if($st -match 'RUNNING'){'Green'}else{'Yellow'})
}

# Drivers
foreach ($dn in @("WdFilter","WdBoot","WdNisDrv")) {
    $dv = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$dn" -Name Start -EA SilentlyContinue).Start
    $disabled = $dv -eq 4
    Write-Host "  Driver ${dn}: Start=$dv$(if($disabled){' (DISABLED)'})" -ForegroundColor $(if($disabled){'Red'}else{'Green'})
}

# Policy disable flags
$polDis = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -EA SilentlyContinue).DisableAntiSpyware
$locDis = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows Defender" -EA SilentlyContinue).DisableAntiSpyware
if ($polDis -eq 1) { Write-Host "  [!] Policy DisableAntiSpyware = 1 (will fix)" -ForegroundColor Red }
if ($locDis -eq 1) { Write-Host "  [!] Local DisableAntiSpyware = 1 (will fix)" -ForegroundColor Red }

# Exclusions planted
$mp = Get-MpPreference -ErrorAction SilentlyContinue
$exTotal = (@("ExclusionPath","ExclusionProcess","ExclusionExtension","ExclusionIpAddress") | ForEach-Object { $p = $mp.PSObject.Properties[$_]; if ($p) { $p.Value } } | Where-Object { $_ }).Count
Write-Host "  Exclusions planted:      $exTotal" -ForegroundColor $(if($exTotal -eq 0){'Green'}else{'Red'})

# Early exit if Defender is already fully operational
$preCheck = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($preCheck -and $preCheck.AMServiceEnabled -and $preCheck.RealTimeProtectionEnabled -and $preCheck.BehaviorMonitorEnabled -and $exTotal -eq 0) {
    Write-Host ""
    Write-Host "[OK] Defender is already fully operational — nothing to fix" -ForegroundColor Green
    return
}

Write-Host ""

# ── Phase 1: Fix red team sabotage that prevents Defender from starting ──────

# 1a. Reset ACLs on Defender service keys (red team often locks these out)
# Strategy: try gentle Get-Acl first (preserves existing ACEs like TrustedInstaller),
# fall back to nuclear New-Object only if red team locked us out completely.
$svcKeys = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend",
    "HKLM:\SYSTEM\CurrentControlSet\Services\WdNisSvc",
    "HKLM:\SYSTEM\CurrentControlSet\Services\WdFilter",
    "HKLM:\SYSTEM\CurrentControlSet\Services\WdNisDrv",
    "HKLM:\SYSTEM\CurrentControlSet\Services\WdBoot",
    "HKLM:\SYSTEM\CurrentControlSet\Services\SecurityHealthService",
    "HKLM:\SYSTEM\CurrentControlSet\Services\wscsvc"
)

# Helper: build the "nuclear" ACL that matches Windows defaults for service keys
function New-DefenderServiceAcl {
    $acl = New-Object System.Security.AccessControl.RegistrySecurity
    # Not protected — inherits from parent (HKLM:\SYSTEM\CurrentControlSet\Services)
    $acl.SetAccessRuleProtection($false, $true)
    # Owner = SYSTEM (matches default)
    $acl.SetOwner([System.Security.Principal.NTAccount]"NT AUTHORITY\SYSTEM")

    $rules = @(
        # SYSTEM — FullControl (default)
        @("NT AUTHORITY\SYSTEM",          "FullControl",
          "ContainerInherit,ObjectInherit", "None", "Allow"),
        # Administrators — FullControl (default)
        @("BUILTIN\Administrators",       "FullControl",
          "ContainerInherit,ObjectInherit", "None", "Allow"),
        # TrustedInstaller — FullControl (default — owns these keys, needed for servicing)
        @("NT SERVICE\TrustedInstaller",  "FullControl",
          "ContainerInherit,ObjectInherit", "None", "Allow"),
        # CREATOR OWNER — FullControl on subkeys only (standard default)
        @("CREATOR OWNER",                "FullControl",
          "ContainerInherit,ObjectInherit", "InheritOnly", "Allow"),
        # Users — Read (standard default)
        @("BUILTIN\Users",                "ReadKey",
          "ContainerInherit,ObjectInherit", "None", "Allow"),
        # ALL APPLICATION PACKAGES — Read (default, needed for AppContainer sandboxes)
        @("APPLICATION PACKAGE AUTHORITY\ALL APPLICATION PACKAGES", "ReadKey",
          "ContainerInherit,ObjectInherit", "None", "Allow"),
        # ALL RESTRICTED APP PACKAGES — Read (default on RS3+, safe no-op on older)
        @("APPLICATION PACKAGE AUTHORITY\ALL RESTRICTED APPLICATION PACKAGES", "ReadKey",
          "ContainerInherit,ObjectInherit", "None", "Allow")
    )
    foreach ($r in $rules) {
        try {
            $ace = New-Object System.Security.AccessControl.RegistryAccessRule(
                $r[0], $r[1], $r[2], $r[3], $r[4])
            $acl.AddAccessRule($ace)
        } catch {
            # ALL RESTRICTED APPLICATION PACKAGES may not exist on Server 2012 R2; skip safely
            Write-Host "    [i] Skipped ACE for $($r[0]) (SID not found on this OS)" -ForegroundColor DarkGray
        }
    }
    return $acl
}

foreach ($key in $svcKeys) {
    if (-not (Test-Path $key)) { continue }
    $keyName = ($key -split '\\')[-1]

    # ── Attempt 1: Gentle — read existing ACL, add SYSTEM+Admins if missing ──
    $gentle = $false
    try {
        $acl = Get-Acl -Path $key -ErrorAction Stop

        # Ensure inheritance is enabled (red team may have disabled it)
        if ($acl.AreAccessRulesProtected) {
            $acl.SetAccessRuleProtection($false, $true)
            Write-Host "    [~] $keyName : re-enabled ACL inheritance" -ForegroundColor Cyan
        }

        # Add SYSTEM FullControl if missing
        $hasSystem = $acl.Access | Where-Object {
            $_.IdentityReference -eq "NT AUTHORITY\SYSTEM" -and
            $_.RegistryRights -band [System.Security.AccessControl.RegistryRights]::FullControl }
        if (-not $hasSystem) {
            $acl.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule(
                "NT AUTHORITY\SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
            Write-Host "    [~] $keyName : added SYSTEM FullControl" -ForegroundColor Cyan
        }

        # Add Administrators FullControl if missing
        $hasAdmin = $acl.Access | Where-Object {
            $_.IdentityReference -eq "BUILTIN\Administrators" -and
            $_.RegistryRights -band [System.Security.AccessControl.RegistryRights]::FullControl }
        if (-not $hasAdmin) {
            $acl.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule(
                "BUILTIN\Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
            Write-Host "    [~] $keyName : added Administrators FullControl" -ForegroundColor Cyan
        }

        # Add TrustedInstaller FullControl if missing
        $hasTI = $acl.Access | Where-Object {
            $_.IdentityReference -eq "NT SERVICE\TrustedInstaller" -and
            $_.RegistryRights -band [System.Security.AccessControl.RegistryRights]::FullControl }
        if (-not $hasTI) {
            try {
                $acl.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule(
                    "NT SERVICE\TrustedInstaller","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
                Write-Host "    [~] $keyName : added TrustedInstaller FullControl" -ForegroundColor Cyan
            } catch { }  # TI SID resolution may fail on some editions
        }

        # Remove any explicit Deny rules (red team plants these to block SYSTEM/Admins)
        $denyRules = $acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' }
        foreach ($deny in $denyRules) {
            $acl.RemoveAccessRule($deny) | Out-Null
            Write-Host "    [!] $keyName : removed Deny rule for $($deny.IdentityReference)" -ForegroundColor Yellow
        }

        Set-Acl -Path $key -AclObject $acl -ErrorAction Stop
        $gentle = $true
        Write-Host "[+] $keyName — ACL verified/repaired (gentle)" -ForegroundColor Green

    } catch {
        Write-Host "[-] $keyName — Get-Acl failed ($($_.Exception.Message)), trying nuclear reset..." -ForegroundColor Yellow
    }

    # ── Attempt 2: Nuclear — red team locked ACL so hard we can't read it ──
    if (-not $gentle) {
        try {
            # Take ownership first (required if even Administrators have no access)
            $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                ($key -replace '^HKLM:\\','').Replace('\','\'),
                [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                [System.Security.AccessControl.RegistryRights]::TakeOwnership)
            if ($regKey) {
                $blank = New-Object System.Security.AccessControl.RegistrySecurity
                $blank.SetOwner([System.Security.Principal.NTAccount]"BUILTIN\Administrators")
                $regKey.SetAccessControl($blank)
                $regKey.Close()
            }

            # Now re-open with ChangePermissions and apply full default ACL
            $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                ($key -replace '^HKLM:\\','').Replace('\','\'),
                [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                [System.Security.AccessControl.RegistryRights]::ChangePermissions)
            if ($regKey) {
                $nuclearAcl = New-DefenderServiceAcl
                $regKey.SetAccessControl($nuclearAcl)
                $regKey.Close()
                Write-Host "[+] $keyName — ACL rebuilt from scratch (nuclear)" -ForegroundColor Green
            } else {
                Write-Host "[X] $keyName — could not open key even for TakeOwnership" -ForegroundColor Red
            }
        } catch {
            Write-Host "[X] $keyName — nuclear ACL reset failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# 1b. Re-enable Defender drivers red team may have disabled (Start=4 means disabled)
# SAFETY: A corrupt/missing boot-start driver (Start=0) = BSOD on reboot.
# We verify binary existence + Microsoft Authenticode signature before touching Start values.
$drivers = @{ "WdFilter" = 0; "WdNisDrv" = 3; "WdBoot" = 0 }
foreach ($drv in $drivers.GetEnumerator()) {
    $svcPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($drv.Key)"

    if (-not (Test-Path $svcPath)) {
        Write-Host "  [i] $($drv.Key) service key missing — skipping" -ForegroundColor Gray
        continue
    }

    $curStart = (Get-ItemProperty $svcPath -Name Start -ErrorAction SilentlyContinue).Start
    if ($curStart -ne 4) {
        Write-Host "  [i] $($drv.Key) Start=$curStart (not disabled) — no change needed" -ForegroundColor Gray
        continue
    }

    # Resolve driver binary path from ImagePath registry value
    $rawImagePath = (Get-ItemProperty $svcPath -Name ImagePath -ErrorAction SilentlyContinue).ImagePath
    if (-not $rawImagePath) {
        Write-Host "  [X] $($drv.Key) has no ImagePath — SKIPPING (cannot verify binary)" -ForegroundColor Red
        Write-Host "      ACTION: Manually inspect HKLM\SYSTEM\CurrentControlSet\Services\$($drv.Key)" -ForegroundColor Red
        continue
    }
    $binaryPath = $rawImagePath -replace '(?i)^\\SystemRoot\\', "$env:SystemRoot\"
    $binaryPath = $binaryPath -replace '(?i)^system32\\', "$env:SystemRoot\System32\"
    $binaryPath = $binaryPath -replace '(?i)^\\\?\?\\', ''
    if ($binaryPath -match '^"([^"]+)"') { $binaryPath = $Matches[1] }

    # Check binary exists
    if (-not (Test-Path $binaryPath)) {
        Write-Host "  [X] $($drv.Key) BINARY MISSING: $binaryPath" -ForegroundColor Red
        Write-Host "      DANGER: Re-enabling would cause BSOD on reboot!" -ForegroundColor Red
        Write-Host "      ACTION: Restore binary (sfc /scannow or DISM), then re-run." -ForegroundColor Red
        continue
    }

    # Check Authenticode signature — must be valid AND signed by Microsoft
    $sig = Get-AuthenticodeSignature -FilePath $binaryPath -ErrorAction SilentlyContinue
    $sigOk = $false
    if ($sig -and $sig.Status -eq 'Valid') {
        if ($sig.SignerCertificate.Subject -match 'O=Microsoft Corporation') {
            $sigOk = $true
        } else {
            Write-Host "  [X] $($drv.Key) signed but NOT by Microsoft: $($sig.SignerCertificate.Subject)" -ForegroundColor Red
            Write-Host "      DANGER: Binary may have been replaced by attacker." -ForegroundColor Red
            Write-Host "      ACTION: Investigate and restore from known-good source." -ForegroundColor Red
            continue
        }
    }
    if (-not $sigOk) {
        $statusText = if ($sig) { $sig.Status } else { "No signature data" }
        Write-Host "  [X] $($drv.Key) signature FAILED: $statusText" -ForegroundColor Red
        Write-Host "      Binary: $binaryPath" -ForegroundColor Red
        Write-Host "      DANGER: Re-enabling a tampered boot-start driver causes BSOD!" -ForegroundColor Red
        Write-Host "      ACTION: Restore binary (sfc /scannow or DISM), then re-run." -ForegroundColor Red
        continue
    }

    # Sanity: reject suspiciously small files
    $fileSize = (Get-Item $binaryPath).Length
    if ($fileSize -lt 1024) {
        Write-Host "  [X] $($drv.Key) binary is only $fileSize bytes — suspiciously small" -ForegroundColor Red
        Write-Host "      ACTION: Investigate before re-enabling." -ForegroundColor Red
        continue
    }

    # All checks passed — safe to re-enable
    try {
        Set-ItemProperty $svcPath -Name Start -Value $drv.Value -ErrorAction Stop
        Write-Host "[+] Re-enabled $($drv.Key) (Start: 4 -> $($drv.Value)) — binary verified OK" -ForegroundColor Green
        Write-Host "    Binary: $binaryPath ($fileSize bytes, Microsoft-signed)" -ForegroundColor Green
        Write-Host "    NOTE: REBOOT REQUIRED for driver changes to take effect." -ForegroundColor Yellow
    } catch {
        Write-Host "[X] Failed to set Start value for $($drv.Key): $_" -ForegroundColor Red
    }
}

# 1c. Re-enable all Defender-related services (with third-party AV guard)
$thirdPartyAV = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct -ErrorAction SilentlyContinue |
    Where-Object { $_.displayName -notmatch 'Windows Defender|Microsoft Defender' }
$services = @("WinDefend", "WdNisSvc", "SecurityHealthService", "wscsvc")
if ($thirdPartyAV) {
    Write-Host "[!] Third-party AV detected — skipping Defender service auto-enable:" -ForegroundColor Yellow
    $thirdPartyAV | ForEach-Object { Write-Host "      $($_.displayName)" -ForegroundColor Yellow }
    Write-Host "    Enabling Defender alongside another AV causes driver conflicts and high CPU." -ForegroundColor Yellow
    Write-Host "    Remove the third-party AV first, then re-run this script." -ForegroundColor Yellow
} else {
    foreach ($svc in $services) {
        $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if (-not $svcObj) {
            Write-Host "  [-] Service $svc does not exist on this machine — skipped" -ForegroundColor Gray
            continue
        }
        $startType = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$svc" -Name Start -EA SilentlyContinue).Start
        if ($startType -eq 2) {
            Write-Host "  [+] $svc already set to auto-start" -ForegroundColor Green
        } else {
            $scOut = sc.exe config $svc start= auto 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [+] $svc set to auto-start" -ForegroundColor Green
            } else {
                Write-Host "  [-] Failed to set $svc to auto-start: $scOut" -ForegroundColor Red
            }
        }
    }
}

# 1d. Remove local registry keys that disable Defender outside of GPO
# Detect Tamper Protection state first — if active, direct registry writes are blocked
$tamperStatus = (Get-MpComputerStatus -ErrorAction SilentlyContinue).IsTamperProtected
if ($tamperStatus) {
    Write-Host "  [i] Tamper Protection is ON — registry writes may be blocked (that's good, it means" -ForegroundColor Cyan
    Write-Host "      Defender is protecting itself). Flags set via policy/MpPreference will still work." -ForegroundColor Cyan
}
$disableKeys = @(
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows Defender"; Name = "DisableAntiSpyware" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows Defender"; Name = "DisableAntiVirus" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"; Name = "DisableRealtimeMonitoring" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection"; Name = "DisableBehaviorMonitoring" }
)
$flagsFound = 0; $flagsCleared = 0; $flagsFailed = 0
foreach ($entry in $disableKeys) {
    $val = Get-ItemProperty -Path $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
    if ($null -ne $val -and $val.($entry.Name) -eq 1) {
        $flagsFound++
        Write-Host "  [!] Found $($entry.Name) = 1 at $($entry.Path)" -ForegroundColor Yellow
        try {
            Remove-ItemProperty -Path $entry.Path -Name $entry.Name -ErrorAction Stop
            # Verify removal
            $check = Get-ItemProperty -Path $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
            if ($null -eq $check -or $check.($entry.Name) -eq $null) {
                $flagsCleared++
                Write-Host "      Removed successfully" -ForegroundColor Green
            } else {
                $flagsFailed++
                Write-Host "      Remove-ItemProperty returned success but value persists (Tamper Protection?)" -ForegroundColor Red
            }
        } catch {
            $flagsFailed++
            Write-Host "      Failed to remove: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
if ($flagsFound -eq 0) {
    Write-Host "[+] No local disable flags found (clean)" -ForegroundColor Green
} elseif ($flagsFailed -eq 0) {
    Write-Host "[+] Cleared $flagsCleared/$flagsFound local disable flags" -ForegroundColor Green
} else {
    Write-Host "[-] Cleared $flagsCleared/$flagsFound flags; $flagsFailed failed (Tamper Protection may be blocking — try Set-MpPreference instead)" -ForegroundColor Red
}

# 1e. Boot integrity check (ADVISORY — never auto-change, boot failure risk)
# If disableintegritycheck is set and unsigned boot drivers exist, removing it = BSOD.
# We scan, report, and tell the operator what to do — but do NOT change BCD automatically.
Write-Host "`n--- Boot Integrity Check ---" -ForegroundColor Cyan
$bcdOutput = bcdedit /enum "{current}" 2>&1 | Out-String
$integrityDisabled = $bcdOutput -match 'disableintegritychecks\s+Yes'
$testsigningOn     = $bcdOutput -match 'testsigning\s+Yes'

if ($integrityDisabled) {
    Write-Host "[!] BOOT INTEGRITY CHECKS ARE DISABLED (disableintegritychecks=Yes)" -ForegroundColor Red
    Write-Host "    This may be attacker sabotage OR required for unsigned drivers." -ForegroundColor Yellow

    # Scan boot-start drivers for unsigned binaries to help operator decide
    Write-Host "    Scanning boot-start drivers for unsigned binaries..." -ForegroundColor Yellow
    $unsignedDrivers = @()
    Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services" -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($props.Start -eq 0 -and $props.Type -eq 1) {  # Boot-start kernel drivers
            $drvImgPath = $props.ImagePath
            if (-not $drvImgPath) { return }
            $resolved = $drvImgPath -replace '(?i)^\\SystemRoot\\', "$env:SystemRoot\"
            $resolved = $resolved -replace '(?i)^system32\\', "$env:SystemRoot\System32\"
            $resolved = $resolved -replace '(?i)^\\\?\?\\', ''
            if (Test-Path $resolved) {
                $drvSig = Get-AuthenticodeSignature -FilePath $resolved -ErrorAction SilentlyContinue
                if (-not $drvSig -or $drvSig.Status -ne 'Valid') {
                    $unsignedDrivers += [PSCustomObject]@{
                        Name   = $_.PSChildName
                        Path   = $resolved
                        Status = if ($drvSig) { $drvSig.Status } else { "NoSignature" }
                    }
                }
            }
        }
    }

    if ($unsignedDrivers.Count -gt 0) {
        Write-Host "    WARNING: Found $($unsignedDrivers.Count) unsigned boot-start driver(s):" -ForegroundColor Red
        foreach ($ud in $unsignedDrivers) {
            Write-Host "      - $($ud.Name): $($ud.Path) [$($ud.Status)]" -ForegroundColor Red
        }
        Write-Host "    DO NOT remove disableintegritychecks — it WILL cause BSOD!" -ForegroundColor Red
    } else {
        Write-Host "    All boot-start drivers appear properly signed." -ForegroundColor Green
        Write-Host "    To re-enable integrity checks MANUALLY:" -ForegroundColor Yellow
        Write-Host '      bcdedit /deletevalue "{current}" disableintegritychecks' -ForegroundColor White
        Write-Host '      bcdedit /set "{current}" integrityservices enable' -ForegroundColor White
    }
} else {
    Write-Host "[+] Boot integrity checks already enabled (good)" -ForegroundColor Green
}

if ($testsigningOn) {
    Write-Host "[!] TEST SIGNING IS ENABLED — unsigned drivers can load" -ForegroundColor Red
    Write-Host "    To disable MANUALLY (only if no test-signed drivers needed):" -ForegroundColor Yellow
    Write-Host "      bcdedit /set testsigning off" -ForegroundColor White
} else {
    Write-Host "[+] Test signing not enabled (good)" -ForegroundColor Green
}

# ── Phase 2: Pull GPO and start services ─────────────────────────────────────
gpupdate /force
foreach ($svc in $services) { try { Start-Service -Name $svc -ErrorAction Stop } catch {} }
Start-Sleep -Seconds 10

# If service still won't start, try MpCmdRun -wdenable
if ((Get-Service WinDefend -ErrorAction SilentlyContinue).Status -ne 'Running') {
    Write-Host "[-] WinDefend not running — trying MpCmdRun -wdenable" -ForegroundColor Yellow
    & "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -wdenable 2>&1 | Out-Null
    Start-Service WinDefend -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}

# Re-enable Defender scheduled tasks red team may have disabled
Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\*" -ErrorAction SilentlyContinue |
    Enable-ScheduledTask -ErrorAction SilentlyContinue

# Force-enable settings the service may not pick up from registry alone
Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction SilentlyContinue
Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
Set-MpPreference -DisableIOAVProtection $false -ErrorAction SilentlyContinue

# ── ASR: Block credential stealing from LSASS (immediate, no reboot) ─────────
try {
    Add-MpPreference -AttackSurfaceReductionRules_Ids 9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2 -AttackSurfaceReductionRules_Actions Enabled -ErrorAction Stop
    Write-Host "[+] ASR rule enabled: Block credential stealing from LSASS" -ForegroundColor Green
} catch {
    Write-Host "[!] ASR LSASS rule failed (Defender may not be fully functional yet): $_" -ForegroundColor Yellow
}

# ── Phase 3: Nuke ALL exclusions (local prefs + direct registry + policy) ────

# 3-pre. LOG all existing exclusions for forensic evidence before removing
$evidenceFile = "$env:USERPROFILE\Desktop\defender-exclusions-evidence-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
$evidenceLines = @("=== Defender Exclusion Evidence Log ===", "Captured: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", "Hostname: $env:COMPUTERNAME", "")

# Log from MpPreference (WMI store)
$prefsSnap = Get-MpPreference -ErrorAction SilentlyContinue
if ($prefsSnap) {
    $evidenceLines += "--- MpPreference Exclusions ---"
    @("ExclusionPath","ExclusionProcess","ExclusionExtension","ExclusionIpAddress") | ForEach-Object {
        $vals = @($prefsSnap.$_) | Where-Object { $_ }
        if ($vals) { $vals | ForEach-Object { $evidenceLines += "  [MpPref] ${_}: $_" } }
    }
}

# Log from direct registry (may differ from MpPreference — red team plants here directly)
$exclusionRegKeys = @(
    "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths",
    "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes",
    "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Extensions",
    "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\TemporaryPaths",
    "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\IpAddresses",
    "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Paths",
    "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Processes",
    "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Extensions",
    "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\TemporaryPaths"
)
$evidenceLines += ""
$evidenceLines += "--- Registry Exclusions ---"
foreach ($rk in $exclusionRegKeys) {
    $vals = reg.exe query $rk 2>&1
    if ($LASTEXITCODE -eq 0) {
        $evidenceLines += "  [$rk]"
        $vals | Where-Object { $_ -match 'REG_' } | ForEach-Object { $evidenceLines += "    $_" }
    }
}
$evidenceLines | Out-File -FilePath $evidenceFile -Encoding UTF8
Write-Host "[+] Exclusion evidence saved to $evidenceFile" -ForegroundColor Cyan

# 3a. reg.exe force-clear all exclusion keys (works even with locked ACLs / service down)
$regCleared = 0; $regFailed = 0; $regEmpty = 0
foreach ($rk in $exclusionRegKeys) {
    # Check if key has values first
    $queryOut = reg.exe query $rk 2>&1
    if ($LASTEXITCODE -ne 0) {
        $regEmpty++  # key doesn't exist or no access — nothing to clear
        continue
    }
    $hasValues = $queryOut | Where-Object { $_ -match 'REG_' }
    if (-not $hasValues) {
        $regEmpty++  # key exists but has no values
        continue
    }
    $delOut = reg.exe delete $rk /va /f 2>&1
    if ($LASTEXITCODE -eq 0) {
        $regCleared++
        $keyShort = ($rk -split '\\')[-1]
        $parentShort = ($rk -split '\\')[-2]
        Write-Host "  [+] Cleared $parentShort\$keyShort" -ForegroundColor Green
    } else {
        $regFailed++
    }
}
if ($regCleared -eq 0 -and $regFailed -eq 0) {
    Write-Host "[+] No exclusion registry values found (already clean)" -ForegroundColor Green
} elseif ($regFailed -gt 0) {
    Write-Host "[i] Registry exclusions: $regCleared cleared, $regFailed skipped (will be cleaned via MpPreference)" -ForegroundColor Cyan
} else {
    Write-Host "[+] Cleared exclusion values from $regCleared registry keys" -ForegroundColor Green
}

# 3b. Also clean via MpPreference (clears WMI store the cmdlet reads from)
$prefs = Get-MpPreference -ErrorAction SilentlyContinue
$mpCleared = 0; $mpFailed = 0
if ($prefs) {
    $exclusionTypes = @(
        @{ Prop = "ExclusionPath";      Cmd = { param($v) Remove-MpPreference -ExclusionPath $v -ErrorAction Stop } },
        @{ Prop = "ExclusionProcess";   Cmd = { param($v) Remove-MpPreference -ExclusionProcess $v -ErrorAction Stop } },
        @{ Prop = "ExclusionExtension"; Cmd = { param($v) Remove-MpPreference -ExclusionExtension $v -ErrorAction Stop } },
        @{ Prop = "ExclusionIpAddress"; Cmd = { param($v) Remove-MpPreference -ExclusionIpAddress $v -ErrorAction Stop } }
    )
    foreach ($et in $exclusionTypes) {
        @($prefs.($et.Prop)) | Where-Object { $_ } | ForEach-Object {
            try {
                & $et.Cmd $_
                $mpCleared++
                Write-Host "  [+] Removed $($et.Prop): $_" -ForegroundColor Green
            } catch {
                $mpFailed++
                Write-Host "  [-] Failed to remove $($et.Prop) '$_': $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}
if ($mpCleared -eq 0 -and $mpFailed -eq 0) {
    Write-Host "[+] No MpPreference exclusions found (already clean)" -ForegroundColor Green
} elseif ($mpFailed -gt 0) {
    Write-Host "[-] MpPreference exclusions: $mpCleared removed, $mpFailed failed" -ForegroundColor Red
} else {
    Write-Host "[+] Removed $mpCleared exclusions via MpPreference" -ForegroundColor Green
}

# ── Phase 4: Update signatures and scan ──────────────────────────────────────
Update-MpSignature -ErrorAction SilentlyContinue
Start-MpScan -ScanType QuickScan -ErrorAction SilentlyContinue

# ── Phase 5: Verify ──────────────────────────────────────────────────────────
$s = Get-MpComputerStatus -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "=== Defender Status ===" -ForegroundColor Cyan
if ($s) {
    Write-Host "  AMServiceEnabled:        $($s.AMServiceEnabled)"          -ForegroundColor $(if($s.AMServiceEnabled){'Green'}else{'Red'})
    Write-Host "  RealTimeProtection:      $($s.RealTimeProtectionEnabled)" -ForegroundColor $(if($s.RealTimeProtectionEnabled){'Green'}else{'Red'})
    Write-Host "  BehaviorMonitor:         $($s.BehaviorMonitorEnabled)"    -ForegroundColor $(if($s.BehaviorMonitorEnabled){'Green'}else{'Red'})
    Write-Host "  OnAccessProtection:      $($s.OnAccessProtectionEnabled)" -ForegroundColor $(if($s.OnAccessProtectionEnabled){'Green'}else{'Red'})
    Write-Host "  IoavProtection:          $($s.IoavProtectionEnabled)"     -ForegroundColor $(if($s.IoavProtectionEnabled){'Green'}else{'Red'})
    Write-Host "  TamperProtection:        $($s.IsTamperProtected)$(if(-not $s.IsTamperProtected){' (requires Defender for Endpoint on Server)'})" -ForegroundColor $(if($s.IsTamperProtected){'Green'}else{'Cyan'})
    Write-Host "  AntivirusSignatureAge:   $($s.AntivirusSignatureAge) days" -ForegroundColor $(if($s.AntivirusSignatureAge -le 1){'Green'}else{'Yellow'})
} else {
    Write-Host "  [!] Get-MpComputerStatus failed — Defender may not be installed" -ForegroundColor Red
}

# Check ASR LSASS rule
$asrPrefs = Get-MpPreference -ErrorAction SilentlyContinue
$asrIds = $asrPrefs.AttackSurfaceReductionRules_Ids
$asrActions = $asrPrefs.AttackSurfaceReductionRules_Actions
$lsassRuleId = "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2"
$lsassEnabled = $false
if ($asrIds -and $asrActions) {
    $lsassIdx = [array]::IndexOf($asrIds, $lsassRuleId)
    if ($lsassIdx -ge 0) { $lsassEnabled = ($asrActions[$lsassIdx] -eq 1) }
}
Write-Host "  ASR LSASS Protection:    $lsassEnabled" -ForegroundColor $(if($lsassEnabled){'Green'}else{'Red'})
Write-Host ""

# Check remaining exclusions
$finalPrefs = Get-MpPreference -ErrorAction SilentlyContinue
$exCount = (@($finalPrefs.ExclusionPath) + @($finalPrefs.ExclusionProcess) + @($finalPrefs.ExclusionExtension) |
    Where-Object { $_ }).Count
if ($exCount -gt 0) {
    Write-Host "[WARN] $exCount exclusions still present:" -ForegroundColor Yellow
    @($finalPrefs.ExclusionPath)      | Where-Object { $_ } | ForEach-Object { Write-Host "  Path: $_" -ForegroundColor Yellow }
    @($finalPrefs.ExclusionProcess)   | Where-Object { $_ } | ForEach-Object { Write-Host "  Proc: $_" -ForegroundColor Yellow }
    @($finalPrefs.ExclusionExtension) | Where-Object { $_ } | ForEach-Object { Write-Host "  Ext:  $_" -ForegroundColor Yellow }
} else {
    Write-Host "[OK] No exclusions remain" -ForegroundColor Green
}

if ($s -and $s.AMServiceEnabled -and $s.RealTimeProtectionEnabled) {
    Write-Host "[OK] Defender is fully operational" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Defender is NOT fully operational — see troubleshooting below" -ForegroundColor Red
}