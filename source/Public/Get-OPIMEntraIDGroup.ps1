function Get-OPIMEntraIDGroup {
    <#
    .SYNOPSIS
    Get eligible or activated PIM group assignments for the current user.
    .DESCRIPTION
    Retrieves eligible or active Entra ID group (PIM for Groups) assignment schedules via the
    Microsoft Graph API. Requires a Graph connection with appropriate scopes.

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
    Retrieve a single group schedule by its schedule ID (the id property from output).
    .EXAMPLE
    Get-OPIMEntraIDGroup -Filter "groupId eq '00000000-0000-0000-0000-000000000000'"
    Return only group assignments matching an OData filter. Common filter properties:
      groupId eq '<guid>'       — filter by a specific group
      principalId eq '<guid>'   — filter by a specific principal
    .OUTPUTS
    System.Collections.Hashtable (tagged as Omnicit.PIM.GroupEligibilitySchedule or Omnicit.PIM.GroupAssignmentScheduleInstance)
    .PARAMETER All
    Return BOTH eligible and active group assignment schedules for the current user in a single call.
    Mutually exclusive with -Activated.
    .PARAMETER Activated
    Only return currently activated group assignment schedule instances instead of eligible
    (inactive) group eligibility schedules.
    Mutually exclusive with -All.
    .PARAMETER Identity
    The schedule item ID used to retrieve a single specific group assignment record by its unique identifier.
    The ID corresponds to the id property on objects returned by this cmdlet.
    When supplied, an OData filter of id eq '<Identity>' is applied automatically.
    .PARAMETER Filter
    An OData filter string appended to the Graph API request to narrow the result set.
    Ignored when -Identity is specified.
    Common examples:
      -Filter "groupId eq '<guid>'"
      -Filter "principalId eq '<guid>'"
    .PARAMETER AccessType
    Limits results to a specific access type. Accepts member or owner. When omitted both
    membership and ownership eligibility schedules are returned.
    Ignored when -All is specified.
    #>
    [Alias('Get-PIMGroup')]
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'All')][Switch]$All,
        [Parameter(ParameterSetName = 'Activated')][Switch]$Activated,
        [String]$Identity,
        [String]$Filter,
        [ValidateSet('member', 'owner')]
        [String]$AccessType
    )
    process {
        $Base = 'v1.0/identityGovernance/privilegedAccess/group'
        [string]$UserFilter = "/filterByCurrentUser(on='principal')"
        $Expand = '?$expand=group,principal'

        $FilterParts = [System.Collections.Generic.List[string]]::new()
        if ($Identity) { $FilterParts.Add("id eq '$Identity'") }
        if ($Filter)   { $FilterParts.Add($Filter) }

        [string]$OdataFilter = if ($FilterParts.Count -gt 0) {
            '&$filter=' + ($FilterParts -join ' and ')
        } else {
            [String]::Empty
        }

        if ($All) {
            # Return both eligible and active for the current user
            foreach ($TypeConfig in @(
                @{ Type = 'eligibilitySchedules';      TypeName = 'Omnicit.PIM.GroupEligibilitySchedule'        }
                @{ Type = 'assignmentScheduleInstances'; TypeName = 'Omnicit.PIM.GroupAssignmentScheduleInstance' }
            )) {
                $RequestUri = "${Base}/$($TypeConfig.Type)${UserFilter}${Expand}${OdataFilter}"
                try {
                    $Items = Invoke-MgGraphRequest -Uri $RequestUri -ErrorAction Stop -Verbose:$false |
                        Select-Object -ExpandProperty Value
                } catch {
                    $PSCmdlet.WriteError((Convert-GraphHttpException $PSItem))
                    continue
                }
                foreach ($Item in $Items) {
                    $Obj = [PSCustomObject]$Item
                    $Obj.PSObject.TypeNames.Insert(0, $TypeConfig.TypeName)
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

        # AccessType filter only applies to single-type calls (not -All)
        $SingleCallParts = [System.Collections.Generic.List[string]]::new()
        if ($Identity)   { $SingleCallParts.Add("id eq '$Identity'") }
        if ($AccessType) { $SingleCallParts.Add("accessId eq '$AccessType'") }
        if ($Filter)     { $SingleCallParts.Add($Filter) }

        [string]$SingleOdataFilter = if ($SingleCallParts.Count -gt 0) {
            '&$filter=' + ($SingleCallParts -join ' and ')
        } else {
            [String]::Empty
        }

        $RequestUri = "${Base}/${Type}${UserFilter}${Expand}${SingleOdataFilter}"

        try {
            $Items = Invoke-MgGraphRequest -Uri $RequestUri -ErrorAction Stop -Verbose:$false |
                Select-Object -ExpandProperty Value
        } catch {
            $PSCmdlet.WriteError((Convert-GraphHttpException $PSItem))
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
