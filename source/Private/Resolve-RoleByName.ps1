function Resolve-RoleByName ($RoleName, [Switch]$AD, [Switch]$Group, [Switch]$Activated) {
    <#
    .SYNOPSIS
    Resolves a tab-completed role name string to the matching PIM schedule object.

    .DESCRIPTION
    Parses the schedule ID from a tab-completion string in the format 'Display Name (schedule-id)'
    and looks up the corresponding schedule object using Get-OPIMDirectoryRole, Get-OPIMAzureRole,
    or Get-OPIMEntraIDGroup depending on the switch parameters provided. Throws if the schedule ID
    cannot be found or if more than one match is returned.

    .PARAMETER RoleName
    A role or group name string in the format produced by the module's IArgumentCompleter classes:
    'Display Name (schedule-id)'. The schedule ID is extracted from the parenthesised suffix.
    This parameter is designed for tab-completion use and should not be typed manually.

    .PARAMETER AD
    When specified, resolves against Entra ID directory role eligibility schedules by calling
    Get-OPIMDirectoryRole and matching on the schedule id property.

    .PARAMETER Group
    When specified, resolves against PIM for Groups eligibility schedules by calling
    Get-OPIMEntraIDGroup and matching on the schedule id property.

    .PARAMETER Activated
    When specified, passes -Activated to the underlying Get-OPIM* call so that only currently
    active assignments are considered rather than eligible (inactive) ones.

    .EXAMPLE
    Resolve-RoleByName -RoleName 'Global Administrator (abc-123)' -AD

    Looks up the Entra ID directory role eligibility schedule whose id is 'abc-123'.
    #>
    if (-not $RoleName) { throw 'RoleName was null. This is a bug.' }

    # Extract the GUID from the end of the completion string: 'Name (guid)'
    $GuidExtractRegex = '.+\(([\w-]+)\)', '$1'
    $ScheduleId       = $RoleName -replace $GuidExtractRegex
    if (-not $ScheduleId) {
        throw "RoleName '$RoleName' is in an unexpected format. Expected 'Display Name (schedule-id)'. The -RoleName parameter is meant to be used with tab completion, not typed manually."
    }

    $Role = if ($Group) {
        Get-OPIMEntraIDGroup -Activated:$Activated | Where-Object { $_.id -eq $ScheduleId }
    } elseif ($AD) {
        Get-OPIMDirectoryRole -Activated:$Activated | Where-Object { $_.id -eq $ScheduleId }
    } else {
        Get-OPIMAzureRole -Activated:$Activated | Where-Object { $_.Name -eq $ScheduleId }
    }

    if (-not $Role) {
        throw "Schedule ID '$ScheduleId' from '$RoleName' was not found as an eligible role for this user. If you used tab completion and this is unexpected, please report it as a bug."
    }
    if (@($Role).Count -gt 1) {
        throw "Multiple roles found for schedule ID '$ScheduleId'. This is a bug -- please report it."
    }

    return $Role
}
