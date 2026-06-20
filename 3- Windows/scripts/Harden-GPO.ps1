param(
    [switch]$All,              # Run everything (default if no flags)
    [switch]$Reset,            # dcgpofix /target:both
    [switch]$AuditPolicy,      # Audit logging + PowerShell logging
    [switch]$PasswordPolicy,   # Password + lockout policy
    [switch]$ScriptPolicy,     # AllSigned execution policy
    [switch]$Encryption,       # SMB, Kerberos, NTLM, LDAP
    [switch]$CredProtection,   # WDigest, anonymous restriction
    [switch]$NetworkHardening, # LLMNR, NBT-NS, WPAD, NLA for RDP
    [switch]$SkipReset,        # Run -All but skip GPO reset
    [switch]$NoLSAProtection,  # Skip RunAsPPL (use if you have unsigned SSPs / smart-card middleware)
    [Alias("S")]
    [switch]$Safe,             # Safe mode: skips settings that could break services
    [Alias("SS")]
    [switch]$SuperSafe,        # Super-safe: only logging + password policy (zero breakage)
    [string]$GPOName = "Hardening"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Banner { param([string]$Text); Write-Host "`n=== $Text ===" -ForegroundColor Cyan }
function Write-Setting { param([string]$Text); Write-Host "  [+] $Text" -ForegroundColor Green }
function Write-Warn    { param([string]$Text); Write-Host "  [!] $Text" -ForegroundColor Yellow }
function Write-Verify  { param([string]$Text); Write-Host "  [?] $Text" -ForegroundColor Magenta }
function Write-Fail    { param([string]$Text); Write-Host "  [X] $Text" -ForegroundColor Red; $script:failures += $Text }

$script:failures = @()

function Test-Result {
    param([string]$Label, $Expected, $Actual)
    if ("$Actual" -eq "$Expected") {
        Write-Verify "PASS: $Label (expected=$Expected)"
    } else {
        Write-Fail "FAIL: $Label (expected=$Expected, got=$Actual)"
    }
}

function Set-RegValue {
    param(
        [string]$GPOName,
        [string]$Key,
        [string]$ValueName,
        $Value,
        [Microsoft.Win32.RegistryValueKind]$Type = [Microsoft.Win32.RegistryValueKind]::DWord
    )
    Set-GPRegistryValue -Name $GPOName -Key $Key -ValueName $ValueName -Value $Value -Type $Type | Out-Null
    Write-Setting "$Key\$ValueName = $Value"
    try {
        $readBack = (Get-GPRegistryValue -Name $GPOName -Key $Key -ValueName $ValueName -ErrorAction Stop).Value
        Test-Result "$Key\$ValueName" $Value $readBack
    } catch {
        Write-Fail "FAIL: Could not read back $Key\$ValueName"
    }
}

# ── Preflight ────────────────────────────────────────────────────────────────

Write-Banner "Preflight checks"

# Must be Domain Controller
$os = Get-CimInstance Win32_OperatingSystem
if ($os.ProductType -ne 2) {
    Write-Error "This script must run on a Domain Controller (ProductType 2). Current: $($os.ProductType)"
    exit 1
}
Write-Setting "Running on Domain Controller: $($env:COMPUTERNAME)"

# Detect OS version for feature support
$osBuild = [int]$os.BuildNumber
# RelaxMinimumPasswordLengthLimits requires build 19041+ (Win10 2004 / Server 2022)
# Server 2019 = build 17763, Server 2022 = build 20348
$isLegacyPasswordPolicy = $osBuild -lt 19041
if ($isLegacyPasswordPolicy) {
    Write-Warn "Server 2019 or older detected (build $osBuild) — password length capped at 14"
} else {
    Write-Setting "Modern OS detected (build $osBuild) — full password policy support"
}

# Import required modules
foreach ($mod in @("GroupPolicy", "ActiveDirectory")) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Error "Required module '$mod' is not installed."
        exit 1
    }
    Import-Module $mod -ErrorAction Stop
    Write-Setting "Module loaded: $mod"
}

