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
                $Response = try {
                    Invoke-MgGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleAssignmentScheduleRequests' -Body $Request -Verbose:$false -ErrorAction Stop
                } catch {
                    $Err = Convert-GraphHttpException $PSItem
                    $AllMsgs = "$($Err.FullyQualifiedErrorId) $($Err.Exception.Message) $($PSItem.Exception.Message)"
                    if ($AllMsgs -match 'RoleAssignmentRequestAcrsValidationFailed') {
                        # PIM requires ACRS 'c1'; the current token no longer carries that claim.
                        # On Windows, Web Account Manager (WAM) or the MSAL process-level cache may
                        # reuse the same token even after Disconnect-MgGraph.  Disable WAM temporarily
                        # so Connect-MgGraph is forced to obtain a truly fresh token.  Retry once.
                        $MgCtx = Get-MgContext
                        $ConnectSplat = @{ ErrorAction = 'Stop' }
                        if ($MgCtx.Scopes)   { $ConnectSplat['Scopes']   = $MgCtx.Scopes }
                        if ($MgCtx.TenantId) { $ConnectSplat['TenantId'] = $MgCtx.TenantId }
                        if ($MgCtx.ClientId) { $ConnectSplat['ClientId'] = $MgCtx.ClientId }
                        $WamWasEnabled = $false
                        if ($IsWindows) {
                            try {
                                if (-not (Get-MgGraphOption -ErrorAction Stop).DisableLoginByWAM) {
                                    Set-MgGraphOption -DisableLoginByWAM $true -ErrorAction Stop
                                    $WamWasEnabled = $true
                                }
                            } catch {
                                Write-Debug "WAM state could not be determined or changed; skipping WAM disable. $_"
                            }
                        }
                        try {
                            $null = Disconnect-MgGraph -ErrorAction Stop
                            $null = Connect-MgGraph @ConnectSplat
                            Invoke-MgGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleAssignmentScheduleRequests' -Body $Request -Verbose:$false -ErrorAction Stop
                        } catch {
                            $RetryErr  = Convert-GraphHttpException $PSItem
                            $RetryMsgs = "$($RetryErr.FullyQualifiedErrorId) $($RetryErr.Exception.Message) $($PSItem.Exception.Message)"
                            if ($RetryMsgs -match 'RoleAssignmentRequestAcrsValidationFailed') {
                                $AcrsMsg = "Your session requires step-up re-authentication (ACRS) and automatic re-authentication failed. " +
                                    "Open a new PowerShell session and run 'Connect-MgGraph' to obtain a fresh token, then retry. " +
                                    "On Windows, if the issue persists after reconnecting, try: Set-MgGraphOption -DisableLoginByWAM `$true"
                                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                                    [System.Exception]::new($AcrsMsg, $RetryErr.Exception),
                                    'RoleAssignmentRequestAcrsValidationFailed',
                                    [System.Management.Automation.ErrorCategory]::AuthenticationError, $null))
                            } else {
                                $PSCmdlet.WriteError($RetryErr)
                            }
                            continue
                        } finally {
                            if ($WamWasEnabled) {
                                try { Set-MgGraphOption -DisableLoginByWAM $false -ErrorAction SilentlyContinue } catch {
                                    Write-Debug "WAM state could not be restored. $_"
                                }
                            }
                        }
                    } elseif ($AllMsgs -notmatch 'RoleAssignmentRequestPolicyValidationFailed') {
                        $PSCmdlet.WriteError($Err)
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
