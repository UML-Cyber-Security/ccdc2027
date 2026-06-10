<#!
.SYNOPSIS
    Certificate Authority Automation
.DESCRIPTION
    Functions for installing, uninstalling, and publishing Enterprise Root CAs.
#>

$Global:LogPath = "C:\CA-Automation.log"
function Log([string]$Message) {
    try {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$ts - $Message" | Out-File -FilePath $Global:LogPath -Append -Encoding utf8
    } catch { }
}

function Require-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script in an elevated PowerShell session (Run as Administrator)."
    }
}

function Pause-IfInteractive {
    if ($Host.Name -match 'ConsoleHost|Windows PowerShell ISE') {
        Write-Host
        Read-Host "Press Enter to continue..."
    }
}

function Detect-ExistingPrivateKey {
    param([string]$Name)

    $machineKeysPath = "C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys"
    $cngKeysPath     = "C:\ProgramData\Microsoft\Crypto\Keys"

    $keyMatches = @()
    $pattern = [Regex]::Escape($Name)

    $keyMatches += Get-ChildItem $machineKeysPath -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pattern }
    $keyMatches += Get-ChildItem $cngKeysPath -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pattern }

    return $keyMatches
}

function CA-InstallEnterpriseRoot {
    param ([string]$CAName)

    Write-Host "WARNING: Do NOT reuse a CA name that has ever been used before." -ForegroundColor Yellow
    if (-not $CAName) { 
        $CAName = Read-Host "Enter CA Common Name (e.g. ROOT-CA)" 
    }

    Write-Host "Checking whether '$CAName' is associated with old private keys..." -ForegroundColor Yellow
    $keyOutput = certutil -csp "Microsoft Software Key Storage Provider" -key 2>$null
    $existingKeys = $keyOutput | Where-Object { $_ -match $CAName }

    if ($existingKeys.Count -gt 0) {
        Write-Host "ERROR: A private key container already exists for CA name '$CAName'." -ForegroundColor Red
        Write-Host "Found matching key container(s):" -ForegroundColor Red
        $existingKeys | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        Write-Host "Choose a completely new CA Common Name. Installation aborted." -ForegroundColor Red
        Log "Installation aborted: private key exists for $CAName"
        return
    }

    if ($CAName.Length -gt 50) { 
        Write-Host "ERROR: CA name too long." -ForegroundColor Red
        return
    }
    if ($CAName -match '[,\/\\\+\=\;\<\>\#\""]') { 
        Write-Host "ERROR: CA name contains invalid characters." -ForegroundColor Red
        return 
    }

    Write-Host "Installing Enterprise Root CA: $CAName" -ForegroundColor Yellow

    Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools
    Import-Module ADCSDeployment

    try {
        Install-ADCSCertificationAuthority `
            -CAType EnterpriseRootCA `
            -CACommonName $CAName `
            -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" `
            -HashAlgorithmName "SHA256" `
            -KeyLength 4096 `
            -ValidityPeriod Years `
            -ValidityPeriodUnits 20 `
            -Force

        Write-Host "CA installation complete." -ForegroundColor Green
    } catch { Write-Host "Installation error: $_" -ForegroundColor Yellow }
}

function CA-PublishToAD {
    $name = Read-Host "Enter CA Common Name to publish (e.g. ROOT-CA)"
    Log "CA-PublishToAD for $name"

    $crt = Get-ChildItem "C:\Windows\System32\CertSrv\CertEnroll" -Filter "*$name*.crt" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($crt) {
        Write-Host "Publishing $($crt.Name) to AD..." -ForegroundColor Yellow
        certutil -dspublish -f $crt.FullName RootCA
        certutil -crl
        Write-Host "Published successfully." -ForegroundColor Green
        Log "CA published: $($crt.FullName)"
    } else {
        Write-Host "No matching CA cert found." -ForegroundColor Red
        Log "CA publish failed: no cert for $name"
    }
}

function CA-Uninstall {
    Write-Host "Uninstalling Certificate Authority..." -ForegroundColor Yellow
    Log "CA-Uninstall starting"

    $CAName = Read-Host "Enter the CA Common Name for cleanup (e.g. ROOT-CA)"
    $Domain = Read-Host "Enter your domain (e.g. zodu.com)"

    if (Get-Module -ListAvailable -Name ActiveDirectory) {
        Import-Module ActiveDirectory

        $dnParts = $Domain.Split(".") | ForEach-Object { "DC=$_" }
        $DomainDN = ($dnParts -join ",")
        $ConfigNC = "CN=Configuration,$DomainDN"

        $PKIObjects = Get-ADObject -LDAPFilter "(|(objectClass=pKIEnrollmentService)(objectClass=certificationAuthority)(objectClass=cRLDistributionPoint)(objectClass=pKIPublicationPoint))" `
            -SearchBase "CN=Public Key Services,CN=Services,$ConfigNC" -Properties *

        $staleObjects = $PKIObjects | Where-Object { $_.CN -ne "NTAuthCertificates" }

        if ($staleObjects.Count -gt 0) {
            Write-Host ""
            $staleObjects | ForEach-Object { Write-Host " - $($_.CN)" }

            $delAD = Read-Host "Delete these AD PKI objects? (Y/N)"
            if ($delAD -eq "Y") {
                foreach ($obj in $staleObjects) {
                    try { Remove-ADObject -Identity $obj.DistinguishedName -Recursive -Confirm:$false } catch {}
                }
            }
        }
    }

    try { Import-Module ADCSDeployment -ErrorAction Stop } catch {}
    try { Uninstall-ADCSCertificationAuthority -Force } catch {}
    try { Remove-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools } catch {}

    Remove-Item -Recurse -Force "C:\Windows\System32\CertLog" -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force "C:\Windows\System32\CertSrv" -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "CA uninstalled successfully." -ForegroundColor Green
    Write-Host "Restart the machine" -ForegroundColor Yellow
    Log "CA-Uninstall complete"
}

function Show-CAMenu {
    Clear-Host
    Write-Host "This script should only be used after the CA has been joined to the AD" -ForegroundColor Red
    Write-Host "You must be logged in as domain\Administrator" -ForegroundColor Red
    Write-Host ""
    Write-Host "=== CA Actions ===" -ForegroundColor Cyan
    Write-Host "1) Install Enterprise Root CA"
    Write-Host "2) Publish CA certificate to AD"
    Write-Host "3) Uninstall CA"
    Write-Host "4) Exit"
}

Require-Admin
$exitScript = $false
while (-not $exitScript) {
    Show-CAMenu
    $choice = Read-Host "Choose (1-4)"
    switch ($choice) {
        1 { CA-InstallEnterpriseRoot; Pause-IfInteractive }
        2 { CA-PublishToAD; Pause-IfInteractive }
        3 { CA-Uninstall; Pause-IfInteractive }
        4 { $exitScript = $true }
        default { Write-Host "Invalid choice."; Pause-IfInteractive }
    }
}
Write-Host "Exiting script." -ForegroundColor Cyan