# Department OU and Security Group Auto-Creation Script
# Creates Users/Computers sub-OUs and standard security groups for each department

Import-Module ActiveDirectory

$ParentOU = "OU=HQ Toronto,OU=Company,DC=itnethub,DC=com"

try {
    $DeptOUs = Get-ADOrganizationalUnit -Filter * -SearchBase $ParentOU -SearchScope OneLevel -ErrorAction Stop
} catch {
    Write-Host "Error: Could not find parent OU '$ParentOU'. Check the path." -ForegroundColor Red
    return
}

foreach ($DeptOU in $DeptOUs) {
    $DeptName = $DeptOU.Name
    Write-Host "Processing: $DeptName" -ForegroundColor Cyan

    # Create Users and Computers sub-OUs
    foreach ($SubOU in @("Users", "Computers")) {
        $OUName = "$DeptName $SubOU"
        if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$OUName'" -SearchBase $DeptOU.DistinguishedName -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $OUName -Path $DeptOU.DistinguishedName -ProtectedFromAccidentalDeletion $true -WhatIf
            Write-Host "  [+] Would create OU: $OUName" -ForegroundColor DarkGreen
        } else {
            Write-Host "  [~] Skipping (exists): $OUName" -ForegroundColor Yellow
        }
    }

    # Create standard security groups
    $Groups = @("$DeptName Management", "$DeptName Team", "${DeptName}ReadOnly", "${DeptName}Write")
    foreach ($GroupName in $Groups) {
        if (-not (Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $GroupName -Path $DeptOU.DistinguishedName -GroupScope Global -GroupCategory Security -WhatIf
            Write-Host "  [+] Would create group: $GroupName" -ForegroundColor Green
        } else {
            Write-Host "  [~] Skipping (exists): $GroupName" -ForegroundColor Yellow
        }
    }
}

Write-Host "Done." -ForegroundColor Blue
