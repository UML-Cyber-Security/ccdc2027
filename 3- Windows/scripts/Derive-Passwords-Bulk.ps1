#Requires -Version 5.1
<#
Bulk-derive deterministic passwords from a master hash for a whitespace-
separated list of usernames. Writes a CSV to the mandatory -OutPath.

RUN ONLY on a trusted, protected machine. The output file contains plaintext
passwords for every listed user — treat it like a key file.

Usage:
    .\Derive-Passwords-Bulk.ps1 -OutPath D:\secure\rotation.csv

Input: paste whitespace-separated usernames (e.g. the "Will reset" block from
the rotation script's output). End with a blank line. Non-username tokens
(colons, parens, "Will", "reset") are auto-filtered.

Output CSV columns: username,password
#>

param(
    [Parameter(Mandatory)]
    [string]$OutPath
)

$ErrorActionPreference = 'Stop'

# --- path safety gates ------------------------------------------------------
$full = [System.IO.Path]::GetFullPath($OutPath)
$parent = Split-Path -Path $full -Parent
if (-not (Test-Path -LiteralPath $parent)) {
    Write-Host "[X] Parent directory does not exist: $parent" -ForegroundColor Red; exit 1
}

$lowerFull = $full.ToLower()
$up = $env:USERPROFILE.ToLower()

if ($full.StartsWith('\\')) {
    Write-Host "[X] UNC/network path refused: $full" -ForegroundColor Red; exit 1
}
if ($lowerFull -like "$up\onedrive*") {
    Write-Host "[X] OneDrive path refused (auto-syncs to cloud): $full" -ForegroundColor Red; exit 1
}
if ($lowerFull -like "$up\documents*") {
    Write-Host "[X] Documents path refused (may auto-sync): $full" -ForegroundColor Red; exit 1
}
if ($lowerFull -like "$up\desktop*") {
    Write-Host "[!] Desktop may sync to OneDrive — proceed only if OneDrive is NOT configured." -ForegroundColor Yellow
}

# Refuse mapped-to-UNC drives
$drive = (Split-Path -Qualifier $full) -replace ':',''
if ($drive) {
    $psdrive = Get-PSDrive -Name $drive -ErrorAction SilentlyContinue
    if ($psdrive -and $psdrive.DisplayRoot -match '^\\\\') {
        Write-Host "[X] Drive ${drive}: is mapped to $($psdrive.DisplayRoot) — refused" -ForegroundColor Red; exit 1
    }
}

if (Test-Path -LiteralPath $full) {
    Write-Host "[!] File exists and will be overwritten: $full" -ForegroundColor Yellow
    $ok = Read-Host "Continue? (y/n)"
    if ($ok -ne 'y') { Write-Host "Aborted." -ForegroundColor Red; exit 0 }
}

# --- collect usernames ------------------------------------------------------
Write-Host "`n=== PASTE USERNAMES ===" -ForegroundColor Cyan
Write-Host "Paste whitespace-separated usernames. Press Enter on an empty line to finish." -ForegroundColor Gray

$lines = @()
while ($true) {
    $line = Read-Host
    if ([string]::IsNullOrWhiteSpace($line)) { break }
    $lines += $line
}

$raw = $lines -join ' '
$tokens = $raw -split '\s+' | Where-Object { $_ -match '^[a-zA-Z0-9_.$-]+$' }
$users = @($tokens | Sort-Object -Unique)

if ($users.Count -eq 0) {
    Write-Host "[X] No valid usernames parsed." -ForegroundColor Red; exit 1
}

Write-Host "`n=== PARSED $($users.Count) USERNAMES ===" -ForegroundColor Cyan
foreach ($u in $users) { Write-Host "  $u" -ForegroundColor Yellow }
Write-Host ""
$ok = Read-Host "Proceed? (y/n)"
if ($ok -ne 'y') { Write-Host "Aborted." -ForegroundColor Red; exit 0 }

# --- crypto helpers ---------------------------------------------------------
function SecureStringToUtf8Bytes {
    param([System.Security.SecureString]$Secure)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        $len = [System.Runtime.InteropServices.Marshal]::ReadInt32($bstr, -4) / 2
        $chars = New-Object char[] $len
        for ($i = 0; $i -lt $len; $i++) {
            $chars[$i] = [char][System.Runtime.InteropServices.Marshal]::ReadInt16($bstr, $i*2)
        }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($chars)
        [Array]::Clear($chars, 0, $chars.Length)
        return ,$bytes
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function DeriveHex {
    param([byte[]]$HashBytes, [string]$Username)

    $userB = [System.Text.Encoding]::UTF8.GetBytes($Username)
    $buf = New-Object byte[] ($HashBytes.Length + 1 + $userB.Length + 1)
    [Buffer]::BlockCopy($HashBytes, 0, $buf, 0, $HashBytes.Length)
    $buf[$HashBytes.Length] = 58                                  # ":"
    [Buffer]::BlockCopy($userB, 0, $buf, $HashBytes.Length + 1, $userB.Length)
    $buf[$buf.Length - 1] = 10                                    # "\n"

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = $sha.ComputeHash($buf) } finally { $sha.Dispose() }
    [Array]::Clear($buf, 0, $buf.Length)
    [Array]::Clear($userB, 0, $userB.Length)

    $sb = New-Object System.Text.StringBuilder 64
    foreach ($b in $digest) { [void]$sb.Append($b.ToString('x2')) }
    [Array]::Clear($digest, 0, $digest.Length)
    return $sb.ToString()
}

# --- hash prompt ------------------------------------------------------------
$master = Read-Host -Prompt "Master hash" -AsSecureString
$hashBytes = SecureStringToUtf8Bytes $master
$master.Dispose()

# --- derive + write CSV -----------------------------------------------------
try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $sw = [System.IO.StreamWriter]::new($full, $false, $utf8NoBom)
    try {
        $sw.WriteLine("username,password")
        foreach ($u in $users) {
            $pw = DeriveHex -HashBytes $hashBytes -Username $u
            $sw.WriteLine("$u,$pw")
            $pw = $null
        }
    } finally {
        $sw.Dispose()
    }
} finally {
    [Array]::Clear($hashBytes, 0, $hashBytes.Length)
    Remove-Variable hashBytes, master -ErrorAction SilentlyContinue
    [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect()
}

# --- lock down ACL (owner-only) ---------------------------------------------
try {
    $acl = Get-Acl -LiteralPath $full
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRule($rule) }

    $meSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $sysSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')       # LocalSystem
    $admSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')   # BUILTIN\Administrators

    foreach ($sid in @($meSid, $sysSid, $admSid)) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $sid, 'FullControl', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $full -AclObject $acl
    Write-Host "  ACL locked to current user + SYSTEM + Administrators only." -ForegroundColor Gray
} catch {
    Write-Host "[!] Could not lock ACL on output file: $_" -ForegroundColor Yellow
}

# --- summary ----------------------------------------------------------------
$dir = Split-Path -Path $full -Parent
Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host "  Wrote $($users.Count) entries to: $full" -ForegroundColor Green
Write-Host ""
Write-Host "  After use, wipe with:" -ForegroundColor Yellow
Write-Host "    Remove-Item -LiteralPath '$full' -Force" -ForegroundColor Gray
Write-Host "    cipher /w:`"$dir`"" -ForegroundColor Gray
