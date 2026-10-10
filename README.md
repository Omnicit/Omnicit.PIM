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

Omnicit.PIM needs PowerShell 7.4 or later (Core only). It declares two dependencies,
Microsoft.Graph.Authentication and AzAuth, which `Install-Module` installs with it; no Az PowerShell
module is needed.

```powershell
Install-Module Omnicit.PIM
Import-Module Omnicit.PIM
```

---

## Authentication

All `Get-/Enable-/Disable-OPIM*` cmdlets authenticate automatically on first use. The first
Microsoft Graph sign-in opens the system browser, or shows a device code with `-DeviceCode` (see
below); the token is cached via MSAL for the session, and later calls reuse it without a new prompt
while it can be refreshed silently. The Azure role cmdlets also need an Azure Resource Manager
sign-in of their own, through AzAuth, which prompts separately the first time (see below). You
never need to call `Connect-MgGraph` or any Az sign-in command manually.

`Connect-OPIM` is the module's optional pre-authentication command. Use it when you want the
sign-in prompt at a predictable time or need to target a specific tenant:

```powershell
Connect-OPIM                                          # home tenant at the first sign-in, then the session's tenant
Connect-OPIM -TenantId 'contoso.onmicrosoft.com'     # specific tenant
Connect-OPIM -TenantAlias corp                        # resolve alias from TenantMap.psd1
Connect-OPIM -IncludeARM                              # also sign in to Azure, for the same tenant
Connect-OPIM -TenantId 'contoso.onmicrosoft.us' -Environment USGov   # a US Government (GCC High) tenant
```

