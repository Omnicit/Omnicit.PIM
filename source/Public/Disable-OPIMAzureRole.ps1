#requires -module Az.Resources
function Disable-OPIMAzureRole {
    <#
    .SYNOPSIS
    Deactivate an active Azure PIM resource role.
    .DESCRIPTION
    Submits a SelfDeactivate request for an active Azure RBAC role assignment.
    The role is named by its display name, or by the form tab completion offers for the RoleName
    parameter for your currently active roles. A name that matches the role at more than one scope is
    refused with AmbiguousName and nothing is deactivated: add -Scope to pick one. A name that
    matches no active role is written as a (non-terminating) ActiveRoleNotFound error; when the role
    is eligible but not active, the message says it is already deactivated.
    The request is reported by the status Azure gives it: a deactivation that does not end Revoked
    is written as an ActivationRequestFailed error, and one that waits for approval or is still
    being processed is returned with a warning.
    .EXAMPLE
    Get-OPIMAzureRole -Activated | Disable-OPIMAzureRole
    Deactivate all currently active Azure roles.
    .EXAMPLE
    Disable-OPIMAzureRole 'Reader' -Scope '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app'
    Deactivates Reader on that resource group only. Without -Scope, a role that is active at more than
    one scope is refused with AmbiguousName.
    .EXAMPLE
    Disable-OPIMAzureRole <tab>
    Tab complete active Azure roles. A name that is unique is offered bare.
    .PARAMETER Role
    Active Azure RBAC role assignment schedule instance object piped from Get-OPIMAzureRole -Activated.
    .PARAMETER RoleName
    The display name of the active Azure role to deactivate (for example Reader), or the tab-completed
    form the argument completer offers for your currently active roles. A display name is compared
    exactly, without regard to letter case, and takes no wildcards. Several matches are refused with
    AmbiguousName.
    .PARAMETER Identity
    The schedule instance Name from Get-OPIMAzureRole -Activated (the Name property) to deactivate
    directly without a role name. A name that matches more than one instance is refused with
    AmbiguousName. Mutually exclusive with -Role and -RoleName.
    .PARAMETER Scope
    Picks one role when the name matches the role at more than one scope: the ARM scope of the
    active assignment, such as a subscription or a resource group. It means exactly that scope, not
    the scopes below it, and it is compared without regard to letter case. Unlike on
    Get-OPIMAzureRole, where '/' means every scope, '/' here means only a role that is active at the
    root scope itself. A scope that ends in '/' (other than '/') is refused. Applies to a name, and
    cannot be combined with piped objects (-Role) or -Identity: piping objects in together with
    -Scope selects the -RoleName parameter set, so an interactive host asks for -RoleName instead
    of failing to bind.
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

        # The request is built for the module's own ARM transport: the name of the request is a new id,
        # and the body names the active assignment by its principal and role definition, at the scope
        # of the path. OPIM-24: a deactivation names no eligibility and carries no schedule; ARM
        # documents linkedRoleEligibilityScheduleId for an activation only, and the instance's own Name
        # is not an eligibility id.
        $RequestName = [string](New-Guid)
        $RequestProperties = [ordered]@{
            principalId      = $Role.PrincipalId
            roleDefinitionId = $Role.RoleDefinitionId
            requestType      = 'SelfDeactivate'
        }
        # The root scope has no prefix: its path starts with /providers, never with //providers.
        $RequestScope = if ($Role.ScopeId -eq '/') { '' } else { $Role.ScopeId }
        $RequestPath = '{0}/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/{1}?api-version=2020-10-01' -f $RequestScope, $RequestName

        if ($PSCmdlet.ShouldProcess(
                "$($Role.RoleDefinitionDisplayName) on $($Role.ScopeDisplayName) ($($Role.ScopeId))",
                'Deactivate Azure Role'
            )) {
            try {
                # The transport gates the request itself (SignInRefused, TenantMismatch,
                # AccountMismatch) and throws a refusal or an ARM error as a record, which this catch
                # writes as itself.
                $Response = ConvertFrom-OPIMArmSchedule -Kind AssignmentScheduleRequest -InputObject (
                    Invoke-OPIMArmRequest -Method PUT -Path $RequestPath -Body @{ properties = $RequestProperties })
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                if (-not (ConvertTo-ActiveDurationTooShortError -CaughtError $PSItem -ResourceType 'role' -Cmdlet $PSCmdlet)) {
                    $PSCmdlet.WriteError($PSItem)
                }
                return
            }
            # Outside the try: a failed status written under -ErrorAction Stop must not reach the
            # catch above and be written a second time.
            $Response.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleRequest')
            $Label = (Get-OPIMScheduleName -Pillar Azure -InputObject $Role).Label
            Write-OPIMRequestOutcome -Request $Response -Status $Response.Status -Name $Label -Deactivate -Cmdlet $PSCmdlet
        }
    }
}
