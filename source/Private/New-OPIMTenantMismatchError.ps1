function New-OPIMTenantMismatchError {
    <#
    .SYNOPSIS
    Builds the TenantMismatch error record for a token or an Azure context of another tenant.

    .DESCRIPTION
    Returns a new ErrorRecord with the FullyQualifiedErrorId TenantMismatch, the category
    AuthenticationError and the requested tenant as its target object. It neither writes nor
    throws the record; the caller raises it, for example with
    Write-CmdletError -ErrorRecord $Record -Cmdlet $PSCmdlet -Terminating.

    The message names only the tenant that was asked for, never the tenant the token or the context
    was issued for, so the record can be shown without disclosing the other tenant.

    -Source Graph (the default) is for a Microsoft Graph token whose tid differs from the tenant the
    session signs in to, and -Unreadable for a Graph token whose tid cannot be read at all.
    -Source Azure is for Azure signed in to another tenant than the Graph session's: an Azure
    Resource Manager token whose tid differs from the tenant of the Graph token, or an Azure context
    of another tenant. With -Unreadable it is for an Azure Resource Manager token whose tid cannot be
    read.

    .PARAMETER RequestedTenant
    The tenant the session signs in to: the GUID or domain asked for, or the session's pinned
    tenant. It is the record's target object and the only tenant the message names.

    .PARAMETER Source
    Graph for a Microsoft Graph token, Azure for an Azure Resource Manager token or an Azure context.
    Defaults to Graph.

    .PARAMETER Unreadable
    Says that the tenant of the token could not be read, instead of that it differs. Applies to both
    sources: the Microsoft Graph token with -Source Graph, the Azure Resource Manager token with
    -Source Azure.

    .EXAMPLE
    Write-CmdletError -ErrorRecord (New-OPIMTenantMismatchError -RequestedTenant $EffectiveTenant) -Cmdlet $PSCmdlet -Terminating

    Ends the calling function with TenantMismatch for a Graph token of another tenant.

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

        [ValidateSet('Graph', 'Azure')]
        [string]$Source = 'Graph',

        [switch]$Unreadable
    )

    $Message = if ($Source -eq 'Azure' -and $Unreadable) {
        "The tenant of the Azure Resource Manager token could not be read, so Omnicit.PIM cannot verify that it was issued for '$RequestedTenant', the tenant of this session's Microsoft Graph sign-in. The token was not used and nothing was sent to Azure."
    } elseif ($Source -eq 'Azure') {
        "Azure is signed in to another tenant than '$RequestedTenant', the tenant of this session's Microsoft Graph sign-in. Omnicit.PIM sends no Azure request under it. Run Connect-OPIM -IncludeARM, or Disconnect-OPIM and sign in again."
    } elseif ($Unreadable) {
        "The tenant of the Microsoft Graph token could not be read, so Omnicit.PIM cannot verify that it was issued for '$RequestedTenant'. The token was not used and nothing was sent."
    } else {
        "The Microsoft Graph token was issued for another tenant than '$RequestedTenant', the tenant this session signs in to. Omnicit.PIM did not use the token and sent nothing. Run Connect-OPIM -TenantId with the tenant you mean, or Disconnect-OPIM and sign in again."
    }

    [System.Management.Automation.ErrorRecord]::new(
        [System.Exception]::new($Message),
        'TenantMismatch',
        [System.Management.Automation.ErrorCategory]::AuthenticationError,
        $RequestedTenant
    )
}
