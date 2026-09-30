$url = "https://github.com/WithSecureLabs/chainsaw/releases/latest/download/chainsaw_all_platforms+rules.zip"

$zipPath = "$env:USERPROFILE\Downloads\chainsaw_package.zip"
$tempExtractPath = "$env:USERPROFILE\Downloads\chainsaw_temp"
$destinationPath = "C:\Chainsaw"

$ProgressPreference = 'SilentlyContinue'
Write-Host "Downloading Chainsaw..."
Invoke-WebRequest -Uri $url -OutFile $zipPath

Write-Host "Preparing folders..."
Remove-Item $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
New-Item $tempExtractPath -ItemType Directory | Out-Null

Write-Host "Extracting package..."
Expand-Archive -Path $zipPath -DestinationPath $tempExtractPath -Force

if (-not (Test-Path $destinationPath)) {
    New-Item $destinationPath -ItemType Directory | Out-Null
}

Write-Host "Locating Windows executable..."
$exeFile = Get-ChildItem $tempExtractPath -Recurse -Filter "chainsaw_x86_64-pc-windows-msvc.exe" |
    Select-Object -First 1

if (-not $exeFile) {
    throw "Windows executable not found!"
}

Write-Host "Installing executable..."
Copy-Item $exeFile.FullName "$destinationPath\chainsaw.exe" -Force

Write-Host "Copying rules..."
$rules = Get-ChildItem $tempExtractPath -Recurse -Directory -Filter "rules" |
    Select-Object -First 1
if ($rules) {
    Copy-Item $rules.FullName $destinationPath -Recurse -Force
}

Write-Host "Copying mappings..."
$mappings = Get-ChildItem $tempExtractPath -Recurse -Directory -Filter "mappings" |
    Select-Object -First 1
if ($mappings) {
    Copy-Item $mappings.FullName $destinationPath -Recurse -Force
}

Write-Host "Cleaning up..."
Remove-Item $zipPath -Force
Remove-Item $tempExtractPath -Recurse -Force

Write-Host "`nInstallation complete!"
Get-ChildItem $destinationPath