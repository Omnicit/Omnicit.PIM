function Enable-OPIMEntraIDGroup {
    <#
    .SYNOPSIS
    Activate an eligible PIM group membership or ownership.
    .DESCRIPTION
    Submits a SelfActivate request for a PIM for Groups eligible assignment.
    The GroupName parameter supports tab completion for available eligible groups.
    .EXAMPLE
    Get-OPIMEntraIDGroup | Enable-OPIMEntraIDGroup
    Activate all eligible PIM group assignments for 1 hour.
    .EXAMPLE
    Enable-OPIMEntraIDGroup <tab>
    Tab complete all eligible PIM groups.
    .EXAMPLE
    Get-OPIMEntraIDGroup -AccessType member | Enable-OPIMEntraIDGroup -Hours 4 -Justification 'Project work'
    Activate all eligible group memberships for 4 hours with justification.
    .OUTPUTS
    System.Collections.Hashtable (tagged as Omnicit.PIM.GroupAssignmentScheduleRequest)
    .PARAMETER Group
    Eligible group schedule object piped from Get-OPIMEntraIDGroup. Used when activating
    by object rather than by tab-completed name. Mutually exclusive with -GroupName.
    .PARAMETER GroupName
    Tab-completable name of the eligible group assignment in the format produced by the argument completer.
    Accepts multiple values. Mutually exclusive with -Group.
    .PARAMETER Justification
    Free-text justification for the activation request. May be required by your PIM policy.
    .PARAMETER TicketNumber
    Ticket or work item number associated with this activation for auditing purposes.
    .PARAMETER TicketSystem
    Name of the ticket system that issued the above ticket number, e.g. ServiceNow or Jira.
    .PARAMETER Hours
    Activation duration in hours. Defaults to 1. Ignored when -Until is specified.
    .PARAMETER NotBefore
    Date and time when the group activation begins. Defaults to the current date and time.
    .PARAMETER Until
    Explicit end date and time for the activation. Takes precedence over -Hours when specified.
    Aliased as -NotAfter.
    .PARAMETER Wait
    Wait until the group assignment is fully provisioned and active before returning.
    #>
    [Alias('Enable-PIMGroup')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'GroupName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'GroupObject', Mandatory, ValueFromPipeline)]
        $Group,
        [Parameter(Position = 0, ParameterSetName = 'GroupName', Mandatory)]
        [ArgumentCompleter([GroupEligibleCompleter])]
        [string[]]$GroupName,
        [string]$Justification,
        [string]$TicketNumber,
        [string]$TicketSystem,
        [ValidateNotNullOrEmpty()][int]$Hours = 1,
        [ValidateNotNullOrEmpty()][DateTime]$NotBefore = [DateTime]::Now,
        [DateTime][Alias('NotAfter')]$Until,
        [Switch]$Wait
    )
    process {
        $ResolvedGroups = if ($GroupName) {
            $GroupName | ForEach-Object { Resolve-RoleByName -Group $_ }
        } else {
            @($Group)
        }

        foreach ($Group in $ResolvedGroups) {
            $ScheduleInfo = @{
                startDateTime = $NotBefore.ToString('o')
                expiration    = @{}
            }
            $Expiration = $ScheduleInfo.expiration
            if ($Until) {
                $Expiration.type        = 'AfterDateTime'
                $Expiration.endDateTime = $Until.ToString('o')
                [string]$ExpireTime     = $Until
            } else {
                $Expiration.type     = 'AfterDuration'
                $Expiration.duration = [System.Xml.XmlConvert]::ToString([TimeSpan]::FromHours($Hours))
                [string]$ExpireTime  = $NotBefore.AddHours($Hours)
            }

            $Request = @{
                action        = 'selfActivate'
                accessId      = $Group.accessId
                groupId       = $Group.groupId
                principalId   = $Group.principalId
                justification = $Justification
                scheduleInfo  = $ScheduleInfo
                ticketInfo    = @{
                    ticketNumber = $TicketNumber
                    ticketSystem = $TicketSystem
                }
            }

            $DisplayName = $Group.group.displayName
            if ($PSCmdlet.ShouldProcess(
                    "$DisplayName ($($Group.accessId))",
                    "Activate PIM Group from $NotBefore to $ExpireTime"
                )) {
                $Response = try {
                    Invoke-MgGraphRequest -Method POST -Uri 'v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests' -Body $Request -Verbose:$false -ErrorAction Stop
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
                            Invoke-MgGraphRequest -Method POST -Uri 'v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests' -Body $Request -Verbose:$false -ErrorAction Stop
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
                        $JustMsg = 'Your PIM policy requires a justification for this group. Use the -Justification parameter.'
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

                # Rehydrate group info from the eligibility schedule
                if (-not $Response.group) { $Response['group'] = $Group.group }

                if ($Wait) {
                    $PollId = $Response.id
                    do {
                        Start-Sleep 2
                        $Status = (Invoke-MgGraphRequest -Verbose:$false -Uri "v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests/$PollId" -ErrorAction Stop).status
                    } while ($Status -like 'Pending*')
                }

                # Convert to PSCustomObject so custom Format views apply (hashtable uses Key/Value formatter).
                $Out = [PSCustomObject]$Response
                $Out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleRequest')
                $Out
            }
        }
    }
}
