function Get-OPIMCurrentTenantInfo {
    <#
    .SYNOPSIS
    Returns the TenantId and display name for the currently connected Graph tenant.

    .DESCRIPTION
    Reads the active Microsoft Graph context via Get-MgContext and performs a best-effort
    call to the v1.0/organization endpoint to retrieve the tenant display name.

    The display name call silently fails when the Organization.Read.All scope is absent — in
    that case DisplayName is returned as an empty string. Both fields are null when no active
    Graph session exists.

    This helper is used by Install-, Set-, and Remove-OPIMConfiguration to enrich the
    ShouldProcess confirmation prompt and to auto-resolve TenantId when not supplied.

    .OUTPUTS
    PSCustomObject with:
      TenantId    [string] — the Entra ID tenant GUID, or $null if not connected.
      DisplayName [string] — the tenant display name, or empty string if unavailable.

    .EXAMPLE
    $Info = Get-OPIMCurrentTenantInfo
    # Returns e.g. @{ TenantId = 'aaaabbbb-...'; DisplayName = 'Contoso Ltd' }
    # TenantId and DisplayName are both $null when no active Graph session exists.
    #>
    [OutputType([PSCustomObject])]
    param()

    $Context = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $Context) {
        return [PSCustomObject]@{
            TenantId    = $null
            DisplayName = $null
        }
    }

    [string]$TenantId    = $Context.TenantId
    [string]$DisplayName = ''

    # Best-effort: retrieve tenant display name from the organization endpoint.
    # Requires Organization.Read.All — silently falls back to empty string on any failure.
    try {
        $OrgResponse = Invoke-MgGraphRequest -Uri 'v1.0/organization?$select=displayName,id' -Method GET -Verbose:$false -ErrorAction Stop
        if ($OrgResponse.value.Count -gt 0) {
            $DisplayName = [string]$OrgResponse.value[0].displayName
        }
    } catch {
        # $Error entry contains the raw HttpRequestMessage with the Authorization: Bearer
        # header in plain text — remove it immediately per module security policy.
        $null = $Error.Remove($PSItem)
    }

    return [PSCustomObject]@{
        TenantId    = $TenantId
        DisplayName = $DisplayName
    }
}
