#Requires -RunAsAdministrator
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$installerUrl  = "https://2.na.dl.wireshark.org/win64/all-versions/Wireshark-4.6.7-x64.exe"
$expectedHash  = "e67cfc2b4462cce93aecb67972d5079e85b8fe575fb18858f9260b6ec7b37258"
$installerPath = Join-Path $env:TEMP "Wireshark-4.6.7-x64.exe"

Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

$actualHash = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
    Write-Host "[-] SHA256 mismatch! Expected $expectedHash but got $actualHash. Aborting." -ForegroundColor Red
    Remove-Item -Path $installerPath -Force
    return
}

Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait
Remove-Item -Path $installerPath -Force
Write-Host "[+] Wireshark 4.6.7 installed." -ForegroundColor Green
