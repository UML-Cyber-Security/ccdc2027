# Requires -RunAsAdministrator
[CmdletBinding()]
param (
    [string]$RootPath = "C:\IR_Backup"
)
$ErrorActionPreference = "SilentlyContinue"
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'$IISDir = Join-Path $RootPath "IISBackup_$Timestamp"
New-Item -ItemType Directory -Path $IISDir -Force | Out-Null

$FlagFile = Join-Path$IISDir "IIS_TRIAGE_FLAGS.txt"
"=== IIS WEB SERVER TRIAGE FLAGS ($Timestamp) ===" \vert{} Out-File $FlagFile

Write-Host "[+] Starting IIS Web Server Backup..." -ForegroundColor Cyan

# 1. Native IIS AppCmd Configuration Backup
if (Test-Path "$env:SystemRoot\System32\inetsrv\appcmd.exe") {
    Write-Host "[*] Executing AppCmd native backup..." -ForegroundColor Yellow
    & "$env:SystemRoot\System32\inetsrv\appcmd.exe" add backup "CCDC_IIS_$Timestamp" | Out-Null
    
    $CfgDir = Join-Path$IISDir "Config"
    New-Item -ItemType Directory -Path $CfgDir -Force | Out-Null
    Copy-Item "$env:SystemRoot\System32\inetsrv\config\applicationHost.config" -Destination (Join-Path $CfgDir "applicationHost.config") -Force
}

# 2. Recursively Backup All web.config Files
Write-Host "[*] Backing up all web.config files..." -ForegroundColor Yellow
$WebCfgDir = Join-Path$IISDir "WebConfigs"
New-Item -ItemType Directory -Path $WebCfgDir -Force | Out-Null
Get-ChildItem -Path "C:\inetpub" -Filter "web.config" -Recurse -Force | ForEach-Object {
    $cleanPath =$_.FullName.Replace("C:\inetpub\", "").Replace("\", "_")
    Copy-Item $_.FullName -Destination (Join-Path $WebCfgDir "web_$cleanPath") -Force
    
    # Check for raw passwords or suspicious modules inside web.config
    $content = Get-Content$_.FullName -Raw
    if ($content -match 'connectionString=".*password=.*"' -or $content -match '<httpModules>' -or$content -match '<handlers>') {
        "`n[!] SUSPICIOUS OR SENSITIVE DATA IN $($_.FullName):" | Out-File $FlagFile -Append
        if ($content -match 'password=') { "  -> Contains cleartext credentials in connectionString" | Out-File $FlagFile -Append }
        if ($content -match '<httpModules>|<handlers>') { "  -> Custom HTTP Handlers/Modules registered (Potential Web Shell / Filter)" | Out-File $FlagFile -Append }
    }
}

# 3. Export Active Sites, Application Pools, and Bindings
if (Get-Module -ListAvailable -Name WebAdministration) {
    Import-Module WebAdministration
    Get-Website | Select-Object Name, ID, State, PhysicalPath, Bindings | Export-Clixml (Join-Path $IISDir "IIS_Websites.xml")
    Get-ChildItem IIS:\AppPools | Select-Object Name, State, ProcessModel | Export-Clixml (Join-Path $IISDir "IIS_AppPools.xml")
}

# 4. Inventory Web Root Binaries & Flag Script Files
Write-Host "[*] Generating baseline file manifest of web roots..." -ForegroundColor Yellow
$webFiles = Get-ChildItem -Path "C:\inetpub\wwwroot" -Recurse -File
$webFiles | Select-Object FullName, Length, LastWriteTime | Export-Csv (Join-Path $IISDir "wwwroot_file_manifest.csv") -NoTypeInformation

$susWebFiles = $webFiles | Where-Object { $_.Extension -match '\.(aspx|ashx|asmx|php|jsp|exe|dll|ps1|bat|cmd)$' }
if ($susWebFiles) {
    "`n[!] EXECUTABLE / SCRIPT FILES FOUND IN WWWROOT (POTENTIAL WEB SHELLS):" | Out-File $FlagFile -Append
    $susWebFiles \vert{} Select-Object FullName, Length, LastWriteTime \vert{} Out-String \vert{} Out-File$FlagFile -Append
}

Write-Host "[+] IIS Backup Completed: $IISDir" -ForegroundColor Green