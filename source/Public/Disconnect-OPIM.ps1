function Disconnect-OPIM {
    <#
    .SYNOPSIS
    Clear all Omnicit.PIM session tokens and disconnect from Microsoft Graph and Azure.

    .DESCRIPTION
    Clears the module-scoped authentication state ($script:_OPIMAuthState) and the cached MSAL
    PublicClientApplication with its tenant. Then calls Disconnect-MgGraph
    and Disconnect-AzAccount to invalidate those sessions. Clearing the auth state also forgets a
    device code sign-in mode (-DeviceCode), so the next sign-in uses the system browser unless
    -DeviceCode is given again.

    After calling Disconnect-OPIM, the next PIM cmdlet (or an explicit Connect-OPIM) will
    trigger a fresh authentication prompt: in the system browser, or with a device code when
    -DeviceCode is given again.

    .EXAMPLE
    Disconnect-OPIM
    Clear all cached tokens and disconnect both Graph and Azure sessions.
    #>
    [Alias('Disconnect-PIM')]
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $script:_OPIMAuthState = $null
    $script:_OPIMMsalApp   = $null
    $script:_OPIMMsalAppTenantId = $null

    try { Disconnect-MgGraph   -ErrorAction SilentlyContinue | Out-Null } catch { $null = $PSItem }
    try { Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null } catch { $null = $PSItem }

    Write-Verbose '[Disconnect-OPIM] Session tokens cleared and Graph/Azure sessions disconnected.'
}