$adDomain = Get-ADDomain
$Domain = $adDomain.DNSRoot
$DomainDN = $adDomain.DistinguishedName
$DomainSID = $adDomain.DomainSID.Value
Write-Setting "Domain: $Domain ($DomainDN)"

# ── Backup existing GPOs ────────────────────────────────────────────────────

Write-Banner "Backing up existing GPOs"
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$exportPath = "C:\GPO-Export-$ts"
New-Item -Path $exportPath -ItemType Directory -Force | Out-Null
try {
    Get-GPO -All | ForEach-Object {
        Backup-GPO -Guid $_.Id -Path $exportPath -ErrorAction Stop | Out-Null
        Write-Host "  Backed up: $($_.DisplayName)" -ForegroundColor Gray
    }
    Compress-Archive -Path "$exportPath\*" -DestinationPath "$exportPath.zip" -ErrorAction Stop -Force
    Remove-Item -Path $exportPath -Recurse -Force
    Write-Setting "All GPOs exported to $exportPath.zip"
} catch {
    Write-Fail "GPO backup failed: $_"
    Write-Host "    Aborting — will NOT reset GPOs without a good backup." -ForegroundColor Red
    return
}

# ── Resolve which sections to run ────────────────────────────────────────────

# Safety modes override individual flags
if ($SuperSafe) {
    Write-Banner "Mode: SUPER-SAFE (logging + passwords only)"
    $runReset            = $false
    $runAuditPolicy      = $true
    $runPasswordPolicy   = $true
    $runScriptPolicy     = $false
    $runEncryption       = $false
    $runCredProtection   = $false
    $runNetworkHardening = $false
} elseif ($Safe) {
    Write-Banner "Mode: SAFE (skipping risky settings)"
    $runReset            = $false
    $runAuditPolicy      = $true
    $runPasswordPolicy   = $true
    $runScriptPolicy     = $false
    $runEncryption       = $true
    $runCredProtection   = $true
    $runNetworkHardening = $true
} else {
    $flags = @($Reset, $AuditPolicy, $PasswordPolicy, $ScriptPolicy,
               $Encryption, $CredProtection, $NetworkHardening, $SkipReset)
    $anyFlag = $flags | Where-Object { $_ }

    if (-not $anyFlag) { $All = [switch]::Present }
    if ($SkipReset) { $All = [switch]::Present }

    $runReset            = $All -and -not $SkipReset -or $Reset
    $runAuditPolicy      = $All -or $AuditPolicy
    $runPasswordPolicy   = $All -or $PasswordPolicy
    $runScriptPolicy     = $All -or $ScriptPolicy
    $runEncryption       = $All -or $Encryption
    $runCredProtection   = $All -or $CredProtection
    $runNetworkHardening = $All -or $NetworkHardening
}

$summary = @()

# ── Reset ────────────────────────────────────────────────────────────────────

if ($runReset) {
    Write-Banner "GPO Reset (dcgpofix)"
    Write-Warn "Resetting Default Domain Policy and Default Domain Controllers Policy"
    Get-GPO -All | Where-Object { $_.DisplayName -notin "Default Domain Policy","Default Domain Controllers Policy" } | ForEach-Object {
        Write-Host "  Removing GPO: $($_.DisplayName)" -ForegroundColor Yellow
        Remove-GPO -Guid $_.Id -ErrorAction SilentlyContinue
    }
    "Y","Y" | dcgpofix /target:both 2>&1 | ForEach-Object { Write-Host "    $_" }
    $dcgpofixExit = $LASTEXITCODE
    & gpupdate /force 2>&1 | Out-Null
    $summary += "GPO Reset"
    Write-Setting "GPO reset complete"
    Test-Result "dcgpofix exit code" 0 $dcgpofixExit
}

