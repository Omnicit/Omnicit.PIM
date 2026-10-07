<#
    Token-shaped test fixtures for Omnicit.PIM unit tests.

    New-OPIMTestAccessToken builds a header.payload.signature string at runtime, so no token-shaped
    literal sits in any test file. It is NOT-A-REAL-TOKEN: the header names no algorithm, the
    signature segment is the text NOT-A-REAL-TOKEN, and the payload carries only placeholder claims.
    Dot-source this file in a test file's root BeforeAll, after the tripwire:

        . "$PSScriptRoot/../TestHelpers/OPIMTestToken.ps1"
#>

function ConvertTo-OPIMTestBase64Url {
    <#
    .SYNOPSIS
    Encodes a string as UTF-8 base64url without padding, as a JWT segment is encoded.
    #>
    param([string]$Text)
    [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-OPIMTestAccessToken {
    <#
    .SYNOPSIS
    Builds a token-shaped test fixture at runtime. It is NOT-A-REAL-TOKEN: no signature, no secret.

    .DESCRIPTION
    Returns header.payload.signature. The payload is the JSON object
    { aud, iss, tid, oid, upn, scp, ver, x-fixture } with the tenant given, base64url-encoded; the
    signature segment is NOT-A-REAL-TOKEN. -NoTenant leaves the tid claim out.

    .PARAMETER TenantId
    The value of the tid claim. Defaults to the all-ones placeholder, which is not a version-4 id.

    .PARAMETER NoTenant
    Leaves the tid claim out of the payload.
    #>
    param(
        [string]$TenantId = '11111111-1111-1111-1111-111111111111',
        [switch]$NoTenant
    )
    $Claims = [ordered]@{
        aud         = 'https://graph.microsoft.com'
        iss         = "https://sts.windows.net/$TenantId/"
        tid         = $TenantId
        oid         = '00000000-0000-0000-0000-000000000000'
        upn         = 'user@contoso.com'
        scp         = 'User.Read'
        ver         = '1.0'
        'x-fixture' = 'NOT-A-REAL-TOKEN'
    }
    if ($NoTenant) { $Claims.Remove('tid') }
    $Header = ConvertTo-OPIMTestBase64Url '{"typ":"JWT","alg":"none"}'
    $Payload = ConvertTo-OPIMTestBase64Url ($Claims | ConvertTo-Json -Compress)
    '{0}.{1}.NOT-A-REAL-TOKEN' -f $Header, $Payload
}
