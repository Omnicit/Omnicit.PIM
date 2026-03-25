#requires -module Az.Resources
function Disable-OPIMAzureRole {
    <#
    .SYNOPSIS
    Deactivate an active Azure PIM resource role.
    .DESCRIPTION
    Submits a SelfDeactivate request for an active Azure RBAC role assignment.
    The RoleName parameter supports tab completion for currently active roles.
    .EXAMPLE
    Get-OPIMAzureRole -Activated | Disable-OPIMAzureRole
    Deactivate all currently active Azure roles.
    .EXAMPLE
    Disable-OPIMAzureRole <tab>
    Tab complete active Azure roles.
    #>
    [Alias('Disable-PIMResourceRole')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'RoleName')]
    param(
        #Active role schedule object from Get-OPIMAzureRole -Activated.
        [Parameter(ParameterSetName = 'RoleObject', Mandatory, ValueFromPipeline)]
        $Role,
        #Name of the active Azure role to deactivate. Supports tab completion.
        [ArgumentCompleter([AzureActivatedRoleCompleter])]
        [Parameter(ParameterSetName = 'RoleName', Mandatory, Position = 0)]
        [String]$RoleName
    )
    process {
        if ($RoleName) { $Role = Resolve-RoleByName -Activated $RoleName }

        $roleDeactivateParams = @{
            Name                            = New-Guid
            Scope                           = $Role.ScopeId
            PrincipalId                     = $Role.PrincipalId
            RoleDefinitionId                = $Role.RoleDefinitionId
            RequestType                     = 'SelfDeactivate'
            LinkedRoleEligibilityScheduleId = $Role.Name
        }

        if ($PSCmdlet.ShouldProcess(
                "$($Role.RoleDefinitionDisplayName) on $($Role.ScopeDisplayName) ($($Role.ScopeId))",
                'Deactivate Azure Role'
            )) {
            try {
                New-AzRoleAssignmentScheduleRequest @roleDeactivateParams -ErrorAction Stop
            } catch {
                if (-not ($PSItem.FullyQualifiedErrorId -like 'ActiveDurationTooShort*')) {
                    $PSCmdlet.WriteError($PSItem)
                    return
                }
                $PSItem.ErrorDetails = 'You must wait at least 5 minutes after activating a role before you can deactivate it.'
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }
    }
}
