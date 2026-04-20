# Omnicit.PIM Copilot Instructions

## Branch Policy — ALWAYS CHECK FIRST

**Before making any code change, Copilot must:**

1. Determine the current branch (`git branch --show-current`).
2. If the current branch is `main` (or any other protected/shared branch), **stop and ask the user** whether to:
   - Create a new branch — propose a name based on the change (e.g. `fix/acrs-bearer-token-leak`, `feat/add-azure-role-filter`, `chore/update-tests`).
   - Continue on the current branch (explicit user consent required).
3. Only proceed after the user has confirmed the target branch.
4. If a new branch is requested, create it with `git checkout -b <branch-name>` before touching any files.

**Branch naming convention:**

| Change type | Prefix | Example |
|---|---|---|
| Bug fix | `fix/` | `fix/acrs-bearer-token-leak` |
| New feature | `feat/` | `feat/enable-myroleset-parallel` |
| Tests / QA | `test/` | `test/fix-completer-mocks` |
| Docs / chore | `chore/` | `chore/update-readme` |
| Refactor | `refactor/` | `refactor/simplify-error-handling` |

---

## Project Overview

**Omnicit.PIM** is a PowerShell 7.2+ (Core-only) module for Azure Privileged Identity Management (PIM) self-activation across three pillars:
- **Directory Roles** — Entra ID / Azure AD roles (via Microsoft Graph)
- **Azure RBAC Roles** — Azure resource roles (via `Az.Resources`)
- **Entra ID Groups** — PIM for Groups (via Microsoft Graph)

Original author: Justin Grote (@justinwgrote); overhauled by Omnicit.

## Module Layout

```
Source/
  Omnicit.PIM.psd1          # Manifest — source of truth for exports, aliases, required modules
  Omnicit.PIM.psm1          # Loader: Classes → Private → Public (this order is intentional)
  Classes/                  # Argument completers (IArgumentCompleter). Loaded FIRST.
  Private/                  # Internal helpers (not exported)
  Public/                   # Exported cmdlets — one file per function, filename == function name
  Formats/                  # *.Types.ps1xml and *.Format.ps1xml output formatters
```

## Build and Test

```powershell
# Bootstrap build dependencies (first time only)
./build.ps1 -ResolveDependency -Tasks noop

# Build the module (Clean → Build → Changelog)
./build.ps1

# Run Pester tests + PSScriptAnalyzer (80% coverage threshold)
./build.ps1 -AutoRestore -Tasks test

# Build + package as NuGet
./build.ps1 -Tasks pack

# Import from source for local development
Import-Module ./Source/Omnicit.PIM.psd1 -Force
```

Build output lands in `output/module/<version>/`. Uses **Sampler** + **ModuleBuilder** orchestration via `build.yaml`.

## Code Style

- **PSScriptAnalyzer** runs in CI — all rules, no suppressions.
- One function per file; filename must equal function name.
- `[CmdletBinding(SupportsShouldProcess)]` on every Enable/Disable function.
- Use `$PSCmdlet` for `ShouldProcess` calls, not `$PSCmdlet.ShouldContinue`.
- **PascalCase for all variables** — `$Response`, `$Request`, `$FakeRole`, `$ScheduleId`. Exceptions: automatic variables (`$PSCmdlet`, `$PSItem`, `$_`), preference variables (`$ErrorActionPreference`), boolean/null literals (`$null`, `$true`, `$false`), and the module-scope cache (`$script:_MyIDCache`).
- **`[OutputType([PSCustomObject])]`** on every function that returns type-tagged objects. Do not use `[OutputType([System.Collections.Hashtable])]`.

## Naming & Command Conventions

| Concept | Pattern | Example |
|---|---|---|
| Canonical function prefix | `OPIM` | `Get-OPIMDirectoryRole` |
| Canonical short aliases | `PIM` | `Get-PIMRole`, `Get-PIMADRole` |
| Directory Role noun | `DirectoryRole` | `Enable-OPIMDirectoryRole` |
| Azure RBAC noun | `AzureRole` | `Enable-OPIMAzureRole` |
| PIM Groups noun | `EntraIDGroup` | `Enable-OPIMEntraIDGroup` |
| Configuration CRUD | `*-OPIMConfiguration` | `Get/Set/Remove/Install-OPIMConfiguration` |
| Filename | `Verb-OPIMNoun.ps1` | `Disable-OPIMDirectoryRole.ps1` |

### Configuration CRUD

`Install-OPIMConfiguration` is **create-only** — it emits a non-terminating error if the alias already exists and directs the user to `Set-OPIMConfiguration`. The four configuration commands follow a strict CRUD model:

