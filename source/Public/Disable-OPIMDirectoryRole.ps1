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
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'RoleObject', Mandatory, ValueFromPipeline)]
        $Role,
        [ArgumentCompleter([DirectoryActivatedRoleCompleter])]
        [Parameter(ParameterSetName = 'RoleName', Mandatory, Position = 0)]
        [String]$RoleName
    )
    process {
        if ($RoleName) { $Role = Resolve-RoleByName -AD -Activated $RoleName }

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
                Invoke-MgGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleAssignmentScheduleRequests' -Body $Request -Verbose:$false -ErrorAction Stop
            } catch {
                $Err = Convert-GraphHttpException $PSItem
                $IsActiveToShort = ($Err.FullyQualifiedErrorId -like 'ActiveDurationTooShort*') -or
                                   ($PSItem.Exception.Message -match 'ActiveDurationTooShort')
                if (-not $IsActiveToShort) {
                    $PSCmdlet.WriteError($Err)
                    return
                }
                $CooldownMsg = 'You must wait at least 5 minutes after activating a role before you can deactivate it.'
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new($CooldownMsg, $Err.Exception),
                    'ActiveDurationTooShort',
                    [System.Management.Automation.ErrorCategory]::ResourceUnavailable, $null))
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
