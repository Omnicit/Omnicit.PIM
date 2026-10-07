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
    .PARAMETER Scope
    Picks one role when the name matches the role at more than one scope: '/' or an administrative
    unit's id path or display name for a directory role, the ARM scope for an Azure role. Compared
    without regard to letter case; a scope that ends in '/' (other than '/') is refused.
    #>
    [Alias('Disable-PIMResourceRole')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'RoleName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'RoleObject', Mandatory, ValueFromPipeline)]
        $Role,
        [ArgumentCompleter([AzureActivatedRoleCompleter])]
        [Parameter(ParameterSetName = 'RoleName', Mandatory, Position = 0)]
        [String]$RoleName,
        [Parameter(ParameterSetName = 'ByIdentity', Mandatory)]
        [String]$Identity,
        [Parameter(ParameterSetName = 'RoleName')]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ $_ -eq '/' -or -not $_.EndsWith('/') }, ErrorMessage = "The scope '{0}' ends with '/'. Give it without the trailing slash; only the root scope is written '/'.")]
        [string]$Scope
    )
    process {
        Initialize-OPIMAuth -IncludeARM
        if ($Identity) {
            try {
                $FoundByIdentity = @(Get-OPIMAzureRole -Activated -ErrorAction Stop | Where-Object Name -EQ $Identity)
            } catch {
                # OPIM-12: the listing failed; report it as itself and stop for this identity.
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            if ($FoundByIdentity.Count -gt 1) {
                # Never the first of several: refuse with the candidates and act on none.
                $PSCmdlet.WriteError((New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Azure `
                    -Name $Identity -Status Active -Candidate $FoundByIdentity -Identity))
                return
            }
            $Role = $FoundByIdentity | Select-Object -First 1
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
        if ($RoleName) {
            $ResolveParams = @{ Pillar = 'Azure'; Status = 'Active'; FilterParameter = 'Scope'; ErrorAction = 'Stop' }
            if ($PSBoundParameters.ContainsKey('Scope')) { $ResolveParams.Scope = $Scope }
            try {
                $Role = Resolve-OPIMSchedule -Name $RoleName @ResolveParams
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }

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
                # SEC (EntraRBAC A19): the ARM gate, inside the try so the catch reports a refusal as
                # itself.
                $ArmRefusal = Get-OPIMArmRefusal
                if ($null -ne $ArmRefusal) { throw $ArmRefusal }
                $Response = New-AzRoleAssignmentScheduleRequest @RoleDeactivateParams -ErrorAction Stop
                $Response.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleRequest')
                $Response
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                if (-not (ConvertTo-ActiveDurationTooShortError -CaughtError $PSItem -ResourceType 'role' -Cmdlet $PSCmdlet)) {
                    $PSCmdlet.WriteError($PSItem)
                }
                return
            }
        }
    }
}
