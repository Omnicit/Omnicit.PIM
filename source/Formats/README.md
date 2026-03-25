# Format & Type Files

Each type requires a paired `.Format.ps1xml` (column layout) and `.Types.ps1xml` (default display properties).

> **Note:** `TypesToProcess` in `Omnicit.PIM.psd1` loads the `.Types.ps1xml` files.  
> `.Format.ps1xml` files are loaded via `Update-FormatData -PrependPath` in `Omnicit.PIM.psm1` due to PowerShell bug [#17345](https://github.com/PowerShell/PowerShell/issues/17345).

## Type → Format mapping

| Type name | Format/Types file prefix | Assigned by |
|---|---|---|
| `Omnicit.PIM.AzureEligibilitySchedule` | `Omnicit.PIM.AzureEligibilitySchedule` | `Get-OPIMAzureRole` (eligible, default) |
| `Omnicit.PIM.AzureAssignmentScheduleInstance` | `Omnicit.PIM.AzureAssignmentScheduleInstance` | `Get-OPIMAzureRole -Activated` |
| `Omnicit.PIM.DirectoryEligibilitySchedule` | `Omnicit.PIM.DirectoryEligibilitySchedule` | `Get-OPIMDirectoryRole` (eligible, default) |
| `Omnicit.PIM.DirectoryAssignmentScheduleInstance` | `Omnicit.PIM.DirectoryAssignmentScheduleInstance` | `Get-OPIMDirectoryRole -Activated` |
| `Omnicit.PIM.DirectoryAssignmentScheduleRequest` | `Omnicit.PIM.DirectoryAssignmentScheduleRequest` | `Enable-OPIMDirectoryRole`, `Disable-OPIMDirectoryRole` |
| `Omnicit.PIM.GroupEligibilitySchedule` | `Omnicit.PIM.GroupEligibilitySchedule` | `Get-OPIMEntraIDGroup` (eligible, default) |
| `Omnicit.PIM.GroupAssignmentScheduleInstance` | `Omnicit.PIM.GroupAssignmentScheduleInstance` | `Get-OPIMEntraIDGroup -Activated` |
| `Omnicit.PIM.GroupAssignmentScheduleRequest` | `Omnicit.PIM.GroupAssignmentScheduleRequest` | `Enable-OPIMEntraIDGroup`, `Disable-OPIMEntraIDGroup` |
| `Microsoft.Azure.PowerShell.Cmdlets.Resources.Authorization.Models.Api20201001Preview.RoleAssignmentScheduleRequest` | `RoleAssignmentScheduleRequest` | `Enable-OPIMAzureRole`, `Disable-OPIMAzureRole` (native Az type, format applied automatically) |

## Adding a new format pair

1. Create `Source/Formats/Omnicit.PIM.<TypeNoun>.Format.ps1xml` and `Omnicit.PIM.<TypeNoun>.Types.ps1xml`.
2. Add the `.Types.ps1xml` path to `TypesToProcess` in `Omnicit.PIM.psd1`.
3. The `.Format.ps1xml` is picked up automatically by the glob in `Omnicit.PIM.psm1` — no manifest change needed.
4. In the outputting function, tag the object before emitting it:
   ```powershell
   $out = [PSCustomObject]$response
   $out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.<TypeNoun>')
   $out
   ```