# ── Create / Get hardening GPO ───────────────────────────────────────────────

$needGPO = $runAuditPolicy -or $runScriptPolicy -or $runEncryption -or $runCredProtection -or $runNetworkHardening

if ($needGPO) {
    Write-Banner "GPO Setup"
    $gpo = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $GPOName
        Write-Setting "Created GPO: $GPOName"
    } else {
        Write-Setting "Using existing GPO: $GPOName"
    }

    try {
        New-GPLink -Name $GPOName -Target $DomainDN -LinkEnabled Yes -ErrorAction Stop | Out-Null
        Write-Setting "Linked GPO to $DomainDN"
    } catch {
        if ($_.Exception.Message -match "already linked|already exists") {
            Write-Setting "GPO already linked to $DomainDN"
        } else { throw }
    }

    $verifyGpo = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
    Test-Result "GPO '$GPOName' exists" $true ($null -ne $verifyGpo)
    $inheritance = Get-GPInheritance -Target $DomainDN
    $linked = $inheritance.GpoLinks | Where-Object { $_.DisplayName -eq $GPOName }
    Test-Result "GPO '$GPOName' linked to domain" $true ($null -ne $linked)
}

# ── Audit Policy ─────────────────────────────────────────────────────────────

if ($runAuditPolicy) {
    Write-Banner "Audit Policy"

    Write-Setting "Writing audit policy to GptTmpl.inf"
    $gpoId = "{$($gpo.Id.ToString().ToUpper())}"
    $secEditPath = "\\$Domain\SYSVOL\$Domain\Policies\$gpoId\Machine\Microsoft\Windows NT\SecEdit"

    if (-not (Test-Path $secEditPath)) {
        New-Item -Path $secEditPath -ItemType Directory -Force | Out-Null
    }

    # 3 = Success and Failure; 0 = No Auditing
    # Only enable categories that WinStride/Sysmon actually consume
    $gptTmpl = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Event Audit]
