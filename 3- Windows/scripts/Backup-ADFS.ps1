# Requires -RunAsAdministrator
[CmdletBinding()]
param (
    [string]$RootPath = "C:\IR_Backup"
)
$ErrorActionPreference = "SilentlyContinue"
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'$AdfsDir = Join-Path $RootPath "ADFSBackup_$Timestamp"
New-Item -ItemType Directory -Path $AdfsDir -Force | Out-Null

$FlagFile = Join-Path$AdfsDir "ADFS_TRIAGE_FLAGS.txt"
"=== AD FS TRIAGE FLAGS ($Timestamp) ===" \vert{} Out-File $FlagFile

Write-Host "[+] Starting Active Directory Federation Services (AD FS) Backup..." -ForegroundColor Cyan

if (Get-Module -ListAvailable -Name ADFS) {
    Import-Module ADFS

    # 1. Relying Party Trusts & Claim Rules
    Write-Host "[*] Exporting Relying Party Trusts and Issuance Rules..." -ForegroundColor Yellow
    $trusts = Get-AdfsRelyingPartyTrust$trusts | Select-Object Name, Identifier, Enabled, IssuanceTransformRules, IssuanceAuthorizationRules | 
        Export-Clixml (Join-Path $AdfsDir "RelyingPartyTrusts.xml")

    # Flag wide-open authorization rules
    foreach ($trust in$trusts) {
        if ($trust.IssuanceAuthorizationRules -match "c:\[\]\s*=>\s*issue\(Type\s*=\s*.*Allow.*") {
            "`n[!] PERMISSIVE AUTH CLAIM RULE ON TRUST: $($trust.Name)" | Out-File $FlagFile -Append
        }
    }

    # 2. Claims Provider Trusts
    Get-AdfsClaimsProviderTrust | 
        Select-Object Name, Identifier, Enabled | 
        Export-Clixml (Join-Path $AdfsDir "ClaimsProviderTrusts.xml")

    # 3. AD FS Certificates
    Write-Host "[*] Exporting AD FS Certificate metadata..." -ForegroundColor Yellow
    $certs = Get-AdfsCertificate
    $certs | Select-Object CertificateType, Thumbprint, IsPrimary | 
        Export-Csv (Join-Path $AdfsDir "ADFS_Certificates.csv") -NoTypeInformation

    # Flag token-signing certs missing private key or nearing expiration
    foreach ($cert in $certs) {
        if ($cert.Certificate.NotAfter -lt (Get-Date).AddDays(14)) {
            "`n[!] AD FS CERTIFICATE EXPIRING SOON ($($cert.CertificateType)): Thumbprint$($cert.Thumbprint)" \vert{} Out-File $FlagFile -Append
        }
    }

    # 4. Global AD FS Properties
    Get-AdfsProperties | Export-Clixml (Join-Path $AdfsDir "AdfsProperties.xml")
} else {
    Write-Host "[-] ADFS PowerShell module not found on this system." -ForegroundColor Red
    "[-] ADFS PowerShell module was not found on this system." | Out-File $FlagFile -Append
}

Write-Host "[+] AD FS Backup Completed: $AdfsDir" -ForegroundColor Green