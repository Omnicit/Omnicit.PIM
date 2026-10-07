function Get-OPIMTokenTenantId {
    <#
    .SYNOPSIS
    Returns the tenant id (the tid claim) of a Microsoft Graph access token, or $null.

    .DESCRIPTION
    Reads only the payload segment of a JWT-shaped access token: the second of its dot-separated
    segments, base64url-decoded and parsed as JSON. It returns the tid claim as a lower-case GUID in
    the D format, or $null when the value is empty, has no payload segment, does not decode, is not
    JSON, carries no tid claim, or carries a tid that is not a GUID.

    It never validates the signature (Initialize-OPIMAuth compares the tid with the tenant asked for;
    it is not a trust decision about the token), never throws, and never writes the token, its
    payload or any claim to any stream.

    .PARAMETER AccessToken
    The access token string, as MSAL returns it in AuthenticationResult.AccessToken.

    .EXAMPLE
    $TokenTenant = Get-OPIMTokenTenantId -AccessToken $AuthResult.AccessToken

    Returns the GUID of the tenant the token was issued for, or $null when it cannot be read.

    .OUTPUTS
    [string] The lower-case tenant GUID, or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$AccessToken
    )

    if ([string]::IsNullOrEmpty($AccessToken)) { return $null }
    $Segments = $AccessToken.Split('.')
    if ($Segments.Count -lt 2) { return $null }

    # base64url -> base64: swap the two URL-safe characters back and restore the padding.
    $Payload = $Segments[1].Replace('-', '+').Replace('_', '/')
    switch ($Payload.Length % 4) {
        2 { $Payload += '==' }
        3 { $Payload += '=' }
    }

    try {
        $Json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Payload))
        $Tid = [string]($Json | ConvertFrom-Json -ErrorAction Stop).tid
    } catch {
        # This file reaches no transport, and a decode failure carries no request: nothing to scrub.
        $null = $PSItem
        return $null
    }

    $Parsed = [guid]::Empty
    if (-not [guid]::TryParse($Tid, [ref]$Parsed)) { return $null }
    $Parsed.ToString('D')
}