| Cmdlet | Operation | Notes |
|---|---|---|
| `Install-OPIMConfiguration` | Create | Mandatory `-TenantAlias`, `-TenantId`; accepts pipeline from `Get-OPIM*`. Error if alias exists. |
| `Get-OPIMConfiguration` | Read | Optional `-TenantAlias` filter. Returns `Omnicit.PIM.TenantConfiguration` objects. |
| `Set-OPIMConfiguration` | Update | Mandatory `-TenantAlias`; optional `-TenantId`; accepts pipeline from `Get-OPIM*`. Error if alias missing. |
| `Remove-OPIMConfiguration` | Delete | Mandatory `-TenantAlias`. Error if alias or file missing. |

The private helper `Export-OPIMTenantMap` (`Source/Private/`) owns PSD1 serialization and is called by `Install`, `Set`, and `Remove`. Do not duplicate the StringBuilder serialization block in any new function — call the helper instead.

- **Never use `*` in `FunctionsToExport`** — always list explicitly.
- **Aliases** must be registered in both `Omnicit.PIM.psm1` (alias map) and `AliasesToExport` in the manifest.

## API Mapping (important — terminology differs from PIM UI)

### Directory Roles (Graph)
| Graph resource | PIM concept |
|---|---|
| `roleEligibilitySchedules` | Roles eligible to activate (inactive) |
| `roleAssignmentScheduleInstances` | Currently active role assignments |
| `roleAssignmentScheduleRequests` | Activate (`SelfActivate`) or deactivate (`SelfDeactivate`) |

For `SelfDeactivate` supply the `roleAssignmentScheduleInstance` ID, **not** the schedule ID.

### Azure RBAC (Az.Resources)
| Cmdlet | PIM concept |
|---|---|
| `Get-AzRoleEligibilitySchedule` | Eligible (inactive) RBAC roles |
| `Get-AzRoleAssignmentScheduleInstance` | Active RBAC assignments |
| `New-AzRoleAssignmentScheduleRequest` | Activate or deactivate |

### PIM for Groups (Graph — `identityGovernance/privilegedAccess/group/`)
| Graph resource | PIM concept |
|---|---|
| `eligibilitySchedules` | Eligible (inactive) group assignments |
| `assignmentScheduleInstances` | Active group assignments |
| `assignmentScheduleRequests` | `selfActivate` / `selfDeactivate` |

`accessId` is `member` or `owner`.

## Standard Parameter Patterns

### Enable-OPIM* (activation)
- `-RoleName` / `-GroupName` — tab-completable; backed by IArgumentCompleter class in `Classes/`
- `-Hours` [int] — default 1; users can override via `$PSDefaultParameterValues`
- `-Until` [DateTime] — explicit end time; takes precedence over `-Hours`
- `-NotBefore` [DateTime] — activation start (default: now)
- `-Justification`, `-TicketNumber`, `-TicketSystem` — optional PIM policy fields
- `-Wait` [switch] — poll until provisioned (Directory Roles only)
- Always support `-WhatIf`/`-Confirm` via `[CmdletBinding(SupportsShouldProcess)]`

### Disable-OPIM* (deactivation)
- `-RoleName` / `-GroupName` — tab-completable to *active* roles
- Always support `-WhatIf`/`-Confirm`

### Get-OPIM*
- `-All` [switch] — list all principals (requires elevated permissions)
- `-Activated` [switch] — show only active assignments
- `-Identity` [string] — retrieve by schedule ID
- `-Filter` [string] — pass-through OData filter

## Error Handling

- All Graph API errors go through `Convert-GraphHttpException` in `Private/` — converts raw HTTP exceptions to typed PowerShell `ErrorRecord` objects with parsed `error.code` and `error.message`.
- **Security: `$Error.Remove()` is mandatory in every Graph `catch` block** — call `$null = $Error.Remove($PSItem)` as the **first** statement in every `catch` that handles a Graph API exception. The raw `HttpRequestMessage` in `$Error` contains the `Authorization: Bearer <token>` header in plain text. Failing to remove it leaks the bearer token to anyone inspecting `$Error`.
- **All functions emit non-terminating errors** via `$PSCmdlet.WriteError()`. Never use bare `throw` in public functions — it terminates the pipeline and prevents `-ErrorAction SilentlyContinue` from working. After `WriteError`, exit with `return` (in `process`) or `continue` (inside a `foreach` loop over multiple roles).
- Use `Write-CmdletError` (private) to emit non-terminating errors consistently from private helpers.
- Special error codes to handle: `InsufficientPermissions` (suggest `-All` is required), `ActiveDurationTooShort` (5-min cooldown between activate/deactivate).
- **`ErrorDetails` must be set via `[System.Management.Automation.ErrorDetails]::new('message')`**, not via plain string assignment. Plain string assignment is accepted by PowerShell but the type is incorrect.
- **Error flow in `foreach` loops** (Enable-* with multiple roles) — use `continue` to skip the failed role and proceed to the next:
  ```powershell
  foreach ($Role in $ResolvedRoles) {
      ...
      try { ... } catch {
          $PSCmdlet.WriteError($Err)
          continue   # <-- not return; try next role
      }
  }
  ```
