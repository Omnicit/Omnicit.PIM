function New-OPIMAccountMismatchError {
    <#
    .SYNOPSIS
    Builds the AccountMismatch error record for an Azure Resource Manager token of another account.

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

    The message names only the tenant of the session, never an account or an object id, so the record
    can be shown without disclosing either account.

    .PARAMETER RequestedTenant
    The tenant of the session's Microsoft Graph sign-in, which the ARM token was requested for. It is
    the record's target object and the only value the message names.

    .PARAMETER Unreadable
    Says that the account of the token could not be read or compared, instead of that it differs.

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

        [switch]$Unreadable
    )

    $Message = if ($Unreadable) {
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
