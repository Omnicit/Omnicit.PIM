function Disable-OPIMDirectoryRole {
    <#
    .SYNOPSIS
    Deactivate an active Azure AD PIM directory role.
    .DESCRIPTION
    Submits a SelfDeactivate request for an active directory role assignment.
    The RoleName parameter supports tab completion for your currently active roles.
    .EXAMPLE
    Get-OPIMDirectoryRole -Activated | Disable-OPIMDirectoryRole
    Deactivate all currently active directory roles.
    .EXAMPLE
    Disable-OPIMDirectoryRole <tab>
    Tab complete active roles; type letters to filter.
    .EXAMPLE
    Get-OPIMDirectoryRole -Activated | Select-Object -First 1 | Disable-OPIMDirectoryRole
    Deactivate the first active role.
    .OUTPUTS
    System.Collections.Hashtable (tagged as Omnicit.PIM.DirectoryAssignmentScheduleRequest)
    .PARAMETER Role
    Active directory role assignment schedule instance object piped from Get-OPIMDirectoryRole -Activated.
    .PARAMETER RoleName
    Name of the active directory role to deactivate. Supports tab completion to currently active roles.
    .PARAMETER Identity
    The schedule instance ID from Get-OPIMDirectoryRole -Activated (the id property) to deactivate
    directly without tab completion. Mutually exclusive with -Role and -RoleName.
    #>
    [Alias('Disable-PIMADRole', 'Disable-PIMRole')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'RoleName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'RoleObject', Mandatory, ValueFromPipeline)]
        $Role,
        [ArgumentCompleter([DirectoryActivatedRoleCompleter])]
        [Parameter(ParameterSetName = 'RoleName', Mandatory, Position = 0)]
        [String]$RoleName,
        [Parameter(ParameterSetName = 'ByIdentity', Mandatory)]
        [String]$Identity
    )
    process {
        Initialize-OPIMAuth
        if ($Identity) {
            $Role = Get-OPIMDirectoryRole -Activated -Identity $Identity | Select-Object -First 1
            if (-not $Role) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("No active directory role found with identity '$Identity'.")) `
                    -ErrorId 'IdentityNotFound' `
                    -Category ObjectNotFound `
                    -TargetObject $Identity `
                    -Cmdlet $PSCmdlet
                return
            }
        }
        if ($RoleName) { $Role = Resolve-RoleByName -AD -Activated $RoleName }

        # Skip eligible-only schedules piped from Get-OPIMDirectoryRole -All
        if ($Role.PSObject.TypeNames -contains 'Omnicit.PIM.DirectoryEligibilitySchedule') {
            Write-Verbose "Skipping eligible-only directory role: $($Role.roleDefinition.displayName)"
            return
        }

        $Request = @{
            action           = 'SelfDeactivate'
            roleDefinitionId = $Role.roleDefinitionId
            directoryScopeId = $Role.directoryScopeId
            principalId      = $Role.principalId
            targetScheduleId = $Role.roleAssignmentScheduleId
        }

        if ($PSCmdlet.ShouldProcess(
                $('{0} ({1})' -f $Role.roleDefinition.displayName, $Role.directoryScopeId),
                'Deactivate Directory Role'
            )) {
            $Response = try {
                Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleAssignmentScheduleRequests' -Body $Request
            } catch {
                $Err = $PSItem
                if (-not (ConvertTo-ActiveDurationTooShortError -CaughtError $Err -ResourceType 'role' -Cmdlet $PSCmdlet)) {
                    $PSCmdlet.WriteError($Err)
                }
                return
            }

            # Rehydrate expanded navigation properties from the active schedule instance
            'roleDefinition', 'principal', 'directoryScope' | Restore-GraphProperty $Request $Response $Role

            # Set a meaningful expiration to the createdDateTime for display
            if (-not $Response.scheduleInfo) { $Response['scheduleInfo'] = @{ expiration = @{} } }
            $Response.scheduleInfo.expiration.type        = 'afterDateTime'
            $Response.scheduleInfo.expiration.endDateTime = $Response.createdDateTime

            # Convert to PSCustomObject so custom Format views apply (hashtable uses Key/Value formatter).
            $Out = [PSCustomObject]$Response
            $Out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')
            return $Out
        }
    }
}
