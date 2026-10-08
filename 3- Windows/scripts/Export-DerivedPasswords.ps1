#Requires -Version 5.1
param([Parameter(Mandatory)][string]$OutPath)

$ErrorActionPreference = 'Stop'
$full = [System.IO.Path]::GetFullPath($OutPath)
if (-not (Test-Path -LiteralPath (Split-Path $full))) { throw "Parent dir missing: $(Split-Path$full)" }
if ($full.StartsWith('\\')) { throw "UNC refused" }
$up =$env:USERPROFILE.ToLower()
if ($full.ToLower() -like "$up\onedrive*") { throw "OneDrive path refused" }
if ($full.ToLower() -like "$up\documents*") { throw "Documents path refused (may sync)" }

Write-Host "`nPaste usernames (whitespace-separated). Blank line to end." -ForegroundColor Cyan
$lines = @(); while ($true) { $l = Read-Host; if ([string]::IsNullOrWhiteSpace($l)) { break }; $lines += $l }
$users = @((($lines -join ' ') -split '\s+' | Where-Object { $_ -match '^[a-zA-Z0-9_.$-]+$' }) | Sort-Object -Unique)
if (-not $users) { throw "No valid usernames" }
Write-Host "`nParsed $($users.Count):" -ForegroundColor Yellow
$users \vert{} ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
if ((Read-Host "`nProceed? (y/n)") -ne 'y') { return }

function SSToBytes($s) {
    $b = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try {
        $n = [System.Runtime.InteropServices.Marshal]::ReadInt32($b, -4) / 2
        $c = New-Object char[] $n
        for ($i = 0; $i -lt $n; $i++) { $c[$i] = [char][System.Runtime.InteropServices.Marshal]::ReadInt16($b, $i*2) }
        $r = [System.Text.Encoding]::UTF8.GetBytes($c); [Array]::Clear($c, 0, $c.Length); ,$r
    } finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

function Derive($hb, $u) {
    $ub = [System.Text.Encoding]::UTF8.GetBytes($u)
    $buf = New-Object byte[] ($hb.Length + 1 + $ub.Length + 1)
    [Buffer]::BlockCopy($hb, 0, $buf, 0, $hb.Length); $buf[$hb.Length] = 58
    [Buffer]::BlockCopy($ub, 0, $buf, $hb.Length + 1, $ub.Length); $buf[$buf.Length-1] = 10
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $d = $sha.ComputeHash($buf) } finally { $sha.Dispose() }
    [Array]::Clear($buf, 0, $buf.Length); [Array]::Clear($ub, 0, $ub.Length)
    
    # Take first 8 bytes of digest = exactly 16 hex chars
    $s = New-Object System.Text.StringBuilder 16
    for ($i = 0; $i -lt 8; $i++) { [void]$s.Append($d[$i].ToString('x2')) }
    [Array]::Clear($d, 0, $d.Length); $s.ToString()
}

$master = Read-Host -Prompt "Master hash" -AsSecureString
$hb = SSToBytes $master; $master.Dispose()
try {
    $sw = [System.IO.StreamWriter]::new($full, $false, (New-Object System.Text.UTF8Encoding($false)))
    try {
        $sw.WriteLine("username,password")
        foreach ($u in $users) { $sw.WriteLine("$u,$(Derive $hb $u)") }
    } finally { $sw.Dispose() }
} finally {
    [Array]::Clear($hb, 0, $hb.Length); Remove-Variable hb, master -EA SilentlyContinue
    [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect()
}

# Lock ACL to current user + SYSTEM + Administrators
$acl = Get-Acl -LiteralPath $full; $acl.SetAccessRuleProtection($true, $false)
foreach ($r in @($acl.Access)) { [void]$acl.RemoveAccessRule($r) }
foreach ($sid in @(
    [System.Security.Principal.WindowsIdentity]::GetCurrent().User,
    (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')),
    (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')))) {
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($sid,'FullControl','Allow')))
}
Set-Acl -LiteralPath $full -AclObject $acl

Write-Host "`nWrote $($users.Count) entries to:$full" -ForegroundColor Green
Write-Host "When done: Remove-Item '$full' -Force; cipher /w:`"$(Split-Path $full)`"" -ForegroundColor Yellow