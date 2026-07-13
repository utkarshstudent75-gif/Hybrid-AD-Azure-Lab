# Implementation Notes

This document captures the full step-by-step build process behind the Hybrid Active Directory and Azure Infrastructure Lab.

---

## Environment

- On-premises Windows Server 2022 Domain Controller (`WS2022-DC01`)
- Domain: `itnethub.com`
- Azure subscription with resource groups, VNets, and VMs
- pfSense as the on-premises VPN endpoint
- Microsoft Entra Connect installed on the domain controller

---

## 1. Active Directory OU Design

The OU structure was designed around delegation and Group Policy targeting rather than geography.

### Structure
```
DC=itnethub,DC=com
└── OU=Company
    └── OU=HQ Toronto
        ├── OU=Sales
        │   ├── OU=Sales Users
        │   └── OU=Sales Computers
        ├── OU=HR
        │   ├── OU=HR Users
        │   └── OU=HR Computers
        └── OU=IT
            ├── OU=IT Users
            └── OU=IT Computers
```

### Design Decisions
- Separate Users and Computers sub-OUs for targeted GPO application.
- Keep the tree shallow (max 3 levels) for easier troubleshooting.
- ProtectedFromAccidentalDeletion enabled on all OUs.
- Naming conventions are consistent and human-readable.

---

## 2. AGDLP Model

Access is managed with AGDLP: Accounts to Global Groups to Domain Local Groups to Permissions.

### Example — Sales Department
- User accounts are added to the **Sales Team** global group.
- Sales Team is nested into **Sales_Read_Only** domain local group.
- Sales_Read_Only is granted Read access on the Sales share.
- A separate **Sales_team_Write** DL group handles write access.

### Groups Created Per Department
- `<Dept> Management` — Global
- `<Dept> team` — Global
- `<Dept>_Read_Only` — Global
- `<Dept>_team_Write` — Global
- `<Dept>_Write` — Global

---

## 3. PowerShell Automation

### User Onboarding
Script: [`scripts/bulk-user-creation.ps1`](../scripts/bulk-user-creation.ps1)

The script creates 5 Sales users in the correct OU, adds them to the Sales Team global group, and forces password change at first login.

```powershell
Import-Module ActiveDirectory

$users = @(
    @{FirstName="Rajat"; LastName="Goyal"; SamAccountName="rgoyal"; Password="P@ssword1"},
    @{FirstName="Sakshi"; LastName="Mehta"; SamAccountName="smehta"; Password="P@ssword1"},
    @{FirstName="Raju"; LastName="Singh"; SamAccountName="rsingh"; Password="P@ssword1"},
    @{FirstName="Harshul"; LastName="Verma"; SamAccountName="hverma"; Password="P@ssword1"},
    @{FirstName="Payal"; LastName="Kaur"; SamAccountName="pkaur"; Password="P@ssword1"}
)

$ouPath = "OU=Sales Users,OU=Sales,OU=HQ Toronto,OU=Company,DC=itnethub,DC=com"
$securityGroup = "Sales team"

foreach ($user in $users) {
    $securePassword = ConvertTo-SecureString $user.Password -AsPlainText -Force
    New-ADUser -Name "$($user.FirstName) $($user.LastName)" `
        -SamAccountName $user.SamAccountName `
        -UserPrincipalName "$($user.SamAccountName)@itnethub.com" `
        -AccountPassword $securePassword `
        -PasswordNeverExpires $false `
        -Enabled $true `
        -ChangePasswordAtLogon $true `
        -Path $ouPath
    Add-ADGroupMember -Identity $securityGroup -Members $user.SamAccountName
}
```

### Department OU and Group Provisioning
Script: [`scripts/dept-ou-groups.ps1`](../scripts/dept-ou-groups.ps1)

Iterates every department OU under HQ Toronto and creates Users/Computers sub-OUs plus five security groups per department.

---

## 4. Group Policy

### Password Policy
Configured via GPMC and PowerShell:
- Minimum password length: 12
- Complexity: Enabled
- History: 24 passwords
- Max age: 60 days
- Min age: 1 day
- Account lockout after 5 failed attempts

```powershell
Set-ADDefaultDomainPasswordPolicy `
    -Identity "itnethub.com" `
    -MinPasswordLength 12 `
    -PasswordHistoryCount 24 `
    -ComplexityEnabled $true `
    -MaxPasswordAge (New-TimeSpan -Days 60) `
    -MinPasswordAge (New-TimeSpan -Days 1)
