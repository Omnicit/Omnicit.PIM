function Invoke-OPIMGraphRequest {
    <#
    .SYNOPSIS
    Wraps Invoke-MgGraphRequest with bearer-token security, ACRS claims-challenge handling,
    and consistent error conversion.

    .DESCRIPTION
    Drop-in replacement for Invoke-MgGraphRequest used by every public and private function in
    Omnicit.PIM. Adds seven layers on top of the raw Graph SDK call:

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
       A second 401 (after a successful step-up) is surfaced as a normal error. A 401 without a
       challenge, or a message that names a rejected or expired token, calls Initialize-OPIMAuth
       -ForceRefresh instead and retries exactly once. The status is read from either form the Graph
       SDK raises a failure in (OPIM-28): an HttpResponseException's Response, or the
       ResponseStatusCode of the Kiota ApiException inside the AggregateException the SDK's retry
       handler throws when it gives up.

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
       is refused latches the nested function that makes the request, Invoke-OPIMGraphSingle,
       which calls Initialize-OPIMAuth from its own body and holds the retry's gates too, so the
       retry's gate refuses it. The gate stands outside the try that sends and returns after its
       throw, as the session gate does.

    6. Paging (OPIM-13): with -All it follows @odata.nextLink until a page carries none and returns
       one response, @{ value = <the items of every page> }. Every page is one request through the
       five layers above. A page that fails throws its own error -- never a shorter list -- with
       three note properties on the record's Exception: PartialValue (the items of the pages read
       before it), NextLink (the URI of the failed page) and PageNumber (its number, from 1). A
       later page that comes back with no body is a failed read as well: it throws an error with no
       error id (category InvalidResult) and the same three facts, since the list is incomplete. A
       first page with no body is an empty list. A next link is followed only when it is an
       absolute https URI on the host of the first request (OPIM-46): the host of -Uri when that
       is an absolute https URI, else graph.microsoft.com. Any other link would carry the session's
       bearer token to another host, so it is never sent: the same kind of error is thrown, with
       no error id (category SecurityError), the same three facts (PageNumber is the page that
       would have been read) and a message that names neither the link nor its host. The verbose
       stream names a page by its number and item count, never by its link, which can carry a skip
       token.

    7. Throttling (OPIM-28): a request Microsoft Graph throttles is sent again after a bounded wait,
       with the rules of the ARM transport (A5). A 429 is always waited out; a 503 only when it
       carries a Retry-After and the request is a GET: a write (any other method) is sent again only
       after a 429, which Graph returns before it acts on a request, since a 503 can come after a
       write was carried out. The wait is the Retry-After value, as delta-seconds or an HTTP-date,
       else an exponential fallback for a 429, each wait held to 1..120 seconds, within a 300-second
       wait budget per request (per page under -All), a 900-second deadline per call that counts the
       time spent in the requests too, and at most 10 throttle retries per request. The status and
       the header are read from either form the Graph SDK raises a failure in. Every retry passes
       the session and latch gates again, and writes one verbose line with the status, the wait, its
       source and the budgets left -- never a header or the uri. When a bound is reached the request
       ends with the error it would have ended with before, Convert-GraphHttpException's record;
       under -All the list fails, never shorter. The claims step-up and the token refresh still run
       at most once per request, after the waits, and their retries are single sends.

    .PARAMETER Method
    HTTP method for the Graph request. Defaults to GET.

    .PARAMETER Uri
    Graph API URI, e.g. 'v1.0/roleManagement/directory/roleEligibilitySchedules'.

    .PARAMETER Body
    Optional request body hashtable (for POST/PATCH requests).

    .PARAMETER All
    Reads every page of a Graph list: follows @odata.nextLink until a page carries none and returns
    @{ value = <the items of every page> }. A failed page throws its own error, with PartialValue,
    NextLink and PageNumber on its Exception, and nothing is returned; so does a later page that
    comes back with no body, with an error that carries no error id. A next link is followed only
    when it is an absolute https URI on the host of the first request (graph.microsoft.com when
    -Uri is relative); any other is the same kind of error, category SecurityError, and is never
    sent.

    .OUTPUTS
    The Graph API response hashtable on success; with -All, a hashtable whose value holds the items
    of every page.

    .EXAMPLE
    $Items = (Invoke-OPIMGraphRequest -Uri 'v1.0/roleManagement/directory/roleEligibilitySchedules/filterByCurrentUser(on=''principal'')').value

    .EXAMPLE
    $Response = Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleAssignmentScheduleRequests' -Body $Request

    .EXAMPLE
    try {
        $Items = (Invoke-OPIMGraphRequest -Uri 'v1.0/roleManagement/directory/roleEligibilitySchedules/filterByCurrentUser(on=''principal'')' -All).value
    } catch {
        $ReadBeforeTheFailure = $PSItem.Exception.PartialValue
    }

    Reads every page of the list. When a page fails, the items of the pages read before it are on
    the error's Exception, as PartialValue, beside the failed page's NextLink and PageNumber.
    #>
    [OutputType([object])]
    param(
        [string]$Method = 'GET',
        [Parameter(Mandatory)]
        [string]$Uri,
        [hashtable]$Body,
        [switch]$All
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

    # -- Helper: the HTTP facts of a failed Graph request, in both forms the SDK raises ---
    # SINGLE OWNER of the status and Retry-After read (OPIM-28, EntraRBAC #75). The Graph SDK raises
    # a failed request in one of two forms:
    #   1. An HttpResponseException whose .Response is the HttpResponseMessage -- an ordinary failure,
    #      a plain 401 among them. Its status is .Response.StatusCode.
    #   2. The Kiota form: when Kiota's RetryHandler in the SDK's pipeline gives up, the SDK raises an
    #      AggregateException around a Microsoft.Kiota.Abstractions.ApiException, which has NO
    #      .Response member. Its HTTP facts are ResponseStatusCode ([int]) and ResponseHeaders.
    # Reading only .Response.StatusCode left the Kiota form with no status at all ([int]$null is 0),
    # so a 401 in that form was refreshed only when its message happened to name a rejected token.
    # The members are read BY NAME through the property bag, never by a cast to a Graph SDK type, so
    # the module takes no dependency on one, and a missing member reads as $null.
    #
    # Returns @{ Status = <int or $null>; RetryAfter = <the raw Retry-After value or $null> }. The two
    # facts are read in one walk and the walk ends early only when it holds BOTH, so a status found
    # on an outer exception does not hide a Retry-After one level further in. The raw header value is
    # parsed by ConvertFrom-GraphRetryAfterHeader, its only reader; no other header is ever read.
    #
    # Breadth-first over InnerException and, for an AggregateException, InnerExceptions. THE elseif
    # BELOW IS LOAD-BEARING: AggregateException.InnerException IS InnerExceptions[0], so following both
    # would enqueue every level twice and the queue would grow 2^depth against the visit ceiling, which
    # is a cycle guard only (a real chain is two or three deep).
    #
    # NEVER THROWS: it runs on the failure path, where an escaping exception would REPLACE the Graph
    # error the caller needs. A status is read with -as [int], never a cast, and 0 means unknown:
    # Kiota leaves ResponseStatusCode at 0 when it saw no response.
    function Get-GraphResponseFact ([System.Exception]$Exception) {
        $Fact = @{ Status = $null; RetryAfter = $null }
        $Pending = [System.Collections.Generic.Queue[System.Exception]]::new()
        if ($null -ne $Exception) { $Pending.Enqueue($Exception) }
        [int]$Visited = 0
        while ($Pending.Count -gt 0 -and $Visited -lt 32) {
            $Current = $Pending.Dequeue()
            $Visited++
            if ($null -eq $Current) { continue }
            try {
                if ($null -eq $Fact.Status) {
                    # The Kiota form: the ApiException's own status.
                    $StatusMember = $Current.PSObject.Properties['ResponseStatusCode']
                    $Status = if ($StatusMember) { $StatusMember.Value -as [int] } else { $null }
                    if ($Status -gt 0) { $Fact.Status = $Status }
                }
                if ($null -eq $Fact.RetryAfter) {
                    # The Kiota form: the ApiException's own headers.
                    $HeadersMember = $Current.PSObject.Properties['ResponseHeaders']
                    if ($HeadersMember -and $null -ne $HeadersMember.Value) {
                        $Fact.RetryAfter = Get-GraphRetryAfterHeaderValue $HeadersMember.Value
                    }
                }
                $ResponseMember = $Current.PSObject.Properties['Response']
                if ($ResponseMember -and $null -ne $ResponseMember.Value) {
                    # The .Response form: the status and the headers of the response the exception holds.
                    if ($null -eq $Fact.Status) {
                        $Status = $ResponseMember.Value.StatusCode -as [int]
                        if ($Status -gt 0) { $Fact.Status = $Status }
                    }
                    if ($null -eq $Fact.RetryAfter) {
                        $Fact.RetryAfter = Get-GraphRetryAfterHeaderValue $ResponseMember.Value.Headers
                    }
                }
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
            }
            if ($null -ne $Fact.Status -and $null -ne $Fact.RetryAfter) { break }
            if ($Current -is [System.AggregateException]) {
                foreach ($Nested in $Current.InnerExceptions) {
                    if ($null -ne $Nested) { $Pending.Enqueue($Nested) }
                }
            } elseif ($null -ne $Current.InnerException) {
                $Pending.Enqueue($Current.InnerException)
            }
        }
        return $Fact
    }

    # -- Helper: turn one raw Retry-After header VALUE into whole seconds ---------
    # SINGLE OWNER of Retry-After parsing in this wrapper. RFC 9110 allows two forms and Microsoft
    # Graph uses both: delta-seconds ("60") and an HTTP-date ("Wed, 21 Oct 2015 07:28:00 GMT").
    # Reading the date form as zero would send again at once to a service that just asked for a
    # pause. Returns $null when the value is absent or is neither form, never a guess; the caller then
    # falls back to exponential backoff. A date already past gives a negative number, which the caller
    # clamps.
    function ConvertFrom-GraphRetryAfterHeader ([string]$RawValue) {
        if ([string]::IsNullOrWhiteSpace($RawValue)) { return $null }
        $Trimmed = $RawValue.Trim()

        [int]$DeltaSeconds = 0
        if ([int]::TryParse($Trimmed, [ref]$DeltaSeconds)) { return $DeltaSeconds }

        $HttpDate = [System.DateTimeOffset]::MinValue
        $Styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                  [System.Globalization.DateTimeStyles]::AdjustToUniversal
        if ([System.DateTimeOffset]::TryParse($Trimmed, [System.Globalization.CultureInfo]::InvariantCulture, $Styles, [ref]$HttpDate)) {
            return [int][Math]::Ceiling(($HttpDate.UtcDateTime - [DateTime]::UtcNow).TotalSeconds)
        }
        return $null
    }

    # -- Helper: pull Retry-After out of a header collection, in either shape -----
    # SINGLE OWNER of that read; Get-GraphResponseFact is its only caller. Two shapes reach it:
    #   1. The Kiota form's ResponseHeaders, an IDictionary[string, IEnumerable[string]] (a hashtable
    #      in a test): it has .Keys and an indexer, and foreach treats a dictionary as ONE item, so it
    #      is walked by .Keys plus the indexer.
    #   2. The .Response form's Headers, an HttpResponseHeaders: it has NO .Keys member, and its
    #      GetValues('Retry-After') THROWS when the header is absent, which is the normal case, so it
    #      is enumerated directly, each element a KeyValuePair with .Key and .Value.
    # PSObject.Properties['Keys'] tells the two apart, so no Graph SDK type has to be loaded. Header
    # names compare case-insensitively (-ne on strings), as HTTP requires; Kiota keys its dictionary
    # with the ordinal comparer, so an indexer lookup by name would not.
    #
    # NEVER THROWS: it runs on the failure path, where an escaping exception would REPLACE the Graph
    # error the caller needs. SECURITY: only the single Retry-After value is ever returned. The
    # collection itself is never returned, written to any stream or logged: it can hold correlation
    # ids and, on some shapes, authentication material.
    function Get-GraphRetryAfterHeaderValue ($HeaderCollection) {
        if ($null -eq $HeaderCollection) { return $null }
        try {
            $KeysMember = $HeaderCollection.PSObject.Properties['Keys']
            if ($null -ne $KeysMember) {
                foreach ($Key in @($KeysMember.Value)) {
                    if ([string]$Key -ne 'Retry-After') { continue }
                    return [string](@($HeaderCollection[$Key]) | Select-Object -First 1)
                }
                return $null
            }
            foreach ($Entry in $HeaderCollection) {
                if ($null -eq $Entry) { continue }
                $NameMember = $Entry.PSObject.Properties['Key']
                if ($null -eq $NameMember -or [string]$NameMember.Value -ne 'Retry-After') { continue }
                $ValueMember = $Entry.PSObject.Properties['Value']
                if ($null -eq $ValueMember) { return $null }
                return [string](@($ValueMember.Value) | Select-Object -First 1)
            }
        } catch {
            Remove-OPIMErrorRecord -Record $PSItem
        }
        return $null
    }

    # -- Helper: how long does Graph want us to wait before sending again? -------
    # Returns $null when the failure is not a throttle this wrapper waits out, else
    # @{ Seconds = <int>; Source = 'server-directed' | 'exponential fallback'; Status = <int> }.
    # The Source is what the verbose line reports, so an operator can tell Graph's own instruction
    # from this module's fallback. The rules are the ARM transport's (A5), on the status
    # Get-GraphResponseFact reads from either form -- never on an error code or a message:
    #   * A 429 is always a throttle: the Retry-After value when it can be read, else 2^Attempt
    #     seconds (Microsoft Learn, Microsoft Graph throttling guidance).
    #   * A 503 is waited out only when it carries a Retry-After, and only for a GET. A 503 without
    #     one is the service saying it is unwell, not asking for a pause, and sending it again blind
    #     turns an outage into a hammering. A write -- any method but GET -- is sent again only after
    #     a 429, which Graph returns BEFORE it acts on a request: a 503 can come after Graph carried a
    #     write out, and sending an activation again could make a second one.
    #   * Anything else is not a throttle.
    # Each wait is clamped to 1..120 s: at least one second, so a "Retry-After: 0" still spends the
    # budget the loop is bounded by; at most 120, so an absurd header cannot hold one wait for an hour.
    function Get-GraphThrottleDelay ([System.Management.Automation.ErrorRecord]$ErrorRecord, [int]$Attempt, [string]$RequestMethod) {
        $Fact = Get-GraphResponseFact $ErrorRecord.Exception
        $Status = $Fact.Status
        if ($Status -ne 429 -and $Status -ne 503) { return $null }
        if ($Status -eq 503 -and $RequestMethod -ne 'GET') { return $null }

        $HeaderSeconds = ConvertFrom-GraphRetryAfterHeader $Fact.RetryAfter
        [string]$Source = 'server-directed'
        if ($null -ne $HeaderSeconds) {
            $Seconds = $HeaderSeconds
        } elseif ($Status -eq 429) {
            $Seconds = [Math]::Pow(2, $Attempt)
            $Source = 'exponential fallback'
        } else {
            return $null
        }

        if ($Seconds -lt 1) { $Seconds = 1 }
        if ($Seconds -gt 120) { $Seconds = 120 }
        return @{ Seconds = [int]$Seconds; Source = $Source; Status = [int]$Status }
    }

    # -- Helper: how much of the per-CALL deadline has this call already used? ----
    # Whole seconds, the LARGER of two measures, as in the ARM transport:
    #   1. Wall-clock time since the call started. It binds in production: it counts the time spent
    #      IN the requests as well as the waits, so slow answers cannot creep past the deadline.
    #   2. The seconds this call has asked Start-Sleep to wait. In production it is always the smaller,
    #      since every sleep is wall-clock time too; it makes the bound deterministic under test, where
    #      Start-Sleep is mocked and measure 1 stays near zero.
    function Get-GraphCallElapsed ([hashtable]$CallBudget) {
        if (-not $CallBudget) { return 0 }
        $WallClockSecond = ([DateTime]::UtcNow - $CallBudget.StartUtc).TotalSeconds
        return [int][Math]::Floor([Math]::Max($WallClockSecond, [double]$CallBudget.WaitSpent))
    }

    # -- One request: its gates, the first attempt with its throttle waits and the two retries --
    # Every send of this function sits in here, so a page of a -All read is one request with the
    # same gates, scrubs and retries as a single call. The retries call Initialize-OPIMAuth from this
    # function's own body, so a refused retry sign-in latches this function's frame, and the retry's
    # latch gate, in the same body, finds it. $CallBudget is the per-CALL state the outer function
    # creates and every page shares.
    function Invoke-OPIMGraphSingle ([string]$SingleMethod, [string]$SingleUri, [hashtable]$SingleBody, [hashtable]$CallBudget) {
        # -- First attempt -----------------------------------------------------
        $InvokeParams = @{
            Method      = $SingleMethod
            Uri         = $SingleUri
            Verbose     = $false
            ErrorAction = 'Stop'
        }
        if ($SingleBody) { $InvokeParams.Body = $SingleBody }
        # Set by the catch of a failed retry and read straight after its try. Under -ErrorAction
        # SilentlyContinue with no try up the call stack a throw inside a catch resumes after the
        # whole try statement, so without the flag a failed claims retry would fall on into the
        # token-rejected retry (a refresh and a third send), and a failed refresh retry into a second
        # error for the first failure.
        [bool]$ClaimsRetryFailed = $false
        [bool]$RefreshRetryFailed = $false

        # -- Throttle backoff (OPIM-28): a bounded loop around the FIRST attempt ------------------
        # The numbers are the ARM transport's (A5), internal constants on purpose (no public
        # parameter):
        #   ThrottleWaitBudgetSeconds = 300, per REQUEST (per PAGE under -All): a server-directed
        #     "Retry-After: 60" five times over.
        #   CallDeadlineSeconds = 900, per CALL, shared by every page through $CallBudget. A DEADLINE:
        #     the time spent IN the requests counts too (Get-GraphCallElapsed). It is consulted only
        #     at a decision to wait, so it bounds a throttled call and nothing else.
        #   ThrottleRetryHardCap = 10, per request: a runaway guard for a server that keeps asking for
        #     a very short wait.
        # BOTH BOUNDS ARE ENFORCED AT THE DECISION TO WAIT, never by stopping a -All walk between
        # pages: a request that cannot wait ends with its error, and a -All read with it fails whole,
        # never shorter. The claims step-up and the token refresh below run after the loop, on the
        # last attempt's failure, at most once each as before: a throttle never spends them, and their
        # retries are single sends.
        [int]$ThrottleWaitBudgetSeconds = 300
        [int]$CallDeadlineSeconds = 900
        [int]$ThrottleRetryHardCap = 10
        [int]$ThrottleWaitSpent = 0
        [int]$ThrottleAttempt = 0
        $FirstError = $null
        while ($true) {
            # SEC (OPIM-09, EntraRBAC A18): never a Graph call under a Graph SDK session this module
            # did not connect. Initialize-OPIMAuth refuses one at a cmdlet's entry, but that refusal
            # does not stop the cmdlet: outside a try the caller carries on, so the check is repeated
            # before every request -- the first attempt and every throttled retry, since another
            # Connect-MgGraph can replace the session during a wait. The return is load-bearing: under
            # -ErrorAction SilentlyContinue with no try up the call stack a function carries on past
            # its own throw.
            if ((Get-OPIMGraphSessionState) -eq 'Changed') {
                throw (New-OPIMGraphSessionChangedError)
                return
            }
            # SEC (EntraRBAC A19): never a Graph call for a command whose sign-in was refused.
            # Initialize-OPIMAuth latches the command that called it and releases it only when the
            # sign-in succeeds; its refusal does not stop that command, which carries on outside any
            # try. So the latch is read before every request, after the session gate (a changed
            # session is still reported as GraphSessionChanged) and outside the try (whose catch would
            # convert the refusal). The return is load-bearing for the same reason as the session
            # gate's.
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

            $Delay = Get-GraphThrottleDelay -ErrorRecord $FirstError -Attempt $ThrottleAttempt -RequestMethod $SingleMethod
            if ($null -eq $Delay) { break }

            [int]$RequestRemaining = $ThrottleWaitBudgetSeconds - $ThrottleWaitSpent
            [int]$CallRemaining = $CallDeadlineSeconds - (Get-GraphCallElapsed -CallBudget $CallBudget)
            # The per-CALL bound first, so that when both are gone the line names the one that ends
            # the command rather than the one that ends this request.
            if ($Delay.Seconds -gt $CallRemaining) {
                Write-Verbose ("[Invoke-OPIMGraphRequest] Throttled. The next wait needs $($Delay.Seconds) s " +
                    "($($Delay.Source)) but only $CallRemaining s of the $CallDeadlineSeconds s per-CALL budget remain. Giving up.")
                break
            }
            if ($Delay.Seconds -gt $RequestRemaining) {
                # A wait this request cannot afford would mean sending EARLY, which only earns another
                # throttle. The request ends with Graph's error.
                Write-Verbose ("[Invoke-OPIMGraphRequest] Throttled. The next wait needs $($Delay.Seconds) s " +
                    "($($Delay.Source)) but only $RequestRemaining s of the $ThrottleWaitBudgetSeconds s per-REQUEST budget remain. Giving up.")
                break
            }
            if ($ThrottleAttempt -ge $ThrottleRetryHardCap) {
                Write-Verbose ("[Invoke-OPIMGraphRequest] Throttled. Reached the hard cap of $ThrottleRetryHardCap " +
                    "throttle retries with $RequestRemaining s of per-REQUEST budget still unspent. Giving up.")
                break
            }

            $ThrottleAttempt++
            $ThrottleWaitSpent += $Delay.Seconds
            if ($CallBudget) { $CallBudget.WaitSpent += $Delay.Seconds }
            $RequestRemaining = $ThrottleWaitBudgetSeconds - $ThrottleWaitSpent
            $CallRemaining = $CallDeadlineSeconds - (Get-GraphCallElapsed -CallBudget $CallBudget)
            # SECURITY: the status, the wait, its source and the budgets only -- never a header, the
            # uri (a next link's query can carry a skip token) or the body.
            Write-Verbose ("[Invoke-OPIMGraphRequest] Throttled (status=$($Delay.Status)). " +
                "Waiting $($Delay.Seconds) s ($($Delay.Source)) before retry $ThrottleAttempt; " +
                "$RequestRemaining s of per-REQUEST and $CallRemaining s of per-CALL budget remain.")
            Start-Sleep -Seconds $Delay.Seconds
        }

        # -- Check for ACRS claims challenge on the last attempt's failure -----
        # No session-sticky guard: this function steps up at most once per request (the retry block
        # below has no loop and a second failure throws), so each command can step up as needed.
        $ClaimsJson = Get-ClaimsFromException $FirstError

        if ($ClaimsJson) {
            Write-Verbose "[Invoke-OPIMGraphRequest] ACRS claims challenge detected. Performing step-up authentication..."
            Write-Verbose "[Invoke-OPIMGraphRequest] Claims: $ClaimsJson"

            $TenantId = $script:_OPIMAuthState.TenantId
            Initialize-OPIMAuth -TenantId $TenantId -ClaimsChallenge $ClaimsJson

            # -- Retry once with the upgraded token ----------------------------
            # SEC (OPIM-09): the session gate again -- another Connect-MgGraph may have replaced the
            # session during the step-up, and a refusal by Initialize-OPIMAuth does not stop this
            # function.
            if ((Get-OPIMGraphSessionState) -eq 'Changed') {
                throw (New-OPIMGraphSessionChangedError)
                return
            }
            # SEC (EntraRBAC A19): the latch gate again. A step-up whose sign-in was refused latched
            # this function itself (it called Initialize-OPIMAuth from its own body), and outside any
            # try it carries on to here.
            $SignInRefusal = Get-OPIMSignInRefusal
            if ($null -ne $SignInRefusal) {
                throw (New-OPIMSignInRefusedError -Command $SignInRefusal)
                return
            }
            try {
                return Invoke-MgGraphRequest @InvokeParams
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $ClaimsRetryFailed = $true
                throw Convert-GraphHttpException $PSItem
            }
            # A failed claims retry ends the request here, never in the token-rejected retry below.
            if ($ClaimsRetryFailed) { return }
        }

        # -- Token rejected/expired (not a claims challenge) -- re-auth and retry
        # A 401 here means the bearer token is invalid or expired (claims challenges were already
        # handled above). Force a token refresh (MSAL refresh-token path, usually no prompt) and
        # retry once instead of surfacing the failure. OPIM-28: the status is read from either form
        # the Graph SDK raises a failure in (Get-GraphResponseFact), so a 401 in the Kiota form is
        # refreshed as well.
        $StatusCode = (Get-GraphResponseFact $FirstError.Exception).Status
        [bool]$TokenInvalid = $StatusCode -eq 401 -or
            $FirstError.Exception.Message -match 'InvalidAuthenticationToken|CompactToken|token is expired|Lifetime validation failed'

        if ($TokenInvalid -and $script:_OPIMAuthState) {
            Write-Verbose "[Invoke-OPIMGraphRequest] Token rejected (status=$StatusCode). Forcing re-authentication and retrying once..."
            Initialize-OPIMAuth -TenantId $script:_OPIMAuthState.TenantId -ForceRefresh
            # SEC (OPIM-09): the session gate again -- another Connect-MgGraph may have replaced the
            # session during the refresh, and a refusal by Initialize-OPIMAuth does not stop this
            # function.
            if ((Get-OPIMGraphSessionState) -eq 'Changed') {
                throw (New-OPIMGraphSessionChangedError)
                return
            }
            # SEC (EntraRBAC A19): the latch gate again, for a refresh whose sign-in was refused (a
            # token for another tenant, a failed device code) -- it latched this function itself.
            $SignInRefusal = Get-OPIMSignInRefusal
            if ($null -ne $SignInRefusal) {
                throw (New-OPIMSignInRefusedError -Command $SignInRefusal)
                return
            }
            try {
                return Invoke-MgGraphRequest @InvokeParams
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $RefreshRetryFailed = $true
                throw Convert-GraphHttpException $PSItem
            }
            # A failed refresh retry ends the request with its own error, never a second one for the
            # first failure below.
            if ($RefreshRetryFailed) { return }
        }

        # -- Not recoverable -- convert and re-throw ----------------------------
        throw Convert-GraphHttpException $FirstError
    }

    # -- Per-CALL deadline (OPIM-28), shared by every page of a -All read ---------
    # A hashtable, so the nested request function adds to THIS state by reference; a value type would
    # give each page its own copy and the deadline would never bind. A single request gets one too, so
    # both paths run the same code; since the deadline counts wall-clock time, one slow request can
    # bring even a single call to it.
    $CallBudget = @{ StartUtc = [DateTime]::UtcNow; WaitSpent = 0 }

    if (-not $All) {
        return Invoke-OPIMGraphSingle -SingleMethod $Method -SingleUri $Uri -SingleBody $Body -CallBudget $CallBudget
    }

    # -- Paging (OPIM-13): follow @odata.nextLink ----------------------------------
    # Invoke-MgGraphRequest returns a Hashtable, so the link is read with the indexer. A failed page
    # throws its own error with what was read before it attached to the Exception (a note property
    # on the ErrorRecord does not survive a throw; on the Exception it does).
    # No page cap and no loop detection, on purpose (ruling R-T7c): a cap would hand back a list cut
    # short as if it were complete -- the very defect -All exists to fix. Graph ends every list with
    # a page that carries no next link.
    $AllValues = [System.Collections.Generic.List[object]]::new()
    $NextUri = $Uri
    [int]$PageNumber = 0
    # OPIM-46 (SEC), ruling P10: the host a next link must stay on is the host of the first request --
    # the host of -Uri when that is an absolute https URI, else graph.microsoft.com, since the module's
    # tokens are for the global Microsoft Graph only. TryCreate, not IsWellFormedUriString, which
    # refuses an unescaped ' or $ in an absolute Graph URI.
    $FirstParsed = $null
    $FirstHost = if ([uri]::TryCreate($Uri, [UriKind]::Absolute, [ref]$FirstParsed) -and $FirstParsed.Scheme -eq 'https') {
        $FirstParsed.Host
    } else {
        'graph.microsoft.com'
    }
    while ($NextUri) {
        $PageNumber++
        $PageFailed = $false
        try {
            $Page = Invoke-OPIMGraphSingle -SingleMethod $Method -SingleUri $NextUri -SingleBody $Body -CallBudget $CallBudget
        } catch {
            Remove-OPIMErrorRecord -Record $PSItem
            $PageFailed = $true
            $PSItem.Exception | Add-Member -NotePropertyName PartialValue -NotePropertyValue $AllValues.ToArray() -Force
            $PSItem.Exception | Add-Member -NotePropertyName NextLink -NotePropertyValue $NextUri -Force
            $PSItem.Exception | Add-Member -NotePropertyName PageNumber -NotePropertyValue $PageNumber -Force
            throw
        }
        # A throw inside a catch resumes after the try under -ErrorAction SilentlyContinue with no try
        # up the call stack. return, never break: break would hand back a short list as complete.
        if ($PageFailed) { return }
        if ($null -eq $Page) {
            # Page 1 with no body is an empty list, as it was before OPIM-13.
            if ($PageNumber -eq 1) { break }
            # A later page with no body is a failed read: Graph promised it through the previous
            # page's next link, so ending here would hand back a short list as complete. It is raised
            # as the failed-page catch raises its error, with the same three facts on the Exception,
            # and carries no error id (no new ErrorId; the form Write-CmdletError gives without one).
            # The message names the page by its number, never by its link (ruling R-T7a).
            $NoBody = [System.Exception]::new(
                "Page $PageNumber`: Microsoft Graph returned no body for this page of the list, so the list is incomplete.")
            $NoBody | Add-Member -NotePropertyName PartialValue -NotePropertyValue $AllValues.ToArray() -Force
            $NoBody | Add-Member -NotePropertyName NextLink -NotePropertyValue $NextUri -Force
            $NoBody | Add-Member -NotePropertyName PageNumber -NotePropertyValue $PageNumber -Force
            Write-CmdletError -Message $NoBody -Category InvalidResult -TargetObject $null -Cmdlet $PSCmdlet -Terminating
            # ThrowTerminatingError ends this function even under SilentlyContinue with no try up
            # the call stack, unlike a throw statement (measured 2026-10-07), so this line is not
            # reached. It stays so the loop can never fall through to a short list: return, never
            # break.
            return
        }
        [int]$PageItemCount = 0
        foreach ($Item in @($Page.value)) {
            if ($null -ne $Item) {
                $AllValues.Add($Item)
                $PageItemCount++
            }
        }
        # Ruling R-T7a: the page's number and item count only -- never its link, which can carry a
        # skip token.
        Write-Verbose "[Invoke-OPIMGraphRequest] Read page $PageNumber of the list: $PageItemCount item(s)."
        $NextUri = [string]$Page['@odata.nextLink']
        if ($NextUri) {
            # OPIM-46 (SEC): follow a next link only to the host of the first request, over https.
            # A link elsewhere would carry the session's token to another host: it is never sent,
            # and the list is reported incomplete. The message names neither the link nor its host.
            $NextParsed = $null
            $SameHost = [uri]::TryCreate($NextUri, [UriKind]::Absolute, [ref]$NextParsed) -and
                $NextParsed.Scheme -eq 'https' -and
                [string]::Equals($NextParsed.Host, $FirstHost, [System.StringComparison]::OrdinalIgnoreCase)
            if (-not $SameHost) {
                $Foreign = [System.Exception]::new(
                    "Page $($PageNumber + 1): Microsoft Graph returned a next link that is not an https link on the host of the first request, so it was not followed and the list is incomplete.")
                $Foreign | Add-Member -NotePropertyName PartialValue -NotePropertyValue $AllValues.ToArray() -Force
                $Foreign | Add-Member -NotePropertyName NextLink -NotePropertyValue $NextUri -Force
                $Foreign | Add-Member -NotePropertyName PageNumber -NotePropertyValue ($PageNumber + 1) -Force
                Write-CmdletError -Message $Foreign -Category SecurityError -TargetObject $null -Cmdlet $PSCmdlet -Terminating
                # As for the page with no body above: ThrowTerminatingError ends this function, so this
                # line is not reached; it stays so the loop can never fall through to follow the link.
                return
            }
        }
    }
    return @{ value = $AllValues.ToArray() }
}
