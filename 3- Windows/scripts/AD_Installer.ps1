<#!
.SYNOPSIS
    Active Directory Automation (State-Aware Menu Tool)
.DESCRIPTION
    Functions for installing, uninstalling, Promote, Demote, and check current state of the AD.
#>

$ErrorActionPreference = 'Continue'

function Show-FatalError {
    param([string]$Message)
    Write-Host ""
    Write-Host "ERROR:" -ForegroundColor Red
    Write-Host $Message -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to exit"
}

function Require-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Show-FatalError "This script must be run as Administrator."
        exit
    }
}

function Pause {
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Get-NetbiosFromDomain {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Fqdn
    )
    $Fqdn.Split('.')[0].ToUpper()
}

# This hashmap contains an InstallDomain/Forest, which is used for the Install-ADDSForest command. It contains DomainMode/ForestMode for the Set-ADDomainMode command.
# For some ungodly reason, these 2 functions need slightly different inputs to work.
# The hashmap also includes Order, which is used to make sure you can't transform a new server into an old one.
$FuncLevelMap = @{
    "2008R2" = @{
        InstallDomain = "Win2008R2"
        InstallForest = "Win2008R2"
        DomainMode    = "Windows2008R2Domain"
        ForestMode    = "Windows2008R2Forest"
        Order         = 1
    }
    "2012" = @{
        InstallDomain = "Win2012"
        InstallForest = "Win2012"
        DomainMode    = "Windows2012Domain"
        ForestMode    = "Windows2012Forest"
        Order         = 2
    }
    "2012R2" = @{
        InstallDomain = "Win2012R2"
        InstallForest = "Win2012R2"
        DomainMode    = "Windows2012R2Domain"
        ForestMode    = "Windows2012R2Forest"
        Order         = 3
    }
    "2016" = @{
        InstallDomain = "WinThreshold"        
        InstallForest = "WinThreshold"
        DomainMode    = "Windows2016Domain"  
        ForestMode    = "Windows2016Forest"
        Order         = 4
    }
}

function Prompt-FunctionalLevel {
    Write-Host "Available Levels: $($FuncLevelMap.Keys -join ', ')"
    while ($true) {
        $l = Read-Host "Enter functional level"
        if ($FuncLevelMap.ContainsKey($l)) { return $l }
        Write-Host "Invalid level." -ForegroundColor Red
    }
}

function Prompt-Domain {
    while ($true) {
        $d = Read-Host "Enter domain FQDN"
        if ($d -and $d.Contains('.')) { return $d }
        Write-Host "Invalid domain." -ForegroundColor Red
    }
}

function Get-NetBIOS([string]$Domain) {
    return $Domain.Split('.')[0].ToUpper()
}

function Get-ADState {
    $feature = Get-WindowsFeature AD-Domain-Services -ErrorAction SilentlyContinue
    $svc = Get-Service NTDS -ErrorAction SilentlyContinue

    if ($svc -and $svc.Status -eq 'Running') { return "DomainController" }
    if ($feature -and $feature.Installed) { return "InstalledNotPromoted" }
    return "NotInstalled"
}

function Show-ADState {
    $state = Get-ADState
    Write-Host "AD State: $state" -ForegroundColor Cyan

    if ($state -eq "DomainController") {
        try {
            Import-Module ActiveDirectory -ErrorAction Stop
            $d = Get-ADDomain
            $f = Get-ADForest
            Write-Host "Domain: $($d.DNSRoot) ($($d.DomainMode))"
            Write-Host "Forest: $($f.Name) ($($f.ForestMode))"
        }
        catch {
            Write-Host "ActiveDirectory module unavailable." -ForegroundColor Yellow
        }
    }
}

function Check-OtherDCs {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $dcs = Get-ADDomainController -Filter *
        return ($dcs.Count -gt 1)
    }
    catch {
        Write-Host "Could not query other DCs." -ForegroundColor Yellow
        return $false
    }
}

