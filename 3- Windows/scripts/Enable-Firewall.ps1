# Turn on firewall for all profiles
Set-NetFirewallProfile -All -Enabled True

# Allow RDP, File/Printer Sharing, and ICMP ping
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"
Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)"

# Verify
Get-NetFirewallProfile | Format-Table Name, Enabled -AutoSize