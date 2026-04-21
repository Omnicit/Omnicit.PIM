function Get-OPIMEntraIDGroup {
    <#
    .SYNOPSIS
    Get eligible or activated PIM group assignments for the current user.
    .DESCRIPTION
    Retrieves eligible or active Entra ID group (PIM for Groups) assignment schedules via the
    Microsoft Graph API. Authentication is handled automatically on first use. Call Connect-OPIM
    to pre-authenticate or to specify a target tenant. Call Disconnect-OPIM to clear cached tokens.

    Without any switch: returns eligible (inactive) group assignments for the current user.
    With -Activated: returns currently active group assignment schedule instances.
    With -All: returns BOTH eligible and active group assignments for the current user.

    -All and -Activated are mutually exclusive.
    .EXAMPLE
    Get-OPIMEntraIDGroup
    List all eligible PIM group memberships/ownerships for yourself.
    .EXAMPLE
    Get-OPIMEntraIDGroup -Activated
    List all currently active PIM group memberships/ownerships.
    .EXAMPLE
    Get-OPIMEntraIDGroup -All
    List both eligible and active PIM group assignments for yourself.
    .EXAMPLE
    Get-OPIMEntraIDGroup -AccessType member
    List only eligible PIM group memberships (not ownerships).
    .EXAMPLE
    Get-OPIMEntraIDGroup -Identity 'elig-001'
    Retrieve both eligible and active records with that schedule ID (dual-search).
    .EXAMPLE
    Get-OPIMEntraIDGroup -Filter "groupId eq '00000000-0000-0000-0000-000000000000'"
    Return both eligible and active group assignments matching an OData filter (dual-search).
    Common filter properties:
      groupId eq '<guid>'       — filter by a specific group
      principalId eq '<guid>'   — filter by a specific principal
    .EXAMPLE
    Get-OPIMEntraIDGroup 'Finance Team - member (elig-001)'
    Tab-complete and retrieve details for a group assignment by name (dual-search).
    .OUTPUTS
    PSCustomObject tagged as Omnicit.PIM.GroupEligibilitySchedule,
    Omnicit.PIM.GroupAssignmentScheduleInstance, or Omnicit.PIM.GroupCombinedSchedule
    (when -All, -Identity or -Filter is used without -Activated).
    .PARAMETER All
    Return BOTH eligible and active group assignment schedules for the current user in a single call.
    Objects are emitted with the Omnicit.PIM.GroupCombinedSchedule type for consistent table
    formatting with a Status column. Mutually exclusive with -Activated.
    .PARAMETER Activated
    Only return currently activated group assignment schedule instances instead of eligible
    (inactive) group eligibility schedules.
    Mutually exclusive with -All.
    .PARAMETER GroupName
    Tab-completable name of the PIM group assignment in the format produced by the argument completer.
    Extracts the schedule ID from the trailing (id) and performs a dual-search across eligible
    and active schedules. Mutually exclusive intent with -Identity (both set the same filter).
    .PARAMETER Identity
    The schedule item ID used to retrieve a single specific group assignment record by its unique identifier.
    The ID corresponds to the id property on objects returned by this cmdlet.
    When supplied, both eligible and active schedules are searched (dual-search) unless -Activated
    is also specified.
    .PARAMETER Filter
    An OData filter string appended to the Graph API request to narrow the result set.
    When specified without -Activated, both eligible and active are searched (dual-search).
    Common examples:
      -Filter "groupId eq '<guid>'"
      -Filter "principalId eq '<guid>'"
    .PARAMETER AccessType
    Limits results to a specific access type. Accepts member or owner. When omitted both
    membership and ownership schedules are returned. Applies to all modes including -All.
    #>
    [Alias('Get-PIMGroup')]
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'All')][Switch]$All,
        [Parameter(ParameterSetName = 'Activated')][Switch]$Activated,
        [Parameter(Position = 0)]
        [ArgumentCompleter([GroupEligibleCompleter])]
        [String]$GroupName,
        [String]$Identity,
        [String]$Filter,
        [ValidateSet('member', 'owner')]
        [String]$AccessType
    )
    process {
        Initialize-OPIMAuth
        # Resolve GroupName to a schedule Identity if provided (extract ID from trailing '(id)' suffix)
        [string]$ResolvedId = $Identity
        if ($GroupName) {
            if ($GroupName -match '\(([^)]+)\)$') {
                $ResolvedId = $Matches[1]
            } else {
                $ResolvedId = $GroupName
            }
        }

        $Base = 'v1.0/identityGovernance/privilegedAccess/group'
        [string]$UserFilter = "/filterByCurrentUser(on='principal')"
        $Expand = '?$expand=group,principal'

        # Build unified OData filter (applies to both eligible and active endpoints in dual mode)
        $AllFilterParts = [System.Collections.Generic.List[string]]::new()
        if ($ResolvedId) { $AllFilterParts.Add("id eq '$ResolvedId'") }
        if ($AccessType) { $AllFilterParts.Add("accessId eq '$AccessType'") }
        if ($Filter)     { $AllFilterParts.Add($Filter) }

        [string]$OdataFilter = if ($AllFilterParts.Count -gt 0) {
            '&$filter=' + ($AllFilterParts -join ' and ')
        } else {
            [String]::Empty
        }

        # Dual mode: -All, or a specific id/filter given and -Activated not explicitly requested
        [bool]$HasSearchCriteria = $ResolvedId -or $Filter
        [bool]$IsDual = $All -or (-not $Activated -and $HasSearchCriteria)

        if ($IsDual) {
            # Return both eligible and active with GroupCombinedSchedule type for consistent formatting
            foreach ($TypeConfig in @(
                @{ Type = 'eligibilitySchedules';        TypeName = 'Omnicit.PIM.GroupEligibilitySchedule';        Status = 'Eligible' }
                @{ Type = 'assignmentScheduleInstances'; TypeName = 'Omnicit.PIM.GroupAssignmentScheduleInstance'; Status = 'Active'   }
            )) {
                $RequestUri = "${Base}/$($TypeConfig.Type)${UserFilter}${Expand}${OdataFilter}"
                try {
                    $Items = Invoke-OPIMGraphRequest -Uri $RequestUri |
                        Select-Object -ExpandProperty Value
                } catch {
                    $PSCmdlet.WriteError($PSItem)
                    continue
                }
                foreach ($Item in $Items) {
                    $Obj = [PSCustomObject]$Item
                    $Obj | Add-Member -NotePropertyName Status -NotePropertyValue $TypeConfig.Status -Force
                    $Obj.PSObject.TypeNames.Insert(0, $TypeConfig.TypeName)
                    $Obj.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupCombinedSchedule')
                    $Obj
                }
            }
            return
        }

        [string]$Type = if ($Activated) {
            'assignmentScheduleInstances'
        } else {
            'eligibilitySchedules'
        }

        $RequestUri = "${Base}/${Type}${UserFilter}${Expand}${OdataFilter}"

        try {
            $Items = Invoke-OPIMGraphRequest -Uri $RequestUri |
                Select-Object -ExpandProperty Value
        } catch {
            $PSCmdlet.WriteError($PSItem)
            return
        }

        $TypeName = if ($Activated) {
            'Omnicit.PIM.GroupAssignmentScheduleInstance'
        } else {
            'Omnicit.PIM.GroupEligibilitySchedule'
        }

        foreach ($Item in $Items) {
            # Cast to PSCustomObject so custom Format views are used instead of the
            # built-in hashtable Key/Value formatter.
            $Obj = [PSCustomObject]$Item
            $Obj.PSObject.TypeNames.Insert(0, $TypeName)
            $Obj
        }
    }
}