```

### Drive Mapping
- GPO: SalesDriveMap
- Linked to: `OU=Sales Users,OU=Sales,OU=HQ Toronto,OU=Company,DC=itnethub,DC=com`
- Path: User Configuration > Preferences > Windows Settings > Drive Maps
- Drive Letter: S:
- Location: `\\WS2022-DC01\Sales`

### Chrome Deployment
1. Download Chrome Enterprise MSI and place on a network share accessible by all clients.
2. Create GPO `ChromeInstallation`, link to Company OU.
3. Navigate to Computer Configuration > Policies > Software Settings > Software Installation.
4. Add Chrome MSI as Assigned application using the share path (not local path).
5. Download Chrome ADMX/ADML templates.
6. Create GPO `ChromeHomeBrowser`, import ADMX templates, set default homepage.

---

## 5. Microsoft Entra Connect Setup

1. Download Microsoft Entra Connect from the official Microsoft portal.
2. Run the installer on `WS2022-DC01`.
3. Use Express Settings or Custom — provide Azure AD global admin and on-prem AD credentials.
4. Configure OU filtering to include only the relevant OUs.
5. Complete the wizard and allow the initial full sync to finish.

### Sync Verification
1. Open Synchronization Service Manager (`miisclient.exe`).
2. Review the Operations tab for recent sync runs.
3. Make a change to a user in ADUC (e.g., update job title).
4. Create a new user in ADUC.
5. Run a delta sync: `Start-ADSyncSyncCycle -PolicyType Delta`
6. Verify changes in Azure Portal > Microsoft Entra ID > Users.

---

## 6. Hybrid Authentication Features

### Password Writeback
- Enable in Entra Connect wizard under Optional Features.
- Enable SSPR in Azure Portal and configure to use password writeback.

### Pass-Through Authentication (PTA)
- Enable in Entra Connect under Sign-In method.
- Install PTA agent on the domain controller.
- Verify authentication flows through on-prem AD.

### Password Protection
- Download Microsoft Entra ID Password Protection proxy and DC agent.
- Install proxy service on a management server.
- Register proxy: `AzureADPasswordProtectionProxy.exe RegisterProxy /AzureTenantId <TenantId>`
- Install DC agent on the domain controller and restart.

---

## 7. Azure Networking and Site-to-Site VPN

### Azure Side
1. Create a Virtual Network with address space `192.168.1.0/24`.
2. Create a Virtual Network Gateway (VPN Gateway, Route-Based).
3. Create a Local Network Gateway pointing to the on-prem pfSense public IP with address space `192.168.126.0/24`.
4. Create a Connection linking the VPN Gateway to the Local Network Gateway.

### pfSense Side
1. Configure IPsec Phase 1 with the Azure VPN Gateway public IP.
2. Configure IPsec Phase 2 with:
   - Local Network: `192.168.126.0/24`
   - Remote Network: `192.168.1.0/24`
3. Apply changes and connect P1 and P2.
4. Verify tunnel status under Status > IPsec.

### Enabling Domain Join from Azure
1. Update Azure VNet DNS to point to on-prem DC IP (`192.168.126.30`).
2. Create a Route Table with a route for `192.168.126.0/24` pointing to the VPN Gateway.
3. Associate the route table with the Azure subnet.
4. Add pfSense IPsec firewall rules to allow all AD-related traffic (TCP/UDP).
5. Add Windows Firewall inbound rules on the DC for ports: 53, 88, 135, 389, 445, 636, 3268, 3269 from `192.168.1.0/24`.

---

## 8. Windows Admin Center

1. Download Windows Admin Center MSI from Microsoft.
2. Install on `WS2022-DC01` or a dedicated management server.
3. Open WAC in a browser and add the server.
4. Under Settings > Azure, register WAC with your Azure subscription.
5. Test hybrid connectivity using Azure Network Adapter.

---

## 9. ARM Templates and Azure Resource Provisioning

### Login to Azure via PowerShell
```powershell
Install-Module -Name Az -AllowClobber -Scope CurrentUser
Import-Module Az.Accounts
Connect-AzAccount
Get-AzSubscription
Select-AzSubscription -Subscription "<subscription name or ID>"
```

### Create Resource Group
```powershell
New-AzResourceGroup -Name "ARMTest" -Location "Central India"
```

### Deploy ARM Template
```powershell
$templateFile = "./templates/hub-vnet.json"
New-AzResourceGroupDeployment -ResourceGroupName "ARMTest" -TemplateFile $templateFile -Name "TestDeployment"
```

### VM Provisioning
```powershell
New-AzVM `
    -ResourceGroupName "myResourceGroup" `
    -Name "myVM" `
    -Location "EastUS" `
    -Image "Win2022Datacenter" `
    -Credential (Get-Credential) `
    -OpenPorts 3389
