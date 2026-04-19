using namespace System.Collections.Generic
using namespace System.Collections.Concurrent
using namespace System.Management.Automation

function Wait-OPIMDirectoryRole {
    <#
    .SYNOPSIS
    Wait for an Azure AD PIM directory role activation request to fully provision.
    .DESCRIPTION
    Polls the Microsoft Graph API until the role activation request reaches 'Provisioned' status
    and the role assignment instance appears in the directory. Useful after Enable-OPIMDirectoryRole
    when you need the role to be active before proceeding.
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
    Maximum number of concurrent role activation polls to run in parallel. Default is 5.
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
        if ($RoleRequests.Count -eq 0) { return }

        [ConcurrentDictionary[Int, hashtable]]$info = [ConcurrentDictionary[Int, hashtable]]::new()

        $waitJobs = $RoleRequests | ForEach-Object -ThrottleLimit $ThrottleLimit -AsJob -Parallel {
            Import-Module 'Microsoft.Graph.Authentication' -Verbose:$false 4>$null
            $VerbosePreference = 'continue'
            $requestItem = $PSItem
            $name        = $requestItem.roleDefinition.displayName
            $created     = [datetime]$requestItem.createdDateTime

            function Get-Timestamp ($created = $created) {
                $since = [datetime]::UtcNow - $created
                if ($since.TotalSeconds -gt $USING:effectiveTimeout) {
                    throw "$name`: Exceeded timeout of $($USING:effectiveTimeout) seconds waiting for role request to complete"
                }
                ' - ' + [int]($since.TotalSeconds) + ' secs elapsed'
            }

            function Write-JobStatus ($Status, $PercentComplete, $jobInfo = $jobInfo) {
                if ($Status)          { $jobInfo.Status = $Status.PadRight(30) + " $(Get-Timestamp)" }
                if ($PercentComplete) { $jobInfo.PercentComplete = $PercentComplete }
            }

            $jobInfo = @{
                Activity = "$Name".PadRight(30)
                Status   = 'Provisioning'
            }
            do {
                $isUnique = ($USING:info).TryAdd((Get-Random), $jobInfo)
            } until ($isUnique)

            $status = $null
            if ($status -ne 'Provisioned') {
                do {
                    $uri    = "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests/filterByCurrentUser(on='principal')?`$select=status&`$filter=id eq '$($requestItem.id)'"
                    $status = (Invoke-MgGraphRequest -Verbose:$false -ErrorAction Stop -Method Get -Uri $uri).value.status
                    Write-JobStatus $status -PercentComplete 30
                    Start-Sleep $USING:Interval
                } while ($status -like 'Pending*')

                if ($status -ne 'Provisioned') {
                    Write-Error "$name`: Request failed with status $status"
                    return
                }
            }

            # Now wait for the assignment schedule instance to appear in the directory
            $activatedRole = $null
            do {
                Write-JobStatus 'Activating' -PercentComplete 60
                $uri           = "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleInstances/filterByCurrentUser(on='principal')?`$select=startDateTime&`$filter=roleAssignmentScheduleId eq '$($requestItem.targetScheduleId)'"
                $activatedRole = (Invoke-MgGraphRequest -Verbose:$false -Method Get -Uri $uri).Value
                Start-Sleep $USING:Interval
            } until ($activatedRole)

            $activatedStart = ([datetime]$activatedRole.startDateTime).ToLocalTime()
            Write-JobStatus "Activated at $activatedStart" -PercentComplete 100
        }

        try {
            Write-Progress -Id $parentId -Activity 'Azure AD PIM Directory Role Activation'
            $runningStates = 'AtBreakpoint', 'Running', 'Stopping', 'Suspending'
            $i             = 0
            $notFirstLoop  = $false
            do {
                Start-Sleep 0.5
                if (!$notFirstLoop) { Start-Sleep 0.5; $notFirstLoop = $true }
                foreach ($infoItem in $info.GetEnumerator()) {
                    Write-Progress -ParentId $parentId -Id $infoItem.Key @($infoItem.Value)
                }
                $totalProgress     = (($info.Values.PercentComplete | Measure-Object -Sum).Sum) / $waitJobs.ChildJobs.Count
                $completeJobCount  = ($waitJobs.ChildJobs | Where-Object State -NotIn $runningStates).Count
                Write-Progress -Id $parentId -Activity 'Azure AD PIM Directory Role Activation' -Status "$completeJobCount of $($waitJobs.ChildJobs.Count)" -PercentComplete $totalProgress
                if ($waitJobs.State -notin $runningStates) { $i++ }
            } until ($waitJobs.State -notin $runningStates -and $i -gt 1)

            if (-not $NoSummary) { Start-Sleep 1 }
            Write-Progress -Id $parentId -Activity 'Azure AD PIM Directory Role Activation' -Completed
        } catch { throw } finally {
            $waitJobs | Receive-Job -Wait -AutoRemoveJob
        }

        if ($PassThru) {
            Get-OPIMDirectoryRole -Activated |
                Where-Object { $_.roleAssignmentScheduleId -in $RoleRequests.targetScheduleId }
        }
    }
}
