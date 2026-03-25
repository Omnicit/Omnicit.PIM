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
    #>
    [Alias('Disable-PIMGroup')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'GroupName')]
    [OutputType([System.Collections.Hashtable])]
    param(
        #Active group assignment object from Get-OPIMEntraIDGroup -Activated.
        [Parameter(ParameterSetName = 'GroupObject', Mandatory, ValueFromPipeline)]
        $Group,
        #Name of the active group assignment to deactivate. Supports tab completion.
        [ArgumentCompleter([GroupActivatedCompleter])]
        [Parameter(ParameterSetName = 'GroupName', Mandatory, Position = 0)]
        [String]$GroupName
    )
    process {
        if ($GroupName) { $Group = Resolve-RoleByName -Group -Activated $GroupName }

        $request = @{
            action      = 'selfDeactivate'
            accessId    = $Group.accessId
            groupId     = $Group.groupId
            principalId = $Group.principalId
        }

        $displayName = $Group.group.displayName
        if ($PSCmdlet.ShouldProcess(
                "$displayName ($($Group.accessId))",
                'Deactivate PIM Group'
            )) {
            $response = try {
                Invoke-MgGraphRequest -Method POST -Uri 'v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests' -Body $request -Verbose:$false -ErrorAction Stop
            } catch {
                $err = Convert-GraphHttpException $PSItem
                if (-not ($err.FullyQualifiedErrorId -like 'ActiveDurationTooShort*')) {
                    $PSCmdlet.WriteError($err)
                    return
                }
                $err.ErrorDetails = 'You must wait at least 5 minutes after activating a group before you can deactivate it.'
                $PSCmdlet.WriteError($err)
                return
            }

            if (-not $response.group) { $response['group'] = $Group.group }
            # Convert to PSCustomObject so custom Format views apply (hashtable uses Key/Value formatter).
            $out = [PSCustomObject]$response
            $out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleRequest')
            return $out
        }
    }
}
