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
    [OutputType([PSCustomObject])]
    param(
        [Switch]$All,
        [Parameter(ParameterSetName = 'Activated')][Switch]$Activated,
        [String]$Identity,
        [String]$Filter,
        [ValidateSet('member', 'owner')]
        [String]$AccessType
    )
    process {
        $Base = 'v1.0/identityGovernance/privilegedAccess/group'
        [string]$Type = if ($Activated) {
            'assignmentScheduleInstances'
        } else {
            'eligibilitySchedules'
        }
        [string]$UserFilter = if (-not $All) {
            "/filterByCurrentUser(on='principal')"
        } else {
            [String]::Empty
        }

        $FilterParts = [System.Collections.Generic.List[string]]::new()
        if ($Identity)   { $FilterParts.Add("id eq '$Identity'") }
        if ($AccessType) { $FilterParts.Add("accessId eq '$AccessType'") }
        if ($Filter)     { $FilterParts.Add($Filter) }

        [string]$OdataFilter = if ($FilterParts.Count -gt 0) {
            '&$filter=' + ($FilterParts -join ' and ')
        } else {
            [String]::Empty
        }

        $RequestUri = "${Base}/${Type}${UserFilter}?`$expand=group,principal${OdataFilter}"

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
