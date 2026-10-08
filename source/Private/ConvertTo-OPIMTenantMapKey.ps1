function ConvertTo-OPIMTenantMapKey {
    <#
    .SYNOPSIS
    Returns the key a role or group is stored and compared under in TenantMap.psd1.

    .DESCRIPTION
    The single owner of the key format of the tenant map and of how a stored entry is read; build
    or read a key nowhere else. Install-OPIMConfiguration and Set-OPIMConfiguration store the key
    of every piped post, and Enable-OPIMMyRole and Disable-OPIMMyRole compare the key of every
    listed post with the configured entries, read through -Entry. It reads what it is given and
    calls nothing.

    The keys are, per pillar:

        Directory  roleDefinitionId|directoryScopeId   (role-def-001|/administrativeUnits/au-001)
        Group      groupId_accessId                     (group-001_member)
        Azure      the eligibility schedule Name

    A directory role is stored with its scope, so a configured role is activated and deactivated
    only at the scope it names (A13). An entry written before 0.6.0 holds the roleDefinitionId
    alone; read through -Entry it means the role at the root scope '/' only, never every scope of
    the role. A blank entry returns nothing, so it matches no post; every other entry is returned
    as it is. Compare keys with [System.StringComparison]::OrdinalIgnoreCase: a scope compares
    without regard to letter case.

    An active Azure role (an instance from Get-OPIMAzureRole -Activated, or an active row of
    -All) is stored by the eligibility schedule it was activated from (OPIM-22): the last
    segment of its LinkedRoleEligibilityScheduleId, which is the Name of that eligibility and so
    the key Enable-OPIMMyRole compares with. An object is such an instance when it carries the
    type Omnicit.PIM.AzureAssignmentScheduleInstance or a LinkedRoleEligibilityScheduleId
    property; an Az.Resources eligibility schedule has no such property. pim activates a stored
    eligibility at the eligibility's own scope, so an instance is stored only when its link names
    the eligibility at the instance's own scope (the text before
    /providers/Microsoft.Authorization/roleEligibilitySchedules/, compared OrdinalIgnoreCase). An
    instance that names no eligibility, one activated at another scope than its eligibility (a
    narrower scope chosen at activation), and one whose link names no scope (a bare name, or the
    provider-only form) are refused: the terminating error LinkedEligibilityNotFound (category
    ObjectNotFound, the instance as its target), whose single owner this function is.

    .PARAMETER Pillar
    Directory, Group or Azure: the list the post or the entry belongs to.

    .PARAMETER InputObject
    One schedule or instance object as Get-OPIMDirectoryRole, Get-OPIMEntraIDGroup or
    Get-OPIMAzureRole returns it. Its key is returned. A null object returns nothing.

    .PARAMETER Entry
    One configured entry as TenantMap.psd1 holds it. It is returned as the key to compare with: a
    directory entry without a scope (no '|') becomes the key of the role at '/'. A null, empty or
    blank entry returns nothing.

    .EXAMPLE
    ConvertTo-OPIMTenantMapKey -Pillar Directory -InputObject $Role

    Returns 'role-def-001|/administrativeUnits/au-001' for the role role-def-001 at that
    administrative unit.

    .EXAMPLE
    ConvertTo-OPIMTenantMapKey -Pillar Directory -Entry 'role-def-001'

    Returns 'role-def-001|/': an entry without a scope means the role at the root scope only.

    .EXAMPLE
    Get-OPIMAzureRole -Activated | ForEach-Object { ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $PSItem }

    Returns, for each active Azure role, the Name of the eligibility schedule it was activated
    from, and throws LinkedEligibilityNotFound for one that names none or is active at another
    scope than that eligibility.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Object')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][ValidateSet('Directory', 'Group', 'Azure')][string]$Pillar,
        [Parameter(Mandatory, ParameterSetName = 'Object')][AllowNull()]$InputObject,
        [Parameter(Mandatory, ParameterSetName = 'Entry')][AllowNull()][AllowEmptyString()][string]$Entry
    )
    if ($PSCmdlet.ParameterSetName -eq 'Entry') {
        # A blank entry (a hand-edited '' in the file) names nothing and matches no post.
        if ([string]::IsNullOrWhiteSpace($Entry)) { return }
        # A13: a directory entry written before 0.6.0 holds only the roleDefinitionId and means the role
        # at the root scope only -- never every scope of the role.
        if ($Pillar -eq 'Directory' -and -not $Entry.Contains('|')) { return "$Entry|/" }
        return $Entry
    }
    if ($null -eq $InputObject) { return }
    switch ($Pillar) {
        'Directory' { "$($InputObject.roleDefinitionId)|$($InputObject.directoryScopeId)" }
        'Group'     { "$($InputObject.groupId)_$($InputObject.accessId)" }
        'Azure' {
            [bool]$IsInstance = $InputObject.PSTypeNames -contains 'Omnicit.PIM.AzureAssignmentScheduleInstance' -or
                                $null -ne $InputObject.PSObject.Properties['LinkedRoleEligibilityScheduleId']
            if (-not $IsInstance) {
                [string]$InputObject.Name
            } else {
                # OPIM-22: the linked id is an ARM id,
                # <eligibility scope>/providers/Microsoft.Authorization/roleEligibilitySchedules/<name>, or the bare
                # name; its last segment is the eligibility's Name.
                [string]$LinkedId = $InputObject.LinkedRoleEligibilityScheduleId
                [string]$Linked = $LinkedId.Split('/')[-1]
                $RoleLabel  = if ($InputObject.RoleDefinitionDisplayName) { $InputObject.RoleDefinitionDisplayName } else { $InputObject.RoleDefinitionId }
                $ScopeLabel = if ($InputObject.ScopeDisplayName) { $InputObject.ScopeDisplayName } else { $InputObject.ScopeId }
                $Refusal = $null
                if ([string]::IsNullOrWhiteSpace($Linked)) {
                    $Refusal = "The active Azure role '$RoleLabel' at scope '$ScopeLabel' names no eligibility schedule it " +
                               'was activated from, so it is not stored. Pipe the eligible role from Get-OPIMAzureRole instead.'
                } else {
                    # pim activates a stored eligibility at the eligibility's own scope (Enable-OPIMAzureRole sends
                    # its ScopeId), and a role can be activated at a narrower scope than its eligibility (the
                    # portal's Scope tab). So the instance is stored only when its link proves that the eligibility
                    # is at the instance's own scope; a link without a scope (a bare name, or the provider-only
                    # form) proves nothing (SECURITY 4: never a wider scope).
                    [int]$At = $LinkedId.IndexOf('/providers/Microsoft.Authorization/roleEligibilitySchedules/',
                        [System.StringComparison]::OrdinalIgnoreCase)
                    [bool]$SameScope = $At -gt 0 -and
                        [string]::Equals($LinkedId.Substring(0, $At), [string]$InputObject.ScopeId, [System.StringComparison]::OrdinalIgnoreCase)
                    if (-not $SameScope) {
                        $Refusal = "The active Azure role '$RoleLabel' at scope '$ScopeLabel' cannot be shown to be active at " +
                                   'the scope of the eligibility it was activated from, so it is not stored: pim activates an ' +
                                   'eligibility at its own scope, which can be wider. Pipe the eligible role from ' +
                                   'Get-OPIMAzureRole instead.'
                    }
                }
                if ($Refusal) {
                    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new($Refusal),
                            'LinkedEligibilityNotFound',
                            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                            $InputObject))
                }
                $Linked
            }
        }
    }
}
