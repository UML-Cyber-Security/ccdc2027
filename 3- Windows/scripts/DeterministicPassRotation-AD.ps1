#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory
<#
Resets every enabled AD user's password to SHA256("<hash>:<samAccountName>\n"),
matching the Linux/local counterpart byte-for-byte. Hash and passwords never
touch disk, console, or managed strings. Run on a DC (or any box with RSAT +
sufficient rights).

Before running:
  1. Launch powershell.exe -NoProfile.
  2. Delete this file after: `cipher /w:C:\path\to\dir`

Safety pattern (mirrors Strip-Groups-Nuclear.ps1): enumerate -> preview ->
confirm -> execute -> summary. No disk output, ever.

Note: Security events 4724 (reset) and 4738 (change) WILL fire on the DC.
Red team sees which users were touched, not the new passwords.
#>

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory -ErrorAction Stop

# kill this session's history
try {
    Set-PSReadLineOption -HistorySaveStyle SaveNothing
    $hp = (Get-PSReadlineOption).HistorySavePath
    if ($hp -and (Test-Path $hp)) { Remove-Item $hp -Force }
} catch {}
Clear-History -ErrorAction SilentlyContinue

# Accounts that must NEVER be reset (exact match, case-insensitive).
# Administrator is left in by default — add it here if you want an emergency
# login preserved.
$ProtectedSam = @(
    'krbtgt','Guest','DefaultAccount','WDAGUtilityAccount',
    'blackteam','black-team',
    'svcroot','svc_root','svc-root'
)

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

function HexBytesToSecureString {
    param([byte[]]$HexBytes)
    $ss = New-Object System.Security.SecureString
    foreach ($b in $HexBytes) { $ss.AppendChar([char]$b) }
    $ss.MakeReadOnly()
    [Array]::Clear($HexBytes, 0, $HexBytes.Length)
    return $ss
}

function DeriveHexBytes {
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

    $hex = New-Object byte[] ($digest.Length * 2)
    $tbl = [byte[]]@(48,49,50,51,52,53,54,55,56,57,97,98,99,100,101,102)
    for ($i = 0; $i -lt $digest.Length; $i++) {
        $hex[$i*2]     = $tbl[($digest[$i] -shr 4) -band 0x0F]
        $hex[$i*2 + 1] = $tbl[ $digest[$i]        -band 0x0F]
    }
    [Array]::Clear($digest, 0, $digest.Length)
    return ,$hex
}

# --- Phase 1: enumerate & classify ------------------------------------------
Write-Host "`n=== PHASE 1: ENUMERATE AD USERS ===" -ForegroundColor Cyan

# Prefer PDC emulator so resets replicate fast and don't race.
try { $dc = (Get-ADDomain).PDCEmulator } catch { $dc = $env:LOGONSERVER.TrimStart('\') }
Write-Host "  Target DC: $dc" -ForegroundColor Gray

$all     = Get-ADUser -Filter * -Server $dc -Properties Enabled,SamAccountName
$toReset = @()
$skipped = @()

foreach ($u in $all) {
    $sam = $u.SamAccountName
    if (-not $u.Enabled) { $skipped += [PSCustomObject]@{Name=$sam; Reason='disabled'}; continue }
    if ($ProtectedSam -contains $sam) { $skipped += [PSCustomObject]@{Name=$sam; Reason='protected'}; continue }
    $toReset += $u
}

Write-Host "  Will reset ($($toReset.Count)):" -ForegroundColor Yellow
foreach ($u in $toReset) { Write-Host "    $($u.SamAccountName)" -ForegroundColor Yellow }
Write-Host "  Skipped ($($skipped.Count)):" -ForegroundColor Gray
foreach ($s in $skipped) { Write-Host "    $($s.Name)  [$($s.Reason)]" -ForegroundColor Gray }

if ($toReset.Count -eq 0) {
    Write-Host "`n[OK] Nothing to reset." -ForegroundColor Green
    return
}

# --- Phase 2: confirm -------------------------------------------------------
Write-Host ""
$confirm = Read-Host "Proceed with $($toReset.Count) AD password resets? (y/n)"
if ($confirm -ne 'y') { Write-Host "  Aborted." -ForegroundColor Red; return }

# --- Phase 3: prompt for master hash ----------------------------------------
$master = Read-Host -Prompt "Master hash" -AsSecureString
$hashBytes = SecureStringToUtf8Bytes $master
$master.Dispose()

# --- Phase 4: execute -------------------------------------------------------
Write-Host "`n=== PHASE 2: APPLY RESETS ===" -ForegroundColor Cyan
$failed = @()

try {
    foreach ($u in $toReset) {
        $sam = $u.SamAccountName
        $hex = DeriveHexBytes -HashBytes $hashBytes -Username $sam
        $pw  = HexBytesToSecureString -HexBytes $hex

        try {
            Set-ADAccountPassword -Identity $u -NewPassword $pw -Reset -Server $dc -Confirm:$false
            Write-Host "  OK    $sam" -ForegroundColor Green
        } catch {
            Write-Host "  FAIL  $sam" -ForegroundColor Red
            $failed += $sam
        } finally {
            $pw.Dispose()
        }
    }
} finally {
    [Array]::Clear($hashBytes, 0, $hashBytes.Length)
    Remove-Variable hashBytes, master -ErrorAction SilentlyContinue
    [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect()
}

# --- Summary ----------------------------------------------------------------
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "  Reset:   $($toReset.Count - $failed.Count)" -ForegroundColor Green
Write-Host "  Failed:  $($failed.Count)" -ForegroundColor $(if ($failed.Count) {'Red'} else {'Green'})
if ($failed.Count) {
    Write-Host "  Failures (retry manually):" -ForegroundColor Red
    foreach ($f in $failed) { Write-Host "    $f" -ForegroundColor Red }
}
