# Omnicit.PIM [![Build and test](https://github.com/Omnicit/Omnicit.PIM/actions/workflows/build-and-test.yml/badge.svg?branch=main)](https://github.com/Omnicit/Omnicit.PIM/actions/workflows/build-and-test.yml) <img align="right" width="110" height="110" src="assets/icon.png">
 
[![PowerShell Gallery (with prereleases)](https://img.shields.io/powershellgallery/v/Omnicit.PIM?label=Omnicit.PIM%20Preview&include_prereleases)](https://www.powershellgallery.com/packages/Omnicit.PIM/)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/Omnicit.PIM?label=Omnicit.PIM)](https://www.powershellgallery.com/packages/Omnicit.PIM/)
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

## Authentication

All `Get-/Enable-/Disable-OPIM*` cmdlets authenticate automatically on first use — a browser
window opens once, the token is cached via MSAL for the session, and subsequent calls are
idempotent. You never need to call `Connect-MgGraph` or `Connect-AzAccount` manually.

`Connect-OPIM` is the module's optional pre-authentication command. Use it when you want the
browser prompt at a predictable time or need to target a specific tenant:

```powershell
Connect-OPIM                                          # home tenant at the first sign-in, then the session's tenant
Connect-OPIM -TenantId 'contoso.onmicrosoft.com'     # specific tenant
Connect-OPIM -TenantAlias corp                        # resolve alias from TenantMap.psd1
Connect-OPIM -IncludeARM                              # also sign in to Azure, for the same tenant
```

A session stays on the tenant it signed in to. A command that names no tenant keeps that tenant,
and every new token must be issued for it: a token for another tenant is refused with
`TenantMismatch`, and nothing is sent. To work in another tenant, run `Connect-OPIM -TenantId`
with it, or `Disconnect-OPIM` and sign in again.

The Microsoft Graph PowerShell SDK keeps one session per PowerShell process. If something else in
the same process runs `Connect-MgGraph` after Omnicit.PIM signed in, the role, group and sign-in
commands refuse to send their calls under that session (`GraphSessionChanged`) instead of
switching it back. Run `Disconnect-OPIM`, which also disconnects that other session, and sign in
again -- or use a new PowerShell window. The configuration commands are the exception, by design:
`Install-OPIMConfiguration` and `Set-OPIMConfiguration` read whatever Graph session is active --
`Install-OPIMConfiguration` takes its tenant when you omit `-TenantId`, and both read the tenant's
display name for the confirmation prompt.

A command whose sign-in at its start was refused sends nothing more, even when it carries on past
the error: every request it would still make is refused with `SignInRefused`. A sign-in refused
while a failed request is retried -- an ACRS step-up or a token refresh -- fails only that request.
Run `Connect-OPIM`, or the command again, once the sign-in can succeed.

Azure signs in separately, through the Az module, for the same tenant as the Microsoft Graph
sign-in. An earlier Azure sign-in is reused only when it is for that tenant and the same account as
the Graph sign-in; otherwise Azure signs in again for that tenant. It never asks you to pick a
subscription: every Azure role command names its own scope. A failed Azure sign-in ends with
`AzureConnectFailed`, and the command then sends nothing to Azure under an earlier sign-in
(`SignInRefused`).

`pim` and `unpim` sign in to Microsoft Graph first; when that fails, the command stops before
anything is listed or changed. They then sign in to Azure, only when Azure roles are part of the
run; when that fails, the error is written and only the Azure roles are skipped -- unless
`$ErrorActionPreference` is `Stop` (or you pass `-ErrorAction Stop`), in which case the error ends
the command before any role or group is activated or deactivated.

On a machine without a browser -- a remote session, a container, a cloud PC -- sign in with a
device code instead. The command shows a short code and the address to open (Microsoft Entra
chooses it, for example `https://login.microsoft.com/device`); open it on any device, enter the code
and sign in.
With `-IncludeARM`, Azure shows a second code. The mode is remembered for the session: the refresh
stays silent while it can, and any later sign-in that needs a prompt uses a device code until
`Disconnect-OPIM`.

```powershell
Connect-OPIM -TenantId 'contoso.onmicrosoft.com' -DeviceCode
Connect-OPIM -TenantAlias corp -DeviceCode -IncludeARM
pim -TenantAlias corp -DeviceCode                     # Enable-OPIMMyRole and Disable-OPIMMyRole take it too
```

The message with the code goes to the Information stream with the tag `OPIMDeviceCode`. The code
Azure shows comes from `Connect-AzAccount` itself: Az.Accounts 5.5.3 writes it as an information
record, an older Az.Accounts as a warning. A script reads both as they arrive by merging the two
streams into a pipeline. Capturing the output in a variable instead (`$x = Connect-OPIM -DeviceCode 6>&1`)
shows nothing until the flow ends, which can take 15 minutes.

```powershell
Connect-OPIM -TenantAlias corp -DeviceCode -IncludeARM 6>&1 3>&1 | ForEach-Object { $PSItem.ToString() }
```

For Azure RBAC cmdlets (`Get-/Enable-/Disable-OPIMAzureRole`) an Azure Resource Manager token
is also needed. Pass `-IncludeARM` to `Connect-OPIM`, or the cmdlets will acquire it
automatically on first use.

To clear all cached tokens and disconnect:

```powershell
Disconnect-OPIM
```

---

## Quick Start

### Azure AD / Entra ID Directory Roles

```powershell
# Connect — browser prompt appears automatically on first use, or pre-authenticate explicitly
Connect-OPIM                                          # home tenant at the first sign-in
Connect-OPIM -TenantId 'contoso.onmicrosoft.com'     # specific tenant

# List eligible roles
Get-OPIMDirectoryRole

# List your active role activations (a permanent assignment is not listed)
Get-OPIMDirectoryRole -Activated

# List BOTH eligible and active in one call
Get-OPIMDirectoryRole -All

# Retrieve one role by display name (its eligible and its active post)
Get-OPIMDirectoryRole 'Usage Summary Reports Reader'

# Activate by display name -- tab completion offers the names (see "Naming a role or group" below)
Enable-OPIMDirectoryRole 'Usage Summary Reports Reader' -Justification 'Monthly report'
Enable-OPIMDirectoryRole <tab>

# A name that matches the role at more than one scope is refused (AmbiguousName); -Scope picks one
Enable-OPIMDirectoryRole 'User Administrator' -Scope '/'

# Activate using positional params: Role (pos 0), Justification (pos 1), Hours (pos 2)
Enable-OPIMDirectoryRole 'Global Administrator' 'Incident response' 4

# The tab-completed form, with the schedule ID in parentheses, still works
Enable-OPIMDirectoryRole 'Global Administrator (elig-id)' 'Incident response' 4

# Activate by schedule ID (from Get-OPIMDirectoryRole id property)
Enable-OPIMDirectoryRole -Identity 'elig-001'

# Activate all eligible roles for 4 hours with a justification
Get-OPIMDirectoryRole | Enable-OPIMDirectoryRole -Hours 4 -Justification 'Incident response'

# Deactivate by display name, or by schedule instance ID (from Get-OPIMDirectoryRole -Activated id property)
Disable-OPIMDirectoryRole 'Usage Summary Reports Reader'
Disable-OPIMDirectoryRole -Identity 'active-instance-001'

# Deactivate all active roles
Get-OPIMDirectoryRole -Activated | Disable-OPIMDirectoryRole

# Activate and wait for provisioning before continuing (up to -TimeoutSeconds per role, default 300)
Get-OPIMDirectoryRole | Enable-OPIMDirectoryRole -Wait
Enable-OPIMDirectoryRole 'Usage Summary Reports Reader' -Wait -TimeoutSeconds 600
```

### Azure Resource (RBAC) Roles

```powershell
# Connect — -IncludeARM also signs in to Azure, for the same tenant as Graph
Connect-OPIM -IncludeARM
Connect-OPIM -TenantId 'contoso.onmicrosoft.com' -IncludeARM

# List eligible roles (current user, all scopes)
Get-OPIMAzureRole

# List your active role activations (a permanent assignment is not listed)
Get-OPIMAzureRole -Activated

# List BOTH eligible and active in one call
Get-OPIMAzureRole -All

# List eligible roles at a specific subscription scope
Get-OPIMAzureRole -Scope '/subscriptions/00000000-...'

# List active roles at a specific scope (exact scope match only)
Get-OPIMAzureRole -Activated -Scope '/subscriptions/00000000-...'

# Retrieve a role by display name (its eligible and its active post), at one scope if it has several
Get-OPIMAzureRole 'Reader'
Get-OPIMAzureRole 'Reader' -Scope '/subscriptions/00000000-0000-0000-0000-000000000000'

# Activate by display name -- tab completion offers the names (see "Naming a role or group" below)
Enable-OPIMAzureRole 'Reader' -Scope '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app'
Enable-OPIMAzureRole <tab>

# Activate using positional params: Role (pos 0), Justification (pos 1), Hours (pos 2)
Enable-OPIMAzureRole 'Contributor' 'Incident response' 4

# The tab-completed form, with the schedule Name in parentheses, still works
Enable-OPIMAzureRole 'Contributor -> My Subscription (elig-name)' 'Incident response' 4

# Activate by schedule Name (the Name property from Get-OPIMAzureRole)
Enable-OPIMAzureRole -Identity 'elig-schedule-name'

# Schedule an activation: -NotBefore is sent to Azure as the start (a time without an offset is
# local time), and a start in the future is reported as a scheduled activation (ScheduleCreated)
Enable-OPIMAzureRole 'Reader' -Scope '/subscriptions/00000000-0000-0000-0000-000000000000' -NotBefore '4pm' -Until '6pm'

# Deactivate by display name, or by schedule instance Name (from Get-OPIMAzureRole -Activated)
Disable-OPIMAzureRole 'Reader' -Scope '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app'
Disable-OPIMAzureRole -Identity 'active-schedule-name'

# Deactivate all active roles
Get-OPIMAzureRole -Activated | Disable-OPIMAzureRole
```

### Entra ID PIM Groups

```powershell
# Connect — the same Connect-OPIM call covers directory roles, groups, and (with -IncludeARM) Azure
Connect-OPIM

# List eligible group memberships/ownerships
Get-OPIMEntraIDGroup

# List your active group activations (a permanent assignment is not listed)
Get-OPIMEntraIDGroup -Activated

# List BOTH eligible and active in one call
Get-OPIMEntraIDGroup -All

# Filter by access type
Get-OPIMEntraIDGroup -AccessType member

# Retrieve one group by display name (the membership; add -AccessType owner for the ownership)
Get-OPIMEntraIDGroup 'Finance Team'

# Activate by display name -- a group name means the membership; tab completion offers the names
Enable-OPIMEntraIDGroup 'Finance Team' -Justification 'Project work'
Enable-OPIMEntraIDGroup <tab>

# Activate the ownership instead
Enable-OPIMEntraIDGroup 'Finance Team' -AccessType Owner

# Activate using positional params: Group (pos 0), Justification (pos 1), Hours (pos 2)
Enable-OPIMEntraIDGroup 'Finance Team' 'Project work' 2

# The tab-completed form, with the schedule ID in parentheses, still works
Enable-OPIMEntraIDGroup 'Finance Team - member (elig-id)' 'Project work' 2

# Activate by schedule ID (from Get-OPIMEntraIDGroup id property)
Enable-OPIMEntraIDGroup -Identity 'elig-001'

# Activate all eligible group assignments
Get-OPIMEntraIDGroup | Enable-OPIMEntraIDGroup -Hours 2 -Justification 'Project work'

# Deactivate by display name (add -AccessType Owner for the ownership), or by schedule instance ID
Disable-OPIMEntraIDGroup 'Finance Team'
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

# Wait until directory role activations are fully provisioned (up to -TimeoutSeconds, default 300)
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

Each stored item is matched against every active role or group. An item that matches more than
one -- the same directory role active at two scopes, say -- is refused with `AmbiguousName`, which
lists the active posts it matches, and none of them is deactivated; the next item still runs.
Deactivate the one you mean with `Disable-OPIMDirectoryRole`, `Disable-OPIMEntraIDGroup` or
`Disable-OPIMAzureRole` and its tab-completed form, as listed. Only activations count as active:
a permanent assignment is never deactivated.

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
    # Alias 'corp' — activates only the stored directory role, at '/', and one group
    'corp' = @{
        TenantId       = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
        DirectoryRoles = @('e8611ab8-c189-46e8-94e1-60213ab1f814|/')   # roleDefinitionId|directoryScopeId
        EntraIDGroups  = @('00000000-0000-0000-0000-000000000006_member')  # groupId_accessId
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
| Directory Role | `"{roleDefinitionId}\|{directoryScopeId}"` | `"$($_.roleDefinitionId)\|$($_.directoryScopeId)"` |
| Entra ID Group | `"{groupId}_{accessId}"` | `"$($_.groupId)_$($_.accessId)"` |
| Azure Role | Schedule name | `$_.Name` |

These identifiers are stable across eligibility renewals. The `accessId` in the group key is
either `member` or `owner`, so you can store member and owner eligibility for the same group
independently.

A directory role is stored with its scope -- `/` for the whole directory, or
`/administrativeUnits/{id}` for an administrative unit -- and `pim` and `unpim` activate and
deactivate it only at that scope. An entry written by 0.5.x holds only the `roleDefinitionId` and
now means the role at the root scope `/` only. An older module version reading an entry with a
scope matches nothing for it: it activates and deactivates no directory role for that entry. Keys
are compared without regard to letter case, and each key is stored once.

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
Connect-OPIM -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

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

## Available Cmdlets

Every exported cmdlet is listed once below, grouped by the surface it works on, with the number
of cmdlets in each group. The groups are for orientation only. Run
`Get-Command -Module Omnicit.PIM` for the live list; the `PIM`-prefixed spellings of these names
are under [Short Aliases](#short-aliases).

### Directory roles (4)

- `Get-OPIMDirectoryRole` -- lists your eligible directory roles; `-Activated` lists your activations (a permanent assignment is not listed) and `-All` both; a role's display name as the first argument retrieves that role.
- `Enable-OPIMDirectoryRole` -- activates an eligible directory role named by its display name (or the tab-completed form), for 1 hour unless `-Hours` or `-Until` says otherwise; `-Scope` picks one when the name matches the role at more than one scope.
- `Disable-OPIMDirectoryRole` -- deactivates an active directory role named by its display name (or the tab-completed form); `-Scope` picks one when the name matches at more than one scope.
- `Wait-OPIMDirectoryRole` -- waits for each directory role activation request to finish provisioning, up to `-TimeoutSeconds` (default 300; the old `-Timeout` still works).

### Groups (3)

- `Get-OPIMEntraIDGroup` -- lists your eligible PIM for Groups assignments, membership and ownership; `-Activated` and `-All` work as above; a group's display name as the first argument retrieves its membership, or its ownership with `-AccessType owner`.
- `Enable-OPIMEntraIDGroup` -- activates an eligible group membership or ownership named by its display name (or the tab-completed form); a name means the membership unless `-AccessType Owner` is given.
- `Disable-OPIMEntraIDGroup` -- deactivates an active group membership or ownership named the same way; `-AccessType Owner` picks the ownership.

### Azure roles (3)

- `Get-OPIMAzureRole` -- lists your eligible Azure resource roles, at the root scope unless `-Scope` names another; `-Activated` and `-All` work as above; a role's display name as the first argument retrieves that role.
- `Enable-OPIMAzureRole` -- activates an eligible Azure resource role named by its display name (or the tab-completed form); `-Scope` picks one when the name matches the role at more than one scope.
- `Disable-OPIMAzureRole` -- deactivates an active Azure resource role named the same way; `-Scope` picks one when the name matches at more than one scope.

### Sign-in and configuration (8)

- `Connect-OPIM` (alias `Connect-PIM`) -- signs in to Microsoft Graph, and to Azure with `-IncludeARM`, in the system browser or with `-DeviceCode`; optional, since every cmdlet signs in on first use.
- `Disconnect-OPIM` (alias `Disconnect-PIM`) -- clears the cached tokens and disconnects from Microsoft Graph and Azure.
- `Install-OPIMConfiguration` -- creates a tenant alias in `TenantMap.psd1`.
- `Get-OPIMConfiguration` -- reads the tenant aliases in `TenantMap.psd1`.
- `Set-OPIMConfiguration` -- updates an existing tenant alias.
- `Remove-OPIMConfiguration` -- removes a tenant alias.
- `Enable-OPIMMyRole` (alias `pim`) -- connects with `Connect-OPIM`, then activates the roles and groups stored for a tenant alias in the tenant map, or every eligible one with an `-AllEligible` switch.
- `Disable-OPIMMyRole` (alias `unpim`) -- connects with `Connect-OPIM`, then deactivates the roles and groups stored for a tenant alias in the tenant map, or every active one with an `-AllActivated` switch.

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
| 0 | `-RoleName` / `-GroupName` | `'Global Administrator'` |
| 1 | `-Justification` | `'Incident response'` |
| 2 | `-Hours` | `4` |

```powershell
# Explicit
Enable-OPIMDirectoryRole -RoleName 'Global Administrator' -Justification 'Incident' -Hours 4

# Positional (identical result)
Enable-OPIMDirectoryRole 'Global Administrator' 'Incident' 4
```

---

## Naming a role or group

`-RoleName` / `-GroupName` (the first positional argument of every `Enable-OPIM*`, `Disable-OPIM*`
and `Get-OPIM*` role and group cmdlet) take the **display name** of the role or group, or the form
tab completion offers. Both work everywhere:

```powershell
Enable-OPIMDirectoryRole 'Usage Summary Reports Reader'               # display name
Enable-OPIMDirectoryRole 'Usage Summary Reports Reader (elig-001)'    # tab-completed form, with the schedule id
```

- A display name is compared exactly and without regard to letter case. There are no wildcards
  (`Reader [Preview]` is just a name), and spaces at either end are not trimmed.
- Tab completion offers the bare name whenever it is unique, and the longer form -- the name, the
  scope or access type, and the schedule id -- when it is not. A name that contains an apostrophe,
  straight or typographic, is completed with the apostrophe doubled, as PowerShell needs it.
- **A name that matches more than one role or group is never resolved by guessing.** The command
  writes `AmbiguousName`, lists the candidates and activates or deactivates nothing. For a role
  name, `-Scope` picks one on the cmdlets that have it (`Enable-`/`Disable-OPIMDirectoryRole`,
  `Enable-`/`Disable-OPIMAzureRole` and `Get-OPIMAzureRole`; on the `Enable-` and `Disable-` commands
  it does not combine with `-Identity`, on `Get-OPIMAzureRole` it does):
  `'/'` or an administrative unit (its `/administrativeUnits/` path or its display name) for a
  directory role, the ARM scope for an Azure role. The scope is compared without regard to letter
  case, means exactly that scope, and is refused when it ends in a slash (only the root scope is
  written `'/'`). On `Get-OPIMAzureRole`, `-Scope '/'` still means every scope; on
  `Enable-`/`Disable-OPIMAzureRole` it means a role at the root scope itself. Everywhere else, and
  for an ambiguous `-Identity`, give the tab-completed form of the one you mean.
- **A group name means the membership.** `-AccessType Owner` names the ownership instead; a group you
  hold only as owner is `EligibleRoleNotFound` (`ActiveRoleNotFound` on `Disable-`), and the message
  says to add `-AccessType Owner`. Two groups that share a display name are `AmbiguousName`;
  `-AccessType` does not separate them, so give the tab-completed form of the one you mean.
- A name that matches nothing is written as `EligibleRoleNotFound`, or `ActiveRoleNotFound` when
  deactivating (and for `Get-OPIM* -Activated`). Deactivating a role that is eligible but not
  active says so in the message (it is already deactivated, or its activation has not finished
  yet), and a name that is active under another key names the active form. These are ordinary
  non-terminating errors: the command is not stopped.
- `-RoleName` / `-GroupName` on the `Enable-` cmdlets take several names. Each is resolved on its
  own, so a name that is ambiguous or unknown is written as an error and the next one still runs;
  `-Scope` or `-AccessType` applies to every name in the list.

```powershell
Enable-OPIMDirectoryRole 'Usage Summary Reports Reader', 'Reports Reader' -Hours 4
Enable-OPIMEntraIDGroup 'Finance Team' -AccessType Owner
Enable-OPIMAzureRole 'Reader' -Scope '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app'
Get-OPIMAzureRole 'Reader' -Scope '/subscriptions/00000000-0000-0000-0000-000000000000'
```

---

## What a request reports

The `Enable-OPIM*` and `Disable-OPIM*` role and group cmdlets report a request by the status Graph or
Azure gives it. A request that failed, was denied or was canceled is an `ActivationRequestFailed`
error and returns nothing, and one that waits for approval or is still being provisioned is returned
with a warning, since it has not taken effect yet. A status the module does not know counts as a
failure, never as a success; a deactivation succeeds only when it ends `Revoked`.

The `Enable-OPIM*` cmdlets never request a role or group that is already active (listed by
`Get-OPIM* -Activated`, read once per command): they write a warning and send nothing for it, and
when that list cannot be read they write that error and send nothing. A role or group named or piped
twice in one command is requested once, with a warning for the second.

With `-Wait`, the `Enable-OPIM*` role and group cmdlets wait for at most `-TimeoutSeconds` (default
300) and then report the request by its last status, written back onto the request (a directory
role returns its role assignment once that appears). Groups and Azure roles read the status
again, with a pause between reads, only while the request is still being worked on, counting from
the start of the wait. Directory roles hand every request that has not failed to
`Wait-OPIMDirectoryRole`, which reads each one at least once, waits for the role assignment to
appear once a request is provisioned, and counts from the time Graph created the request. A
request that waits for approval ends the wait at once, with a warning. One still in progress at the
limit is an `ActivationWaitTimedOut` error and returns nothing; the request stays submitted. Each
role or group is reported on its own, so one that fails or times out never stops the next.

---

## Using -All, -Activated, and default (eligible only)

All `Get-OPIM*` cmdlets support three modes. `-All` and `-Activated` are mutually exclusive:

| Command | Returns |
|---|---|
| `Get-OPIMDirectoryRole` | Eligible (inactive) roles only |
| `Get-OPIMDirectoryRole -Activated` | Your activations: the currently active, time-bound role assignments. Permanent assignments are not listed |
| `Get-OPIMDirectoryRole -All` | Both eligible **and** active (activations only) for the current user |

The same applies to `Get-OPIMEntraIDGroup` and `Get-OPIMAzureRole`.

> **Note:** `-All` returns both schedule types **for the current user**. It does not list other
> users' roles. Both result types are returned with their correct TypeNames so Format views apply.
> A permanent assignment is no activation and cannot be deactivated by you, so it is listed in
> neither `-Activated` nor the active rows of `-All`.
>
> A directory role at an administrative unit that cannot be read is still listed, with the unit's id in
> place of its name, and a warning reports the error.

---

## Using -Identity for direct activation/deactivation

Every `Enable-OPIM*` and `Disable-OPIM*` cmdlet accepts `-Identity` to target a specific schedule
by ID instead of by name (see [Naming a role or group](#naming-a-role-or-group)). An id that matches
more than one schedule is refused with `AmbiguousName`, like a name, and nothing is activated or
deactivated:

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

Use `-Activated` on the `Get-OPIM*` cmdlets to see your activations: the currently active,
time-bound assignments. An always-on assignment is not listed.

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