AuditSystemEvents = 3
AuditLogonEvents = 3
AuditObjectAccess = 3
AuditPrivilegeUse = 0
AuditPolicyChange = 0
AuditAccountManage = 3
AuditProcessTracking = 3
AuditDSAccess = 3
AuditAccountLogon = 3
[Privilege Rights]
SeRemoteInteractiveLogonRight = *S-1-5-32-544,*S-1-5-32-555,*$DomainSID-513
"@
    $gptTmpl | Out-File -FilePath "$secEditPath\GptTmpl.inf" -Encoding Unicode -Force
    Write-Setting "GptTmpl.inf written (7 categories enabled, 2 disabled)"

    $securityCSE = "[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}]"
    $gpoDN = "CN=$gpoId,CN=Policies,CN=System,$DomainDN"
    $gpoAD = Get-ADObject -Identity $gpoDN -Properties gPCMachineExtensionNames
    $currentCSE = $gpoAD.gPCMachineExtensionNames
    if (-not $currentCSE) { $currentCSE = "" }
    if ($currentCSE -notmatch [regex]::Escape($securityCSE)) {
        $currentCSE += $securityCSE
        Set-ADObject -Identity $gpoDN -Replace @{gPCMachineExtensionNames = $currentCSE}
        Write-Setting "Security CSE registered"
    } else {
        Write-Setting "Security CSE already present"
    }

    $gpoAD = Get-ADObject -Identity $gpoDN -Properties versionNumber
    $newVer = [int]$gpoAD.versionNumber + 65536
    Set-ADObject -Identity $gpoDN -Replace @{versionNumber = $newVer}
    $gptIniPath = "\\$Domain\SYSVOL\$Domain\Policies\$gpoId\GPT.INI"
    $gptIniContent = Get-Content $gptIniPath -Raw -ErrorAction SilentlyContinue
    if ($gptIniContent) {
        $gptIniContent = $gptIniContent -replace "Version=\d+", "Version=$newVer"
        $gptIniContent | Out-File -FilePath $gptIniPath -Encoding ASCII -Force
    }
    Write-Setting "GPO version bumped to $newVer"

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\System\CurrentControlSet\Control\Lsa" `
        -ValueName "SCENoApplyLegacyAuditPolicy" -Value 0
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Lsa" -Name "SCENoApplyLegacyAuditPolicy" -Value 0 -Type DWord -Force
    Write-Setting "SCENoApplyLegacyAuditPolicy = 0 (legacy audit enabled)"

    # Only PowerShell logging — Sysmon handles process/cmdline tracking
    Write-Setting "Configuring registry-based logging"

    # PowerShell Script Block Logging (Event 4104)
    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" `
        -ValueName "EnableScriptBlockLogging" -Value 1

    # PowerShell Module Logging (Event 4103)
    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging" `
        -ValueName "EnableModuleLogging" -Value 1
    Set-GPRegistryValue -Name $GPOName `
        -Key "HKLM\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames" `
        -ValueName "*" -Value "*" -Type String | Out-Null
    Write-Setting "  ModuleNames\* = *"

    # Security log size: 1 GB
    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\Software\Policies\Microsoft\Windows\EventLog\Security" `
        -ValueName "MaxSize" -Value 1048576

    # Verify audit policy in GptTmpl.inf
    $verifyInf = Get-Content "$secEditPath\GptTmpl.inf" -ErrorAction SilentlyContinue
    if ($verifyInf) {
        $expectedAudit = @{
            AuditSystemEvents    = "3"
            AuditLogonEvents     = "3"
            AuditObjectAccess    = "3"
            AuditPrivilegeUse    = "0"
            AuditPolicyChange    = "0"
            AuditAccountManage   = "3"
            AuditProcessTracking = "3"
            AuditDSAccess        = "3"
            AuditAccountLogon    = "3"
        }
        foreach ($cat in $expectedAudit.Keys) {
            $match = $verifyInf | Where-Object { $_ -match "^\s*$cat\s*=" }
            if ($match -and $match -match "=\s*(\d+)") { $val = $Matches[1] } else { $val = "MISSING" }
            Test-Result "Audit $cat" $expectedAudit[$cat] $val
        }
    } else {
        Write-Fail "FAIL: Could not read back GptTmpl.inf for audit verification"
    }

    $summary += "Audit Policy"
}

# ── Password Policy ──────────────────────────────────────────────────────────

