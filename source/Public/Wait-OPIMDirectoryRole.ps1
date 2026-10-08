using namespace System.Collections.Generic
using namespace System.Management.Automation

function Wait-OPIMDirectoryRole {
    <#
    .SYNOPSIS
    Wait for Azure AD PIM directory role activation requests to finish.
    .DESCRIPTION
    Polls the Microsoft Graph API until each role activation request has finished. A request that
    reaches 'Provisioned' is waited for until its role assignment instance appears in the directory;
    a request Graph grants without one ('Granted', 'ScheduleCreated') is done at once. Useful after
    Enable-OPIMDirectoryRole when you need the role to be active before proceeding. The requests are
    polled in turn, in sequence, through the module's own Graph transport, and each one ends on its
    own, with its last status written back onto the request object (added when it has none):
    a request that waits for a decision, such as PendingApproval, ends its wait at once with a
    warning; one that failed, was denied or was canceled is written as an ActivationRequestFailed
    error; one still in progress -TimeoutSeconds after Graph created it (after the start of the
    wait when the request carries no readable creation time) is written as an
    ActivationWaitTimedOut error and stays submitted; and one whose status cannot be read is written
    as that error. A request whose end date has already passed is not polled at all: it is written
    as an ActivationAlreadyExpired error. All of them are non-terminating, so one request never ends
    the wait for the others. Times are compared in UTC.
    .EXAMPLE
    Enable-OPIMDirectoryRole -RoleName 'Global Administrator (...)' | Wait-OPIMDirectoryRole
    Enable a role and wait for it to be fully active.
    .EXAMPLE
    Get-OPIMDirectoryRole | Enable-OPIMDirectoryRole -Wait
    Enable all eligible roles and wait for each to be active (via the -Wait switch on Enable-OPIMDirectoryRole).
    .EXAMPLE
    Enable-OPIMDirectoryRole 'Global Administrator' | Wait-OPIMDirectoryRole -TimeoutSeconds 600 -PassThru
    Enable a role, wait up to 10 minutes for it, and return the active assignment.
    .OUTPUTS
    PSCustomObject: with -PassThru, the instances of the activated roles (tagged
    Omnicit.PIM.DirectoryAssignmentScheduleInstance) and the requests that ended without an instance
    (tagged Omnicit.PIM.DirectoryAssignmentScheduleRequest). Nothing without -PassThru.
    .PARAMETER RoleRequest
    Role activation request object piped from Enable-OPIMDirectoryRole. Contains the schedule request details used to poll for provisioning status.
    .PARAMETER Interval
    Polling interval in seconds between Graph API status checks. Default is 1 second.
    .PARAMETER TimeoutSeconds
    The most seconds to wait for each request, counted from the time Graph created it, or from the
    start of the wait when the request carries no readable creation time. Default is 300 seconds (5
    minutes), from 1 to 86400. A request still in progress at the limit is written as an
    ActivationWaitTimedOut error, and the wait for the other requests goes on. The old name
    -Timeout still works.
    .PARAMETER ThrottleLimit
    Accepted for compatibility and has no effect: the requests are polled in sequence. Default is 5.
    .PARAMETER PassThru
    When specified, returns the activated role schedule instances (tagged as
    Omnicit.PIM.DirectoryAssignmentScheduleInstance) of the requests that were provisioned, followed
    by the request objects that ended without an instance (Granted, ScheduleCreated, or waiting for
    a decision), each with its status written back.
    .PARAMETER NoSummary
    Skip the 1-second summary pause before returning results.
    #>
    [Alias('Wait-PIMADRole', 'Wait-PIMRole')]
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        $RoleRequest,
        [double]$Interval = 1,
        [Alias('Timeout')][ValidateRange(1, 86400)][int]$TimeoutSeconds = 300,
        $ThrottleLimit = 5,
        [Switch]$PassThru,
        [Switch]$NoSummary
    )
    begin {
        Initialize-OPIMAuth
        [List[PSObject]]$RoleRequests = [List[PSObject]]::new()
        # Bounded, so the per-request child id ($ParentId + 1 + index) can never overflow Int32.
        $ParentId = Get-Random -Maximum 1000000
    }
    process {
        # The end date is read as UTC and compared with UTC, whatever Kind or offset it arrives in.
        $EndTime = ConvertTo-OPIMUtcDateTime -Value $RoleRequest.scheduleInfo.expiration.endDateTime
        if ($null -ne $EndTime -and $EndTime -lt (Get-Date -AsUTC)) {
            # Ruling R-P5: an id of its own, since no existing one says "the end date has passed;
            # nothing to wait for". Written as this command, with the request as its target.
            Write-CmdletError -Message ([System.Exception]::new("$($RoleRequest.RoleName) role end date already expired at $($EndTime.ToLocalTime()). Skipping.")) `
                -ErrorId 'ActivationAlreadyExpired' -Category InvalidArgument -TargetObject $RoleRequest -Cmdlet $PSCmdlet
            return
        }
        $RoleRequests.Add($RoleRequest)
    }
    end {
        if ($PSBoundParameters.ContainsKey('ThrottleLimit')) {
            Write-Verbose "[Wait-OPIMDirectoryRole] -ThrottleLimit $ThrottleLimit has no effect: the requests are polled in sequence."
        }
        if ($RoleRequests.Count -eq 0) { return }

        # OPIM-14 / OPIM-16: each request has its own deadline, -TimeoutSeconds after its
        # createdDateTime read as UTC, or after the start of the wait when it has none that can be read.
        $WaitStart = Get-Date -AsUTC
        $Tracked = @{}
        foreach ($RequestItem in $RoleRequests) {
            $Created = ConvertTo-OPIMUtcDateTime -Value $RequestItem.createdDateTime
            $CountFrom = if ($null -ne $Created) { $Created } else { $WaitStart }
            # A request without a role name (a hand-made one, or a raw Graph answer) is named by its
            # id: Write-Progress refuses an empty -Activity with a terminating error, outside any try.
            $Label = (Get-OPIMScheduleName -Pillar Directory -InputObject $RequestItem).Label
            if ([string]::IsNullOrWhiteSpace($Label)) { $Label = "Request $($RequestItem.id)".Trim() }
            $Tracked[[string]$RequestItem.id] = @{
                Label       = $Label
                Deadline    = $CountFrom.AddSeconds($TimeoutSeconds)
                Status      = [string]$RequestItem.status
                Provisioned = $false
            }
        }
        $Pending = [List[PSObject]]::new($RoleRequests)
        $Activated = [List[PSObject]]::new()
        $Finished = [List[PSObject]]::new()
        Write-Progress -Id $ParentId -Activity 'Azure AD PIM Directory Role Activation'
        while ($Pending.Count -gt 0) {
            foreach ($RequestItem in @($Pending)) {
                $State = $Tracked[[string]$RequestItem.id]
                if (-not $State.Provisioned) {
                    $StatusUri = "v1.0/roleManagement/directory/roleAssignmentScheduleRequests/filterByCurrentUser(on='principal')?`$select=status&`$filter=id eq '$($RequestItem.id)'"
                    try {
                        $State.Status = [string](Invoke-OPIMGraphRequest -Uri $StatusUri).value.status
                    } catch {
                        # A poll that fails is reported as itself and ends the wait for this request only.
                        Remove-OPIMErrorRecord -Record $PSItem
                        $PSCmdlet.WriteError($PSItem)
                        $null = $Pending.Remove($RequestItem)
                        continue
                    }
                    # Write the status back onto the request; a request without one gets it added.
                    $StatusProperty = $RequestItem.PSObject.Properties['status']
                    if ($null -eq $StatusProperty) {
                        $RequestItem | Add-Member -NotePropertyName status -NotePropertyValue $State.Status
                    } elseif ($StatusProperty.IsSettable) {
                        $StatusProperty.Value = $State.Status
                    }
                    if ($State.Status -eq 'Provisioned') {
                        $State.Provisioned = $true
                    } elseif ((Get-OPIMRequestOutcome -Status $State.Status) -ne 'InProgress') {
                        # Granted or ScheduleCreated (no instance to wait for), a request that waits for
                        # a decision, or a failure: reported now, and the wait for it ends.
                        $Reported = Write-OPIMRequestOutcome -Request $RequestItem -Status $State.Status -Name $State.Label -Cmdlet $PSCmdlet
                        if ($null -ne $Reported) { $Finished.Add($Reported) }
                        $null = $Pending.Remove($RequestItem)
                        continue
                    }
                }
                if ($State.Provisioned) {
                    $InstanceUri = "v1.0/roleManagement/directory/roleAssignmentScheduleInstances/filterByCurrentUser(on='principal')?`$select=startDateTime&`$filter=roleAssignmentScheduleId eq '$($RequestItem.targetScheduleId)'"
                    try {
                        $Instances = (Invoke-OPIMGraphRequest -Uri $InstanceUri).value
                    } catch {
                        Remove-OPIMErrorRecord -Record $PSItem
                        $PSCmdlet.WriteError($PSItem)
                        $null = $Pending.Remove($RequestItem)
                        continue
                    }
                    if ($Instances) {
                        $StartedAt = ConvertTo-OPIMUtcDateTime -Value (@($Instances)[0].startDateTime)
                        $ProgressStatus = if ($null -ne $StartedAt) { "Activated at $($StartedAt.ToLocalTime())" } else { 'Activated' }
                        Write-Progress -ParentId $ParentId -Id ($ParentId + 1 + $RoleRequests.IndexOf($RequestItem)) -Activity $State.Label -Status $ProgressStatus -PercentComplete 100
                        $Activated.Add($RequestItem)
                        $null = $Pending.Remove($RequestItem)
                        continue
                    }
                }
                # Still in progress, or Provisioned with no instance yet: the wait for this request
                # ends at its deadline, written as an error of its own (Ruling P3: non-terminating).
                if ((Get-Date -AsUTC) -ge $State.Deadline) {
                    $PSCmdlet.WriteError((New-OPIMRequestError -ErrorId ActivationWaitTimedOut -Name $State.Label `
                        -Status $State.Status -TimeoutSeconds $TimeoutSeconds -Request $RequestItem))
                    $null = $Pending.Remove($RequestItem)
                }
            }
            if ($Pending.Count -gt 0) { Start-Sleep -Seconds $Interval }
        }
        if (-not $NoSummary) { Start-Sleep 1 }
        Write-Progress -Id $ParentId -Activity 'Azure AD PIM Directory Role Activation' -Completed

        if ($PassThru) {
            # The instances of the provisioned requests, then the requests that ended without one.
            if ($Activated.Count -gt 0) {
                $ScheduleIds = @($Activated | ForEach-Object { [string]$_.targetScheduleId })
                Get-OPIMDirectoryRole -Activated |
                    Where-Object { $_.roleAssignmentScheduleId -in $ScheduleIds }
            }
            foreach ($Reported in $Finished) { $Reported }
        }
    }
}
