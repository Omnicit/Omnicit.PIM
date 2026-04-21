function Get-OPIMDirectoryRole {
    <#
    .SYNOPSIS
    Get eligible or activated Azure AD PIM directory roles for the current user.
    .DESCRIPTION
    Retrieves eligible or active role assignment schedules for the current user via the Microsoft
    Graph API. Authentication is handled automatically on first use. Call Connect-OPIM to
    pre-authenticate or to specify a target tenant. Call Disconnect-OPIM to clear cached tokens.

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
    Return both eligible and active roles matching an OData filter (dual-search).
    Common filter properties:
      roleDefinitionId eq '<guid>'  — filter by role definition
      principalId eq '<guid>'       — filter by a specific principal (requires elevated permissions)
    .EXAMPLE
    Get-OPIMDirectoryRole 'Global Administrator -> Directory (elig-001)'
    Tab-complete and retrieve details for a role by name (dual-search: returns eligible and/or active).
    .OUTPUTS
    PSCustomObject tagged as Omnicit.PIM.DirectoryEligibilitySchedule,
    Omnicit.PIM.DirectoryAssignmentScheduleInstance, or Omnicit.PIM.DirectoryCombinedSchedule
    (when -All, -Identity, or -Filter is used without -Activated).
    .PARAMETER All
    Return BOTH eligible and active role schedules for the current user in a single call.
    Objects are emitted with the Omnicit.PIM.DirectoryCombinedSchedule type for consistent
    table formatting with a Status column. Mutually exclusive with -Activated.
    .PARAMETER Activated
    Only return currently activated role assignment schedule instances instead of eligible
    (inactive) role eligibility schedules.
    Mutually exclusive with -All.
    .PARAMETER RoleName
    Tab-completable name of the directory role in the format produced by the argument completer.
    Extracts the schedule ID from the trailing (id) and performs a dual-search across eligible
    and active schedules. Mutually exclusive intent with -Identity (both set the same filter).
    .PARAMETER Identity
    The schedule item ID used to retrieve a single specific role record by its unique identifier.
    The ID corresponds to the id property on objects returned by this cmdlet.
    When supplied, both eligible and active schedules are searched (dual-search) unless -Activated
    is also specified.
    .PARAMETER Filter
    An OData filter string appended to the Graph API request to narrow the result set.
    When specified without -Activated, both eligible and active are searched (dual-search).
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
        [Parameter(Position = 0)]
        [ArgumentCompleter([DirectoryEligibleRoleCompleter])]
        [String]$RoleName,
        [String]$Identity,
        [String]$Filter
    )
    process {
        Initialize-OPIMAuth
        # Resolve RoleName to a schedule Identity if provided (extract ID from trailing '(id)' suffix)
        if ($RoleName) {
            if ($RoleName -match '\(([^)]+)\)$') {
                $Identity = $Matches[1]
            } else {
                $Identity = $RoleName
            }
        }

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

        # Dual mode: -All, or a specific filter was given and -Activated was not explicitly requested
        [bool]$IsDual = $All -or (-not $Activated -and $OdataFilter)

        if ($IsDual) {
            # Return both eligible and active with DirectoryCombinedSchedule type for consistent formatting
            foreach ($TypeConfig in @(
                @{ Type = 'roleEligibilitySchedules';        TypeName = 'Omnicit.PIM.DirectoryEligibilitySchedule';        Status = 'Eligible' }
                @{ Type = 'roleAssignmentScheduleInstances'; TypeName = 'Omnicit.PIM.DirectoryAssignmentScheduleInstance'; Status = 'Active'   }
            )) {
                [string]$RequestUri = "v1.0/roleManagement/directory/$($TypeConfig.Type)${UserFilter}${Expand}${ObjectFilter}"
                try {
                    $Items = Invoke-OPIMGraphRequest -Uri $RequestUri |
                        Select-Object -ExpandProperty Value
                } catch {
                    $PSCmdlet.WriteError($PSItem)
                    continue
                }
                foreach ($Item in $Items) {
                    if ($Item.directoryScopeId -eq '/') {
                        $Item['directoryScope'] = @{ id = '/' }
                    } else {
                        $Item['directoryScope'] = Invoke-OPIMGraphRequest -Method Get -Uri "v1.0/directory$($Item.directoryScopeId)"
                    }
                    $Obj = [PSCustomObject]$Item
                    $Obj | Add-Member -NotePropertyName Status -NotePropertyValue $TypeConfig.Status -Force
                    $Obj.PSObject.TypeNames.Insert(0, $TypeConfig.TypeName)
                    $Obj.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryCombinedSchedule')
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
            $Items = Invoke-OPIMGraphRequest -Uri $RequestUri |
                Select-Object -ExpandProperty Value
        } catch {
            $PSCmdlet.WriteError($PSItem)
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
                $Item['directoryScope'] = Invoke-OPIMGraphRequest -Method Get -Uri "v1.0/directory$($Item.directoryScopeId)"
            }
            # Cast to PSCustomObject so custom Format views are used instead of the
            # built-in hashtable Key/Value formatter.
            $Obj = [PSCustomObject]$Item
            $Obj.PSObject.TypeNames.Insert(0, $TypeName)
            $Obj
        }
    }
}
