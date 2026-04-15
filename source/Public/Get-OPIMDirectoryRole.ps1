function Get-OPIMDirectoryRole {
    <#
    .SYNOPSIS
    Get eligible or activated Azure AD PIM directory roles for the current user.
    .DESCRIPTION
    Retrieves eligible or active role assignment schedules for the current user via the Microsoft
    Graph API. Requires a Microsoft Graph connection (Connect-MgGraph).

    Without any switch: returns eligible (inactive) directory roles for the current user.
    With -Activated: returns currently active role assignment schedule instances.
    With -All: returns BOTH eligible and active schedules for the current user.

    -All and -Activated are mutually exclusive.
    .EXAMPLE
    Get-OPIMDirectoryRole
    List all eligible (inactive) directory roles for yourself.
    .EXAMPLE
    Get-OPIMDirectoryRole -Activated
    List all currently activated directory roles for yourself.
    .EXAMPLE
    Get-OPIMDirectoryRole -All
    List both eligible and active directory roles for yourself.
    .EXAMPLE
    Get-OPIMDirectoryRole -Identity 'elig-001'
    Retrieve a single eligible role schedule by its schedule ID (the id property from output).
    .EXAMPLE
    Get-OPIMDirectoryRole -Filter "roleDefinitionId eq '62e90394-69f5-4237-9190-012177145e10'"
    Return only eligible roles matching an OData filter. Common filter properties:
      roleDefinitionId eq '<guid>'  — filter by role definition
      principalId eq '<guid>'       — filter by a specific principal (requires elevated permissions)
    .OUTPUTS
    System.Collections.Hashtable (tagged as Omnicit.PIM.DirectoryEligibilitySchedule or Omnicit.PIM.DirectoryAssignmentScheduleInstance)
    .PARAMETER All
    Return BOTH eligible and active role schedules for the current user in a single call.
    Mutually exclusive with -Activated.
    .PARAMETER Activated
    Only return currently activated role assignment schedule instances instead of eligible
    (inactive) role eligibility schedules.
    Mutually exclusive with -All.
    .PARAMETER Identity
    The schedule item ID used to retrieve a single specific role record by its unique identifier.
    The ID corresponds to the id property on objects returned by this cmdlet.
    When supplied, an OData filter of id eq '<Identity>' is applied automatically.
    .PARAMETER Filter
    An OData filter string appended to the Graph API request to narrow the result set.
    Ignored when -Identity is specified.
    Common examples:
      -Filter "roleDefinitionId eq '<guid>'"
      -Filter "principalId eq '<guid>'"
    #>
    [Alias('Get-PIMADRole', 'Get-PIMRole')]
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'All')][Switch]$All,
        [Parameter(ParameterSetName = 'Activated')][Switch]$Activated,
        [String]$Identity,
        [String]$Filter
    )
    process {
        [string]$UserFilter = "/filterByCurrentUser(on='principal')"

        if ($Identity) {
            $OdataFilter = "id eq '$Identity'"
        } elseif ($Filter) {
            $OdataFilter = $Filter
        } else {
            $OdataFilter = [String]::Empty
        }

        [string]$ObjectFilter = if ($OdataFilter) {
            "&`$filter=$OdataFilter"
        } else {
            [String]::Empty
        }

        $Expand = '?$expand=principal,roledefinition'

        if ($All) {
            # Return both eligible and active for the current user
            foreach ($TypeConfig in @(
                @{ Type = 'roleEligibilitySchedules';      TypeName = 'Omnicit.PIM.DirectoryEligibilitySchedule'        }
                @{ Type = 'roleAssignmentScheduleInstances'; TypeName = 'Omnicit.PIM.DirectoryAssignmentScheduleInstance' }
            )) {
                $RequestUri = "v1.0/roleManagement/directory/$($TypeConfig.Type)${UserFilter}${Expand}${ObjectFilter}"
                try {
                    $Items = Invoke-MgGraphRequest -Uri $RequestUri -ErrorAction Stop -Verbose:$false |
                        Select-Object -ExpandProperty Value
                } catch {
                    $PSCmdlet.WriteError((Convert-GraphHttpException $PSItem))
                    continue
                }
                foreach ($Item in $Items) {
                    if ($Item.directoryScopeId -eq '/') {
                        $Item['directoryScope'] = @{ id = '/' }
                    } else {
                        $Item['directoryScope'] = Invoke-MgGraphRequest -Verbose:$false -ErrorAction Stop -Method Get -Uri "v1.0/directory$($Item.directoryScopeId)"
                    }
                    $Obj = [PSCustomObject]$Item
                    $Obj.PSObject.TypeNames.Insert(0, $TypeConfig.TypeName)
                    $Obj
                }
            }
            return
        }

        [string]$Type = if ($Activated) {
            'roleAssignmentScheduleInstances'
        } else {
            'roleEligibilitySchedules'
        }

        $RequestUri = "v1.0/roleManagement/directory/${Type}${UserFilter}${Expand}${ObjectFilter}"

        try {
            $Items = Invoke-MgGraphRequest -Uri $RequestUri -ErrorAction Stop -Verbose:$false |
                Select-Object -ExpandProperty Value
        } catch {
            $PSCmdlet.WriteError((Convert-GraphHttpException $PSItem))
            return
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
