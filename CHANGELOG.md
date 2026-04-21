# Changelog for Omnicit.PIM

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Get-OPIMCurrentTenantInfo` private helper — resolves the current tenant GUID and display name from the active Graph session. Used by `Install-`, `Set-`, and `Remove-OPIMConfiguration` to enrich the confirmation prompt.
- `Install-OPIMConfiguration` now auto-resolves `-TenantId` from the active Graph context when the parameter is omitted. A non-terminating error is emitted when no `-TenantId` is supplied and no active Graph session is available.

### Changed

- `Install-OPIMConfiguration`, `Set-OPIMConfiguration`, and `Remove-OPIMConfiguration` now have `ConfirmImpact = 'High'`. The `ShouldProcess` confirmation prompt includes the tenant alias, display name, and resolved GUID, making it clear which tenant is being modified before any write occurs.
- `-TenantId` in `Install-OPIMConfiguration` is no longer `[Mandatory]`; it is auto-resolved from `Get-MgContext` when omitted.
- PSScriptAnalyzer suppressions added to all six argument-completer classes (`AzureEligibleRoleCompleter`, `AzureActivatedRoleCompleter`, `DirectoryEligibleRoleCompleter`, `DirectoryActivatedRoleCompleter`, `GroupEligibleCompleter`, `GroupActivatedCompleter`).

### Changed

- `Write-CmdletError` revamped: new `ErrorRecord` parameter set (pass-through), `InnerException` parameter for exception chaining, `[CmdletBinding()]` added. All public and private functions now use `Write-CmdletError` as the single error-emission entry point.
- All variable names across `Convert-GraphHttpException`, `Get-MyId`, `Invoke-OPIMGraphRequest`, `Export-OPIMTenantMap`, and completer classes updated to PascalCase per module code-style rules.

 (alias `Connect-PIM`) — new public cmdlet to pre-authenticate against Microsoft Graph and optionally Azure. A single browser prompt covers all PIM surfaces (directory roles, Entra ID groups, Azure RBAC). All `Get-/Enable-/Disable-OPIM*` cmdlets call this automatically on first use.
- `Disconnect-OPIM` (alias `Disconnect-PIM`) — new public cmdlet to clear all cached session tokens and disconnect from Graph and Azure.
- Centralized MSAL-based authentication layer (`Initialize-OPIMAuth`, `Get-OPIMMsalApplication` private helpers). All PIM cmdlets now share a single token-acquisition flow that caches the result and is idempotent when called multiple times in the same session.
- ACRS Conditional Access claims-challenge handling moved into `Invoke-OPIMGraphRequest`. A single reactive browser re-prompt is issued when Graph returns a step-up challenge, eliminating repeated browser windows when activating multiple roles in one `Enable-OPIMMyRole` call.
- `Invoke-OPIMGraphRequest` private wrapper replaces direct `Invoke-MgGraphRequest` calls throughout the module. Provides bearer-token security (removes raw error records before any processing), ACRS retry, and consistent `Convert-GraphHttpException` error conversion.

 (ParameterSetName `ByIdentity`) added to all six `Enable-OPIM*` and `Disable-OPIM*` cmdlets. Activates or deactivates a role/group by schedule ID (or schedule `Name` for Azure) without tab completion. For `Disable-*` cmdlets, the ID must correspond to an active schedule instance (from `Get-OPIM* -Activated`). For Azure RBAC the identity is the `Name` property.
- `Get-OPIMDirectoryRole`, `Get-OPIMEntraIDGroup`, and `Get-OPIMAzureRole` gain a new `-All` ParameterSet that returns **both** eligible and active schedules for the current user in a single call. `-All` and `-Activated` are mutually exclusive.
- `Get-OPIMDirectoryRole` — new `-RoleName` positional parameter (`[Position = 0]`) with tab completion via `DirectoryEligibleRoleCompleter`. Extracts the schedule ID from the trailing `(id)` and performs a dual-search across eligible and active endpoints.
- `Get-OPIMEntraIDGroup` — new `-GroupName` positional parameter (`[Position = 0]`) with tab completion via `GroupEligibleCompleter`. Extracts the schedule ID from the trailing `(id)` and performs a dual-search across eligible and active endpoints.
- `Get-OPIMAzureRole` — new `-RoleName` positional parameter (`[Position = 0]`) with tab completion via `AzureEligibleRoleCompleter`, and new `-Identity` parameter for direct look-up by schedule `Name`. Both perform dual-search across eligible and active endpoints.
- Combined schedule view: When `-All`, `-RoleName`/`-GroupName`/`-Identity` trigger dual-search, all three `Get-OPIM*` cmdlets now return `Omnicit.PIM.*CombinedSchedule` typed objects with a `Status` column (`Eligible` or `Active`) for consistent table output across both result types.
- New format/type files for combined schedule views: `Omnicit.PIM.DirectoryCombinedSchedule`, `Omnicit.PIM.GroupCombinedSchedule`, `Omnicit.PIM.AzureCombinedSchedule` — each with a `Status` column in the default table view.

### Performance

- **Module load time reduced by ~8 seconds** (~55% of total import time). Consolidated 13 individual `*.Format.ps1xml` files into a single `Omnicit.PIM.Format.ps1xml` and 13 `*.Types.ps1xml` files into a single `Omnicit.PIM.Types.ps1xml`. Previously each file triggered a full format/type table rebuild (~0.49s and ~0.11s per call respectively).
- `FormatsToProcess` re-enabled in the module manifest — format data is now loaded natively by PowerShell at zero extra cost. This was previously disabled because `Update-FormatData -PrependPath` was needed to override Az.Resources native types; that override (`RoleAssignmentScheduleRequest`) is no longer needed since all output is wrapped as `Omnicit.PIM.*` custom types.
- `suffix.ps1` now loads a single consolidated `Omnicit.PIM.Types.ps1xml` file (1 call to `Update-TypeData`) instead of enumerating and loading 13 individual files (14 calls). `TypesToProcess` remains disabled in the manifest because `Remove-Module` does not clean type data, causing "member already present" errors on `Import-Module -Force`.
- Removed orphaned `RoleAssignmentScheduleRequest.Format.ps1xml` and `RoleAssignmentScheduleRequest.Types.ps1xml` — these targeted the native Az `Microsoft.Azure.PowerShell.Cmdlets.Resources.Authorization.Models.Api20201001Preview.RoleAssignmentScheduleRequest` type, but all Azure output is now wrapped with `Omnicit.PIM.AzureAssignmentScheduleRequest`.
- Pipeline safety guards: `Enable-OPIMDirectoryRole`, `Enable-OPIMEntraIDGroup`, `Enable-OPIMAzureRole` now skip pipeline objects already tagged as active assignment instances (e.g. objects piped from `Get-OPIM* -All` that have `Status = Active`), emitting a `Write-Verbose` message instead of attempting an activation that would fail.
- Pipeline safety guards: `Disable-OPIMDirectoryRole`, `Disable-OPIMEntraIDGroup`, `Disable-OPIMAzureRole` now skip pipeline objects tagged as eligible-only schedules (e.g. objects piped from `Get-OPIM* -All` that have `Status = Eligible`), emitting a non-terminating error instead of attempting a deactivation that would fail.

### Changed

- **BREAKING** — `Get-OPIMDirectoryRole -All`, `Get-OPIMEntraIDGroup -All`, and `Get-OPIMAzureRole -All` no longer remove `filterByCurrentUser` / `asTarget()` to list all principals. They now return **both** eligible and active schedules for the **current user**. Admins seeking all-principals data should query the Graph API directly with elevated permissions.
- **BREAKING** — `-All` and `-Activated` are now mutually exclusive on all three `Get-OPIM*` cmdlets. Combining them raises a parameter binding error.
- `Enable-OPIMDirectoryRole`, `Enable-OPIMEntraIDGroup`, `Enable-OPIMAzureRole` — `-Justification` is now positional `[Position = 1]` and `-Hours` is positional `[Position = 2]`, enabling: `Enable-OPIMDirectoryRole 'Role (id)' 'Justification' 4`.

### Fixed

- `Get-OPIMDirectoryRole -Activated` no longer applies a post-filter of `assignmentType -eq 'Activated'`. All items returned by `roleAssignmentScheduleInstances` are inherently active assignments; the filter suppressed results when the real Graph API response omitted or differed in that field.
- `Get-OPIMEntraIDGroup -All` no longer throws `MissingParameters: The required parameters GroupId or PrincipalId is missing`. The PIM Groups API requires `filterByCurrentUser(on='principal')` even when listing all types; this is now preserved.
- `Get-OPIMAzureRole -All` no longer throws `InsufficientPermissions`. The `asTarget()` filter is now preserved with `-All`, restricting results to the current user at scope `/`.
- `Get-OPIMAzureRole -Activated -Scope '<specific-scope>'` now returns only instances at that exact scope. Previously, `Get-AzRoleAssignmentScheduleInstance` returned inherited parent-scope instances; these are now filtered out client-side when scope is not `/`.
- `Get-OPIMDirectoryRole`, `Get-OPIMEntraIDGroup` — improved `.PARAMETER Filter` documentation with OData examples. Added `.EXAMPLE` blocks for `-Filter` and `-Identity` usage.
- `Get-OPIMEntraIDGroup` — `-AccessType` filter now applies correctly when `-All` is combined with `-AccessType member` or `-AccessType owner`. Previously the filter was silently ignored in `-All` mode.
- `Get-OPIMAzureRole` — removed `[Alias('Id')]` from the `-Scope` parameter. PowerShell's prefix-matching treated `Id` as an abbreviation of `-Identity`, causing "Parameter set cannot be resolved" errors when `-Identity` was specified alongside the default `$Scope = '/'` binding.
- `Get-OPIMAzureRole` — `Add-Member -NotePropertyName Status` now uses `-Force` to prevent "Cannot add a member with the name 'Status' because a member already exists" errors when the same object is processed more than once (e.g. across multiple pipeline invocations).
- `Get-OPIMAzureRole` dual-search now correctly separates the `-Name` (Get parameter set) and `-Filter` (List parameter set) calls to `Get-AzRoleEligibilitySchedule` and `Get-AzRoleAssignmentScheduleInstance`. These are mutually exclusive parameter sets in Az.Resources; previously passing both parameters caused a parameter binding error.

 — wraps `Invoke-MgGraphRequest` for PIM activation POST requests with automatic ACRS claims-challenge retry via MSAL interactive authentication. Used by `Enable-OPIMDirectoryRole` and `Enable-OPIMEntraIDGroup`.
- `Enable-OPIMMyRole` gains four new switch parameters: `-AllEligible`, `-AllEligibleDirectoryRoles`, `-AllEligibleEntraIDGroups`, `-AllEligibleAzureRoles`. These bypass the TenantMap filter and activate all eligible roles in the selected categories, each requiring interactive ShouldProcess confirmation (supports `-WhatIf`/`-Confirm`).
- `Omnicit.PIM.AzureAssignmentScheduleRequest` type with matching `Format.ps1xml` and `Types.ps1xml` — enables consistent table output for `Enable-OPIMAzureRole` and `Disable-OPIMAzureRole` results.
- `Get-OPIMConfiguration` — reads the TenantMap.psd1 file and returns typed `Omnicit.PIM.TenantConfiguration` objects (one per alias). Supports `-TenantAlias` filter and `-TenantMapPath` override. Alias: `Get-PIMConfig`.
- `Set-OPIMConfiguration` — updates an existing tenant alias entry. Accepts `-TenantId` to change the GUID and pipeline input from `Get-OPIMDirectoryRole`, `Get-OPIMEntraIDGroup`, or `Get-OPIMAzureRole` to replace stored role/group lists. Categories not supplied via pipeline are preserved. Supports `-WhatIf`/`-Confirm`. Alias: `Set-PIMConfig`.
- `Remove-OPIMConfiguration` — removes a single tenant alias from the TenantMap.psd1 file while preserving all other entries. Supports `-WhatIf`/`-Confirm`. Alias: `Remove-PIMConfig`.
- `Export-OPIMTenantMap` (private) — shared PSD1 serializer extracted from `Install-OPIMConfiguration` and reused by `Set-OPIMConfiguration` and `Remove-OPIMConfiguration`.
- `Omnicit.PIM.TenantConfiguration` type with script properties `DirectoryRoleCount`, `EntraIDGroupCount`, and `AzureRoleCount` for concise table display.

### Changed

- **BREAKING** — `Enable-OPIMMyRole` now requires explicit activation intent. Calling it without `-TenantAlias` or an `-AllEligible*` switch emits a non-terminating error (`NoActivationTargetSpecified`) and exits immediately. Previously it silently activated all eligible roles using the current Graph context.
- `Enable-OPIMMyRole` — when `-TenantAlias` is used with a hashtable Config that omits a category key (`DirectoryRoles`, `EntraIDGroups`, `AzureRoles`), a `Write-Warning` is now emitted and that category is skipped instead of activating all eligible roles in it.
- `Enable-OPIMMyRole` — replaced bare `throw` calls (for TenantMap-not-found and alias-not-found errors) with `$PSCmdlet.WriteError()` + `return`, making the function honour `-ErrorAction SilentlyContinue`.
- `Enable-OPIMAzureRole` and `Disable-OPIMAzureRole` — output is now tagged with the `Omnicit.PIM.AzureAssignmentScheduleRequest` type name so the new format file applies.
- **BREAKING** — `Install-OPIMConfiguration` is now a create-only operation. It emits a non-terminating error if the alias already exists and instructs the user to call `Set-OPIMConfiguration` instead.
- **BREAKING** — the `-Force` parameter has been removed from `Install-OPIMConfiguration`. Update semantics (including category preservation) are now handled by `Set-OPIMConfiguration`.
- `Install-OPIMConfiguration` now delegates PSD1 serialization to the new private helper `Export-OPIMTenantMap`.

### Removed

- The `-Force` switch on `Install-OPIMConfiguration` has been removed (see Changed above).

### Fixed

- **Security**: All Graph API `catch` blocks now call `$null = $Error.Remove($PSItem)` as the first statement, removing the raw `HttpRequestMessage` (which contains the `Authorization: Bearer <token>`) from `$Error` before any further processing. Previously the bearer token could be inspected via `$Error` after a failed Graph call.
- `Enable-OPIMEntraIDGroup` and `Enable-OPIMDirectoryRole` now surface `RoleAssignmentRequestAcrsValidationFailed` (CAE/ACRS claims challenge) as a direct, non-terminating `AuthenticationError` with an actionable message directing the user to run `Connect-MgGraph` in a new PowerShell session. The previous WAM-disable/disconnect/retry logic has been removed because `Set-MgGraphOption -DisableLoginByWAM $true` is silently ignored when using the default Graph ClientId, making the retry ineffective and causing unnecessary session disconnection.
- All `IArgumentCompleter` class methods now invoke `Get-OPIM*` functions via `[scriptblock]::Create()` to ensure Pester mocks can intercept calls from .NET class method bodies.

### Security

- In case of vulnerabilities.

