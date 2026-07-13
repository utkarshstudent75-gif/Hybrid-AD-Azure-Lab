# GPO Baseline & Policy Hygiene

## Baseline GPO
A Domain-Baseline GPO is linked at the domain root and sets the security foundation:
- Password policy (min 12 chars, complexity, 60-day max age)
- Account lockout (5 failed attempts)
- Audit policies
- Windows Firewall defaults

## Policy Hygiene Rules
- Use descriptive GPO names (e.g., `SalesDriveMap`, `ChromeInstallation`)
- Document the purpose of every GPO
- Review and remove unused GPOs quarterly
- Never edit the Default Domain Policy or Default Domain Controllers Policy directly
- Use Item-Level Targeting in Preferences for conditional application

## GPO Inventory
| GPO Name | Linked OU | Purpose |
|---|---|---|
| Domain-Baseline | Domain root | Security baseline |
| SalesDriveMap | Sales OU | Map S: drive |
| ChromeInstallation | Company OU | Deploy Chrome MSI |
| ChromeHomeBrowser | Company OU | Set default homepage |
