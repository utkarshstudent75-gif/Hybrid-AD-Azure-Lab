# Microsoft Entra Connect — Setup & Verification

## Installation Steps
1. Download Entra Connect from Microsoft
2. Run installer on WS2022-DC01
3. Choose Express or Custom setup
4. Sign in with Azure Global Admin credentials
5. Enter on-prem Enterprise Admin credentials
6. Select OUs to sync
7. Enable optional features as needed
8. Install and verify

## Optional Features Configured
| Feature | Purpose |
|---|---|
| Password Hash Sync | Fallback authentication method |
| Password Writeback | Cloud resets apply to on-prem AD |
| Pass-Through Authentication | Users auth against on-prem DC directly |
| SSPR | Users reset own passwords without IT |
| Password Protection | Banned password lists enforced at DC |

## Running a Manual Delta Sync
```powershell
Start-ADSyncSyncCycle -PolicyType Delta
```

## Verification
- Check Synchronization Service Manager (miisclient.exe)
- Verify user attributes updated in Azure portal under Entra ID > Users
- Review sign-in logs in Entra admin center
