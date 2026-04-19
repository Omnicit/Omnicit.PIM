function Get-OPIMMsalApplication {
    <#
    .SYNOPSIS
    Returns a cached MSAL PublicClientApplication built from the Microsoft.Identity.Client
    assembly that is already loaded by the Microsoft.Graph.Authentication module.

    .DESCRIPTION
    Constructs an IPublicClientApplication via reflection (the MSAL types live in a separate
    Assembly Load Context owned by the Graph SDK and are not directly accessible from the default
    ALC). The application is cached in $script:_OPIMMsalApp for the lifetime of the session and
    is only rebuilt when the target tenant changes.

    No Add-Type or path-pinning is used: the assembly is located through
    [System.Runtime.Loader.AssemblyLoadContext]::All after ensuring that
    Microsoft.Graph.Authentication has been imported (which loads MSAL into the Graph SDK's
    custom ALC). Any version 4.x or 5.x of Microsoft.Identity.Client is accepted.

    .PARAMETER TenantId
    The Entra ID tenant ID (GUID or domain name) for which to build the authority URI. Defaults
    to 'organizations' for multi-tenant-capable accounts. The cached app is rebuilt whenever this
    value differs from the previously cached value.

    .OUTPUTS
    The IPublicClientApplication instance (opaque object via reflection).

    .EXAMPLE
    $MsalApp = Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com'
    #>
    [OutputType([object])]
    param(
        [string]$TenantId = 'organizations'
    )

    # Return cached instance when tenant has not changed.
    if ($script:_OPIMMsalApp -and $script:_OPIMMsalAppTenantId -eq $TenantId) {
        Write-Verbose "[Get-OPIMMsalApplication] Returning cached MSAL app for tenant '$TenantId'."
        return $script:_OPIMMsalApp
    }

    Write-Verbose "[Get-OPIMMsalApplication] Building new MSAL PublicClientApplication for tenant '$TenantId'."

    # Force-load the Graph.Authentication module assemblies (no-op if already loaded).
    # This is intentionally a throwaway call; Get-MgContext returns $null when not connected
    # and that is fine — we only need its side-effect of loading Microsoft.Identity.Client into
    # the process (in the Graph SDK's custom ALC) before we scan all ALCs below.
    $null = Get-MgContext -ErrorAction SilentlyContinue

    # Locate MSAL assembly. The Graph SDK loads it into a private AssemblyLoadContext (ALC)
    # that is NOT always enumerable — the ALC is only registered after Connect-MgGraph has been
    # called at least once in the session, bootstrapping token acquisition. On the very first
    # call (before any auth), [AssemblyLoadContext]::All won't see it.
    #
    # Two-pass strategy:
    #   Pass 1 — scan all registered ALCs (fast; works once Graph SDK has loaded MSAL)
    #   Pass 2 — load from Microsoft.Graph.Authentication's bundled copy via LoadFile
    #            into the default ALC (works on first call before any auth has occurred)
    $MsalAssembly = try {
        [System.Runtime.Loader.AssemblyLoadContext]::All |
            ForEach-Object { try { $_.Assemblies } catch { $null = $PSItem } } |
            Where-Object { $_.FullName -match '^Microsoft\.Identity\.Client, Version=[45]' } |
            Select-Object -First 1
    } catch { $null = $PSItem }

    if (-not $MsalAssembly) {
        $GraphModule = Get-Module 'Microsoft.Graph.Authentication' -ErrorAction SilentlyContinue
        if ($GraphModule) {
            $MsalDll = Get-ChildItem -Path (Split-Path $GraphModule.Path -Parent) `
                -Recurse -Filter 'Microsoft.Identity.Client.dll' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq 'Microsoft.Identity.Client.dll' } |
                Select-Object -First 1
            if ($MsalDll) {
                Write-Verbose "[Get-OPIMMsalApplication] Loading MSAL from Graph module path: $($MsalDll.FullName)"
                $MsalAssembly = [System.Reflection.Assembly]::LoadFile($MsalDll.FullName)
            }
        }
    }

    if (-not $MsalAssembly) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    'Microsoft.Identity.Client assembly not found. ' +
                    'Ensure Microsoft.Graph.Authentication >= 2.36.0 is installed: ' +
                    'Install-Module Microsoft.Graph.Authentication -MinimumVersion 2.36.0'),
                'MsalAssemblyNotFound',
                [System.Management.Automation.ErrorCategory]::NotInstalled, $null))
    }

    Write-Verbose "[Get-OPIMMsalApplication] Located MSAL assembly: $($MsalAssembly.FullName)"

    # --- Build the PublicClientApplication via reflection ---
    # Client ID: Microsoft Graph Command Line Tools (public, no app registration required)
    [string]$ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
    [string]$Authority = "https://login.microsoftonline.com/$TenantId"

    $BuilderType = $MsalAssembly.GetType('Microsoft.Identity.Client.PublicClientApplicationBuilder')
    if (-not $BuilderType) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    'Microsoft.Identity.Client.PublicClientApplicationBuilder type not found in MSAL assembly. ' +
                    'The installed version may be incompatible.'),
                'MsalBuilderTypeNotFound',
                [System.Management.Automation.ErrorCategory]::NotInstalled, $null))
    }

    # PublicClientApplicationBuilder.Create(string clientId) — static factory.
    # Use GetMethods() name-search instead of GetMethod(name,[Type[]]) to avoid cross-ALC type-
    # identity failures where [string] from the default ALC may not satisfy an overload-resolution
    # check on types loaded in a different AssemblyLoadContext.
    $CreateMethod = $BuilderType.GetMethods(
        [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static) |
        Where-Object { $_.Name -eq 'Create' -and ($_.GetParameters()).Count -eq 1 } |
        Select-Object -First 1
    $Builder = $CreateMethod.Invoke($null, @($ClientId))

    # .WithAuthority — resolve on the runtime type of $Builder so the full inheritance chain
    # (including generic base AbstractApplicationBuilder<T>) is traversed inside the correct ALC.
    # Prefer the single-string overload (MSAL 4.60+). If only (string, bool) is present, pass $true.
    $WithAuthorityMethod = $Builder.GetType().GetMethods() |
        Where-Object {
            $_.Name -eq 'WithAuthority' -and
            ($_.GetParameters()).Count -ge 1 -and
            ($_.GetParameters())[0].ParameterType.Name -eq 'String'
        } |
        Sort-Object { ($_.GetParameters()).Count } |
        Select-Object -First 1
    $Builder = if (($WithAuthorityMethod.GetParameters()).Count -eq 1) {
        $WithAuthorityMethod.Invoke($Builder, @($Authority))
    } else {
        $WithAuthorityMethod.Invoke($Builder, @($Authority, $true))
    }

    # .WithRedirectUri(string) — http://localhost activates the system browser (no WAM required)
    $WithRedirectMethod = $Builder.GetType().GetMethods() |
        Where-Object { $_.Name -eq 'WithRedirectUri' -and ($_.GetParameters()).Count -eq 1 } |
        Select-Object -First 1
    $Builder = $WithRedirectMethod.Invoke($Builder, @('http://localhost'))

    # .Build() — construct the final IPublicClientApplication
    $MsalApp = $Builder.GetType().GetMethod('Build').Invoke($Builder, @())

    if (-not $MsalApp) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Failed to build MSAL PublicClientApplication via reflection.'),
                'MsalBuildFailed',
                [System.Management.Automation.ErrorCategory]::NotInstalled, $null))
    }

    $script:_OPIMMsalApp         = $MsalApp
    $script:_OPIMMsalAppTenantId = $TenantId

    Write-Verbose "[Get-OPIMMsalApplication] MSAL app built and cached."
    return $MsalApp
}
