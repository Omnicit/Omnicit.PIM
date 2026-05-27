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

    # ── Helper: extract claims from a Graph failure ──────────────────────────
    # Two distinct encodings must be handled:
    #   1. 401 WWW-Authenticate step-up: claims="<base64url-encoded JSON>" (quoted).
    #   2. PIM 400 RoleAssignmentRequestAcrsValidationFailed: the response body carries
    #      &claims=<URL-encoded JSON> (unquoted, e.g. &claims=%7B%22access_token%22...).
    # The decoded result is always the MSAL claims-request JSON, e.g.
    #   {"access_token":{"acrs":{"essential":true,"value":"c1"}}}
    function Get-ClaimsFromException ([System.Management.Automation.ErrorRecord]$ErrorRecord) {
        # Gather every place the challenge might live, most-reliable first.
        $Candidates = [System.Collections.Generic.List[string]]::new()
        try { $Candidates.Add($ErrorRecord.Exception.Response.Headers.WwwAuthenticate.ToString()) } catch { $null = $PSItem }
        try {
            if ($ErrorRecord.Exception.Response -and $ErrorRecord.Exception.Response.Content) {
                $Candidates.Add($ErrorRecord.Exception.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult())
            }
        } catch { $null = $PSItem }
        $Candidates.Add($ErrorRecord.Exception.Message)

        foreach ($Text in $Candidates) {
            # Capture quoted ("...") or unquoted (stop at & / whitespace / quote) value.
            if (-not ($Text -and ($Text -match 'claims=(?:"([^"]+)"|([^"&\s]+))'))) { continue }
            $Encoded = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }

            # 1. URL-encoded JSON (PIM body form).
            if ($Encoded -match '%') {
                $Decoded = [System.Uri]::UnescapeDataString($Encoded)
                if ($Decoded -match '^\s*\{') { return $Decoded }
            }

            # 2. Base64url-encoded JSON (WWW-Authenticate step-up form).
            $Padded = $Encoded.Replace('-', '+').Replace('_', '/')
            switch ($Padded.Length % 4) {
                2 { $Padded += '==' }
                3 { $Padded += '='  }
            }
            try {
                $Decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Padded))
                if ($Decoded -match '^\s*\{') { return $Decoded }
            } catch { $null = $PSItem }

            # 3. Already raw JSON.
            if ($Encoded -match '^\s*\{') { return $Encoded }
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
    # No session-sticky guard: this function retries at most once per call (the retry block
    # below has no loop and a second failure throws), so each command can step up as needed.
    $ClaimsJson = Get-ClaimsFromException $FirstError

    if ($ClaimsJson) {
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

    # ── Token rejected/expired (not a claims challenge) — re-auth and retry ───
    # A 401 here means the bearer token is invalid or expired (claims challenges were already
    # handled above). Force a token refresh (MSAL refresh-token path, usually no prompt) and
    # retry once instead of surfacing the failure.
    $StatusCode = $null
    try { $StatusCode = [int]$FirstError.Exception.Response.StatusCode } catch { $null = $PSItem }
    [bool]$TokenInvalid = $StatusCode -eq 401 -or
        $FirstError.Exception.Message -match 'InvalidAuthenticationToken|CompactToken|token is expired|Lifetime validation failed'

    if ($TokenInvalid -and $script:_OPIMAuthState) {
        Write-Verbose "[Invoke-OPIMGraphRequest] Token rejected (status=$StatusCode). Forcing re-authentication and retrying once..."
        Initialize-OPIMAuth -TenantId $script:_OPIMAuthState.TenantId -ForceRefresh
        try {
            return Invoke-MgGraphRequest @InvokeParams
        } catch {
            $null = $Error.Remove($PSItem)
            throw Convert-GraphHttpException $PSItem
        }
    }

    # ── Not recoverable — convert and re-throw ────────────────────────────────
    throw Convert-GraphHttpException $FirstError
}
