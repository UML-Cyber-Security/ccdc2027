$ProgressPreference = 'SilentlyContinue'
$firefoxInstallerUrl = "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US"
$installerPath = "$env:TEMP\firefox_installer.exe"
Invoke-WebRequest -Uri $firefoxInstallerUrl -OutFile $installerPath
Start-Process -FilePath $installerPath -Args "/S" -Wait
Remove-Item -Path $installerPath