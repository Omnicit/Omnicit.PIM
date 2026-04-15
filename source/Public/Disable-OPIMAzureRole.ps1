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
    .PARAMETER Identity
    The schedule instance Name from Get-OPIMAzureRole -Activated (the Name property) to deactivate
    directly without tab completion. Mutually exclusive with -Role and -RoleName.
    #>
    [Alias('Disable-PIMResourceRole')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'RoleName')]
    param(
        [Parameter(ParameterSetName = 'RoleObject', Mandatory, ValueFromPipeline)]
        $Role,
        [ArgumentCompleter([AzureActivatedRoleCompleter])]
        [Parameter(ParameterSetName = 'RoleName', Mandatory, Position = 0)]
        [String]$RoleName,
        [Parameter(ParameterSetName = 'ByIdentity', Mandatory)]
        [String]$Identity
    )
    process {
        if ($Identity) {
            $Role = Get-OPIMAzureRole -Activated | Where-Object Name -EQ $Identity | Select-Object -First 1
            if (-not $Role) {
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("No active Azure role found with identity '$Identity'."),
                    'IdentityNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Identity))
                return
            }
        }
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
                $Response = New-AzRoleAssignmentScheduleRequest @RoleDeactivateParams -ErrorAction Stop
                $Response.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleRequest')
                $Response
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
