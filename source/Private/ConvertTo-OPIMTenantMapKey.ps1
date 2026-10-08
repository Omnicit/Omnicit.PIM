function ConvertTo-OPIMTenantMapKey {
    <#
    .SYNOPSIS
    Returns the key a role or group is stored and compared under in TenantMap.psd1.

    .DESCRIPTION
    The single owner of the key format of the tenant map and of how a stored entry is read; build
    or read a key nowhere else. Install-OPIMConfiguration and Set-OPIMConfiguration store the key
    of every piped post, and Enable-OPIMMyRole and Disable-OPIMMyRole compare the key of every
    listed post with the configured entries, read through -Entry. It is pure: it reads what it is
    given and calls nothing.

    The keys are, per pillar:

        Directory  roleDefinitionId|directoryScopeId   (role-def-001|/administrativeUnits/au-001)
        Group      groupId_accessId                     (group-001_member)
        Azure      the eligibility schedule Name

    A directory role is stored with its scope, so a configured role is activated and deactivated
    only at the scope it names (A13). An entry written before 0.6.0 holds the roleDefinitionId
    alone; read through -Entry it means the role at the root scope '/' only, never every scope of
    the role. Every other entry is returned as it is. Compare keys with
    [System.StringComparison]::OrdinalIgnoreCase: a scope compares without regard to letter case.

    .PARAMETER Pillar
    Directory, Group or Azure: the list the post or the entry belongs to.

    .PARAMETER InputObject
    One schedule or instance object as Get-OPIMDirectoryRole, Get-OPIMEntraIDGroup or
    Get-OPIMAzureRole returns it. Its key is returned. A null object returns nothing.

    .PARAMETER Entry
    One configured entry as TenantMap.psd1 holds it. It is returned as the key to compare with: a
    directory entry without a scope (no '|') becomes the key of the role at '/'.

    .EXAMPLE
    ConvertTo-OPIMTenantMapKey -Pillar Directory -InputObject $Role

    Returns 'role-def-001|/administrativeUnits/au-001' for the role role-def-001 at that
    administrative unit.

    .EXAMPLE
    ConvertTo-OPIMTenantMapKey -Pillar Directory -Entry 'role-def-001'

    Returns 'role-def-001|/': an entry without a scope means the role at the root scope only.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Object')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][ValidateSet('Directory', 'Group', 'Azure')][string]$Pillar,
        [Parameter(Mandatory, ParameterSetName = 'Object')][AllowNull()]$InputObject,
        [Parameter(Mandatory, ParameterSetName = 'Entry')][string]$Entry
    )
    if ($PSCmdlet.ParameterSetName -eq 'Entry') {
        # A13: a directory entry written before 0.6.0 holds only the roleDefinitionId and means the role
        # at the root scope only -- never every scope of the role.
        if ($Pillar -eq 'Directory' -and -not $Entry.Contains('|')) { return "$Entry|/" }
        return $Entry
    }
    if ($null -eq $InputObject) { return }
    switch ($Pillar) {
        'Directory' { "$($InputObject.roleDefinitionId)|$($InputObject.directoryScopeId)" }
        'Group'     { "$($InputObject.groupId)_$($InputObject.accessId)" }
        'Azure'     { [string]$InputObject.Name }
    }
}
