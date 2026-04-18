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
        [String]$Identity
    )
    process {
        Initialize-OPIMAuth
        if ($Identity) {
            $Group = Get-OPIMEntraIDGroup -Activated -Identity $Identity | Select-Object -First 1
            if (-not $Group) {
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("No active PIM group assignment found with identity '$Identity'."),
                    'IdentityNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Identity))
                return
            }
        }
        if ($GroupName) { $Group = Resolve-RoleByName -Group -Activated $GroupName }

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
                $Err = $PSItem
                $IsActiveToShort = ($Err.FullyQualifiedErrorId -like 'ActiveDurationTooShort*') -or
                                   ($Err.Exception.Message -match 'ActiveDurationTooShort')
                if (-not $IsActiveToShort) {
                    $PSCmdlet.WriteError($Err)
                    return
                }
                $CooldownMsg = 'You must wait at least 5 minutes after activating a group before you can deactivate it.'
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new($CooldownMsg, $Err.Exception),
                    'ActiveDurationTooShort',
                    [System.Management.Automation.ErrorCategory]::ResourceUnavailable, $null))
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