if ($runPasswordPolicy) {
    Write-Banner "Password & Lockout Policy"

    $ddpGpo = Get-GPO -Name "Default Domain Policy" -ErrorAction Stop
    $ddpId = "{$($ddpGpo.Id.ToString().ToUpper())}"
    $ddpSecEditPath = "\\$Domain\SYSVOL\$Domain\Policies\$ddpId\Machine\Microsoft\Windows NT\SecEdit"

    if (-not (Test-Path $ddpSecEditPath)) {
        New-Item -Path $ddpSecEditPath -ItemType Directory -Force | Out-Null
    }

    $ddpInfPath = "$ddpSecEditPath\GptTmpl.inf"

    # Enable MinimumPasswordLength > 14 (required before setting length to 16)
    # Server 2019 does not support RelaxMinimumPasswordLengthLimits — cap at 14
    if (-not $isLegacyPasswordPolicy) {
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\SAM" `
            -Name "RelaxMinimumPasswordLengthLimits" -Value 1 -Type DWord -Force
        Write-Setting "RelaxMinimumPasswordLengthLimits = 1 (allows MinPasswordLength > 14)"

        Set-GPRegistryValue -Name "Default Domain Policy" `
            -Key "HKLM\System\CurrentControlSet\Control\SAM" `
            -ValueName "RelaxMinimumPasswordLengthLimits" -Value 1 -Type DWord | Out-Null
        Write-Setting "RelaxMinimumPasswordLengthLimits pushed via Default Domain Policy GPO"
    } else {
        Write-Warn "Skipping RelaxMinimumPasswordLengthLimits (not supported on build $osBuild)"
    }

    $minPwdLen = if ($isLegacyPasswordPolicy) { 14 } else { 16 }

    # NIST SP 800-63B 2024: length-based policy, no composition rules
    $pwdSettings = [ordered]@{
        MinimumPasswordLength = $minPwdLen
        PasswordHistorySize   = 24
        MinimumPasswordAge    = 0
        MaximumPasswordAge    = -1
        PasswordComplexity    = 0
        ClearTextPassword     = 0
        LockoutBadCount       = 10
        ResetLockoutCount     = 15
        LockoutDuration       = 15
    }

    # AllowAdministratorLockout was added in Server 2022 (KB5020282) — doesn't exist on 2019
    if (-not $isLegacyPasswordPolicy) {
        $pwdSettings["AllowAdministratorLockout"] = 1
    } else {
        Write-Warn "Skipping AllowAdministratorLockout (not supported on build $osBuild)"
    }

    if (Test-Path $ddpInfPath) {
        $infContent = Get-Content $ddpInfPath -Raw
    } else {
        $infContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
"@
    }

    if ($infContent -notmatch '\[System Access\]') {
        $infContent += "`r`n[System Access]`r`n"
    }

    foreach ($key in $pwdSettings.Keys) {
        $val = $pwdSettings[$key]
        if ($infContent -match "(?m)^\s*$key\s*=") {
            $infContent = $infContent -replace "(?m)^\s*$key\s*=\s*.*$", "$key = $val"
        } else {
            $infContent = $infContent -replace "(\[System Access\])", "`$1`r`n$key = $val"
        }
    }

    $infContent | Out-File -FilePath $ddpInfPath -Encoding Unicode -Force
    foreach ($key in $pwdSettings.Keys) {
        Write-Setting "$key = $($pwdSettings[$key])"
    }

    $securityCSE = "[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}]"
    $ddpDN = "CN=$ddpId,CN=Policies,CN=System,$DomainDN"
    $ddpAD = Get-ADObject -Identity $ddpDN -Properties gPCMachineExtensionNames
    $currentCSE = $ddpAD.gPCMachineExtensionNames
    if (-not $currentCSE) { $currentCSE = "" }
    if ($currentCSE -notmatch [regex]::Escape($securityCSE)) {
        $currentCSE += $securityCSE
        Set-ADObject -Identity $ddpDN -Replace @{gPCMachineExtensionNames = $currentCSE}
        Write-Setting "Security CSE registered on Default Domain Policy"
    } else {
        Write-Setting "Security CSE already present on Default Domain Policy"
    }

    $ddpAD = Get-ADObject -Identity $ddpDN -Properties versionNumber
    $ddpNewVer = [int]$ddpAD.versionNumber + 65536
    Set-ADObject -Identity $ddpDN -Replace @{versionNumber = $ddpNewVer}
    $ddpGptIniPath = "\\$Domain\SYSVOL\$Domain\Policies\$ddpId\GPT.INI"
    $ddpGptIniContent = Get-Content $ddpGptIniPath -Raw -ErrorAction SilentlyContinue
    if ($ddpGptIniContent) {
        $ddpGptIniContent = $ddpGptIniContent -replace "Version=\d+", "Version=$ddpNewVer"
        $ddpGptIniContent | Out-File -FilePath $ddpGptIniPath -Encoding ASCII -Force
    }
    Write-Setting "Default Domain Policy version bumped to $ddpNewVer"

    # NIST SP 800-63B 2024: complexity disabled (no composition rules)
    Set-ADDefaultDomainPasswordPolicy -Identity $Domain `
        -MinPasswordLength $minPwdLen `
        -PasswordHistoryCount 24 `
        -MinPasswordAge ([TimeSpan]::Zero) `
        -MaxPasswordAge ([TimeSpan]::Zero) `
        -ComplexityEnabled $false `
        -LockoutThreshold 10 `
        -LockoutDuration (New-TimeSpan -Minutes 15) `
        -LockoutObservationWindow (New-TimeSpan -Minutes 15)
    Write-Setting "AD attributes set via Set-ADDefaultDomainPasswordPolicy"

    $verifyPwdInf = Get-Content $ddpInfPath -ErrorAction SilentlyContinue
    if ($verifyPwdInf) {
        foreach ($key in $pwdSettings.Keys) {
            $expected = "$($pwdSettings[$key])"
            $match = $verifyPwdInf | Where-Object { $_ -match "^\s*$key\s*=" }
            if ($match -and $match -match "=\s*(-?\d+)") { $val = $Matches[1] } else { $val = "MISSING" }
            Test-Result "Password GptTmpl $key" $expected $val
        }
    } else {
        Write-Fail "FAIL: Could not read back GptTmpl.inf for password verification"
    }

    $adPwd = Get-ADDefaultDomainPasswordPolicy -Identity $Domain
    Test-Result "AD MinPasswordLength" "$minPwdLen" "$($adPwd.MinPasswordLength)"
    Test-Result "AD PasswordHistoryCount" "24" "$($adPwd.PasswordHistoryCount)"
    Test-Result "AD ComplexityEnabled" "False" "$($adPwd.ComplexityEnabled)"
    Test-Result "AD LockoutThreshold" "10" "$($adPwd.LockoutThreshold)"

    $summary += "Password Policy"
}

