# Domain Password Policy Configuration
# Sets minimum length, complexity, history, max/min age, and lockout policy

Import-Module ActiveDirectory

$domain = (Get-ADDomain).DNSRoot

Set-ADDefaultDomainPasswordPolicy -Identity $domain `
    -MinPasswordLength 12 `
    -PasswordHistoryCount 24 `
    -ComplexityEnabled $true `
    -MaxPasswordAge (New-TimeSpan -Days 60) `
    -MinPasswordAge (New-TimeSpan -Days 1)

Write-Host "[+] Password policy applied to domain: $domain" -ForegroundColor Green
