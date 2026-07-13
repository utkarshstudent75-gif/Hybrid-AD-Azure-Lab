# 📦 ARM Templates

This folder contains Azure Resource Manager (ARM) templates used for repeatable infrastructure deployment.

| Template | Description |
|---|---|
| `hub-vnet.json` | Hub VNet with subnets, Azure Firewall, and route tables |

## Deploying a Template

```powershell
New-AzResourceGroupDeployment `
    -ResourceGroupName "AZ-800" `
    -TemplateFile ".\hub-vnet.json" `
    -Verbose
```
