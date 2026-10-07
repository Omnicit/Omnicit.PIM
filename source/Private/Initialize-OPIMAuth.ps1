function Initialize-OPIMAuth {
    <#
    .SYNOPSIS
    The single authentication entry point for Omnicit.PIM. Acquires a Graph token via MSAL.NET,
    wires it into Connect-MgGraph, and optionally connects to Azure via Connect-AzAccount.

    .DESCRIPTION
    All Get-/Enable-/Disable-OPIM* cmdlets call this function at their entry point.
    It is idempotent: when a valid Graph token is already cached for the requested tenant and
    (when -IncludeARM is given) the cached Azure context is validated by silently minting an ARM
    access token via Get-AzAccessToken, it returns immediately without making any network calls
    or showing any sign-in prompt.

    Graph token acquisition order:
      1. AcquireTokenSilent -- uses the MSAL in-memory cache (refresh token).
         Falls through to interactive only on MsalUiRequiredException.
      2. AcquireTokenInteractive -- opens the system browser exactly once.
         If a ClaimsChallenge string is supplied the interactive call chains
         .WithClaims() so the step-up happens in the same single browser window.

    The session is pinned to one tenant. A call that names no tenant keeps the tenant the session
    is signed in to; 'organizations' is used only for a first sign-in that names none, and the
    session is then pinned to the tenant its token was issued for. A request matches the session
    when it names the session's tenant label, or a GUID equal to the tenant of the session's Graph
    token. A refresh of the session reuses the MSAL application it was built with. After every
    token, its tid claim is compared with the tenant asked for -- the GUID requested, or the
    session's recorded tenant -- and a token for another tenant, or one whose tenant cannot be read,
    ends this function with TenantMismatch before the token reaches Connect-MgGraph or the auth
    state. Only the module's own session counts as signed in: a Microsoft Graph context made outside
    the module is never adopted.

    The Microsoft Graph PowerShell SDK keeps one session per process. Straight after its own
    Connect-MgGraph this function records a fingerprint of that session
    (Get-OPIMGraphSessionFingerprint), and at every entry it compares the session the process holds
    with it (Get-OPIMGraphSessionState). When another Connect-MgGraph has replaced the session, the
    function ends with GraphSessionChanged before the cached return, a new token or a Connect-MgGraph:
    connecting again would move that session's calls to this module's tenant, so the user runs
    Disconnect-OPIM and signs in again. When the process holds no session at all, a cached token does
    not count, and the function signs in and connects again.

    A refused sign-in closes the transport for the command that asked for it (EntraRBAC A19). Every
    entry first refuses a sign-in under a command whose own sign-in was refused: when a latched
    command stands on the call stack outside the command that called this function
    (Get-OPIMSignInRefusal -OutsideCaller), the function ends with SignInRefused before any token
    call, Connect-MgGraph or Connect-AzAccount, and latches nothing (BL-74). Every other entry latches
    the command that called it (Lock-OPIMSignIn) and releases it only on a success
    (Unlock-OPIMSignIn): the cached return, or a sign-in that went the whole way. A refusal or a
    terminating error -- TenantMismatch, GraphSessionChanged, a failed device code sign-in -- and a
    failed Azure connection leave it latched, and Invoke-OPIMGraphRequest and the ARM gate
    Get-OPIMArmRefusal then refuse every request that command makes with SignInRefused, since outside
    any try a command carries on past a terminating error raised here.

    For Azure RBAC commands, pass -IncludeARM. Azure is checked after Graph, since it needs the
    session's tenant: the tenant the Graph token was issued for (TokenTenantId), always a GUID, also
    for a session pinned by domain or first signed in under 'organizations'. The Az module's cached
    context is reused, without a sign-in prompt, only when it is for that tenant and for the account
    the Graph session signed in with, and can mint an ARM token silently. Otherwise
    Connect-AzAccount -Tenant <that tenant> establishes a new context with the Az module's own
    authentication, which is separate from Graph auth and may open its own browser window, or in
    device code mode show its own code. A failed Connect-AzAccount ends this function with the
    terminating AzureConnectFailed, which keeps the Az message but neither the Az exception nor its
    record; an Az context for another tenant after the sign-in, or none, ends it with TenantMismatch.
    Before Connect-AzAccount the function sets the Az configuration for this process only
    (Update-AzConfig -Scope Process), each key in a call of its own: WAM off, and LoginExperienceV2
    off. LoginExperienceV2 off is what keeps the Azure sign-in from asking for a subscription, and it
    is safe because the module names the scope of every ARM call and never uses the default
    subscription. Connect-AzAccount also gets -SkipContextPopulation, which only skips filling the Az
    context list with a context for each of the first 25 subscriptions when the user has no context
    yet; it has no part in the subscription prompt. The two Update-AzConfig calls and
    Connect-AzAccount run with -WhatIf:$false and -Confirm:$false: a sign-in is not the change that
    -WhatIf previews (the Graph sign-in runs under -WhatIf too), and a -WhatIf handed down from
    Enable-OPIMMyRole or Disable-OPIMMyRole would otherwise connect nothing and end in a misleading
    TenantMismatch. The user's own Az configuration is never touched.

    Graph auth and Azure auth are intentionally independent -- the Microsoft Graph Command Line
    Tools app registration (used by MSAL here) is not authorised for Azure Resource Manager.

    With -DeviceCode, or once a session has used it, the Graph token comes from the device code flow
    (Invoke-OPIMDeviceCodeAuth) instead of the system browser, and Azure signs in with
    Connect-AzAccount -UseDeviceAuthentication. The mode is stored as DeviceCode in the auth state,
    so every later sign-in in the session uses it -- the silent refresh, the token-rejected retry and
    the ACRS step-up in Invoke-OPIMGraphRequest pass no -DeviceCode -- until Disconnect-OPIM clears
    the state. A device code session never falls back to the system browser. Before the first
    sign-in the state holds only DeviceCode, which never counts as signed in, so a first sign-in
    that fails (a declined or expired code, Ctrl+C) keeps the mode too. A failed device code flow
    ends this function with the helper's DeviceCodeAuthFailed error and no second error after it.

    .PARAMETER TenantId
    The Entra ID tenant GUID or domain. When omitted or empty, the session keeps the tenant it is
    signed in to. Only before the first sign-in is 'organizations' used (the home tenant of the
    authenticating account), and the session is then pinned to the tenant of that sign-in's token.
    Must match the tenant the user intends to manage PIM in; a token issued for another tenant is
    refused with TenantMismatch.

    .PARAMETER IncludeARM
    When set, ensures an Azure context for the tenant of the Graph session's token and its account.
    A cached Az context is trusted only when its tenant and account match and it is validated with a
    silent Get-AzAccessToken (not merely detected via Get-AzContext); the Az module autosaves its
    context to disk, so a stale context can resurface in a fresh session with an expired token. When
    no usable context exists, Connect-AzAccount is called with -Tenant set to the session's tenant.
    The Az module handles its own token caching independently of the MSAL/Graph cache.

    .PARAMETER ClaimsChallenge
    The decoded JSON claims challenge string extracted from a 401 WWW-Authenticate header.
    When supplied the function bypasses AcquireTokenSilent and performs an ACRS step-up with the
    claims chained on the sign-in request: AcquireTokenInteractive(...).WithClaims($ClaimsChallenge)
    in the system browser or, in device code mode,
    AcquireTokenWithDeviceCode(...).WithClaims($ClaimsChallenge).

    .PARAMETER ForceRefresh
    Bypass the cached-token idempotency check and force MSAL to mint a fresh access token via
    the refresh token (AcquireTokenSilent(...).WithForceRefresh($true)). Used by
    Invoke-OPIMGraphRequest to recover transparently when Graph rejects a bearer token as
    invalid or expired. Usually completes without a sign-in prompt.

    .PARAMETER DeviceCode
    Sign in with the device code flow instead of the system browser, and remember the mode in the
    auth state for every later sign-in in the session, even when this first sign-in fails. When a
    valid token is already cached, no new sign-in happens; only the mode is remembered.

    .EXAMPLE
    Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com'

    .EXAMPLE
    Initialize-OPIMAuth -TenantId $TenantId -IncludeARM

    .EXAMPLE
    Initialize-OPIMAuth -TenantId $TenantId -ClaimsChallenge $DecodedClaimsJson

    .EXAMPLE
    Initialize-OPIMAuth -TenantId $TenantId -DeviceCode
    #>
    [CmdletBinding()]
    param(
        [string]$TenantId,
        [switch]$IncludeARM,
        [string]$ClaimsChallenge,
        [switch]$ForceRefresh,
        [switch]$DeviceCode
    )

    # SEC (EntraRBAC BL-74): a sign-in under a command whose own sign-in was refused is refused before
    # any prompt. Only a frame OUTSIDE the calling command counts (Get-OPIMSignInRefusal
    # -OutsideCaller): the caller's own latched frame, from an earlier refused sign-in in the same
    # invocation, keeps its chance to sign in again. Before Lock-OPIMSignIn, so it latches nothing of
    # its own; the outer command's latch already refuses every request the caller makes.
    $OuterRefused = Get-OPIMSignInRefusal -OutsideCaller
    if ($OuterRefused) {
        Write-CmdletError -ErrorRecord (New-OPIMSignInRefusedError -Command $OuterRefused) -Cmdlet $PSCmdlet -Terminating
        return
    }
    # SEC (EntraRBAC A19): latch the calling command. Only a success releases it -- the cached return
    # and the last statement of a new sign-in that went the whole way. Every refusal and terminating
    # error leaves it latched, and both transports refuse every request it makes (SignInRefused):
    # outside any try a command carries on past a terminating error raised here, and would otherwise
    # send under the session or the Azure context an earlier sign-in left. Keyed on the calling
    # command's invocation, so a nested command's or a pipeline neighbour's success releases only its
    # own entry. The caller is the command that called this function directly: the cmdlet, or
    # Invoke-OPIMGraphRequest's nested Invoke-OPIMGraphSingle for its claims step-up and
    # token-rejected retry.
    $SignInCaller = Lock-OPIMSignIn

    # OPIM-07: a call that names no tenant keeps the session's tenant -- never 'organizations' once the
    # module holds one. 'organizations' is only the very first sign-in's authority.
    [string]$EffectiveTenant = if ($TenantId) {
        $TenantId
    } elseif ($script:_OPIMAuthState -and $script:_OPIMAuthState.TenantId) {
        [string]$script:_OPIMAuthState.TenantId
    } else {
        'organizations'
    }
    $ParsedTenant = [guid]::Empty
    [bool]$EffectiveIsGuid = [guid]::TryParse($EffectiveTenant, [ref]$ParsedTenant)

    # -- Sign-in mode ------------------------------------------------------------
    # -DeviceCode is remembered in the auth state, so every later sign-in in the session uses it:
    # the silent refresh, the token-rejected retry and the ACRS step-up in Invoke-OPIMGraphRequest
    # pass no -DeviceCode. A cached token that is still valid stays in use; only the mode changes.
    # Before the first sign-in the state holds only DeviceCode. That never counts as signed in (the
    # cache checks below need TenantId and GraphTokenExpiry), so a failed first sign-in keeps the
    # mode, and the next call asks for a device code again instead of opening the browser, until
    # Disconnect-OPIM clears it.
    if ($DeviceCode) {
        if ($script:_OPIMAuthState) {
            $script:_OPIMAuthState.DeviceCode = $true
        } else {
            $script:_OPIMAuthState = @{ DeviceCode = $true }
        }
    }
    [bool]$UseDeviceCode = $DeviceCode -or ($script:_OPIMAuthState -and $script:_OPIMAuthState.DeviceCode)

    # -- Session match -----------------------------------------------------------
    # The request names the session's tenant: its label, or the GUID its Graph token was issued for.
    # A state that holds only DeviceCode has no TenantId, so it never matches.
    [bool]$SessionMatches = $script:_OPIMAuthState -and $script:_OPIMAuthState.TenantId -and (
        $script:_OPIMAuthState.TenantId -eq $EffectiveTenant -or
        ($EffectiveIsGuid -and $script:_OPIMAuthState.TokenTenantId -eq $ParsedTenant.ToString('D')))

    # -- Graph SDK session check (OPIM-09, EntraRBAC A18) -----------------------
    # The SDK keeps one session per process, and every Graph call goes out under it. Compare it with
    # the fingerprint recorded after this module's own Connect-MgGraph: Untracked (nothing recorded
    # yet), Own, Absent (no session at all, so the module connects again with a token of its own) or
    # Changed (another Connect-MgGraph replaced it).
    $GraphSession = Get-OPIMGraphSessionState

    # -- Idempotency check -----------------------------------------------------
    # Graph: cached token is valid for at least 5 more minutes, same tenant, no new claims
    # challenge, and the SDK session is still the module's own. OPIM-09: only the module's own
    # session counts -- a live Graph context the module did not make is never adopted as one.
    # Azure: only checked when -IncludeARM is specified (below).
    $FiveMinutesFromNow = [DateTime]::UtcNow.AddMinutes(5)
    [bool]$GraphCached = $GraphSession -ne 'Absent' -and
                         $GraphSession -ne 'Changed' -and
                         $SessionMatches -and
                         -not $ClaimsChallenge -and
                         -not $ForceRefresh -and
                         $script:_OPIMAuthState.GraphTokenExpiry -gt $FiveMinutesFromNow

    # SEC (OPIM-09): never a cached return, a new token or a Connect-MgGraph under a session another
    # Connect-MgGraph made. Connecting again would switch that session's calls to this module's
    # tenant, so nothing here takes the session back; the message says to run Disconnect-OPIM. Before
    # the Azure check, so a refused call reaches nothing. The refusal ends only this function: a caller
    # outside any try carries on, so Invoke-OPIMGraphRequest repeats the check before every request.
    if ($GraphSession -eq 'Changed') {
        Write-CmdletError -ErrorRecord (New-OPIMGraphSessionChangedError) -Cmdlet $PSCmdlet -Terminating
        return
    }

    # Graph only: a cached token is the whole answer. With -IncludeARM the Azure check below needs the
    # session's tenant, so it runs after the Graph block, cached or not.
    if ($GraphCached -and -not $IncludeARM) {
        Write-Verbose "[Initialize-OPIMAuth] Returning cached auth state for tenant '$EffectiveTenant'."
        # SEC (EntraRBAC A19): a cache hit is a success; release the calling command's latch.
        Unlock-OPIMSignIn -Invocation $SignInCaller
        return
    }

    # -- Graph authentication (skipped when Graph token is still valid) --------
    if (-not $GraphCached) {
        # OPIM-07: the MSAL app is rebuilt only when the tenant really changes. A session keeps the
        # authority its app was built with -- 'organizations' after a first sign-in that named none --
        # so a refresh reuses the app and its token cache instead of prompting again.
        [string]$Authority = if ($SessionMatches -and $script:_OPIMAuthState.AuthorityTenant) {
            [string]$script:_OPIMAuthState.AuthorityTenant
        } else {
            $EffectiveTenant
        }
        # The tenant every token must be issued for: the GUID asked for, else the session's recorded
        # tenant. A first sign-in under 'organizations' or a new domain has none to compare with yet;
        # its token's tid becomes the session's tenant.
        [string]$ExpectedTenant = if ($EffectiveIsGuid) {
            $ParsedTenant.ToString('D')
        } elseif ($SessionMatches -and $script:_OPIMAuthState.TokenTenantId) {
            [string]$script:_OPIMAuthState.TokenTenantId
        } else {
            ''
        }

        Write-Verbose "[Initialize-OPIMAuth] Acquiring Graph token for tenant '$EffectiveTenant' (authority '$Authority'). ClaimsChallenge=$(if ($ClaimsChallenge) { 'YES' } else { 'NO' })"

        $MsalApp = Get-OPIMMsalApplication -TenantId $Authority

        # -- Graph scopes (all PIM surfaces in one prompt) ---------------------
        [string[]]$GraphScopes = @(
            'RoleEligibilitySchedule.ReadWrite.Directory'
            'RoleAssignmentSchedule.ReadWrite.Directory'
            'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup'
            'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup'
            'AdministrativeUnit.Read.All'
            'User.Read'
        )

        # Use GetMethods() name-based search to avoid cross-AssemblyLoadContext type-identity
        # failures. The MSAL assembly lives in the Graph SDK's custom ALC; types loaded from
        # that ALC are not identical to the same types from the default ALC, so
        # GetMethod(name, [Type[]]) with default-ALC type arguments returns $null.
        $AppType = $MsalApp.GetType()

        $CachedAccount = if ($script:_OPIMAuthState -and $script:_OPIMAuthState.Account) {
            $script:_OPIMAuthState.Account
        } else {
            $null
        }

        $AuthResult = $null

        # -- Try silent acquisition first (unless we have a claims challenge) --
        if (-not $ClaimsChallenge -and $CachedAccount) {
            Write-Verbose "[Initialize-OPIMAuth] Attempting silent token acquisition..."
            $SilentMethod = $AppType.GetMethods() |
                Where-Object {
                    $_.Name -eq 'AcquireTokenSilent' -and
                    ($SilentParams = $_.GetParameters()) -and
                    $SilentParams.Count -eq 2 -and
                    $SilentParams[0].ParameterType.Name -eq 'IEnumerable`1' -and
                    $SilentParams[1].ParameterType.Name -match 'IAccount'
                } | Select-Object -First 1

            try {
                # Use [object[]]::new() instead of @(, $x, $y) -- the unary-comma syntax
                # wraps $GraphScopes in a nested object[] which the runtime cannot coerce
                # to IEnumerable<string>.
                $SilentArgs    = [object[]]::new(2)
                $SilentArgs[0] = $GraphScopes
                $SilentArgs[1] = $CachedAccount
                $SilentBuilder = $SilentMethod.Invoke($MsalApp, $SilentArgs)

                # Force MSAL to bypass its cached access token and refresh from the STS when
                # the caller asked for it (e.g. Graph rejected the current token as expired).
                if ($ForceRefresh) {
                    $WithForceRefreshMethod = $SilentBuilder.GetType().GetMethod('WithForceRefresh', [Type[]]@([bool]))
                    if ($WithForceRefreshMethod) {
                        $SilentBuilder = $WithForceRefreshMethod.Invoke($SilentBuilder, @($true))
                        Write-Verbose '[Initialize-OPIMAuth] Silent acquisition forced to refresh (WithForceRefresh).'
                    }
                }

                $AuthResult    = $SilentBuilder.ExecuteAsync().GetAwaiter().GetResult()
                Write-Verbose "[Initialize-OPIMAuth] Silent acquisition succeeded. Token expiry: $($AuthResult.ExpiresOn.UtcDateTime)"
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                # MsalUiRequiredException or any reflection error -> fall through to a new sign-in
                # (the device code flow in device code mode, the system browser otherwise)
                Write-Verbose "[Initialize-OPIMAuth] Silent acquisition failed ($($_.Exception.GetType().Name)). Falling through to a new sign-in."
                $AuthResult = $null
            }
        }

        # -- Device code acquisition (initial auth or ACRS step-up) -----------
        if (-not $AuthResult -and $UseDeviceCode) {
            Write-Verbose '[Initialize-OPIMAuth] Starting device code authentication...'
            try {
                $AuthResult = Invoke-OPIMDeviceCodeAuth -MsalApp $MsalApp -Scopes $GraphScopes -ClaimsChallenge $ClaimsChallenge
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                # The helper's error is only statement-terminating here; end this function with it,
                # so a failure never runs on into a second NoAccessToken error.
                $PSCmdlet.ThrowTerminatingError($PSItem)
            }
        }

        # -- Interactive acquisition (initial auth or ACRS step-up) -----------
        # Never in device code mode: a session that asked for a device code has no browser to open.
        if (-not $AuthResult -and -not $UseDeviceCode) {
            Write-Verbose "[Initialize-OPIMAuth] Starting interactive authentication (system browser)..."
            $InteractiveMethod = $AppType.GetMethods() |
                Where-Object {
                    $_.Name -eq 'AcquireTokenInteractive' -and
                    ($_.GetParameters()).Count -eq 1 -and
                    ($_.GetParameters())[0].ParameterType.Name -eq 'IEnumerable`1'
                } | Select-Object -First 1

            $InteractiveArgs    = [object[]]::new(1)
            $InteractiveArgs[0] = $GraphScopes
            $InteractiveBuilder = $InteractiveMethod.Invoke($MsalApp, $InteractiveArgs)

            # Enforce system browser -- no WAM, no embedded WebView
            $WithEmbeddedMethod = $InteractiveBuilder.GetType().GetMethod('WithUseEmbeddedWebView', [Type[]]@([bool]))
            if ($WithEmbeddedMethod) {
                $InteractiveBuilder = $WithEmbeddedMethod.Invoke($InteractiveBuilder, @($false))
            }

            # Pre-fill login hint when we know the account (tenant switch, re-auth)
            if ($CachedAccount) {
                $WithLoginHintMethod = $InteractiveBuilder.GetType().GetMethod('WithLoginHint', [Type[]]@([string]))
                if ($WithLoginHintMethod) {
                    $InteractiveBuilder = $WithLoginHintMethod.Invoke($InteractiveBuilder, @($CachedAccount.Username))
                }
            }

            # Chain ACRS claims challenge when provided
            if ($ClaimsChallenge) {
                $WithClaimsMethod = $InteractiveBuilder.GetType().GetMethod('WithClaims', [Type[]]@([string]))
                if ($WithClaimsMethod) {
                    $InteractiveBuilder = $WithClaimsMethod.Invoke($InteractiveBuilder, @($ClaimsChallenge))
                    Write-Verbose "[Initialize-OPIMAuth] ACRS claims challenge chained: $ClaimsChallenge"
                } else {
                    $PSCmdlet.ThrowTerminatingError(
                        [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new(
                                'MSAL WithClaims method not found. Cannot satisfy the ACRS claims challenge. ' +
                                'Ensure Microsoft.Graph.Authentication >= 2.36.0 is installed.'),
                            'MsalWithClaimsNotFound',
                            [System.Management.Automation.ErrorCategory]::NotInstalled, $null))
                }
            }

            try {
                $AuthResult = $InteractiveBuilder.ExecuteAsync().GetAwaiter().GetResult()
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                Write-CmdletError `
                    -Message ([System.Exception]::new(
                        "Interactive authentication failed: $($PSItem.Exception.Message). " +
                        'On headless systems (Linux without a display server) the system browser ' +
                        'cannot be launched. Run this command on a desktop system.')) `
                    -InnerException $PSItem.Exception `
                    -ErrorId 'InteractiveAuthFailed' `
                    -Category AuthenticationError `
                    -Cmdlet $PSCmdlet `
                    -Terminating
            }
        }

        if (-not $AuthResult -or -not $AuthResult.AccessToken) {
            Write-CmdletError `
                -Message ([System.Exception]::new('Authentication completed but no access token was returned.')) `
                -ErrorId 'NoAccessToken' `
                -Category AuthenticationError `
                -Cmdlet $PSCmdlet `
                -Terminating
        }

        # The plaintext token reaches .NET only. Every command below receives this SecureString:
        # module logging (LogPipelineExecutionDetails) records every value bound to a command
        # parameter, so a bound string would put the bearer token in the event log. NetworkCredential
        # converts it without ConvertTo-SecureString -AsPlainText (PSSA rule
        # PSAvoidUsingConvertToSecureStringWithPlainText).
        $SecureToken = [System.Net.NetworkCredential]::new('', $AuthResult.AccessToken).SecurePassword

        # -- Tenant check (OPIM-07) ---------------------------------------------
        # After EVERY token, compare its tid with the tenant asked for. A difference is
        # TenantMismatch, raised before the token reaches Connect-MgGraph or the auth state.
        [string]$TokenTenant = Get-OPIMTokenTenantId -AccessToken $SecureToken
        if (-not $TokenTenant) {
            Write-CmdletError -ErrorRecord (New-OPIMTenantMismatchError -RequestedTenant $EffectiveTenant -Unreadable) -Cmdlet $PSCmdlet -Terminating
            return
        }
        if ($ExpectedTenant -and $TokenTenant -ne $ExpectedTenant) {
            Write-CmdletError -ErrorRecord (New-OPIMTenantMismatchError -RequestedTenant $EffectiveTenant) -Cmdlet $PSCmdlet -Terminating
            return
        }

        $GraphTokenExpiry = $AuthResult.ExpiresOn.UtcDateTime
        Write-Verbose "[Initialize-OPIMAuth] Graph token acquired. Account: $($AuthResult.Account.Username). Expiry (UTC): $GraphTokenExpiry. FromCache: $($AuthResult.AuthenticationResultMetadata.TokenSource -eq 'Cache')"

        # -- Wire Graph token into Connect-MgGraph -----------------------------
        # The same SecureString as the tenant check. A failure is scrubbed first, as on every
        # transport path, and still ends this function, before the auth state is written.
        try {
            Connect-MgGraph -AccessToken $SecureToken -NoWelcome -ErrorAction Stop
        } catch {
            Remove-OPIMErrorRecord -Record $PSItem
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
        # OPIM-09: the session this Connect-MgGraph left, read straight after it. Recorded even when it
        # is $null, so the key says the module connected; Get-OPIMGraphSessionState compares every
        # later session with it.
        $GraphSessionFingerprint = Get-OPIMGraphSessionFingerprint

        # -- Cache auth state ---------------------------------------------------
        # TenantId is the label the session is pinned to: as requested, or the token's tid after a
        # first sign-in under 'organizations'. TokenTenantId is the tid of the current Graph token;
        # AuthorityTenant is the tenant the MSAL app was built for; GraphSessionFingerprint is the
        # Graph SDK session the module connected (it holds no token).
        $script:_OPIMAuthState = @{
            TenantId                = if ($EffectiveTenant -eq 'organizations') { $TokenTenant } else { $EffectiveTenant }
            TokenTenantId           = $TokenTenant
            AuthorityTenant         = $Authority
            Account                 = $AuthResult.Account
            GraphTokenExpiry        = $GraphTokenExpiry
            ClaimsSatisfied         = [bool]$ClaimsChallenge
            DeviceCode              = $UseDeviceCode
            GraphSessionFingerprint = $GraphSessionFingerprint
        }
    }

    # -- Azure connection (when requested) -------------------------------------
    # The Az module manages its own authentication independently from MSAL/Graph.
    # The Microsoft Graph Command Line Tools app registration used above is NOT authorised
    # for Azure Resource Manager -- Connect-AzAccount handles Azure auth with its own sign-in
    # (a browser prompt, or a device code in device code mode) the first time, then caches the
    # context in the Az module.
    if ($IncludeARM) {
        # OPIM-08: Azure must be signed in to the Graph session's tenant -- always the GUID its token
        # was issued for, also for a session pinned by domain or first signed in under
        # 'organizations' -- and as the same account; anything else is a new sign-in, never a reuse.
        [string]$ArmTenant = [string]$script:_OPIMAuthState.TokenTenantId
        if (-not $ArmTenant) {
            # Cannot happen for a state this module built. Refused rather than signed in to Azure
            # without a tenant.
            Write-CmdletError -ErrorRecord (New-OPIMTenantMismatchError -RequestedTenant $EffectiveTenant -Unreadable) -Cmdlet $PSCmdlet -Terminating
            return
        }

        # A cached Az context object alone is NOT proof of a usable connection. The Az module
        # autosaves its context to disk (Enable-AzContextAutosave, on by default), so a brand-new
        # PowerShell session resurfaces a context whose underlying token may have expired or now
        # needs an interactive Conditional Access / MFA step-up. Verify that it can mint an ARM
        # access token silently (no browser) before reusing it. String -eq is case-insensitive, as
        # wanted for a GUID and a user principal name.
        $AzContext = Get-AzContext -ErrorAction SilentlyContinue
        [bool]$AzReusable = $false
        if ($AzContext -and [string]$AzContext.Tenant.Id -eq $ArmTenant -and
            $script:_OPIMAuthState.Account -and
            [string]$AzContext.Account.Id -eq [string]$script:_OPIMAuthState.Account.Username) {
            try {
                $null = Get-AzAccessToken -TenantId $ArmTenant -AsSecureString -WarningAction SilentlyContinue -ErrorAction Stop
                $AzReusable = $true
                Write-Verbose "[Initialize-OPIMAuth] Reusing the Azure context for tenant '$ArmTenant'."
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                Write-Verbose "[Initialize-OPIMAuth] Cached Azure context cannot acquire an ARM token silently ($($PSItem.Exception.GetType().Name)); signing in to Azure again."
            }
        }

        if (-not $AzReusable) {
            Write-Verbose "[Initialize-OPIMAuth] Connecting to Azure via Connect-AzAccount for tenant '$ArmTenant'..."

            # -WhatIf:$false -Confirm:$false on both Update-AzConfig calls and on Connect-AzAccount: a
            # sign-in is not the change -WhatIf previews (the Graph sign-in above runs under it too).
            # Enable-/Disable-OPIMMyRole -WhatIf or -Confirm hand $WhatIfPreference or
            # $ConfirmPreference down to here, and the Az cmdlets honour them: under -WhatIf
            # Connect-AzAccount would connect nothing, so the tenant check after it would report a
            # misleading TenantMismatch, and under -Confirm the settings would ask to be confirmed.

            # Force browser-based sign-in for parity with the Graph side. Since Az 12.0.0 (Az.Accounts
            # 3.0.0) WAM is the Windows default (the "Please select the account" picker), which hangs
            # in some terminals. Disable it at PROCESS scope only -- the user's persisted Az config is
            # never touched. No-op on Linux/macOS, where browser login is already the default.
            try {
                Update-AzConfig -EnableLoginByWam $false -Scope Process -WhatIf:$false -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            } catch { Remove-OPIMErrorRecord -Record $PSItem }

            # A15 (OPIM-43): Az 12.0.0 (Az.Accounts 3.0.0) and later ask for a subscription at sign-in
            # when the account reaches more than one. The module never uses the default subscription
            # -- every ARM call names its scope (asTarget() at '/', or the role's own scope) -- so
            # LoginExperienceV2 Off turns that prompt off, for this PROCESS only. This setting is what
            # keeps the prompt away. The user's own Az configuration (CurrentUser) is never touched. A
            # call of its own, so an Az.Accounts without this key still gets the WAM setting and signs
            # in.
            try {
                Update-AzConfig -LoginExperienceV2 Off -Scope Process -WhatIf:$false -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            } catch { Remove-OPIMErrorRecord -Record $PSItem }

            # -SkipContextPopulation only skips filling the Az context list with a context for each of
            # the first 25 subscriptions when the user has no context yet (Microsoft Learn,
            # Connect-AzAccount); the module reads none of them. It has no part in the subscription
            # prompt, which LoginExperienceV2 Off above keeps away.
            $AzParams = @{
                Tenant                = $ArmTenant
                SkipContextPopulation = $true
                WhatIf                = $false
                Confirm               = $false
                ErrorAction           = 'Stop'
            }
            # Device code mode signs in to Azure with a device code too. Connect-AzAccount writes its
            # own message with the code (Az.Accounts 5.5.3: an information record; older: a warning).
            if ($UseDeviceCode) {
                $AzParams.UseDeviceAuthentication = $true
            }
            try {
                Connect-AzAccount @AzParams | Out-Null
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                # Terminating (OPIM-08): a failed Azure sign-in ends this function, not the command.
                # A caller outside any try carries on past it, still latched (SEC, EntraRBAC A19: no
                # success, so the latch stays), and the ARM gate then refuses every Az.Resources call
                # it makes with SignInRefused. The record keeps the Az message only -- no inner
                # exception and the session tenant as its target object -- since the Az exception and
                # record can reference the request (OPIM-11).
                Write-CmdletError `
                    -Message ([System.Exception]::new("Azure connection failed: $($PSItem.Exception.Message)")) `
                    -ErrorId 'AzureConnectFailed' `
                    -Category AuthenticationError `
                    -TargetObject $ArmTenant `
                    -Cmdlet $PSCmdlet `
                    -Terminating
                return
            }

            # The context the sign-in left is the one every Az.Resources call runs under. One for
            # another tenant than the Graph session, or none, is refused.
            $AzContext = Get-AzContext -ErrorAction SilentlyContinue
            if (-not $AzContext -or [string]$AzContext.Tenant.Id -ne $ArmTenant) {
                Write-CmdletError -ErrorRecord (New-OPIMTenantMismatchError -RequestedTenant $ArmTenant -Source Azure) -Cmdlet $PSCmdlet -Terminating
                return
            }
        }
    }

    # SEC (EntraRBAC A19): the new sign-in went the whole way -- Graph connected or cached, and Azure
    # connected or not asked for -- so release the calling command's latch. The last statement and not
    # a finally: every refusal and terminating error above must leave the command latched.
    Unlock-OPIMSignIn -Invocation $SignInCaller
}