# ── Script Execution Policy ──────────────────────────────────────────────────

if ($runScriptPolicy) {
    Write-Banner "Script Execution Policy"

    Set-GPRegistryValue -Name $GPOName `
        -Key "HKLM\Software\Policies\Microsoft\Windows\PowerShell" `
        -ValueName "ExecutionPolicy" -Value "AllSigned" -Type String | Out-Null
    Write-Setting "ExecutionPolicy = AllSigned"

    try {
        $readBack = (Get-GPRegistryValue -Name $GPOName `
            -Key "HKLM\Software\Policies\Microsoft\Windows\PowerShell" `
            -ValueName "ExecutionPolicy" -ErrorAction Stop).Value
        Test-Result "ExecutionPolicy" "AllSigned" $readBack
    } catch {
        Write-Fail "FAIL: Could not read back ExecutionPolicy"
    }

    $summary += "Script Policy"
}

# ── Encryption Hardening ─────────────────────────────────────────────────────

if ($runEncryption) {
    Write-Banner "Encryption Hardening"

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\System\CurrentControlSet\Services\LanManServer\Parameters" `
        -ValueName "RequireSecuritySignature" -Value 1

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\System\CurrentControlSet\Services\LanmanWorkstation\Parameters" `
        -ValueName "RequireSecuritySignature" -Value 1

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\System\CurrentControlSet\Services\LanManServer\Parameters" `
        -ValueName "SMB1" -Value 0

    if (-not $Safe) {
        Set-RegValue -GPOName $GPOName `
            -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters" `
            -ValueName "SupportedEncryptionTypes" -Value 24

        Set-RegValue -GPOName $GPOName `
            -Key "HKLM\System\CurrentControlSet\Control\Lsa" `
            -ValueName "LmCompatibilityLevel" -Value 5
    } else {
        Set-RegValue -GPOName $GPOName `
            -Key "HKLM\System\CurrentControlSet\Control\Lsa" `
            -ValueName "LmCompatibilityLevel" -Value 3
        Write-Warn "Skipped Kerberos AES-only (Safe mode)"
        Write-Warn "Using LmCompatibilityLevel 3 instead of 5 (Safe mode)"
    }

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\System\CurrentControlSet\Services\NTDS\Parameters" `
        -ValueName "LDAPServerIntegrity" -Value 2

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\System\CurrentControlSet\Services\ldap" `
        -ValueName "LDAPClientIntegrity" -Value 2

    if (-not $Safe) {
        Set-RegValue -GPOName $GPOName `
            -Key "HKLM\System\CurrentControlSet\Services\NTDS\Parameters" `
            -ValueName "LdapEnforceChannelBinding" -Value 2
    } else {
        Write-Warn "Skipped LDAP channel binding enforcement (Safe mode)"
    }

    $summary += "Encryption"
}

