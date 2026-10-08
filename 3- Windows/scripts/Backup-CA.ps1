# Requires -RunAsAdministrator
[CmdletBinding()]
param (
    [string]$RootPath = "C:\IR_Backup",
    [string]$KeyPassword = "P@ssw0rd123!" # Change to team standard credential
)
$ErrorActionPreference = "SilentlyContinue"
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$CADir = Join-Path $RootPath "CABackup_$Timestamp"
New-Item -ItemType Directory -Path $CADir -Force | Out-Null

$FlagFile = Join-Path $CADir "CA_TRIAGE_FLAGS.txt"
"=== CA / ADCS TRIAGE FLAGS ($Timestamp) ===" | Out-File $FlagFile

Write-Host "[+] Starting Certificate Authority (ADCS) Backup..." -ForegroundColor Cyan

# 1. Backup CA Database and Private Keys
$DbDir = Join-Path $CADir "DB_and_Keys"
New-Item -ItemType Directory -Path $DbDir -Force | Out-Null
Write-Host "[*] Exporting CA Database and Private Keys via Certutil..." -ForegroundColor Yellow
certutil -backupdb $DbDir | Out-File (Join-Path $CADir "certutil_db_backup.log")
certutil -p $KeyPassword -backupkey $DbDir | Out-File (Join-Path $CADir "certutil_key_backup.log")

# 2. Export CA Registry Configuration
Write-Host "[*] Exporting CA Registry parameters..." -ForegroundColor Yellow
reg export "HKLM\SYSTEM\CurrentControlSet\Services\CertSvc" (Join-Path $CADir "CertSvc_Registry.reg") /y | Out-Null

# 3. Export Certificate Templates and Permissions
Write-Host "[*] Dumping published certificate templates and security..." -ForegroundColor Yellow
certutil -catemplates > (Join-Path $CADir "Published_Templates.txt") 2>&1
certutil -getreg CA\Security > (Join-Path $CADir "CA_Security_Permissions.txt") 2>&1

# Flag dangerous ESC1 templates (Client Authentication + Enrollee Supplies Subject)
$rawTemplates = Get-Content (Join-Path $CADir "Published_Templates.txt")
if ($rawTemplates -match "CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT" -and $rawTemplates -match "Client Authentication") {
    "`n[!] POTENTIAL ESC1 TEMPLATE DETECTED: Enrollee Supplies Subject + Client Auth enabled!" | Out-File $FlagFile -Append
}

# Flag non-admin CA permissions
$rawSec = Get-Content (Join-Path$CADir "CA_Security_Permissions.txt")
if ($rawSec -match "Everyone" -or $rawSec -match "Authenticated Users") {
    "`n[!] BROAD CA ENROLLMENT / MANAGE RIGHTS DETECTED (CHECK CA_Security_Permissions.txt)" | Out-File $FlagFile -Append
}

# 4. Check for Web Enrollment (CertSrv / ESC8)
if (Test-Path "$env:SystemRoot\System32\certsrv") {
    Write-Host "[*] Backing up CertSrv web enrollment..." -ForegroundColor Yellow
    $WebEnrollDir = Join-Path $CADir "WebEnrollment"
    New-Item -ItemType Directory -Path $WebEnrollDir -Force | Out-Null
    Copy-Item "$env:SystemRoot\System32\certsrv\*" -Destination $WebEnrollDir -Recurse -Force
    
    "`n[!] ADCS WEB ENROLLMENT (CertSrv) IS INSTALLED: Vulnerable to NTLM Relay (ESC8) if HTTP is active without Extended Protection!" | Out-File $FlagFile -Append
}

Write-Host "[+] CA Backup Completed: $CADir" -ForegroundColor Green