# Omnicit.PIM [![Azure DevOps builds](https://img.shields.io/azure-devops/build/omnicit/04de5b37-b0aa-4178-8500-8ee073e3b2a4/6)](https://dev.azure.com/omnicit/Omnicit.PIM/_build?definitionId=6&_a=summary) <img align="right" width="110" height="110" src="assets/icon.png">
 
[![PowerShell Gallery (with prereleases)](https://img.shields.io/powershellgallery/v/Omnicit.PIM?label=Omnicit.PIM%20Preview&include_prereleases)](https://www.powershellgallery.com/packages/Omnicit.PIM/)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/Omnicit.PIM?label=Omnicit.PIM)](https://www.powershellgallery.com/packages/Omnicit.PIM/)
[![Azure DevOps tests](https://img.shields.io/azure-devops/tests/omnicit/04de5b37-b0aa-4178-8500-8ee073e3b2a4/6)](https://dev.azure.com/omnicit/Omnicit.PIM/_test/analytics?definitionId=6&contextType=build)
![Azure DevOps coverage](https://img.shields.io/azure-devops/coverage/omnicit/04de5b37-b0aa-4178-8500-8ee073e3b2a4/6)
![PowerShell Gallery](https://img.shields.io/powershellgallery/p/Omnicit.PIM)

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

# List active role assignments
Get-OPIMDirectoryRole -Activated

# List BOTH eligible and active in one call
Get-OPIMDirectoryRole -All

# Activate — tab-complete the role name
Enable-OPIMDirectoryRole <tab>

# Activate using positional params: Role (pos 0), Justification (pos 1), Hours (pos 2)
Enable-OPIMDirectoryRole 'Global Administrator (elig-id)' 'Incident response' 4

# Activate by schedule ID (from Get-OPIMDirectoryRole id property)
Enable-OPIMDirectoryRole -Identity 'elig-001'

# Activate all eligible roles for 4 hours with a justification
Get-OPIMDirectoryRole | Enable-OPIMDirectoryRole -Hours 4 -Justification 'Incident response'

# Deactivate by schedule instance ID (from Get-OPIMDirectoryRole -Activated id property)
Disable-OPIMDirectoryRole -Identity 'active-instance-001'

# Deactivate all active roles
Get-OPIMDirectoryRole -Activated | Disable-OPIMDirectoryRole

# Activate and wait for provisioning before continuing
Get-OPIMDirectoryRole | Enable-OPIMDirectoryRole -Wait
```

### Azure Resource (RBAC) Roles

```powershell
# Connect
Connect-AzAccount

# List eligible roles (current user, all scopes)
Get-OPIMAzureRole

# List active role assignments
Get-OPIMAzureRole -Activated

# List BOTH eligible and active in one call
Get-OPIMAzureRole -All

# List eligible roles at a specific subscription scope
Get-OPIMAzureRole -Scope '/subscriptions/00000000-...'

# List active roles at a specific scope (exact scope match only)
Get-OPIMAzureRole -Activated -Scope '/subscriptions/00000000-...'

# Activate — tab-complete the role name
Enable-OPIMAzureRole <tab>

# Activate using positional params: Role (pos 0), Justification (pos 1), Hours (pos 2)
Enable-OPIMAzureRole 'Contributor -> My Subscription (elig-name)' 'Incident response' 4

# Activate by schedule Name (the Name property from Get-OPIMAzureRole)
Enable-OPIMAzureRole -Identity 'elig-schedule-name'

# Deactivate by schedule instance Name (from Get-OPIMAzureRole -Activated)
Disable-OPIMAzureRole -Identity 'active-schedule-name'

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

# List active group assignments
Get-OPIMEntraIDGroup -Activated

# List BOTH eligible and active in one call
Get-OPIMEntraIDGroup -All

# Filter by access type
Get-OPIMEntraIDGroup -AccessType member

# Activate — tab-complete the group name
Enable-OPIMEntraIDGroup <tab>

# Activate using positional params: Group (pos 0), Justification (pos 1), Hours (pos 2)
Enable-OPIMEntraIDGroup 'Finance Team - member (elig-id)' 'Project work' 2

# Activate by schedule ID (from Get-OPIMEntraIDGroup id property)
Enable-OPIMEntraIDGroup -Identity 'elig-001'

# Activate all eligible group assignments
Get-OPIMEntraIDGroup | Enable-OPIMEntraIDGroup -Hours 2 -Justification 'Project work'

# Deactivate by schedule instance ID (from Get-OPIMEntraIDGroup -Activated id property)
Disable-OPIMEntraIDGroup -Identity 'active-instance-001'

# Deactivate all active group assignments
Get-OPIMEntraIDGroup -Activated | Disable-OPIMEntraIDGroup
```

---

## Enable-OPIMMyRoles / pim  ·  Disable-OPIMMyRole / unpim

`Enable-OPIMMyRole` (aliases: `pim`, `Enable-OPIMMyRoles`) is the all-in-one activation command.
`Disable-OPIMMyRole` (aliases: `unpim`, `Disable-OPIMMyRoles`) is its counterpart for deactivation.

Both commands reuse an existing authenticated session — if you have already called `Connect-OPIM`
or run any `Get-OPIM*` cmdlet, no additional browser prompt is shown.

Output is a unified table across all three role types:

```
Category    Action       Status              DisplayName                       Scope          EndDateTime
--------    ------       ------              -----------                       -----          -----------
EntraIDGroup selfActivate PendingProvisioning role_sec_office365_administrator member         2026-04-20 21:54:57
EntraIDGroup selfActivate PendingProvisioning role_sec_security_administrator  member         2026-04-20 21:55:08
AzureRole    SelfActivate Provisioned        Owner                             EA - Security  2026-04-20 21:55:26
```

### Activation — pim

```powershell
# Activate all configured roles/groups for 1 hour (reuses existing token if already connected)
pim -TenantAlias contoso

# Activate using a named tenant alias looked up in TenantMap.psd1, for 4 hours
pim -TenantAlias contoso -Hours 4 -Justification 'Incident response'

# Wait until directory role activations are fully provisioned
pim -TenantAlias corp -Wait

# Activate ALL eligible roles without a stored alias (confirmation required per category)
pim -AllEligible -Confirm:$false

# Activate only directory roles and Azure roles
Enable-OPIMMyRole -AllEligibleDirectoryRoles -AllEligibleAzureRoles
```

### Deactivation — unpim

```powershell
# Deactivate all configured roles/groups for a tenant alias
unpim -TenantAlias contoso

# Items that are not currently active are silently skipped (use -Verbose to see them)
unpim -TenantAlias contoso -Verbose

# Deactivate ALL currently active roles without a stored alias (confirmation required per category)
unpim -AllActivated -Confirm:$false

# Deactivate only directory roles and Entra ID groups
Disable-OPIMMyRole -AllActivatedDirectoryRoles -AllActivatedEntraIDGroups

# Preview without making changes
unpim -TenantAlias contoso -WhatIf
```

The default activation duration is 1 hour. Override persistently:

```powershell
$PSDefaultParameterValues['Enable-OPIM*:Hours'] = 4
```

---

## Configuration CRUD

The four `*-OPIMConfiguration` cmdlets manage the `TenantMap.psd1` file that `pim` uses to
resolve tenant aliases:

| Cmdlet | Alias | Purpose |
|---|---|---|
| `Install-OPIMConfiguration` | — | **Create** — add a new alias. Error if alias already exists. |
| `Get-OPIMConfiguration` | `Get-PIMConfig` | **Read** — return one typed object per alias. |
| `Set-OPIMConfiguration` | `Set-PIMConfig` | **Update** — change TenantId or replace stored role lists. |
| `Remove-OPIMConfiguration` | `Remove-PIMConfig` | **Delete** — remove an alias, preserve the rest. |

### Install-OPIMConfiguration — create a new alias

```powershell
# Register a new tenant alias
Install-OPIMConfiguration -TenantAlias contoso -TenantId '00000000-0000-0000-0000-000000000000'

# Register and store specific directory roles as the default activation set
Get-OPIMDirectoryRole | Where-Object { $_.roleDefinition.displayName -like 'Compliance*' } |
    Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>'

# Preview without writing
Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>' -WhatIf
```

> **Install is create-only.** If the alias already exists a non-terminating error is emitted.
> Use `Set-OPIMConfiguration` to update an existing alias.

### Get-OPIMConfiguration — read current configuration

```powershell
# List all tenant aliases
Get-OPIMConfiguration

# Inspect a specific alias
Get-OPIMConfiguration -TenantAlias contoso

# Use a custom file path
Get-OPIMConfiguration -TenantMapPath 'D:\config\MyTenants.psd1'
```

### Set-OPIMConfiguration — update an existing alias

```powershell
# Update only the TenantId, preserve stored role lists
Set-OPIMConfiguration -TenantAlias contoso -TenantId '<new-guid>'

# Replace the stored DirectoryRoles list
Get-OPIMDirectoryRole | Where-Object { $_.roleDefinition.displayName -like '*Admin*' } |
    Set-OPIMConfiguration -TenantAlias contoso

# Replace the stored EntraIDGroups list
Get-OPIMEntraIDGroup | Set-OPIMConfiguration -TenantAlias contoso

# Preview without writing
Set-OPIMConfiguration -TenantAlias contoso -TenantId '<new-guid>' -WhatIf
```

### Remove-OPIMConfiguration — delete an alias

```powershell
# Remove the 'contoso' alias (other aliases are preserved)
Remove-OPIMConfiguration -TenantAlias contoso

# Preview without writing
Remove-OPIMConfiguration -TenantAlias contoso -WhatIf
```

---

## TenantMap

The TenantMap is a PowerShell data file (`.psd1`) that maps short tenant aliases to Azure Tenant
IDs. Each alias can optionally store a default set of roles and groups to activate, so `pim` only
activates what you actually need rather than everything eligible.

> **The TenantAlias is the key.** You can change the TenantId (e.g. after a tenant migration) by
> running `Set-OPIMConfiguration -TenantAlias <same-alias> -TenantId <new-guid>`
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
# Add a new tenant alias with no role defaults (activates all eligible at runtime)
Install-OPIMConfiguration -TenantAlias contoso -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

# Add a second tenant
Install-OPIMConfiguration -TenantAlias fabrikam -TenantId 'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy'

# Update the TenantId for an existing alias (role lists are preserved)
Set-OPIMConfiguration -TenantAlias contoso -TenantId '<new-guid>'

# Read back the current configuration
Get-OPIMConfiguration

# Remove an alias (other aliases are preserved)
Remove-OPIMConfiguration -TenantAlias fabrikam

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

# Update directory roles and groups incrementally using Set-OPIMConfiguration
Get-OPIMDirectoryRole |
    Where-Object { $_.roleDefinition.displayName -like '*Admin*' } |
    Set-OPIMConfiguration -TenantAlias contoso
Get-OPIMEntraIDGroup |
    Set-OPIMConfiguration -TenantAlias contoso
```

> **Tip:** Pipe new role/group objects to `Set-OPIMConfiguration` to replace the stored list
> for that category. Categories not supplied via pipeline retain their existing values.
> To update only the `TenantId` without touching role lists, run `Set-OPIMConfiguration` with
> `-TenantId` and no pipeline input.

### Using a custom path

```powershell
# One-off override
pim    -TenantAlias contoso -TenantMapPath 'D:\config\MyTenants.psd1'
unpim  -TenantAlias contoso -TenantMapPath 'D:\config\MyTenants.psd1'

# Permanent: add to your profile
$PSDefaultParameterValues['Enable-OPIMMyRole:TenantMapPath']         = 'D:\config\MyTenants.psd1'
$PSDefaultParameterValues['Disable-OPIMMyRole:TenantMapPath']        = 'D:\config\MyTenants.psd1'
$PSDefaultParameterValues['Install-OPIMConfiguration:TenantMapPath'] = 'D:\config\MyTenants.psd1'
$PSDefaultParameterValues['Get-OPIMConfiguration:TenantMapPath']     = 'D:\config\MyTenants.psd1'
$PSDefaultParameterValues['Set-OPIMConfiguration:TenantMapPath']     = 'D:\config\MyTenants.psd1'
$PSDefaultParameterValues['Remove-OPIMConfiguration:TenantMapPath']  = 'D:\config\MyTenants.psd1'
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
    Set-OPIMConfiguration -TenantAlias corp

Get-OPIMEntraIDGroup -AccessType member |
    Set-OPIMConfiguration -TenantAlias corp

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
| `Enable-OPIMMyRole` | `pim`, `Enable-OPIMMyRoles` |
| `Disable-OPIMMyRole` | `unpim`, `Disable-OPIMMyRoles` |

---

## Default Activation Duration

The default activation period is 1 hour. Override per-call with `-Hours`, or make it persistent:

```powershell
$PSDefaultParameterValues['Enable-OPIM*:Hours'] = 4
```

Or add to your profile:  `$PSDefaultParameterValues['Enable-OPIM*:Hours'] = 4`

---

## Positional Parameters for Enable-*

All three `Enable-OPIM*` cmdlets accept positional arguments in this order:

| Position | Parameter | Example |
|---|---|---|
| 0 | `-RoleName` / `-GroupName` | `'Global Administrator (elig-id)'` |
| 1 | `-Justification` | `'Incident response'` |
| 2 | `-Hours` | `4` |

```powershell
# Explicit
Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-id)' -Justification 'Incident' -Hours 4

# Positional (identical result)
Enable-OPIMDirectoryRole 'Global Administrator (elig-id)' 'Incident' 4
```

---

## Using -All, -Activated, and default (eligible only)

All `Get-OPIM*` cmdlets support three modes. `-All` and `-Activated` are mutually exclusive:

| Command | Returns |
|---|---|
| `Get-OPIMDirectoryRole` | Eligible (inactive) roles only |
| `Get-OPIMDirectoryRole -Activated` | Currently active role assignments |
| `Get-OPIMDirectoryRole -All` | Both eligible **and** active for the current user |

The same applies to `Get-OPIMEntraIDGroup` and `Get-OPIMAzureRole`.

> **Note:** `-All` returns both schedule types **for the current user**. It does not list other
> users' roles. Both result types are returned with their correct TypeNames so Format views apply.

---

## Using -Identity for direct activation/deactivation

Every `Enable-OPIM*` and `Disable-OPIM*` cmdlet accepts `-Identity` to target a specific schedule
by ID without needing tab completion:

```powershell
# Get the ID of an eligible role
Get-OPIMDirectoryRole | Select-Object id, @{n='Role';e={$_.roleDefinition.displayName}}

# Activate by ID
Enable-OPIMDirectoryRole -Identity 'elig-001'

# Deactivate by ID (use the id from -Activated output)
Get-OPIMDirectoryRole -Activated | Select-Object id, @{n='Role';e={$_.roleDefinition.displayName}}
Disable-OPIMDirectoryRole -Identity 'active-instance-001'
```

For Azure RBAC roles the identity is the **Name** property (not `id`):

```powershell
Get-OPIMAzureRole | Select-Object Name, RoleDefinitionDisplayName, ScopeId
Enable-OPIMAzureRole -Identity 'eligible-schedule-name'

Get-OPIMAzureRole -Activated | Select-Object Name, RoleDefinitionDisplayName
Disable-OPIMAzureRole -Identity 'active-schedule-name'
```

---

## Using -Filter for OData queries

`Get-OPIMDirectoryRole` and `Get-OPIMEntraIDGroup` accept an OData `-Filter` string for
server-side filtering. Common examples:

```powershell
# Filter by role definition (Directory roles)
Get-OPIMDirectoryRole -Filter "roleDefinitionId eq '62e90394-69f5-4237-9190-012177145e10'"

# Filter by group ID (Entra ID Groups)
Get-OPIMEntraIDGroup -Filter "groupId eq '00000000-0000-0000-0000-000000000000'"

# Filter by principal (requires elevated permissions)
Get-OPIMDirectoryRole -Filter "principalId eq '00000000-0000-0000-0000-000000000000'"

# -Identity is shorthand for id eq '<value>' filter
Get-OPIMDirectoryRole -Identity 'elig-001'
# equivalent to:
Get-OPIMDirectoryRole -Filter "id eq 'elig-001'"
```

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
| `Microsoft.Graph.Authentication` 2.36+ | Directory roles and Entra ID group PIM (raw `Invoke-MgGraphRequest`) |
| `Az.Resources` 9.0.3+ | Azure resource (RBAC) roles |

---

---

## Development

### Build system overview

This module uses [Sampler](https://github.com/gaelcolas/Sampler) + [ModuleBuilder](https://github.com/PoshCode/ModuleBuilder) for compilation. The key distinction between source mode and compiled mode is:

| | Source mode | Compiled mode |
|---|---|---|
| Import | `Import-Module ./Source/Omnicit.PIM.psd1 -Force` | `Import-Module ./output/module/Omnicit.PIM/<ver>/Omnicit.PIM.psd1` |
| Functions | Dot-sourced at runtime by `Omnicit.PIM.psm1` | Merged into a single `Omnicit.PIM.psm1` by ModuleBuilder |
| Type data | Loaded by `Omnicit.PIM.psm1` via `Update-TypeData` | Loaded by `suffix.ps1` via `Update-TypeData` |
| Format data | Loaded natively via `FormatsToProcess` in manifest | Loaded natively via `FormatsToProcess` in manifest |

### Source `Omnicit.PIM.psm1`

The source psm1 is a **source-mode-only** loader. Its contents are **discarded** during a build. ModuleBuilder replaces it entirely with a compiled file that merges all `Classes/`, `Private/`, and `Public/` files in load order.

Do not put runtime initialization logic here expecting it to run in the compiled module. Use `suffix.ps1` instead.

### `suffix.ps1` (and `prefix.ps1`)

ModuleBuilder appends `suffix.ps1` to the compiled psm1 verbatim (configured in `build.yaml` as `suffix: suffix.ps1`). This is the correct place for any initialization that must run at module import time in the compiled module — type data registration, alias setup, etc.

> **Format data** is loaded natively via `FormatsToProcess` in the manifest (zero-cost). **Type data** is loaded by `suffix.ps1` via a single `Update-TypeData` call with `-ErrorAction SilentlyContinue` because `TypesToProcess` in the manifest does not support `-ErrorAction` and `Remove-Module` does not clean type data, causing "member already present" errors on `Import-Module -Force`.

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

