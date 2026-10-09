function Disconnect-OPIM {
    <#
    .SYNOPSIS
    Clear the module's tokens and disconnect the Microsoft Graph session.

    .DESCRIPTION
    Clears the module's tokens, the Azure Resource Manager token included, and disconnects the
    Microsoft Graph session; AzAuth keeps its own sign-in in the PowerShell process until the
    module's next Azure sign-in rebuilds it or the process ends.

    It clears the module-scoped authentication state ($script:_OPIMAuthState) and the cached MSAL
    PublicClientApplication with its tenant, whose in-memory cache holds the Microsoft Graph tokens.
    The module's Azure Resource Manager token lives only in that state, so it is cleared with it.
    Then it calls Disconnect-MgGraph to end the Microsoft Graph SDK session of this PowerShell
    process. Clearing the auth state also forgets a device code sign-in mode (-DeviceCode), so the
    next sign-in uses the system browser unless -DeviceCode is given again.

    AzAuth, which signs in to Azure, keeps a credential of its own in the process, which
    Disconnect-OPIM cannot clear. The module's first Azure sign-in after Disconnect-OPIM rebuilds it
    (Get-AzToken -Force) instead of reusing it; otherwise it ends with the PowerShell process.

    After calling Disconnect-OPIM, the next PIM cmdlet (or an explicit Connect-OPIM) will
    trigger a fresh authentication prompt: in the system browser, or with a device code when
    -DeviceCode is given again.

    .EXAMPLE
    Disconnect-OPIM
    Clears the module's tokens, the Azure Resource Manager token included, and disconnects the
    Microsoft Graph session; AzAuth keeps its own sign-in in the PowerShell process until the
    module's next Azure sign-in rebuilds it or the process ends.
    #>
    [Alias('Disconnect-PIM')]
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # The Azure Resource Manager token is a SecureString in the auth state and nowhere else, so this
    # line clears it too.
    $script:_OPIMAuthState = $null
    $script:_OPIMMsalApp   = $null
    $script:_OPIMMsalAppTenantId = $null

    try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch { $null = $PSItem }

    Write-Verbose '[Disconnect-OPIM] Session tokens cleared, the Azure Resource Manager token with them, and the Graph session disconnected.'
}
