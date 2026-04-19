function Enable-OPIMMyRole {
    <#
    .SYNOPSIS
    Connect to Microsoft Graph and activate PIM roles and groups for the current user.
    .DESCRIPTION
    Activates directory roles, Entra ID group assignments, and Azure RBAC roles for the current
    user. Requires either a -TenantAlias (resolved from TenantMap.psd1 managed by
    Install-OPIMConfiguration) or an explicit -AllEligible* switch.

    When -TenantAlias is used, only roles and groups explicitly defined in the tenant configuration
    are activated. Categories not listed in the configuration are skipped with a warning. Use
    Set-OPIMConfiguration to add roles to a tenant alias.

    When an -AllEligible* switch is used without -TenantAlias, all eligible assignments in the
    selected categories are activated. Confirmation is required — use -WhatIf to preview or
    -Confirm:$false to suppress the prompt.

    Use the 'pim' alias for daily quick activation:

        pim -TenantAlias contoso
        pim -TenantAlias contoso -Hours 4 -Justification 'Incident response'
        pim -AllEligible

    The default activation duration is 1 hour. Override persistently in your profile:

        $PSDefaultParameterValues['Enable-OPIM*:Hours'] = 4

    .EXAMPLE
    Enable-OPIMMyRole -TenantAlias contoso
    Activate all roles and groups configured for the 'contoso' alias in TenantMap.psd1.
    .EXAMPLE
    pim -TenantAlias contoso -Hours 4 -Justification 'Incident response'
    Activate configured roles for the 'contoso' tenant for 4 hours with a justification.
    .EXAMPLE
    pim -TenantAlias fabrikam -Wait
    Activate configured roles for the 'fabrikam' tenant and wait until directory roles are provisioned.
    .EXAMPLE
    Enable-OPIMMyRole -AllEligible -Confirm:$false
    Activate all eligible directory roles, Entra ID groups, and Azure RBAC roles without prompting.
    .EXAMPLE
    Enable-OPIMMyRole -AllEligibleDirectoryRoles -AllEligibleAzureRoles
    Activate all eligible directory roles and Azure RBAC roles, prompting per category.
    .PARAMETER TenantAlias
    Short alias for the target tenant matched against TenantMap.psd1. Run Install-OPIMConfiguration
    to create or update tenant aliases. Only categories explicitly listed in the configuration are
    activated; categories without configuration are skipped with a warning.
    .PARAMETER AllEligible
    Activate all eligible directory roles, Entra ID group assignments, and Azure RBAC roles.
    Requires confirmation per category. Use -Confirm:$false to suppress prompts.
    .PARAMETER AllEligibleDirectoryRoles
    Activate all eligible directory roles. Requires confirmation. May be combined with other
    -AllEligible* switches.
    .PARAMETER AllEligibleEntraIDGroups
    Activate all eligible Entra ID PIM group assignments. Requires confirmation. May be combined
    with other -AllEligible* switches.
    .PARAMETER AllEligibleAzureRoles
    Activate all eligible Azure RBAC roles. Triggers Connect-AzAccount. Requires confirmation.
    May be combined with other -AllEligible* switches.
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
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$TenantAlias,
        [Switch]$AllEligible,
        [Switch]$AllEligibleDirectoryRoles,
        [Switch]$AllEligibleEntraIDGroups,
        [Switch]$AllEligibleAzureRoles,
        [ValidateRange(1, 24)][int]$Hours = 1,
        [string]$Justification,
        [string]$TicketNumber,
        [string]$TicketSystem,
        [string]$TenantMapPath = "$env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1",
        [Switch]$Wait
    )

    # ── Guard: require explicit activation target ──────────────────────────────
    if (-not $TenantAlias -and -not $AllEligible -and -not $AllEligibleDirectoryRoles -and
        -not $AllEligibleEntraIDGroups -and -not $AllEligibleAzureRoles) {
        $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new(
                'No activation target specified. Supply -TenantAlias or use ' +
                '-AllEligible, -AllEligibleDirectoryRoles, -AllEligibleEntraIDGroups, or -AllEligibleAzureRoles.'),
            'NoActivationTargetSpecified',
            [System.Management.Automation.ErrorCategory]::InvalidArgument, $null))
        return
    }

    # ── Resolve tenant config and connect ─────────────────────────────────────
    $Config = $null
    [string]$ResolvedTenantId = $null
    if ($TenantAlias) {
        if (-not (Test-Path $TenantMapPath)) {
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "TenantMap file not found at '$TenantMapPath'. Run: Install-OPIMConfiguration -TenantAlias <alias> -TenantId <guid>"),
                'TenantMapNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound, $TenantMapPath))
            return
        }
        $Map    = Import-PowerShellDataFile $TenantMapPath
        $Config = $Map[$TenantAlias]
        if (-not $Config) {
            $Available = ($Map.Keys | Sort-Object) -join ', '
            $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "Tenant alias '$TenantAlias' not found in '$TenantMapPath'. Available aliases: $Available"),
                'TenantAliasNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound, $TenantAlias))
            return
        }
        $ResolvedTenantId = if ($Config -is [hashtable]) { $Config.TenantId } else { [string]$Config }
    }

    [bool]$NeedsArm = $AllEligible -or $AllEligibleAzureRoles -or
                      ($Config -is [hashtable] -and $Config.AzureRoles)
    Initialize-OPIMAuth -TenantId $ResolvedTenantId -IncludeARM:$NeedsArm

    $ActivateParams = @{ Hours = $Hours }
    if ($Justification) { $ActivateParams.Justification = $Justification }
    if ($TicketNumber)  { $ActivateParams.TicketNumber   = $TicketNumber }
    if ($TicketSystem)  { $ActivateParams.TicketSystem   = $TicketSystem }

    # ── Directory Roles ───────────────────────────────────────────────────────
    if ($TenantAlias -or $AllEligible -or $AllEligibleDirectoryRoles) {
        if ($TenantAlias) {
            if ($Config -is [hashtable] -and -not $Config.DirectoryRoles) {
                Write-Warning "No DirectoryRoles configured for alias '$TenantAlias'. Use Set-OPIMConfiguration to add roles, or run with -AllEligibleDirectoryRoles."
            } else {
                $DirectoryRoles = Get-OPIMDirectoryRole
                if ($Config -is [hashtable] -and $Config.DirectoryRoles) {
                    $DirectoryRoles = $DirectoryRoles | Where-Object { $_.roleDefinitionId -in $Config.DirectoryRoles }
                }
                if ($DirectoryRoles) {
                    $DirectoryRoles | Enable-OPIMDirectoryRole @ActivateParams -Wait:$Wait
                } else {
                    Write-Verbose 'No eligible directory roles matched the configured set.'
                }
            }
        } elseif ($PSCmdlet.ShouldProcess('all eligible directory roles', 'Activate')) {
            $DirectoryRoles = Get-OPIMDirectoryRole
            if ($DirectoryRoles) {
                $DirectoryRoles | Enable-OPIMDirectoryRole @ActivateParams -Wait:$Wait
            } else {
                Write-Verbose 'No eligible directory roles found.'
            }
        }
    }

    # ── Entra ID PIM Groups ───────────────────────────────────────────────────
    if ($TenantAlias -or $AllEligible -or $AllEligibleEntraIDGroups) {
        if ($TenantAlias) {
            if ($Config -is [hashtable] -and -not $Config.EntraIDGroups) {
                Write-Warning "No EntraIDGroups configured for alias '$TenantAlias'. Use Set-OPIMConfiguration to add groups, or run with -AllEligibleEntraIDGroups."
            } else {
                $Groups = Get-OPIMEntraIDGroup
                if ($Config -is [hashtable] -and $Config.EntraIDGroups) {
                    $Groups = $Groups | Where-Object { "$($_.groupId)_$($_.accessId)" -in $Config.EntraIDGroups }
                }
                if ($Groups) {
                    $Groups | Enable-OPIMEntraIDGroup @ActivateParams
                } else {
                    Write-Verbose 'No eligible Entra ID group assignments matched the configured set.'
                }
            }
        } elseif ($PSCmdlet.ShouldProcess('all eligible Entra ID group assignments', 'Activate')) {
            $Groups = Get-OPIMEntraIDGroup
            if ($Groups) {
                $Groups | Enable-OPIMEntraIDGroup @ActivateParams
            } else {
                Write-Verbose 'No eligible Entra ID group assignments found.'
            }
        }
    }

    # ── Azure RBAC Roles ──────────────────────────────────────────────────────
    if ($TenantAlias -or $AllEligible -or $AllEligibleAzureRoles) {
        if ($TenantAlias) {
            if ($Config -is [hashtable] -and -not $Config.AzureRoles) {
                Write-Warning "No AzureRoles configured for alias '$TenantAlias'. Use Set-OPIMConfiguration to add roles, or run with -AllEligibleAzureRoles."
            } else {
                $AzureRoles = Get-OPIMAzureRole
                if ($Config -is [hashtable] -and $Config.AzureRoles) {
                    $AzureRoles = $AzureRoles | Where-Object { $_.Name -in $Config.AzureRoles }
                }
                if ($AzureRoles) {
                    $AzureRoles | Enable-OPIMAzureRole @ActivateParams
                } else {
                    Write-Verbose 'No eligible Azure roles matched the configured set.'
                }
            }
        } elseif ($PSCmdlet.ShouldProcess('all eligible Azure RBAC roles', 'Activate')) {
            $AzureRoles = Get-OPIMAzureRole
            if ($AzureRoles) {
                $AzureRoles | Enable-OPIMAzureRole @ActivateParams
            } else {
                Write-Verbose 'No eligible Azure RBAC roles found.'
            }
        }
    }
}
