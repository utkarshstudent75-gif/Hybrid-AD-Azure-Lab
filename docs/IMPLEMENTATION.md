# Implementation Guide — Hybrid AD & Azure Lab

> This document is the complete step-by-step implementation guide for the Hybrid Active Directory + Azure lab environment. Every screenshot referenced below maps directly to an image in the [`/images`](../images/) folder.

---

## Table of Contents

1. [OU Design Best Practices](#1-ou-design-best-practices)
2. [AGDLP Model & Security Groups](#2-agdlp-model--security-groups)
3. [PowerShell User Onboarding](#3-powershell-user-onboarding)
4. [Shared Drive Mapping via GPO](#4-shared-drive-mapping-via-gpo)
5. [GPO Baseline & Policy Hygiene](#5-gpo-baseline--policy-hygiene)
6. [Password Policy](#6-password-policy)
7. [Automated Security Group Creation](#7-automated-security-group-creation)
8. [Google Chrome Deployment via GPO](#8-google-chrome-deployment-via-gpo)
9. [Microsoft Entra Connect — Download, Install & Configure](#9-microsoft-entra-connect--download-install--configure)
10. [Verifying AD DS ↔ Entra ID Synchronisation](#10-verifying-ad-ds--entra-id-synchronisation)
11. [Entra ID Integration Features in AD DS](#11-entra-id-integration-features-in-ad-ds)
12. [Windows Admin Center — Install & Configure](#12-windows-admin-center--install--configure)
13. [WAC in Hybrid Scenarios (Azure Network Adapter)](#13-wac-in-hybrid-scenarios-azure-network-adapter)
14. [Azure VM Deployment](#14-azure-vm-deployment)
15. [Installing and Configuring Containers](#15-installing-and-configuring-containers)
16. [ARM Templates](#16-arm-templates)
17. [Connecting On-Prem DC to Azure (Site-to-Site VPN)](#17-connecting-on-prem-dc-to-azure-site-to-site-vpn)
18. [Domain Joining Azure VM to On-Prem DC](#18-domain-joining-azure-vm-to-on-prem-dc)
19. [Hub and Spoke Topology in Azure](#19-hub-and-spoke-topology-in-azure)
20. [Firewall Deployment](#20-firewall-deployment)
21. [Spoke VM Deployment](#21-spoke-vm-deployment)
22. [VNet Peering between DC VNet and Firewall VNet](#22-vnet-peering-between-dc-vnet-and-firewall-vnet)
23. [Troubleshooting](#23-troubleshooting)

---

## 1. OU Design Best Practices

Organizational Units (OUs) are a fundamental component of Active Directory structure. A well-designed OU structure simplifies administration, enhances security, and streamlines Group Policy application.

### Key Design Tips

- **Mirror business structure** — Design your OU layout around administrative and operational requirements, not geography alone.
- **Delegate at the right level** — Assign permissions to specific OUs so local admins manage objects without impacting the entire domain.
- **Keep it flat** — Deep nesting slows Group Policy processing and complicates troubleshooting. Aim for no more than 3–4 levels.
- **Separate users and computers** — Maintain distinct OUs for user accounts and computer accounts to apply different GPOs.
- **Design for GPO** — OUs are the only containers where GPOs can be directly linked. Group objects that require similar policies.
- **Don't replace security groups** — OUs serve administrative/policy purposes; security groups control resource permissions.
- **Plan for growth** — Design flexibly to accommodate mergers, expansions, or restructuring.
- **Document everything** — Record the purpose of each OU, delegated permissions, and applied policies.
- **Avoid OU sprawl** — Only create OUs when necessary.
- **Use consistent naming** — Adopt clear naming conventions for easy navigation.

### Lab Environment OU Structure

Below is the OU structure implemented in the `itnethub.com` domain:

![OU Structure — itnethub.com](../images/image33.jpg)

> The structure follows: `Company > HQ Toronto > [Departments] > Users / Computers`

---

## 2. AGDLP Model & Security Groups

**AGDLP** = **A**ccounts → **G**lobal groups → **D**omain **L**ocal groups → **P**ermissions (resource access)

```
Users  →  Global Groups  →  Domain Local Groups  →  Resource (permission)
```

### Example — Sales Department

- Sales team members are added to the **Sales team** global security group.
- The **Sales team** global group is made a member of the **Sales_Read_Only** domain local group.
- The `Sales Files` shared folder grants access to the **Sales_Read_Only** domain local group.

This model ensures clean permission delegation across domain boundaries.

![AGDLP Sales Group Implementation](../images/image34.jpg)

---

## 3. PowerShell User Onboarding

PowerShell automation ensures users are placed in the correct OUs, assigned to appropriate global groups, and granted permissions consistently — eliminating manual errors.

### Create 5 Sales Users Script

The script below creates 5 users in `OU=Sales Users,OU=Sales,OU=HQ Toronto,OU=Company,DC=itnethub,DC=com`, adds them to the **Sales team** security group, and forces a password change at first login.

```powershell
Import-Module ActiveDirectory

$users = @(
    @{FirstName="Rajat";   LastName="Goyal"; SamAccountName="rgoyal"; Password="P@ssword1"},
    @{FirstName="Sakshi";  LastName="Mehta";  SamAccountName="smehta"; Password="P@ssword1"},
    @{FirstName="Raju";    LastName="Singh";  SamAccountName="rsingh"; Password="P@ssword1"},
    @{FirstName="Harshul"; LastName="Verma";  SamAccountName="hverma"; Password="P@ssword1"},
    @{FirstName="Payal";   LastName="Kaur";   SamAccountName="pkaur";  Password="P@ssword1"}
)

$ouPath       = "OU=Sales Users,OU=Sales,OU=HQ Toronto,OU=Company,DC=itnethub,DC=com"
$securityGroup = "Sales team"

foreach ($user in $users) {
    $securePassword = ConvertTo-SecureString $user.Password -AsPlainText -Force

    New-ADUser `
        -Name             "$($user.FirstName) $($user.LastName)" `
        -GivenName        $user.FirstName `
        -Surname          $user.LastName `
        -SamAccountName   $user.SamAccountName `
        -UserPrincipalName "$($user.SamAccountName)@itnethub.com" `
        -AccountPassword  $securePassword `
        -PasswordNeverExpires $false `
        -Enabled          $true `
        -ChangePasswordAtLogon $true `
        -Path             $ouPath

    Add-ADGroupMember -Identity $securityGroup -Members $user.SamAccountName
    Write-Host "Created user $($user.SamAccountName) and added to $securityGroup"
}
```

> **Note:** New users are placed under probation with Read Only access initially. Once confirmed, they can be promoted to write-access groups.

![Sales Users Created in AD](../images/image35.jpg)

![Sales Users in Sales Team Group](../images/image36.jpg)

---

## 4. Shared Drive Mapping via GPO

### Scenario

Map `S:` drive automatically for all users in the **Sales Users OU** so they don't need to contact IT each time.

### Steps to Map S: Drive for Sales Users

1. Open **Group Policy Management Console (GPMC)**.
2. Right-click the **Sales Users OU** → **Create a GPO in this domain and link it here**.
3. Name it (e.g., `Sales-Drive-Mapping`) and click **OK**.
4. Right-click the GPO → **Edit**.
5. Navigate to:  
   `User Configuration > Preferences > Windows Settings > Drive Maps`
6. Right-click → **New > Mapped Drive**.
7. Set:
   - **Action:** Create
   - **Location:** `\\<ServerName>\Sales` (your share path)
   - **Drive Letter:** `S:`
   - **Label:** Sales Files
8. Under the **Common** tab, check **Item-level targeting** and target `OU=Sales Users`.
9. Click **OK** and close the editor.

When users in the Sales Users OU next log in, the `S:` drive will be automatically mapped.

![GPO Drive Map — Sales S: Drive Setup](../images/image37.jpg)

![GPO Drive Map — Result on Client](../images/image38.jpg)

---

## 5. GPO Baseline & Policy Hygiene

A GPO baseline is a set of standard policies serving as a foundation for system configuration and security. Policy hygiene means regularly reviewing, updating, and removing outdated or redundant GPOs.

**Best Practices:**
- Document all changes with clear, descriptive naming conventions.
- Periodically audit GPOs to ensure they are still relevant and correctly applied.
- Align new GPOs with established baselines to prevent configuration drift.

### Copy ADMX Templates to Central Store

```powershell
# Run as Domain Admin on a DC or management host
$domain = $env:USERDNSDOMAIN
$target = "\\$domain\SYSVOL\$domain\Policies\PolicyDefinitions"

New-Item -Path $target -ItemType Directory -Force
robocopy "C:\Windows\PolicyDefinitions" $target /MIR
```

### Create Baseline GPO

```powershell
Import-Module GroupPolicy
New-GPO -Name "Domain-Baseline" -Comment "Security baseline: firewall, auditing, account lockout"
```

### Lab Implementation

![GPO Baseline — GPMC View](../images/image39.jpg)

![GPO Baseline — Settings Detail](../images/image40.jpg)

---

## 6. Password Policy

Configure a strong domain password policy via GPMC:

**Path:** `Computer Configuration > Policies > Windows Settings > Security Settings > Account Policies > Password Policy`

**Recommended Settings:**
| Setting | Value |
|---|---|
| Minimum password length | 12 characters |
| Password complexity | Enabled |
| Maximum password age | 60 days |
| Minimum password age | 1 day |
| Password history | 24 passwords |

### PowerShell Alternative

```powershell
Import-Module ActiveDirectory

Set-ADDefaultDomainPasswordPolicy `
    -Identity            "itnethub.com" `
    -MinPasswordLength   12 `
    -PasswordHistoryCount 24 `
    -ComplexityEnabled   $true `
    -MaxPasswordAge      (New-TimeSpan -Days 60) `
    -MinPasswordAge      (New-TimeSpan -Days 1)
```

![Password Policy — GPMC Configuration](../images/image41.jpg)

---

## 7. Automated Security Group Creation

This script creates **Users** and **Computers** sub-OUs and all required security groups for every department OU under `OU=HQ Toronto,OU=Company,DC=itnethub,DC=com`.

```powershell
Import-Module ActiveDirectory

$ParentOU = "OU=HQ Toronto,OU=Company,DC=itnethub,DC=com"

try {
    $DepartmentOUs = Get-ADOrganizationalUnit -Filter * -SearchBase $ParentOU `
                     -SearchScope OneLevel -ErrorAction Stop
} catch {
    Write-Host "Error: Could not find the parent OU: $ParentOU" -ForegroundColor Red
    return
}

foreach ($DeptOU in $DepartmentOUs) {
    $DeptName = $DeptOU.Name
    Write-Host "Processing OU: $DeptName" -ForegroundColor Cyan

    # Create sub-OUs
    foreach ($subOuName in "$DeptName Users", "$DeptName Computers") {
        if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$subOuName'" -SearchBase $DeptOU.DistinguishedName -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $subOuName `
                -Path $DeptOU.DistinguishedName `
                -ProtectedFromAccidentalDeletion $true
            Write-Host "  Created OU: $subOuName" -ForegroundColor DarkGreen
        } else {
            Write-Host "  Skipping '$subOuName' — already exists." -ForegroundColor Yellow
        }
    }

    # Create security groups
    $groupNames = @(
        "$DeptName Management",
        "$DeptName team",
        "${DeptName}_Read_Only",
        "${DeptName}_team_Write",
        "${DeptName}_Write"
    )

    foreach ($groupName in $groupNames) {
        if (-not (Get-ADGroup -Filter { Name -eq $groupName } -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $groupName `
                -Path $DeptOU.DistinguishedName `
                -GroupScope 'Global' `
                -GroupCategory 'Security'
            Write-Host "  Created group: $groupName" -ForegroundColor Green
        } else {
            Write-Host "  Skipping '$groupName' — already exists." -ForegroundColor Yellow
        }
    }
}

Write-Host "Script finished." -ForegroundColor Blue
```

![Automated Groups — Script Output](../images/image42.jpg)

![Automated Groups — AD Result](../images/image43.jpg)

---

## 8. Google Chrome Deployment via GPO

### Overview

For fully automated Chrome installation in a domain, use Group Policy to deploy the **Chrome Enterprise MSI** installer.

**Steps:**
1. Place the Chrome Enterprise MSI in a network-shared folder accessible by all target machines.
2. Open GPMC and create or modify a GPO.
3. Navigate to:  
   `Computer Configuration > Policies > Software Settings > Software Installation`
4. Right-click → **New > Package** → Browse to the MSI → Select **Assigned**.
5. Chrome installs automatically on domain computers at startup.
6. Import Chrome **ADMX/ADML** templates into Group Policy for additional browser configuration.

### Lab Setup — Chrome Installation GPO

![Chrome GPO — Software Installation Policy](../images/image44.jpg)

### Lab Setup — Chrome Default Settings GPO

![Chrome GPO — Default Browser Settings](../images/image45.jpg)

### Result — Chrome Installed

![Chrome Installed on Client](../images/image46.jpg)

### Result — Default Page Showing

![Chrome Default Page Verified](../images/image47.jpg)

---

## 9. Microsoft Entra Connect — Download, Install & Configure

### Scenario

> You're now ready to implement the integration by downloading Microsoft Entra Connect, installing it on DC, and configuring its settings to match the integration objective.

**Objective:** After completing these steps, `WS2022-DC01` will be integrated with Azure AD using Microsoft Entra Connect. Monitor synchronisation status and review logs for any issues.

### Main Tasks

1. Download Microsoft Entra Connect from the Microsoft portal or the official documentation page.
2. Run the installer on your Domain Controller (`WS2022-DC01`).
3. Follow the setup wizard — choose **Express Settings** for a standard single-forest configuration.
4. Provide your **Azure AD Global Admin** credentials and your **AD DS Enterprise Admin** credentials when prompted.
5. Review the configuration summary and click **Install**.
6. After installation completes, allow the initial synchronisation cycle to run.

### Lab Setup Screenshots

![Entra Connect — Download Page / Initial Setup](../images/image48.jpg)

![Entra Connect — Installation Wizard](../images/image49.jpg)

![Entra Connect — Credentials Screen](../images/image50.jpg)

![Entra Connect — Configuration Complete](../images/image51.jpg)

---

## 10. Verifying AD DS ↔ Entra ID Synchronisation

### Scenario

> Now that Microsoft Entra Connect is installed and configured, verify its synchronisation mechanism by making changes to on-premises user accounts and confirming they replicate to Microsoft Entra ID.

### Main Tasks

#### Task 1 — Verify in Synchronisation Service Manager

1. On the server running Microsoft Entra Connect, open **Synchronisation Service Manager** (`miisclient.exe`).
2. In the **Operations** tab, review recent synchronisation runs for errors or warnings.
3. Locate the **Export** and **Import** steps to confirm data flow to Microsoft Entra ID.
4. Use the **Connectors** tab to inspect connector spaces and verify expected updates.

#### Task 2 — Update a User Account in Active Directory

1. Open **Active Directory Users and Computers** on your domain controller.
2. Locate user **Payal Kaur** in the Sales OU, right-click → **Properties**.
3. Modify an attribute (e.g., Job Title or Department) → **OK**.

#### Task 3 — Create a New User in Active Directory

1. In ADUC, right-click the appropriate OU → **New > User**.
2. Fill in the user details (name, logon name) and set a password.
3. Complete the wizard and confirm the new user appears in the directory.

#### Task 4 — Force Delta Sync to Microsoft Entra ID

```powershell
# Run on the server with Microsoft Entra Connect (as administrator)
Start-ADSyncSyncCycle -PolicyType Delta
```

Wait for the synchronisation cycle to complete. Monitor progress in Synchronisation Service Manager.

#### Task 5 — Verify Changes in Microsoft Entra ID

1. Go to **Azure Portal** → **Microsoft Entra ID** → **Users**.
2. Search for the updated or newly created user.
3. Open the user's profile and confirm the changes are reflected.

### Lab Screenshots — On-Premises Changes Made

![Payal Kaur — Properties Updated in AD](../images/image52.jpg)

![New User Created in AD](../images/image53.jpg)

### Lab Screenshots — Changes Reflected via Sync

![Synchronisation Service Manager — Delta Sync Run](../images/image54.jpg)

![Azure Portal — Updated User Profile in Entra ID](../images/image55.jpg)

---

## 11. Entra ID Integration Features in AD DS

### Main Tasks

#### Enable Password Writeback in Microsoft Entra Connect

1. Open **Microsoft Entra Connect** on the DC.
2. Select **Configure** → **Customize synchronization options**.
3. On the **Optional Features** page, enable **Password writeback**.
4. Complete the wizard and allow the configuration to apply.

![Password Writeback — Entra Connect Optional Features](../images/image56.jpg)

#### Pass-Through Authentication (PTA) Setup

You will see this screen when setting up PTA:

![PTA Setup Screen](../images/image57.jpg)

After Azure and on-premises credentials are authenticated:

![PTA — Credentials Authenticated Screen](../images/image58.jpg)

### Install and Register Entra ID Password Protection

1. Download the **Microsoft Entra ID Password Protection proxy service** and **DC agent** installers from the official Microsoft documentation.
2. Install the **proxy service** on a member server (or the DC for lab purposes).
3. Install the **DC agent** on all domain controllers.
4. Open a command prompt as administrator and register the proxy:

```cmd
AzureADPasswordProtectionProxy.exe RegisterProxy /AzureTenantId <YourTenantId>
```

> Replace `<YourTenantId>` with your actual Azure AD tenant ID. Run this command in the directory where the proxy service was installed. Refer to [Microsoft Entra ID Password Protection documentation](https://learn.microsoft.com/en-us/entra/identity/authentication/howto-password-ban-bad-on-premises-deploy) for full details.

---

## 12. Windows Admin Center — Install & Configure

### Objectives

Install Windows Admin Center (WAC) and configure it for managing hybrid Windows Server infrastructure.

**Reference guide:**  
[AZ-800 Lab 03 — Managing Windows Server](https://microsoftlearning.github.io/AZ-800-Administering-Windows-Server-Hybrid-Core-Infrastructure/Instructions/Labs/LAB_03_Managing_Windows_Server.html)

### Main Tasks

1. Download the Windows Admin Center installer from the [official Microsoft page](https://aka.ms/windowsadmincenter).
2. Run the `.msi` installer on the management server or DC.
3. Choose the port (default: `443`) and install a self-signed certificate for lab use.
4. Complete the installation and open `https://localhost` in a browser.
5. Log in with domain admin credentials.

### Lab Setup — WAC Dashboard After Login

![WAC — Dashboard After Installation and Login](../images/image59.jpg)

> **Note:** `AppIDSvc` refers to the **Application Identity** service in Windows — it determines and verifies the identity of an application. It may appear in WAC service management views.

---

## 13. WAC in Hybrid Scenarios (Azure Network Adapter)

### Reference

[AZ-800 Lab 04 — Using Windows Admin Center in Hybrid Scenarios](https://microsoftlearning.github.io/AZ-800-Administering-Windows-Server-Hybrid-Core-Infrastructure/Instructions/Labs/LAB_04_Using_Windows_Admin_Center_in_hybrid_scenarios.html)

### Task — Test Hybrid Connectivity Using Azure Network Adapter

1. In **Windows Admin Center**, connect to your server.
2. Navigate to **Networks** → **+ Add Azure Network Adapter**.
3. Sign in to your Azure account when prompted.
4. Select your **Subscription**, **Resource Group**, **Location**, and **Gateway**.
5. Specify the IP address for the network adapter.
6. Click **Create** — WAC will provision the Azure VPN Gateway and configure the adapter automatically.
7. Once the adapter is configured, verify connectivity by attempting to access resources in the connected Azure Virtual Network from your on-premises server.

---

## 14. Azure VM Deployment

### Pre-requisite — Create Azure Resource Group

Before deploying VMs, create a resource group. The lab uses resource group **AZ-800**:

![Azure Resource Group AZ-800 Created](../images/image13.jpg)

### Approach A — Azure Portal (GUI)

1. Sign in to [portal.azure.com](https://portal.azure.com).
2. In the search bar, type **Virtual Machines** and open the service.
3. Click **Create** → **Azure virtual machine**.
4. On the **Basics** tab:
   - **Subscription:** Choose your subscription.
   - **Resource group:** Create new or select existing (e.g., `AZ-800`).
   - **Virtual machine name:** e.g., `myVM`.
   - **Region:** e.g., East US.
   - **Image:** Windows Server 2022 Datacenter.
   - **Size:** Accept default or choose another.
   - **Username / Password:** Create admin credentials.
   - **Public Inbound ports:** Allow RDP (3389).
5. Click **Review + Create** → Review settings → **Create**.
6. Wait for deployment, then click **Go to resource**.

### Approach B — Azure Cloud Shell (PowerShell)

```powershell
# 1. Create a resource group
New-AzResourceGroup -Name "myResourceGroup" -Location "EastUS"

# 2. Create the VM (also creates supporting resources)
New-AzVM `
    -ResourceGroupName "myResourceGroup" `
    -Name              "myVM" `
    -Location          "EastUS" `
    -Image             "Win2022Datacenter" `
    -Credential        (Get-Credential) `
    -OpenPorts         3389

# 3. Get the public IP after deployment
Get-AzPublicIpAddress -ResourceGroupName "myResourceGroup" | Select IpAddress
```

You will be prompted for a username and password — this becomes the admin account for the VM.

### Lab Result — VM Created via PowerShell

![Azure VM myVM — PowerShell Deployment](../images/image14.jpg)

![Azure VM myVM — Deployment Confirmed in Portal](../images/image15.jpg)

---

## 15. Installing and Configuring Containers

To install and configure containers on Windows Server:

1. **Install the Containers feature** — Open PowerShell as an administrator and run:
   ```powershell
   Install-WindowsFeature -Name Containers
   ```
2. **Restart the server** — After the feature installs, restart to apply changes.
3. **Install Docker:**
   ```powershell
   Install-Module -Name DockerMsftProvider -Repository PSGallery -Force
   Install-Package -Name docker -ProviderName DockerMsftProvider
   ```
4. **Start the Docker service:**
   ```powershell
   Start-Service docker
   ```
5. **Verify installation:**
   ```cmd
   docker version
   ```
6. **Configure containers** — Pull container images, run containers, and manage them:
   ```cmd
   docker pull mcr.microsoft.com/windows/servercore:ltsc2022
   docker run -it mcr.microsoft.com/windows/servercore:ltsc2022
   docker ps
   ```

---

## 16. ARM Templates

Azure Resource Manager (ARM) templates are **JSON-based files** used to define and automate deployment of Azure infrastructure. They are central to the **Infrastructure as Code (IaC)** approach in Azure.

When you deploy an ARM template, Azure Resource Manager reads it and translates resource definitions into corresponding REST API operations.

### Core Components

An ARM template has five key sections:

| Section | Purpose |
|---|---|
| **Parameters** | Input variables like region, VM size, or password |
| **Variables** | Reusable values to avoid duplication |
| **User-defined Functions** | Custom logic or reusable calculations |
| **Resources** | Core section — defines Azure resources (VMs, VNets, storage) |
| **Outputs** | Return values after deployment (IP addresses, resource IDs) |

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {},
  "variables": {},
  "resources": [],
  "outputs": {}
}
```

### Deployment Process

1. Write the ARM template in JSON format.
2. Choose a deployment method — Azure Portal, CLI, PowerShell, REST API, or GitHub.
3. Azure Resource Manager validates the template.
4. Resource Manager converts each resource definition into REST API calls using the `apiVersion` specified.
5. Resources are deployed in order or in parallel depending on dependencies.

### Benefits

- **Consistency** — Every environment (dev, test, prod) is identical.
- **Repeatability** — Reuse templates across teams or projects.
- **Automation** — Enable CI/CD integration for continuous deployments.
- **Version Control** — Store templates in Git to track changes.
- **Reduced Errors** — Templates are pre-validated by Azure before deployment.

### Lab Mini Project — ARM Deployment to Azure

#### Step 1 — Install and Connect Azure PowerShell Module

```powershell
# Install the module if not already installed
Install-Module -Name Az -AllowClobber -Scope CurrentUser

# Import the accounts module
Import-Module Az.Accounts

# Sign in (standard prompt)
Connect-AzAccount

# Alternative — use device code if the above doesn't work
Connect-AzAccount -DeviceCode
```

![Azure PowerShell — Successful Sign-In Screen](../images/image16.jpg)

#### Step 2 — Select Your Subscription

```powershell
Get-AzSubscription
```

![Get-AzSubscription Output](../images/image17.jpg)

```powershell
Select-AzSubscription -Subscription "<Name or ID of your Azure Subscription>"
```

#### Step 3 — Create Resource Group

```powershell
New-AzResourceGroup -Name "ARMTest" -Location "Central India"
```

![ARMTest Resource Group Created](../images/image18.jpg)

#### Step 4 — Declare Template Variable and Deploy

```powershell
$templateFile = ".\deploymentTemplate.json"

New-AzResourceGroupDeployment `
    -Name              "TestDeployment" `
    -ResourceGroupName "ARMTest" `
    -TemplateFile      $templateFile
```

![ARM Deployment — PowerShell Command](../images/image19.jpg)

#### Step 5 — Verify Deployment Output

You should receive output like this:

![ARM Deployment — Successful Output](../images/image20.jpg)

#### Step 6 — Verify in Azure Portal

![Azure Portal — TestDeployment Confirmed](../images/image21.jpg)

![Azure Portal — Original JSON Template Used](../images/image1.png)

![Azure Portal — Deployment Detail View](../images/image2.png)

---

## 17. Connecting On-Prem DC to Azure (Site-to-Site VPN)

### Architecture Overview

| Component | Network | Details |
|---|---|---|
| On-premises DC | `192.168.126.0/24` | VMware Workstation — Primary DC for `itnethub.com` |
| Azure VMs | `192.168.1.0/24` | Azure VNet — Secondary DCs / DHCP servers |
| pfSense | WAN (Bridged) / LAN `192.168.126.1` | On-prem VPN gateway |
| Connectivity | Site-to-Site VPN | Tunnel between pfSense and Azure VPN Gateway |

### Step 1 — Configure Site-to-Site VPN

You must create a secure tunnel between your VMware on-prem network and Azure's VNet using a **VPN Gateway**.

#### Azure Side Steps

1. Create an Azure **VNet** with address space `192.168.1.0/24`.
2. Add a **GatewaySubnet** (e.g., `192.168.1.224/27`) inside that VNet.
3. Create a **Virtual Network Gateway** (VPN type: Route-based, SKU: VpnGw1 or higher).
4. Create a **Local Network Gateway** for your on-prem network:
   - Address space: `192.168.126.0/24`
   - Public IP: your home router or pfSense external IP.
5. Create a **Site-to-Site connection** between Azure and the on-prem VPN gateway using a **shared key (PSK)**.

#### Lab Screenshot — Azure Environment (VNet + Gateway)

![Azure VNet and VPN Gateway Setup](../images/image3.png)

### Step 2 — Create Local Network Gateway

The **Local Network Gateway (LNG)** is an Azure resource representing your on-premises network within Azure. It stores:
- The **public IP address** of your on-prem VPN device (pfSense, RRAS, etc.)
- Your **on-prem network address ranges** (e.g., `192.168.126.0/24`)

**How it fits in the architecture:**
- In Azure, you deploy a **Virtual Network Gateway** to represent the Azure side of the VPN.
- You create a **Local Network Gateway** describing the on-prem environment (its public IP and LAN address space). Azure uses this to route traffic to your on-prem network over the tunnel.
- On-prem, you configure **pfSense** to match Azure's public VPN Gateway IP and shared key.

#### Lab Screenshot — Local Network Gateway Setup

![Local Network Gateway — Configuration](../images/image4.png)

> You can find your public IP address by searching "what is my IP" in a browser. For address space, use the IP address space of your Windows Server environment.

After the Local Network Gateway is created, go to:  
**Local Network Gateway → Settings → Connections**  
The connection links your local network to the Azure network.

![Local Network Gateway — Connection Settings](../images/image5.png)

![Local Network Gateway — Connection Chosen](../images/image6.png)

### Step 3 — Configure pfSense IPsec

**Topology:**
```
Internet ↔ pfSense (WAN/Bridged) ↔ pfSense LAN 192.168.126.1 ↔ On-prem DC + VMs (192.168.126.0/24)
```

On pfSense, configure the IPsec tunnel:

![pfSense — IPsec General Configuration](../images/image7.jpg)

Copy the **Public IP address** from your Azure Virtual Network Gateway:

![Azure VPN Gateway — Public IP Address](../images/image8.jpg)

### Step 4 — Configure IPsec Phase 1 on pfSense

In pfSense: **VPN → IPsec → Tunnels → Edit Phase 1**

Use the Azure VPN Gateway public IP as the remote gateway. Follow the screenshot below:

![pfSense IPsec — Phase 1 Configuration](../images/image9.jpg)

![pfSense IPsec — Phase 1 Full Settings](../images/image10.png)

Click **Save** at the end of the page, then **Apply Changes**, then click **Phase 2**.

### Step 5 — Configure IPsec Phase 2 on pfSense

Fill out the **Local Network** and **Remote Network** sections:

**1. Local Network** — This is your on-prem network behind pfSense where your DC lives.
- **Type:** Network
- **Address:** `192.168.126.0`
- **Subnet:** `/24`

**2. Remote Network** — This is your Azure subnet where Azure VMs are running.
- **Type:** Network
- **Address:** Your Azure VNet subnet (e.g., `192.168.1.0` or `10.1.0.0`)
- **Subnet:** `/24` (or match your Azure VNet setup)

![pfSense IPsec — Phase 2 Configuration](../images/image26.png)

![pfSense IPsec — Phase 2 Local/Remote Network](../images/image27.png)

### Step 6 — Connect and Verify Tunnel

Go to **Status → IPsec**:

![pfSense — Status IPsec Page](../images/image28.png)

Click **Connect P1 and P2s**. If settings are correct, the connection will be established. Verify in Azure:

![Azure VPN Gateway — Connection Status Confirmed](../images/image29.png)

---

## 18. Domain Joining Azure VM to On-Prem DC

After the VPN is established, pinging the on-prem DC from Azure may still fail. Follow these steps to resolve the issue.

### 1. Confirm Bidirectional Routing

**On pfSense:**
- Go to **VPN → IPsec → Status Overview** to confirm tunnel is "Established".
- Under **VPN → IPsec → Tunnels → Phase 2**, ensure:
  - Local network: `192.168.126.0/24`
  - Remote network: `192.168.1.0/24`
- Go to **Firewall → Rules → IPsec** and add a rule allowing required traffic (DNS, LDAP, Kerberos, SMB, RPC — ports 53, 88, 135, 389, 445, 636, 3268, 3269).

**In Azure:**
- Ensure the VNet address space includes `192.168.1.0/24` and the **Local Network Gateway** has `192.168.126.0/24`.
- Create a **User Defined Route (UDR)**:
  - Next hop: Virtual Network Gateway
  - Route: `192.168.126.0/24`
  - Associate with the Azure subnet containing your VM.

### 2. Configure DNS Correctly in Azure

Simply setting the VNet DNS to `192.168.126.30` often fails without proper VPN path and firewall permissions. Configure properly:

- **VNet DNS settings:** Set Custom DNS to `192.168.126.30` (your on-prem DNS/DC IP).
- Ensure the DNS server allows recursive queries from the remote Azure subnet `192.168.1.0/24`.
- On pfSense under **Services → DNS Resolver → Access Lists**, add the Azure subnet as allowed clients.
- If using Unbound, add a **Domain Override** for your AD domain to forward queries to the DC.

**Test DNS:**
```text
nslookup yourdomain.local 192.168.126.30
```
If this fails, DNS queries are not passing through the tunnel.

### 3. Verify Port Access for Domain Join

Open the following ports on pfSense's IPsec rules tab:
- TCP/UDP 53 — DNS
- TCP/UDP 88 — Kerberos
- TCP 135 — RPC
- TCP/UDP 389, 636 — LDAP/LDAPS
- TCP 445 — SMB
- TCP 3268–3269 — Global Catalog

> You can temporarily set an **"Allow all any-any"** rule under IPsec for testing, then tighten it afterward.

### 4. Connectivity Tests

On the Azure VM:
```cmd
ping 192.168.126.30
telnet 192.168.126.30 53
```
```powershell
Test-ComputerSecureChannel -Verbose   # after joining attempt
```

If ping or DNS fails, likely causes are:
- pfSense does not pass return traffic (missing static route).
- Azure subnet lacks a UDR to route back.

### Lab Implementation

#### Change DNS on Azure VNet to On-Prem DC IP

![Azure VNet — Custom DNS Set to On-Prem DC](../images/image30.png)

#### Create Route Table in Azure

1. Search for **Route tables** in the Azure Portal.
2. Click **+ Create** to create a new route table.

![Azure Route Table — Create Route Table](../images/image31.png)

After creating a route table, create a route inside it:

![Azure Route Table — Add Route](../images/image32.png)

**Where and How to Create a UDR in Azure Portal:**

1. Log in to the Azure Portal.
2. Search for and select **Route tables**.
3. Click **+ Create** / **+ Add**.
4. Fill in required details:
   - **Name:** e.g., `OnPrem-RouteTable`
   - **Subscription:** Your Azure subscription
   - **Resource Group:** Same as your Azure VNet
   - **Region:** Same as your VNet region
5. Click **Review + Create** → **Create**.
6. Once created, open the Route Table → **Settings → Routes** → **+ Add**:
   - **Route name:** e.g., `RouteToOnPrem`
   - **Address prefix:** `192.168.126.0/24` (your on-prem subnet)
   - **Next hop type:** Virtual network gateway
7. Click **OK**.
8. Associate the route table with your subnet: **Settings → Subnets** → **+ Associate** → Select VNet and subnet → **OK**.

> **Note:** You can select the option **Propagate gateway routes** to automatically include VPN gateway routes.

#### Configure pfSense Firewall Rules for Domain Traffic

For a pfSense site-to-site VPN with Azure, use a **Pass** rule on the IPsec interface allowing all protocols:

| Field | Value |
|---|---|
| **Action** | Pass |
| **Interface** | IPsec |
| **Protocol** | Any |
| **Source** | `192.168.1.0/24` (Azure subnet) |
| **Destination** | `192.168.126.0/24` (on-prem subnet) |
| **Description** | Allow Azure to On-Prem AD traffic |

> **Why Protocol Any?** Domain join requires TCP and UDP across multiple ports plus ICMP. Allowing all protocols is simpler and safer than listing each one individually during initial testing.

#### Windows Firewall Rule — Allow AD Traffic from Azure

```powershell
$azureSubnet = "192.168.1.0/24"

$tcpPorts = @(53, 88, 135, 389, 445, 636, 3268, 3269)
$udpPorts = @(53, 88, 389, 137, 138)

foreach ($port in $tcpPorts) {
    New-NetFirewallRule -DisplayName "Allow TCP port $port from AzureSubnet" `
        -Direction Inbound -LocalPort $port -Protocol TCP `
        -Action Allow -RemoteAddress $azureSubnet
}

foreach ($port in $udpPorts) {
    New-NetFirewallRule -DisplayName "Allow UDP port $port from AzureSubnet" `
        -Direction Inbound -LocalPort $port -Protocol UDP `
        -Action Allow -RemoteAddress $azureSubnet
}

# Allow Dynamic RPC ports
New-NetFirewallRule -DisplayName "Allow RPC Dynamic Ports from AzureSubnet" `
    -Direction Inbound -Protocol TCP -LocalPort 49152-65535 `
    -Action Allow -RemoteAddress $azureSubnet
```

After all these steps, you should be able to domain join the Azure VM to the on-prem DC.

---

## 19. Hub and Spoke Topology in Azure

### Architecture

| Resource | VNet | Subnet | IP Range |
|---|---|---|---|
| DC | Hub-VNet | HubSubnet | `192.168.1.0/24` |
| Azure Firewall | Hub-VNet | AzureFirewallSubnet | `10.0.1.0/24` |
| Spoke 1 VM(s) | Spoke1-VNet | Spoke1Subnet | `10.1.0.0/24` |
| Spoke 2 VM(s) | Spoke2-VNet | Spoke2Subnet | `10.2.0.0/24` |

### How Hub-and-Spoke Works with a DC

- The **Hub VNet** hosts the Domain Controller and Azure Firewall.
- **Spoke VNets** are peered to the Hub and route traffic through the Azure Firewall.
- Spoke VMs reach the DC via **VNet Peering** + **UDRs** pointing to the Azure Firewall as the next hop.

### PowerShell Deployment Script

#### 1. Set Variables

```powershell
$HubVNetName        = "myVM"
$HubRG              = "AZ-800"
$Location           = "Central India"

$AzFwSubnetName     = "AzureFirewallSubnet"
$AzFwSubnetPrefix   = "10.0.1.0/24"

$Spoke1RG           = "Spoke1RG"
$Spoke1VNet         = "Spoke1-VNet"
$Spoke1SubnetName   = "Spoke1-Subnet"
$Spoke1SubnetPrefix = "10.1.0.0/24"

$Spoke2RG           = "Spoke2RG"
$Spoke2VNet         = "Spoke2-VNet"
$Spoke2SubnetName   = "Spoke2-Subnet"
$Spoke2SubnetPrefix = "10.2.0.0/24"
```

#### 2. Add AzureFirewallSubnet to Existing Hub VNet

```powershell
$hubVNet = Get-AzVirtualNetwork -Name $HubVNetName -ResourceGroupName $HubRG

if (-not ($hubVNet.AddressSpace.AddressPrefixes -contains "10.0.1.0/24")) {
    $hubVNet.AddressSpace.AddressPrefixes.Add("10.0.1.0/24")
    Set-AzVirtualNetwork -VirtualNetwork $hubVNet
}

Add-AzVirtualNetworkSubnetConfig -Name $AzFwSubnetName -AddressPrefix $AzFwSubnetPrefix `
    -VirtualNetwork $hubVNet | Out-Null
Set-AzVirtualNetwork -VirtualNetwork $hubVNet | Out-Null
```

#### 3. Create Spoke Resource Groups

```powershell
New-AzResourceGroup -Name $Spoke1RG -Location $Location
New-AzResourceGroup -Name $Spoke2RG -Location $Location
```

#### 4. Create Spoke VNets

```powershell
$spoke1Subnet = New-AzVirtualNetworkSubnetConfig -Name $Spoke1SubnetName -AddressPrefix $Spoke1SubnetPrefix
$spoke1VNet   = New-AzVirtualNetwork -Name $Spoke1VNet -ResourceGroupName $Spoke1RG `
                -Location $Location -AddressPrefix $Spoke1SubnetPrefix -Subnet $spoke1Subnet

$spoke2Subnet = New-AzVirtualNetworkSubnetConfig -Name $Spoke2SubnetName -AddressPrefix $Spoke2SubnetPrefix
$spoke2VNet   = New-AzVirtualNetwork -Name $Spoke2VNet -ResourceGroupName $Spoke2RG `
                -Location $Location -AddressPrefix $Spoke2SubnetPrefix -Subnet $spoke2Subnet
```

#### 5. Create VNet Peerings (Bidirectional)

```powershell
# Hub <-> Spoke 1
Add-AzVirtualNetworkPeering -Name "HubToSpoke1" -VirtualNetwork $hubVNet `
    -RemoteVirtualNetworkId $spoke1VNet.Id -AllowVirtualNetworkAccess
Add-AzVirtualNetworkPeering -Name "Spoke1ToHub" -VirtualNetwork $spoke1VNet `
    -RemoteVirtualNetworkId $hubVNet.Id -AllowVirtualNetworkAccess

# Hub <-> Spoke 2
Add-AzVirtualNetworkPeering -Name "HubToSpoke2" -VirtualNetwork $hubVNet `
    -RemoteVirtualNetworkId $spoke2VNet.Id -AllowVirtualNetworkAccess
Add-AzVirtualNetworkPeering -Name "Spoke2ToHub" -VirtualNetwork $spoke2VNet `
    -RemoteVirtualNetworkId $hubVNet.Id -AllowVirtualNetworkAccess
```

> If you get errors with `AllowVirtualNetworkAccess`, create peerings without it first, then update:
> ```powershell
> $peering = Get-AzVirtualNetworkPeering -VirtualNetworkName $HubVNetName `
>            -ResourceGroupName $HubRG -Name "HubToSpoke1"
> $peering.AllowVirtualNetworkAccess = $true
> Set-AzVirtualNetworkPeering -VirtualNetworkPeering $peering
> ```

### Results — Resource Groups and VNets Created

![Hub-Spoke — Spoke RGs and VNets in Azure Portal](../images/image60.jpg)

---

## 20. Firewall Deployment

Deploy the Azure Firewall into the `AzureFirewallSubnet` of the Hub VNet using an ARM template.

### ARM Template — Azure Firewall

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "firewallName":  { "type": "string", "defaultValue": "MyAzureFirewall" },
    "location":      { "type": "string", "defaultValue": "Central India" },
    "publicIpName":  { "type": "string", "defaultValue": "MyAzFirewall-PIP" },
    "vnetName":      { "type": "string", "defaultValue": "myVM" },
    "subnetName":    { "type": "string", "defaultValue": "AzureFirewallSubnet" }
  },
  "resources": [
    {
      "type":       "Microsoft.Network/publicIPAddresses",
      "apiVersion": "2023-04-01",
      "name":       "[parameters('publicIpName')]",
      "location":   "[parameters('location')]",
      "sku":        { "name": "Standard" },
      "properties": { "publicIPAllocationMethod": "Static" }
    },
    {
      "type":       "Microsoft.Network/azureFirewalls",
      "apiVersion": "2023-04-01",
      "name":       "[parameters('firewallName')]",
      "location":   "[parameters('location')]",
      "dependsOn":  [ "[resourceId('Microsoft.Network/publicIPAddresses', parameters('publicIpName'))]" ],
      "properties": {
        "sku": { "name": "AZFW_VNet", "tier": "Standard" },
        "ipConfigurations": [{
          "name": "fw-ipconfig",
          "properties": {
            "subnet": {
              "id": "[resourceId(resourceGroup().name, 'Microsoft.Network/virtualNetworks/subnets', parameters('vnetName'), parameters('subnetName'))]"
            },
            "publicIPAddress": {
              "id": "[resourceId(resourceGroup().name, 'Microsoft.Network/publicIPAddresses', parameters('publicIpName'))]"
            }
          }
        }]
      }
    }
  ]
}
```

### Deploy the Firewall

Save the template as `azurefirewall.json`, then run:

```powershell
New-AzResourceGroupDeployment `
    -ResourceGroupName "AZ-800" `
    -TemplateFile      ".\azurefirewall.json"
```

### Lab Results — Firewall Deployed

![Azure Firewall — Deployment Result in Portal](../images/image61.jpg)

### Troubleshooting — Address Space Conflict

If you encounter an error about overlapping address spaces:

```powershell
$HubVNetName = "myVM"
$HubRG       = "AZ-800"
$hubVNet     = Get-AzVirtualNetwork -Name $HubVNetName -ResourceGroupName $HubRG

if (-not ($hubVNet.AddressSpace.AddressPrefixes -contains "10.0.1.0/24")) {
    $hubVNet.AddressSpace.AddressPrefixes.Add("10.0.1.0/24")
    Set-AzVirtualNetwork -VirtualNetwork $hubVNet
}

Add-AzVirtualNetworkSubnetConfig -Name "AzureFirewallSubnet" -AddressPrefix "10.0.1.0/24" `
    -VirtualNetwork $hubVNet | Out-Null
Set-AzVirtualNetwork -VirtualNetwork $hubVNet | Out-Null
```

---

## 21. Spoke VM Deployment

### Spoke 1 VM — Using ARM Template + Azure CLI

Save the ARM template as `windows11-spoke-vm.json` (includes NSG, NIC, and VM resources with RDP allowed), then deploy:

```bash
az deployment group create \
  --resource-group Spoke1RG \
  --template-file windows11-spoke-vm.json \
  --parameters vmName=Spoke1-VM \
               vmAdminUsername=YOURUSERNAME \
               vmAdminPassword=YOURPASSWORD \
               subnetId="/subscriptions/<YOUR_SUBSCRIPTION_ID>/resourceGroups/Spoke1RG/providers/Microsoft.Network/virtualNetworks/Spoke1-VNet/subnets/Spoke1-Subnet"
```

### Spoke 2 VM — Using PowerShell

```powershell
New-AzResourceGroupDeployment `
    -ResourceGroupName "Spoke2RG" `
    -TemplateFile      "windows11-spoke-vm.json" `
    -vmName            "Spoke2-VM" `
    -vmAdminUsername   "YOURUSERNAME" `
    -vmAdminPassword   (ConvertTo-SecureString "YOURPASSWORD" -AsPlainText -Force) `
    -subnetId          "/subscriptions/<YOUR_SUBSCRIPTION_ID>/resourceGroups/Spoke2RG/providers/Microsoft.Network/virtualNetworks/Spoke2-VNet/subnets/Spoke2-Subnet"
```

> **Note:** You can reuse the same ARM template (`windows11-spoke-vm.json`) for both Spoke 1 and Spoke 2 VM deployments.

![Spoke VMs — Both VMs Deployed in Azure Portal](../images/image62.jpg)

---

## 22. VNet Peering between DC VNet and Firewall VNet

Use this ARM template to establish bidirectional peering between the DC VNet and the Firewall/Hub VNet:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "hubVNetName":       { "type": "string" },
    "spokeVNetName":     { "type": "string" },
    "hubResourceGroup":  { "type": "string" },
    "spokeResourceGroup":{ "type": "string" }
  },
  "resources": [
    {
      "name":       "[concat(parameters('hubVNetName'), '/HubToSpokePeering')]",
      "type":       "Microsoft.Network/virtualNetworks/virtualNetworkPeerings",
      "apiVersion": "2023-04-01",
      "properties": {
        "remoteVirtualNetwork": {
          "id": "[resourceId(parameters('spokeResourceGroup'), 'Microsoft.Network/virtualNetworks', parameters('spokeVNetName'))]"
        },
        "allowVirtualNetworkAccess": true,
        "allowForwardedTraffic":     true,
        "allowGatewayTransit":       false,
        "useRemoteGateways":         false
      }
    },
    {
      "name":       "[concat(parameters('spokeVNetName'), '/SpokeToHubPeering')]",
      "type":       "Microsoft.Network/virtualNetworks/virtualNetworkPeerings",
      "apiVersion": "2023-04-01",
      "properties": {
        "remoteVirtualNetwork": {
          "id": "[resourceId(parameters('hubResourceGroup'), 'Microsoft.Network/virtualNetworks', parameters('hubVNetName'))]"
        },
        "allowVirtualNetworkAccess": true,
        "allowForwardedTraffic":     true,
        "allowGatewayTransit":       false,
        "useRemoteGateways":         false
      }
    }
  ]
}
```

### PowerShell Alternative — Bidirectional Peering

```powershell
$hubVNet   = Get-AzVirtualNetwork -Name "HubVNetName"   -ResourceGroupName "HubRG"
$spokeVNet = Get-AzVirtualNetwork -Name "SpokeVNetName" -ResourceGroupName "SpokeRG"

Add-AzVirtualNetworkPeering -Name "HubToSpokePeering" -VirtualNetwork $hubVNet `
    -RemoteVirtualNetworkId $spokeVNet.Id -AllowForwardedTraffic -AllowVirtualNetworkAccess

Add-AzVirtualNetworkPeering -Name "SpokeToHubPeering" -VirtualNetwork $spokeVNet `
    -RemoteVirtualNetworkId $hubVNet.Id -AllowForwardedTraffic -AllowVirtualNetworkAccess
```

### NSG — Allow AD Traffic to DC Subnet from Firewall Subnet

```json
{
  "type": "Microsoft.Network/networkSecurityGroups",
  "apiVersion": "2023-04-01",
  "name": "DCSubnet-NSG",
  "location": "Central India",
  "properties": {
    "securityRules": [
      {
        "name": "Allow-LDAP",
        "properties": {
          "priority": 100, "protocol": "Tcp",
          "sourceAddressPrefix": "10.0.0.0/16",
          "destinationPortRange": "389",
          "access": "Allow", "direction": "Inbound"
        }
      },
      {
        "name": "Allow-Kerberos",
        "properties": {
          "priority": 110, "protocol": "Tcp",
          "sourceAddressPrefix": "10.0.0.0/16",
          "destinationPortRange": "88",
          "access": "Allow", "direction": "Inbound"
        }
      }
    ]
  }
}
```

Deploy the NSG:

```powershell
New-AzResourceGroupDeployment -ResourceGroupName "YourResourceGroup" `
    -TemplateFile "DCSubnet-NSG-template.json" `
    -sourceAddressPrefix "10.0.0.0/16" `
    -location "Central India" `
    -nsgName "DCSubnet-NSG"
```

### Route Table — Force Spoke Traffic Through Azure Firewall

The route table for spoke subnets routes all traffic via the Azure Firewall (including traffic to the DC):

```json
"routes": [
  {
    "name": "default-route",
    "properties": {
      "addressPrefix":     "0.0.0.0/0",
      "nextHopType":       "VirtualAppliance",
      "nextHopIpAddress":  "<AzureFirewallPrivateIP>"
    }
  }
]
```

Deploy:

```bash
az deployment group create \
  --resource-group YourResourceGroup \
  --template-file routefirewall-template.json \
  --parameters routeTableName=YourRouteTableName \
               routeTableResourceGroup=YourResourceGroup \
               azureFirewallPrivateIP=<AzureFirewallPrivateIP> \
               firewallSubnetPrefix=<AzureFirewallSubnetCIDR> \
               dcSubnetPrefix=<DomainControllerSubnetCIDR> \
               location=<region>
```

#### Sample Parameter Values

```json
{
  "hubVNetName":           { "value": "HubVNet" },
  "hubResourceGroup":      { "value": "HubRG" },
  "spokeVNetName":         { "value": "Spoke2-VNet" },
  "spokeResourceGroup":    { "value": "Spoke2RG" },
  "azureFirewallPrivateIP":{ "value": "10.1.0.4" },
  "firewallSubnetPrefix":  { "value": "10.1.0.0/24" },
  "dcSubnetPrefix":        { "value": "10.2.0.0/24" },
  "location":              { "value": "Central India" },
  "nsgName":               { "value": "DCSubnet-NSG" },
  "routeTableName":        { "value": "Spoke2-RouteTable" }
}
```

### Internet Access from Spokes via Azure Firewall

#### 1. NAT Rule Collection for SNAT (Outbound Internet)

```json
{
  "name": "NAT-RuleCollection",
  "properties": {
    "priority": 100,
    "ruleCollectionType": "NatRuleCollection",
    "action": { "type": "Dnat" },
    "rules": [{
      "name": "OutboundSNAT",
      "ruleType": "NatRule",
      "protocols": ["TCP", "UDP"],
      "sourceAddresses":      ["<Spoke-Subnet-IP-Range>"],
      "destinationAddresses": ["*"],
      "destinationPorts":     ["*"],
      "translatedAddress":    "<AzureFirewall-Public-IP>",
      "translatedPort":       "*"
    }]
  }
}
```

#### 2. Network Rule Collection — Allow Internet-Bound Traffic

```json
{
  "name": "Internet-Access-RuleCollection",
  "properties": {
    "priority": 200,
    "ruleCollectionType": "NetworkRuleCollection",
    "action": { "type": "Allow" },
    "rules": [
      {
        "name": "Allow-HTTP",
        "protocols": ["TCP"],
        "sourceAddresses":      ["<Spoke-Subnet-IP-Range>"],
        "destinationAddresses": ["Internet"],
        "destinationPorts":     ["80"]
      },
      {
        "name": "Allow-HTTPS",
        "protocols": ["TCP"],
        "sourceAddresses":      ["<Spoke-Subnet-IP-Range>"],
        "destinationAddresses": ["Internet"],
        "destinationPorts":     ["443"]
      },
      {
        "name": "Allow-DNS",
        "protocols": ["UDP","TCP"],
        "sourceAddresses":      ["<Spoke-Subnet-IP-Range>"],
        "destinationAddresses": ["Internet"],
        "destinationPorts":     ["53"]
      }
    ]
  }
}
```

![Hub-Spoke — Final VNet Peering and Firewall Result](../images/image63.jpg)

![Hub-Spoke — Spoke Subnets Routing Through Firewall](../images/image64.jpg)

![Hub-Spoke — Full Topology Verified in Azure Portal](../images/image65.jpg)

---

## 23. Troubleshooting

### Issue — VPN Disconnects After Public IP Changes

**Symptom:** Site-to-Site VPN drops after your ISP assigns a new public IP to your home router/pfSense WAN.

**Solution:**
1. Find your new public IP address (Google "what is my IP").
2. In the Azure Portal, go to your **Local Network Gateway** resource.
3. Navigate to **Settings → Configuration**.
4. Update the **IP address** field with your new public IP.
5. Save the changes — the VPN tunnel will re-establish automatically.

### Issue — Peering Fails with "Address Space Overlap"

**Solution:** Update the Hub VNet address space before adding the `AzureFirewallSubnet`:

```powershell
$hubVNet = Get-AzVirtualNetwork -Name "myVM" -ResourceGroupName "AZ-800"

if (-not ($hubVNet.AddressSpace.AddressPrefixes -contains "10.0.1.0/24")) {
    $hubVNet.AddressSpace.AddressPrefixes.Add("10.0.1.0/24")
    Set-AzVirtualNetwork -VirtualNetwork $hubVNet
}

Add-AzVirtualNetworkSubnetConfig -Name "AzureFirewallSubnet" -AddressPrefix "10.0.1.0/24" `
    -VirtualNetwork $hubVNet | Out-Null
Set-AzVirtualNetwork -VirtualNetwork $hubVNet | Out-Null
```

### Issue — Azure VM Cannot Join On-Prem Domain

Check the following in order:
1. VPN tunnel status in pfSense (**Status → IPsec**) — must show "Established".
2. Azure VNet DNS setting — must point to on-prem DC IP (`192.168.126.30`).
3. pfSense IPsec firewall rules — must allow all AD ports (53, 88, 135, 389, 445, 636, 3268, 3269).
4. Azure UDR — must route `192.168.126.0/24` via Virtual Network Gateway.
5. On-prem Windows Firewall — must allow inbound AD ports from `192.168.1.0/24` (Azure subnet).
6. NSG on Azure subnet — must not block outbound traffic to on-prem.

### Issue — ARM Deployment Fails with Template Validation Error

- Validate your JSON syntax before deploying using VS Code with the ARM Tools extension.
- Ensure `apiVersion` values are current — outdated versions may be rejected.
- Check that all `dependsOn` references match exact resource names.

---

*This implementation guide was generated from the project documentation and lab environment of the [Hybrid-AD-Azure-Lab](https://github.com/utkarshstudent75-gif/Hybrid-AD-Azure-Lab).*
