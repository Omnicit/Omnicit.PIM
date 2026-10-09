function Invoke-OPIMArmRequest {
    <#
    .SYNOPSIS
    Sends Azure Resource Manager requests directly with the session's ARM token, adding the ARM gate,
    one 401 refresh, throttling backoff, paging and consistent error conversion.

    .DESCRIPTION
    The single ARM call site of the module: nothing else sends an Azure Resource Manager request. The
    caller supplies the ARM path INCLUDING the pinned api-version query parameter; the wrapper prepends
    the ARM host and sends the request with Invoke-WebRequest. The token is the one
    Initialize-OPIMAuth -IncludeARM holds in $script:_OPIMAuthState.ArmToken: a SecureString that is
    handed to Invoke-WebRequest -Authentication Bearer -Token as it is, so the module never makes it
    plaintext; -Authentication Bearer refuses a uri that is not https, and the header is not replayed
    on a redirect. The host is the state's ArmResourceUrl, else https://management.azure.com. No Az
    module takes part: neither Az.Accounts nor its REST cmdlet.

    Before every request -- the first attempt, each throttled retry, the retry after a 401 refresh
    and every page of a -All read -- the ARM gate, Get-OPIMArmRefusal, refuses a request made for a
    command whose sign-in was refused (SignInRefused), and a request whose ARM token was issued for
    another tenant (TenantMismatch) or another account (AccountMismatch) than the module's Graph
    session. A refused request is never sent. A request is never sent without a usable ARM token
    either: when the session holds none -- no state, a state without the Graph session's tenant
    (TokenTenantId), no ArmToken, or an empty SecureString -- it is refused after the gate and before
    anything is sent, with ArmTokenAcquisitionFailed. Run Connect-OPIM -IncludeARM to sign in to Azure.
    Nor does a request ever leave the session's ARM host: the uri of every request -- the host and the
    caller's path, or a page's path -- must parse as an absolute https uri on that host and on the
    port of the session's ARM url, or it is refused before anything is sent, with a terminating error
    with no error id (category SecurityError) whose message names neither the path nor any host. The
    records this function raises for a single request name the path without its query string as their
    target.

    Invoke-WebRequest is called with -SkipHttpErrorCheck so HTTP errors do not throw. Each response is
    normalized to a { StatusCode; Content; Headers } object before the status logic runs; the header
    collection stays inside this wrapper and only its Retry-After entry is ever read. The wrapper
    returns the parsed JSON content for a 2xx response ($null when the body of a GET or a DELETE is
    empty, as for a 204). A 2xx body that does not parse is a failed read: ArmTransportError, category
    InvalidResult, with the caller's path as its target. So is a 2xx answer with no body to a PUT, POST
    or PATCH: the request may have been accepted, but its answer cannot be read.
    On a 401 it calls Initialize-OPIMAuth -IncludeARM -ForceRefresh and retries exactly once; the
    refresh budget is shared across the whole call, so a token that expires part-way through a -All
    read gets exactly one forced refresh for the entire walk, not one per page. Any other non-2xx
    status is thrown as the Convert-OPIMArmHttpException record, whose id is the ARM error code (or
    ArmTransportError when the body carries none). A request that gets no response at all is thrown
    as ArmTransportError.

    With -All, GET results are aggregated across pages, following either the nextLink or the
    @nextLink property. A next link is followed only when it is an absolute https URI on the
    session's ARM host, and is then requested by its path and query on that host. Any other link
    would carry the session's ARM token elsewhere: it is never sent, and the call ends with a
    terminating error with no error id (category SecurityError) whose message names neither the link
    nor its host. Every page, the first included, must carry a body that parses into an object with a
    value property: an ARM list always answers with a value array, so a page with no body, a body that
    does not parse or one without value is a failed read (ArmTransportError, category InvalidResult,
    the caller's path as its target, a message naming the page by its number), never an empty or a
    shorter list. So is a next link to a page this call already requested, the first page included:
    no page is requested twice. Nothing is ever returned for a list that was not read to its end.

    A 429, and a 503 that carries a Retry-After header, are retried with a bounded backoff: the
    Retry-After value is honoured in either RFC 9110 form (delta-seconds or an HTTP-date), with an
    exponential fallback when the header is absent or unparseable, each single wait clamped to
    1..120 seconds. Two nested bounds hold: a 300-second wait budget per REQUEST (per PAGE under
    -All) and a 900-second DEADLINE for the whole call, which counts time spent in the requests
    themselves, plus a hard cap of 10 throttle retries per request as a runaway guard. Both bounds are
    enforced at the decision to WAIT and never by stopping a paging loop part-way, so a throttled
    enumeration fails cleanly instead of returning a partial collection as though it were complete.
    One Write-Verbose line is emitted per retry, naming the delay, the attempt number and whether the
    value came from the server or from the exponential fallback. The backoff wraps the 401 refresh
    rather than nesting inside it, so a throttled response can never consume the single per-call
    refresh budget and the two retry paths cannot compound.

    The verbose stream names each request by its method and its path without the query string -- a
    next link's query can carry a skip token -- and never carries the token, the body or a header.

    .PARAMETER Method
    HTTP method for the ARM request. Defaults to GET.

    .PARAMETER Path
    ARM path including the api-version query parameter, for example
    '/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01'.
    Never includes the host. The root scope has no prefix, so the path starts with /providers.

    .PARAMETER Body
    Optional request body hashtable, serialized with ConvertTo-Json -Depth 100 into the request body
    with content type application/json; charset=utf-8.

    .PARAMETER All
    Follow nextLink/@nextLink paging on GET list responses and return a single object whose value
    property contains all aggregated items.

    .EXAMPLE
    $Eligible = (Invoke-OPIMArmRequest -Path '/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01' -All).value

    Lists every eligibility of the signed-in user, across pages.

    .EXAMPLE
    Invoke-OPIMArmRequest -Method PUT -Path "$Scope/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/$Name`?api-version=2020-10-01" -Body $Body

    Sends a role assignment schedule request at the given scope.
    #>
    [OutputType([object])]
    param(
        [string]$Method = 'GET',

        [Parameter(Mandatory)]
        [string]$Path,

        [hashtable]$Body,

        [switch]$All
    )

    # Suppress the Invoke-WebRequest progress bar for the lifetime of this call.
    $ProgressPreference = 'SilentlyContinue'

    # ARM host: the session's own resource url when it has one. Every state Initialize-OPIMAuth builds
    # with an ARM token records it.
    $ArmBaseUrl = if ($script:_OPIMAuthState -is [System.Collections.IDictionary] -and $script:_OPIMAuthState['ArmResourceUrl']) {
        ([string]$script:_OPIMAuthState['ArmResourceUrl']).TrimEnd('/')
    } else {
        # The ARM fallback: a request with no state is refused for its missing token below.
        'https://management.azure.com'
    }
    $ArmBaseHost = ([uri]$ArmBaseUrl).Host
    $ArmBasePort = ([uri]$ArmBaseUrl).Port

    function Invoke-OPIMArmSingle ([string]$CallPath, [string]$CallMethod, [hashtable]$CallBody, [string]$BaseUrl) {
        # The path without its query: what the verbose line and the target of this function's records
        # name. A page's path is its next link's path and query, and that query can carry a skip token.
        $CallTarget = ($CallPath -split '\?', 2)[0]
        # SECURITY: the method and the path without its query. Never the token, never the body.
        Write-Verbose "[Invoke-OPIMArmRequest] $CallMethod $CallTarget"

        # SEC (EntraRBAC A19, OPIM-08, A3): the ARM gate before every request -- the first attempt, each
        # throttled retry, the 401 retry (a refused refresh latches Invoke-OPIMArmWithRefresh) and every
        # page. The return is load-bearing: under -ErrorAction SilentlyContinue with no try up the call
        # stack a function carries on past its own throw.
        $ArmRefusal = Get-OPIMArmRefusal
        if ($null -ne $ArmRefusal) {
            throw $ArmRefusal
            return
        }

        # SEC: never a request without a usable ARM token. A token is usable only in a state that is a
        # dictionary holding both the Graph session's tenant (TokenTenantId) and a non-empty SecureString
        # ArmToken: Initialize-OPIMAuth never stores an ARM token without that tenant, and the gate above
        # compares the token with it, so a token with no tenant to compare against is no usable token.
        $ArmToken = $null
        if ($script:_OPIMAuthState -is [System.Collections.IDictionary] -and $script:_OPIMAuthState['TokenTenantId']) {
            $ArmToken = $script:_OPIMAuthState['ArmToken']
        }
        if (-not ($ArmToken -is [System.Security.SecureString]) -or $ArmToken.Length -eq 0) {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(('No Azure Resource Manager request was sent: the module''s session holds no ' +
                    'Azure Resource Manager token. Run Connect-OPIM -IncludeARM to sign in to Azure, and run the command again.')),
                'ArmTokenAcquisitionFailed',
                [System.Management.Automation.ErrorCategory]::AuthenticationError,
                $CallTarget)
            return
        }

        # SEC: the request stays on the session's ARM host. The caller's path is appended to the host, so
        # a path such as '@other.host/...', '.other.host/...' or ':8443/...' would move the uri, and the
        # token, to another host or port. The uri is built and checked here, before every send -- the
        # first attempt, each retry and every page -- with the same terms as a next link: absolute,
        # https, and the session's ARM host ($ArmBaseHost, of the wrapper this function is nested in),
        # and on the port of the session's ARM url ($ArmBasePort, 443) as well. The checked uri is the
        # one sent. No error id, as the next-link refusal; the message names neither the path nor any
        # host. ThrowTerminatingError ends the call even under SilentlyContinue; the return stays.
        $CallUri = $null
        $OnArmHost = [uri]::TryCreate("$BaseUrl$CallPath", [UriKind]::Absolute, [ref]$CallUri) -and
            $CallUri.Scheme -eq 'https' -and
            [string]::Equals($CallUri.Host, $ArmBaseHost, [System.StringComparison]::OrdinalIgnoreCase) -and
            $CallUri.Port -eq $ArmBasePort
        if (-not $OnArmHost) {
            Write-CmdletError -Message ([System.Exception]::new(
                    'No Azure Resource Manager request was sent: the request path does not stay on the session''s Azure Resource Manager host.')) `
                -Category SecurityError -TargetObject $null -Cmdlet $PSCmdlet -Terminating
            return
        }
        # A6: the SecureString goes to Invoke-WebRequest as it is; the module never makes it plaintext.
        # -Authentication Bearer refuses a non-https uri, and the header is not replayed on a redirect.
        $InvokeParams = @{
            Method             = $CallMethod
            Uri                = $CallUri
            Authentication     = 'Bearer'
            Token              = $ArmToken
            SkipHttpErrorCheck = $true
            ErrorAction        = 'Stop'
            Verbose            = $false
        }
        if ($CallBody) {
            $InvokeParams.Body        = ($CallBody | ConvertTo-Json -Depth 100)
            # The charset names the encoding of the body, so a justification outside ASCII reaches ARM
            # as written: without one, an older Invoke-WebRequest can encode a string body as ISO-8859-1.
            $InvokeParams.ContentType = 'application/json; charset=utf-8'
        }
        $TransportFailed = $false
        try {
            $Raw = Invoke-WebRequest @InvokeParams
        } catch {
            # Security hygiene: the failed request lives in $Error -- remove it FIRST, before anything
            # else, uniformly with the Graph wrapper.
            Remove-OPIMErrorRecord -Record $PSItem
            # Read straight after this try statement; see the check there.
            $TransportFailed = $true
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Azure Resource Manager request failed before a response was received: $($PSItem.Exception.Message)"),
                'ArmTransportError',
                [System.Management.Automation.ErrorCategory]::ConnectionError,
                $CallTarget)
        }
        # The throw above does not always end this function: under -ErrorAction SilentlyContinue or
        # Ignore, with no try up the call stack, a throw inside a CATCH block resumes AFTER the whole try
        # statement, so a return placed after that throw would never run. Carrying on would build a
        # status-0 response out of a request that never got one, and the wrapper would raise a second
        # record for it. No object at all goes back instead; every caller above hands that on without
        # sending anything, and the top of the wrapper ends the call on it.
        if ($TransportFailed) { return }
        # Normalize to a { StatusCode; Content; Headers } shape for the status logic, the throttle
        # backoff and Convert-OPIMArmHttpException. The headers have to survive this line, or no
        # Retry-After could ever be read. In production $Raw.Headers is a
        # Dictionary[string, IEnumerable[string]]; under test it is whatever the Invoke-WebRequest mock
        # returned, usually a hashtable, and $null when the mock supplies none.
        # Get-ArmRetryAfterHeaderValue tolerates all three.
        #
        # SECURITY: this collection stays INSIDE the wrapper. It is never returned to a caller, written
        # to any stream, put into an error message, or logged. Only the single Retry-After entry is ever
        # read out of it, and only by Get-ArmRetryAfterHeaderValue.
        [PSCustomObject]@{
            StatusCode = [int]$Raw.StatusCode
            Content    = [string]$Raw.Content
            Headers    = $Raw.Headers
        }
    }

    # -- Helper: turn one raw Retry-After header VALUE into whole seconds --
    # SINGLE OWNER of raw Retry-After parsing. RFC 9110 allows two forms and both are handled:
    # delta-seconds ("60") and an HTTP-date ("Wed, 21 Oct 2015 07:28:00 GMT"). Reading the date form as
    # zero would retry IMMEDIATELY against an endpoint that just asked for a pause. Returns $null when
    # the value is absent or is neither form, never a guess; the caller then falls back to exponential
    # backoff. A date already in the past yields a negative number here and is clamped by the caller.
    function ConvertFrom-ArmRetryAfterHeader ([string]$RawValue) {
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

    # -- Helper: pull Retry-After out of a response's header collection --
    # SINGLE OWNER of that read. Do not add a second reader.
    #
    # Invoke-WebRequest's response exposes .Headers as a Dictionary[string, IEnumerable[string]].
    # PowerShell's foreach treats a dictionary as ONE item, so it is walked by .Keys plus the indexer.
    # A hashtable exposes the same two members, so one reader serves both and no test-only path
    # exists. Header names are compared case-insensitively: HTTP header names are, and nothing
    # guarantees the dictionary's comparer is.
    #
    # NEVER THROWS. This runs on the failure path, where an escaping exception would REPLACE the ARM
    # error the caller needs to see.
    #
    # SECURITY: only the single Retry-After entry is ever returned. The collection itself is never
    # returned, written to any stream, or logged.
    function Get-ArmRetryAfterHeaderValue ($HeaderCollection) {
        if ($null -eq $HeaderCollection) { return $null }
        try {
            $KeysMember = $HeaderCollection.PSObject.Properties['Keys']
            if ($null -eq $KeysMember) { return $null }
            foreach ($Key in @($KeysMember.Value)) {
                if ([string]$Key -ne 'Retry-After') { continue }
                return [string](@($HeaderCollection[$Key]) | Select-Object -First 1)
            }
        } catch {
            Remove-OPIMErrorRecord -Record $PSItem
        }
        return $null
    }

    # -- Helper: how long does ARM want us to wait before retrying? --
    # Returns $null when the response is not a retryable throttle, otherwise
    # @{ Seconds = <int>; Source = 'server-directed' | 'exponential fallback' }. The Source is what the
    # verbose line reports, so an operator can tell whether the wait is ARM's own instruction or this
    # module's fallback.
    #
    # Invoke-WebRequest is called with -SkipHttpErrorCheck, so a 429 arrives as an ordinary response
    # object with a real status code and real headers: nothing has to be dug out of an exception.
    #
    # -as [int], never a cast: a StatusCode that is not numeric would make a cast THROW from inside the
    # failure path and replace the real ARM error. -as yields $null and the caller moves on.
    function Get-ArmThrottleDelay ($CallResult, [int]$Attempt) {
        $Status = $CallResult.StatusCode -as [int]
        if ($null -eq $Status) { return $null }
        if ($Status -ne 429 -and $Status -ne 503) { return $null }

        $HeaderSeconds = ConvertFrom-ArmRetryAfterHeader (Get-ArmRetryAfterHeaderValue $CallResult.Headers)

        [string]$Source = 'server-directed'
        if ($null -ne $HeaderSeconds) {
            $Seconds = $HeaderSeconds
        } elseif ($Status -eq 429) {
            # No usable header: exponential fallback, per Microsoft Learn's throttling guidance.
            $Seconds = [Math]::Pow(2, $Attempt)
            $Source = 'exponential fallback'
        } else {
            # A 503 with no Retry-After is not a throttle signal. It is ARM saying it is unwell, and
            # retrying it blind turns a transient outage into a hammering. Only a 503 that NAMES a wait
            # is retried -- the same rule as on the Graph side.
            return $null
        }

        # Clamp. The lower bound is ONE second, not zero: the loop is bounded by a wait BUDGET rather
        # than a retry count alone, so a zero-second wait would let a server answering
        # "Retry-After: 0" spin without ever spending budget. The upper bound of 120 s guards a hostile
        # or absurd header: the budget bounds the TOTAL wait, this bounds any SINGLE interval.
        if ($Seconds -lt 1) { $Seconds = 1 }
        if ($Seconds -gt 120) { $Seconds = 120 }
        return @{ Seconds = [int]$Seconds; Source = $Source }
    }

    # -- Helper: how much of the per-CALL budget has this Invoke-OPIMArmRequest call already used? --
    # Whole seconds, deliberately the LARGER of two measures:
    #   1. Real wall-clock time since the call started. This is the honest measure and the one that
    #      binds in production: it counts time spent IN the requests as well as time spent waiting, so
    #      a call cannot creep past its ceiling through slow responses rather than sleeps.
    #   2. The seconds this call has asked Start-Sleep to wait. In production this is always the
    #      SMALLER of the two, since every sleep is also wall-clock time, so it never loosens the real
    #      bound. It exists so the bound is deterministic under test: the unit suite mocks
    #      Start-Sleep, which pins measure 1 near zero, and a bound no test can drive is a bound no
    #      test can prove.
    function Get-ArmCallElapsed ([hashtable]$CallBudget) {
        if (-not $CallBudget) { return 0 }
        $WallClockSecond = ([DateTime]::UtcNow - $CallBudget.StartUtc).TotalSeconds
        return [int][Math]::Floor([Math]::Max($WallClockSecond, [double]$CallBudget.WaitSpent))
    }

    # -- 401: token rejected or expired -> force a refresh and retry once --
    # One forced refresh serves the WHOLE call, pages included. Per-page budgets would turn a long -All
    # walk against a genuinely broken token into a refresh storm.
    $RefreshBudget = [ref]$false
    function Invoke-OPIMArmWithRefresh ([string]$CallPath, [string]$CallMethod, [hashtable]$CallBody, [string]$BaseUrl, [ref]$RefreshBudget) {
        $CallResult = Invoke-OPIMArmSingle -CallPath $CallPath -CallMethod $CallMethod -CallBody $CallBody -BaseUrl $BaseUrl
        if ([int]$CallResult.StatusCode -ne 401 -or -not $script:_OPIMAuthState -or $RefreshBudget.Value) {
            return $CallResult
        }
        $RefreshBudget.Value = $true
        Write-Verbose '[Invoke-OPIMArmRequest] Azure Resource Manager rejected the token (status=401). Forcing re-authentication and retrying once...'
        # The latch rule: Initialize-OPIMAuth is called directly in this function's own body, so a
        # refused refresh latches this frame, and the gate of the retry below finds it. No -TenantId:
        # the refresh keeps the session's tenant.
        Initialize-OPIMAuth -IncludeARM -ForceRefresh
        Invoke-OPIMArmSingle -CallPath $CallPath -CallMethod $CallMethod -CallBody $CallBody -BaseUrl $BaseUrl
    }

    # -- Throttle backoff: bounded retry around ONE request, pages included --
    # THE LOOP SITS OUTSIDE THE 401 REFRESH, and that ordering is the design.
    #   * A 429 or 503 is never a 401, so Invoke-OPIMArmWithRefresh hands it straight back and the
    #     refresh branch is not entered at all. A throttled response therefore CANNOT spend the refresh
    #     budget -- structurally, not by a check that could rot.
    #   * $RefreshBudget is one [ref] shared by the whole call, so however many times this loop
    #     re-enters, at most one forced refresh happens for the entire call, pages included. The two
    #     retry paths cannot multiply: the throttle side is bounded by the wait budget and the hard
    #     cap, the refresh side by a budget of one.
    #
    # THE NUMBERS (internal constants on purpose -- no public parameter):
    #   ThrottleWaitBudgetSeconds = 300, per REQUEST (per PAGE under -All). Five minutes absorbs a
    #     server-directed "Retry-After: 60" five times over.
    #   CallDeadlineSeconds = 900, per CALL, however many pages that call fetches. It is a DEADLINE,
    #     not a wait allowance: TIME SPENT IN THE REQUESTS THEMSELVES COUNTS TOWARD IT (see
    #     Get-ArmCallElapsed). It is only ever CONSULTED at a decision to WAIT, so it caps a THROTTLED
    #     call and nothing else: an -All walk that is never throttled follows its next links for as
    #     long as ARM hands out pages. A long, legitimately slow -All read that has already run past
    #     900 s refuses any further throttle backoff, turning a recoverable 429 on its last pages into
    #     a hard failure -- the intended trade, since an unbounded backoff is worse. Three times the
    #     per-page budget: enough that three fully-throttled pages can still be ridden out, which is
    #     the realistic recoverable case, but a ceiling the operator can predict from the cmdlet alone
    #     rather than from a page count they cannot see. Fifteen minutes is also about the longest an
    #     interactive operator will wait before concluding a session is hung, and past that a clean
    #     error beats a longer wait for the same all-or-nothing failure.
    #   ThrottleRetryHardCap = 10, per request. A runaway guard, not a primary bound. It binds only
    #     when a server answers with a very small Retry-After over and over -- the one shape where a
    #     budget alone would allow hundreds of requests against an already throttled endpoint.
    #
    # BOTH BOUNDS ARE ENFORCED AT THE DECISION TO WAIT, never by stopping the paging loop between
    # pages. Truncating an enumeration on a deadline would return a partial collection as though it
    # were complete. When the budget is gone this returns the throttled response and lets the caller's
    # non-2xx check convert and THROW it. The cost is deliberate: a call may overrun the deadline by
    # the last request's own duration.
    function Invoke-OPIMArmWithBackoff ([string]$CallPath, [string]$CallMethod, [hashtable]$CallBody, [string]$BaseUrl, [ref]$RefreshBudget, [hashtable]$CallBudget) {
        [int]$ThrottleWaitBudgetSeconds = 300
        [int]$CallDeadlineSeconds = 900
        [int]$ThrottleRetryHardCap = 10
        [int]$ThrottleWaitSpent = 0
        [int]$ThrottleAttempt = 0

        while ($true) {
            $CallResult = Invoke-OPIMArmWithRefresh -CallPath $CallPath -CallMethod $CallMethod `
                -CallBody $CallBody -BaseUrl $BaseUrl -RefreshBudget $RefreshBudget

            $Delay = Get-ArmThrottleDelay $CallResult $ThrottleAttempt
            if ($null -eq $Delay) { return $CallResult }

            [int]$RequestRemaining = $ThrottleWaitBudgetSeconds - $ThrottleWaitSpent
            [int]$CallRemaining = $CallDeadlineSeconds - (Get-ArmCallElapsed -CallBudget $CallBudget)

            # The per-CALL bound is checked FIRST so that when both are gone the operator is told about
            # the one that actually ends the command rather than the one that ends this page.
            if ($Delay.Seconds -gt $CallRemaining) {
                Write-Verbose ("[Invoke-OPIMArmRequest] Throttled. The next wait needs $($Delay.Seconds) s " +
                    "($($Delay.Source)) but only $CallRemaining s of the $CallDeadlineSeconds s per-CALL budget remain. Giving up.")
                return $CallResult
            }
            if ($Delay.Seconds -gt $RequestRemaining) {
                # Honouring a wait this module cannot afford would mean retrying EARLY, which just
                # earns another throttle. Give up cleanly and let the caller see the ARM error.
                Write-Verbose ("[Invoke-OPIMArmRequest] Throttled. The next wait needs $($Delay.Seconds) s " +
                    "($($Delay.Source)) but only $RequestRemaining s of the $ThrottleWaitBudgetSeconds s per-REQUEST budget remain. Giving up.")
                return $CallResult
            }
            if ($ThrottleAttempt -ge $ThrottleRetryHardCap) {
                Write-Verbose ("[Invoke-OPIMArmRequest] Throttled. Reached the hard cap of $ThrottleRetryHardCap " +
                    "throttle retries with $RequestRemaining s of per-REQUEST budget still unspent. Giving up.")
                return $CallResult
            }

            $ThrottleAttempt++
            $ThrottleWaitSpent += $Delay.Seconds
            if ($CallBudget) { $CallBudget.WaitSpent += $Delay.Seconds }
            $RequestRemaining = $ThrottleWaitBudgetSeconds - $ThrottleWaitSpent
            $CallRemaining = $CallDeadlineSeconds - (Get-ArmCallElapsed -CallBudget $CallBudget)
            # SECURITY: the status, the delay and its provenance only. The header COLLECTION this value
            # came from is never written to any stream -- see Get-ArmRetryAfterHeaderValue.
            Write-Verbose ("[Invoke-OPIMArmRequest] Throttled (status=$([int]$CallResult.StatusCode)). " +
                "Waiting $($Delay.Seconds) s ($($Delay.Source)) before retry $ThrottleAttempt; " +
                "$RequestRemaining s of per-REQUEST and $CallRemaining s of per-CALL budget remain.")
            Start-Sleep -Seconds $Delay.Seconds
        }
    }

    # -- Per-CALL deadline state, shared by every page of a -All enumeration --
    # A hashtable rather than two scalars so the nested function mutates THIS state by reference; a
    # value type would give each page its own copy and the per-call bound would never bind. The
    # single-page path gets one too, so both paths run identical code. The per-call bound can still
    # bind on the single-page path: Get-ArmCallElapsed counts wall-clock time spent IN the request, so
    # one slow or hung request can carry a single call past 900 s with WaitSpent still at 0.
    $CallBudget = @{ StartUtc = [DateTime]::UtcNow; WaitSpent = 0 }

    $Response = Invoke-OPIMArmWithBackoff -CallPath $Path -CallMethod $Method -CallBody $Body `
        -BaseUrl $ArmBaseUrl -RefreshBudget $RefreshBudget -CallBudget $CallBudget

    # EVERY THROW IN THIS FUNCTION IS FOLLOWED BY A RETURN (one inside a catch, by a flag read straight
    # after its try), and none of them is tidiness: under -ErrorAction SilentlyContinue or Ignore, with
    # no try up the call stack, a function carries on past its OWN throw to its next statement -- and so
    # does every caller of a nested function that threw, since a return there ends only that nested
    # function.
    #
    # No response object at all means a nested function already raised and returned: the ARM gate,
    # the missing-token refusal, the host refusal or the transport failure in Invoke-OPIMArmSingle.
    # Its record is the call's answer. Converting the missing response would add a parameter-binding
    # record of its own, since Convert-OPIMArmHttpException requires one.
    if ($null -eq $Response) { return }
    if ([int]$Response.StatusCode -lt 200 -or [int]$Response.StatusCode -gt 299) {
        throw (Convert-OPIMArmHttpException -Response $Response -Path $Path)
        # Carrying on would parse the error body and return it as data.
        return
    }

    # A write is answered with what it wrote. A 2xx answer to a PUT, POST or PATCH with no body says
    # nothing of what ARM made of the request -- it may have been accepted -- so it is a failed read,
    # never "no content". The caller's path as the target.
    if ([string]::IsNullOrWhiteSpace($Response.Content) -and $Method -in 'PUT', 'POST', 'PATCH') {
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('Azure Resource Manager returned no body for the request, so its answer could not be read; the request may have been accepted.'),
            'ArmTransportError',
            [System.Management.Automation.ErrorCategory]::InvalidResult,
            $Path)
        # Carrying on would hand back nothing, as though the request had no answer to read.
        return
    }

    # Every 2xx body is parsed into a FRESH variable inside a try whose catch only scrubs and sets a
    # flag, read straight after the try: a throw inside the catch would resume after the try under
    # -ErrorAction SilentlyContinue with no try up the call stack, and a failed assignment would leave a
    # reused variable holding the previous page. Without -All an empty body is no content ($null, as
    # for a 204 to a DELETE or a GET), but a body that does not parse is a failed read. With -All the
    # first page must carry a body that parses into an object with a value property: an ARM list always
    # answers with a value array, so an empty answer, or one without value, is a failed read, never an
    # empty list.
    $Parsed = $null
    $ReadFailed = $false
    if ($Response.Content) {
        try {
            $Parsed = $Response.Content | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Remove-OPIMErrorRecord -Record $PSItem
            $ReadFailed = $true
        }
    }
    if ($ReadFailed -or ($All -and ($null -eq $Parsed -or $null -eq $Parsed.PSObject.Properties['value']))) {
        $ReadMessage = if ($All) {
            'Page 1: Azure Resource Manager returned a body that could not be read, so the list is incomplete.'
        } else {
            'Azure Resource Manager returned a body that could not be read.'
        }
        # The caller's path as the target, never a next link.
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($ReadMessage),
            'ArmTransportError',
            [System.Management.Automation.ErrorCategory]::InvalidResult,
            $Path)
        # Carrying on would hand back nothing as an answer, or read a missing page as an empty list.
        return
    }

    if (-not $All) { return $Parsed }

    # -- Paging: aggregate value arrays across nextLink / @nextLink --
    $AllValues = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Parsed.value) { foreach ($Item in $Parsed.value) { $AllValues.Add($Item) } }
    $NextLink = if ($Parsed.PSObject.Properties['nextLink']) { $Parsed.nextLink }
    elseif ($Parsed.PSObject.Properties['@nextLink']) { $Parsed.'@nextLink' }
    else { $null }
    # The number of pages read so far; the message of a refused link names the page it would have read.
    [int]$PageNumber = 1
    # The path and query of every page requested in this call, the first included. A next link back to
    # a page already requested would read it again: a duplicated list, or a walk that never ends.
    # The first page was sent on the uri this builds, so the cast cannot fail here.
    $RequestedPages = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $null = $RequestedPages.Add(([uri]"$ArmBaseUrl$Path").PathAndQuery)

    while ($NextLink) {
        $NextParsed = $null
        $SameHost = [uri]::TryCreate([string]$NextLink, [UriKind]::Absolute, [ref]$NextParsed) -and
            $NextParsed.Scheme -eq 'https' -and
            [string]::Equals($NextParsed.Host, $ArmBaseHost, [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $SameHost) {
            # SEC (A5, as OPIM-46 for Graph): a next link elsewhere would carry the session's ARM token to
            # another host. It is never sent and the list is incomplete; the message names neither the
            # link nor its host. No error id, as the Graph wrapper's refusal.
            Write-CmdletError -Message ([System.Exception]::new(
                    "Page $($PageNumber + 1): Azure Resource Manager returned a next link that is not an https link on the session's Azure Resource Manager host, so it was not followed and the list is incomplete.")) `
                -Category SecurityError -TargetObject $null -Cmdlet $PSCmdlet -Terminating
            # ThrowTerminatingError ends this function even under SilentlyContinue with no try up the
            # call stack, so this line is not reached. It stays so the loop can never fall through to
            # follow the link: return, never break.
            return
        }
        # The link's path and query on the session's own host: never the link's own host or port.
        $NextPath = $NextParsed.PathAndQuery
        if (-not $RequestedPages.Add($NextPath)) {
            # The page that carried the link points back into the list, so its body cannot be read as
            # the next part of it. The caller's path as the target, never the link. return, never
            # break: break would hand back the pages so far as the whole collection.
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Page $PageNumber`: Azure Resource Manager returned a body that could not be read, so the list is incomplete."),
                'ArmTransportError',
                [System.Management.Automation.ErrorCategory]::InvalidResult,
                $Path)
            return
        }
        # Each page gets its own per-REQUEST wait budget and shares the per-CALL deadline, so the paging
        # path backs off exactly like the single-request path.
        $PageResponse = Invoke-OPIMArmWithBackoff -CallPath $NextPath -CallMethod $Method -CallBody $Body `
            -BaseUrl $ArmBaseUrl -RefreshBudget $RefreshBudget -CallBudget $CallBudget
        # The same two checks as for the first page above. return, never break: break would hand back
        # the pages so far as though they were the whole collection.
        if ($null -eq $PageResponse) { return }
        if ([int]$PageResponse.StatusCode -lt 200 -or [int]$PageResponse.StatusCode -gt 299) {
            # The caller's path as the target, never the next link, whose query can carry a skip token.
            throw (Convert-OPIMArmHttpException -Response $PageResponse -Path $Path)
            # Carrying on would read the error body as a page with no next link, so the walk would end
            # and return the pages before it as the whole collection.
            return
        }
        $PageNumber++
        # A FRESH variable for every page, parsed as the first page is: a page that does not parse,
        # carries no body at all, or has no value property, is a failed read. Reusing the previous
        # page's variable added that page's items again and requested its next link again -- a
        # duplicated list, or an endless walk.
        $Page = $null
        $PageReadFailed = $false
        if ($PageResponse.Content) {
            try {
                $Page = $PageResponse.Content | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $PageReadFailed = $true
            }
        }
        if ($PageReadFailed -or $null -eq $Page -or $null -eq $Page.PSObject.Properties['value']) {
            # The caller's path as the target, never the next link, whose query can carry a skip token.
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Page $PageNumber`: Azure Resource Manager returned a body that could not be read, so the list is incomplete."),
                'ArmTransportError',
                [System.Management.Automation.ErrorCategory]::InvalidResult,
                $Path)
            # return, never break: break would hand back the pages so far as the whole collection.
            return
        }
        if ($null -ne $Page.value) { foreach ($Item in $Page.value) { $AllValues.Add($Item) } }
        $NextLink = if ($Page.PSObject.Properties['nextLink']) { $Page.nextLink }
        elseif ($Page.PSObject.Properties['@nextLink']) { $Page.'@nextLink' }
        else { $null }
    }

    return [PSCustomObject]@{ value = $AllValues.ToArray() }
}
