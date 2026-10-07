function New-OPIMGraphSessionChangedError {
    <#
    .SYNOPSIS
    Builds the GraphSessionChanged error record.

    .DESCRIPTION
    The single owner of the GraphSessionChanged id and message. Initialize-OPIMAuth raises it at its
    entry and Invoke-OPIMGraphRequest before every Graph call, when the Microsoft Graph PowerShell
    SDK session in the process is not the one this module connected. The target is the module's own
    tenant, the one $script:_OPIMAuthState names. The message names no other tenant, no account and
    no token: the session that replaced the module's may belong to another tenant, and none of its
    values is repeated.

    Nothing in the module takes a changed session back. The message tells the user to run
    Disconnect-OPIM, which also disconnects the other session, and to sign in again.

    .EXAMPLE
    throw (New-OPIMGraphSessionChangedError)

    Refuses the call with the GraphSessionChanged record.

    .OUTPUTS
    [System.Management.Automation.ErrorRecord]
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory error-record builder; returns an ErrorRecord and performs no state change, so ShouldProcess does not apply.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param()

    [string]$Tenant = if ($script:_OPIMAuthState) { [string]$script:_OPIMAuthState.TenantId } else { '' }
    [System.Management.Automation.ErrorRecord]::new(
        [System.Exception]::new(
            "The Microsoft Graph PowerShell SDK session in this PowerShell process has changed since Omnicit.PIM " +
            "connected it for tenant '$Tenant': another Connect-MgGraph has replaced it. Omnicit.PIM does not send " +
            'its Microsoft Graph calls under a session it did not connect, and it does not switch the session back ' +
            "by itself, since that would move the other session's calls to this module's tenant. Run Disconnect-OPIM, " +
            'which also disconnects that session, and sign in again, or use a new PowerShell process.'),
        'GraphSessionChanged',
        [System.Management.Automation.ErrorCategory]::AuthenticationError,
        $Tenant)
}
