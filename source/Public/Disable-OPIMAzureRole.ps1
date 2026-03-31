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
    .PARAMETER Role
    Active Azure RBAC role assignment schedule instance object piped from Get-OPIMAzureRole -Activated.
    .PARAMETER RoleName
    Name of the active Azure role to deactivate. Supports tab completion to currently active roles.
    #>
    [Alias('Disable-PIMResourceRole')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'RoleName')]
    param(
        [Parameter(ParameterSetName = 'RoleObject', Mandatory, ValueFromPipeline)]
        $Role,
        [ArgumentCompleter([AzureActivatedRoleCompleter])]
        [Parameter(ParameterSetName = 'RoleName', Mandatory, Position = 0)]
        [String]$RoleName
    )
    process {
        if ($RoleName) { $Role = Resolve-RoleByName -Activated $RoleName }

        $RoleDeactivateParams = @{
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
                New-AzRoleAssignmentScheduleRequest @RoleDeactivateParams -ErrorAction Stop
            } catch {
                $IsActiveToShort = ($PSItem.FullyQualifiedErrorId -like 'ActiveDurationTooShort*') -or
                                   ($PSItem.Exception.Message -match 'ActiveDurationTooShort')
                if (-not $IsActiveToShort) {
                    $PSCmdlet.WriteError($PSItem)
                    return
                }
                $CooldownMsg = 'You must wait at least 5 minutes after activating a role before you can deactivate it.'
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new($CooldownMsg, $PSItem.Exception),
                    'ActiveDurationTooShort',
                    [System.Management.Automation.ErrorCategory]::ResourceUnavailable, $null))
                return
            }
        }
    }
}
