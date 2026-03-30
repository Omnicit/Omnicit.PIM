function Get-MyId ($user) {
    <#
    .SYNOPSIS
    Returns the Entra ID object GUID of the currently authenticated Graph user.

    .DESCRIPTION
    Retrieves the object GUID for the user account currently connected to Microsoft Graph via
    Get-MgContext. The result is cached in a module-scope dictionary keyed by user principal name
    so subsequent calls within the same session avoid a repeat Microsoft Graph API call.

    .PARAMETER user
    The user principal name (UPN) to resolve. When omitted the UPN is read from the active
    Microsoft Graph context returned by Get-MgContext. Supply this parameter to resolve a
    specific UPN or to bypass the context lookup when the UPN is already known.

    .EXAMPLE
    Get-MyId

    Returns the Guid representing the current user's Entra ID object ID using the active Graph context.
    #>

    #module scoped cache of the user's GUID
    if (-not $SCRIPT:_MyIDCache) { $SCRIPT:_MyIDCache = [Collections.Generic.Dictionary[String, Guid]]@{} }

    if (-not $user) {
        $context = Get-MgContext
        if (-not $context) { throw 'You are not connected to Microsoft Graph. Please run connect-mggraph first.' }
        $user = $context.Account
    }

    #Cache Hit
    $result = $SCRIPT:_MyIDCache[$user]
    if ($null -ne $result) {
        return $result
    }

    #Cache Miss
    $response = Invoke-MgGraphRequest -Uri 'v1.0/me' -Body @{select = 'userPrincipalName,id' }
    if ($response.userprincipalname -notmatch $context.account) { throw 'The userPrincipalName in the response does not match your Mg context. This is probably a bug, please report it.' }
    $SCRIPT:_MYIDCache[$response.userPrincipalName] = $response.id
    return [guid]($response.id)
}
