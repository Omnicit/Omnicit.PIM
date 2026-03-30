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
    #>
    [Alias('Disable-PIMADRole', 'Disable-PIMRole')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'RoleName')]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Parameter(ParameterSetName = 'RoleObject', Mandatory, ValueFromPipeline)]
        $Role,
        [ArgumentCompleter([DirectoryActivatedRoleCompleter])]
        [Parameter(ParameterSetName = 'RoleName', Mandatory, Position = 0)]
        [String]$RoleName
    )
    process {
        if ($RoleName) { $Role = Resolve-RoleByName -AD -Activated $RoleName }

        $request = @{
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
            $response = try {
                Invoke-MgGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleAssignmentScheduleRequests' -Body $request -Verbose:$false -ErrorAction Stop
            } catch {
                $err = Convert-GraphHttpException $PSItem
                if (-not ($err.FullyQualifiedErrorId -like 'ActiveDurationTooShort*')) {
                    $PSCmdlet.WriteError($err)
                    return
                }
                $err.ErrorDetails = 'You must wait at least 5 minutes after activating a role before you can deactivate it.'
                $PSCmdlet.WriteError($err)
                return
            }

            # Rehydrate expanded navigation properties from the active schedule instance
            'roleDefinition', 'principal', 'directoryScope' | Restore-GraphProperty $request $response $Role

            # Set a meaningful expiration to the createdDateTime for display
            if (-not $response.scheduleInfo) { $response['scheduleInfo'] = @{ expiration = @{} } }
            $response.scheduleInfo.expiration.type        = 'afterDateTime'
            $response.scheduleInfo.expiration.endDateTime = $response.createdDateTime

            # Convert to PSCustomObject so custom Format views apply (hashtable uses Key/Value formatter).
            $out = [PSCustomObject]$response
            $out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')
            return $out
        }
    }
}
