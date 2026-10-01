#Requires -RunAsAdministrator
[CmdletBinding()]
param (
    [string]$RootPath = "C:\IR_Backup"
)
$ErrorActionPreference = "SilentlyContinue"
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir = Join-Path $RootPath "BaseBackup_$Timestamp"

# 0. Initialize & Lock NTFS ACLs
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
$acl = Get-Acl $BackupDir
$acl.SetAccessRuleProtection($true, $false)
$adminRule  = [System.Security.AccessControl.FileSystemAccessRule]::new("BUILTIN\Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$systemRule = [System.Security.AccessControl.FileSystemAccessRule]::new("NT AUTHORITY\SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.AddAccessRule($adminRule)
$acl.AddAccessRule($systemRule)
Set-Acl -Path $BackupDir -AclObject $acl

$FlagFile = Join-Path $BackupDir "TRIAGE_FLAGS.txt"
"=== BASE HOST TRIAGE FLAGS ($Timestamp) ===" | Out-File $FlagFile

# 1. Volatile Network Sockets & Live Sockets Triage
$VolDir = Join-Path $BackupDir "LiveState"
New-Item -ItemType Directory -Path $VolDir -Force | Out-Null

$tcp = Get-NetTCPConnection
$tcp | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess, @{Name="ProcessName";Expression={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name}} | Export-Csv (Join-Path $VolDir "ActiveTCP.csv") -NoTypeInformation
Get-NetUDPEndpoint | Select-Object LocalAddress, LocalPort, OwningProcess, @{Name="ProcessName";Expression={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name}} | Export-Csv (Join-Path $VolDir "ActiveUDP.csv") -NoTypeInformation

$susConns = $tcp | Where-Object { $_.State -eq 'Established' -and $_.RemoteAddress -notmatch '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|::1|fe80)' }
if ($susConns) {
    "`n[!] SUSPICIOUS EXTERNAL TCP CONNECTIONS:" | Out-File $FlagFile -Append
    $susConns | Select-Object RemoteAddress, RemotePort, OwningProcess | Out-String | Out-File $FlagFile -Append
}

# 2. Process Tree & Command Lines
$procs = Get-CimInstance Win32_Process
$procs | Select-Object ProcessId, ParentProcessId, Name, CommandLine, ExecutablePath | Export-Csv (Join-Path $VolDir "ProcessTree.csv") -NoTypeInformation

$susProcs = $procs | Where-Object {
    $_.CommandLine -match '-enc|-encodedcommand|downloadstring|bypass|-w hidden' -or $_.ExecutablePath -match '\\AppData\\|\\Temp\\|\\Users\\Public\\'
}
if ($susProcs) {
    "`n[!] SUSPICIOUS RUNNING PROCESSES / COMMAND LINES:" | Out-File $FlagFile -Append
    $susProcs | Select-Object ProcessId, Name, CommandLine | Out-String | Out-File $FlagFile -Append
}

# 3. Network Configuration, Hosts, and Firewall
$NetDir = Join-Path $BackupDir "Network"
New-Item -ItemType Directory -Path $NetDir -Force | Out-Null
Copy-Item "$env:SystemRoot\System32\drivers\etc\hosts" -Destination (Join-Path $NetDir "hosts.bak") -Force
Get-NetIPConfiguration | Out-File (Join-Path $NetDir "IPConfig.txt")
Get-NetRoute | Out-File (Join-Path $NetDir "RoutingTable.txt")
netsh advfirewall export (Join-Path $NetDir "FirewallRules.wfw") | Out-Null

$hostsEntries = Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" | Where-Object { $_ -match '^\s*[^#\s]' }
if ($hostsEntries) {
    "`n[!] ACTIVE ENTRIES IN HOSTS FILE:" | Out-File $FlagFile -Append
    $hostsEntries | Out-String | Out-File $FlagFile -Append
}

# 4. Console Histories
$HistDir = Join-Path $BackupDir "PSHistories"
New-Item -ItemType Directory -Path $HistDir -Force | Out-Null
Get-ChildItem -Path "C:\Users" -Filter "ConsoleHost_history.txt" -Recurse -Force | ForEach-Object {
    $uName = $_.FullName.Split('\')[2]
    Copy-Item $_.FullName -Destination (Join-Path $HistDir "${uName}_ConsoleHost_history.txt") -Force
}

# 5. Raw Registry Hives & Restorable Services
$HiveDir = Join-Path $BackupDir "RawRegistryHives"
New-Item -ItemType Directory -Path $HiveDir -Force | Out-Null
reg save HKLM\SYSTEM (Join-Path $HiveDir "SYSTEM.hive") /y | Out-Null
reg save HKLM\SOFTWARE (Join-Path $HiveDir "SOFTWARE.hive") /y | Out-Null
reg save HKLM\SECURITY (Join-Path $HiveDir "SECURITY.hive") /y | Out-Null

$IsDC = (Get-CimInstance Win32_OperatingSystem).ProductType -eq 2
if (-not $IsDC) {
    reg save HKLM\SAM (Join-Path $HiveDir "SAM.hive") /y | Out-Null
    secedit /export /cfg (Join-Path $BackupDir "LocalSecPol.cfg") | Out-Null
}
reg export "HKLM\SYSTEM\CurrentControlSet\Services" (Join-Path $BackupDir "Services_Full_Restorable.reg") /y | Out-Null

# 6. Persistence & WMI Check
$PersistDir = Join-Path $BackupDir "Persistence"
New-Item -ItemType Directory -Path $PersistDir -Force | Out-Null

$wmiFilters   = Get-CimInstance -Namespace root\subscription -ClassName __EventFilter
$wmiConsumers = Get-CimInstance -Namespace root\subscription -ClassName __EventConsumer
$wmiBindings  = Get-CimInstance -Namespace root\subscription -ClassName __FilterToConsumerBinding

$wmiFilters   | Export-Clixml (Join-Path $PersistDir "WMI_Filters.xml")
$wmiConsumers | Export-Clixml (Join-Path $PersistDir "WMI_Consumers.xml")
$wmiBindings  | Export-Clixml (Join-Path $PersistDir "WMI_Bindings.xml")

if ($wmiBindings) {
    "`n[!] ACTIVE WMI EVENT CONSUMER BINDINGS FOUND (HIGH RISK PERSISTENCE):" | Out-File $FlagFile -Append
    $wmiBindings | Out-String | Out-File $FlagFile -Append
}

Get-ScheduledTask | Export-Clixml (Join-Path $PersistDir "ScheduledTasks.xml")
$services = Get-CimInstance Win32_Service
$services | Select-Object Name, DisplayName, State, StartMode, StartName, PathName | Export-Csv (Join-Path $PersistDir "Services.csv") -NoTypeInformation

$susServices = $services | Where-Object { $_.PathName -match '\\AppData\\|\\Temp\\|\\Users\\Public\\' }
if ($susServices) {
    "`n[!] SUSPICIOUS SERVICE PATHS DETECTED:" | Out-File $FlagFile -Append
    $susServices | Select-Object Name, PathName, StartName | Out-String | Out-File $FlagFile -Append
}

reg export "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" (Join-Path $PersistDir "HKLM_Run.reg") /y | Out-Null
reg export "HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce" (Join-Path $PersistDir "HKLM_RunOnce.reg") /y | Out-Null
reg export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options" (Join-Path $PersistDir "IFEO.reg") /y | Out-Null
reg export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows" (Join-Path $PersistDir "AppInit.reg") /y | Out-Null

# 7. LSA Packages & Shares
$LsaDir = Join-Path $BackupDir "LSA_And_Signing"
New-Item -ItemType Directory -Path $LsaDir -Force | Out-Null
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "Notification Packages", "Authentication Packages", "Security Packages" | Out-File (Join-Path $LsaDir "LSA_Packages.txt")
reg export "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Shares" (Join-Path $LsaDir "Shares_Registry.reg") /y | Out-Null
reg export "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" (Join-Path $LsaDir "LanmanServer_Params.reg") /y | Out-Null
reg export "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" (Join-Path $LsaDir "LanmanWorkstation_Params.reg") /y | Out-Null

# 8. Event Logs
$LogDir = Join-Path $BackupDir "EventLogs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
wevtutil epl Security (Join-Path $LogDir "Security.evtx")
wevtutil epl System (Join-Path $LogDir "System.evtx")
wevtutil epl "Microsoft-Windows-PowerShell/Operational" (Join-Path $LogDir "PowerShell_Operational.evtx")

Write-Host "[+] Base Backup & Fast Triage Completed: $BackupDir" -ForegroundColor Green