A session stays on the tenant it signed in to. A command that names no tenant keeps that tenant,
and every new token must be issued for it: a token for another tenant is refused with
`TenantMismatch`, and nothing is sent. To work in another tenant, run `Connect-OPIM -TenantId`
with it, or `Disconnect-OPIM` and sign in again. A session also stays in the cloud it signed in to
-- the global cloud unless `-Environment` said otherwise; see [Sovereign clouds](#sovereign-clouds).

The Microsoft Graph PowerShell SDK keeps one session per PowerShell process. If something else in
the same process runs `Connect-MgGraph` after Omnicit.PIM signed in, the role, group and sign-in
commands refuse to send their calls under that session (`GraphSessionChanged`) instead of
switching it back. Run `Disconnect-OPIM`, which also disconnects that other session, and sign in
again -- or use a new PowerShell window. The configuration commands do not sign in, and they take a
tenant only from Omnicit.PIM's own sign-in, never from a session started with `Connect-MgGraph`
outside the module: `Install-OPIMConfiguration` without `-TenantId` stores the tenant Omnicit.PIM is
signed in to, and without such a sign-in refuses with `TenantIdNotResolvable` and stores nothing.
`Set-OPIMConfiguration` keeps the tenant stored for the alias. Both show the tenant's display name
in the confirmation prompt only for the tenant they write, and only while Omnicit.PIM's own Graph
session is active; otherwise it reads `N/A`.

A command whose sign-in at its start was refused sends nothing more, even when it carries on past
the error: every request it would still make is refused with `SignInRefused`. A sign-in refused
while a failed request is retried -- an ACRS step-up or a token refresh -- fails only that request.
Run `Connect-OPIM`, or the command again, once the sign-in can succeed.

Azure signs in separately, through AzAuth's `Get-AzToken`, for the same tenant as the Microsoft
Graph sign-in. Its token must be issued for that tenant and for the account the Graph sign-in used:
a token for another tenant is refused with `TenantMismatch`, and one for another account with
`AccountMismatch`, before anything is sent. The token is reused only while it is for that tenant
and account and has more than 5 minutes left; otherwise Azure signs in again. Omnicit.PIM sends
every Azure request itself, with that token, so no Az context and no Az session are involved, and
it never asks you to pick a subscription: every Azure role command names its own scope. A failed
Azure sign-in ends with `AzureConnectFailed`, and the command then sends nothing to Azure under an
earlier sign-in (`SignInRefused`).

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

The message with the code goes to the Information stream with the tag `OPIMDeviceCode`. AzAuth
hands over the code Azure shows as a warning; Omnicit.PIM writes it on the Information stream
instead, with the same tag, so it shows even where warnings are silenced. A script reads both as
they arrive by merging the Information stream into a pipeline that only shows them. The sign-in
waits while that pipeline handles a message: a pipeline that also waits for the user, calls
Omnicit.PIM or waits for the sign-in to finish holds the sign-in up until it returns, and one that
waits for the sign-in never returns. Run the rest of the script after the command has returned.
Capturing the output in a variable instead (`$x = Connect-OPIM -DeviceCode 6>&1`) shows nothing
until the flow ends, which can take 15 minutes.

```powershell
Connect-OPIM -TenantAlias corp -DeviceCode -IncludeARM 6>&1 | ForEach-Object { Write-Host $PSItem.ToString() }
Get-OPIMAzureRole    # the rest of the script runs once the sign-in has returned
```

For Azure RBAC cmdlets (`Get-/Enable-/Disable-OPIMAzureRole`) an Azure Resource Manager token
is also needed. Pass `-IncludeARM` to `Connect-OPIM`, or the cmdlets will acquire it
automatically on first use.

`Disconnect-OPIM` clears the module's tokens, the Azure Resource Manager token included, and
disconnects the Microsoft Graph session; AzAuth keeps its own sign-in in the PowerShell process until
the module's next Azure sign-in rebuilds it or the process ends.

```powershell
Disconnect-OPIM
```

### Azure sign-in and AzAuth's credential

AzAuth keeps one credential per PowerShell process, and it is shared with any `Get-AzToken` call
you make yourself. Omnicit.PIM makes AzAuth rebuild it (AzAuth's `-Force`) on the first Azure
sign-in of a session -- also after `Disconnect-OPIM`, and after a token the module refused or
dropped -- so a credential left in the process by another sign-in is not reused for the first
token, and again on every forced refresh after Azure Resource Manager rejects a token.
Omnicit.PIM reuses its own Azure token, without asking AzAuth, only while it is for the session's
tenant and account and has more than 5 minutes left. Whatever AzAuth answers, every token is
checked against the tenant (`tid`) and the account (`oid`) of the Microsoft Graph session before
anything is sent with it.

`Disconnect-OPIM` cannot clear AzAuth's credential: it ends with the PowerShell process, or is
rebuilt at the module's next Azure sign-in. Omnicit.PIM creates, reads and ends no Az context, so an
Az PowerShell session you started yourself is left alone, and `Disconnect-OPIM` does not sign it
out.

---

## Sovereign clouds

Omnicit.PIM signs in to one of four clouds and sends every Microsoft Graph and Azure Resource
Manager request to it. `Connect-OPIM`, `Enable-OPIMMyRole` (`pim`) and `Disable-OPIMMyRole`
(`unpim`) take `-Environment` to choose the cloud, in any letter case, and `Install-` and
`Set-OPIMConfiguration` take it to store the cloud of a tenant alias. Without it nothing changes:
the cloud is `Global`, as it has always been.

| `-Environment` | Cloud | Sign-in authority | Microsoft Graph | Azure Resource Manager |
|---|---|---|---|---|
| `Global` (default) | The worldwide cloud, including Microsoft 365 GCC | `login.microsoftonline.com` | `graph.microsoft.com` | `management.azure.com` |
| `USGov` | US Government, GCC High | `login.microsoftonline.us` | `graph.microsoft.us` | `management.usgovcloudapi.net` |
| `USGovDoD` | US Government, DoD | `login.microsoftonline.us` | `dod-graph.microsoft.us` | `management.usgovcloudapi.net` |
| `China` | Operated by 21Vianet | `login.chinacloudapi.cn` | `microsoftgraph.chinacloudapi.cn` | `management.chinacloudapi.cn` |

Microsoft 365 GCC is a commercial-cloud tenant and is `Global`; `USGov` is GCC High. The other
environments the Microsoft Graph SDK names (`BleuCloud`, `DelosCloud` and `GovSGCloud`) are not
supported, and an unknown cloud is an error, never a fallback to `Global`.

```powershell
Connect-OPIM -TenantId 'contoso.onmicrosoft.us' -Environment USGov
Connect-OPIM -TenantId 'contoso.onmicrosoft.us' -Environment USGov -IncludeARM
pim -TenantAlias gov                                  # an alias that stores its cloud needs no -Environment
```

### What follows the cloud

The cloud decides three things, and the module reads each from one table:

- **The sign-in authority.** The Microsoft Graph token comes from MSAL, whose application is built for
  the authority of the cloud, and is handed to the Graph SDK connected to that cloud's environment.
  The Azure token comes from AzAuth, asked for the Azure Resource Manager of the cloud.
- **The Microsoft Graph host.** Every request, and every next page of a list, stays on it.
- **The Azure Resource Manager host.** Every Azure request is sent to it, and only to it.

The Microsoft Graph permissions that are requested are the same in every cloud.

### The cloud follows the tenant

A cloud is a property of the tenant, so a command without `-Environment` takes the cloud from the
tenant it is for. A command for the tenant the session is signed in to, or one that names no tenant,
keeps the session's cloud; a command for any other tenant uses `Global`. Naming another cloud signs
in again, also for the same tenant, and the Azure token of the old cloud is never reused or carried
into the new one. `-Environment Global` on a session that signed in without `-Environment` is the
same session, so it starts no new sign-in.

An organisation has a separate tenant, with its own ID, in each cloud. A session pinned by a tenant
ID -- which includes one whose first sign-in named no tenant, since it is then pinned to the ID of the
token it got -- is held to that ID. So `Connect-OPIM -Environment USGov` alone on such a session asks
the other cloud for a token for the same ID, and the switch fails: the other cloud most likely
refuses that ID before any token exists, and `TenantMismatch` comes only if a token for another
tenant does come back (untested live). Switch clouds by naming the tenant of the cloud you switch
to, or an alias that stores it:

```powershell
Connect-OPIM -TenantId 'contoso.onmicrosoft.us' -Environment USGov
Connect-OPIM -TenantAlias gov
```

### The cloud of a tenant alias

A tenant alias remembers its cloud in an optional `Environment` key of its `TenantMap.psd1` entry,
which is written only when the cloud is not `Global`. A file without the key means `Global`, so every
existing map keeps working.

```powershell
Install-OPIMConfiguration -TenantAlias gov -TenantId '00000000-0000-0000-0000-000000000000' -Environment USGov
Set-OPIMConfiguration -TenantAlias gov -Environment China   # change the cloud; -Environment Global removes it
Get-OPIMConfiguration -TenantAlias gov                      # shows Environment, Global when none is stored
```

- `Connect-OPIM -TenantAlias`, `pim -TenantAlias` and `unpim -TenantAlias` sign in to the cloud the
  alias stores -- `Global` for an alias that stores none, whatever cloud the session is in -- unless
  you pass `-Environment`, which wins.
- `Install-OPIMConfiguration` without `-Environment` gives the new alias the cloud of Omnicit.PIM's own
  sign-in when, and only when, the alias also takes that sign-in's tenant: no `-TenantId`, or the tenant
  ID that sign-in was issued for. The alias of any other tenant is `Global`, and `-Environment Global`
  stores no cloud, also for the tenant of a sovereign sign-in.
- `Set-OPIMConfiguration` without `-Environment` keeps the stored cloud as it is written, except a
  stored `Global`, which means the same as none and is dropped.
- A cloud in the file that the module does not know, a hand-typed `Environment = 'Germany'` say, is an
  error, and nothing is signed in. The letter case of a known cloud does not matter.

A 0.6.x module, and the 0.7.0 previews before this one, ignore the stored cloud and sign in to the
global cloud, where a sovereign tenant does not exist, so the sign-in fails. They also write the file
without the key whenever they change it (`Install-`, `Set-` or `Remove-OPIMConfiguration`), so a map
shared with a 0.6.x module, or with one of those previews, loses its clouds.

### Azure and AZURE_AUTHORITY_HOST

AzAuth's `Get-AzToken` has no authority parameter. The library under it, Azure.Identity, reads the
`AZURE_AUTHORITY_HOST` environment variable when AzAuth builds its credential. For a sovereign cloud
Omnicit.PIM sets the variable to the cloud's sign-in authority only around the Azure sign-in, and puts
it back afterwards on every path, a failed sign-in included: a value you had set is restored exactly,
and a variable that was not set is removed again. For `Global` the module writes nothing; if you have
set the variable to another authority yourself, the Azure sign-in follows it and the module warns. The
variable is process-wide, so an Azure sign-in that another thread of the same PowerShell process
starts during a sovereign sign-in reads it too. AzAuth keeps one credential per process; on a switch of
cloud, Omnicit.PIM makes it rebuild the credential (`-Force`).

### Which clouds are tested live

Only `Global` is verified live. `USGov`, `USGovDoD` and `China` are covered by unit tests only, which
mock every sign-in and request and pin the hosts in the table above; they are untested live, so treat
the first sign-in to one of them as a test of its own.

`China` has a second, unverified risk. Microsoft Learn ("Authentication module cmdlets in Microsoft
Graph PowerShell") says that globally registered apps do not replicate to Azure China, and that you
must register your own application there and use it to connect to Microsoft Graph. Omnicit.PIM signs in
to Microsoft Graph with the Microsoft Graph Command Line Tools public client, a globally registered
app, so a `China` sign-in may fail until the module can take an application of the tenant's own. It
cannot today, and this has not been tried.

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

# Activate the ownership instead -- only of a group that has another owner. If you are the group's
# only owner, PIM for Groups refuses to deactivate the ownership (CannotDeleteLastAdminAssignment)
# and it does not end at its end time; adding a service principal as a direct owner of the group
# did not change this in testing
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

Both commands reuse an existing sign-in: after `Connect-OPIM` or any role or group cmdlet, they
start no new Microsoft Graph sign-in for the same tenant while its token can still be used or
refreshed silently. When Azure roles are part of the run, Azure needs its own sign-in, which is
reused only when it was already made for the same tenant and account (`Connect-OPIM -IncludeARM`,
or an earlier Azure role cmdlet). With `-DeviceCode`, a sign-in that needs a prompt shows a
device code instead of opening the browser -- one for Microsoft Graph and, when Azure signs in, a
second one for Azure. `-Environment` (`Global`, `USGov`, `USGovDoD` or `China`) is handed to both
sign-ins; without it, `-TenantAlias` signs in to the cloud the alias stores, and the `-All*` forms
keep the session's cloud (see [Sovereign clouds](#sovereign-clouds)).

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

# A tenant alias signs in to the cloud it stores (see Sovereign clouds); -Environment overrides it
pim -TenantAlias gov
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

# Deactivate in the cloud a tenant alias stores (see Sovereign clouds)
unpim -TenantAlias gov
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
| `Set-OPIMConfiguration` | `Set-PIMConfig` | **Update** — change TenantId or the cloud, or replace stored role lists. |
| `Remove-OPIMConfiguration` | `Remove-PIMConfig` | **Delete** — remove an alias, preserve the rest. |

### Install-OPIMConfiguration — create a new alias

```powershell
# Register a new tenant alias
Install-OPIMConfiguration -TenantAlias contoso -TenantId '00000000-0000-0000-0000-000000000000'

# Register and store specific directory roles as the default activation set
Get-OPIMDirectoryRole | Where-Object { $_.roleDefinition.displayName -like 'Compliance*' } |
    Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>'

# Register an alias together with its cloud (stored only when it is not Global)
Install-OPIMConfiguration -TenantAlias gov -TenantId '<guid>' -Environment USGov

# Preview without writing
Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>' -WhatIf
```

> **Install is create-only.** If the alias already exists a non-terminating error is emitted.
> Use `Set-OPIMConfiguration` to update an existing alias.

### Get-OPIMConfiguration — read current configuration

```powershell
# List all tenant aliases
Get-OPIMConfiguration

# Inspect a specific alias (TenantAlias, TenantId, Environment and the stored lists)
Get-OPIMConfiguration -TenantAlias contoso

# Use a custom file path
Get-OPIMConfiguration -TenantMapPath 'D:\config\MyTenants.psd1'
```

### Set-OPIMConfiguration — update an existing alias

```powershell
# Update only the TenantId, preserve stored role lists
Set-OPIMConfiguration -TenantAlias contoso -TenantId '<new-guid>'

# Store the cloud of the alias, or remove it again with -Environment Global (role lists are preserved)
Set-OPIMConfiguration -TenantAlias contoso -Environment USGov
Set-OPIMConfiguration -TenantAlias contoso -Environment Global

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
$HOME/.config/Omnicit.PIM/TenantMap.psd1
```

On Windows `$HOME` is your user profile, so this is the file where it has always been,
`$env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1`. On Linux and macOS it sits under your home
folder, where `$env:USERPROFILE` does not exist. Every cmdlet that reads the map takes
`-TenantMapPath` to use another file.

### File format

Each entry is a nested hashtable under the alias key. The only required field is `TenantId`.
`Environment` is optional too: the cloud of the tenant (`Global`, `USGov`, `USGovDoD` or `China`),
written by `Install-` and `Set-OPIMConfiguration` only when it is not `Global`; without it the alias
signs in to the global cloud (see [Sovereign clouds](#sovereign-clouds)).
The role/group arrays are optional, and `pim` and `unpim` act only on what they list: a category
whose array is missing is skipped, with a verbose message, so an entry with no arrays activates
**nothing**. To activate everything eligible, use the `-AllEligible*` switches of `pim`
(`Enable-OPIMMyRole`) instead. The exception is an alias written in the old string form,
`'alias' = '<tenant id>'`: `pim` activates everything eligible for it and `unpim` deactivates
everything active, until `Set-OPIMConfiguration` rewrites it in the table form.

```powershell
@{
    # Alias 'corp' — activates only the stored directory role, at '/', and one group
    'corp' = @{
        TenantId       = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
        DirectoryRoles = @('e8611ab8-c189-46e8-94e1-60213ab1f814|/')   # roleDefinitionId|directoryScopeId
        EntraIDGroups  = @('00000000-0000-0000-0000-000000000006_member')  # groupId_accessId
        AzureRoles     = @('schedule-name-from-get-opimazurerole')
    }
    # Alias 'partner' -- no role lists: pim and unpim skip every category (nothing is activated)
    'partner' = @{
        TenantId = 'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy'
    }
    # Alias 'gov' -- a GCC High tenant: Connect-OPIM, pim and unpim sign in to the USGov cloud for it
    'gov' = @{
        TenantId    = 'zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz'
        Environment = 'USGov'
    }
}
```

The file is safe to edit manually — it is standard PowerShell data file syntax.

### Key identifiers stored per type

| Type | Stored value | Field on Get-OPIM* object |
|---|---|---|
| Directory Role | `"{roleDefinitionId}\|{directoryScopeId}"` | `"$($_.roleDefinitionId)\|$($_.directoryScopeId)"` |
| Entra ID Group | `"{groupId}_{accessId}"` | `"$($_.groupId)_$($_.accessId)"` |
| Azure Role | Eligibility schedule name; for an active role, `"{name}\|{ScopeId}"` | `$_.Name`; for an active role from `-Activated`, the eligibility it was activated from (the last segment of `$_.LinkedRoleEligibilityScheduleId`) and the role's own `$_.ScopeId` |

These identifiers are stable across eligibility renewals. The `accessId` in the group key is
either `member` or `owner`, so you can store member and owner eligibility for the same group
independently.

A directory role is stored with its scope -- `/` for the whole directory, or
`/administrativeUnits/{id}` for an administrative unit -- and `pim` and `unpim` activate and
deactivate it only at that scope. An entry written by 0.5.x holds only the `roleDefinitionId` and
now means the role at the root scope `/` only; for a role eligible only below the root, pipe all
the directory roles the alias should hold to `Set-OPIMConfiguration` again, which stores them with
their scopes (Set replaces the alias's whole `DirectoryRoles` list). An older module version (0.5.x) reading
an entry with a scope matches nothing for it: it activates and deactivates no directory role, and
no Azure role stored from `-Activated`, for that entry. Keys are compared without regard to letter
case, and each key is stored once.

### Creating and managing entries

```powershell
# Add a new tenant alias with no role lists yet (pim activates nothing for it until you add some)
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
default set. `-TenantAlias` is required. `-TenantId` is optional on `Install-OPIMConfiguration`:
without it the tenant Omnicit.PIM is signed in to is stored, and without such a sign-in nothing is
stored (`TenantIdNotResolvable`). The file written is the default tenant map unless
`-TenantMapPath` names another.

An active Azure role is stored as the eligibility it was activated from plus its own scope
(`{name}|{ScopeId}`), and `pim` and `unpim` act on it only while that eligibility is at that
scope. One activated at another scope than its eligibility (a narrower scope chosen when it was
activated) never stands for the wider eligibility: when Azure names the eligibility's scope, it is
refused with the error `LinkedEligibilityNotFound` and not stored, and otherwise the stored entry
matches no eligible role, so `pim` activates nothing for it. An active Azure role that names no
eligibility is refused the same way. To activate the eligibility at its own scope, pipe the
eligible role from `Get-OPIMAzureRole` instead. The other piped objects are still stored.

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

# Store your currently active Azure roles as the eligibilities they were activated from, each
# with its own scope (a role activated at a narrower scope than its eligibility is refused, or
# stored as an entry that activates nothing)
Get-OPIMAzureRole -Activated |
    Install-OPIMConfiguration -TenantAlias fabrikam -TenantId '<guid>'

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

# Activate everything eligible in the partner tenant (it has no stored role lists, so use the
# -AllEligible switch; an alias without role lists activates nothing)
Connect-OPIM -TenantAlias partner
pim -AllEligible -Hours 2 -Justification 'Partner review'
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

- `Connect-OPIM` (alias `Connect-PIM`) -- signs in to Microsoft Graph, and to Azure with `-IncludeARM`, in the system browser or with `-DeviceCode`, and in a sovereign cloud with `-Environment`; optional, since every cmdlet signs in on first use.
- `Disconnect-OPIM` (alias `Disconnect-PIM`) -- clears the module's tokens, the Azure Resource Manager token included, and disconnects the Microsoft Graph session; AzAuth keeps its own sign-in in the PowerShell process until the module's next Azure sign-in rebuilds it or the process ends.
- `Install-OPIMConfiguration` -- creates a tenant alias in `TenantMap.psd1`, with its cloud when you pass `-Environment`.
- `Get-OPIMConfiguration` -- reads the tenant aliases in `TenantMap.psd1`.
- `Set-OPIMConfiguration` -- updates an existing tenant alias, its cloud (`-Environment`) included.
- `Remove-OPIMConfiguration` -- removes a tenant alias.
- `Enable-OPIMMyRole` (alias `pim`) -- connects with `Connect-OPIM`, then activates the roles and groups stored for a tenant alias in the tenant map, or every eligible one with an `-AllEligible` switch; an alias signs in to the cloud it stores, and `-Environment` names another.
- `Disable-OPIMMyRole` (alias `unpim`) -- connects with `Connect-OPIM`, then deactivates the roles and groups stored for a tenant alias in the tenant map, or every active one with an `-AllActivated` switch; an alias signs in to the cloud it stores, and `-Environment` names another.

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
300) and then report the request by its last status. For a directory role or a group that status is
written back onto the request (a directory role returns its role assignment once that appears); an
Azure role returns the request as Azure last gave it, which already carries that status. Groups and
Azure roles read the status again, with a pause between reads, only while the request is still being
worked on, counting from the start of the wait. Directory roles hand every request that has not
failed to `Wait-OPIMDirectoryRole`, which reads each one at least once, waits for the role
assignment to appear once a request is provisioned, and counts from the time Graph created the
request. A request that waits for approval ends the wait at once, with a warning. One still in
progress at the limit is an `ActivationWaitTimedOut` error and returns nothing; the request stays
submitted. Each role or group is reported on its own, so one that fails or times out never stops the
next.

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
| PowerShell 7.4 or later | Core only; AzAuth 2.9.0 requires 7.4 |
| `Microsoft.Graph.Authentication` 2.36.0+ | Directory roles and Entra ID group PIM (raw `Invoke-MgGraphRequest`), and the Microsoft Graph sign-in |
| `AzAuth` 2.9.0+ | The Azure Resource Manager sign-in (`Get-AzToken`) |

No Az PowerShell module is required or loaded; the module sends every Azure Resource Manager
request itself.

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

