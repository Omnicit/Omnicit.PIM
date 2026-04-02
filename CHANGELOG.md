# Changelog for Omnicit.PIM

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Get-OPIMConfiguration` — reads the TenantMap.psd1 file and returns typed `Omnicit.PIM.TenantConfiguration` objects (one per alias). Supports `-TenantAlias` filter and `-TenantMapPath` override. Alias: `Get-PIMConfig`.
- `Set-OPIMConfiguration` — updates an existing tenant alias entry. Accepts `-TenantId` to change the GUID and pipeline input from `Get-OPIMDirectoryRole`, `Get-OPIMEntraIDGroup`, or `Get-OPIMAzureRole` to replace stored role/group lists. Categories not supplied via pipeline are preserved. Supports `-WhatIf`/`-Confirm`. Alias: `Set-PIMConfig`.
- `Remove-OPIMConfiguration` — removes a single tenant alias from the TenantMap.psd1 file while preserving all other entries. Supports `-WhatIf`/`-Confirm`. Alias: `Remove-PIMConfig`.
- `Export-OPIMTenantMap` (private) — shared PSD1 serializer extracted from `Install-OPIMConfiguration` and reused by `Set-OPIMConfiguration` and `Remove-OPIMConfiguration`.
- `Omnicit.PIM.TenantConfiguration` type with script properties `DirectoryRoleCount`, `EntraIDGroupCount`, and `AzureRoleCount` for concise table display.

### Changed

- **BREAKING** — `Install-OPIMConfiguration` is now a create-only operation. It emits a non-terminating error if the alias already exists and instructs the user to call `Set-OPIMConfiguration` instead.
- **BREAKING** — the `-Force` parameter has been removed from `Install-OPIMConfiguration`. Update semantics (including category preservation) are now handled by `Set-OPIMConfiguration`.
- `Install-OPIMConfiguration` now delegates PSD1 serialization to the new private helper `Export-OPIMTenantMap`.

### Removed

- The `-Force` switch on `Install-OPIMConfiguration` has been removed (see Changed above).

### Fixed

- For any bug fix.

### Security

- In case of vulnerabilities.

