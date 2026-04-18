function Invoke-OPIMGraphRequest {
    <#
    .SYNOPSIS
    Wraps Invoke-MgGraphRequest with bearer-token security, ACRS claims-challenge handling,
    and consistent error conversion.

    .DESCRIPTION
    Drop-in replacement for Invoke-MgGraphRequest used by every public and private function in
    Omnicit.PIM. Adds three layers on top of the raw Graph SDK call:

    1. Bearer token security: the $Error record that contains the raw HttpRequestMessage
       (which carries the Authorization: Bearer header in plain text) is removed from $Error
       immediately in every catch block.

    2. ACRS claims-challenge retry: when Microsoft Graph returns a 401 response whose
       WWW-Authenticate header contains a claims="<base64url>" challenge, this function:
         a. Base64url-decodes the challenge to a JSON string.
         b. Calls Initialize-OPIMAuth -ClaimsChallenge to perform a one-time interactive
            step-up authentication.
         c. Retries the original request exactly once.
       A second 401 (after a successful step-up) is surfaced as a normal error.

    3. Error conversion: non-claims errors are run through Convert-GraphHttpException to
       produce structured ErrorRecord objects with the Graph error.code as the
       FullyQualifiedErrorId. The caller receives either a response or a thrown ErrorRecord —
       no _AcrsError hashtable protocol.

    .PARAMETER Method
    HTTP method for the Graph request. Defaults to GET.

    .PARAMETER Uri
    Graph API URI, e.g. 'v1.0/roleManagement/directory/roleEligibilitySchedules'.

    .PARAMETER Body
    Optional request body hashtable (for POST/PATCH requests).

    .OUTPUTS
    The Graph API response hashtable on success.

    .EXAMPLE
    $Items = (Invoke-OPIMGraphRequest -Uri 'v1.0/roleManagement/directory/roleEligibilitySchedules/filterByCurrentUser(on=''principal'')').value

    .EXAMPLE
    $Response = Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleAssignmentScheduleRequests' -Body $Request
    #>
    [OutputType([object])]
    param(
        [string]$Method = 'GET',
        [Parameter(Mandatory)]
        [string]$Uri,
        [hashtable]$Body
    )

    # ── Helper: extract claims from a WWW-Authenticate header ─────────────────
    function Get-ClaimsFromException ([System.Management.Automation.ErrorRecord]$ErrorRecord) {
        # Try the structured HTTP response headers first (most reliable)
        $WwwAuth = $null
        try {
            $WwwAuth = $ErrorRecord.Exception.Response.Headers.WwwAuthenticate.ToString()
        } catch { }

        # Fallback: the Graph SDK sometimes embeds the header value in the exception message
        if (-not $WwwAuth) {
            $WwwAuth = $ErrorRecord.Exception.Message
        }

        if ($WwwAuth -and ($WwwAuth -match 'claims="([^"]+)"')) {
            $Encoded = $Matches[1]
            # Base64url → standard Base64 padding
            $Padded  = $Encoded.Replace('-', '+').Replace('_', '/')
            switch ($Padded.Length % 4) {
                2 { $Padded += '==' }
                3 { $Padded += '='  }
            }
            try {
                return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Padded))
            } catch {
                # Not base64-encoded — may already be JSON (rare but handle gracefully)
                if ($Encoded -match '^\{') { return $Encoded }
            }
        }
        return $null
    }

    # ── First attempt ─────────────────────────────────────────────────────────
    $InvokeParams = @{
        Method      = $Method
        Uri         = $Uri
        Verbose     = $false
        ErrorAction = 'Stop'
    }
    if ($Body) { $InvokeParams.Body = $Body }

    try {
        return Invoke-MgGraphRequest @InvokeParams
    } catch {
        # Security: remove the raw error record before anything else.
        # The TargetObject (HttpRequestMessage) contains "Authorization: Bearer <token>".
        $null = $Error.Remove($PSItem)
        $FirstError = $PSItem
    }

    # ── Check for ACRS claims challenge on the first failure ──────────────────
    $ClaimsJson = Get-ClaimsFromException $FirstError

    if ($ClaimsJson -and -not $script:_OPIMAuthState.ClaimsSatisfied) {
        Write-Verbose "[Invoke-OPIMGraphRequest] ACRS claims challenge detected. Performing step-up authentication..."
        Write-Verbose "[Invoke-OPIMGraphRequest] Claims: $ClaimsJson"

        $TenantId = $script:_OPIMAuthState.TenantId
        Initialize-OPIMAuth -TenantId $TenantId -ClaimsChallenge $ClaimsJson

        # ── Retry once with the upgraded token ────────────────────────────────
        try {
            return Invoke-MgGraphRequest @InvokeParams
        } catch {
            $null = $Error.Remove($PSItem)
            throw Convert-GraphHttpException $PSItem
        }
    }

    # ── Not a claims challenge (or already retried) — convert and re-throw ────
    throw Convert-GraphHttpException $FirstError
}
