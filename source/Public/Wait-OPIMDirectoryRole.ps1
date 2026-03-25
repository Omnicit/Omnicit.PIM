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
    #>
    [Alias('Wait-PIMADRole', 'Wait-PIMRole')]
    [OutputType([System.Collections.Hashtable])]
    [CmdletBinding()]
    param (
        #Role activation request from Enable-OPIMDirectoryRole.
        [Parameter(Mandatory, ValueFromPipeline)]
        $RoleRequest,
        #Polling interval in seconds. Default is 1 second.
        [double]$Interval = 1,
        #Maximum seconds to wait before timing out. Default is 10 minutes (600 seconds).
        $Timeout = 600,
        #Maximum concurrent role activation polls.
        $ThrottleLimit = 5,
        #When specified, returns the activated role schedule instances after all activations complete.
        [Switch]$PassThru,
        #Skip the 1-second summary pause before returning.
        [Switch]$NoSummary
    )
    begin {
        [List[PSObject]]$RoleRequests = [List[PSObject]]::new()
        $parentId = Get-Random
    }
    process {
        if ($RoleRequest.scheduleInfo.expiration.endDateTime) {
            $localEndTime = [datetime]$RoleRequest.scheduleInfo.expiration.endDateTime
            if ($localEndTime -lt [DateTime]::UtcNow) {
                Write-CmdletError -Message ([System.Exception]::new("$($RoleRequest.RoleName) role end date already expired at $($localEndTime.ToLocalTime()). Skipping."))
                return
            }
        }
        $RoleRequests.Add($RoleRequest)
    }
    end {
        [ConcurrentDictionary[Int, hashtable]]$info = [ConcurrentDictionary[Int, hashtable]]::new()

        $waitJobs = $RoleRequests | ForEach-Object -ThrottleLimit $ThrottleLimit -AsJob -Parallel {
            Import-Module 'Microsoft.Graph.Authentication' -Verbose:$false 4>$null
            $VerbosePreference = 'continue'
            $requestItem = $PSItem
            $name        = $requestItem.roleDefinition.displayName
            $created     = [datetime]$requestItem.createdDateTime

            function Get-Timestamp ($created = $created) {
                $since = [datetime]::UtcNow - $created
                if ($since.TotalSeconds -gt $USING:Timeout) {
                    throw "$name`: Exceeded timeout of $($USING:Timeout) seconds waiting for role request to complete"
                }
                ' - ' + [int]($since.TotalSeconds) + ' secs elapsed'
            }

            function Set-JobStatus ($Status, $PercentComplete, $jobInfo = $jobInfo) {
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
                    Set-JobStatus $status -PercentComplete 30
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
                Set-JobStatus 'Activating' -PercentComplete 60
                $uri           = "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleInstances/filterByCurrentUser(on='principal')?`$select=startDateTime&`$filter=roleAssignmentScheduleId eq '$($requestItem.targetScheduleId)'"
                $activatedRole = (Invoke-MgGraphRequest -Verbose:$false -Method Get -Uri $uri).Value
                Start-Sleep $USING:Interval
            } until ($activatedRole)

            $activatedStart = ([datetime]$activatedRole.startDateTime).ToLocalTime()
            Set-JobStatus "Activated at $activatedStart" -PercentComplete 100
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
