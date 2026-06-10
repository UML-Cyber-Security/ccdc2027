<#
.SYNOPSIS
    Incident Response Toolkit - Merged detection and response functions.
.DESCRIPTION
    Runs all detection functions by default, or specify individual ones via -Function.
    Functions: Block-OutboundIP, Find-RecentAccounts, Get-RecentSecurityEvents,
               Search-FailedLogons, Find-HiddenExecutables, Get-SuspiciousConnections,
               Get-RecentProcesses
.PARAMETER Function
    Name of a specific function to run. If omitted, runs all detection functions.
.PARAMETER IP
    IP address for Block-OutboundIP.
.PARAMETER MinutesAgo
    Lookback window in minutes for Get-RecentProcesses (default 10).
.EXAMPLE
    .\IncidentResponse.ps1
    .\IncidentResponse.ps1 -Function Find-HiddenExecutables
    .\IncidentResponse.ps1 -Function Block-OutboundIP -IP "10.0.0.50"
    .\IncidentResponse.ps1 -Function Get-RecentProcesses -MinutesAgo 30
#>
param (
    [string]$Function,
    [string]$IP,
    [int]$MinutesAgo = 10
)

function Block-OutboundIP {
    param ([string]$RemoteAddress)
    if (-not $RemoteAddress) {
        Write-Host "Usage: -Function Block-OutboundIP -IP <address>" -ForegroundColor Yellow
        return
    }
    New-NetFirewallRule -DisplayName "Block Evil IP - $RemoteAddress" -Direction Outbound -RemoteAddress $RemoteAddress -Action Block
    Write-Host "Blocked outbound traffic to $RemoteAddress" -ForegroundColor Green
}

function Find-RecentAccounts {
    Write-Host "`n=== Recently Created Local Accounts (last hour) ===" -ForegroundColor Cyan
    $accounts = Get-LocalUser | Where-Object { $_.WhenCreated -gt (Get-Date).AddHours(-1) }
    if ($accounts) { $accounts } else { Write-Host "No accounts created in the last hour." }
}

function Get-RecentSecurityEvents {
    Write-Host "`n=== Last 20 Security Event Log Entries ===" -ForegroundColor Cyan
    Get-WinEvent -LogName Security -MaxEvents 20 | Format-List
}

function Search-FailedLogons {
    Write-Host "`n=== Failed Logon Attempts (Event 4625) ===" -ForegroundColor Cyan
    Get-WinEvent -LogName Security | Where-Object {
        $_.Id -eq 4625
    } | Format-Table TimeCreated, Message -AutoSize
}

function Find-HiddenExecutables {
    Write-Host "`n=== Hidden Executables (.exe, .ps1, .bat) ===" -ForegroundColor Cyan
    Get-ChildItem -Path C:\ -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Attributes -match 'Hidden' -and $_.Extension -match '\.(exe|ps1|bat)' }
}

function Get-SuspiciousConnections {
    Write-Host "`n=== TCP Connections with Process Info ===" -ForegroundColor Cyan
    Get-NetTCPConnection | ForEach-Object {
        $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            LocalAddress  = $_.LocalAddress
            LocalPort     = $_.LocalPort
            RemoteAddress = $_.RemoteAddress
            RemotePort    = $_.RemotePort
            State         = $_.State
            Process       = $proc.ProcessName
            PID           = $_.OwningProcess
        }
    } | Format-Table -AutoSize
}

function Get-RecentProcesses {
    param ([int]$Minutes = 10)
    Write-Host "`n=== Processes Created in Last $Minutes Minutes ===" -ForegroundColor Cyan
    $cutoffTime = (Get-Date).AddMinutes(-$Minutes)
    Get-Process | ForEach-Object {
        try {
            if ($_.StartTime -gt $cutoffTime) { $_ }
        } catch {
            # Some system processes may not expose StartTime
        }
    }
}

# Main execution
if ($Function) {
    switch ($Function) {
        'Block-OutboundIP'      { Block-OutboundIP -RemoteAddress $IP }
        'Find-RecentAccounts'   { Find-RecentAccounts }
        'Get-RecentSecurityEvents' { Get-RecentSecurityEvents }
        'Search-FailedLogons'   { Search-FailedLogons }
        'Find-HiddenExecutables' { Find-HiddenExecutables }
        'Get-SuspiciousConnections' { Get-SuspiciousConnections }
        'Get-RecentProcesses'   { Get-RecentProcesses -Minutes $MinutesAgo }
        default { Write-Host "Unknown function: $Function. Available: Block-OutboundIP, Find-RecentAccounts, Get-RecentSecurityEvents, Search-FailedLogons, Find-HiddenExecutables, Get-SuspiciousConnections, Get-RecentProcesses" -ForegroundColor Red }
    }
} else {
    Write-Host "=== INCIDENT RESPONSE TOOLKIT ===" -ForegroundColor Green
    Write-Host "Running all detection functions...`n" -ForegroundColor Green
    Find-RecentAccounts
    Get-RecentSecurityEvents
    Search-FailedLogons
    Find-HiddenExecutables
    Get-SuspiciousConnections
    Get-RecentProcesses -Minutes $MinutesAgo
}
