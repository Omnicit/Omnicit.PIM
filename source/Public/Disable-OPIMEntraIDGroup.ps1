function Disable-OPIMEntraIDGroup {
    <#
    .SYNOPSIS
    Deactivate an active PIM group membership or ownership.
    .DESCRIPTION
    Submits a selfDeactivate request for an active PIM for Groups assignment.
    The GroupName parameter supports tab completion for currently active group memberships.
    .EXAMPLE
    Get-OPIMEntraIDGroup -Activated | Disable-OPIMEntraIDGroup
    Deactivate all currently active PIM group assignments.
    .EXAMPLE
    Disable-OPIMEntraIDGroup <tab>
    Tab complete active PIM group assignments.
    .OUTPUTS
    System.Collections.Hashtable (tagged as Omnicit.PIM.GroupAssignmentScheduleRequest)
    .PARAMETER Group
    Active PIM group assignment schedule instance object piped from Get-OPIMEntraIDGroup -Activated.
    .PARAMETER GroupName
    Name of the active PIM group assignment to deactivate. Supports tab completion to currently active group assignments.
    .PARAMETER Identity
    The schedule instance ID from Get-OPIMEntraIDGroup -Activated (the id property) to deactivate
    directly without tab completion. Mutually exclusive with -Group and -GroupName.
    .PARAMETER AccessType
    Member or Owner. A group display name means the membership unless -AccessType Owner is given.
    The tab-completed form names its access type itself.
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
            return $Out
        }
    }
}
