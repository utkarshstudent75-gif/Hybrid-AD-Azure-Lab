# Bulk User Creation Script
# Reads from newusers.csv and creates AD users with group assignment
# CSV format: FirstName,LastName,Username,Department,OU,GlobalGroup

Import-Module ActiveDirectory

Import-Csv ".\newusers.csv" | ForEach-Object {
    $securePassword = ConvertTo-SecureString $_.Password -AsPlainText -Force

    New-ADUser `
        -Name "$($_.FirstName) $($_.LastName)" `
        -GivenName $_.FirstName `
        -Surname $_.LastName `
        -SamAccountName $_.Username `
        -UserPrincipalName "$($_.Username)@itnethub.com" `
        -Path $_.OU `
        -Department $_.Department `
        -AccountPassword $securePassword `
        -PasswordNeverExpires $false `
        -Enabled $true `
        -ChangePasswordAtLogon $true

    Add-ADGroupMember -Identity $_.GlobalGroup -Members $_.Username

    Write-Host "[+] Created user $($_.Username) and added to $($_.GlobalGroup)" -ForegroundColor Green
}