- **Error flow in `process` blocks** (single-item Disable-*, Get-*) — use `return` to exit the current pipeline object:
  ```powershell
  process {
      try { ... } catch {
          $PSCmdlet.WriteError($Err)
          return   # <-- not continue
      }
  }
  ```
- **Graph vs Az.Resources error patterns are different by design** — Graph errors arrive as `HttpRequestException` and must go through `Convert-GraphHttpException`. Az.Resources errors arrive through `$PSItem` from `catch` blocks and are passed directly to `$PSCmdlet.WriteError()` after inspecting `$PSItem.FullyQualifiedErrorId`.

## Key Implementation Details

- **Duration formatting** — Use `[System.Xml.XmlConvert]::ToString([timespan]...)` for ISO 8601 durations required by PIM APIs, e.g. `PT1H`.
- **Current user ID** — Use `Get-MyId` (private) which caches the result in `$SCRIPT:_MyIDCache`.
- **ACRS claims-challenge retry** — `Invoke-GraphWithAcrsRetry` (private) wraps `Invoke-MgGraphRequest` POST calls for PIM activation. When the Graph API returns `RoleAssignmentRequestAcrsValidationFailed`, it extracts the claims JSON, acquires a new token via MSAL `AcquireTokenInteractive` with `WithClaims` (using reflection — MSAL types live in a separate Assembly Load Context), and retries with `Invoke-RestMethod`. On success it returns the response hashtable; on failure it returns a hashtable with `_AcrsError = $true` and diagnostic keys (`_ErrorRecord`, `_AllMsgs`, `_NoClaimsExtracted`, `_NoMsal`, etc.) for the caller to inspect. Callers (`Enable-OPIMDirectoryRole`, `Enable-OPIMEntraIDGroup`) check `$Result.ContainsKey('_AcrsError')` to distinguish success from error. **Do not mock `Invoke-MgGraphRequest` when testing ACRS error paths** — mock `Invoke-GraphWithAcrsRetry` directly to avoid triggering the real MSAL reflection code.
- **Tab completers** — Return strings in a format that includes the schedule ID in trailing parentheses. Format differs by pillar:
  - Directory roles: `'DisplayName -> ScopeName (id)'` (scope omitted for root `/`)
  - Azure RBAC roles: `'RoleName -> ScopeDisplayName (Name)'` (ID is `.Name`, not `.id`)
  - PIM Groups: `'GroupName - accessId (id)'` (dash separator, not arrow)
  `Resolve-RoleByName` (private) parses the trailing `(id)` back to find the schedule object. The ID property differs: Directory/Groups use `.id`, Azure uses `.Name`.
- **Parallel polling** — `Wait-OPIMDirectoryRole` uses `ForEach-Object -AsJob -Parallel` with `ConcurrentDictionary` for concurrent multi-role waiting.
- **directoryScopeId expand workaround** — Graph v1.0 cannot `$expand=directoryScope` in the same query; `Restore-GraphProperty` makes a second request to rehydrate scope display names.
- **Format/Type loading** — All format and type definitions are consolidated into two files in `Source/Formats/`: `Omnicit.PIM.Format.ps1xml` (loaded via `FormatsToProcess` in the manifest) and `Omnicit.PIM.Types.ps1xml` (loaded via a single `Update-TypeData -AppendPath` call in `suffix.ps1`). `TypesToProcess` is not used because `Remove-Module` does not clean type data, causing "member already present" errors on `Import-Module -Force`.

## Checklist: Adding a New Function

1. Create `Source/Public/Verb-OPIMNoun.ps1` — function name must match file name.
2. Add to `FunctionsToExport` in `Omnicit.PIM.psd1`.
3. If tab completion is needed, add an `IArgumentCompleter` class in `Source/Classes/`.
4. Add a `<View>` element to `Source/Formats/Omnicit.PIM.Format.ps1xml` and, if the type needs ScriptProperty members, a `<Type>` element to `Source/Formats/Omnicit.PIM.Types.ps1xml`.
5. Declare aliases via the `[Alias()]` attribute on the function. The source-mode psm1 uses `Export-ModuleMember -Function $PublicFunctions -Alias *` to export them. The build process (ModuleBuilder) populates `AliasesToExport` in the manifest from the `[Alias()]` attributes automatically.

## Dependencies

| Module | Version | Used for |
|---|---|---|
| `Az.Resources` | ≥ 9.0.3 | Azure RBAC PIM (`Get/Enable/Disable-OPIMAzureRole`) |
| `Microsoft.Graph.Authentication` | ≥ 2.36.0 | All Graph calls via `Invoke-MgGraphRequest` |

