function Resolve-RoleByName ($RoleName, [Switch]$AD, [Switch]$Group, [Switch]$Activated) {
    <#
    .SYNOPSIS
    Resolves a tab-completed role name string to the matching schedule object.
    The RoleName string must contain the schedule ID in parentheses, e.g. 'Global Administrator (abc-123)'.
    #>
    if (-not $RoleName) { throw 'RoleName was null. This is a bug.' }

    # Extract the GUID from the end of the completion string: 'Name (guid)'
    $guidExtractRegex = '.+\(([\w-]+)\)', '$1'
    $scheduleId       = $RoleName -replace $guidExtractRegex
    if (-not $scheduleId) {
        throw "RoleName '$RoleName' is in an unexpected format. Expected 'Display Name (schedule-id)'. The -RoleName parameter is meant to be used with tab completion, not typed manually."
    }

    $role = if ($Group) {
        Get-OPIMEntraIDGroup -Activated:$Activated | Where-Object { $_.id -eq $scheduleId }
    } elseif ($AD) {
        Get-OPIMDirectoryRole -Activated:$Activated | Where-Object { $_.id -eq $scheduleId }
    } else {
        Get-OPIMAzureRole -Activated:$Activated | Where-Object { $_.Name -eq $scheduleId }
    }

    if (-not $role) {
        throw "Schedule ID '$scheduleId' from '$RoleName' was not found as an eligible role for this user. If you used tab completion and this is unexpected, please report it as a bug."
    }
    if (@($role).Count -gt 1) {
        throw "Multiple roles found for schedule ID '$scheduleId'. This is a bug — please report it."
    }

    return $role
}
