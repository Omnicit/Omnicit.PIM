function Disable-OPIMEntraIDGroup {
    <#
    .SYNOPSIS
    Deactivate an active PIM group membership or ownership.
    .DESCRIPTION
    Submits a selfDeactivate request for an active PIM for Groups assignment.
    The group is named by its display name, or by the form tab completion offers for the GroupName
    parameter for your currently active group assignments. A display name means the membership: add
    -AccessType Owner for the ownership. Two groups with the same display name are refused with
    AmbiguousName and nothing is deactivated. A name that matches no active assignment is written as
    a (non-terminating) ActiveRoleNotFound error; when the assignment is eligible but not active, the
    message says it is already deactivated.
    The request is reported by the status Graph gives it: a deactivation that does not end Revoked
    is written as an ActivationRequestFailed error, and one that waits for approval or is still
    being processed is returned with a warning.
    .EXAMPLE
    Get-OPIMEntraIDGroup -Activated | Disable-OPIMEntraIDGroup
    Deactivate all currently active PIM group assignments.
    .EXAMPLE
    Disable-OPIMEntraIDGroup 'Finance Team'
    Deactivates the membership of the group by its display name.
    .EXAMPLE
    Disable-OPIMEntraIDGroup 'Finance Team' -AccessType Owner
    Deactivates the ownership of the group. Without -AccessType a group name means the membership.
    .EXAMPLE
    Disable-OPIMEntraIDGroup <tab>
    Tab complete active PIM group assignments. A name that is unique is offered bare.
    .OUTPUTS
    System.Collections.Hashtable (tagged as Omnicit.PIM.GroupAssignmentScheduleRequest)
    .PARAMETER Group
    Active PIM group assignment schedule instance object piped from Get-OPIMEntraIDGroup -Activated.
    .PARAMETER GroupName
    The display name of the active PIM group assignment to deactivate, or the tab-completed form the
    argument completer offers for your currently active group assignments. A display name means the
    membership unless -AccessType says otherwise, is compared exactly, without regard to letter
    case, and takes no wildcards. Several matches are refused with AmbiguousName.
    .PARAMETER Identity
    The schedule instance ID from Get-OPIMEntraIDGroup -Activated (the id property) to deactivate
    directly without a name. An id that matches more than one instance is refused with
    AmbiguousName. Mutually exclusive with -Group and -GroupName.
    .PARAMETER AccessType
    Member or Owner. A group display name means the membership unless -AccessType Owner is given;
    a group you hold only as owner is then written as ActiveRoleNotFound, and the message names
    -AccessType Owner. The tab-completed form names its access type itself and needs no -AccessType,
    but a form that -AccessType excludes is not found. Applies to a name, and cannot be combined
    with piped objects (-Group) or -Identity: piping objects in together with -AccessType selects
    the -GroupName parameter set, so an interactive host asks for -GroupName instead of failing to
    bind.
    #>
    [Alias('Disable-PIMGroup')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'GroupName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'GroupObject', Mandatory, ValueFromPipeline)]
        $Group,
        [ArgumentCompleter([GroupActivatedCompleter])]
        [Parameter(ParameterSetName = 'GroupName', Mandatory, Position = 0)]
        [String]$GroupName,
        [Parameter(ParameterSetName = 'ByIdentity', Mandatory)]
        [String]$Identity,
        [Parameter(ParameterSetName = 'GroupName')]
        [ValidateSet('Member', 'Owner')]
        [string]$AccessType
    )
    process {
        Initialize-OPIMAuth
        if ($Identity) {
            try {
                $FoundByIdentity = @(Get-OPIMEntraIDGroup -Activated -Identity $Identity -ErrorAction Stop)
            } catch {
                # OPIM-12: the listing failed; report it as itself and stop for this identity.
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            if ($FoundByIdentity.Count -gt 1) {
                # Never the first of several: refuse with the candidates and act on none.
                $PSCmdlet.WriteError((New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Group `
                    -Name $Identity -Status Active -Candidate $FoundByIdentity -Identity))
                return
            }
            $Group = $FoundByIdentity | Select-Object -First 1
            if (-not $Group) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("No active PIM group assignment found with identity '$Identity'.")) `
                    -ErrorId 'IdentityNotFound' `
                    -Category ObjectNotFound `
                    -TargetObject $Identity `
                    -Cmdlet $PSCmdlet
                return
            }
        }
        if ($GroupName) {
            $ResolveParams = @{ Pillar = 'Group'; Status = 'Active'; FilterParameter = 'AccessType'; ErrorAction = 'Stop' }
            if ($PSBoundParameters.ContainsKey('AccessType')) { $ResolveParams.AccessType = $AccessType.ToLowerInvariant() }
            try {
                $Group = Resolve-OPIMSchedule -Name $GroupName @ResolveParams
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }

        # Skip eligible-only schedules piped from Get-OPIMEntraIDGroup -All
        if ($Group.PSObject.TypeNames -contains 'Omnicit.PIM.GroupEligibilitySchedule') {
            Write-Verbose "Skipping eligible-only group assignment: $($Group.group.displayName) ($($Group.accessId))"
            return
        }

        $Request = @{
            action      = 'selfDeactivate'
            accessId    = $Group.accessId
            groupId     = $Group.groupId
            principalId = $Group.principalId
        }

        $DisplayName = $Group.group.displayName
        if ($PSCmdlet.ShouldProcess(
                "$DisplayName ($($Group.accessId))",
                'Deactivate PIM Group'
            )) {
            $Response = try {
                Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests' -Body $Request
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $Err = $PSItem
                if (-not (ConvertTo-ActiveDurationTooShortError -CaughtError $Err -ResourceType 'group' -Cmdlet $PSCmdlet)) {
                    $PSCmdlet.WriteError($Err)
                }
                return
            }

            if (-not $Response.group) { $Response['group'] = $Group.group }
            # Convert to PSCustomObject so custom Format views apply (hashtable uses Key/Value formatter).
            $Out = [PSCustomObject]$Response
            $Out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleRequest')
            $Label = (Get-OPIMScheduleName -Pillar Group -InputObject $Group).Label
            Write-OPIMRequestOutcome -Request $Out -Status $Out.status -Name $Label -Deactivate -Cmdlet $PSCmdlet
            return
        }
    }
}
