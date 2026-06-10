#Requires -RunAsAdministrator
<#
Resets every enabled local user's password to SHA256("<hash>:<username>\n"),
matching the Linux counterpart byte-for-byte. Hash is never written to disk,
never printed, never stored in any managed string. Derived passwords are
built directly into SecureString objects and zeroed after use.

Before running:
  1. Launch powershell.exe -NoProfile.
  2. Delete this file after run: `cipher /w:C:\path\to\dir`

Safety pattern (mirrors Strip-Groups-Nuclear.ps1): enumerate -> preview ->
confirm -> execute -> summary. No disk output, ever.
#>

$ErrorActionPreference = 'Stop'

# --- kill this session's history surface ------------------------------------
try {
    Set-PSReadLineOption -HistorySaveStyle SaveNothing
    $histPath = (Get-PSReadlineOption).HistorySavePath
    if ($histPath -and (Test-Path $histPath)) { Remove-Item $histPath -Force }
} catch {}
Clear-History -ErrorAction SilentlyContinue

# Names that must NEVER be reset (exact match, case-insensitive).
# Administrator is left IN (it will be reset) — add it here if you want an
# emergency login preserved.
$ProtectedNames = @(
    'DefaultAccount','WDAGUtilityAccount',
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
Write-Host "`n=== PHASE 1: ENUMERATE LOCAL USERS ===" -ForegroundColor Cyan

$allLocal = Get-LocalUser
$toReset  = @()
$skipped  = @()

foreach ($u in $allLocal) {
    $name = $u.Name
    if (-not $u.Enabled) { $skipped += [PSCustomObject]@{Name=$name; Reason='disabled'}; continue }
    if ($ProtectedNames -contains $name) { $skipped += [PSCustomObject]@{Name=$name; Reason='protected'}; continue }
    $toReset += $name
}

Write-Host "  Will reset ($($toReset.Count)):" -ForegroundColor Yellow
foreach ($n in $toReset) { Write-Host "    $n" -ForegroundColor Yellow }
Write-Host "  Skipped ($($skipped.Count)):" -ForegroundColor Gray
foreach ($s in $skipped) { Write-Host "    $($s.Name)  [$($s.Reason)]" -ForegroundColor Gray }

if ($toReset.Count -eq 0) {
    Write-Host "`n[OK] Nothing to reset." -ForegroundColor Green
    return
}

# --- Phase 2: confirm -------------------------------------------------------
Write-Host ""
$confirm = Read-Host "Proceed with $($toReset.Count) local password resets? (y/n)"
if ($confirm -ne 'y') { Write-Host "  Aborted." -ForegroundColor Red; return }

# --- Phase 3: prompt for master hash (never echoed, never on disk) ----------
$master = Read-Host -Prompt "Master hash" -AsSecureString
$hashBytes = SecureStringToUtf8Bytes $master
$master.Dispose()

# --- Phase 4: execute -------------------------------------------------------
Write-Host "`n=== PHASE 2: APPLY RESETS ===" -ForegroundColor Cyan
$failed = @()

try {
    foreach ($name in $toReset) {
        $hex = DeriveHexBytes -HashBytes $hashBytes -Username $name
        $pw  = HexBytesToSecureString -HexBytes $hex

        try {
            Set-LocalUser -Name $name -Password $pw
            Write-Host "  OK    $name" -ForegroundColor Green
        } catch {
            Write-Host "  FAIL  $name" -ForegroundColor Red
            $failed += $name
        } finally {
            $pw.Dispose()
        }

        Start-Sleep -Milliseconds 300
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
