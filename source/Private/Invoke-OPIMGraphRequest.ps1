function Invoke-OPIMGraphRequest {
    <#
    .SYNOPSIS
    Wraps Invoke-MgGraphRequest with bearer-token security, ACRS claims-challenge handling,
    and consistent error conversion.

    .DESCRIPTION
    Drop-in replacement for Invoke-MgGraphRequest used by every public and private function in
    Omnicit.PIM. Adds five layers on top of the raw Graph SDK call:

    1. Bearer token security: every catch block starts with Remove-OPIMErrorRecord, which clears
       the Authorization header off the raw HttpRequestMessage the SDK record points at (the
       header carries the bearer token in plain text) and removes the record from the caller's
       $global:Error. Clearing the header on the shared request object also disarms every copy of
       the record that already escaped, such as the caller's -ErrorVariable. The idiom this
       replaced, $Error.Remove($PSItem), removed nothing: a module's $Error is its own private
       list, and the record bound to $PSItem is not the instance PowerShell stored.

    2. ACRS claims-challenge retry: when Microsoft Graph returns a 401 response whose
       WWW-Authenticate header contains a claims="<base64url>" challenge, this function:
         a. Base64url-decodes the challenge to a JSON string.
         b. Calls Initialize-OPIMAuth -ClaimsChallenge to perform a one-time interactive
            step-up authentication.
         c. Retries the original request exactly once.
       A second 401 (after a successful step-up) is surfaced as a normal error.

    3. Error conversion: non-claims errors are run through Convert-GraphHttpException to
       produce structured ErrorRecord objects with the Graph error.code as the
       FullyQualifiedErrorId. The caller receives either a response or a thrown ErrorRecord --
       no _AcrsError hashtable protocol.

    4. Graph SDK session gate: before the first attempt and before each retry it asks
       Get-OPIMGraphSessionState whether the Microsoft Graph PowerShell SDK session is still the
       one Initialize-OPIMAuth connected, and throws GraphSessionChanged, sending nothing, when
       another Connect-MgGraph has replaced it. The gate stands outside the try that sends, and
       returns after its throw, so a caller under -ErrorAction SilentlyContinue sends nothing either.

    5. Sign-in latch gate: straight after each session gate it asks Get-OPIMSignInRefusal whether a
       command on the call stack is latched -- its sign-in was refused and it carried on past the
       refusal -- and throws SignInRefused, sending nothing, when one is. A retry whose own sign-in
       is refused latches this function itself, which calls Initialize-OPIMAuth from its own body,
       so the retry's gate refuses it. The gate stands outside the try that sends and returns after
       its throw, as the session gate does.

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

    # -- Helper: extract claims from a Graph failure --------------------------
    # Two distinct encodings must be handled:
    #   1. 401 WWW-Authenticate step-up: claims="<base64url-encoded JSON>" (quoted).
    #   2. PIM 400 RoleAssignmentRequestAcrsValidationFailed: the response body carries
    #      &claims=<URL-encoded JSON> (unquoted, e.g. &claims=%7B%22access_token%22...).
    # The decoded result is always the MSAL claims-request JSON, e.g.
    #   {"access_token":{"acrs":{"essential":true,"value":"c1"}}}
    function Get-ClaimsFromException ([System.Management.Automation.ErrorRecord]$ErrorRecord) {
        # Gather every place the challenge might live, most-reliable first.
        $Candidates = [System.Collections.Generic.List[string]]::new()
        try { $Candidates.Add($ErrorRecord.Exception.Response.Headers.WwwAuthenticate.ToString()) } catch { Remove-OPIMErrorRecord -Record $PSItem }
        try {
            if ($ErrorRecord.Exception.Response -and $ErrorRecord.Exception.Response.Content) {
                $Candidates.Add($ErrorRecord.Exception.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult())
            }
        } catch { Remove-OPIMErrorRecord -Record $PSItem }
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
            } catch { Remove-OPIMErrorRecord -Record $PSItem }

            # 3. Already raw JSON.
            if ($Encoded -match '^\s*\{') { return $Encoded }
        }
        return $null
    }

    # -- First attempt ---------------------------------------------------------
    $InvokeParams = @{
        Method      = $Method
        Uri         = $Uri
        Verbose     = $false
        ErrorAction = 'Stop'
    }
    if ($Body) { $InvokeParams.Body = $Body }

    # SEC (OPIM-09, EntraRBAC A18): never a Graph call under a Graph SDK session this module did not
    # connect. Initialize-OPIMAuth refuses one at a cmdlet's entry, but that refusal does not stop the
    # cmdlet: outside a try the caller carries on, so the check is repeated before every request. The
    # return is load-bearing: under -ErrorAction SilentlyContinue with no try up the call stack a
    # function carries on past its own throw.
    if ((Get-OPIMGraphSessionState) -eq 'Changed') {
        throw (New-OPIMGraphSessionChangedError)
        return
    }
    # SEC (EntraRBAC A19): never a Graph call for a command whose sign-in was refused.
    # Initialize-OPIMAuth latches the command that called it and releases it only when the sign-in
    # succeeds; its refusal does not stop that command, which carries on outside any try. So the latch
    # is read before every request, after the session gate (a changed session is still reported as
    # GraphSessionChanged) and outside the try (whose catch would convert the refusal). The return is
    # load-bearing for the same reason as the session gate's.
    $SignInRefusal = Get-OPIMSignInRefusal
    if ($null -ne $SignInRefusal) {
        throw (New-OPIMSignInRefusedError -Command $SignInRefusal)
        return
    }
    try {
        return Invoke-MgGraphRequest @InvokeParams
    } catch {
        # Security: scrub the raw error record before anything else.
        # Its request message (TargetObject, and the exception's response) carries the
        # Authorization header with the bearer token in plain text.
        Remove-OPIMErrorRecord -Record $PSItem
        $FirstError = $PSItem
    }

    # -- Check for ACRS claims challenge on the first failure ------------------
    # No session-sticky guard: this function retries at most once per call (the retry block
    # below has no loop and a second failure throws), so each command can step up as needed.
    $ClaimsJson = Get-ClaimsFromException $FirstError

    if ($ClaimsJson) {
        Write-Verbose "[Invoke-OPIMGraphRequest] ACRS claims challenge detected. Performing step-up authentication..."
        Write-Verbose "[Invoke-OPIMGraphRequest] Claims: $ClaimsJson"

        $TenantId = $script:_OPIMAuthState.TenantId
        Initialize-OPIMAuth -TenantId $TenantId -ClaimsChallenge $ClaimsJson

        # -- Retry once with the upgraded token --------------------------------
        # SEC (OPIM-09): the session gate again -- another Connect-MgGraph may have replaced the
        # session during the step-up, and a refusal by Initialize-OPIMAuth does not stop this function.
        if ((Get-OPIMGraphSessionState) -eq 'Changed') {
            throw (New-OPIMGraphSessionChangedError)
            return
        }
        # SEC (EntraRBAC A19): the latch gate again. A step-up whose sign-in was refused latched this
        # function itself (it called Initialize-OPIMAuth from its own body), and outside any try it
        # carries on to here.
        $SignInRefusal = Get-OPIMSignInRefusal
        if ($null -ne $SignInRefusal) {
            throw (New-OPIMSignInRefusedError -Command $SignInRefusal)
            return
        }
        try {
            return Invoke-MgGraphRequest @InvokeParams
        } catch {
            Remove-OPIMErrorRecord -Record $PSItem
            throw Convert-GraphHttpException $PSItem
        }
    }

    # -- Token rejected/expired (not a claims challenge) -- re-auth and retry ---
    # A 401 here means the bearer token is invalid or expired (claims challenges were already
    # handled above). Force a token refresh (MSAL refresh-token path, usually no prompt) and
    # retry once instead of surfacing the failure.
    $StatusCode = $null
    try { $StatusCode = [int]$FirstError.Exception.Response.StatusCode } catch { Remove-OPIMErrorRecord -Record $PSItem }
    [bool]$TokenInvalid = $StatusCode -eq 401 -or
        $FirstError.Exception.Message -match 'InvalidAuthenticationToken|CompactToken|token is expired|Lifetime validation failed'

    if ($TokenInvalid -and $script:_OPIMAuthState) {
        Write-Verbose "[Invoke-OPIMGraphRequest] Token rejected (status=$StatusCode). Forcing re-authentication and retrying once..."
        Initialize-OPIMAuth -TenantId $script:_OPIMAuthState.TenantId -ForceRefresh
        # SEC (OPIM-09): the session gate again -- another Connect-MgGraph may have replaced the
        # session during the refresh, and a refusal by Initialize-OPIMAuth does not stop this function.
        if ((Get-OPIMGraphSessionState) -eq 'Changed') {
            throw (New-OPIMGraphSessionChangedError)
            return
        }
        # SEC (EntraRBAC A19): the latch gate again, for a refresh whose sign-in was refused (a token
        # for another tenant, a failed device code) -- it latched this function itself.
        $SignInRefusal = Get-OPIMSignInRefusal
        if ($null -ne $SignInRefusal) {
            throw (New-OPIMSignInRefusedError -Command $SignInRefusal)
            return
        }
        try {
            return Invoke-MgGraphRequest @InvokeParams
        } catch {
            Remove-OPIMErrorRecord -Record $PSItem
            throw Convert-GraphHttpException $PSItem
        }
    }

    # -- Not recoverable -- convert and re-throw --------------------------------
    throw Convert-GraphHttpException $FirstError
}
