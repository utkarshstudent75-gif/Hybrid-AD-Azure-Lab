# OU Design

## Goal
Design an OU structure that reflects administrative and policy needs, not physical geography.

## Structure
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

## Principles
- Keep hierarchy flat (max 3 levels)
- Separate Users and Computers at every department level
- Each OU exists because it needs a different GPO or delegation scope
- Enable ProtectedFromAccidentalDeletion on all OUs
- Use consistent naming: `[Dept] Users`, `[Dept] Computers`
