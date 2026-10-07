using namespace System.Xml

#requires -module Az.Resources
function Enable-OPIMAzureRole {
    <#
    .SYNOPSIS
    Activate an Azure PIM eligible resource role.
    .DESCRIPTION
    Activates an eligible Azure RBAC role assignment for the current user. By default activates for 1 hour.
    The RoleName parameter supports tab completion.
    .NOTES
    The default activation period is 1 hour. Override with -Hours. Make it persistent in your profile:

    $PSDefaultParameterValues['Enable-OPIM*:Hours'] = 5

    .EXAMPLE
    Get-OPIMAzureRole | Enable-OPIMAzureRole
    Activate all eligible Azure roles for 1 hour.
    .EXAMPLE
    Enable-OPIMAzureRole <tab>
    Tab complete all eligible Azure roles.
    .EXAMPLE
    Get-OPIMAzureRole | Select-Object -First 1 | Enable-OPIMAzureRole -Hours 4
    Activate the first eligible Azure role for 4 hours.
    .PARAMETER Role
    Eligible Azure RBAC role schedule object piped from Get-OPIMAzureRole. Used when activating
    by object rather than by tab-completed name. Mutually exclusive with -RoleName.
    .PARAMETER RoleName
    Tab-completable name of the eligible Azure role in the format produced by the argument completer.
    Accepts multiple values. Mutually exclusive with -Role.
    .PARAMETER Identity
    The schedule name from Get-OPIMAzureRole (the Name property) to activate directly without
    tab completion. Mutually exclusive with -Role and -RoleName.
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
        [Switch]$Wait
    )
    process {
        Initialize-OPIMAuth -IncludeARM
        if ($Identity) {
            try {
                $Role = Get-OPIMAzureRole -ErrorAction Stop | Where-Object Name -EQ $Identity | Select-Object -First 1
            } catch {
                # OPIM-12: the listing failed; report it as itself and stop for this identity.
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
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
            $RoleName | ForEach-Object { Resolve-RoleByName $_ }
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
                $Response
            }
        }
    }
}
