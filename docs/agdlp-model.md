# AGDLP Model

## What is AGDLP?
AGDLP stands for: **A**ccounts → **G**lobal Groups → **D**omain **L**ocal Groups → **P**ermissions

Instead of assigning permissions directly to users, you nest them through groups. This makes auditing, changes, and scaling much easier.

## Sales Department Example

```
User: rgoyal (Sales)
  └── Member of: Sales Team [Global Group]
        └── Member of: SalesReadOnly [Domain Local Group]
              └── Has: Read permission on \\DC01\SalesFiles
```

## Why It Matters
- Moving a user between teams = just change their Global Group membership
- Auditing who has access to a resource = check the Domain Local Group
- No direct user-to-resource permission links = clean, scalable, auditable
