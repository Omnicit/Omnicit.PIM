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
        Azure      the eligibility schedule Name        (elig-az-001)
                   or, from an active role, Name|ScopeId (elig-az-001|/subscriptions/sub-001)

    A directory role is stored with its scope, so a configured role is activated and deactivated
    only at the scope it names (A13). An entry written before 0.6.0 holds the roleDefinitionId
    alone; read through -Entry it means the role at the root scope '/' only, never every scope of
    the role. A blank entry returns nothing, so it matches no post; every other entry is returned
    as it is. Compare keys with [System.StringComparison]::OrdinalIgnoreCase: a scope compares
    without regard to letter case.

    An active Azure role (an instance from Get-OPIMAzureRole -Activated, or an active row of
    -All) is stored as the eligibility schedule it was activated from plus its own scope
    (OPIM-22): the last segment of its LinkedRoleEligibilityScheduleId -- the Name of that
    eligibility; ARM returned the link as a full ARM id at the role's own scope when measured
    live, Microsoft's reference sample shows a bare name, and both forms are read -- then '|'
    and the instance's ScopeId. An
    object is such an instance when it carries the type
    Omnicit.PIM.AzureAssignmentScheduleInstance or a LinkedRoleEligibilityScheduleId property; an
    Az.Resources eligibility schedule has no such property. pim activates an eligibility at the
    eligibility's own scope, so a reader matches an eligible post with an entry equal to its Name
    (stored from the eligibility) or to its -WithScope key, Name|ScopeId (stored from an active
    role): an entry from an activation at a narrower scope than its eligibility then matches no
    eligible post and activates nothing. An instance whose link names no eligibility, and one
    whose link is a full ARM id naming the eligibility at another scope than the instance's (the
    text before /providers/Microsoft.Authorization/roleEligibilitySchedules/, compared
    OrdinalIgnoreCase), are refused: the terminating error LinkedEligibilityNotFound (category
    ObjectNotFound, the instance as its target), whose single owner this function is.

    .PARAMETER Pillar
    Directory, Group or Azure: the list the post or the entry belongs to.

    .PARAMETER InputObject
    One schedule or instance object as Get-OPIMDirectoryRole, Get-OPIMEntraIDGroup or
    Get-OPIMAzureRole returns it. Its key is returned. A null object returns nothing.

    .PARAMETER WithScope
    Returns the scoped key of the post: Name|ScopeId for an Azure eligibility, the form an active
    role of it at its own scope is stored under. Every other post's key is returned as without
    the switch: a directory key and an active Azure role's key already name the scope, and a
    group has none.

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
    from and the role's own scope, as 'elig-az-001|/subscriptions/sub-001', and throws
    LinkedEligibilityNotFound for one that names no eligibility, or whose link names the
    eligibility at another scope.

    .EXAMPLE
    ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Eligible -WithScope

    Returns 'elig-az-001|/subscriptions/sub-001' for the eligibility elig-az-001 at that
    subscription: the entry an active role of it at that scope was stored as.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Object')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][ValidateSet('Directory', 'Group', 'Azure')][string]$Pillar,
        [Parameter(Mandatory, ParameterSetName = 'Object')][AllowNull()]$InputObject,
        [Parameter(ParameterSetName = 'Object')][switch]$WithScope,
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
                # An eligibility is stored as its Name. -WithScope gives the form an active role of it at its own
                # scope is stored under, so a reader can match both forms.
                if ($WithScope) { "$($InputObject.Name)|$($InputObject.ScopeId)" } else { [string]$InputObject.Name }
            } else {
                # OPIM-22: the linked id is an ARM id,
                # <eligibility scope>/providers/Microsoft.Authorization/roleEligibilitySchedules/<name> (as ARM
                # returned it live, at the role's own scope), or the bare name of the eligibility (as Microsoft's
                # reference sample shows it, and as Enable-OPIMAzureRole sends it); its last segment is the
                # eligibility's Name.
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
                    # portal's Scope tab). So the instance is stored with its OWN scope, and a reader matches the
                    # entry only with the eligibility at that scope (SECURITY 4: never a wider scope). A full ARM id
                    # names the eligibility's scope: when that differs from the instance's, it is refused here.
                    [int]$At = $LinkedId.IndexOf('/providers/Microsoft.Authorization/roleEligibilitySchedules/',
                        [System.StringComparison]::OrdinalIgnoreCase)
                    if ($At -gt 0 -and -not [string]::Equals($LinkedId.Substring(0, $At), [string]$InputObject.ScopeId,
                            [System.StringComparison]::OrdinalIgnoreCase)) {
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
                "$Linked|$($InputObject.ScopeId)"
            }
        }
    }
}
