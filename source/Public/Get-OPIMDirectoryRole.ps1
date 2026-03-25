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
    #>
    [Alias('Get-PIMADRole', 'Get-PIMRole')]
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        #Fetch roles for all principals, not just yourself. Requires additional permissions.
        [Switch]$All,
        #Only return currently activated role assignment instances.
        [Parameter(ParameterSetName = 'Activated')][Switch]$Activated,
        #The schedule item ID to retrieve a specific role record.
        $Identity,
        #An OData filter string to limit results. Ignored if -Identity is specified.
        [String]$Filter
    )
    process {
        [string]$userFilter = if (-not $All) {
            "/filterByCurrentUser(on='principal')"
        } else {
            [String]::Empty
        }
        [string]$type = if ($Activated) {
            'roleAssignmentScheduleInstances'
        } else {
            'roleEligibilitySchedules'
        }

        if ($Identity) {
            $Filter = "id eq '$Identity'"
        }
        [string]$objectFilter = if ($Filter) {
            "&`$filter=$Filter"
        } else {
            [String]::Empty
        }

        $requestUri = "v1.0/roleManagement/directory/${type}${userFilter}?`$expand=principal,roledefinition${objectFilter}"

        try {
            $items = Invoke-MgGraphRequest -Uri $requestUri -ErrorAction Stop -Verbose:$false |
                Select-Object -ExpandProperty Value
        } catch {
            throw (Convert-GraphHttpException $PSItem)
        }

        if ($Activated) {
            $items = $items | Where-Object { $_.assignmentType -eq 'Activated' }
        }

        $typeName = if ($Activated) {
            'Omnicit.PIM.DirectoryAssignmentScheduleInstance'
        } else {
            'Omnicit.PIM.DirectoryEligibilitySchedule'
        }

        foreach ($item in $items) {
            # Rehydrate directoryScope — v1.0 API does not support $expand for directoryScopeId
            # Ref: https://github.com/microsoftgraph/microsoft-graph-docs/issues/16936
            if ($item.directoryScopeId -eq '/') {
                $item['directoryScope'] = @{ id = '/' }
            } else {
                $item['directoryScope'] = Invoke-MgGraphRequest -Verbose:$false -Method Get -Uri "v1.0/directory/$($item.directoryScopeId)"
            }
            # Cast to PSCustomObject so custom Format views are used instead of the
            # built-in hashtable Key/Value formatter.
            $obj = [PSCustomObject]$item
            $obj.PSObject.TypeNames.Insert(0, $typeName)
            $obj
        }
    }
}
