using namespace System.Xml

#requires -module Az.Resources
function Enable-OPIMAzureRole {
    <#
    .SYNOPSIS
    Activate an Azure PIM eligible resource role.
    .DESCRIPTION
    Activates an eligible Azure RBAC role assignment for the current user. By default activates for 1 hour.
    The role is named by its display name, or by the form tab completion offers for the RoleName
    parameter ('Role -> Scope name (Name)'). A name that matches the role at more than one scope is
    refused with AmbiguousName and nothing is activated: add -Scope to pick one. A name that matches
    no eligible role is written as an EligibleRoleNotFound error. Several names are resolved one by
    one, each on its own, so a name that fails does not stop the next one.
    The request is reported by the status Azure gives it: a request that failed, was denied or was
    canceled is written as an ActivationRequestFailed error, and one that waits for approval or is
    still being provisioned is returned with a warning.
    .NOTES
    The default activation period is 1 hour. Override with -Hours. Make it persistent in your profile:

    $PSDefaultParameterValues['Enable-OPIM*:Hours'] = 5

    .EXAMPLE
    Get-OPIMAzureRole | Enable-OPIMAzureRole
    Activate all eligible Azure roles for 1 hour.
    .EXAMPLE
    Enable-OPIMAzureRole 'Reader' -Scope '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app'
    Activates Reader on that resource group only. Without -Scope, a role that is eligible at more than
    one scope is refused with AmbiguousName.
    .EXAMPLE
    Enable-OPIMAzureRole 'Reader', 'Contributor' -Scope '/subscriptions/00000000-0000-0000-0000-000000000000'
    Activates both roles at that subscription. Each name is resolved on its own.
    .EXAMPLE
    Enable-OPIMAzureRole <tab>
    Tab complete all eligible Azure roles. A name that is unique is offered bare; one that is not is
    offered in the longer form.
    .EXAMPLE
    Get-OPIMAzureRole | Select-Object -First 1 | Enable-OPIMAzureRole -Hours 4
    Activate the first eligible Azure role for 4 hours.
    .PARAMETER Role
    Eligible Azure RBAC role schedule object piped from Get-OPIMAzureRole. Used when activating
    by object rather than by name. Mutually exclusive with -RoleName.
    .PARAMETER RoleName
    The display name of the eligible Azure role (for example Reader), or the tab-completed form the
    argument completer offers ('Role -> Scope name (Name)'). A display name is compared exactly,
    without regard to letter case, and takes no wildcards. Accepts multiple values, each resolved on
    its own; -Scope applies to every one of them. Several matches are refused with AmbiguousName.
    Mutually exclusive with -Role.
    .PARAMETER Identity
    The schedule name from Get-OPIMAzureRole (the Name property) to activate directly without
    a role name. A name that matches more than one schedule is refused with AmbiguousName. Mutually
    exclusive with -Role and -RoleName.
    .PARAMETER Justification
    Free-text justification for the activation request. May be required by your PIM policy.
    .PARAMETER TicketNumber
    Ticket or work item number associated with this activation for auditing purposes.
    .PARAMETER TicketSystem
    Name of the ticket system that issued the above ticket number, e.g. ServiceNow or Jira.
    .PARAMETER Hours
    Activation duration in hours. Defaults to 1. Ignored when -Until is specified.
    .PARAMETER NotBefore
    Date and time when the role activation begins. Defaults to the current date and time.
    .PARAMETER Until
    Explicit end date and time for the activation. Takes precedence over -Hours when specified.
    Aliased as -NotAfter.
    .PARAMETER Scope
    Picks one role when the name matches the role at more than one scope: the ARM scope of the
    eligibility, such as a subscription or a resource group. It means exactly that scope, not the
    scopes below it, and it is compared without regard to letter case. Unlike on Get-OPIMAzureRole,
    where '/' means every scope, '/' here means only a role that is eligible at the root scope
    itself. A scope that ends in '/' (other than '/') is refused. Applies to every name in
    -RoleName, and cannot be combined with piped objects (-Role) or -Identity: piping objects in
    together with -Scope selects the -RoleName parameter set, so an interactive host asks for
    -RoleName instead of failing to bind.
    .PARAMETER Wait
    Wait for the activation request to be provisioned and appear before returning.
    #>
    [Alias('Enable-PIMResourceRole')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'RoleName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'RoleObject', Mandatory, ValueFromPipeline)]
        $Role,
        [Parameter(Position = 0, ParameterSetName = 'RoleName', Mandatory)]
        [ArgumentCompleter([AzureEligibleRoleCompleter])]
        [string[]]$RoleName,
        [Parameter(ParameterSetName = 'ByIdentity', Mandatory)]
        [string]$Identity,
        [Parameter(Position = 1)][string]$Justification,
        [string]$TicketNumber,
        [string]$TicketSystem,
        [Parameter(Position = 2)][ValidateNotNullOrEmpty()][int]$Hours = 1,
        [ValidateNotNullOrEmpty()][DateTime]$NotBefore = [DateTime]::Now,
        [DateTime][Alias('NotAfter')]$Until,
        [Parameter(ParameterSetName = 'RoleName')]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ $_ -eq '/' -or -not $_.EndsWith('/') }, ErrorMessage = "The scope '{0}' ends with '/'. Give it without the trailing slash; only the root scope is written '/'.")]
        [string]$Scope,
        [Switch]$Wait
    )
    process {
        Initialize-OPIMAuth -IncludeARM
        if ($Identity) {
            try {
                $FoundByIdentity = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object Name -EQ $Identity)
            } catch {
                # OPIM-12: the listing failed; report it as itself and stop for this identity.
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            if ($FoundByIdentity.Count -gt 1) {
                # Never the first of several: refuse with the candidates and act on none.
                $PSCmdlet.WriteError((New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Azure `
                    -Name $Identity -Status Eligible -Candidate $FoundByIdentity -Identity))
                return
            }
            $Role = $FoundByIdentity | Select-Object -First 1
            if (-not $Role) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("No eligible Azure role found with identity '$Identity'.")) `
                    -ErrorId 'IdentityNotFound' `
                    -Category ObjectNotFound `
                    -TargetObject $Identity `
                    -Cmdlet $PSCmdlet
                return
            }
        }
        $ResolvedRoles = if ($RoleName) {
            $ResolveParams = @{ Pillar = 'Azure'; FilterParameter = 'Scope'; ErrorAction = 'Stop' }
            if ($PSBoundParameters.ContainsKey('Scope')) { $ResolveParams.Scope = $Scope }
            foreach ($EachName in $RoleName) {
                try {
                    Resolve-OPIMSchedule -Name $EachName @ResolveParams
                } catch {
                    # Each name resolves on its own: a name that is ambiguous, unknown or cannot be
                    # listed is written as itself, and the next name still runs (OPIM-12).
                    Remove-OPIMErrorRecord -Record $PSItem
                    $PSCmdlet.WriteError($PSItem)
                }
            }
        } else {
            @($Role)
        }

        foreach ($Role in $ResolvedRoles) {
            # Skip already-active instances piped from Get-OPIMAzureRole -All
            if ($Role.PSObject.TypeNames -contains 'Omnicit.PIM.AzureAssignmentScheduleInstance') {
                Write-Verbose "Skipping already-active Azure role: $($Role.RoleDefinitionDisplayName) on $($Role.ScopeDisplayName)"
                continue
            }
            $RoleActivateParams = @{
                Name                            = New-Guid
                Scope                           = $Role.ScopeId
                PrincipalId                     = $Role.PrincipalId
                RoleDefinitionId                = $Role.RoleDefinitionId
                RequestType                     = 'SelfActivate'
                LinkedRoleEligibilityScheduleId = $Role.Name
                Justification                   = $Justification
            }

            if ($Until) {
                $RoleActivateParams.ExpirationType         = 'AfterDateTime'
                $RoleActivateParams.ExpirationEndDateTime  = $Until
                [string]$RoleExpireTime = $Until
            } else {
                $RoleActivateParams.ExpirationType        = 'AfterDuration'
                $RoleActivateParams.ExpirationDuration    = [XmlConvert]::ToString([TimeSpan]::FromHours($Hours))
                [string]$RoleExpireTime = $NotBefore.AddHours($Hours)
            }

            if ($TicketNumber) { $RoleActivateParams.TicketNumber = $TicketNumber }
            if ($TicketSystem)  { $RoleActivateParams.TicketSystem  = $TicketSystem }

            if ($PSCmdlet.ShouldProcess(
                    "$($Role.RoleDefinitionDisplayName) on $($Role.ScopeDisplayName) ($($Role.ScopeId))",
                    "Activate Azure Role from $NotBefore to $RoleExpireTime"
                )) {
                try {
                    # SEC (EntraRBAC A19): the ARM gate, inside the try so the catch reports a refusal
                    # as itself.
                    $ArmRefusal = Get-OPIMArmRefusal
                    if ($null -ne $ArmRefusal) { throw $ArmRefusal }
                    $Response = New-AzRoleAssignmentScheduleRequest @RoleActivateParams -ErrorAction Stop
                } catch {
                    Remove-OPIMErrorRecord -Record $PSItem
                    if (-not (ConvertTo-PolicyValidationError -CaughtError $PSItem -ResourceType 'role' -Cmdlet $PSCmdlet)) {
                        $PSCmdlet.WriteError($PSItem)
                    }
                    continue
                }

                if ($Wait) {
                    do {
                        # SEC (EntraRBAC A19): the ARM gate before every round of the poll. Outside the
                        # try below, whose catch ends the command: a refusal is written and stops only
                        # the wait; the request above was already sent.
                        $ArmRefusal = Get-OPIMArmRefusal
                        if ($null -ne $ArmRefusal) { $PSCmdlet.WriteError($ArmRefusal); break }
                        try {
                            $RoleActivation = Get-AzRoleAssignmentScheduleRequest -Name $Response.Name -Scope $Response.Scope -ErrorAction Stop
                        } catch {
                            # An ARM failure record can point at the request and its bearer token:
                            # scrub it, then end the command with it as before.
                            Remove-OPIMErrorRecord -Record $PSItem
                            $PSCmdlet.ThrowTerminatingError($PSItem)
                        }
                    } while (-not $RoleActivation)
                }

                $Response.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleRequest')
                $Label = (Get-OPIMScheduleName -Pillar Azure -InputObject $Role).Label
                Write-OPIMRequestOutcome -Request $Response -Status $Response.Status -Name $Label -Cmdlet $PSCmdlet
            }
        }
    }
}
