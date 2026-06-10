# Ensure the Active Directory module is imported
Import-Module ActiveDirectory

# Define the output CSV file path
$outputFile = "C:\path\to\output\OUs_and_Permissions.csv"

# Function to get permissions for each OU
function Get-OUPermissions {
    param (
        [string]$OU
    )
    
    # Get the permissions for the specified OU
    $permissions = Get-Acl "AD:$OU" | Select-Object -ExpandProperty Access
    
    # Prepare the output data
    $permissionsInfo = $permissions | Select-Object @{Name="OU";Expression={$OU}}, 
                                                     @{Name="IdentityReference";Expression={$_.IdentityReference}},
                                                     @{Name="AccessControlType";Expression={$_.AccessControlType}},
                                                     @{Name="ActiveDirectoryRights";Expression={$_.ActiveDirectoryRights}},
                                                     @{Name="IsInherited";Expression={$_.IsInherited}}
    
    return $permissionsInfo
}

# Get all Organizational Units (OUs) in the domain
$OUs = Get-ADOrganizationalUnit -Filter * | Select-Object DistinguishedName

# Create an empty list to store all the data
$allOUData = @()

# Loop through each OU and get its permissions
foreach ($OU in $OUs) {
    Write-Host "Gathering permissions for OU: $($OU.DistinguishedName)"
    $OUPermissions = Get-OUPermissions -OU $OU.DistinguishedName
    
    # Add the permissions info for this OU to the list
    $allOUData += $OUPermissions
}

# Export the gathered information to a CSV file
$allOUData | Export-Csv -Path ".\OU_Permissions.csv" -NoTypeInformation

Start-Process ".\OU_Permissions.csv"

Write-Host "Information has been exported to: .\OU_Permissions.csv"