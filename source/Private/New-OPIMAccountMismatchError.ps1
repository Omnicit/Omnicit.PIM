function New-OPIMAccountMismatchError {
    <#
    .SYNOPSIS
    Builds the AccountMismatch error record for a token of another account than the session's.

    .DESCRIPTION
    Returns a new ErrorRecord with the FullyQualifiedErrorId AccountMismatch, the category
    AuthenticationError and the requested tenant as its target object. It neither writes nor throws
    the record; the caller raises it, for example with
    Write-CmdletError -ErrorRecord $Record -Cmdlet $PSCmdlet -Terminating.

    Initialize-OPIMAuth raises it when the oid claim of an Azure Resource Manager token differs from
    the oid of the session's Microsoft Graph token (A3): the ARM token was issued to another account
    than the one the Graph session signed in with. With -Unreadable it says instead that the account
    could not be compared at all -- the ARM token carries no readable oid, or the session records
    none. Either way the token was not used and nothing was sent to Azure.

    With -Source Graph it is the refusal of a new Microsoft Graph sign-in that continues the session
    -- a renewal near the token's expiry, the token-rejected retry or an ACRS step-up, for the
    session's tenant and cloud -- but was answered by another account than the one the session signed
    in with (ported from Omnicit.EntraRBAC BL-119, where the same refusal is SignInSuperseded). The
    token was not used: the session stays the account it was, and the message says to run
    Disconnect-OPIM before signing in as another account.

    The message names only the tenant of the session, never an account or an object id, so the record
    can be shown without disclosing either account.

    .PARAMETER RequestedTenant
    The tenant of the session's Microsoft Graph sign-in, which the ARM token was requested for. It is
    the record's target object and the only value the message names.

    .PARAMETER Source
    'Azure' (the default) for an Azure Resource Manager token, 'Graph' for a new Microsoft Graph token
    of a sign-in that continues the session.

    .PARAMETER Unreadable
    Says that the account of the token could not be read or compared, instead of that it differs.
    Azure only: a Microsoft Graph token whose account cannot be read is never refused.

    .EXAMPLE
    Write-CmdletError -ErrorRecord (New-OPIMAccountMismatchError -RequestedTenant $ArmTenant) -Cmdlet $PSCmdlet -Terminating

    Ends the calling function with AccountMismatch for an ARM token of another account.

    .OUTPUTS
    [System.Management.Automation.ErrorRecord]
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory error-record builder')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [string]$RequestedTenant,

        [ValidateSet('Azure', 'Graph')]
        [string]$Source = 'Azure',

        [switch]$Unreadable
    )

    $Message = if ($Source -eq 'Graph') {
        "The new Microsoft Graph sign-in in '$RequestedTenant' was answered by another account than the one this session signed in with. Omnicit.PIM did not use the token and sent nothing, and the session stays signed in as it was. Sign in with the session's account, or run Disconnect-OPIM and then sign in again to use another account."
    } elseif ($Unreadable) {
        "The account of the Azure Resource Manager token could not be read, so Omnicit.PIM cannot verify that it is the account of this session's Microsoft Graph sign-in in '$RequestedTenant'. The token was not used and nothing was sent to Azure."
    } else {
        "The Azure Resource Manager token was issued to another account than this session's Microsoft Graph sign-in in '$RequestedTenant'. Omnicit.PIM did not use the token and sent nothing to Azure. Run Disconnect-OPIM, then sign in to Microsoft Graph and Azure with the same account."
    }

    [System.Management.Automation.ErrorRecord]::new(
        [System.Exception]::new($Message),
        'AccountMismatch',
        [System.Management.Automation.ErrorCategory]::AuthenticationError,
        $RequestedTenant
    )
}