# ── Credential Protection ────────────────────────────────────────────────────

if ($runCredProtection) {
    Write-Banner "Credential Protection"

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\System\CurrentControlSet\Control\SecurityProviders\WDigest" `
        -ValueName "UseLogonCredential" -Value 0

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\System\CurrentControlSet\Control\Lsa" `
        -ValueName "RestrictAnonymousSAM" -Value 1

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\System\CurrentControlSet\Control\Lsa" `
        -ValueName "RestrictAnonymous" -Value 1

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\System\CurrentControlSet\Control\Lsa" `
        -ValueName "EveryoneIncludesAnonymous" -Value 0

    Set-GPRegistryValue -Name $GPOName `
        -Key "HKLM\System\CurrentControlSet\Control\Lsa" `
        -ValueName "RestrictRemoteSAM" -Value "O:BAG:BAD:(A;;RC;;;BA)" -Type String | Out-Null
    Write-Setting "HKLM\System\CurrentControlSet\Control\Lsa\RestrictRemoteSAM = O:BAG:BAD:(A;;RC;;;BA)"

    # LSA Protection (RunAsPPL) — LSASS as PPL, blocks userland LSASS dumps
    # Requires reboot. Server 2012 R2+ / Win 8.1+. Skip with -NoLSAProtection.
    if (-not $NoLSAProtection) {
        Set-RegValue -GPOName $GPOName `
            -Key "HKLM\System\CurrentControlSet\Control\Lsa" `
            -ValueName "RunAsPPL" -Value 1
        Write-Warn "RunAsPPL enabled — requires reboot to take effect"
    } else {
        Write-Warn "Skipped RunAsPPL (NoLSAProtection)"
    }

    $summary += "Credential Protection"
}

# ── Windows Defender (via GPO) ───────────────────────────────────────────────

if ($runCredProtection) {
    Write-Banner "Windows Defender (GPO)"

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\Software\Policies\Microsoft\Windows Defender" `
        -ValueName "DisableAntiSpyware" -Value 0

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\Software\Policies\Microsoft\Windows Defender" `
        -ValueName "DisableAntiVirus" -Value 0

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\Software\Policies\Microsoft\Windows Defender\Real-Time Protection" `
        -ValueName "DisableRealtimeMonitoring" -Value 0

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\Software\Policies\Microsoft\Windows Defender\Real-Time Protection" `
        -ValueName "DisableBehaviorMonitoring" -Value 0

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\Software\Policies\Microsoft\Windows Defender\Real-Time Protection" `
        -ValueName "DisableOnAccessProtection" -Value 0

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\Software\Policies\Microsoft\Windows Defender\Real-Time Protection" `
        -ValueName "DisableScanOnRealtimeEnable" -Value 0

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\Software\Policies\Microsoft\Windows Defender\Real-Time Protection" `
        -ValueName "DisableIOAVProtection" -Value 0

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\Software\Policies\Microsoft\Windows Defender\Spynet" `
        -ValueName "SpynetReporting" -Value 2

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\Software\Policies\Microsoft\Windows Defender\MpEngine" `
        -ValueName "MpEnablePus" -Value 1

    $summary += "Windows Defender"
}

# ── Network Hardening ────────────────────────────────────────────────────────

