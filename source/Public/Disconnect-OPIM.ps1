function Disconnect-OPIM {
    <#
    .SYNOPSIS
    Clear the module's tokens and disconnect the Microsoft Graph session.

    .DESCRIPTION
    Clears the module's tokens, the Azure Resource Manager token included, and disconnects the
    Microsoft Graph session; AzAuth keeps its own sign-in, for Microsoft Graph and for Azure, in the
    PowerShell process until the module's next sign-in rebuilds it or the process ends.

    It clears the module-scoped authentication state ($script:_OPIMAuthState). The module's Azure
    Resource Manager token lives only in that state, so it is cleared with it; the Microsoft Graph
    token lives in the Graph SDK's session.
    Then it calls Disconnect-MgGraph to end the Microsoft Graph SDK session of this PowerShell
    process. Clearing the auth state also forgets a device code sign-in mode (-DeviceCode), so the
    next sign-in uses the system browser unless -DeviceCode is given again.

    AzAuth, which signs in to Microsoft Graph and to Azure, keeps a credential of its own in the
    process, which Disconnect-OPIM cannot clear. AzAuth builds a new credential for every sign-in in
    the system browser, and the module asks it to rebuild one (Get-AzToken -Force) for every device
    code sign-in and every switch of cloud; otherwise it ends with the PowerShell process.

    After calling Disconnect-OPIM, the next PIM cmdlet (or an explicit Connect-OPIM) will
    trigger a fresh authentication prompt: in the system browser, or with a device code when
    -DeviceCode is given again.

    .EXAMPLE
    Disconnect-OPIM
    Clears the module's tokens, the Azure Resource Manager token included, and disconnects the
    Microsoft Graph session; AzAuth keeps its own sign-in, for Microsoft Graph and for Azure, in the
    PowerShell process until the module's next sign-in rebuilds it or the process ends.
    #>
    [Alias('Disconnect-PIM')]
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # The Azure Resource Manager token is a SecureString in the auth state and nowhere else, so this
    # line clears it too. $script:_OPIMLastAuthorityHost is left as it is: it records where AzAuth's
    # process-wide credential was last built, and that credential outlives this command.
    $script:_OPIMAuthState = $null

    try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch { $null = $PSItem }

    Write-Verbose '[Disconnect-OPIM] Session tokens cleared, the Azure Resource Manager token with them, and the Graph session disconnected.'
}
