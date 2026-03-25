# Load order: Classes (completers/types) -> Private (helpers) -> Public (exported functions)
$PublicFunctions = [System.Collections.Generic.List[string]]::new()
foreach ($ScriptPathItem in 'Classes', 'Private', 'Public') {
    $ScriptSearchFilter = [io.path]::Combine($PSScriptRoot, $ScriptPathItem, '*.ps1')
    Get-ChildItem -Recurse -Path $ScriptSearchFilter -Exclude '*.Tests.ps1' -ErrorAction SilentlyContinue |
        ForEach-Object {
            . $PSItem
            if ($ScriptPathItem -eq 'Public') {
                $PublicFunctions.Add($PSItem.BaseName)
            }
        }
}

Export-ModuleMember -Function $PublicFunctions

# FormatsToProcess in the manifest uses Update-FormatData -AppendPath, which means RequiredModules (Az.Resources)
# loaded before this psm1 take format precedence. Using -PrependPath here ensures our formats win, which is
# required for the RoleAssignmentScheduleRequest Az-native type. The manifest FormatsToProcess remains
# disabled because it would lose to Az's format definitions.
# Ref: https://github.com/PowerShell/PowerShell/issues/17345 (closed for inactivity, not fixed — confirmed still an issue Feb 2025)
Get-ChildItem "$PSScriptRoot\Formats\*.Format.PS1XML" | ForEach-Object {
    Update-FormatData -PrependPath $PSItem
}
