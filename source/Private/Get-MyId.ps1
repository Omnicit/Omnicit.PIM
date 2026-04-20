function Get-MyId ($User) {
    <#
    .SYNOPSIS
    Returns the Entra ID object GUID of the currently authenticated Graph user.

    .DESCRIPTION
    Retrieves the object GUID for the user account currently connected to Microsoft Graph via
    Get-MgContext. The result is cached in a module-scope dictionary keyed by user principal name
    so subsequent calls within the same session avoid a repeat Microsoft Graph API call.

    .PARAMETER User
    The user principal name (UPN) to resolve. When omitted the UPN is read from the active
    Microsoft Graph context returned by Get-MgContext. Supply this parameter to resolve a
    specific UPN or to bypass the context lookup when the UPN is already known.

    .EXAMPLE
    Get-MyId

    Returns the Guid representing the current user's Entra ID object ID using the active Graph context.
    #>

    #module scoped cache of the user's GUID
    if (-not $script:_MyIDCache) { $script:_MyIDCache = [Collections.Generic.Dictionary[String, Guid]]@{} }

    if (-not $User) {
        $Context = Get-MgContext
        if (-not $Context) { throw 'Not connected. Run any Get-OPIM*/Enable-OPIM* cmdlet or call Connect-OPIM.' }
        $User = $Context.Account
    }

    #Cache Hit
    $Result = $script:_MyIDCache[$User]
    if ($null -ne $Result) {
        return $Result
    }

    #Cache Miss
    $Response = Invoke-OPIMGraphRequest -Uri 'v1.0/me'
    if ($Response.userprincipalname -notmatch $User) { throw 'The userPrincipalName in the response does not match the requested user. This is probably a bug, please report it.' }
    $script:_MyIDCache[$Response.userPrincipalName] = $Response.id
    return [guid]($Response.id)
}
