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
    #>
    [Alias('Enable-PIMGroup')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'GroupName')]
    [OutputType([System.Collections.Hashtable])]
    param(
        #Eligible group schedule object from Get-OPIMEntraIDGroup.
        [Parameter(ParameterSetName = 'GroupObject', Mandatory, ValueFromPipeline)]
        $Group,
        #Friendly name of the eligible group assignment. Supports tab completion. Accepts multiple values.
        [Parameter(Position = 0, ParameterSetName = 'GroupName', Mandatory)]
        [ArgumentCompleter([GroupEligibleCompleter])]
        [string[]]$GroupName,
        #Justification for the activation. May be required by your PIM policy.
        [string]$Justification,
        #Ticket number associated with this activation.
        [string]$TicketNumber,
        #Ticket system containing the above ticket number.
        [string]$TicketSystem,
        #Duration in hours. Defaults to 1 hour.
        [ValidateNotNullOrEmpty()][int]$Hours = 1,
        #Date and time when the activation begins. Defaults to now.
        [ValidateNotNullOrEmpty()][DateTime]$NotBefore = [DateTime]::Now,
        #Explicit end date/time for the activation. Takes precedence over -Hours when specified.
        [DateTime][Alias('NotAfter')]$Until,
        #Wait until the group assignment is fully active before returning.
        [Switch]$Wait
    )
    process {
        $resolvedGroups = if ($GroupName) {
            $GroupName | ForEach-Object { Resolve-RoleByName -Group $_ }
        } else {
            @($Group)
        }

        foreach ($Group in $resolvedGroups) {

        $scheduleInfo = @{
            startDateTime = $NotBefore.ToString('o')
            expiration    = @{}
        }
        $expiration = $scheduleInfo.expiration
        if ($Until) {
            $expiration.type        = 'AfterDateTime'
            $expiration.endDateTime = $Until.ToString('o')
            [string]$expireTime     = $Until
        } else {
            $expiration.type    = 'AfterDuration'
            $expiration.duration = [System.Xml.XmlConvert]::ToString([TimeSpan]::FromHours($Hours))
            [string]$expireTime  = $NotBefore.AddHours($Hours)
        }

        $request = @{
            action       = 'selfActivate'
            accessId     = $Group.accessId
            groupId      = $Group.groupId
            principalId  = $Group.principalId
            justification = $Justification
            scheduleInfo = $scheduleInfo
            ticketInfo   = @{
                ticketNumber = $TicketNumber
                ticketSystem = $TicketSystem
            }
        }

        $displayName = $Group.group.displayName
        if ($PSCmdlet.ShouldProcess(
                "$displayName ($($Group.accessId))",
                "Activate PIM Group from $NotBefore to $expireTime"
            )) {
            $response = try {
                Invoke-MgGraphRequest -Method POST -Uri 'v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests' -Body $request -Verbose:$false -ErrorAction Stop
            } catch {
                $err = Convert-GraphHttpException $PSItem
                if (-not ($err.FullyQualifiedErrorId -like 'RoleAssignmentRequestPolicyValidationFailed*')) {
                    $PSCmdlet.WriteError($err)
                    continue
                }
                if ($err -match 'JustificationRule') {
                    $err.ErrorDetails = 'Your PIM policy requires a justification for this group. Use the -Justification parameter.'
                }
                if ($err -match 'ExpirationRule') {
                    $err.ErrorDetails = 'Your PIM policy requires a shorter expiration. Use -NotAfter to specify an earlier time.'
                }
                $PSCmdlet.WriteError($err)
                continue
            }

            # Rehydrate group info from the eligibility schedule
            if (-not $response.group) { $response['group'] = $Group.group }

            if ($Wait) {
                $pollId = $response.id
                do {
                    Start-Sleep 2
                    $status = (Invoke-MgGraphRequest -Verbose:$false -Uri "v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests/$pollId" -ErrorAction Stop).status
                } while ($status -like 'Pending*')
            }

            # Convert to PSCustomObject so custom Format views apply (hashtable uses Key/Value formatter).
            $out = [PSCustomObject]$response
            $out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleRequest')
            $out
        }
        } # end foreach
    }
}
