function Get-OPIMTokenTenantId {
    <#
    .SYNOPSIS
    Returns the tenant id (the tid claim) of a Microsoft Graph access token, or $null.

    .DESCRIPTION
    Reads only the payload segment of a JWT-shaped access token: the second of its dot-separated
    segments, base64url-decoded and parsed as a JSON object. It returns the tid claim as a
    lower-case GUID in the D format, or $null when the token is null or empty, has no payload
    segment, does not decode, is not a JSON object, carries no tid claim, or carries a tid that is
    not a GUID.

    The token is taken only as a SecureString, and the plaintext, the payload and the claims are
    handled through .NET calls alone (String.Split, Convert.FromBase64String, Encoding.GetString,
    System.Text.Json.JsonDocument) -- never bound to a cmdlet or function parameter. PowerShell
    module logging (LogPipelineExecutionDetails, event 4103) records the value of every parameter
    bound to a command, so a token passed as a string, or a payload piped to ConvertFrom-Json, would
    reach the event log.

    It never validates the signature (Initialize-OPIMAuth compares the tid with the tenant asked for;
    it is not a trust decision about the token), never throws, and never writes the token, its
    payload or any claim to any stream.

    .PARAMETER AccessToken
    The access token as a SecureString, for example
    [System.Net.NetworkCredential]::new('', $AuthResult.AccessToken).SecurePassword.

    .EXAMPLE
    $TokenTenant = Get-OPIMTokenTenantId -AccessToken $SecureToken

    Returns the GUID of the tenant the token was issued for, or $null when it cannot be read.

    .OUTPUTS
    [string] The lower-case tenant GUID, or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [System.Security.SecureString]$AccessToken
    )

    if ($null -eq $AccessToken -or $AccessToken.Length -eq 0) { return $null }

    $Document = $null
    try {
        $Plain = [System.Net.NetworkCredential]::new('', $AccessToken).Password
        $Segments = $Plain.Split('.')
        if ($Segments.Count -lt 2) { return $null }

        # base64url -> base64: swap the two URL-safe characters back and restore the padding.
        $Payload = $Segments[1].Replace('-', '+').Replace('_', '/')
        switch ($Payload.Length % 4) {
            2 { $Payload += '==' }
            3 { $Payload += '=' }
        }

        $Json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Payload))
        $Document = [System.Text.Json.JsonDocument]::Parse($Json, [System.Text.Json.JsonDocumentOptions]::new())
        if ($Document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { return $null }

        $TidElement = [System.Text.Json.JsonElement]::new()
        if (-not $Document.RootElement.TryGetProperty('tid', [ref]$TidElement)) { return $null }
        if ($TidElement.ValueKind -ne [System.Text.Json.JsonValueKind]::String) { return $null }
        $Tid = $TidElement.GetString()
    } catch {
        # This file reaches no transport, and a decode failure carries no request: nothing to scrub.
        $null = $PSItem
        return $null
    } finally {
        if ($Document) { $Document.Dispose() }
    }

    $Parsed = [guid]::Empty
    if (-not [guid]::TryParse($Tid, [ref]$Parsed)) { return $null }
    $Parsed.ToString('D')
}
