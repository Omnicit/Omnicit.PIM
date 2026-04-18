function Initialize-OPIMAuth {
    <#
    .SYNOPSIS
    The single authentication entry point for Omnicit.PIM. Acquires a Graph token via MSAL.NET,
    wires it into Connect-MgGraph, and optionally connects to Azure via Connect-AzAccount.

    .DESCRIPTION
    All Get-/Enable-/Disable-OPIM* cmdlets call this function at their entry point.
    It is idempotent: when a valid Graph token is already cached for the requested tenant and
    (when -IncludeARM is given) an Azure context is already connected, it returns immediately
    without making any network calls or showing any browser prompt.

    Graph token acquisition order:
      1. AcquireTokenSilent — uses the MSAL in-memory cache (refresh token).
         Falls through to interactive only on MsalUiRequiredException.
      2. AcquireTokenInteractive — opens the system browser exactly once.
         If a ClaimsChallenge string is supplied the interactive call chains
         .WithClaims() so the step-up happens in the same single browser window.

    For Azure RBAC commands, pass -IncludeARM. Connect-AzAccount is called to establish an
    Azure context using the Az module's own authentication. This is separate from Graph auth
    and may open its own browser window on first use. Subsequent calls reuse the Az module's
    cached context (checked via Get-AzContext) without any browser prompt.

    Graph auth and Azure auth are intentionally independent — the Microsoft Graph Command Line
    Tools app registration (used by MSAL here) is not authorised for Azure Resource Manager.

    .PARAMETER TenantId
    The Entra ID tenant GUID or domain. When omitted or empty, 'organizations' is used
    (multi-tenant / home tenant of the authenticating account). Must match the tenant the
    user intends to manage PIM in.

    .PARAMETER IncludeARM
    When set, ensures an Azure context is available by calling Connect-AzAccount when
    Get-AzContext returns no current connection for the target tenant. The Az module
    handles its own token caching independently of the MSAL/Graph cache.

    .PARAMETER ClaimsChallenge
    The decoded JSON claims challenge string extracted from a 401 WWW-Authenticate header.
    When supplied the function bypasses AcquireTokenSilent and calls
    AcquireTokenInteractive(...).WithClaims($ClaimsChallenge) to perform an ACRS step-up.

    .EXAMPLE
    Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com'

    .EXAMPLE
    Initialize-OPIMAuth -TenantId $TenantId -IncludeARM

    .EXAMPLE
    Initialize-OPIMAuth -TenantId $TenantId -ClaimsChallenge $DecodedClaimsJson
    #>
    [CmdletBinding()]
    param(
        [string]$TenantId,
        [switch]$IncludeARM,
        [string]$ClaimsChallenge
    )

    # Resolve effective tenant; fall back to 'organizations' when caller supplies nothing.
    [string]$EffectiveTenant = if ($TenantId) { $TenantId } else { 'organizations' }

    # ── Idempotency check ─────────────────────────────────────────────────────
    # Graph: cached token is valid for at least 5 more minutes, same tenant, no new claims
    # challenge.
    # Azure: only checked when -IncludeARM is specified. Get-AzContext returning a context
    # for the right tenant means the Az module already has an active connection — no browser
    # prompt will be needed.
    $FiveMinutesFromNow = [DateTime]::UtcNow.AddMinutes(5)
    [bool]$GraphCached = $script:_OPIMAuthState -and
                         $script:_OPIMAuthState.TenantId -eq $EffectiveTenant -and
                         -not $ClaimsChallenge -and
                         $script:_OPIMAuthState.GraphTokenExpiry -gt $FiveMinutesFromNow

    # Evaluate Azure connectivity once here and reuse below to avoid a second Get-AzContext call.
    $AzCtxAtStart = if ($IncludeARM) { Get-AzContext -ErrorAction SilentlyContinue } else { $null }
    [bool]$AzAlreadyConnected = -not $IncludeARM -or (
        $AzCtxAtStart -and (
            $EffectiveTenant -eq 'organizations' -or
            $AzCtxAtStart.Tenant.Id -eq $EffectiveTenant
        )
    )

    if ($GraphCached -and $AzAlreadyConnected) {
        Write-Verbose "[Initialize-OPIMAuth] Returning cached auth state for tenant '$EffectiveTenant'."
        return
    }

    # ── Graph authentication (skipped when Graph token is still valid) ────────
    if (-not $GraphCached) {
        Write-Verbose "[Initialize-OPIMAuth] Acquiring Graph token for tenant '$EffectiveTenant'. ClaimsChallenge=$(if ($ClaimsChallenge) { 'YES' } else { 'NO' })"

        $MsalApp = Get-OPIMMsalApplication -TenantId $EffectiveTenant

        # ── Graph scopes (all PIM surfaces in one prompt) ─────────────────────
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

        # ── Try silent acquisition first (unless we have a claims challenge) ──
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
                # Use [object[]]::new() instead of @(, $x, $y) — the unary-comma syntax
                # wraps $GraphScopes in a nested object[] which the runtime cannot coerce
                # to IEnumerable<string>.
                $SilentArgs    = [object[]]::new(2)
                $SilentArgs[0] = $GraphScopes
                $SilentArgs[1] = $CachedAccount
                $SilentBuilder = $SilentMethod.Invoke($MsalApp, $SilentArgs)
                $AuthResult    = $SilentBuilder.ExecuteAsync().GetAwaiter().GetResult()
                Write-Verbose "[Initialize-OPIMAuth] Silent acquisition succeeded. Token expiry: $($AuthResult.ExpiresOn.UtcDateTime)"
            } catch {
                # MsalUiRequiredException or any reflection error → fall through to interactive
                Write-Verbose "[Initialize-OPIMAuth] Silent acquisition failed ($($_.Exception.GetType().Name)). Falling through to interactive."
                $AuthResult = $null
            }
        }

        # ── Interactive acquisition (initial auth or ACRS step-up) ───────────
        if (-not $AuthResult) {
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

            # Enforce system browser — no WAM, no embedded WebView
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
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new(
                            "Interactive authentication failed: $($_.Exception.Message). " +
                            'On headless systems (Linux without a display server) the system browser ' +
                            'cannot be launched. Run this command on a desktop system.', $_.Exception),
                        'InteractiveAuthFailed',
                        [System.Management.Automation.ErrorCategory]::AuthenticationError, $null))
            }
        }

        if (-not $AuthResult -or -not $AuthResult.AccessToken) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authentication completed but no access token was returned.'),
                    'NoAccessToken',
                    [System.Management.Automation.ErrorCategory]::AuthenticationError, $null))
        }

        $GraphTokenExpiry = $AuthResult.ExpiresOn.UtcDateTime
        Write-Verbose "[Initialize-OPIMAuth] Graph token acquired. Account: $($AuthResult.Account.Username). Expiry (UTC): $GraphTokenExpiry. FromCache: $($AuthResult.AuthenticationResultMetadata.TokenSource -eq 'Cache')"

        # ── Wire Graph token into Connect-MgGraph ─────────────────────────────
        $SecureToken = ConvertTo-SecureString $AuthResult.AccessToken -AsPlainText -Force
        Connect-MgGraph -AccessToken $SecureToken -NoWelcome -ErrorAction Stop

        # ── Cache auth state ───────────────────────────────────────────────────
        $script:_OPIMAuthState = @{
            TenantId         = $EffectiveTenant
            Account          = $AuthResult.Account
            GraphTokenExpiry = $GraphTokenExpiry
            ClaimsSatisfied  = [bool]$ClaimsChallenge
        }
    }

    # ── Azure connection (when requested) ─────────────────────────────────────
    # The Az module manages its own authentication independently from MSAL/Graph.
    # The Microsoft Graph Command Line Tools app registration used above is NOT authorised
    # for Azure Resource Manager — Connect-AzAccount handles Azure auth with its own browser
    # prompt the first time, then caches the context in the Az module.
    if ($IncludeARM -and -not $AzAlreadyConnected) {
        Write-Verbose "[Initialize-OPIMAuth] Connecting to Azure via Connect-AzAccount..."
        $AzParams = @{ ErrorAction = 'Stop' }
        if ($EffectiveTenant -ne 'organizations') {
            $AzParams.Tenant = $EffectiveTenant
        }
        try {
            Connect-AzAccount @AzParams | Out-Null
        } catch {
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "Azure connection failed: $($_.Exception.Message)", $_.Exception),
                'AzureConnectFailed',
                [System.Management.Automation.ErrorCategory]::AuthenticationError, $null))
        }
    } elseif ($IncludeARM -and $AzAlreadyConnected) {
        Write-Verbose "[Initialize-OPIMAuth] Azure already connected: $($AzCtxAtStart.Account.Id)"
    }
}
