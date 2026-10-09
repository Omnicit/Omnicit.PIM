function Initialize-OPIMAuth {
    <#
    .SYNOPSIS
    The single authentication entry point for Omnicit.PIM. Acquires a Graph token via MSAL.NET,
    wires it into Connect-MgGraph, and optionally acquires an Azure Resource Manager token via AzAuth.

    .DESCRIPTION
    All Get-/Enable-/Disable-OPIM* cmdlets call this function at their entry point.
    It is idempotent: when a valid Graph token is already cached for the requested tenant and
    (when -IncludeARM is given) the cached Azure Resource Manager token is for the same tenant and
    account with more than 5 minutes left, it returns immediately without making any network calls
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
    call, Connect-MgGraph or Get-AzToken, and latches nothing (BL-74). Every other entry latches
    the command that called it (Lock-OPIMSignIn) and releases it only on a success
    (Unlock-OPIMSignIn): the cached return, or a sign-in that went the whole way. A refusal or a
    terminating error -- TenantMismatch, AccountMismatch, GraphSessionChanged, a failed device code
    sign-in -- and a failed Azure sign-in leave it latched, and Invoke-OPIMGraphRequest and the ARM
    gate Get-OPIMArmRefusal then refuse every request that command makes with SignInRefused, since
    outside any try a command carries on past a terminating error raised here.

    For Azure RBAC commands, pass -IncludeARM. The Azure Resource Manager token is acquired after
    Graph, since it needs the session's tenant: the tenant the Graph token was issued for
    (TokenTenantId), always a GUID, also for a session pinned by domain or first signed in under
    'organizations'. It comes from AzAuth's Get-AzToken for the resource https://management.azure.com
    and that tenant -- interactively in the system browser, or with a device code in device code
    mode -- with AzAuth's own authentication, separate from the Graph sign-in, waiting up to 900
    seconds for it (TimeoutSeconds), as long as a device code lives. A session that records no account
    (the oid of its Graph token) is refused with AccountMismatch before Get-AzToken is called, since no
    ARM token could be kept for it. Every new ARM token is checked before it is kept (A3): its tid must
    be the session's tenant (TenantMismatch otherwise, also when it cannot be read) and its oid the
    account of the session's Graph token (AccountMismatch otherwise, also when it cannot be read). A
    refused token also drops the ARM token the state held, so the next -IncludeARM sign-in rebuilds
    AzAuth's credential. Only a token that passed is kept, as a SecureString in the auth state and in
    memory only, never on disk, with its expiry, tenant and account, for Invoke-OPIMArmRequest to send.
    A cached ARM token is reused silently only when it was issued for the same tenant and the same
    account and has more than 5 minutes left. A new Graph token for another tenant or another account
    drops the cached ARM token, so the next -IncludeARM acquires a new one. A failed Get-AzToken ends
    this function with the terminating AzureConnectFailed, which keeps the AzAuth message but neither
    its exception nor its record; when Get-AzToken cannot be found at all, its message says that AzAuth
    is not installed or could not be loaded (AzAuth 2.9.0 needs PowerShell 7.4 or later). AzAuth keeps
    one credential per process, so the first ARM sign-in of a session and every -ForceRefresh pass
    -Force to rebuild it.

    Graph auth and Azure auth are intentionally independent -- the Microsoft Graph Command Line
    Tools app registration (used by MSAL here) is not authorised for Azure Resource Manager.

    With -DeviceCode, or once a session has used it, the Graph token comes from the device code flow
    (Invoke-OPIMDeviceCodeAuth) instead of the system browser, and the ARM token from
    Get-AzToken -DeviceCode. AzAuth writes its sign-in instruction as a warning; this function
    re-emits it on the Information stream with the OPIMDeviceCode tag, as the Graph device code is,
    so a host that silenced warnings still shows it. The mode is stored as DeviceCode in the auth
    state, so every later sign-in in the session uses it -- the silent refresh, the token-rejected
    retry and the ACRS step-up in Invoke-OPIMGraphRequest pass no -DeviceCode -- until
    Disconnect-OPIM clears the state. A device code session never falls back to the system browser.
    Before the first sign-in the state holds only DeviceCode, which never counts as signed in, so a
    first sign-in that fails (a declined or expired code, Ctrl+C) keeps the mode too. A failed device
    code flow ends this function with the helper's DeviceCodeAuthFailed error and no second error
    after it.

    .PARAMETER TenantId
    The Entra ID tenant GUID or domain. When omitted or empty, the session keeps the tenant it is
    signed in to. Only before the first sign-in is 'organizations' used (the home tenant of the
    authenticating account), and the session is then pinned to the tenant of that sign-in's token.
    Must match the tenant the user intends to manage PIM in; a token issued for another tenant is
    refused with TenantMismatch.

    .PARAMETER IncludeARM
    When set, ensures an Azure Resource Manager token for the tenant of the Graph session's token and
    its account. A cached ARM token is reused without a call only when its tenant and its account (the
    tid and oid claims) are the session's and it has more than 5 minutes left. Otherwise AzAuth's
    Get-AzToken acquires a new one for that tenant, interactively or with a device code by the
    session's mode, and the token is kept only after its tid and oid matched the Graph session's, as
    a SecureString in memory. A failed sign-in ends this function with AzureConnectFailed.

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
    invalid or expired. Usually completes without a sign-in prompt. With -IncludeARM it also acquires
    a new Azure Resource Manager token, passing -Force to Get-AzToken.

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

    # The Azure Resource Manager resource. A constant until the cloud table owns it (OPIM-29).
    [string]$ArmResource = 'https://management.azure.com'

    # AzAuth (A6), ported from Omnicit.EntraRBAC Invoke-AzTokenCall. In device code mode AzAuth writes its
    # sign-in instruction on the WARNING stream; it is re-emitted on the Information stream with the
    # OPIMDeviceCode tag, as the Graph device code is, while Get-AzToken still waits. -WarningAction
    # Continue is load-bearing: a record dropped at source under a silenced warning preference cannot be
    # redirected. The pipeline ends in a script block, not ForEach-Object, so the token object AzAuth
    # returns is bound to no command parameter (module logging records every bound value).
    function Invoke-OPIMAzTokenCall ([hashtable]$TokenParameter, [switch]$DeviceCodeFlow) {
        if (-not $DeviceCodeFlow) {
            return Get-AzToken @TokenParameter
        }
        Get-AzToken @TokenParameter -WarningAction Continue 3>&1 | & {
            process {
                if ($PSItem -is [System.Management.Automation.WarningRecord]) {
                    Write-Information -MessageData $PSItem.Message -Tags 'OPIMDeviceCode' -InformationAction Continue
                } else {
                    $PSItem
                }
            }
        }
    }

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
    # send under the session or the ARM token an earlier sign-in left. Keyed on the calling
    # command's invocation, so a nested command's or a pipeline neighbour's success releases only its
    # own entry. The caller is the command that called this function directly: the cmdlet,
    # Invoke-OPIMGraphRequest's nested Invoke-OPIMGraphSingle for its claims step-up and
    # token-rejected retry, or Invoke-OPIMArmRequest's nested Invoke-OPIMArmWithRefresh for its one
    # refresh after a 401.
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

        # MSAL methods that take MSAL types are found by name through GetMethods(), never through
        # GetMethod(name, [Type[]]): MSAL lives in the Graph SDK's own AssemblyLoadContext, whose
        # types are not the default context's. A typed GetMethod is used below only for [bool] and
        # [string] (WithForceRefresh, WithUseEmbeddedWebView, WithLoginHint, WithClaims).
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
        # Graph SDK session the module connected (it holds no token). ObjectId is the oid of the
        # Graph token, the account every ARM token must be issued to. The state holds no Graph token,
        # and the ARM token only as a SecureString (A6), with its expiry, tenant, account and
        # resource.
        # A3: the Graph token's own object id, compared with every ARM token's oid.
        [string]$GraphObjectId = Get-OPIMTokenObjectId -AccessToken $SecureToken
        # SEC (A3): an ARM token survives a new Graph token only when it was issued for the same tenant
        # and the same account; otherwise it is dropped, never carried, and -IncludeARM acquires a new
        # one.
        $PreviousState = $script:_OPIMAuthState
        [bool]$KeepArmToken = ($PreviousState -is [System.Collections.IDictionary]) -and
            ($null -ne $PreviousState['ArmToken']) -and
            [bool]$GraphObjectId -and
            [string]$PreviousState['ArmTokenTenantId'] -eq $TokenTenant -and
            [string]$PreviousState['ArmTokenObjectId'] -eq $GraphObjectId
        $script:_OPIMAuthState = @{
            TenantId                = if ($EffectiveTenant -eq 'organizations') { $TokenTenant } else { $EffectiveTenant }
            TokenTenantId           = $TokenTenant
            AuthorityTenant         = $Authority
            Account                 = $AuthResult.Account
            ObjectId                = if ($GraphObjectId) { $GraphObjectId } else { $null }
            GraphTokenExpiry        = $GraphTokenExpiry
            ClaimsSatisfied         = [bool]$ClaimsChallenge
            DeviceCode              = $UseDeviceCode
            GraphSessionFingerprint = $GraphSessionFingerprint
            ArmToken                = if ($KeepArmToken) { $PreviousState['ArmToken'] } else { $null }
            ArmTokenExpiry          = if ($KeepArmToken) { $PreviousState['ArmTokenExpiry'] } else { $null }
            ArmTokenTenantId        = if ($KeepArmToken) { $PreviousState['ArmTokenTenantId'] } else { $null }
            ArmTokenObjectId        = if ($KeepArmToken) { $PreviousState['ArmTokenObjectId'] } else { $null }
            ArmResourceUrl          = if ($KeepArmToken) { $PreviousState['ArmResourceUrl'] } else { $null }
        }
    }

    # -- Azure Resource Manager token (when requested) ---------------------------
    # A2/A6: Azure is signed in by AzAuth, separately from Graph (the Microsoft Graph Command Line Tools
    # app is not authorised for ARM), for the tenant of the session's Graph token, interactively or with a
    # device code by the session's mode. The token is kept as a SecureString in the auth state and never
    # written to disk; Invoke-OPIMArmRequest sends it.
    if ($IncludeARM) {
        [string]$ArmTenant = [string]$script:_OPIMAuthState.TokenTenantId
        if (-not $ArmTenant) {
            # Cannot happen for a state this module built. Refused rather than signed in without a tenant.
            Write-CmdletError -ErrorRecord (New-OPIMTenantMismatchError -RequestedTenant $EffectiveTenant -Unreadable) -Cmdlet $PSCmdlet -Terminating
            return
        }
        [string]$SessionObjectId = [string]$script:_OPIMAuthState.ObjectId
        # SEC (A3): an ARM token is kept only for the account of the Graph session, so a session that
        # records no account can keep none. Refused before Get-AzToken, so no AzAuth sign-in is shown
        # for a token that would be refused.
        if (-not $SessionObjectId) {
            Write-CmdletError -ErrorRecord (New-OPIMAccountMismatchError -RequestedTenant $ArmTenant -Unreadable) -Cmdlet $PSCmdlet -Terminating
            return
        }

        # Silent reuse only for the same tenant and the same account with more than 5 minutes left.
        [bool]$ArmCached = -not $ForceRefresh -and
            ($null -ne $script:_OPIMAuthState.ArmToken) -and
            $script:_OPIMAuthState.ArmTokenExpiry -gt [DateTime]::UtcNow.AddMinutes(5) -and
            [string]$script:_OPIMAuthState.ArmTokenTenantId -eq $ArmTenant -and
            [string]$script:_OPIMAuthState.ArmTokenObjectId -eq $SessionObjectId

        if (-not $ArmCached) {
            # TimeoutSeconds: AzAuth stops waiting for the sign-in after 120 seconds by default, much less
            # than a device code lives (15 minutes), so the sign-in waits as long as the code can be used.
            $ArmTokenParams = @{ Resource = $ArmResource; Tenant = $ArmTenant; TimeoutSeconds = 900; ErrorAction = 'Stop' }
            if ($UseDeviceCode) { $ArmTokenParams.DeviceCode = $true } else { $ArmTokenParams.Interactive = $true }
            # AzAuth keeps one credential per process (EntraRBAC A6 rule). -Force rebuilds it: on a forced
            # refresh, and on the first ARM sign-in of a session -- after Disconnect-OPIM, or when the
            # Graph identity changed -- so a reused credential never answers for an earlier sign-in (a
            # device-code credential reused for another tenant never returns, measured in EntraRBAC).
            if ($ForceRefresh -or $null -eq $script:_OPIMAuthState.ArmToken) { $ArmTokenParams.Force = $true }
            try {
                $ArmResult = Invoke-OPIMAzTokenCall -TokenParameter $ArmTokenParams -DeviceCodeFlow:$UseDeviceCode
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                # Terminating, and the calling command stays latched (EntraRBAC A19), so its ARM requests
                # are refused with SignInRefused. The AzAuth message only: no inner exception, and the
                # session tenant as the target object. A Get-AzToken that cannot be found at all means
                # AzAuth is missing, or did not load (it needs PowerShell 7.4), and the message says so.
                $AzureFailure = if ($PSItem.Exception -is [System.Management.Automation.CommandNotFoundException] -or
                    ([string]$PSItem.FullyQualifiedErrorId).StartsWith('CommandNotFoundException', [System.StringComparison]::Ordinal)) {
                    'Azure connection failed: the AzAuth module is not installed or could not be loaded. Install AzAuth 2.9.0 from the PowerShell Gallery; it needs PowerShell 7.4 or later.'
                } else {
                    "Azure connection failed: $($PSItem.Exception.Message)"
                }
                Write-CmdletError `
                    -Message ([System.Exception]::new($AzureFailure)) `
                    -ErrorId 'AzureConnectFailed' `
                    -Category AuthenticationError `
                    -TargetObject $ArmTenant `
                    -Cmdlet $PSCmdlet `
                    -Terminating
                return
            }
            if (-not $ArmResult -or -not $ArmResult.Token) {
                Write-CmdletError `
                    -Message ([System.Exception]::new('Azure connection failed: the Azure sign-in returned no access token.')) `
                    -ErrorId 'AzureConnectFailed' `
                    -Category AuthenticationError `
                    -TargetObject $ArmTenant `
                    -Cmdlet $PSCmdlet `
                    -Terminating
                return
            }
            # The plaintext reaches .NET only, as for the Graph token above.
            $SecureArmToken = [System.Net.NetworkCredential]::new('', $ArmResult.Token).SecurePassword
            $ArmTokenExpiry = ConvertTo-OPIMUtcDateTime -Value $ArmResult.ExpiresOn
            $ArmResult = $null

            # SEC (A3, OPIM-47): the ARM token must be for the tenant AND the account of the Graph
            # session. Refused before it reaches the auth state, so no ARM request ever carries it. The
            # account is read only once the tenant matched.
            [string]$ArmTokenTenant = Get-OPIMTokenTenantId -AccessToken $SecureArmToken
            [string]$ArmTokenObject = ''
            $ArmTokenRefusal = if (-not $ArmTokenTenant) {
                New-OPIMTenantMismatchError -RequestedTenant $ArmTenant -Source Azure -Unreadable
            } elseif ($ArmTokenTenant -ne $ArmTenant) {
                New-OPIMTenantMismatchError -RequestedTenant $ArmTenant -Source Azure
            } else {
                $ArmTokenObject = Get-OPIMTokenObjectId -AccessToken $SecureArmToken
                if (-not $ArmTokenObject) {
                    New-OPIMAccountMismatchError -RequestedTenant $ArmTenant -Unreadable
                } elseif ($ArmTokenObject -ne $SessionObjectId) {
                    New-OPIMAccountMismatchError -RequestedTenant $ArmTenant
                }
            }
            if ($null -ne $ArmTokenRefusal) {
                # A refused token drops the ARM token the state held as well: AzAuth's credential just
                # answered for another tenant or account, so the next -IncludeARM sign-in rebuilds it
                # (-Force) instead of reusing it, and no earlier ARM token outlives the refusal.
                foreach ($ArmKey in 'ArmToken', 'ArmTokenExpiry', 'ArmTokenTenantId', 'ArmTokenObjectId', 'ArmResourceUrl') {
                    $script:_OPIMAuthState[$ArmKey] = $null
                }
                Write-CmdletError -ErrorRecord $ArmTokenRefusal -Cmdlet $PSCmdlet -Terminating
                return
            }

            $script:_OPIMAuthState.ArmToken         = $SecureArmToken
            $script:_OPIMAuthState.ArmTokenExpiry   = $ArmTokenExpiry
            $script:_OPIMAuthState.ArmTokenTenantId = $ArmTokenTenant
            $script:_OPIMAuthState.ArmTokenObjectId = $ArmTokenObject
            $script:_OPIMAuthState.ArmResourceUrl   = $ArmResource
            Write-Verbose "[Initialize-OPIMAuth] Azure Resource Manager token acquired for tenant '$ArmTenant'. Expiry (UTC): $ArmTokenExpiry."
        } else {
            Write-Verbose "[Initialize-OPIMAuth] Reusing the Azure Resource Manager token for tenant '$ArmTenant'."
        }
    }

    # SEC (EntraRBAC A19): the new sign-in went the whole way -- Graph connected or cached, and the ARM
    # token acquired or reused, or not asked for -- so release the calling command's latch. The last
    # statement and not a finally: every refusal and terminating error above must leave the command
    # latched.
    Unlock-OPIMSignIn -Invocation $SignInCaller
}
