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
        Initialize-OPIMAuth -IncludeARM
        if ($Identity) {
            $Role = Get-OPIMAzureRole -Activated | Where-Object Name -EQ $Identity | Select-Object -First 1
            if (-not $Role) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("No active Azure role found with identity '$Identity'.")) `
                    -ErrorId 'IdentityNotFound' `
                    -Category ObjectNotFound `
                    -TargetObject $Identity `
                    -Cmdlet $PSCmdlet
                return
            }
        }
        if ($RoleName) { $Role = Resolve-RoleByName -Activated $RoleName }

        # Skip eligible-only schedules piped from Get-OPIMAzureRole -All
        if ($Role.PSObject.TypeNames -contains 'Omnicit.PIM.AzureEligibilitySchedule') {
            Write-Verbose "Skipping eligible-only Azure role: $($Role.RoleDefinitionDisplayName)"
            return
        }

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
                if (-not (ConvertTo-ActiveDurationTooShortError -CaughtError $PSItem -ResourceType 'role' -Cmdlet $PSCmdlet)) {
                    $PSCmdlet.WriteError($PSItem)
                }
                return
            }
        }
    }
}
