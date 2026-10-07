function Disable-OPIMMyRole {
    <#
    .SYNOPSIS
    Deactivate PIM roles and groups for the current user.
    .DESCRIPTION
    Deactivates directory roles, Entra ID group assignments, and Azure RBAC roles for the current
    user. Requires either a -TenantAlias (resolved from TenantMap.psd1 managed by
    Install-OPIMConfiguration) or an explicit -AllActivated* switch.

    When -TenantAlias is used, only roles and groups explicitly defined in the tenant configuration
    are deactivated. For each configured item that is not currently active a verbose message is
    written and the item is skipped without error. Categories not listed in the configuration are
    skipped with a verbose message.

    When an -AllActivated* switch is used without -TenantAlias, all currently active assignments
    in the selected categories are deactivated. Confirmation is required -- use -WhatIf to preview
    or -Confirm:$false to suppress the prompt.

    The command signs in to Microsoft Graph first and then, when Azure RBAC roles are to be
    deactivated, to Azure for the same tenant. A failed Graph sign-in stops the command before any
    role or group is listed or deactivated. A failed Azure sign-in skips the Azure RBAC roles only.

    Use the 'unpim' alias for quick deactivation:

        unpim -TenantAlias contoso
        unpim -AllActivated -Confirm:$false

    .EXAMPLE
    Disable-OPIMMyRole -TenantAlias contoso
    Deactivate all roles and groups configured for the 'contoso' alias in TenantMap.psd1.
    Roles/groups that are not currently active are silently skipped (use -Verbose to see them).
    .EXAMPLE
    unpim -TenantAlias contoso
    Same as above using the short alias.
    .EXAMPLE
    Disable-OPIMMyRole -AllActivated -Confirm:$false
    Deactivate all currently active directory roles, Entra ID groups, and Azure RBAC roles
    without prompting.
    .EXAMPLE
    Disable-OPIMMyRole -AllActivatedDirectoryRoles -AllActivatedAzureRoles
    Deactivate all active directory roles and Azure RBAC roles, prompting per category.
    .EXAMPLE
    unpim -TenantAlias contoso -DeviceCode
    Sign in with a device code instead of the system browser, then deactivate the configured roles.
    .PARAMETER TenantAlias
    Short alias for the target tenant matched against TenantMap.psd1. Run Install-OPIMConfiguration
    to create or update tenant aliases. Only categories explicitly listed in the configuration are
    deactivated; categories without configuration are skipped. Configured items that are not
    currently active are written to the verbose stream and skipped.
    .PARAMETER AllActivated
    Deactivate all currently active directory roles, Entra ID group assignments, and Azure RBAC
    roles. Requires confirmation per category. Use -Confirm:$false to suppress prompts.
    .PARAMETER AllActivatedDirectoryRoles
    Deactivate all currently active directory roles. Requires confirmation. May be combined with
    other -AllActivated* switches.
    .PARAMETER AllActivatedEntraIDGroups
    Deactivate all currently active Entra ID PIM group assignments. Requires confirmation. May be
    combined with other -AllActivated* switches.
    .PARAMETER AllActivatedAzureRoles
    Deactivate all currently active Azure RBAC roles. Requires confirmation. May be combined with
    other -AllActivated* switches.
    .PARAMETER TenantMapPath
    Path to the TenantMap.psd1 file managed by Install-OPIMConfiguration.
    Defaults to $env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1.
    .PARAMETER DeviceCode
    Sign in with a device code instead of the system browser. Passed to Connect-OPIM, which
    remembers the mode for the session; see Get-Help Connect-OPIM -Parameter DeviceCode.
    #>
    [Alias('unpim', 'Disable-OPIMMyRoles')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [string]$TenantAlias,
        [Switch]$AllActivated,
        [Switch]$AllActivatedDirectoryRoles,
        [Switch]$AllActivatedEntraIDGroups,
        [Switch]$AllActivatedAzureRoles,
        [string]$TenantMapPath = "$env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1",
        [Switch]$DeviceCode
    )

    # -- Guard: require explicit deactivation target ---------------------------
    if (-not $TenantAlias -and -not $AllActivated -and -not $AllActivatedDirectoryRoles -and
        -not $AllActivatedEntraIDGroups -and -not $AllActivatedAzureRoles) {
        Write-CmdletError `
            -Message ([System.Exception]::new(
                'No deactivation target specified. Supply -TenantAlias or use ' +
                '-AllActivated, -AllActivatedDirectoryRoles, -AllActivatedEntraIDGroups, or -AllActivatedAzureRoles.')) `
            -ErrorId 'NoDeactivationTargetSpecified' `
            -Category InvalidArgument `
            -Cmdlet $PSCmdlet
        return
    }

    # -- Resolve tenant config and connect -------------------------------------
    $Config = $null
    [string]$ResolvedTenantId = $null
    if ($TenantAlias) {
        if (-not (Test-Path $TenantMapPath)) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "TenantMap file not found at '$TenantMapPath'. Run: Install-OPIMConfiguration -TenantAlias <alias> -TenantId <guid>")) `
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
        $ResolvedTenantId = if ($Config -is [hashtable]) { $Config.TenantId } else { [string]$Config }
    }

    # The Azure pillar runs for -AllActivated, -AllActivatedAzureRoles, a hashtable alias that lists
    # AzureRoles, and the plain string form of an alias, whose Azure pillar deactivates every active
    # Azure role.
    [bool]$NeedsArm = $AllActivated -or $AllActivatedAzureRoles -or
                      ($TenantAlias -and ($Config -isnot [hashtable] -or $Config.AzureRoles))

    # -- Progress --------------------------------------------------------------
    [int]$ProgressPillarCount = ([int][bool]($TenantAlias -or $AllActivated -or $AllActivatedDirectoryRoles)) +
                                ([int][bool]($TenantAlias -or $AllActivated -or $AllActivatedEntraIDGroups)) +
                                ([int][bool]($TenantAlias -or $AllActivated -or $AllActivatedAzureRoles))
    [int]$ProgressShare       = [int](80 / [math]::Max($ProgressPillarCount, 1))
    [int]$ProgressPillarIndex = 0
    Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status 'Connecting...' -PercentComplete 3

    # OPIM-08: Graph first. A failed Graph sign-in stops the command: nothing is listed or
    # deactivated, not even in the tenant an earlier sign-in pinned.
    try {
        Connect-OPIM -TenantId $ResolvedTenantId -DeviceCode:$DeviceCode -ErrorAction Stop
    } catch {
        Remove-OPIMErrorRecord -Record $PSItem
        $PSCmdlet.WriteError($PSItem)
        Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Completed
        return
    }
    # Then Azure, for the same tenant, only when an Azure pillar runs. A failed Azure sign-in skips
    # the Azure pillar only.
    [bool]$ArmConnected = $false
    if ($NeedsArm) {
        try {
            Connect-OPIM -TenantId $ResolvedTenantId -IncludeARM -DeviceCode:$DeviceCode -ErrorAction Stop
            $ArmConnected = $true
        } catch {
            Remove-OPIMErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
        }
    }

    # -- Directory Roles -------------------------------------------------------
    if ($TenantAlias -or $AllActivated -or $AllActivatedDirectoryRoles) {
        if ($TenantAlias) {
            if ($Config -is [hashtable] -and -not $Config.DirectoryRoles) {
                Write-Verbose "No DirectoryRoles configured for alias '$TenantAlias'. Use Set-OPIMConfiguration to add roles, or run with -AllActivatedDirectoryRoles."
            } else {
                Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Directory roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- fetching active roles..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare)
                $ActiveDirectoryRoles = Get-OPIMDirectoryRole -Activated
                if ($Config -is [hashtable] -and $Config.DirectoryRoles) {
                    Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Directory roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- deactivating $($Config.DirectoryRoles.Count) configured role(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                    foreach ($ConfiguredRoleId in $Config.DirectoryRoles) {
                        $ActiveRole = $ActiveDirectoryRoles | Where-Object { $_.roleDefinitionId -eq $ConfiguredRoleId } | Select-Object -First 1
                        if ($ActiveRole) {
                            $ActiveRole | Disable-OPIMDirectoryRole | ConvertTo-OPIMMyRoleResult
                        } else {
                            Write-Verbose "Directory role '$ConfiguredRoleId' is not currently activated. No deactivation needed."
                        }
                    }
                } else {
                    # Simple string config -- deactivate all active directory roles
                    if ($ActiveDirectoryRoles) {
                        Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Directory roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- deactivating $($ActiveDirectoryRoles.Count) role(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                        $ActiveDirectoryRoles | Disable-OPIMDirectoryRole | ConvertTo-OPIMMyRoleResult
                    } else {
                        Write-Verbose 'No active directory roles found.'
                    }
                }
            }
        } elseif ($PSCmdlet.ShouldProcess('all active directory roles', 'Deactivate')) {
            Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Directory roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- fetching active roles..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare)
            $ActiveDirectoryRoles = Get-OPIMDirectoryRole -Activated
            if ($ActiveDirectoryRoles) {
                Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Directory roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- deactivating $($ActiveDirectoryRoles.Count) role(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                $ActiveDirectoryRoles | Disable-OPIMDirectoryRole | ConvertTo-OPIMMyRoleResult
            } else {
                Write-Verbose 'No active directory roles found.'
            }
        }
        $ProgressPillarIndex++
    }

    # -- Entra ID PIM Groups ---------------------------------------------------
    if ($TenantAlias -or $AllActivated -or $AllActivatedEntraIDGroups) {
        if ($TenantAlias) {
            if ($Config -is [hashtable] -and -not $Config.EntraIDGroups) {
                Write-Verbose "No EntraIDGroups configured for alias '$TenantAlias'. Use Set-OPIMConfiguration to add groups, or run with -AllActivatedEntraIDGroups."
            } else {
                Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Entra ID groups ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- fetching active groups..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare)
                $ActiveGroups = Get-OPIMEntraIDGroup -Activated
                if ($Config -is [hashtable] -and $Config.EntraIDGroups) {
                    Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Entra ID groups ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- deactivating $($Config.EntraIDGroups.Count) configured group(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                    foreach ($ConfiguredGroupKey in $Config.EntraIDGroups) {
                        $ActiveGroup = $ActiveGroups | Where-Object { "$($_.groupId)_$($_.accessId)" -eq $ConfiguredGroupKey } | Select-Object -First 1
                        if ($ActiveGroup) {
                            $ActiveGroup | Disable-OPIMEntraIDGroup | ConvertTo-OPIMMyRoleResult
                        } else {
                            Write-Verbose "Entra ID group '$ConfiguredGroupKey' is not currently activated. No deactivation needed."
                        }
                    }
                } else {
                    # Simple string config -- deactivate all active groups
                    if ($ActiveGroups) {
                        Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Entra ID groups ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- deactivating $($ActiveGroups.Count) group(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                        $ActiveGroups | Disable-OPIMEntraIDGroup | ConvertTo-OPIMMyRoleResult
                    } else {
                        Write-Verbose 'No active Entra ID group assignments found.'
                    }
                }
            }
        } elseif ($PSCmdlet.ShouldProcess('all active Entra ID group assignments', 'Deactivate')) {
            Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Entra ID groups ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- fetching active groups..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare)
            $ActiveGroups = Get-OPIMEntraIDGroup -Activated
            if ($ActiveGroups) {
                Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Entra ID groups ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- deactivating $($ActiveGroups.Count) group(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                $ActiveGroups | Disable-OPIMEntraIDGroup | ConvertTo-OPIMMyRoleResult
            } else {
                Write-Verbose 'No active Entra ID group assignments found.'
            }
        }
        $ProgressPillarIndex++
    }

    # -- Azure RBAC Roles ------------------------------------------------------
    # Only when Azure is signed in. Without $NeedsArm this is the verbose skip of a hashtable alias
    # that lists no AzureRoles.
    if (($TenantAlias -or $AllActivated -or $AllActivatedAzureRoles) -and (-not $NeedsArm -or $ArmConnected)) {
        if ($TenantAlias) {
            if ($Config -is [hashtable] -and -not $Config.AzureRoles) {
                Write-Verbose "No AzureRoles configured for alias '$TenantAlias'. Use Set-OPIMConfiguration to add roles, or run with -AllActivatedAzureRoles."
            } else {
                Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Azure RBAC roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- fetching active roles..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare)
                $ActiveAzureRoles = Get-OPIMAzureRole -Activated
                if ($Config -is [hashtable] -and $Config.AzureRoles) {
                    # The config stores eligible schedule .Name values (same as Enable-OPIMMyRole).
                    # Active instances are different objects -- correlate via RoleDefinitionId + ScopeId.
                    $ConfiguredEligible = Get-OPIMAzureRole | Where-Object { $_.Name -in $Config.AzureRoles }
                    Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Azure RBAC roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- deactivating $($Config.AzureRoles.Count) configured role(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                    foreach ($EligibleRole in $ConfiguredEligible) {
                        $ActiveRole = $ActiveAzureRoles | Where-Object {
                            $_.RoleDefinitionId -eq $EligibleRole.RoleDefinitionId -and
                            $_.ScopeId -eq $EligibleRole.ScopeId
                        } | Select-Object -First 1
                        if ($ActiveRole) {
                            $ActiveRole | Disable-OPIMAzureRole | ConvertTo-OPIMMyRoleResult
                        } else {
                            Write-Verbose "Azure role '$($EligibleRole.RoleDefinitionDisplayName)' on '$($EligibleRole.ScopeDisplayName)' is not currently activated. No deactivation needed."
                        }
                    }
                } else {
                    # Simple string config -- deactivate all active Azure roles
                    if ($ActiveAzureRoles) {
                        Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Azure RBAC roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- deactivating $($ActiveAzureRoles.Count) role(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                        $ActiveAzureRoles | Disable-OPIMAzureRole | ConvertTo-OPIMMyRoleResult
                    } else {
                        Write-Verbose 'No active Azure RBAC roles found.'
                    }
                }
            }
        } elseif ($PSCmdlet.ShouldProcess('all active Azure RBAC roles', 'Deactivate')) {
            Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Azure RBAC roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- fetching active roles..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare)
            $ActiveAzureRoles = Get-OPIMAzureRole -Activated
            if ($ActiveAzureRoles) {
                Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Azure RBAC roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- deactivating $($ActiveAzureRoles.Count) role(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                $ActiveAzureRoles | Disable-OPIMAzureRole | ConvertTo-OPIMMyRoleResult
            } else {
                Write-Verbose 'No active Azure RBAC roles found.'
            }
        }
        $ProgressPillarIndex++
    }

    Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Completed
}
