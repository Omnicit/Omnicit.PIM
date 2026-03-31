function Get-OPIMDirectoryRole {
    <#
    .SYNOPSIS
    Get eligible or activated Azure AD PIM directory roles for the current user.
    .DESCRIPTION
    Retrieves eligible or active role assignment schedules for the current user (or all users with -All)
    via the Microsoft Graph API. Requires a Microsoft Graph connection (Connect-MgGraph).
    .EXAMPLE
    Get-OPIMDirectoryRole
    List all eligible (inactive) directory roles for yourself.
    .EXAMPLE
    Get-OPIMDirectoryRole -Activated
    List all currently activated directory roles for yourself.
    .EXAMPLE
    Get-OPIMDirectoryRole -All
    List eligible directory roles for all users (requires privileged permissions).
    .OUTPUTS
    System.Collections.Hashtable (tagged as Omnicit.PIM.DirectoryEligibilitySchedule or Omnicit.PIM.DirectoryAssignmentScheduleInstance)
    .PARAMETER All
    Fetch role schedules for all principals in the directory, not just your own account.
    Requires elevated Graph permissions such as PrivilegedEligibilitySchedule.Read.AzureADGroup.
    .PARAMETER Activated
    Only return currently activated role assignment schedule instances instead of eligible
    (inactive) role eligibility schedules.
    .PARAMETER Identity
    The schedule item ID used to retrieve a single specific role record by its unique identifier.
    When supplied, an OData filter of id eq '<Identity>' is applied automatically.
    .PARAMETER Filter
    An OData filter string appended to the Graph API request to narrow the result set.
    Ignored when -Identity is specified.
    #>
    [Alias('Get-PIMADRole', 'Get-PIMRole')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Switch]$All,
        [Parameter(ParameterSetName = 'Activated')][Switch]$Activated,
        $Identity,
        [String]$Filter
    )
    process {
        [string]$UserFilter = if (-not $All) {
            "/filterByCurrentUser(on='principal')"
        } else {
            [String]::Empty
        }
        [string]$Type = if ($Activated) {
            'roleAssignmentScheduleInstances'
        } else {
            'roleEligibilitySchedules'
        }

        if ($Identity) {
            $Filter = "id eq '$Identity'"
        }
        [string]$ObjectFilter = if ($Filter) {
            "&`$filter=$Filter"
        } else {
            [String]::Empty
        }

        $RequestUri = "v1.0/roleManagement/directory/${Type}${UserFilter}?`$expand=principal,roledefinition${ObjectFilter}"

        try {
            $Items = Invoke-MgGraphRequest -Uri $RequestUri -ErrorAction Stop -Verbose:$false |
                Select-Object -ExpandProperty Value
        } catch {
            $PSCmdlet.WriteError((Convert-GraphHttpException $PSItem))
            return
        }

        if ($Activated) {
            $Items = $Items | Where-Object { $_.assignmentType -eq 'Activated' }
        }

        $TypeName = if ($Activated) {
            'Omnicit.PIM.DirectoryAssignmentScheduleInstance'
        } else {
            'Omnicit.PIM.DirectoryEligibilitySchedule'
        }

        foreach ($Item in $Items) {
            # Rehydrate directoryScope — v1.0 API does not support $expand for directoryScopeId
            # Ref: https://github.com/microsoftgraph/microsoft-graph-docs/issues/16936
            if ($Item.directoryScopeId -eq '/') {
                $Item['directoryScope'] = @{ id = '/' }
            } else {
                $Item['directoryScope'] = Invoke-MgGraphRequest -Verbose:$false -ErrorAction Stop -Method Get -Uri "v1.0/directory$($Item.directoryScopeId)"
            }
            # Cast to PSCustomObject so custom Format views are used instead of the
            # built-in hashtable Key/Value formatter.
            $Obj = [PSCustomObject]$Item
            $Obj.PSObject.TypeNames.Insert(0, $TypeName)
            $Obj
        }
    }
}
