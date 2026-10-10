<#
    A failed-request fixture for Omnicit.PIM unit tests.

    New-ScrubFixture builds a failed Graph call as the SDK leaves it: a request message carrying an
    Authorization header, the response pointing back at it, an HttpResponseException holding the
    response and an ErrorRecord that targets the request. It is how a test proves that a catch
    scrubs the bearer token. This is a helper, not a Pester file: it reaches no module code and no
    transport. The token is built at runtime and says what it is, NOT-A-REAL-TOKEN, so no
    token-shaped literal sits in any test file.
    Dot-source this file in a test file's root BeforeAll, after the tripwire:

        . "$PSScriptRoot/../TestHelpers/OPIMScrubFixture.ps1"
#>

function New-ScrubFixture {
    <#
    .SYNOPSIS
    Builds a failed Graph request as the SDK leaves it, with an Authorization header a scrub must remove.

    .DESCRIPTION
    Returns an object with three members: Request, an HttpRequestMessage that carries an
    Authorization header; Exception, an HttpResponseException whose response points back at that
    same request message; and Record, an ErrorRecord with the id HttpFail, the category
    InvalidOperation and the request as its target. The header value is built at runtime and ends in
    NOT-A-REAL-TOKEN, so it is no token and no token-shaped literal sits in a test file.

    .PARAMETER Status
    The HTTP status code of the response. Defaults to 403.

    .PARAMETER Content
    The body of the response. Defaults to a Graph Authorization_RequestDenied error body.

    .PARAMETER RetryAfter
    The value of a Retry-After header on the response. The header is added only when this is given.

    .PARAMETER Uri
    The uri of the request message. Defaults to https://graph.microsoft.com/v1.0/me.

    .PARAMETER TokenShape
    Plain builds Bearer, forty x characters and NOT-A-REAL-TOKEN. Jwt builds Bearer, eyJ, twenty A
    characters, a dot and NOT-A-REAL-TOKEN, the shape of a real token, which a test that looks for
    eyJ in a rendered error needs. Defaults to Plain.
    #>
    [CmdletBinding()]
    param(
        [int]$Status = 403,
        [string]$Content = '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges."}}',
        [string]$RetryAfter,
        [string]$Uri = 'https://graph.microsoft.com/v1.0/me',
        [ValidateSet('Plain', 'Jwt')]
        [string]$TokenShape = 'Plain'
    )
    $Token = if ($TokenShape -eq 'Jwt') {
        'Bearer ' + 'eyJ' + ('A' * 20) + '.' + 'NOT-A-REAL-TOKEN'
    } else {
        'Bearer ' + ('x' * 40) + 'NOT-A-REAL-TOKEN'
    }
    $Request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $Uri)
    $null = $Request.Headers.TryAddWithoutValidation('Authorization', $Token)
    $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Status)
    $Response.RequestMessage = $Request
    $Response.Content = [System.Net.Http.StringContent]::new($Content)
    if ($RetryAfter) { $null = $Response.Headers.TryAddWithoutValidation('Retry-After', $RetryAfter) }
    $Exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Response status code does not indicate success.', $Response)
    [pscustomobject]@{
        Request   = $Request
        Exception = $Exception
        Record    = [System.Management.Automation.ErrorRecord]::new($Exception, 'HttpFail', 'InvalidOperation', $Request)
    }
}
