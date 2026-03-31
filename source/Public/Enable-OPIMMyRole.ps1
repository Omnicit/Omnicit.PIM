function Enable-OPIMMyRole {
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
    .PARAMETER TenantAlias
    Short alias for the target tenant matched against TenantMap.psd1. Run Install-OPIMConfiguration
    to create or update tenant aliases. When omitted uses the current MgGraph context.
    .PARAMETER Hours
    Activation duration in hours applied to all role and group activations. Defaults to 1.
    Make it persistent with: $PSDefaultParameterValues['Enable-OPIM*:Hours'] = 4
    .PARAMETER Justification
    Free-text justification passed to all activation requests. May be required by your PIM policy.
    .PARAMETER TicketNumber
    Ticket or work item number passed to all activation requests for auditing purposes.
    .PARAMETER TicketSystem
    Name of the ticket system that issued the above ticket number, e.g. ServiceNow or Jira.
    .PARAMETER TenantMapPath
    Path to the TenantMap.psd1 file managed by Install-OPIMConfiguration.
    Defaults to $env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1.
    .PARAMETER Wait
    Wait until all directory role activations are fully provisioned before returning.
    #>
    [Alias('pim', 'Enable-OPIMMyRoles')]
    [CmdletBinding()]
    param(
        [string]$TenantAlias,
        [ValidateRange(1, 24)][int]$Hours = 1,
        [string]$Justification,
        [string]$TicketNumber,
        [string]$TicketSystem,
        [string]$TenantMapPath = "$env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1",
        [Switch]$Wait
    )

    $GraphScopes = @(
        'RoleEligibilitySchedule.ReadWrite.Directory'
        'RoleAssignmentSchedule.ReadWrite.Directory'
        'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup'
        'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup'
        'AdministrativeUnit.Read.All'
    )

    # ── Resolve tenant config and connect ─────────────────────────────────────
    $Config = $null
    if ($TenantAlias) {
        if (-not (Test-Path $TenantMapPath)) {
            throw "TenantMap file not found at '$TenantMapPath'. Run: Install-OPIMConfiguration -TenantAlias <alias> -TenantId <guid>"
        }
        $Map    = Import-PowerShellDataFile $TenantMapPath
        $Config = $Map[$TenantAlias]
        if (-not $Config) {
            $Available = ($Map.Keys | Sort-Object) -join ', '
            throw "Tenant alias '$TenantAlias' not found in '$TenantMapPath'. Available aliases: $Available"
        }
        $TenantId = if ($Config -is [hashtable]) { $Config.TenantId } else { [string]$Config }
        Connect-MgGraph -TenantId $TenantId -Scopes $GraphScopes -NoWelcome -ErrorAction Stop
        if ($Config -is [hashtable] -and $Config.AzureRoles) {
            Connect-AzAccount -TenantId $TenantId -ErrorAction Stop | Out-Null
        }
    } else {
        Connect-MgGraph -Scopes $GraphScopes -NoWelcome -ErrorAction Stop
    }

    $ActivateParams = @{ Hours = $Hours }
    if ($Justification) { $ActivateParams.Justification = $Justification }
    if ($TicketNumber)  { $ActivateParams.TicketNumber   = $TicketNumber }
    if ($TicketSystem)  { $ActivateParams.TicketSystem   = $TicketSystem }

    # ── Directory Roles ───────────────────────────────────────────────────────
    $DirectoryRoles = Get-OPIMDirectoryRole
    if ($Config -is [hashtable] -and $Config.DirectoryRoles) {
        $DirectoryRoles = $DirectoryRoles | Where-Object { $_.roleDefinitionId -in $Config.DirectoryRoles }
    }
    if ($DirectoryRoles) {
        $DirectoryRoles | Enable-OPIMDirectoryRole @ActivateParams -Wait:$Wait
    } else {
        Write-Verbose 'No eligible directory roles found (or none matched the configured set).'
    }

    # ── Entra ID PIM Groups ───────────────────────────────────────────────────
    $Groups = Get-OPIMEntraIDGroup
    if ($Config -is [hashtable] -and $Config.EntraIDGroups) {
        $Groups = $Groups | Where-Object { "$($_.groupId)_$($_.accessId)" -in $Config.EntraIDGroups }
    }
    if ($Groups) {
        $Groups | Enable-OPIMEntraIDGroup @ActivateParams
    } else {
        Write-Verbose 'No eligible PIM group assignments found (or none matched the configured set).'
    }

    # ── Azure RBAC Roles ──────────────────────────────────────────────────────
    if ((-not ($Config -is [hashtable])) -or $Config.AzureRoles) {
        $AzureRoles = Get-OPIMAzureRole
        if ($Config -is [hashtable] -and $Config.AzureRoles) {
            $AzureRoles = $AzureRoles | Where-Object { $_.Name -in $Config.AzureRoles }
        }
        if ($AzureRoles) {
            $AzureRoles | Enable-OPIMAzureRole @ActivateParams
        } else {
            Write-Verbose 'No eligible Azure roles found (or none matched the configured set).'
        }
    }
}