**Do not add other `Microsoft.Graph.*` SDK modules** — the module intentionally uses raw `Invoke-MgGraphRequest` to avoid typed SDK coupling and SDK version drift.

## Running the Module Locally

See [README.md](../README.md) for full usage examples, connection scopes, `Install-OPIMConfiguration`, and `TenantMap` shortcuts.

## Common Pitfalls

- **`DefaultCommandPrefix` is absent** — the manifest does NOT use `DefaultCommandPrefix = 'OPIM'`. Function names carry the prefix explicitly. Adding it would double-prefix to `OPIM-OPIMFoo`.
- **`Write-CmdletError -Message` expects `[Exception]`**, not a string. Wrap bare strings: `[System.Exception]::new('message')`.
- **Output tagging is required** — never return raw `Invoke-MgGraphRequest` hashtables (the default `Key/Value` formatter applies). Always convert to `[PSCustomObject]` and tag:
  ```powershell
  $Out = [PSCustomObject]$Response
  $Out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.SomeTypeName')
  ```
  The type name must have a matching `<View>` in `Source/Formats/Omnicit.PIM.Format.ps1xml` and, if it needs ScriptProperty members, a `<Type>` entry in `Source/Formats/Omnicit.PIM.Types.ps1xml`.
- **`FormatsToProcess` is active; `TypesToProcess` is disabled** — Formats are loaded natively via the manifest. Types are loaded via a single `Update-TypeData -AppendPath` call in `suffix.ps1` with `-ErrorAction SilentlyContinue` to handle `Import-Module -Force` re-imports.
- **Parallel runspaces require explicit Graph import** — `Wait-OPIMDirectoryRole` calls `Import-Module 'Microsoft.Graph.Authentication'` inside `ForEach-Object -Parallel`. Any new parallel block must do the same.
- **`Invoke-MgGraphRequest` must always use `-Verbose:$false -ErrorAction Stop`** — suppresses SDK noise and ensures exceptions are catchable. This applies to ALL calls including secondary rehydration calls.
- **`ErrorRecord.ErrorDetails` requires `[ErrorDetails]::new()`** — `$Err.ErrorDetails = 'plain string'` is silently ignored in some PowerShell versions. Always use:
  ```powershell
  $Err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('Your message here.')
  ```
- **Never use bare `throw` in public functions** — always emit via `$PSCmdlet.WriteError()` followed by `return` or `continue`. `throw` terminates the pipeline and bypasses `-ErrorAction SilentlyContinue`.
- **Local variable `$Filter` shadows the `-Filter` parameter** — in functions that have a `-Filter` parameter and also build an internal OData filter string, name the local variable `$OdataFilter` to avoid the collision.
- **`Az.Resources` manifest version is the source of truth** — the required version is `9.0.3`, not the older `5.6.0` sometimes cited in older docs.
- **PowerShell 7.2+ Core only** — `CompatiblePSEditions = @('Core')`. Do not suggest Windows PowerShell 5.x or Desktop-compatible code.
- **`Install-OPIMConfiguration` is create-only** — it does NOT have a `-Force` parameter. Updating an existing alias is done via `Set-OPIMConfiguration`. Do not add `-Force` back.
- **`Export-OPIMTenantMap` (private) owns PSD1 serialization** — always call this helper from `Install`, `Set`, and `Remove` instead of inlining the StringBuilder block.
- **Mocking functions called from `.NET` classes (`IArgumentCompleter`)** — Pester's `InModuleScope { Mock ... }` does NOT intercept calls made from class methods because .NET class method bodies are bound to the module's runspace at class-load time, not the Pester mock scope. The completer classes work around this by calling `Get-OPIM*` via `& ([scriptblock]::Create('Get-OPIMDirectoryRole'))` instead of a direct function call — `[scriptblock]::Create()` forces command resolution through the normal pipeline where Pester can intercept. **Do not revert this to a direct call** or mocks will break. Always use `Mock -ModuleName Omnicit.PIM FunctionName { ... }` at the outer `It` / `Context` level when testing completer classes. Class types defined in a module are NOT accessible in the outer test scope (calling `[ClassName]::new()` outside `InModuleScope` raises "Unable to find type"). Use `InModuleScope` for class instantiation, method calls, and assertions — use `Mock -ModuleName` (outside `InModuleScope`) for mocking. Correct pattern:
  ```powershell
  It 'test' {
      Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return $fakeData }
      InModuleScope Omnicit.PIM {
          $Completer = [DirectoryEligibleRoleCompleter]::new()
          $Result = $Completer.CompleteArgument('Enable-OPIMDirectoryRole', 'RoleName', '', $null, @{})
          $Result | Should -Not -BeNullOrEmpty
      }
  }
  ```
