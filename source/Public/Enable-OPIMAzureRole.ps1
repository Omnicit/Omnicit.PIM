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
    param(
        [Parameter(ParameterSetName = 'RoleObject', Mandatory, ValueFromPipeline)]
        $Role,
        [Parameter(Position = 0, ParameterSetName = 'RoleName', Mandatory)]
        [ArgumentCompleter([AzureEligibleRoleCompleter])]
        [string[]]$RoleName,
        [string]$Justification,
        [string]$TicketNumber,
        [string]$TicketSystem,
        [ValidateNotNullOrEmpty()][int]$Hours = 1,
        [ValidateNotNullOrEmpty()][DateTime]$NotBefore = [DateTime]::Now,
        [DateTime][Alias('NotAfter')]$Until,
        [Switch]$Wait
    )
    process {
        $resolvedRoles = if ($RoleName) {
            $RoleName | ForEach-Object { Resolve-RoleByName $_ }
        } else {
            @($Role)
        }

        foreach ($Role in $resolvedRoles) {
            $roleActivateParams = @{
                Name                            = New-Guid
                Scope                           = $Role.ScopeId
                PrincipalId                     = $Role.PrincipalId
                RoleDefinitionId                = $Role.RoleDefinitionId
                RequestType                     = 'SelfActivate'
                LinkedRoleEligibilityScheduleId = $Role.Name
                Justification                   = $Justification
            }

            if ($Until) {
                $roleActivateParams.ExpirationType         = 'AfterDateTime'
                $roleActivateParams.ExpirationEndDateTime  = $Until
                [string]$roleExpireTime = $Until
            } else {
                $roleActivateParams.ExpirationType        = 'AfterDuration'
                $roleActivateParams.ExpirationDuration    = [XmlConvert]::ToString([TimeSpan]::FromHours($Hours))
                [string]$roleExpireTime = $NotBefore.AddHours($Hours)
            }

            if ($TicketNumber) { $roleActivateParams.TicketNumber = $TicketNumber }
            if ($TicketSystem)  { $roleActivateParams.TicketSystem  = $TicketSystem }

            if ($PSCmdlet.ShouldProcess(
                    "$($Role.RoleDefinitionDisplayName) on $($Role.ScopeDisplayName) ($($Role.ScopeId))",
                    "Activate Azure Role from $NotBefore to $roleExpireTime"
                )) {
                try {
                    $response = New-AzRoleAssignmentScheduleRequest @roleActivateParams -ErrorAction Stop
                } catch {
                    if (-not ($PSItem.FullyQualifiedErrorId -like 'RoleAssignmentRequestPolicyValidationFailed*')) {
                        $PSCmdlet.WriteError($PSItem)
                        continue
                    }
                    if ($PSItem -match 'JustificationRule') {
                        $PSItem.ErrorDetails = 'Your PIM policy requires a justification for this role. Use the -Justification parameter.'
                    }
                    if ($PSItem -match 'ExpirationRule') {
                        $PSItem.ErrorDetails = 'Your PIM policy requires a shorter expiration. Use -NotAfter to specify an earlier time.'
                    }
                    $PSCmdlet.WriteError($PSItem)
                    continue
                }

                if ($Wait) {
                    do {
                        $roleActivation = Get-AzRoleAssignmentScheduleRequest -Name $response.Name -Scope $response.Scope -ErrorAction Stop
                    } while (-not $roleActivation)
                }

                $response
            }
        }
    }
}
