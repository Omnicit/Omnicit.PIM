function Enable-OPIMMyRoles {
    <#
    .SYNOPSIS
    Connect to Microsoft Graph and activate all eligible PIM roles and groups for the current user.
    .DESCRIPTION
    One-shot command that connects to Microsoft Graph (and optionally Az) then activates all eligible
    directory roles, PIM group assignments, and Azure RBAC roles for the current user.

    If -TenantAlias is supplied, the tenant ID is resolved from TenantMap.psd1 (managed by
    Install-OPIMConfiguration). Only roles/groups stored for that alias are activated; if no role
    filter is stored for a category, all eligible assignments in that category are activated.

    Use the 'pim' alias for daily quick activation:

        pim
        pim -TenantAlias contoso -Hours 4 -Justification 'Incident response'

    The default activation duration is 1 hour. Override persistently in your profile:

        $PSDefaultParameterValues['Enable-OPIM*:Hours'] = 4

    .EXAMPLE
    Enable-OPIMMyRoles
    Connect with the current MgGraph context (or prompt for one) and activate all eligible roles for 1 hour.
    .EXAMPLE
    pim
    Short alias for Enable-OPIMMyRoles.
    .EXAMPLE
    pim -TenantAlias contoso -Hours 4 -Justification 'Incident response'
    Connect to the 'contoso' tenant (from TenantMap.psd1) and activate all eligible roles for 4 hours.
    .EXAMPLE
    pim -TenantAlias fabrikam -Wait
    Activate all configured roles for the 'fabrikam' tenant and wait until directory roles are provisioned.
    #>
    [Alias('pim')]
    [CmdletBinding()]
    param(
        # Short alias for the target tenant, matched against TenantMap.psd1.
        # Run Install-OPIMConfiguration to create or update tenant aliases.
        [string]$TenantAlias,

        # Activation duration in hours. Defaults to 1.
        # Make it persistent: $PSDefaultParameterValues['Enable-OPIM*:Hours'] = 4
        [ValidateRange(1, 24)][int]$Hours = 1,

        # Justification passed to all activation requests. May be required by your PIM policy.
        [string]$Justification,

        # Ticket number for auditing purposes.
        [string]$TicketNumber,

        # Ticket system associated with the above ticket number.
        [string]$TicketSystem,

        # Path to TenantMap.psd1 managed by Install-OPIMConfiguration.
        # Defaults to $env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1.
        [string]$TenantMapPath = "$env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1",

        # Wait until directory role activations are fully provisioned before returning.
        [Switch]$Wait
    )

    $graphScopes = @(
        'RoleEligibilitySchedule.ReadWrite.Directory'
        'RoleAssignmentSchedule.ReadWrite.Directory'
        'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup'
        'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup'
        'AdministrativeUnit.Read.All'
    )

    # ── Resolve tenant config and connect ─────────────────────────────────────
    $config = $null
    if ($TenantAlias) {
        if (-not (Test-Path $TenantMapPath)) {
            throw "TenantMap file not found at '$TenantMapPath'. Run: Install-OPIMConfiguration -TenantAlias <alias> -TenantId <guid>"
        }
        $map    = Import-PowerShellDataFile $TenantMapPath
        $config = $map[$TenantAlias]
        if (-not $config) {
            $available = ($map.Keys | Sort-Object) -join ', '
            throw "Tenant alias '$TenantAlias' not found in '$TenantMapPath'. Available aliases: $available"
        }
        $tenantId = if ($config -is [hashtable]) { $config.TenantId } else { [string]$config }
        Connect-MgGraph -TenantId $tenantId -Scopes $graphScopes -NoWelcome -ErrorAction Stop
        if ($config -is [hashtable] -and $config.AzureRoles) {
            Connect-AzAccount -TenantId $tenantId -ErrorAction Stop | Out-Null
        }
    } else {
        Connect-MgGraph -Scopes $graphScopes -NoWelcome -ErrorAction Stop
    }

    $activateParams = @{ Hours = $Hours }
    if ($Justification) { $activateParams.Justification = $Justification }
    if ($TicketNumber)  { $activateParams.TicketNumber   = $TicketNumber }
    if ($TicketSystem)  { $activateParams.TicketSystem   = $TicketSystem }

    # ── Directory Roles ───────────────────────────────────────────────────────
    $directoryRoles = Get-OPIMDirectoryRole
    if ($config -is [hashtable] -and $config.DirectoryRoles) {
        $directoryRoles = $directoryRoles | Where-Object { $_.roleDefinitionId -in $config.DirectoryRoles }
    }
    if ($directoryRoles) {
        $directoryRoles | Enable-OPIMDirectoryRole @activateParams -Wait:$Wait
    } else {
        Write-Verbose 'No eligible directory roles found (or none matched the configured set).'
    }

    # ── Entra ID PIM Groups ───────────────────────────────────────────────────
    $groups = Get-OPIMEntraIDGroup
    if ($config -is [hashtable] -and $config.EntraIDGroups) {
        $groups = $groups | Where-Object { "$($_.groupId)_$($_.accessId)" -in $config.EntraIDGroups }
    }
    if ($groups) {
        $groups | Enable-OPIMEntraIDGroup @activateParams
    } else {
        Write-Verbose 'No eligible PIM group assignments found (or none matched the configured set).'
    }

    # ── Azure RBAC Roles ──────────────────────────────────────────────────────
    if ((-not ($config -is [hashtable])) -or $config.AzureRoles) {
        $azureRoles = Get-OPIMAzureRole
        if ($config -is [hashtable] -and $config.AzureRoles) {
            $azureRoles = $azureRoles | Where-Object { $_.Name -in $config.AzureRoles }
        }
        if ($azureRoles) {
            $azureRoles | Enable-OPIMAzureRole @activateParams
        } else {
            Write-Verbose 'No eligible Azure roles found (or none matched the configured set).'
        }
    }
}
