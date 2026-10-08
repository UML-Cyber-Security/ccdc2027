$ProgressPreference = 'SilentlyContinue'
$nmapUrl = "https://nmap.org/dist/nmap-7.98-setup.exe"
$installerPath = "$env:USERPROFILE\Downloads\nmap-setup.exe"
Invoke-WebRequest -Uri $nmapUrl -OutFile $installerPath
Start-Process -FilePath $installerPath -ArgumentList '/forceinstall /NpcapInstallMode=1' -Wait
Remove-Item -Path $installerPath -Force