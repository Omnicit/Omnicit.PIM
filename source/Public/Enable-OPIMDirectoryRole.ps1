function Enable-OPIMDirectoryRole {
    <#
    .SYNOPSIS
    Activate an Azure AD PIM eligible directory role.
    .DESCRIPTION
    Activates an eligible directory role assignment for the current user. By default activates for 1 hour.
    The RoleName parameter supports tab completion for available eligible roles.
    .NOTES
    The default activation period is 1 hour. Override with -Hours. Make it persistent in your profile:

    $PSDefaultParameterValues['Enable-OPIM*:Hours'] = 5

    .EXAMPLE
    Get-OPIMDirectoryRole | Enable-OPIMDirectoryRole
    Activate all eligible directory roles for 1 hour.
    .EXAMPLE
    Enable-OPIMDirectoryRole <tab>
    Tab complete all eligible directory roles.
    .EXAMPLE
    Get-OPIMDirectoryRole | Select -First 1 | Enable-OPIMDirectoryRole -Hours 4
    Activate the first eligible role for 4 hours.
    .EXAMPLE
    Get-OPIMDirectoryRole | Select -First 1 | Enable-OPIMDirectoryRole -NotBefore '4pm' -Until '5pm'
    Activate a role from 4pm to 5pm today.
    .OUTPUTS
    System.Collections.Hashtable (tagged as Omnicit.PIM.DirectoryAssignmentScheduleRequest)
    .PARAMETER Role
    Eligible directory role schedule object piped from Get-OPIMDirectoryRole. Used when activating
    by object rather than by tab-completed name. Mutually exclusive with -RoleName.
    .PARAMETER RoleName
    Tab-completable name of the eligible directory role in the format produced by the argument completer.
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
    Wait until the directory role is fully provisioned before returning.
    #>
    [Alias('Enable-PIMADRole', 'Enable-PIMRole')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'RoleName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'RoleObject', Mandatory, ValueFromPipeline)]
        $Role,
        [Parameter(Position = 0, ParameterSetName = 'RoleName', Mandatory)]
        [ArgumentCompleter([DirectoryEligibleRoleCompleter])]
        [string[]]$RoleName,
        [string]$Justification,
        [string]$TicketNumber,
        [string]$TicketSystem,
        [ValidateNotNullOrEmpty()][int]$Hours = 1,
        [ValidateNotNullOrEmpty()][DateTime]$NotBefore = [DateTime]::Now,
        [DateTime][Alias('NotAfter')]$Until,
        [Switch]$Wait
    )
    begin {
        [System.Collections.Generic.List[PSObject]]$_pendingWait = [System.Collections.Generic.List[PSObject]]::new()
    }
    process {
        $ResolvedRoles = if ($RoleName) {
            $RoleName | ForEach-Object { Resolve-RoleByName -AD $_ }
        } else {
            @($Role)
        }

        foreach ($Role in $ResolvedRoles) {
            $ScheduleInfo = @{
                startDateTime = $NotBefore.ToString('o')
                expiration    = @{}
            }

            $Expiration = $ScheduleInfo.expiration
            if ($Until) {
                $Expiration.type        = 'AfterDateTime'
                $Expiration.endDateTime = $Until.ToString('o')
                [string]$RoleExpireTime = $Until
            } else {
                $Expiration.type     = 'AfterDuration'
                $Expiration.duration = [System.Xml.XmlConvert]::ToString([TimeSpan]::FromHours($Hours))
                [string]$RoleExpireTime = $NotBefore.AddHours($Hours)
            }

            $Request = @{
                action           = 'SelfActivate'
                justification    = $Justification
                roleDefinitionId = $Role.roleDefinitionId
                directoryScopeId = $Role.directoryScopeId
                principalId      = $Role.principalId
                scheduleInfo     = $ScheduleInfo
                ticketInfo       = @{
                    ticketNumber = $TicketNumber
                    ticketSystem = $TicketSystem
                }
            }

            $UserPrincipalName = $Role.principal.userPrincipalName
            if ($PSCmdlet.ShouldProcess(
                    $UserPrincipalName,
                    "Activate $($Role.roleDefinition.displayName) for scope $($Role.directoryScopeId) from $NotBefore to $RoleExpireTime"
                )) {
                $GraphUri = 'v1.0/roleManagement/directory/roleAssignmentScheduleRequests'
                $Result = Invoke-GraphWithAcrsRetry -Uri $GraphUri -Body $Request

                # Invoke-GraphWithAcrsRetry returns a hashtable with _AcrsError key when the call failed.
                # Success returns a plain response hashtable without this key.
                if ($Result -is [hashtable] -and $Result.ContainsKey('_AcrsError')) {
                    $Err     = $Result._ErrorRecord
                    $AllMsgs = $Result._AllMsgs
                    if ($Result._AcrsError -and ($Result._NoClaimsExtracted -or $Result._NoMsal -or $Result._MsalBuildFailed -or $Result._NoWithClaims -or $Result._TokenFailed -or $Result._RetryFailed)) {
                        $AcrsMsg = 'PIM requires Conditional Access authentication context that your current ' +
                            'session token does not satisfy. The automatic claims-challenge retry failed. ' +
                            'Run Disconnect-MgGraph, then Connect-MgGraph in a new PowerShell session. ' +
                            'If the issue persists, the tenant may require a custom app registration.'
                        $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new($AcrsMsg, $Err.Exception),
                            'RoleAssignmentRequestAcrsValidationFailed',
                            [System.Management.Automation.ErrorCategory]::AuthenticationError, $null))
                        continue
                    } elseif ($AllMsgs -match 'JustificationRule') {
                        $JustMsg = 'Your PIM policy requires a justification for this role. Use the -Justification parameter.'
                        $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new($JustMsg, $Err.Exception),
                            'RoleAssignmentRequestPolicyValidationFailed',
                            [System.Management.Automation.ErrorCategory]::OperationStopped, $null))
                        continue
                    } elseif ($AllMsgs -match 'ExpirationRule') {
                        $ExpMsg = 'Your PIM policy requires a shorter expiration. Use -NotAfter to specify an earlier time.'
                        $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new($ExpMsg, $Err.Exception),
                            'RoleAssignmentRequestPolicyValidationFailed',
                            [System.Management.Automation.ErrorCategory]::OperationStopped, $null))
                        continue
                    } else {
                        $PSCmdlet.WriteError($Err)
                        continue
                    }
                }

                $Response = $Result

                # Rehydrate expanded navigation properties from the eligibility schedule
                'roleDefinition', 'principal', 'directoryScope' | Restore-GraphProperty $Request $Response $Role

                # Convert to PSCustomObject so custom Format views apply (hashtable uses Key/Value formatter).
                $Out = [PSCustomObject]$Response
                $Out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')

                if ($Wait) {
                    $_pendingWait.Add($Out)
                } else {
                    $Out
                }
            }
        }
    }
    end {
        if ($_pendingWait.Count -gt 0) {
            $_pendingWait | Wait-OPIMDirectoryRole -PassThru
        }
    }
}