```

---

## 10. Containers

1. Install the Containers feature on Windows Server:
```powershell
Install-WindowsFeature -Name Containers -Restart
```
2. Install Docker:
```powershell
Install-Module -Name DockerMsftProvider -Repository PSGallery -Force
Install-Package -Name docker -ProviderName DockerMsftProvider
Restart-Computer
```
3. Verify Docker is running:
```powershell
docker version
docker run hello-world
```

---

## 11. Hub-and-Spoke Topology

### Design
| Resource | VNet | Subnet | IP Range |
|---|---|---|---|
| DC | Hub-VNet | HubSubnet | 192.168.1.0/24 |
| Azure Firewall | Hub-VNet | AzureFirewallSubnet | 10.0.1.0/24 |
| Spoke 1 VM | Spoke1-VNet | Spoke1Subnet | 10.1.0.0/24 |
| Spoke 2 VM | Spoke2-VNet | Spoke2Subnet | 10.2.0.0/24 |

### Key Steps
1. Add AzureFirewallSubnet to the Hub VNet.
2. Create Spoke1RG and Spoke2RG resource groups.
3. Create Spoke1-VNet and Spoke2-VNet.
4. Create bidirectional VNet peerings (Hub ↔ Spoke1, Hub ↔ Spoke2).
5. Deploy Azure Firewall using the ARM template in `templates/`.
6. Deploy Spoke VMs using the Spoke VM ARM template.
7. Add NSG rules to the DC subnet to allow AD traffic from the Azure Firewall subnet.

---

## 12. Troubleshooting

### VPN Not Connecting
- Check if your on-premises public IP has changed.
- Go to Local Network Gateway > Settings > Configuration and update the public IP.

### DNS Not Resolving from Azure VM
- Confirm Azure VNet DNS is set to the on-prem DC IP.
- Restart the Azure VM after updating DNS settings.
- Test: `nslookup itnethub.com 192.168.126.30` from the Azure VM.

### Domain Join Failing
- Confirm bidirectional routing is in place (route table on Azure subnet).
- Confirm pfSense IPsec rules allow all protocols, not just TCP.
- Confirm Windows Firewall inbound rules on DC allow the Azure subnet.

### Entra Connect Sync Errors
- Open Synchronization Service Manager and check the Operations tab.
- Look for Export or Import errors on the connector.
- Run a full sync if delta sync fails: `Start-ADSyncSyncCycle -PolicyType Initial`

### Hub-and-Spoke Peering Error
- If AllowVirtualNetworkAccess fails during Add-AzVirtualNetworkPeering, create the peering first then set the property:
```powershell
$peering = Get-AzVirtualNetworkPeering -VirtualNetworkName $HubVNetName -ResourceGroupName $HubRG -Name "HubToSpoke1"
$peering.AllowVirtualNetworkAccess = $true
Set-AzVirtualNetworkPeering -VirtualNetworkPeering $peering
```

---

*For the project overview and screenshots, see [README.md](../README.md).*
