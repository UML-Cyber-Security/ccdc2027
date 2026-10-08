Get-Process sshd, ssh -ErrorAction SilentlyContinue | Stop-Process -Force
Stop-Service sshd -Force -ErrorAction SilentlyContinue
Set-Service sshd -StartupType Disabled -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "Block SSH Inbound" -Direction Inbound -Protocol TCP -LocalPort 22,2222 -Action Block -ErrorAction SilentlyContinue
Write-Host "[+] SSH killed, disabled, and blocked" -ForegroundColor Green