$ProgressPreference = 'SilentlyContinue'
$installerUrl = "https://2.na.dl.wireshark.org/win64/Wireshark-4.6.4-x64.exe"
$installerPath = "wireshark.exe"
Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait
Remove-Item -Path $installerPath