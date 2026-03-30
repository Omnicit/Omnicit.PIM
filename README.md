# Omnicit.PIM — Privileged Identity Management Module

A PowerShell module for self-service activation and deactivation of PIM roles and group memberships across three surfaces:

| Surface | Noun | Cmdlet prefix |
|---|---|---|
| Azure AD / Entra ID directory roles | `DirectoryRole` | `OPIM` |
| Azure resource (RBAC) roles | `AzureRole` | `OPIM` |
| Entra ID PIM groups | `EntraIDGroup` | `OPIM` |

> Originally created by [Justin Grote @justinwgrote](https://github.com/justinwgrote). Overhauled and maintained by [Omnicit](https://github.com/Omnicit).

---

## Installation

```powershell
Install-Module Omnicit.PIM
Import-Module Omnicit.PIM
```

---

## Quick Start

### Azure AD / Entra ID Directory Roles

```powershell
# Connect (request only what you need)
Connect-MgGraph -Scopes 'RoleEligibilitySchedule.ReadWrite.Directory',
                         'RoleAssignmentSchedule.ReadWrite.Directory',
                         'AdministrativeUnit.Read.All'

# List eligible roles
Get-OPIMDirectoryRole

# Activate — tab-complete the role name
Enable-OPIMDirectoryRole <tab>

# Activate all eligible roles for 4 hours with a justification
Get-OPIMDirectoryRole | Enable-OPIMDirectoryRole -Hours 4 -Justification 'Incident response'

# Deactivate
Get-OPIMDirectoryRole -Activated | Disable-OPIMDirectoryRole

# Activate and wait for provisioning before continuing
Get-OPIMDirectoryRole | Enable-OPIMDirectoryRole -Wait
```

### Azure Resource (RBAC) Roles

```powershell
# Connect
Connect-AzAccount

# List eligible roles
Get-OPIMAzureRole

# Activate — tab-complete the role name
Enable-OPIMAzureRole <tab>

# Deactivate all active roles
Get-OPIMAzureRole -Activated | Disable-OPIMAzureRole
```

### Entra ID PIM Groups

```powershell
# Connect (additional scope required)
Connect-MgGraph -Scopes 'RoleEligibilitySchedule.ReadWrite.Directory',
                         'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup'

# List eligible group memberships/ownerships
Get-OPIMEntraIDGroup

# Filter by access type
Get-OPIMEntraIDGroup -AccessType member

# Activate — tab-complete the group name
Enable-OPIMEntraIDGroup <tab>

# Activate all eligible group assignments
Get-OPIMEntraIDGroup | Enable-OPIMEntraIDGroup -Hours 2 -Justification 'Project work'

# Deactivate
Get-OPIMEntraIDGroup -Activated | Disable-OPIMEntraIDGroup
```

---

## Enable-OPIMMyRoles / pim

`Enable-OPIMMyRoles` (alias: `pim`) is the all-in-one activation command. It connects to
Microsoft Graph (and Azure if Azure roles are configured) and activates all eligible directory
roles, PIM group assignments, and Azure RBAC roles for the current user.

```powershell
# Activate all eligible roles/groups for 1 hour (prompts for Graph login if not connected)
pim

# Activate using a named tenant alias looked up in TenantMap.psd1, for 4 hours
pim -TenantAlias contoso -Hours 4 -Justification 'Incident response'

# Wait until directory role activations are fully provisioned
pim -TenantAlias corp -Wait
```

The default activation duration is 1 hour. Override persistently:

```powershell
$PSDefaultParameterValues['Enable-OPIM*:Hours'] = 4
```

---

## Install-OPIMConfiguration

Manages the `TenantMap.psd1` file used by `Enable-OPIMMyRoles` / `pim` to resolve tenant
aliases and optionally filter which roles/groups are activated per tenant.

```powershell
# Register a tenant alias (TenantAlias is the key — the GUID can be updated later with -Force)
Install-OPIMConfiguration -TenantAlias contoso -TenantId '00000000-0000-0000-0000-000000000000'

# Store specific directory roles as the default activation set for a tenant
Get-OPIMDirectoryRole | Where-Object { $_.roleDefinition.displayName -like 'Compliance*' } |
    Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>'

# Preview without writing
Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>' -WhatIf
```

---

## TenantMap

The TenantMap is a PowerShell data file (`.psd1`) that maps short tenant aliases to Azure Tenant
IDs. Each alias can optionally store a default set of roles and groups to activate, so `pim` only
activates what you actually need rather than everything eligible.

> **The TenantAlias is the key.** You can change the TenantId (e.g. after a tenant migration) by
> running `Install-OPIMConfiguration -TenantAlias <same-alias> -TenantId <new-guid> -Force`
> without losing your stored role/group configuration.

### Default location

```
$env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1
```

### File format

Each entry is a nested hashtable under the alias key. The only required field is `TenantId`;
the role/group arrays are optional — omit them and `pim` will activate **all** eligible items:

```powershell
@{
    # Alias 'corp' — activates only the two stored directory roles and one group
    'corp' = @{
        TenantId       = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
        DirectoryRoles = @('e8611ab8-c189-46e8-94e1-60213ab1f814')   # roleDefinitionId
        EntraIDGroups  = @('75b93f19-07b0-4d87-8b7f-6bd04d79f023_member')  # groupId_accessId
        AzureRoles     = @('schedule-name-from-get-opimazurerole')
    }
    # Alias 'partner' — no role list: activates ALL eligible items at login
    'partner' = @{
        TenantId = 'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy'
    }
}
```

The file is safe to edit manually — it is standard PowerShell data file syntax.

### Key identifiers stored per type

| Type | Stored value | Field on Get-OPIM* object |
|---|---|---|
| Directory Role | `roleDefinitionId` | `$_.roleDefinitionId` |
| Entra ID Group | `"{groupId}_{accessId}"` | `"$($_.groupId)_$($_.accessId)"` |
| Azure Role | Schedule name | `$_.Name` |

These identifiers are stable across eligibility renewals. The `accessId` in the group key is
either `member` or `owner`, so you can store member and owner eligibility for the same group
independently.

### Creating and managing entries

```powershell
# Basic — add a tenant alias with no role defaults (activates all eligible at runtime)
# -TenantMap is optional: it is implied when -TenantAlias and -TenantId are provided
Install-OPIMConfiguration -TenantAlias contoso -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

# Add a second tenant
Install-OPIMConfiguration -TenantAlias fabrikam -TenantId 'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy'

# Overwrite an existing alias (update TenantId; existing role lists are preserved)
Install-OPIMConfiguration -TenantAlias contoso -TenantId '<new-guid>' -Force

# Preview without writing
Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>' -WhatIf
```

### Configuring default roles by piping from Get-OPIM*

Pipe `Get-OPIM*` output (optionally filtered with `Where-Object`) to store exactly which
roles/groups `pim` should activate for a tenant. Both eligible (`default`) and activated
(`-Activated`) objects are accepted — useful for piping your currently active roles as the
default set. `-TenantMap` is implied; `-TenantAlias` and `-TenantId` are required.

```powershell
# Store all eligible directory roles for this tenant
Get-OPIMDirectoryRole |
    Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>'

# Store only specific directory roles (by display name pattern)
Get-OPIMDirectoryRole |
    Where-Object { $_.roleDefinition.displayName -in 'Compliance Administrator','User Administrator' } |
    Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>'

# Store currently active groups as defaults (pipe from -Activated)
Get-OPIMEntraIDGroup -Activated |
    Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>'

# Store eligible PIM group memberships only (not ownerships)
Get-OPIMEntraIDGroup -AccessType member |
    Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>'

# Store specific Azure RBAC roles
Get-OPIMAzureRole |
    Where-Object { $_.RoleDefinitionDisplayName -like 'Contributor*' } |
    Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>'

# Combine directory roles AND groups in two calls with -Force to update incrementally
Get-OPIMDirectoryRole |
    Where-Object { $_.roleDefinition.displayName -like '*Admin*' } |
    Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>' -Force
Get-OPIMEntraIDGroup |
    Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>' -Force
```

> **Tip:** Running `Install-OPIMConfiguration` again with `-Force` and new piped input
> replaces the stored role list. Omit pipe input with `-Force` to update only the `TenantId`
> while keeping the existing role/group lists intact.

### Using a custom path

```powershell
# One-off override
pim -TenantAlias contoso -TenantMapPath 'D:\config\MyTenants.psd1'

# Permanent: add to your profile
$PSDefaultParameterValues['Enable-OPIMMyRoles:TenantMapPath'] = 'D:\config\MyTenants.psd1'
$PSDefaultParameterValues['Install-OPIMConfiguration:TenantMapPath'] = 'D:\config\MyTenants.psd1'
```

### Multi-tenant workflow example

```powershell
# ── First-time setup (run once) ───────────────────────────────────────────────

# 1. Register tenant aliases
Install-OPIMConfiguration -TenantAlias corp    -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
Install-OPIMConfiguration -TenantAlias partner -TenantId 'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy'

# 2. Connect to the corp tenant and configure default roles
Connect-MgGraph -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -Scopes `
    'RoleEligibilitySchedule.ReadWrite.Directory', `
    'RoleAssignmentSchedule.ReadWrite.Directory', `
    'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup', `
    'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup', `
    'AdministrativeUnit.Read.All'

Get-OPIMDirectoryRole |
    Where-Object { $_.roleDefinition.displayName -in 'Compliance Administrator','Security Reader' } |
    Install-OPIMConfiguration -TenantAlias corp -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -Force

Get-OPIMEntraIDGroup -AccessType member |
    Install-OPIMConfiguration -TenantAlias corp -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -Force

# ── Daily use ─────────────────────────────────────────────────────────────────

# Activate only the stored roles in corp tenant
pim -TenantAlias corp -Hours 8 -Justification 'Daily operations'

# Activate everything eligible in partner tenant (no stored role list)
pim -TenantAlias partner -Hours 2 -Justification 'Partner review'
```

---

## Short Aliases

For backwards compatibility and convenience, short `PIM`-prefixed aliases are available:

| Canonical cmdlet | Aliases |
|---|---|
| `Get-OPIMDirectoryRole` | `Get-PIMADRole`, `Get-PIMRole` |
| `Enable-OPIMDirectoryRole` | `Enable-PIMADRole`, `Enable-PIMRole` |
| `Disable-OPIMDirectoryRole` | `Disable-PIMADRole`, `Disable-PIMRole` |
| `Wait-OPIMDirectoryRole` | `Wait-PIMADRole`, `Wait-PIMRole` |
| `Get-OPIMAzureRole` | `Get-PIMResourceRole` |
| `Enable-OPIMAzureRole` | `Enable-PIMResourceRole` |
| `Disable-OPIMAzureRole` | `Disable-PIMResourceRole` |
| `Get-OPIMEntraIDGroup` | `Get-PIMGroup` |
| `Enable-OPIMEntraIDGroup` | `Enable-PIMGroup` |
| `Disable-OPIMEntraIDGroup` | `Disable-PIMGroup` |
| `Enable-OPIMMyRoles` | `pim` |

---

## Default Activation Duration

The default activation period is 1 hour. Override per-call with `-Hours`, or make it persistent:

```powershell
$PSDefaultParameterValues['Enable-OPIM*:Hours'] = 4
```

Or add to your profile:  `$PSDefaultParameterValues['Enable-OPIM*:Hours'] = 4`

---

## WhatIf / Confirm Support

All activation and deactivation commands support `-WhatIf` and `-Confirm`:

```powershell
Get-OPIMDirectoryRole | Enable-OPIMDirectoryRole -WhatIf
```

---

## Activated vs Active

This module distinguishes:

- **Eligible** — a role assignment you can activate but haven't yet
- **Activated** — an eligible role you have explicitly turned on for a time window
- **Active (persistent)** — a role that is always on (outside scope of this module)

Use `-Activated` on the `Get-OPIM*` cmdlets to see currently active assignments.

---

## Dependencies

| Dependency | Purpose |
|---|---|
| `Microsoft.Graph.Authentication` 2.0+ | Directory roles and Entra ID group PIM (raw `Invoke-MgGraphRequest`) |
| `Az.Resources` 5.6+ | Azure resource (RBAC) roles |

---

---

## Development

### Build system overview

This module uses [Sampler](https://github.com/gaelcolas/Sampler) + [ModuleBuilder](https://github.com/PoshCode/ModuleBuilder) for compilation. The key distinction between source mode and compiled mode is:

| | Source mode | Compiled mode |
|---|---|---|
| Import | `Import-Module ./Source/Omnicit.PIM.psd1 -Force` | `Import-Module ./output/module/Omnicit.PIM/<ver>/Omnicit.PIM.psd1` |
| Functions | Dot-sourced at runtime by `Omnicit.PIM.psm1` | Merged into a single `Omnicit.PIM.psm1` by ModuleBuilder |
| Type data | Loaded by `Omnicit.PIM.psm1` | Loaded by `suffix.ps1` (appended to built psm1) |
| Format data | Loaded by `Omnicit.PIM.psm1` | Loaded by `suffix.ps1` (appended to built psm1) |

### Source `Omnicit.PIM.psm1`

The source psm1 is a **source-mode-only** loader. Its contents are **discarded** during a build. ModuleBuilder replaces it entirely with a compiled file that merges all `Classes/`, `Private/`, and `Public/` files in load order.

Do not put runtime initialization logic here expecting it to run in the compiled module. Use `suffix.ps1` instead.

### `suffix.ps1` (and `prefix.ps1`)

ModuleBuilder appends `suffix.ps1` to the compiled psm1 verbatim (configured in `build.yaml` as `suffix: suffix.ps1`). This is the correct place for any initialization that must run at module import time in the compiled module — type data registration, format data registration, alias setup, etc.

A `prefix.ps1` (not currently used) would be prepended to the compiled psm1 in the same way.

### Common commands

```powershell
# Bootstrap dependencies (first time)
./build.ps1 -ResolveDependency -Tasks noop

# Compile the module
./build.ps1

# Run Pester tests + PSScriptAnalyzer
./build.ps1 -AutoRestore -Tasks test

# Import from source for interactive development
Import-Module ./Source/Omnicit.PIM.psd1 -Force
```

---

## Attribution

This module is a fork/overhaul of [JAz.PIM](https://github.com/JustinGrote/JAz.PIM) by [Justin Grote @justinwgrote](https://github.com/justinwgrote), released under the [MIT License](LICENSE).

