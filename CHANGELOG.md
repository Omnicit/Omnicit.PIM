# Changelog for Omnicit.PIM

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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

- For any bug fix.

### Security

- In case of vulnerabilities.

