function Connect-OPIM {
    <#
    .SYNOPSIS
    Authenticate to Microsoft Graph (and optionally Azure) for Omnicit.PIM.

    .DESCRIPTION
    Pre-authenticates the session before running Get-/Enable-/Disable-OPIM* cmdlets.
    All PIM cmdlets call this automatically on first use, so running Connect-OPIM explicitly
    is optional — use it when you want to control when the browser prompt appears.

    A single browser window covers all PIM surfaces (directory roles, Entra ID groups, and
    Azure RBAC). WAM is never used; authentication always goes through the system browser,
    which works identically on Windows, macOS, and Linux.

    The session state is cached in memory. Subsequent calls are idempotent — if a valid token
    already exists for the same tenant no browser prompt is shown.

    To disconnect and clear all cached tokens, call Disconnect-OPIM.

    .EXAMPLE
    Connect-OPIM -TenantId 'contoso.onmicrosoft.com'
    Authenticate and cache tokens for the Contoso tenant (Graph + Azure RBAC).

    .EXAMPLE
    Connect-OPIM -TenantAlias corp
    Resolve the 'corp' alias from TenantMap.psd1 and authenticate.

    .EXAMPLE
    Connect-OPIM -TenantAlias corp -IncludeARM
    Authenticate and also acquire an Azure Resource Manager token (for Enable-OPIMAzureRole).

    .PARAMETER TenantAlias
    Short alias for the target tenant, resolved from the TenantMap.psd1 managed by
    Install-OPIMConfiguration. Mutually exclusive with -TenantId.

    .PARAMETER TenantId
    The Entra ID tenant GUID or verified domain name, e.g. 'contoso.onmicrosoft.com'.
    Mutually exclusive with -TenantAlias.

    .PARAMETER IncludeARM
    Also acquire an Azure Resource Manager token and connect to Azure (Connect-AzAccount).
    Required when using Get-/Enable-/Disable-OPIMAzureRole in the same session.
    If not set, Azure cmdlets will call Connect-OPIM -IncludeARM automatically on first use.

    .PARAMETER TenantMapPath
    Path to TenantMap.psd1. Defaults to $env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1.
    #>
    [Alias('Connect-PIM')]
    [CmdletBinding(DefaultParameterSetName = 'ByTenantId')]
    param(
        [Parameter(ParameterSetName = 'ByAlias', Mandatory)]
        [string]$TenantAlias,

        [Parameter(ParameterSetName = 'ByTenantId')]
        [string]$TenantId,

        [switch]$IncludeARM,

        [string]$TenantMapPath = "$env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1"
    )

    # ── Resolve TenantAlias → TenantId ────────────────────────────────────────
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
    }

    Initialize-OPIMAuth -TenantId $TenantId -IncludeARM:$IncludeARM
}
