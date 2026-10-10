function Connect-OPIM {
    <#
    .SYNOPSIS
    Authenticate to Microsoft Graph (and optionally Azure) for Omnicit.PIM.

    .DESCRIPTION
    Pre-authenticates the session before running Get-/Enable-/Disable-OPIM* cmdlets.
    All PIM cmdlets sign in automatically on first use, so running Connect-OPIM explicitly
    is optional -- use it when you want to control when the sign-in prompt appears.

    One Microsoft Graph sign-in covers directory roles and Entra ID groups. WAM is never used: the
    Graph sign-in goes through the system browser, which works identically on Windows, macOS, and
    Linux, or, with -DeviceCode, through a device code for a machine without a browser. Azure RBAC
    signs in separately, through AzAuth's Get-AzToken, for the tenant of the Graph session: with
    -IncludeARM here, or when an Azure role cmdlet first needs it. It opens its own browser window
    or, in device code mode, shows its own code. Its token must be issued for the tenant and the
    account of the Graph sign-in (TenantMismatch, AccountMismatch otherwise), and Omnicit.PIM sends
    every Azure request itself with it: no Az context and no subscription choice are involved.

    The session state is cached in memory. Subsequent calls are idempotent -- if a valid token
    already exists for the same tenant no sign-in prompt is shown.

    Disconnect-OPIM clears the module's tokens, the Azure Resource Manager token included, and
    disconnects the Microsoft Graph session; AzAuth keeps its own sign-in in the PowerShell process
    until the module's next Azure sign-in rebuilds it or the process ends.

    .EXAMPLE
    Connect-OPIM -TenantId 'contoso.onmicrosoft.com'
    Sign in to Microsoft Graph for the Contoso tenant and cache the token (directory roles and
    Entra ID groups).

    .EXAMPLE
    Connect-OPIM -TenantAlias corp
    Resolve the 'corp' alias from TenantMap.psd1 and authenticate.

    .EXAMPLE
    Connect-OPIM -TenantAlias corp -Environment China
    Sign in to the tenant of the 'corp' alias in the China cloud, whatever cloud the alias stores.

    .EXAMPLE
    Connect-OPIM -TenantAlias corp -IncludeARM
    Authenticate and also sign in to Azure Resource Manager, for the Azure role cmdlets.

    .EXAMPLE
    Connect-OPIM -TenantId 'contoso.onmicrosoft.com' -DeviceCode -IncludeARM
    Sign in with device codes instead of the system browser, for example in a remote session. The
    command shows a code and the address to open; open the address on any device and enter the
    code. With -IncludeARM, Azure shows a second code.

    .EXAMPLE
    Connect-OPIM -TenantId 'contoso.onmicrosoft.us' -Environment USGov
    Sign in to the Contoso tenant in the US Government (GCC High) cloud, where the initial domain of
    a tenant ends in .onmicrosoft.us. Later commands for that tenant keep the cloud until
    Disconnect-OPIM, a call for another tenant, or a call that names another cloud.

    .PARAMETER TenantAlias
    Short alias for the target tenant, resolved from the TenantMap.psd1 managed by
    Install-OPIMConfiguration. Mutually exclusive with -TenantId.

    .PARAMETER TenantId
    The Entra ID tenant GUID or verified domain name, e.g. 'contoso.onmicrosoft.com'.
    Mutually exclusive with -TenantAlias.

    .PARAMETER IncludeARM
    Also sign in to Azure Resource Manager, through AzAuth's Get-AzToken, for the tenant and the
    account of the Microsoft Graph session. The session's Azure token is reused when it was issued
    for that tenant and the same account and has more than 5 minutes left. Optional: without it,
    Get-/Enable-/Disable-OPIMAzureRole sign in to Azure on first use; use it to have the Azure
    prompt appear now.

    .PARAMETER TenantMapPath
    Path to TenantMap.psd1. Defaults to .config/Omnicit.PIM/TenantMap.psd1 under your home
    folder ($HOME; on Windows the same file as before, under $env:USERPROFILE).

    .PARAMETER DeviceCode
    Sign in with a device code instead of the system browser, for a machine without one, such as a
    remote session or a cloud PC. The sign-in message with the code and the address is written to
    the Information stream with the tag OPIMDeviceCode and shown whatever the information preference
    is. With -IncludeARM, Azure shows a second code: AzAuth hands it over as a warning, which
    Omnicit.PIM writes on the Information stream instead, with the same tag, so it is shown even
    where warnings are silenced. A script reads both as they arrive by merging the Information
    stream into a pipeline, for example 6>&1 | ForEach-Object { $PSItem.ToString() }; capturing
    the output in a variable shows nothing until the flow ends, which can take 15 minutes. The mode
    is remembered for this PowerShell session: the refresh stays silent while it can, and any later
    sign-in that needs a prompt, a step-up included, uses a device code until Disconnect-OPIM.

    .PARAMETER Environment
    The cloud to sign in to: 'Global', 'USGov' (US Government, GCC High), 'USGovDoD' (US Government,
    DoD) or 'China', in any letter case. Microsoft 365 GCC is a commercial-cloud tenant and is
    'Global'. The cloud follows the tenant: without -Environment, a call for the tenant the session
    is signed in to keeps the session's cloud, and any other tenant is 'Global'. Naming a cloud other
    than the session's signs in again, also for the same tenant. The session keeps its cloud for
    that tenant until Disconnect-OPIM, a call for another tenant, or a call that names another cloud.

    A tenant alias (-TenantAlias) signs in to the cloud it stores in the tenant map (see
    Install-OPIMConfiguration -Environment and Set-OPIMConfiguration -Environment), and to 'Global'
    when it stores none, whatever cloud the session is in. -Environment overrides the cloud of the
    alias. A cloud stored in the file that Omnicit.PIM does not know is refused with an error
    before anything is signed in, unless -Environment names the cloud.
    #>
    [Alias('Connect-PIM')]
    [CmdletBinding(DefaultParameterSetName = 'ByTenantId')]
    [OutputType([void])]
    param(
        [Parameter(ParameterSetName = 'ByAlias', Mandatory)]
        [string]$TenantAlias,

        [Parameter(ParameterSetName = 'ByTenantId')]
        [string]$TenantId,

        [switch]$IncludeARM,

        [string]$TenantMapPath = (Join-Path $HOME '.config/Omnicit.PIM/TenantMap.psd1'),

        [switch]$DeviceCode,

        [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
        [string]$Environment
    )

    # -- Resolve TenantAlias -> TenantId ----------------------------------------
    $AliasEnvironment = $null
    if ($TenantAlias) {
        if (-not (Test-Path $TenantMapPath)) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "TenantMap file not found at '$TenantMapPath'. " +
                    'Run: Install-OPIMConfiguration -TenantAlias <alias> -TenantId <guid>')) `
                -ErrorId 'TenantMapNotFound' `
                -Category ObjectNotFound `
                -TargetObject $TenantMapPath `
                -Cmdlet $PSCmdlet
            return
        }
        $Map    = Import-PowerShellDataFile $TenantMapPath
        $Config = $Map[$TenantAlias]
        if (-not $Config) {
            $Available = ($Map.Keys | Sort-Object) -join ', '
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Tenant alias '$TenantAlias' not found in '$TenantMapPath'. Available aliases: $Available")) `
                -ErrorId 'TenantAliasNotFound' `
                -Category ObjectNotFound `
                -TargetObject $TenantAlias `
                -Cmdlet $PSCmdlet
            return
        }
        $TenantId = if ($Config -is [hashtable]) { $Config.TenantId } else { [string]$Config }

        # A12: a tenant alias signs in to the cloud it stores, unless -Environment names one. An unknown
        # stored cloud is refused before anything is signed in.
        if (-not $Environment) {
            try {
                $AliasEnvironment = Get-OPIMTenantMapEnvironment -Entry $Config -TenantAlias $TenantAlias -TenantMapPath $TenantMapPath -ErrorAction Stop
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }
    }

    $AuthParams = @{ TenantId = $TenantId; IncludeARM = $IncludeARM; DeviceCode = $DeviceCode }
    # The cloud the caller named, else the cloud of the alias, else none: without one,
    # Initialize-OPIMAuth keeps the session's cloud for the session's tenant (OPIM-29). An alias always
    # names one (Global when it stores none), so it never inherits the cloud of a session in another
    # tenant. $Environment itself is not assigned: it carries the ValidateSet.
    if ($Environment) {
        $AuthParams.Environment = $Environment
    } elseif ($AliasEnvironment) {
        $AuthParams.Environment = $AliasEnvironment
    }
    Initialize-OPIMAuth @AuthParams
}
