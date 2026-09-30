Write-Host "`n=== PRE-FLIGHT AUDIT & REMEDIATION GUIDE ===" -ForegroundColor Cyan

# 1. Check UAC (EnableLUA)
$uac = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction SilentlyContinue
if ($uac.EnableLUA -eq 1) {
    Write-Host "[!] TRAP: EnableLUA is 1 (Active)" -ForegroundColor Red
    Write-Host "    -> New admins get downgraded to standard user tokens" -ForegroundColor Yellow
    Write-Host "    FIX COMMAND:" -ForegroundColor Yellow
    Write-Host "    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -Value 0 -Type DWord; Restart-Computer -Force`n"
} else {
    Write-Host "[+] PASS: EnableLUA is 0 (Full admin tokens enabled)" -ForegroundColor Green
}

# 2. Check AppInit DLL Injection
$appInit64 = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" -ErrorAction SilentlyContinue).AppInit_DLLs
$appInit32 = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows" -ErrorAction SilentlyContinue).AppInit_DLLs

if ($appInit64 -and $appInit64.Trim()) {
    Write-Host "[!] TRAP: 64-bit AppInit_DLLs found: $appInit64" -ForegroundColor Red
    Write-Host "    FIX COMMAND:" -ForegroundColor Yellow
    Write-Host "    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' -Name 'AppInit_DLLs' -Value ''; Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' -Name 'LoadAppInit_DLLs' -Value 0`n"
} elseif ($appInit32 -and$appInit32.Trim()) {
    Write-Host "[!] TRAP: 32-bit AppInit_DLLs found: $appInit32" -ForegroundColor Red
    Write-Host "    FIX COMMAND:" -ForegroundColor Yellow
    Write-Host "    Set-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows' -Name 'AppInit_DLLs' -Value ''; Set-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows' -Name 'LoadAppInit_DLLs' -Value 0`n"
} else {
    Write-Host "[+] PASS: AppInit_DLLs is clean" -ForegroundColor Green
}

# 3. Check Image File Execution Options (IFEO) Hijacks
$ifeoKeys = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options" -ErrorAction SilentlyContinue
$hijacks = $ifeoKeys | Where-Object { (Get-ItemProperty -Path $_.PSPath -Name "Debugger" -ErrorAction SilentlyContinue).Debugger }

if ($hijacks) {
    $hijacks | ForEach-Object {
        $dbg = (Get-ItemProperty -Path $_.PSPath -Name "Debugger").Debugger
        Write-Host "[!] TRAP: IFEO Debugger on $($_.PSChildName) -> $dbg" -ForegroundColor Red
        Write-Host "    FIX COMMAND:" -ForegroundColor Yellow
        Write-Host "    Remove-ItemProperty -Path '$($_.PSPath)' -Name 'Debugger' -Force`n"
    }
} else {
    Write-Host "[+] PASS: No IFEO debuggers found" -ForegroundColor Green
}

# 4. Check Root File Associations (.lnk and .exe)
$lnkCheck = cmd.exe /c "assoc .lnk 2>nul"
$exeCheck = cmd.exe /c "assoc .exe 2>nul"

if ($lnkCheck -notmatch "lnkfile" -or $exeCheck -notmatch "exefile") {
    Write-Host "[!] TRAP: File associations broken ($lnkCheck \vert{}$exeCheck)" -ForegroundColor Red
    Write-Host "    FIX COMMAND:" -ForegroundColor Yellow
    Write-Host "    cmd.exe /c 'assoc .lnk=lnkfile && assoc .exe=exefile && ftype exefile=`"%1`" %*'`n"
} else {
    Write-Host "[+] PASS: File associations intact (.lnk and .exe)" -ForegroundColor Green
}

# 5. Check Default User Profile Template
cmd.exe /c "reg load HKLM\DefCheck C:\Users\Default\NTUSER.DAT >nul 2>&1"
if ($LASTEXITCODE -eq 0) {
    $badLnk = cmd.exe /c "reg query HKLM\DefCheck\Software\Classes\.lnk 2>nul"
    cmd.exe /c "reg unload HKLM\DefCheck >nul 2>&1"
    if ($badLnk) {
        Write-Host "[!] TRAP: Default profile has rogue .lnk override" -ForegroundColor Red
        Write-Host "    FIX COMMAND:" -ForegroundColor Yellow
        Write-Host "    cmd.exe /c 'reg load HKLM\DefFix C:\Users\Default\NTUSER.DAT && reg delete HKLM\DefFix\Software\Classes\.lnk /f && reg unload HKLM\DefFix'`n"
    } else {
        Write-Host "[+] PASS: Default user profile template is clean" -ForegroundColor Green
    }
} else {
    Write-Host "[-] INFO: Default NTUSER.DAT could not be locked" -ForegroundColor Gray
}

# 6. Check System PATH
$sysPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($sysPath -notmatch "System32" -or $sysPath -notmatch "WindowsPowerShell") {
    Write-Host "[!] TRAP: System PATH is missing core system folders" -ForegroundColor Red
    Write-Host "    FIX COMMAND:" -ForegroundColor Yellow
    Write-Host "    [Environment]::SetEnvironmentVariable('Path', 'C:\Windows\system32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0\;C:\Windows\System32\OpenSSH\;' + [Environment]::GetEnvironmentVariable('Path', 'Machine'), 'Machine')`n"
} else {
    Write-Host "[+] PASS: System PATH contains System32 and PowerShell" -ForegroundColor Green
}

Write-Host "============================================`n" -ForegroundColor Cyan