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
    System.Collections.Hashtable (tagged as Omnicit.PIM.GroupAssignmentScheduleRequest)
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
    Activation duration in hours. Defaults to 1. Ignored when -Until is specified.
    .PARAMETER NotBefore
    Date and time when the group activation begins. Defaults to the current date and time.
    .PARAMETER Until
    Explicit end date and time for the activation. Takes precedence over -Hours when specified.
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
        [Parameter(ParameterSetName = 'ByIdentity', Mandatory)]
        [string]$Identity,
        [Parameter(Position = 1)][string]$Justification,
        [string]$TicketNumber,
        [string]$TicketSystem,
        [Parameter(Position = 2)][ValidateNotNullOrEmpty()][int]$Hours = 1,
        [ValidateNotNullOrEmpty()][DateTime]$NotBefore = [DateTime]::Now,
        [DateTime][Alias('NotAfter')]$Until,
        [Parameter(ParameterSetName = 'GroupName')]
        [ValidateSet('Member', 'Owner')]
        [string]$AccessType,
        [Switch]$Wait
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

        foreach ($Group in $ResolvedGroups) {
            # Skip already-active instances piped from Get-OPIMEntraIDGroup -All
            if ($Group.PSObject.TypeNames -contains 'Omnicit.PIM.GroupAssignmentScheduleInstance') {
                Write-Verbose "Skipping already-active group assignment: $($Group.group.displayName) ($($Group.accessId))"
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

                if ($Wait) {
                    $PollId = $Response.id
                    do {
                        Start-Sleep 2
                        $Status = (Invoke-OPIMGraphRequest -Uri "v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests/$PollId").status
                    } while ($Status -like 'Pending*')
                }

                # Convert to PSCustomObject so custom Format views apply (hashtable uses Key/Value formatter).
                $Out = [PSCustomObject]$Response
                $Out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleRequest')
                $Label = (Get-OPIMScheduleName -Pillar Group -InputObject $Group).Label
                Write-OPIMRequestOutcome -Request $Out -Status $Out.status -Name $Label -Cmdlet $PSCmdlet
            }
        }
    }
}