if ($runNetworkHardening) {
    Write-Banner "Network Hardening"

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\Software\Policies\Microsoft\Windows NT\DNSClient" `
        -ValueName "EnableMulticast" -Value 0

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\System\CurrentControlSet\Services\NetBT\Parameters" `
        -ValueName "NodeType" -Value 2

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp" `
        -ValueName "DisableWpad" -Value 1

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
        -ValueName "UserAuthentication" -Value 1

    Set-RegValue -GPOName $GPOName `
        -Key "HKLM\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
        -ValueName "SecurityLayer" -Value 2

    if (-not $Safe) {
        foreach ($svc in @("TlntSvr", "SNMP")) {
            Set-RegValue -GPOName $GPOName `
                -Key "HKLM\System\CurrentControlSet\Services\$svc" `
                -ValueName "Start" -Value 4
        }
    } else {
        Write-Warn "Skipped disabling services (Safe mode)"
    }

    $summary += "Network Hardening"
}

# ── Force GP Update ──────────────────────────────────────────────────────────

Write-Banner "Applying Group Policy"
& gpupdate /force 2>&1 | ForEach-Object { Write-Host "    $_" }

# ── Post-gpupdate Verification ──────────────────────────────────────────────

Write-Banner "Post-gpupdate Verification"

if ($runPasswordPolicy) {
    $netAccounts = net accounts 2>&1
    foreach ($line in $netAccounts) {
        if ($line -match "Minimum password length\s+(\d+)") {
            Test-Result "Effective MinPasswordLength" "$minPwdLen" $Matches[1]
        }
        if ($line -match "Lockout threshold\s+(\d+)") {
            Test-Result "Effective LockoutThreshold" "10" $Matches[1]
        }
        if ($line -match "Lockout duration.*?(\d+)") {
            Test-Result "Effective LockoutDuration" "15" $Matches[1]
        }
        if ($line -match "Length of password history\s+(\d+)") {
            Test-Result "Effective PasswordHistory" "24" $Matches[1]
        }
    }
}

if ($runAuditPolicy) {
    $auditOut = auditpol /get /category:* 2>&1
    $auditCategories = @{
        "Logon/Logoff"       = "Success and Failure"
        "Account Logon"      = "Success and Failure"
        "Account Management" = "Success and Failure"
        "Object Access"      = "Success and Failure"
        "DS Access"          = "Success and Failure"
        "Policy Change"      = "No Auditing"
        "Privilege Use"      = "No Auditing"
        "System"             = "Success and Failure"
        "Detailed Tracking"  = "Success and Failure"
    }
    foreach ($cat in $auditCategories.Keys) {
        $match = $auditOut | Where-Object { $_ -match "^\s+$cat\s+" }
        if ($match -and $match -match "(Success and Failure|Success|Failure|No Auditing)") {
            Test-Result "Effective Audit '$cat'" $auditCategories[$cat] $Matches[1]
        }
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Banner "Complete"
Write-Host ""
if ($summary.Count -eq 0) {
    Write-Host "  No sections were executed." -ForegroundColor Yellow
} else {
    Write-Host "  Sections applied:" -ForegroundColor Green
    foreach ($s in $summary) { Write-Host "    - $s" -ForegroundColor Green }
}

# ── Verification Summary ────────────────────────────────────────────────────

Write-Banner "Verification Summary"
if ($script:failures.Count -eq 0) {
    Write-Host "  All verifications passed." -ForegroundColor Green
} else {
    Write-Host "  $($script:failures.Count) verification(s) FAILED:" -ForegroundColor Red
    foreach ($f in $script:failures) {
        Write-Host "    - $f" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "  Manual checks:" -ForegroundColor White
Write-Host "    gpmc.msc            - '$GPOName' GPO linked to domain" -ForegroundColor Gray
Write-Host "    auditpol /get /category:* - audit categories on DC" -ForegroundColor Gray
Write-Host "    gpresult /r         - on remote machines after gpupdate" -ForegroundColor Gray
Write-Host "    net accounts        - password policy" -ForegroundColor Gray
Write-Host ""

if ($script:failures.Count -gt 0) { exit 1 }
