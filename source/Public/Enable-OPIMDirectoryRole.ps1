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
    .PARAMETER Identity
    The schedule item ID from Get-OPIMDirectoryRole (the id property) to activate directly without
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
    begin {
        Initialize-OPIMAuth
        [System.Collections.Generic.List[PSObject]]$_pendingWait = [System.Collections.Generic.List[PSObject]]::new()
    }
    process {
        if ($Identity) {
            $Role = Get-OPIMDirectoryRole -Identity $Identity | Select-Object -First 1
            if (-not $Role) {
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("No eligible directory role found with identity '$Identity'."),
                    'IdentityNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Identity))
                return
            }
        }
        $ResolvedRoles = if ($RoleName) {
            $RoleName | ForEach-Object { Resolve-RoleByName -AD $_ }
        } else {
            @($Role)
        }

        foreach ($Role in $ResolvedRoles) {
            # Skip already-active instances piped from Get-OPIMDirectoryRole -All
            if ($Role.PSObject.TypeNames -contains 'Omnicit.PIM.DirectoryAssignmentScheduleInstance') {
                Write-Verbose "Skipping already-active directory role: $($Role.roleDefinition.displayName)"
                continue
            }
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
                $Response = try {
                    Invoke-OPIMGraphRequest -Method POST -Uri $GraphUri -Body $Request
                } catch {
                    $Err = $PSItem
                    $AllMsgs = "$($Err.FullyQualifiedErrorId) $($Err.Exception.Message)"
                    if ($AllMsgs -match 'JustificationRule') {
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
                if ($null -eq $Response) { continue }

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
