function Initialize-OPIMAuth {
    <#
    .SYNOPSIS
    The single authentication entry point for Omnicit.PIM. Signs in to Microsoft Graph through AzAuth,
    wires the token into Connect-MgGraph, and optionally acquires an Azure Resource Manager token the
    same way.

    .DESCRIPTION
    All Get-/Enable-/Disable-OPIM* cmdlets call this function at their entry point.
    It is idempotent: when a valid Graph token is already cached for the requested tenant and
    (when -IncludeARM is given) the cached Azure Resource Manager token is for the same tenant and
    account with more than 5 minutes left, it returns immediately without making any network calls
    or showing any sign-in prompt.

    Microsoft Graph is signed in to through AzAuth's Get-AzToken, as Omnicit.EntraRBAC does (decision
    A16): one request for the Graph resource of the session's cloud, with the module's fixed scope list
    and the Microsoft Graph Command Line Tools public client (no app registration), interactively in
    the system browser or, in device code mode, with a device code. A claims challenge is passed on as
    -Claim, so an ACRS step-up happens in the same single sign-in. The token is then handed to
    Connect-MgGraph as a SecureString. The module builds no MSAL client of its own and reflects into
    no MSAL assembly. A renewal near the token's expiry, the token-rejected retry (-ForceRefresh) and
    an ACRS step-up sign in again -- a browser window, or a new device code -- except where AzAuth can
    renew a browser session silently, as below.

    A system-browser session is renewed without a prompt where AzAuth can answer from the interactive
    credential it already holds (ported from Omnicit.EntraRBAC A22). As READ in EntraRBAC from the
    AzAuth 2.11.0 and Azure.Identity 1.21.0 sources, not measured against a tenant, Get-AzToken
    (AzAuth 2.11.0 and later) accepts a non-interactive request that tries that credential first when
    the request is for the tenant of the last token call: the renewal is sent without -Interactive and
    without -ClientId, with -CredentialPrecedence Environment, so AzAuth's chain holds the stored
    interactive credential and the one source that sends nothing unless AZURE_* variables are set. It
    is tried only for a renewal of the session's own tenant and cloud in the system browser, only when
    the module's own record of the interactive credential AzAuth holds ($script:_OPIMInteractiveCredential,
    a client id and a tenant, never a token) names the client id and tenant the interactive request
    would pass, and never for a first sign-in, a device code session, -ForceRefresh, a claims
    challenge or a moved authority (each of which passes -Force, which clears the stored credential).
    Its token is accepted only when its oid and tid claims are the session's account and tenant;
    otherwise, or when the request fails, it is discarded and the interactive request runs exactly
    once, as before. An accepted token takes every check an interactive token takes. A token this
    function refuses (TenantMismatch, AccountMismatch) clears the record, so the next sign-in is
    interactive. AzAuth holds one
    interactive credential, the one the last interactive request built, so a session that signs in to
    Microsoft Graph and Azure alternates it between the two and still prompts for each renewal. A
    stored credential whose refresh token no longer works can still open the browser from this request,
    so the renewal means fewer prompts, not none.

    A sign-in in the system browser in a console host started with pwsh -NonInteractive is refused
    with the terminating InteractiveSignInUnavailable (EntraRBAC BL-100), after the cached return and
    before any token request, the silent renewal included: -NonInteractive declares that nobody can
    answer a prompt. Test-OPIMHostNonInteractive decides it. Device code mode is not affected.

    A new Microsoft Graph sign-in that continues the session -- a token issued for the session's tenant
    (the tid of its Graph token) in the session's cloud, however the tenant was named -- never makes
    the session another account's (EntraRBAC BL-119). When the oid of the new token and the session's
    account (ObjectId) are both GUIDs and differ, the sign-in ends with the terminating AccountMismatch
    (New-OPIMAccountMismatchError -Source Graph) before Connect-MgGraph: the token is not used and the
    state, the Graph SDK session and the cached ARM token stay as they were. A token without an oid
    never refuses, and a continuation whose token carries none keeps the session's ObjectId. Signing in
    as another account takes Disconnect-OPIM first.

    The session is pinned to one tenant. A call that names no tenant keeps the tenant the session
    is signed in to; 'organizations' is used only for a first sign-in that names none, and the
    session is then pinned to the tenant its token was issued for. A request matches the session
    when it names the session's tenant label, or a GUID equal to the tenant of the session's Graph
    token. After every token, its tid claim -- the token's own, never the tenant AzAuth reports beside
    it -- is compared with the tenant asked for: the GUID requested, or the session's recorded tenant.
    A token for another tenant, or one whose tenant cannot be read, ends this function with
    TenantMismatch before the token reaches Connect-MgGraph or the auth state. Only the module's own
    session counts as signed in: a Microsoft Graph context made outside the module is never adopted.

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
    terminating error -- TenantMismatch, AccountMismatch, GraphSessionChanged, a failed sign-in --
    and a failed Azure sign-in leave it latched, and Invoke-OPIMGraphRequest and the ARM gate
    Get-OPIMArmRefusal then refuse every request that command makes with SignInRefused, since
    outside any try a command carries on past a terminating error raised here.

    A failed Microsoft Graph sign-in ends this function with the terminating InteractiveAuthFailed in
    the system browser or DeviceCodeAuthFailed in device code mode, which keeps AzAuth's message but
    neither its exception nor its record; when Get-AzToken cannot be found at all, the message says
    that AzAuth is not installed or could not be loaded. A sign-in that returns no token ends with
    NoAccessToken.

    For Azure RBAC commands, pass -IncludeARM. The Azure Resource Manager token is acquired after
    Graph, since it needs the session's tenant: the tenant the Graph token was issued for
    (TokenTenantId), always a GUID, also for a session pinned by domain or first signed in under
    'organizations'. It comes from AzAuth's Get-AzToken for the Azure Resource Manager resource of the
    session's cloud (https://management.azure.com in the global cloud; the cloud table,
    Get-OPIMCloudEndpoint, owns the others) and that tenant -- interactively in the system browser,
    or with a device code in device code mode -- waiting up to 900 seconds for it (TimeoutSeconds),
    as long as a device code lives, as the Microsoft Graph sign-in does.
    A session that records no account (the oid of its Graph token) is refused with AccountMismatch
    before Get-AzToken is called, since no ARM token could be kept for it. Every new ARM token is
    checked before it is kept (A3): its tid must be the session's tenant (TenantMismatch otherwise,
    also when it cannot be read) and its oid the account of the session's Graph token
    (AccountMismatch otherwise, also when it cannot be read). A refused token also drops the ARM
    token the state held, so no earlier ARM token outlives the refusal. Only a token that passed is
    kept, as a SecureString in the auth state and in memory only, never on disk, with its expiry,
    tenant and account, for Invoke-OPIMArmRequest to send. A cached ARM token is reused silently
    only when it was issued for the same tenant and the same account, for the Azure Resource Manager
    resource of the session's cloud, and has more than 5 minutes left. A new Graph token for another
    tenant or another account drops the cached ARM token, so the next -IncludeARM acquires a new one.
    A failed Get-AzToken ends this function with the terminating AzureConnectFailed, which keeps the
    AzAuth message but neither its exception nor its record; when Get-AzToken cannot be found at all,
    its message says that AzAuth is not installed or could not be loaded (AzAuth 2.11.0 needs
    PowerShell 7.4 or later).

    AzAuth keeps one credential per process, keyed on neither the tenant nor the authority, and
    -Force is the only way to make it build a new one (EntraRBAC A17). Every token request in device
    code mode passes -Force, since a reused device code credential never returns; so does every
    request under -ForceRefresh, and every request whose cloud's sign-in authority differs from the one
    the module last asked AzAuth for ($script:_OPIMLastAuthorityHost, recorded before each token call,
    since a failed call still leaves AzAuth's credential built at the new authority, and never cleared
    by Disconnect-OPIM, since AzAuth's credential outlives it). After a Microsoft Graph sign-in the
    ARM request keeps -Force only for -ForceRefresh or a device code: the move of the authority is
    done.

    AzAuth's Get-AzToken has no authority parameter: Azure.Identity reads the AZURE_AUTHORITY_HOST
    environment variable when it builds the credential. For a sovereign cloud this function sets it to
    the cloud's sign-in authority host once, around both token calls, and puts it back in a finally on
    every path -- a failed sign-in and a refused token included -- so the process is never left pinned
    to a sovereign authority: an absent variable is deleted again (not left empty) and a value the
    operator had set is restored exactly. A cached return writes nothing. The Global cloud never
    writes the variable; when the operator's own value names another authority than the global one, a
    warning says that the Microsoft Entra ID sign-in, for Microsoft Graph and for Azure, follows it.

    With -DeviceCode, or once a session has used it, both sign-ins use a device code instead of the
    system browser. AzAuth writes its sign-in instruction as a warning; this function re-emits it on
    the Information stream with the OPIMDeviceCode tag, so a host that silenced warnings still shows
    it. The mode is stored as DeviceCode in the auth state, so every later sign-in in the session uses
    it -- the renewal, the token-rejected retry and the ACRS step-up in Invoke-OPIMGraphRequest pass
    no -DeviceCode -- until Disconnect-OPIM clears the state. A device code session never falls back
    to the system browser. With no state, -DeviceCode creates one holding only DeviceCode until a
    sign-in succeeds. It is no sign-in (no TenantId, no GraphTokenExpiry), so a failed first sign-in
    keeps the mode. A latched command sends nothing (SignInRefused), and the Graph transport's
    token-rejected retry and claims step-up sign in again only for a state that records a tenant.

    The cloud (OPIM-29) is a property of the tenant, so it follows the tenant. -Environment names it:
    Global, USGov, USGovDoD or China, in any letter case, resolved by Get-OPIMCloudEndpoint, which
    owns every cloud host. Microsoft 365 GCC is a commercial-cloud tenant and is Global. A call that
    names no cloud takes the session's cloud when it names the session's tenant, by label or by the
    GUID of its Graph token, or no tenant at all, and is Global for any other tenant. A state written
    before the cloud was recorded is Global. The cloud joins the session match: a call that names
    another cloud than the session's is a new sign-in, even for the same tenant, and the new session
    records it as Environment in the auth state. The Azure Resource Manager token of one cloud is
    never carried into another, even for the same tenant and account. An unknown cloud is an error,
    never a fallback to Global.

    The Microsoft Graph sign-in follows the cloud: AzAuth is asked for the Graph resource of the cloud
    table, at the cloud's sign-in authority, and the token is wired into the Graph SDK with
    Connect-MgGraph -Environment, named by the cloud table's GraphEnvironment. The Global cloud passes
    no -Environment to Connect-MgGraph at all, so the call stays the one the module always made.

    .PARAMETER TenantId
    The Entra ID tenant GUID or domain. When omitted or empty, the session keeps the tenant it is
    signed in to. Only before the first sign-in is 'organizations' used (the home tenant of the
    authenticating account; AzAuth is then asked for no tenant), and the session is then pinned to the
    tenant of that sign-in's token. Must match the tenant the user intends to manage PIM in; a token
    issued for another tenant is refused with TenantMismatch.

    .PARAMETER IncludeARM
    When set, ensures an Azure Resource Manager token for the tenant of the Graph session's token and
    its account. A cached ARM token is reused without a call only when its tenant and its account (the
    tid and oid claims) are the session's, it was minted for the Azure Resource Manager resource of
    the session's cloud, and it has more than 5 minutes left. Otherwise AzAuth's Get-AzToken
    acquires a new one for that tenant and cloud, interactively or with a device code by the
    session's mode, and the token is kept only after its tid and oid matched the Graph session's, as
    a SecureString in memory. A failed sign-in ends this function with AzureConnectFailed.

    .PARAMETER ClaimsChallenge
    The decoded JSON claims challenge string extracted from a 401 WWW-Authenticate header or a PIM
    policy refusal. When supplied, the cached token does not count: the function signs in to
    Microsoft Graph again through AzAuth with the claims passed on as Get-AzToken -Claim, in the
    system browser or, in device code mode, with a new device code, so the ACRS step-up happens in
    that one sign-in.

    .PARAMETER ForceRefresh
    Bypass the cached-token idempotency check and sign in to Microsoft Graph again, with -Force so
    AzAuth builds a new credential. Used by Invoke-OPIMGraphRequest to recover when Graph rejects a
    bearer token as invalid or expired. AzAuth has no refresh-token path, so this shows a sign-in: a
    browser window, or a new device code in device code mode. With -IncludeARM it also acquires a new
    Azure Resource Manager token, passing -Force to Get-AzToken.

    .PARAMETER DeviceCode
    Sign in with a device code instead of the system browser, and remember the mode in the auth
    state for every later sign-in in the session, even when this first sign-in fails. When a valid
    token is already cached, no new sign-in happens; only the mode is remembered.

    .PARAMETER Environment
    The cloud to sign in to: 'Global', 'USGov', 'USGovDoD' or 'China', in any letter case. Microsoft
    365 GCC is a commercial-cloud tenant and is 'Global'. When omitted, the session's cloud is kept
    for a call that names the session's tenant or none, and any other tenant is 'Global'. Naming a
    cloud other than the session's is a new sign-in, also for the same tenant. The cloud signed in
    to is recorded as Environment in the auth state.

    .EXAMPLE
    Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com'

    .EXAMPLE
    Initialize-OPIMAuth -TenantId $TenantId -IncludeARM

    .EXAMPLE
    Initialize-OPIMAuth -TenantId $TenantId -ClaimsChallenge $DecodedClaimsJson

    .EXAMPLE
    Initialize-OPIMAuth -TenantId $TenantId -DeviceCode

    .EXAMPLE
    Initialize-OPIMAuth -TenantId $TenantId -Environment USGov
    #>
    [CmdletBinding()]
    param(
        [string]$TenantId,
        [switch]$IncludeARM,
        [string]$ClaimsChallenge,
        [switch]$ForceRefresh,
        [switch]$DeviceCode,
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
        [string]$Environment
    )

    # AzAuth (A6, A16), ported from Omnicit.EntraRBAC Invoke-AzTokenCall, for the Microsoft Graph and
    # the Azure Resource Manager token alike. In device code mode AzAuth writes its sign-in instruction
    # on the WARNING stream; it is re-emitted on the Information stream with the OPIMDeviceCode tag
    # while Get-AzToken still waits. -WarningAction Continue is load-bearing: a record dropped at source
    # under a silenced warning preference cannot be redirected. The pipeline ends in a script block, not
    # ForEach-Object, so the token object AzAuth returns is bound to no command parameter (module
    # logging records every bound value).
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

    # True for the record of a Get-AzToken that cannot be found at all: AzAuth is missing, or did not
    # load (it needs PowerShell 7.4). Read by both sign-ins, so their messages cannot drift apart.
    function Test-OPIMAzAuthMissing ([System.Management.Automation.ErrorRecord]$Record) {
        $Record.Exception -is [System.Management.Automation.CommandNotFoundException] -or
            ([string]$Record.FullyQualifiedErrorId).StartsWith('CommandNotFoundException', [System.StringComparison]::Ordinal)
    }

    # True for a value that parses as a GUID: the account and tenant checks below compare only GUIDs, so
    # a value that is missing or unreadable proves nothing and never refuses.
    function Test-OPIMGuidText ($Value) {
        $Parsed = [guid]::Empty
        [guid]::TryParse([string]$Value, [ref]$Parsed)
    }

    # SEC (EntraRBAC A22, BL-115): the silent renewal of a system-browser session, sent and judged here
    # for both resources; the predicate that decides whether to try stands at each call site, where the
    # tracker and the request of that resource are known. It answers one question: did the
    # non-interactive request return a token for the account and tenant the session already holds? It
    # returns that token, or $null, and the caller then runs the interactive request exactly once.
    #
    # WHY IT CAN WORK. Read in EntraRBAC in the AzAuth 2.11.0 and Azure.Identity 1.21.0 sources (not
    # measured against a tenant): Get-AzToken's NonInteractive parameter set puts the stored credential
    # FIRST in its chain when that credential is an InteractiveBrowserCredential and the request names
    # the tenant of the LAST token call (TokenManager.NonInteractive.cs:71). The stored credential
    # carries an AuthenticationRecord once it has signed in, so it answers from MSAL's cache without a
    # prompt. Every interactive call builds a NEW credential holding only its client id, which is why
    # the tracker names the client id and the tenant of the call that built it, and why the silent
    # request names the same tenant and carries no -ClientId (refused at run time in that parameter
    # set, GetAzToken.cs, as read in EntraRBAC; the parameter metadata lists it).
    #
    # WHAT IT CANNOT PROMISE. A stored credential whose refresh token no longer works can still open the
    # browser from this very call, so "non-interactive" means "no prompt when MSAL can answer". Every
    # failure is treated alike: discarded, and the interactive request runs once.
    #
    # WHY THE IDENTITY CHECK. The chain's other source, Environment, answers when AZURE_CLIENT_ID and
    # its siblings are set in the process, and a browser opened from this call could be answered by
    # another account. So the token's own oid and tid claims (R10: never the TenantId AzAuth reports
    # beside it) are compared with the session's ObjectId and TokenTenantId, both GUIDs by the
    # predicate at the call site, and only an equal pair is accepted. Each half is its own term.
    #
    # The catch scrubs first and writes only a verbose line that names the exception TYPE: no error
    # record of its own (a caller's -ErrorVariable still collects the caught, scrubbed record, as the
    # engine collects every caught nested record), no warning, no message (a failed token request's message can quote the request). The
    # silent request leaves the tracker as it is: the credential AzAuth holds is still the one it was
    # built from.
    function Invoke-OPIMSilentRenewal ([hashtable]$SilentParameter) {
        try {
            $SilentResult = Invoke-OPIMAzTokenCall -TokenParameter $SilentParameter
            if (-not $SilentResult -or -not $SilentResult.Token) {
                Write-Verbose '[Initialize-OPIMAuth] The silent renewal returned no token; signing in interactively.'
                return $null
            }
            $SilentSecure = [System.Net.NetworkCredential]::new('', $SilentResult.Token).SecurePassword
            [bool]$SameAccount = (Get-OPIMTokenObjectId -AccessToken $SilentSecure) -eq [string]$script:_OPIMAuthState.ObjectId
            [bool]$SameTenant = (Get-OPIMTokenTenantId -AccessToken $SilentSecure) -eq [string]$script:_OPIMAuthState.TokenTenantId
        } catch {
            Remove-OPIMErrorRecord -Record $PSItem
            Write-Verbose "[Initialize-OPIMAuth] The silent renewal failed ($($PSItem.Exception.GetType().Name)); signing in interactively."
            return $null
        }
        if (-not $SameAccount -or -not $SameTenant) {
            Write-Verbose '[Initialize-OPIMAuth] The silent renewal returned a token for another account or tenant; discarded, signing in interactively.'
            return $null
        }
        Write-Verbose '[Initialize-OPIMAuth] Renewed the session silently.'
        return $SilentResult
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

    # -- Cloud (OPIM-29, A11) ------------------------------------------------------
    # The request names the session's tenant: its label, or the GUID its Graph token was issued for.
    # A state that holds only DeviceCode has no TenantId, so it never matches.
    [bool]$SessionTenantMatches = $script:_OPIMAuthState -and $script:_OPIMAuthState.TenantId -and (
        $script:_OPIMAuthState.TenantId -eq $EffectiveTenant -or
        ($EffectiveIsGuid -and $script:_OPIMAuthState.TokenTenantId -eq $ParsedTenant.ToString('D')))
    # A state written before the cloud was recorded is Global, the only cloud there was.
    [string]$StateEnvironment = if ($script:_OPIMAuthState -and $script:_OPIMAuthState.Environment) {
        [string]$script:_OPIMAuthState.Environment
    } else {
        'Global'
    }
    # The cloud is a property of the tenant (EntraRBAC): a request for the session's tenant that names no
    # cloud keeps the session's cloud; a request for another tenant that names none is Global.
    [string]$EffectiveEnvironment = if ($Environment) {
        $Environment
    } elseif ($SessionTenantMatches) {
        $StateEnvironment
    } else {
        'Global'
    }
    # Get-OPIMCloudEndpoint owns every cloud host and returns the canonical name.
    $Endpoint = Get-OPIMCloudEndpoint -Environment $EffectiveEnvironment
    $EffectiveEnvironment = $Endpoint.Environment
    # The Azure Resource Manager resource AzAuth is asked for, and the host the state records for the ARM
    # transport. The host without a trailing slash is the resource string the module has always sent to
    # AzAuth for the global cloud, so the Global call stays byte-identical.
    [string]$ArmResource = $Endpoint.ArmHost
    # -- Session match -----------------------------------------------------------
    # The same tenant AND the same cloud: another cloud is another session, so a switch signs in again.
    [bool]$SessionMatches = $SessionTenantMatches -and $StateEnvironment -eq $EffectiveEnvironment

    # -- Sign-in mode ------------------------------------------------------------
    # -DeviceCode is remembered in the auth state, so every later sign-in in the session uses it:
    # the renewal, the token-rejected retry and the ACRS step-up in Invoke-OPIMGraphRequest pass no
    # -DeviceCode. A cached token that is still valid stays in use; only the mode changes.
    # With no state, -DeviceCode creates one holding only DeviceCode until a sign-in succeeds. The
    # session and cache checks need TenantId and GraphTokenExpiry, so it never counts and a failed
    # first sign-in keeps the mode until Disconnect-OPIM. The Graph transport's retries sign in again
    # only for a state that records a tenant, and a latched command sends nothing.
    if ($DeviceCode) {
        if ($script:_OPIMAuthState) {
            $script:_OPIMAuthState.DeviceCode = $true
        } else {
            $script:_OPIMAuthState = @{ DeviceCode = $true }
        }
    }
    [bool]$UseDeviceCode = $DeviceCode -or ($script:_OPIMAuthState -and $script:_OPIMAuthState.DeviceCode)

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

    # -- Microsoft Graph sign-in (A16) --------------------------------------------
    # Microsoft Graph Command Line Tools: the first-party public client the module has always signed in
    # to Microsoft Graph as (A16, the template's default client). No app registration.
    [string]$GraphClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
    # All PIM surfaces in one prompt.
    [string[]]$GraphScopes = @(
        'RoleEligibilitySchedule.ReadWrite.Directory'
        'RoleAssignmentSchedule.ReadWrite.Directory'
        'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup'
        'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup'
        'AdministrativeUnit.Read.All'
        'User.Read'
    )
    # The Graph token audience of the session's cloud, with its trailing slash, as the table keeps it.
    [string]$GraphResource = $Endpoint.GraphResource
    [string]$EffectiveAuthorityHost = $Endpoint.AuthorityHost

    # Silent reuse of the ARM token: the same tenant and the same account as the session's Graph token,
    # more than 5 minutes left, and minted for the resource of the session's own cloud (OPIM-29). Written
    # once and read twice -- for the cached return below, on the state at entry, and in the ARM step, on
    # the state as a Graph sign-in left it -- so the two checks cannot drift apart. A session that
    # records no tenant or no account reuses nothing; the ARM step refuses it.
    function Test-OPIMArmReuse {
        ($script:_OPIMAuthState -is [System.Collections.IDictionary]) -and
            [bool]$script:_OPIMAuthState.TokenTenantId -and
            [bool]$script:_OPIMAuthState.ObjectId -and
            -not $ForceRefresh -and
            ($null -ne $script:_OPIMAuthState.ArmToken) -and
            $script:_OPIMAuthState.ArmTokenExpiry -gt $FiveMinutesFromNow -and
            [string]$script:_OPIMAuthState.ArmTokenTenantId -eq [string]$script:_OPIMAuthState.TokenTenantId -and
            [string]$script:_OPIMAuthState.ArmTokenObjectId -eq [string]$script:_OPIMAuthState.ObjectId -and
            [string]$script:_OPIMAuthState.ArmResourceUrl -eq $ArmResource
    }
    [bool]$ArmCached = -not $IncludeARM -or (Test-OPIMArmReuse)

    # Both tokens cached: the whole answer, BEFORE the AZURE_AUTHORITY_HOST block (R9), so a cached
    # session writes nothing, warns about nothing and records no authority.
    if ($GraphCached -and $ArmCached) {
        Write-Verbose "[Initialize-OPIMAuth] Returning cached auth state for tenant '$EffectiveTenant'."
        # SEC (EntraRBAC A19): a cache hit is a success; release the calling command's latch.
        Unlock-OPIMSignIn -Invocation $SignInCaller
        return
    }

    # SEC (EntraRBAC A17, BL-112): every device code token request carries -Force, the Microsoft Graph
    # and the Azure Resource Manager token alike. AzAuth keeps the device code credential it built and
    # reuses it for the next device code request, and a reused device code credential never returns
    # (decompiled in EntraRBAC, measured live there for a tenant switch); -Force makes AzAuth build a new
    # one, which prints a new code. Not a cache term: a device code session whose tokens are still valid
    # answered from the cached return above with no token request at all.
    [bool]$DeviceCodeForced = $UseDeviceCode
    # AzAuth keeps its credential in a static field and reuses it whatever the tenant or the authority,
    # and Azure.Identity bakes the authority in when it builds the credential, so -Force is the only way
    # to move it to another cloud (EntraRBAC). Seeded with the global authority, so a session that only
    # ever uses Global gains no -Force; never cleared by Disconnect-OPIM, since the credential outlives it.
    if (-not $script:_OPIMLastAuthorityHost) {
        $script:_OPIMLastAuthorityHost = (Get-OPIMCloudEndpoint -Environment 'Global').AuthorityHost
    }
    [bool]$AuthorityMoved = $EffectiveAuthorityHost -ne $script:_OPIMLastAuthorityHost

    # SEC (EntraRBAC BL-100): -NonInteractive declares that nobody can answer a prompt, so a sign-in in
    # the system browser is not started in such a host (a policy; whether a browser could be completed
    # there is not measured), and AzAuth would still open the browser from the token request. Refused
    # here, once, for every token request below -- Microsoft Graph, Azure and the silent renewal alike:
    # after the cached return (a session that needs no token is answered) and BEFORE the
    # AZURE_AUTHORITY_HOST block, the authority tracker and every token call, so nothing is requested or
    # written. The calling command stays latched, like every refusal. Device code mode is not affected.
    # Test-OPIMHostNonInteractive is the single owner of the host question.
    if (-not $UseDeviceCode -and (Test-OPIMHostNonInteractive)) {
        Write-CmdletError `
            -Message ([System.Exception]::new(
                "This PowerShell host was started with -NonInteractive, which declares that nobody can answer a " +
                "prompt, so Omnicit.PIM does not start a sign-in in the system browser here, and no token was " +
                "requested for tenant '$EffectiveTenant'. Sign in with a device code instead (Connect-OPIM -DeviceCode, " +
                "or -DeviceCode on Enable-OPIMMyRole and Disable-OPIMMyRole), or run the command in an interactive " +
                'PowerShell.')) `
            -ErrorId 'InteractiveSignInUnavailable' `
            -Category AuthenticationError `
            -TargetObject $EffectiveTenant `
            -Cmdlet $PSCmdlet `
            -Terminating
        return
    }

    # AzAuth's Get-AzToken has no authority parameter: Azure.Identity reads AZURE_AUTHORITY_HOST when it
    # builds the credential. Set ONCE around both token calls, only off Global, and put back in the
    # finally on every path -- every terminating error included -- so the process is never left pinned
    # to a sovereign authority (R9). Captured outside the try and NOT [string]: an absent variable is
    # $null, and the finally deletes it again rather than leaving ''.
    $PreviousAuthorityHost = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')
    [bool]$AuthorityHostOverridden = $false
    try {
        if ($EffectiveEnvironment -ne 'Global') {
            # The flag first: a pipeline stop between the two statements can then never leave the
            # variable set, and restoring a value that was not changed is harmless.
            $AuthorityHostOverridden = $true
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $EffectiveAuthorityHost)
        } elseif ($PreviousAuthorityHost -and
            $PreviousAuthorityHost.TrimEnd('/') -ne $EffectiveAuthorityHost.TrimEnd('/')) {
            # Global writes nothing; an operator's own value is followed by Azure.Identity, so say so.
            Write-Warning ("AZURE_AUTHORITY_HOST is set to '$PreviousAuthorityHost' in this process, which is not the " +
                "global cloud's authority '$EffectiveAuthorityHost'. The Microsoft Entra ID sign-in follows that variable, " +
                'for Microsoft Graph and for Azure, so this Global sign-in goes to that authority instead. Omnicit.PIM ' +
                'does not change the variable for the Global cloud. Clear it with Remove-Item Env:AZURE_AUTHORITY_HOST, ' +
                'or use -Environment for a sovereign cloud.')
        }
        # Recorded HERE, before any credential can be built (EntraRBAC): Get-AzToken builds the
        # credential and THEN asks for the token, so a sovereign attempt that fails still leaves AzAuth's
        # credential at the new authority, and the next sign-in elsewhere must pass -Force.
        $script:_OPIMLastAuthorityHost = $EffectiveAuthorityHost

        if (-not $GraphCached) {
            # The tenant every token must be issued for: the GUID asked for, else the session's recorded
            # tenant. A first sign-in under 'organizations' or a new domain has none to compare with
            # yet; its token's tid becomes the session's tenant.
            [string]$ExpectedTenant = if ($EffectiveIsGuid) {
                $ParsedTenant.ToString('D')
            } elseif ($SessionMatches -and $script:_OPIMAuthState.TokenTenantId) {
                [string]$script:_OPIMAuthState.TokenTenantId
            } else {
                ''
            }

            Write-Verbose "[Initialize-OPIMAuth] Acquiring Graph token for tenant '$EffectiveTenant' (cloud '$EffectiveEnvironment'). ClaimsChallenge=$(if ($ClaimsChallenge) { 'YES' } else { 'NO' })"

            # TimeoutSeconds: AzAuth stops waiting for the sign-in after 120 seconds by default, much
            # less than a device code lives (15 minutes), so the sign-in waits as long as the code can
            # be used (R5). 'organizations' names no tenant: AzAuth then signs in the account's home
            # tenant.
            $GraphTokenParams = @{
                Resource       = $GraphResource
                Scope          = $GraphScopes
                ClientId       = $GraphClientId
                TimeoutSeconds = 900
                ErrorAction    = 'Stop'
            }
            if ($EffectiveTenant -ne 'organizations') { $GraphTokenParams.Tenant = $EffectiveTenant }
            if ($ClaimsChallenge) { $GraphTokenParams.Claim = $ClaimsChallenge }
            # Never the system browser in device code mode: a session that asked for a device code has
            # no browser to open.
            if ($UseDeviceCode) { $GraphTokenParams.DeviceCode = $true } else { $GraphTokenParams.Interactive = $true }
            # ORed, not overwritten: each reason is its own term (R8).
            if ($ForceRefresh -or $DeviceCodeForced -or $AuthorityMoved) { $GraphTokenParams.Force = $true }

            # SEC (EntraRBAC A22, BL-115): renew a system-browser session without a prompt where AzAuth
            # can answer from the interactive credential it holds; see Invoke-OPIMSilentRenewal for the
            # evidence and for what it cannot promise. Evaluated HERE, directly before the call it may
            # replace. Every term on its own line. Two are implied by others and kept so the rule reads
            # here (deleting either changes nothing a test can see): the system browser, by "no -Force"
            # (device code mode always passes -Force), and "the tracker exists", by the -ceq terms.
            #   - the system browser: a device code session never takes this path.
            #   - a renewal: the state is a dictionary and the request is for the session's own tenant
            #     and cloud ($SessionMatches); a first sign-in has nothing to renew and no account to
            #     compare a token with.
            #   - no claims challenge: an ACRS step-up needs the user to answer the challenge.
            #   - no -Force (-ForceRefresh, a device code, a moved authority): -Force clears the
            #     credential AzAuth holds, which the silent request depends on.
            #   - the tracker names the client id and the tenant the interactive request below would
            #     pass, compared ordinally: a credential another request built (the Azure one, another
            #     tenant) is not the one this request would use.
            #   - the session's account and token tenant are GUIDs, so the identity check has something
            #     to compare with.
            $GraphResult = $null
            [bool]$SilentGraph = -not $UseDeviceCode -and
                ($script:_OPIMAuthState -is [System.Collections.IDictionary]) -and
                $SessionMatches -and
                -not $ClaimsChallenge -and
                -not $GraphTokenParams.ContainsKey('Force') -and
                $script:_OPIMInteractiveCredential -and
                $script:_OPIMInteractiveCredential.ClientId -ceq [string]$GraphTokenParams.ClientId -and
                $script:_OPIMInteractiveCredential.Tenant -ceq [string]$GraphTokenParams.Tenant -and
                (Test-OPIMGuidText -Value $script:_OPIMAuthState.ObjectId) -and
                (Test-OPIMGuidText -Value $script:_OPIMAuthState.TokenTenantId)
            if ($SilentGraph) {
                # The interactive request without -Interactive and -ClientId (refused at run time in AzAuth's
                # NonInteractive parameter set); Resource, Scope, Tenant and TimeoutSeconds as before.
                # CredentialPrecedence Environment: the one allowed source that sends nothing unless
                # AZURE_* variables are set.
                $SilentGraphParams = $GraphTokenParams.Clone()
                $SilentGraphParams.Remove('Interactive')
                $SilentGraphParams.Remove('ClientId')
                $SilentGraphParams.CredentialPrecedence = @('Environment')
                $GraphResult = Invoke-OPIMSilentRenewal -SilentParameter $SilentGraphParams
            }
            if ($null -eq $GraphResult) {
                # SEC (A22): the tracker is cleared directly before every token request but the silent
                # one -- AzAuth's credential is replaced by it -- and set again only after a request in
                # the system browser returned. A request that throws leaves it cleared, so the next
                # renewal is interactive.
                $script:_OPIMInteractiveCredential = $null
                try {
                    $GraphResult = Invoke-OPIMAzTokenCall -TokenParameter $GraphTokenParams -DeviceCodeFlow:$UseDeviceCode
                } catch {
                    Remove-OPIMErrorRecord -Record $PSItem
                    # R6: the module's own ids -- DeviceCodeAuthFailed in device code mode,
                    # InteractiveAuthFailed in the system browser. Terminating, and the calling command stays
                    # latched (EntraRBAC A19). AzAuth's message only: no inner exception, and the tenant
                    # asked for as the target object.
                    [string]$GraphFailureId = if ($UseDeviceCode) { 'DeviceCodeAuthFailed' } else { 'InteractiveAuthFailed' }
                    [string]$GraphFailurePrefix = if ($UseDeviceCode) { 'Device code authentication failed' } else { 'Interactive authentication failed' }
                    [string]$GraphFailure = if (Test-OPIMAzAuthMissing -Record $PSItem) {
                        "${GraphFailurePrefix}: the AzAuth module is not installed or could not be loaded. Install AzAuth 2.11.0 or later from the PowerShell Gallery; it needs PowerShell 7.4 or later."
                    } elseif ($UseDeviceCode) {
                        "${GraphFailurePrefix}: $($PSItem.Exception.Message) A device code expires after about 15 minutes; run the command again for a new code."
                    } else {
                        "${GraphFailurePrefix}: $($PSItem.Exception.Message). On headless systems (Linux without a display server) " +
                        'the system browser cannot be launched. Run this command on a desktop system.'
                    }
                    Write-CmdletError `
                        -Message ([System.Exception]::new($GraphFailure)) `
                        -ErrorId $GraphFailureId `
                        -Category AuthenticationError `
                        -TargetObject $EffectiveTenant `
                        -Cmdlet $PSCmdlet `
                        -Terminating
                    return
                }
                # SEC (A22): AzAuth now holds the interactive credential this request built, for this client
                # id and tenant. A device code request replaced the stored credential and records nothing.
                if (-not $UseDeviceCode) {
                    $script:_OPIMInteractiveCredential = @{
                        ClientId = [string]$GraphTokenParams.ClientId
                        Tenant   = [string]$GraphTokenParams.Tenant
                    }
                }
            }
            if (-not $GraphResult -or -not $GraphResult.Token) {
                Write-CmdletError `
                    -Message ([System.Exception]::new('Authentication completed but no access token was returned.')) `
                    -ErrorId 'NoAccessToken' `
                    -Category AuthenticationError `
                    -Cmdlet $PSCmdlet `
                    -Terminating
                return
            }

            # The plaintext token reaches .NET only. Every command below receives this SecureString:
            # module logging (LogPipelineExecutionDetails) records every value bound to a command
            # parameter, so a bound string would put the bearer token in the event log. NetworkCredential
            # converts it without ConvertTo-SecureString -AsPlainText (PSSA rule
            # PSAvoidUsingConvertToSecureStringWithPlainText).
            $SecureToken = [System.Net.NetworkCredential]::new('', $GraphResult.Token).SecurePassword
            $GraphTokenExpiry = ConvertTo-OPIMUtcDateTime -Value $GraphResult.ExpiresOn
            # R14: the account is the Identity AzAuth reports for the sign-in.
            [string]$GraphAccount = [string]$GraphResult.Identity
            $GraphResult = $null

            # -- Tenant check (OPIM-07) -----------------------------------------
            # After EVERY token, compare its tid with the tenant asked for. A difference is
            # TenantMismatch, raised before the token reaches Connect-MgGraph or the auth state. R10:
            # the tid is the token's own claim, never AzToken.TenantId, which AzAuth can echo from the
            # request.
            [string]$TokenTenant = Get-OPIMTokenTenantId -AccessToken $SecureToken
            if (-not $TokenTenant) {
                # SEC (A22): AzAuth's credential just answered for another tenant or account, so no silent
                # renewal is tried from it; the next sign-in is interactive.
                $script:_OPIMInteractiveCredential = $null
                Write-CmdletError -ErrorRecord (New-OPIMTenantMismatchError -RequestedTenant $EffectiveTenant -Unreadable) -Cmdlet $PSCmdlet -Terminating
                return
            }
            if ($ExpectedTenant -and $TokenTenant -ne $ExpectedTenant) {
                # SEC (A22): AzAuth's credential just answered for another tenant or account, so no silent
                # renewal is tried from it; the next sign-in is interactive.
                $script:_OPIMInteractiveCredential = $null
                Write-CmdletError -ErrorRecord (New-OPIMTenantMismatchError -RequestedTenant $EffectiveTenant) -Cmdlet $PSCmdlet -Terminating
                return
            }

            Write-Verbose "[Initialize-OPIMAuth] Graph token acquired. Account: $GraphAccount. Expiry (UTC): $GraphTokenExpiry."

            # -- Account check (EntraRBAC BL-119) -------------------------------
            # A sign-in that CONTINUES the session never makes it another account's. Without this, a
            # renewal near the expiry, the token-rejected retry or a step-up could be answered in the
            # browser by another account of the same tenant, and every command after it -- the one that
            # asked included -- would activate and deactivate as that account under the session the
            # user began. A continuation is a new Graph token issued for the tenant the session's Graph
            # token was (both tids, so a domain against its tenant ID, or any label after a first
            # sign-in under 'organizations', counts) in the session's cloud; the client is always the
            # same and the sign-in mode is the session's. Switching account is Disconnect-OPIM's. Both
            # oids must be GUIDs: a token without one, on either side, proves nothing and never refuses.
            # Placed after the tenant check and before Connect-MgGraph: the token is not used, and the
            # state, the Graph SDK session and the cached ARM token stay as they were. Each term on its
            # own line; the GUID test of the state's TokenTenantId is implied by its equality with the
            # new token's tid (Get-OPIMTokenTenantId returns only a GUID) and kept so the rule reads here.
            [string]$GraphObjectId = Get-OPIMTokenObjectId -AccessToken $SecureToken
            $PreviousState = $script:_OPIMAuthState
            [bool]$ContinuesSession = ($PreviousState -is [System.Collections.IDictionary]) -and
                (Test-OPIMGuidText -Value $PreviousState['TokenTenantId']) -and
                [string]$PreviousState['TokenTenantId'] -eq $TokenTenant -and
                $StateEnvironment -eq $EffectiveEnvironment
            [bool]$AccountChanged = $ContinuesSession -and
                (Test-OPIMGuidText -Value $GraphObjectId) -and
                (Test-OPIMGuidText -Value $PreviousState['ObjectId']) -and
                $GraphObjectId -ne [string]$PreviousState['ObjectId']
            if ($AccountChanged) {
                # Terminating, and the calling command stays latched (EntraRBAC A19), as for every
                # refusal. The SecureString is dropped first.
                $SecureToken = $null
                # SEC (A22): AzAuth's credential just answered for another tenant or account, so no silent
                # renewal is tried from it; the next sign-in is interactive.
                $script:_OPIMInteractiveCredential = $null
                Write-CmdletError -ErrorRecord (New-OPIMAccountMismatchError -RequestedTenant $EffectiveTenant -Source Graph) -Cmdlet $PSCmdlet -Terminating
                return
            }

            # -- Wire Graph token into Connect-MgGraph -------------------------
            # The same SecureString as the tenant check. A failure is scrubbed first, as on every
            # transport path, and still ends this function, before the auth state is written.
            # Global passes no -Environment at all, so the public call stays the one the module always
            # made; any other cloud names the Graph SDK's environment from the table (EntraRBAC).
            $ConnectParams = @{ AccessToken = $SecureToken; NoWelcome = $true; ErrorAction = 'Stop' }
            if ($EffectiveEnvironment -ne 'Global') { $ConnectParams.Environment = $Endpoint.GraphEnvironment }
            try {
                Connect-MgGraph @ConnectParams
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.ThrowTerminatingError($PSItem)
            }
            # OPIM-09: the session this Connect-MgGraph left, read straight after it. Recorded even when
            # it is $null, so the key says the module connected; Get-OPIMGraphSessionState compares
            # every later session with it.
            $GraphSessionFingerprint = Get-OPIMGraphSessionFingerprint

            # -- Cache auth state -----------------------------------------------
            # TenantId is the label the session is pinned to: as requested, or the token's tid after a
            # first sign-in under 'organizations'. TokenTenantId is the tid of the current Graph token;
            # GraphSessionFingerprint is the Graph SDK session the module connected (it holds no token).
            # ObjectId is the oid of the Graph token, the account every ARM token must be issued to. The
            # state holds no Graph token, and the ARM token only as a SecureString (A6), with its expiry,
            # tenant, account and resource.
            # A3: the Graph token's own object id ($GraphObjectId, read by the account check above),
            # compared with every ARM token's oid. SEC (EntraRBAC BL-119, D2): a continuation whose new
            # token carries no readable oid never replaces the session's account -- it is carried over,
            # so the next continuation is still compared with the known account instead of with
            # nothing. Any other sign-in records its own token's oid, or none.
            $NewObjectId = if ($GraphObjectId) {
                $GraphObjectId
            } elseif ($ContinuesSession -and (Test-OPIMGuidText -Value $PreviousState['ObjectId'])) {
                [string]$PreviousState['ObjectId']
            } else {
                $null
            }
            # SEC (A3): an ARM token survives a new Graph token only when it was issued for the same
            # tenant and the same account; otherwise it is dropped, never carried, and -IncludeARM
            # acquires a new one. OPIM-29: and only in the same cloud -- a token minted in another cloud
            # is never carried.
            [bool]$KeepArmToken = ($PreviousState -is [System.Collections.IDictionary]) -and
                ($null -ne $PreviousState['ArmToken']) -and
                [bool]$GraphObjectId -and
                $StateEnvironment -eq $EffectiveEnvironment -and
                [string]$PreviousState['ArmTokenTenantId'] -eq $TokenTenant -and
                [string]$PreviousState['ArmTokenObjectId'] -eq $GraphObjectId
            $script:_OPIMAuthState = @{
                TenantId                = if ($EffectiveTenant -eq 'organizations') { $TokenTenant } else { $EffectiveTenant }
                TokenTenantId           = $TokenTenant
                Environment             = $EffectiveEnvironment
                Account                 = $GraphAccount
                ObjectId                = $NewObjectId
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

            # The move of the authority is done: AzAuth built its credential at this cloud's authority
            # for the Graph request, so the ARM request after it keeps -Force only for -ForceRefresh or a
            # device code (EntraRBAC). Reset HERE, inside the Graph branch, and nowhere else: an ARM-only
            # request after a failed sovereign attempt still needs it.
            $AuthorityMoved = $false
        }

        # -- Azure Resource Manager token (when requested) -----------------------
        # A2/A6: Azure is signed in by AzAuth, separately from Graph, for the tenant of the session's
        # Graph token, interactively or with a device code by the session's mode. The token is kept as a
        # SecureString in the auth state and never written to disk; Invoke-OPIMArmRequest sends it.
        if ($IncludeARM) {
            [string]$ArmTenant = [string]$script:_OPIMAuthState.TokenTenantId
            if (-not $ArmTenant) {
                # Cannot happen for a state this module built. Refused rather than signed in without a
                # tenant.
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

            # The reuse check again, on the state as it stands now: a Graph sign-in above may have
            # dropped the ARM token or kept it.
            if (-not (Test-OPIMArmReuse)) {
                # TimeoutSeconds: as for the Graph sign-in, the sign-in waits as long as a device code
                # can be used.
                $ArmTokenParams = @{ Resource = $ArmResource; Tenant = $ArmTenant; TimeoutSeconds = 900; ErrorAction = 'Stop' }
                if ($UseDeviceCode) { $ArmTokenParams.DeviceCode = $true } else { $ArmTokenParams.Interactive = $true }
                # R8: the same three reasons as the Graph request; after a Graph sign-in the move of the
                # authority is already done.
                if ($ForceRefresh -or $DeviceCodeForced -or $AuthorityMoved) { $ArmTokenParams.Force = $true }

                # SEC (EntraRBAC A22, BL-115): the same silent renewal for the Azure Resource Manager token,
                # with the same terms as the Microsoft Graph one, each on its own line. The difference is
                # the client id the interactive request would pass: none, so the tracker must name the
                # empty client id -- the Azure credential, not the Graph one an interactive Graph request
                # just above this made AzAuth hold. Evaluated here, after that request, for exactly that
                # reason. The account and tenant are the state's as they stand now: after a Graph sign-in
                # above they are the new Graph token's, which the account check held to the same account.
                $ArmResult = $null
                [bool]$SilentArm = -not $UseDeviceCode -and
                    ($script:_OPIMAuthState -is [System.Collections.IDictionary]) -and
                    $SessionMatches -and
                    -not $ClaimsChallenge -and
                    -not $ArmTokenParams.ContainsKey('Force') -and
                    $script:_OPIMInteractiveCredential -and
                    $script:_OPIMInteractiveCredential.ClientId -ceq [string]$ArmTokenParams.ClientId -and
                    $script:_OPIMInteractiveCredential.Tenant -ceq [string]$ArmTokenParams.Tenant -and
                    (Test-OPIMGuidText -Value $script:_OPIMAuthState.ObjectId) -and
                    (Test-OPIMGuidText -Value $script:_OPIMAuthState.TokenTenantId)
                if ($SilentArm) {
                    # No Remove('ClientId'): the Azure request carries none.
                    $SilentArmParams = $ArmTokenParams.Clone()
                    $SilentArmParams.Remove('Interactive')
                    $SilentArmParams.CredentialPrecedence = @('Environment')
                    $ArmResult = Invoke-OPIMSilentRenewal -SilentParameter $SilentArmParams
                }
                if ($null -eq $ArmResult) {
                    # SEC (A22): cleared before every token request but the silent one, set again only
                    # after a request in the system browser returned; see the Graph request above.
                    $script:_OPIMInteractiveCredential = $null
                    try {
                        $ArmResult = Invoke-OPIMAzTokenCall -TokenParameter $ArmTokenParams -DeviceCodeFlow:$UseDeviceCode
                    } catch {
                        Remove-OPIMErrorRecord -Record $PSItem
                        # Terminating, and the calling command stays latched (EntraRBAC A19), so its ARM
                        # requests are refused with SignInRefused. The AzAuth message only: no inner
                        # exception, and the session tenant as the target object. A Get-AzToken that cannot be
                        # found at all means AzAuth is missing, or did not load, and the message says so.
                        $AzureFailure = if (Test-OPIMAzAuthMissing -Record $PSItem) {
                            'Azure connection failed: the AzAuth module is not installed or could not be loaded. Install AzAuth 2.11.0 or later from the PowerShell Gallery; it needs PowerShell 7.4 or later.'
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
                    # SEC (A22): AzAuth now holds the interactive credential this request built: no client
                    # id (the Azure request names none) and the session tenant.
                    if (-not $UseDeviceCode) {
                        $script:_OPIMInteractiveCredential = @{
                            ClientId = [string]$ArmTokenParams.ClientId
                            Tenant   = [string]$ArmTokenParams.Tenant
                        }
                    }
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
                # session. Refused before it reaches the auth state, so no ARM request ever carries it.
                # The account is read only once the tenant matched.
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
                    # answered for another tenant or account, so no earlier ARM token outlives the refusal
                    # and the next -IncludeARM sign-in asks AzAuth again.
                    foreach ($ArmKey in 'ArmToken', 'ArmTokenExpiry', 'ArmTokenTenantId', 'ArmTokenObjectId', 'ArmResourceUrl') {
                        $script:_OPIMAuthState[$ArmKey] = $null
                    }
                    # SEC (A22): AzAuth's credential just answered for another tenant or account, so no silent
                    # renewal is tried from it; the next sign-in is interactive.
                    $script:_OPIMInteractiveCredential = $null
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

        # SEC (EntraRBAC A19): the new sign-in went the whole way -- Graph connected or cached, and the
        # ARM token acquired or reused, or not asked for -- so release the calling command's latch. The
        # last statement of the try and not in the finally: every refusal and terminating error above
        # must leave the command latched.
        Unlock-OPIMSignIn -Invocation $SignInCaller
    } finally {
        # [NullString]::Value, not $null: PowerShell binds $null to a string parameter as '', and
        # SetEnvironmentVariable with '' leaves the variable in existence (measured in EntraRBAC and here
        # on Windows, PowerShell 7.6: Test-Path Env: still finds it).
        if ($AuthorityHostOverridden) {
            if ($null -eq $PreviousAuthorityHost) {
                [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
            } else {
                [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $PreviousAuthorityHost)
            }
        }
    }
}
