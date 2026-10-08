function Enable-OPIMEntraIDGroup {
    <#
    .SYNOPSIS
    Activate an eligible PIM group membership or ownership.
    .DESCRIPTION
    Submits a SelfActivate request for a PIM for Groups eligible assignment.
    The group is named by its display name, or by the form tab completion offers for the GroupName
    parameter ('Group - member (id)'). A display name means the membership: add -AccessType Owner for
    the ownership. Two groups with the same display name are refused with AmbiguousName and nothing
    is activated; give the tab-completed form of the one you mean. A name that matches no eligible
    assignment is written as an EligibleRoleNotFound error. Several names are resolved one by one,
    each on its own, so a name that fails does not stop the next one.
    The request is reported by the status Graph gives it: a request that failed, was denied or was
    canceled is written as an ActivationRequestFailed error, and one that waits for approval or is
    still being provisioned is returned with a warning.
    A membership or ownership that is already active (listed by Get-OPIMEntraIDGroup -Activated) is
    not requested again: a warning is written and nothing is sent for it, and when that list cannot
    be read, its error is written and nothing more is sent.
    .EXAMPLE
    Get-OPIMEntraIDGroup | Enable-OPIMEntraIDGroup
    Activate all eligible PIM group assignments for 1 hour.
    .EXAMPLE
    Enable-OPIMEntraIDGroup 'Finance Team' -Justification 'Project work'
    Activates the membership of the group by its display name.
    .EXAMPLE
    Enable-OPIMEntraIDGroup 'Finance Team' -AccessType Owner
    Activates the ownership of the group. Without -AccessType a group name means the membership.
    .EXAMPLE
    Enable-OPIMEntraIDGroup 'Finance Team - member (elig-001)'
    The form tab completion offers, with the schedule id in parentheses, still works and names its
    own access type.
    .EXAMPLE
    Enable-OPIMEntraIDGroup <tab>
    Tab complete all eligible PIM groups. A name that is unique is offered bare; one that is not is
    offered in the longer form.
    .EXAMPLE
    Get-OPIMEntraIDGroup -AccessType member | Enable-OPIMEntraIDGroup -Hours 4 -Justification 'Project work'
    Activate all eligible group memberships for 4 hours with justification.
    .OUTPUTS
    PSCustomObject (tagged as Omnicit.PIM.GroupAssignmentScheduleRequest): the activation request,
    with the status Graph gave it (the last status read, with -Wait).
    .PARAMETER Group
    Eligible group schedule object piped from Get-OPIMEntraIDGroup. Used when activating
    by object rather than by name. Mutually exclusive with -GroupName.
    .PARAMETER GroupName
    The display name of the eligible group, or the tab-completed form the argument completer offers
    ('Group - member (id)'). A display name means the membership unless -AccessType says otherwise,
    is compared exactly, without regard to letter case, and takes no wildcards. Accepts multiple
    values, each resolved on its own; -AccessType applies to every one of them. Several matches are
    refused with AmbiguousName. Mutually exclusive with -Group.
    .PARAMETER Identity
    The schedule item ID from Get-OPIMEntraIDGroup (the id property) to activate directly without
    a name. An id that matches more than one schedule is refused with AmbiguousName. Mutually
    exclusive with -Group and -GroupName.
    .PARAMETER Justification
    Free-text justification for the activation request. May be required by your PIM policy.
    .PARAMETER TicketNumber
    Ticket or work item number associated with this activation for auditing purposes.
    .PARAMETER TicketSystem
    Name of the ticket system that issued the above ticket number, e.g. ServiceNow or Jira.
    .PARAMETER Hours
    Activation duration in hours, from 1 to 24. Defaults to 1. Ignored when -Until is specified. Your PIM
    policy can allow less; a longer request is refused by the policy as before.
    .PARAMETER NotBefore
    Date and time when the group activation begins. Defaults to the current date and time. A time
    without an offset, such as '4pm', is local time; it is sent to Graph in UTC.
    .PARAMETER Until
    Explicit end date and time for the activation. Takes precedence over -Hours when specified.
    A time without an offset, such as '5pm', is local time; it is sent to Graph in UTC.
    Aliased as -NotAfter.
    .PARAMETER AccessType
    Member or Owner. A group display name means the membership unless -AccessType Owner is given;
    a group you hold only as owner is then written as EligibleRoleNotFound, and the message names
    -AccessType Owner. It applies to every name in -GroupName. The tab-completed form names its
    access type itself and needs no -AccessType, but a form that -AccessType excludes is not found.
    Applies to a name, and cannot be combined with piped objects (-Group) or -Identity: piping
    objects in together with -AccessType selects the -GroupName parameter set, so an interactive
    host asks for -GroupName instead of failing to bind.
    .PARAMETER Wait
    Wait while the request is in progress before returning: the request status is read every 2
    seconds, up to -TimeoutSeconds, and the group is then reported by the last status, which is
    written back onto the returned request. A failed read is written as its own error for that group
    only.
    .PARAMETER TimeoutSeconds
    With -Wait, the most seconds to wait for the request to finish, counted from the start of the
    wait. Defaults to 300. A request that waits for approval ends the wait at once, with a warning;
    one still in progress at the limit is written as an ActivationWaitTimedOut error and stays
    submitted.
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
        [Parameter(ParameterSetName = 'ByIdentity', Mandatory)]
        [string]$Identity,
        [Parameter(Position = 1)][string]$Justification,
        [string]$TicketNumber,
        [string]$TicketSystem,
        [Parameter(Position = 2)][ValidateRange(1, 24)][int]$Hours = 1,
        [ValidateNotNullOrEmpty()][DateTime]$NotBefore = [DateTime]::Now,
        [DateTime][Alias('NotAfter')]$Until,
        [Parameter(ParameterSetName = 'GroupName')]
        [ValidateSet('Member', 'Owner')]
        [string]$AccessType,
        [Switch]$Wait,
        [ValidateRange(1, 86400)][int]$TimeoutSeconds = 300
    )
    process {
        Initialize-OPIMAuth
        if ($Identity) {
            try {
                $FoundByIdentity = @(Get-OPIMEntraIDGroup -Identity $Identity -ErrorAction Stop)
            } catch {
                # OPIM-12: the listing failed; report it as itself and stop for this identity.
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            if ($FoundByIdentity.Count -gt 1) {
                # Never the first of several: refuse with the candidates and act on none.
                $PSCmdlet.WriteError((New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Group `
                    -Name $Identity -Status Both -Candidate $FoundByIdentity -Identity))
                return
            }
            $Group = $FoundByIdentity | Select-Object -First 1
            if (-not $Group) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("No eligible PIM group assignment found with identity '$Identity'.")) `
                    -ErrorId 'IdentityNotFound' `
                    -Category ObjectNotFound `
                    -TargetObject $Identity `
                    -Cmdlet $PSCmdlet
                return
            }
        }
        $ResolvedGroups = if ($GroupName) {
            $ResolveParams = @{ Pillar = 'Group'; FilterParameter = 'AccessType'; ErrorAction = 'Stop' }
            if ($PSBoundParameters.ContainsKey('AccessType')) { $ResolveParams.AccessType = $AccessType.ToLowerInvariant() }
            foreach ($EachName in $GroupName) {
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
            @($Group)
        }

        $ActivePosts = $null
        $ActiveReadFailed = $false
        foreach ($Group in $ResolvedGroups) {
            # Skip already-active instances piped from Get-OPIMEntraIDGroup -All
            if ($Group.PSObject.TypeNames -contains 'Omnicit.PIM.GroupAssignmentScheduleInstance') {
                Write-Verbose "Skipping already-active group assignment: $($Group.group.displayName) ($($Group.accessId))"
                continue
            }
            # OPIM-39: never send a second request for a membership or ownership that is already
            # active -- a repeated request can end the active one. A list that cannot be read is no
            # proof that nothing is active, so nothing more is sent (G3).
            if ($ActiveReadFailed) { continue }
            if ($null -eq $ActivePosts) {
                try {
                    $ActivePosts = @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop)
                } catch {
                    Remove-OPIMErrorRecord -Record $PSItem
                    $PSCmdlet.WriteError($PSItem)
                    $ActiveReadFailed = $true
                    continue
                }
            }
            $Label = (Get-OPIMScheduleName -Pillar Group -InputObject $Group).Label
            if (@($ActivePosts | Where-Object {
                        [string]::Equals($_.groupId, $Group.groupId, [System.StringComparison]::OrdinalIgnoreCase) -and
                        [string]::Equals($_.accessId, $Group.accessId, [System.StringComparison]::OrdinalIgnoreCase)
                    }).Count -gt 0) {
                $PSCmdlet.WriteWarning("$Label is already active, so no new request was sent and the active assignment is left as it is.")
                continue
            }
            # OPIM-18: a time without an offset is local time; Graph gets it in UTC.
            $ScheduleInfo = @{
                startDateTime = $NotBefore.ToUniversalTime().ToString('o')
                expiration    = @{}
            }
            $Expiration = $ScheduleInfo.expiration
            if ($Until) {
                $Expiration.type        = 'AfterDateTime'
                $Expiration.endDateTime = $Until.ToUniversalTime().ToString('o')
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
                $GraphUri = 'v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests'
                $Response = try {
                    Invoke-OPIMGraphRequest -Method POST -Uri $GraphUri -Body $Request
                } catch {
                    Remove-OPIMErrorRecord -Record $PSItem
                    $Err = $PSItem
                    if (-not (ConvertTo-PolicyValidationError -CaughtError $Err -ResourceType 'group' -Cmdlet $PSCmdlet)) {
                        $PSCmdlet.WriteError($Err)
                    }
                    continue
                }
                if ($null -eq $Response) { continue }

                # Rehydrate group info from the eligibility schedule
                if (-not $Response.group) { $Response['group'] = $Group.group }

                # Convert to PSCustomObject so custom Format views apply (hashtable uses Key/Value formatter).
                $Out = [PSCustomObject]$Response
                $Out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleRequest')
                $Status = [string]$Out.status
                if ($Wait) {
                    # OPIM-14: poll while the request is in progress, up to -TimeoutSeconds, counted in UTC.
                    $Deadline = (Get-Date -AsUTC).AddSeconds($TimeoutSeconds)
                    $PollUri = "v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests/$($Out.id)"
                    $PollFailed = $false
                    $TimedOut = $false
                    while ((Get-OPIMRequestOutcome -Status $Status) -eq 'InProgress') {
                        if ((Get-Date -AsUTC) -ge $Deadline) { $TimedOut = $true; break }
                        Start-Sleep -Seconds 2
                        try {
                            $Status = [string](Invoke-OPIMGraphRequest -Uri $PollUri).status
                        } catch {
                            # A poll that fails is reported as itself for this group only.
                            Remove-OPIMErrorRecord -Record $PSItem
                            $PSCmdlet.WriteError($PSItem)
                            $PollFailed = $true
                            break
                        }
                    }
                    if ($PollFailed) { continue }
                    if ($TimedOut) {
                        $Out.status = $Status
                        $PSCmdlet.WriteError((New-OPIMRequestError -ErrorId ActivationWaitTimedOut -Name $Label `
                            -Status $Status -TimeoutSeconds $TimeoutSeconds -Request $Out))
                        continue
                    }
                }
                Write-OPIMRequestOutcome -Request $Out -Status $Status -Name $Label -Cmdlet $PSCmdlet
            }
        }
    }
}
