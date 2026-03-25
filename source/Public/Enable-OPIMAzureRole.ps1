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
    #>
    [Alias('Enable-PIMResourceRole')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'RoleName')]
    param(
        #Eligible role object from Get-OPIMAzureRole.
        [Parameter(ParameterSetName = 'RoleObject', Mandatory, ValueFromPipeline)]
        $Role,
        #Friendly name of the eligible Azure role. Supports tab completion. Accepts multiple values.
        [Parameter(Position = 0, ParameterSetName = 'RoleName', Mandatory)]
        [ArgumentCompleter([AzureEligibleRoleCompleter])]
        [string[]]$RoleName,
        #Justification for the activation. May be required by your PIM policy.
        [string]$Justification,
        #Ticket number associated with this activation.
        [string]$TicketNumber,
        #Ticket system containing the above ticket number.
        [string]$TicketSystem,
        #Duration in hours. Defaults to 1 hour.
        [ValidateNotNullOrEmpty()][int]$Hours = 1,
        #Date and time when the role activation begins. Defaults to now.
        [ValidateNotNullOrEmpty()][DateTime]$NotBefore = [DateTime]::Now,
        #Explicit end date/time for the role activation. Takes precedence over -Hours when specified.
        [DateTime][Alias('NotAfter')]$Until,
        #Wait for the activation request to appear before returning.
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
