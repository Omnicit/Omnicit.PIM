# Format & Type Files

All format and type definitions are consolidated into two files:

| File | Purpose | Loaded by |
|---|---|---|
| `Omnicit.PIM.Format.ps1xml` | Table column layouts for all 13 `Omnicit.PIM.*` types | `FormatsToProcess` in `Omnicit.PIM.psd1` (manifest) |
| `Omnicit.PIM.Types.ps1xml` | ScriptProperty members (computed properties) for types that need them | `Update-TypeData -AppendPath` in `suffix.ps1` |

> **Why not `TypesToProcess`?** `Remove-Module` does not clean type data. On `Import-Module -Force`, re-registering
> ScriptProperty members via the manifest fails with "member already present" errors. Loading in the psm1 suffix
> with `-ErrorAction SilentlyContinue` silently skips already-registered members.

> **Why `FormatsToProcess` is safe now:** All format targets are `Omnicit.PIM.*` custom types. The orphaned
> `RoleAssignmentScheduleRequest` Az-native type override was removed because all Azure functions wrap output
> with `Omnicit.PIM.AzureAssignmentScheduleRequest` before returning — the native Az format was never applied.

## Type → Format mapping

| Type name | Assigned by |
|---|---|
| `Omnicit.PIM.AzureEligibilitySchedule` | `Get-OPIMAzureRole` (eligible, default) |
| `Omnicit.PIM.AzureAssignmentScheduleInstance` | `Get-OPIMAzureRole -Activated` |
| `Omnicit.PIM.AzureAssignmentScheduleRequest` | `Enable-OPIMAzureRole`, `Disable-OPIMAzureRole` |
| `Omnicit.PIM.AzureCombinedSchedule` | `Get-OPIMAzureRole -All` |
| `Omnicit.PIM.DirectoryEligibilitySchedule` | `Get-OPIMDirectoryRole` (eligible, default) |
| `Omnicit.PIM.DirectoryAssignmentScheduleInstance` | `Get-OPIMDirectoryRole -Activated` |
| `Omnicit.PIM.DirectoryAssignmentScheduleRequest` | `Enable-OPIMDirectoryRole`, `Disable-OPIMDirectoryRole` |
| `Omnicit.PIM.DirectoryCombinedSchedule` | `Get-OPIMDirectoryRole -All` |
| `Omnicit.PIM.GroupEligibilitySchedule` | `Get-OPIMEntraIDGroup` (eligible, default) |
| `Omnicit.PIM.GroupAssignmentScheduleInstance` | `Get-OPIMEntraIDGroup -Activated` |
| `Omnicit.PIM.GroupAssignmentScheduleRequest` | `Enable-OPIMEntraIDGroup`, `Disable-OPIMEntraIDGroup` |
| `Omnicit.PIM.GroupCombinedSchedule` | `Get-OPIMEntraIDGroup -All` |
| `Omnicit.PIM.TenantConfiguration` | `Get-OPIMConfiguration` |

## Adding a new type

1. Add a `<View>` element to `Omnicit.PIM.Format.ps1xml`.
2. If the type needs ScriptProperty members, add a `<Type>` element to `Omnicit.PIM.Types.ps1xml`.
3. In the outputting function, tag the object before emitting it:
   ```powershell
   $out = [PSCustomObject]$response
   $out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.<TypeNoun>')
   $out
   ```
