Write-Host "`n=== RDP Sessions ===" -ForegroundColor Cyan
$rdp = qwinsta 2>&1 | Where-Object { $_ -match "rdp-tcp|console" -and $_ -notmatch "^SESSIONNAME" }
if ($rdp) { $rdp | ForEach-Object { Write-Host "  $_" } } else { Write-Host "  None" -ForegroundColor Gray }

Write-Host "`n=== SSH ===" -ForegroundColor Cyan
$sshService = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshService) {
    Write-Host "  OpenSSH Server: $($sshService.Status)" -ForegroundColor $(if($sshService.Status -eq 'Running'){'Yellow'}else{'Green'})
    $sshProcs = Get-Process sshd -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $sshService.Id }
    if ($sshProcs) {
        Write-Host "  Active SSH sessions:" -ForegroundColor Yellow
        $sshProcs | ForEach-Object { Write-Host "    PID $($_.Id) — started $($_.StartTime)" }
    } else { Write-Host "  No active SSH sessions" -ForegroundColor Gray }
} else { Write-Host "  OpenSSH Server: Not installed" -ForegroundColor Green }

Write-Host "`n=== WinRM ===" -ForegroundColor Cyan
$winrmService = Get-Service WinRM -ErrorAction SilentlyContinue
if ($winrmService) {
    Write-Host "  WinRM Service: $($winrmService.Status)" -ForegroundColor $(if($winrmService.Status -eq 'Running'){'Yellow'}else{'Green'})
    if ($winrmService.Status -eq 'Running') {
        $sessions = Get-WSManInstance -ResourceURI shell -Enumerate -ErrorAction SilentlyContinue
        if ($sessions) {
            Write-Host "  Active WinRM sessions:" -ForegroundColor Yellow
            $sessions | ForEach-Object { Write-Host "    Owner: $($_.Owner) — Shell: $($_.ShellId) — Idle: $($_.ShellInactivity)s" }
        } else { Write-Host "  No active WinRM sessions" -ForegroundColor Gray }
    }
} else { Write-Host "  WinRM Service: Not installed" -ForegroundColor Green }

Write-Host ""