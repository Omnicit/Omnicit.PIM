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
    if (-not $script:_MyIDCache) { $script:_MyIDCache = [Collections.Generic.Dictionary[String, Guid]]@{} }

    if (-not $user) {
        $Context = Get-MgContext
        if (-not $Context) { throw 'You are not connected to Microsoft Graph. Please run connect-mggraph first.' }
        $user = $Context.Account
    }

    #Cache Hit
    $Result = $script:_MyIDCache[$user]
    if ($null -ne $Result) {
        return $Result
    }

    #Cache Miss
    $Response = Invoke-MgGraphRequest -Uri 'v1.0/me' -Body @{select = 'userPrincipalName,id' } -Verbose:$false -ErrorAction Stop
    if ($Response.userprincipalname -notmatch $Context.Account) { throw 'The userPrincipalName in the response does not match your Mg context. This is probably a bug, please report it.' }
    $script:_MyIDCache[$Response.userPrincipalName] = $Response.id
    return [guid]($Response.id)
}
