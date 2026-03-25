# FormatsToProcess in the manifest uses Update-FormatData -AppendPath, which means RequiredModules (Az.Resources)
# loaded before this module take format precedence. Using -PrependPath here ensures our formats win, which is
# required for the RoleAssignmentScheduleRequest Az-native type. The manifest FormatsToProcess remains
# disabled because it would lose to Az's format definitions.
# Ref: https://github.com/PowerShell/PowerShell/issues/17345 (closed for inactivity, not fixed — confirmed still an issue Feb 2025)
Get-ChildItem "$PSScriptRoot\Formats\*.Format.PS1XML" | ForEach-Object {
    Update-FormatData -PrependPath $PSItem
}