function Demote-DC {

    try {
        $forest = Get-ADForest -ErrorAction Stop
    }
    catch {
        Write-Host "This server is not part of an Active Directory forest. Demotion not possible." -ForegroundColor Yellow
        return
    }

    if (-not (Check-OtherDCs)) {
        Write-Host "THIS IS THE LAST DC." -ForegroundColor Red
        $c = Read-Host "Destroy domain? (Y/N)"
        if ($c -notmatch '^[Yy]$') { return }


        #https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/demoting-domain-controllers-and-domains--level-200-
        Uninstall-ADDSDomainController -LastDomainControllerInDomain -RemoveApplicationPartitions
        Uninstall-WindowsFeature
    }
    else {
        Uninstall-ADDSDomainController `
            -DemoteOperationMasterRole `
            -RemoveApplicationPartitions `
            -Force
    }
}

function Install-ADRole {
    Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
}

function Uninstall-ADRole {
    $state = Get-ADState

    if ($state -eq "DomainController") {
        Write-Host "Server is still a Domain Controller. You must demote it before uninstalling AD DS!" -ForegroundColor Red
        return
    }

    Uninstall-WindowsFeature AD-Domain-Services -IncludeManagementTools -Restart
}

function Promote-NewForest {
    $state = Get-ADState
    if ($state -eq "DomainController") {
        Write-Host "This server is already a Domain Controller for an existing forest." -ForegroundColor Red
        return
    }
    elseif ($state -eq "InstalledNotPromoted") {
        $domain = Prompt-Domain
        $netbios = Get-NetbiosFromDomain $domain
        $choice = Prompt-FunctionalLevel
        $map = $FuncLevelMap[$choice]

        Install-ADDSForest `
            -DomainName $domain `
            -DomainNetbiosName $netbios `
            -DomainMode $map.InstallDomain `
            -ForestMode $map.InstallForest `
            -InstallDNS:$true `
            -CreateDnsDelegation:$false `
            -DatabasePath "C:\Windows\NTDS" `
            -SysvolPath "C:\Windows\SYSVOL" `
            -LogPath "C:\Windows\NTDS" `
            -Force:$true `
            -NoRebootOnCompletion:$false
    }
        
    else {
        Write-Host "AD DS role not installed." -ForegroundColor Yellow
    }
}

function Upgrade-FunctionalLevel {
    Import-Module ActiveDirectory

    while ($true) {
        $domainFqdn = Read-Host "Enter EXISTING domain FQDN: "
        try {
            $domain = Get-ADDomain -Identity $domainFqdn -ErrorAction Stop
            break 
        } catch {
            Write-Host "The domain '$domainFqdn' does not exist or is unreachable. Please try again." -ForegroundColor Red
        }
    }
    
    $lvl = Prompt-FunctionalLevel
    $target = $FuncLevelMap[$lvl]

    #needed because of discrepancy between Set-ADDomainMode and Install-ADDSForest flags naming convention
    $EnumToShortKey = @{
        "Windows2008Domain"   = "2008"
        "Windows2008R2Domain" = "2008R2"
        "Windows2012Domain"   = "2012"
        "Windows2012R2Domain" = "2012R2"
        "Windows2016Domain"   = "2016"
    }

    $current = $FuncLevelMap[$EnumToShortKey[$domain.DomainMode.ToString()]]

    if ($current.Order -ge $target.Order) {
        Write-Host "Cannot lower or keep the same functional level. Current domain/forest is already at the same or higher level." -ForegroundColor Red
        return
    }

    Set-ADDomainMode -Identity $domain -DomainMode $target.DomainMode
    Set-ADForestMode -Identity $domain -ForestMode $target.ForestMode
}

function Show-Menu {
    Clear-Host
    Write-Host "=== Active Directory Menu ===" -ForegroundColor Cyan
    Write-Host "1) Demote Domain Controller"
    Write-Host "2) Uninstall AD DS Role"
    Write-Host "3) Install AD DS Role"
    Write-Host "4) Promote to New Forest"
    Write-Host "5) Upgrade Functional Level"
    Write-Host "6) Show AD State"
    Write-Host "7) Exit"
}

Require-Admin

while ($true) {
    Show-Menu
    $c = Read-Host "Choose (1-8)"
    switch ($c) {
        1 { Demote-DC }
        2 { Uninstall-ADRole }
        3 { Install-ADRole }
        4 { Promote-NewForest }
        5 { Upgrade-FunctionalLevel }
        6 { Show-ADState }
        7 {
            exit
        }
        default {
            Write-Host "Invalid choice." -ForegroundColor Red
        }
    }
    Pause
}
