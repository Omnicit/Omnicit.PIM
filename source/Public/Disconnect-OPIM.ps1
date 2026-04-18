function Disconnect-OPIM {
    <#
    .SYNOPSIS
    Clear all Omnicit.PIM session tokens and disconnect from Microsoft Graph and Azure.

    .DESCRIPTION
    Clears the module-scoped authentication state ($script:_OPIMAuthState), the cached MSAL
    PublicClientApplication, and the cached user-ID lookup table. Then calls Disconnect-MgGraph
    and Disconnect-AzAccount to invalidate those sessions.

    After calling Disconnect-OPIM, the next PIM cmdlet (or an explicit Connect-OPIM) will
    trigger a fresh browser authentication prompt.

    .EXAMPLE
    Disconnect-OPIM
    Clear all cached tokens and disconnect both Graph and Azure sessions.
    #>
    [Alias('Disconnect-PIM')]
    [CmdletBinding()]
    param()

    $script:_OPIMAuthState = $null
    $script:_OPIMMsalApp   = $null
    $script:_OPIMMsalAppTenantId = $null
    $script:_MyIDCache     = $null

    try { Disconnect-MgGraph   -ErrorAction SilentlyContinue | Out-Null } catch { }
    try { Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null } catch { }

    Write-Verbose '[Disconnect-OPIM] Session tokens cleared and Graph/Azure sessions disconnected.'
}
