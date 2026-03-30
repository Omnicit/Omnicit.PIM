# TypesToProcess is disabled in the manifest: Remove-Module does not clean type data, so re-importing in the
# same session fails with "member already present" errors. Loading here with -ErrorAction SilentlyContinue
# silently skips already-registered members on subsequent imports.
Get-ChildItem "$PSScriptRoot\Formats\*.Types.PS1XML" | ForEach-Object {
    Update-TypeData -AppendPath $PSItem -ErrorAction SilentlyContinue
}

# FormatsToProcess in the manifest uses Update-FormatData -AppendPath, which means RequiredModules (Az.Resources)
# loaded before this module take format precedence. Using -PrependPath here ensures our formats win, which is
# required for the RoleAssignmentScheduleRequest Az-native type. The manifest FormatsToProcess remains
# disabled because it would lose to Az's format definitions.
# Ref: https://github.com/PowerShell/PowerShell/issues/17345 (closed for inactivity, not fixed — confirmed still an issue Feb 2025)
# -ErrorAction SilentlyContinue prevents stale format-file paths registered from a previous build version
# (cleaned from output/) from causing a terminating error on session-wide format refresh.
Get-ChildItem "$PSScriptRoot\Formats\*.Format.PS1XML" | ForEach-Object {
    Update-FormatData -PrependPath $PSItem -ErrorAction SilentlyContinue
}
