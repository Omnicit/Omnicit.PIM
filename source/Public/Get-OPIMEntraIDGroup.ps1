function Get-OPIMEntraIDGroup {
    <#
    .SYNOPSIS
    Get eligible or activated PIM group assignments for the current user.
    .DESCRIPTION
    Retrieves eligible or active Entra ID group (PIM for Groups) assignment schedules via the
    Microsoft Graph API. Requires a Graph connection with appropriate scopes.
    .EXAMPLE
    Get-OPIMEntraIDGroup
    List all eligible PIM group memberships/ownerships for yourself.
    .EXAMPLE
    Get-OPIMEntraIDGroup -Activated
    List all currently active PIM group memberships/ownerships.
    .EXAMPLE
    Get-OPIMEntraIDGroup -AccessType member
    List only eligible PIM group memberships (not ownerships).
    .OUTPUTS
    System.Collections.Hashtable (tagged as Omnicit.PIM.GroupEligibilitySchedule or Omnicit.PIM.GroupAssignmentScheduleInstance)
    .PARAMETER All
    Fetch group assignment schedules for all principals, not just your own account.
    Requires elevated Graph permissions to read other users' group eligibility assignments.
    .PARAMETER Activated
    Only return currently activated group assignment schedule instances instead of eligible
    (inactive) group eligibility schedules.
    .PARAMETER Identity
    The schedule item ID used to retrieve a single specific group assignment record by its unique identifier.
    When supplied, an OData filter of id eq '<Identity>' is applied automatically.
    .PARAMETER Filter
    An OData filter string appended to the Graph API request to narrow the result set.
    Ignored when -Identity is specified.
    .PARAMETER AccessType
    Limits results to a specific access type. Accepts member or owner. When omitted both
    membership and ownership eligibility schedules are returned.
    #>
    [Alias('Get-PIMGroup')]
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [Switch]$All,
        [Parameter(ParameterSetName = 'Activated')][Switch]$Activated,
        [String]$Identity,
        [String]$Filter,
        [ValidateSet('member', 'owner')]
        [String]$AccessType
    )
    process {
        $base = 'v1.0/identityGovernance/privilegedAccess/group'
        [string]$type = if ($Activated) {
            'assignmentScheduleInstances'
        } else {
            'eligibilitySchedules'
        }
        [string]$userFilter = if (-not $All) {
            "/filterByCurrentUser(on='principal')"
        } else {
            [String]::Empty
        }

        $filterParts = [System.Collections.Generic.List[string]]::new()
        if ($Identity)   { $filterParts.Add("id eq '$Identity'") }
        if ($AccessType) { $filterParts.Add("accessId eq '$AccessType'") }
        if ($Filter)     { $filterParts.Add($Filter) }

        [string]$odataFilter = if ($filterParts.Count -gt 0) {
            '&$filter=' + ($filterParts -join ' and ')
        } else {
            [String]::Empty
        }

        $requestUri = "${base}/${type}${userFilter}?`$expand=group,principal${odataFilter}"

        try {
            $items = Invoke-MgGraphRequest -Uri $requestUri -ErrorAction Stop -Verbose:$false |
                Select-Object -ExpandProperty Value
        } catch {
            throw (Convert-GraphHttpException $PSItem)
        }

        $typeName = if ($Activated) {
            'Omnicit.PIM.GroupAssignmentScheduleInstance'
        } else {
            'Omnicit.PIM.GroupEligibilitySchedule'
        }

        foreach ($item in $items) {
            # Cast to PSCustomObject so custom Format views are used instead of the
            # built-in hashtable Key/Value formatter.
            $obj = [PSCustomObject]$item
            $obj.PSObject.TypeNames.Insert(0, $typeName)
            $obj
        }
    }
}
