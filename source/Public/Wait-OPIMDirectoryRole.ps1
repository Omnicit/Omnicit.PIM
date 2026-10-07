using namespace System.Collections.Generic
using namespace System.Management.Automation

function Wait-OPIMDirectoryRole {
    <#
    .SYNOPSIS
    Wait for an Azure AD PIM directory role activation request to fully provision.
    .DESCRIPTION
    Polls the Microsoft Graph API until the role activation request reaches 'Provisioned' status
    and the role assignment instance appears in the directory. Useful after Enable-OPIMDirectoryRole
    when you need the role to be active before proceeding. The requests are polled in turn, in
    sequence, through the module's own Graph transport; a request whose status is neither pending
    nor Provisioned is written as a non-terminating error, and a request that has not completed
    within -Timeout seconds of its creation ends the command with a terminating error.
    .EXAMPLE
    Enable-OPIMDirectoryRole -RoleName 'Global Administrator (...)' | Wait-OPIMDirectoryRole
    Enable a role and wait for it to be fully active.
    .EXAMPLE
    Get-OPIMDirectoryRole | Enable-OPIMDirectoryRole -Wait
    Enable all eligible roles and wait for each to be active (via the -Wait switch on Enable-OPIMDirectoryRole).
    .OUTPUTS
    System.Collections.Hashtable (tagged as Omnicit.PIM.DirectoryAssignmentScheduleInstance) when -PassThru is used.
    .PARAMETER RoleRequest
    Role activation request object piped from Enable-OPIMDirectoryRole. Contains the schedule request details used to poll for provisioning status.
    .PARAMETER Interval
    Polling interval in seconds between Graph API status checks. Default is 1 second.
    .PARAMETER Timeout
    Maximum number of seconds to wait for a role activation to complete before timing out. Default is 600 seconds (10 minutes).
    .PARAMETER ThrottleLimit
    Accepted for compatibility and has no effect: the requests are polled in sequence. Default is 5.
    .PARAMETER PassThru
    When specified, returns the activated role schedule instances (tagged as Omnicit.PIM.DirectoryAssignmentScheduleInstance) after all activations complete.
    .PARAMETER NoSummary
    Skip the 1-second summary pause before returning results.
    #>
    [Alias('Wait-PIMADRole', 'Wait-PIMRole')]
    [OutputType([System.Collections.Hashtable])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        $RoleRequest,
        [double]$Interval = 1,
        $Timeout = 600,
        $ThrottleLimit = 5,
        [Switch]$PassThru,
        [Switch]$NoSummary
    )
    begin {
        Initialize-OPIMAuth
        [List[PSObject]]$RoleRequests = [List[PSObject]]::new()
        $parentId = Get-Random
        $effectiveTimeout = $Timeout
    }
    process {
        if ($RoleRequest.scheduleInfo.expiration.endDateTime) {
            $localEndTime = [datetime]$RoleRequest.scheduleInfo.expiration.endDateTime
            if ($localEndTime.ToUniversalTime() -lt [DateTime]::UtcNow) {
                Write-CmdletError -Message ([System.Exception]::new("$($RoleRequest.RoleName) role end date already expired at $($localEndTime.ToLocalTime()). Skipping."))
                return
            }
        }
        $RoleRequests.Add($RoleRequest)
    }
    end {
        if ($PSBoundParameters.ContainsKey('ThrottleLimit')) {
            Write-Verbose "[Wait-OPIMDirectoryRole] -ThrottleLimit $ThrottleLimit has no effect: the requests are polled in sequence."
        }
        if ($RoleRequests.Count -eq 0) { return }
        $Pending = [System.Collections.Generic.List[PSObject]]::new($RoleRequests)
        $Provisioned = [System.Collections.Generic.HashSet[string]]::new()
        Write-Progress -Id $parentId -Activity 'Azure AD PIM Directory Role Activation'
        while ($Pending.Count -gt 0) {
            foreach ($RequestItem in @($Pending)) {
                $Name    = $RequestItem.roleDefinition.displayName
                $Created = [datetime]$RequestItem.createdDateTime
                try {
                    if (-not $Provisioned.Contains([string]$RequestItem.id)) {
                        $StatusUri = "v1.0/roleManagement/directory/roleAssignmentScheduleRequests/filterByCurrentUser(on='principal')?`$select=status&`$filter=id eq '$($RequestItem.id)'"
                        $Status = (Invoke-OPIMGraphRequest -Uri $StatusUri).value.status
                        if ($Status -eq 'Provisioned') {
                            $null = $Provisioned.Add([string]$RequestItem.id)
                        } elseif ($Status -notlike 'Pending*') {
                            # No -ErrorId: the same form as the expiry error in the process block (no new id).
                            Write-CmdletError -Message ([System.Exception]::new("$Name`: Request failed with status $Status")) -TargetObject $RequestItem.id -Cmdlet $PSCmdlet
                            $null = $Pending.Remove($RequestItem)
                            continue
                        }
                    }
                    if ($Provisioned.Contains([string]$RequestItem.id)) {
                        $InstanceUri = "v1.0/roleManagement/directory/roleAssignmentScheduleInstances/filterByCurrentUser(on='principal')?`$select=startDateTime&`$filter=roleAssignmentScheduleId eq '$($RequestItem.targetScheduleId)'"
                        $Activated = (Invoke-OPIMGraphRequest -Uri $InstanceUri).value
                        if ($Activated) {
                            Write-Progress -ParentId $parentId -Id ($parentId + 1 + $RoleRequests.IndexOf($RequestItem)) -Activity $Name -Status "Activated at $(([datetime]@($Activated)[0].startDateTime).ToLocalTime())" -PercentComplete 100
                            $null = $Pending.Remove($RequestItem)
                            continue
                        }
                    }
                } catch {
                    Remove-OPIMErrorRecord -Record $PSItem
                    $PSCmdlet.WriteError($PSItem)
                    $null = $Pending.Remove($RequestItem)
                    continue
                }
                # The timeout compares UtcNow with createdDateTime exactly as before (OPIM-16, step 5a).
                # Outside the try above, so its catch never turns the timeout into a per-request error.
                if (([datetime]::UtcNow - $Created).TotalSeconds -gt $effectiveTimeout) {
                    Write-CmdletError -Message ([System.Exception]::new("$Name`: Exceeded timeout of $effectiveTimeout seconds waiting for role request to complete")) -Category OperationTimeout -TargetObject $RequestItem.id -Cmdlet $PSCmdlet -Terminating
                }
            }
            if ($Pending.Count -gt 0) { Start-Sleep -Seconds $Interval }
        }
        if (-not $NoSummary) { Start-Sleep 1 }
        Write-Progress -Id $parentId -Activity 'Azure AD PIM Directory Role Activation' -Completed

        if ($PassThru) {
            Get-OPIMDirectoryRole -Activated |
                Where-Object { $_.roleAssignmentScheduleId -in $RoleRequests.targetScheduleId }
        }
    }
}
