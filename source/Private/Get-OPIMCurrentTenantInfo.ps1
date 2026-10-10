function Get-OPIMCurrentTenantInfo {
    <#
    .SYNOPSIS
    Returns the tenant Omnicit.PIM is signed in to, and its display name when it can be read.

    .DESCRIPTION
    Returns the tenant of the module's own sign-in: TokenTenantId in the auth state, the tenant
    (a GUID) that the module's Microsoft Graph token was issued for. It is returned whatever
    Get-OPIMGraphSessionState says -- Own, Absent, Changed or Untracked -- since an alias gets the
    tenant the module signed in to. The tenant of a Microsoft Graph session that another
    Connect-MgGraph started is never used (OPIM-45), and this function does not call Get-MgContext
    itself. TenantId is $null while the module holds no sign-in: no auth state, a state that is not
    a dictionary, or a state without TokenTenantId, such as the one that holds only the device code
    mode before the first sign-in.

    The display name is read, best-effort, from v1.0/organization, and only when
    Get-OPIMGraphSessionState is Own -- the process still holds the Graph session the module
    connected -- and the organization's id is that tenant. Otherwise DisplayName is an empty string,
    and so it is when the call fails, for example without the scope to read the organization. A
    failed call is scrubbed with Remove-OPIMErrorRecord and not reported.

    Environment is the cloud of that sign-in, as the auth state records it ('Global', 'USGov',
    'USGovDoD' or 'China'): 'Global' for a state that records none, since the global cloud was the
    only one before the cloud was recorded, and $null without a sign-in, when there is no cloud to
    give.

    Install-OPIMConfiguration calls this to take the tenant of a new alias when -TenantId is
    omitted, to give the alias the cloud of the sign-in when it takes the sign-in's tenant, and,
    with Set-OPIMConfiguration, for the display name in their confirmation prompt, which they show
    only for the tenant they write.

    .OUTPUTS
    PSCustomObject with:
      TenantId    [string] -- the tenant GUID of the module's sign-in, or $null without one.
      DisplayName [string] -- the display name of that tenant, or an empty string.
      Environment [string] -- the cloud of the sign-in, 'Global' when the state records none, or
                              $null without a sign-in.

    .EXAMPLE
    $Info = Get-OPIMCurrentTenantInfo
    if (-not $Info.TenantId) { Write-Warning 'Omnicit.PIM holds no sign-in.' }

    TenantId is the tenant of the module's sign-in, and DisplayName its name, such as 'Contoso Ltd',
    while the module's own Graph session is active.
    #>
    [OutputType([PSCustomObject])]
    param()

    # OPIM-45: the tenant of the module's own sign-in only, never that of a Graph context another
    # Connect-MgGraph started. A state without TokenTenantId -- none, not a dictionary, or the
    # device-code-only state -- is no sign-in, and nothing is read.
    $State = $script:_OPIMAuthState
    if (-not ($State -is [System.Collections.IDictionary]) -or -not $State['TokenTenantId']) {
        return [PSCustomObject]@{
            TenantId    = $null
            DisplayName = ''
            Environment = $null
        }
    }

    [string]$TenantId    = $State['TokenTenantId']
    [string]$DisplayName = ''
    # A12: the cloud of the module's sign-in. A state that records none is the global cloud, the only
    # one before the cloud was recorded (ruling D1).
    [string]$Environment = if ($State['Environment']) { [string]$State['Environment'] } else { 'Global' }

    # The display name only under the module's own Graph session, and only of that tenant: under
    # another session the call would answer for that session's tenant.
    if ((Get-OPIMGraphSessionState) -eq 'Own') {
        # Best-effort: without the scope to read the organization the call fails and the name stays empty.
        try {
            $OrgResponse = Invoke-MgGraphRequest -Uri 'v1.0/organization?$select=displayName,id' -Method GET -Verbose:$false -ErrorAction Stop
            $Organization = @($OrgResponse.value)[0]
            if ($null -ne $Organization -and
                [string]::Equals([string]$Organization.id, $TenantId, [System.StringComparison]::OrdinalIgnoreCase)) {
                $DisplayName = [string]$Organization.displayName
            }
        } catch {
            # The raw record points at the HttpRequestMessage whose Authorization header carries the
            # bearer token in plain text -- scrub it and drop the record first, per module security policy.
            Remove-OPIMErrorRecord -Record $PSItem
        }
    }

    return [PSCustomObject]@{
        TenantId    = $TenantId
        DisplayName = $DisplayName
        Environment = $Environment
    }
}
