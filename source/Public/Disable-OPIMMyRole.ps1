function Disable-OPIMMyRole {
    <#
    .SYNOPSIS
    Deactivate PIM roles and groups for the current user.
    .DESCRIPTION
    Deactivates directory roles, Entra ID group assignments, and Azure RBAC roles for the current
    user. Requires either a -TenantAlias (resolved from TenantMap.psd1 managed by
    Install-OPIMConfiguration) or an explicit -AllActivated* switch.

    When -TenantAlias is used, only roles and groups explicitly defined in the tenant configuration
    are deactivated -- except for an alias in the old string form ('alias' = 'tenant id'), which
    lists no categories and deactivates every active directory role, group and Azure role. For
    each configured item that is not currently active a verbose message is written and the item
    is skipped without error. Categories not listed in the configuration are skipped with a
    verbose message. A directory role is deactivated only at the scope its entry
    names (roleDefinitionId|directoryScopeId); an entry written by 0.5.x holds the roleDefinitionId
    alone and means the role at the root scope '/' only, and an old and a new entry for the same
    role and scope are read once. Each configured item is matched against every active role or
    group: an item that matches more than one is refused with AmbiguousName, which lists the active
    roles or groups it matches, and none of them is deactivated; the next item still runs. To
    deactivate one of them, use Disable-OPIMDirectoryRole, Disable-OPIMEntraIDGroup or
    Disable-OPIMAzureRole with its tab-completed form. Only activations are active here: a permanent
    assignment is no activation and is never deactivated.

    When an -AllActivated* switch is used without -TenantAlias, all currently active assignments
    in the selected categories are deactivated. Confirmation is required -- use -WhatIf to preview
    or -Confirm:$false to suppress the prompt.

    The command signs in to Microsoft Graph first and then, when Azure RBAC roles are to be
    deactivated, to Azure for the same tenant. A failed Graph sign-in stops the command before any
    role or group is listed or deactivated. A failed Azure sign-in is written as an error and skips
    the Azure RBAC roles only -- except under the error preference Stop ($ErrorActionPreference or
    -ErrorAction), where that error ends the command before any category runs. A list of roles or
    groups that cannot be read is written as its own error, and nothing of that category is
    deactivated; the other categories still run, except under the error preference Stop, where the
    first such error ends the command.

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
    .EXAMPLE
    Disable-OPIMMyRole -AllActivatedDirectoryRoles -Environment USGov -Confirm:$false
    Sign in to the US Government (GCC High) cloud and deactivate all active directory roles there.
    .PARAMETER TenantAlias
    Short alias for the target tenant matched against TenantMap.psd1. Run Install-OPIMConfiguration
    to create or update tenant aliases. Only categories explicitly listed in the configuration are
    deactivated; categories without configuration are skipped. An alias in the old string form
    ('alias' = 'tenant id') is the exception and deactivates everything active. Configured items
    that are not currently active are written to the verbose stream and skipped. A directory role
    is deactivated only at its configured scope, and an entry without a scope means the role at
    '/' only. A configured item that matches more than one active role or group is written as the
    error AmbiguousName and none of the matches is deactivated. The alias also names the cloud to
    sign in to (Install-OPIMConfiguration -Environment): the sovereign cloud it stores, else the
    global cloud.
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
    Defaults to .config/Omnicit.PIM/TenantMap.psd1 under your home folder ($HOME; on Windows the
    same file as before, under $env:USERPROFILE).
    .PARAMETER DeviceCode
    Sign in with a device code instead of the system browser. Passed to Connect-OPIM, which
    remembers the mode for the session; see Get-Help Connect-OPIM -Parameter DeviceCode.
    .PARAMETER Environment
    The cloud to sign in to: 'Global', 'USGov', 'USGovDoD' or 'China'. Passed to both sign-ins,
    Graph and Azure; see Get-Help Connect-OPIM -Parameter Environment. Without it, a -TenantAlias
    signs in to the cloud the alias stores in the tenant map ('Global' when it stores none), and a
    stored cloud Omnicit.PIM does not know is refused before any sign-in. Without it and without an
    alias, the session's cloud is kept for the tenant it is signed in to, and any other tenant is
    'Global'.
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
        [string]$TenantMapPath = (Join-Path $HOME '.config/Omnicit.PIM/TenantMap.psd1'),
        [Switch]$DeviceCode,
        [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
        [string]$Environment
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
    $AliasEnvironment = $null
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

        # A12: a tenant alias signs in to the cloud it stores, unless -Environment names one. An unknown
        # stored cloud is refused here, before any sign-in and before anything is listed.
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
    # OPIM-29: only a cloud the caller named, or the cloud an alias stores, is passed on, so the -All*
    # form keeps the session's own cloud. An alias always names one (Global when it stores none).
    $ConnectParams = @{ TenantId = $ResolvedTenantId; DeviceCode = $DeviceCode; ErrorAction = 'Stop' }
    if ($Environment) {
        $ConnectParams.Environment = $Environment
    } elseif ($AliasEnvironment) {
        $ConnectParams.Environment = $AliasEnvironment
    }
    try {
        Connect-OPIM @ConnectParams
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
            Connect-OPIM @ConnectParams -IncludeARM
            $ArmConnected = $true
        } catch {
            Remove-OPIMErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
        }
    }

    # OPIM-12: in every pillar below, a listing that fails is written as its own error and ends that
    # pillar only. $ListRead is set only after every listing of the pillar returned, so nothing a
    # failed listing read is deactivated and the failure is never reported as "no active ..." or
    # "not currently activated"; the other pillars still run.

    # -- Directory Roles -------------------------------------------------------
    if ($TenantAlias -or $AllActivated -or $AllActivatedDirectoryRoles) {
        if ($TenantAlias) {
            if ($Config -is [hashtable] -and -not $Config.DirectoryRoles) {
                Write-Verbose "No DirectoryRoles configured for alias '$TenantAlias'. Use Set-OPIMConfiguration to add roles, or run with -AllActivatedDirectoryRoles."
            } else {
                Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Directory roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- fetching active roles..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare)
                [bool]$ListRead = $false
                try {
                    $ActiveDirectoryRoles = Get-OPIMDirectoryRole -Activated -ErrorAction Stop
                    $ListRead = $true
                } catch {
                    Remove-OPIMErrorRecord -Record $PSItem
                    $PSCmdlet.WriteError($PSItem)
                }
                if ($ListRead) {
                    if ($Config -is [hashtable] -and $Config.DirectoryRoles) {
                        # OPIM-10 (A13): a role is deactivated only at the scope its entry names; an entry from
                        # before 0.6.0 names no scope and means the role at '/' only. Each distinct key is read
                        # once, in the order configured; a blank entry yields no key and matches nothing.
                        $ConfiguredKeys = [System.Collections.Generic.List[string]]::new()
                        $SeenKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($Entry in $Config.DirectoryRoles) {
                            $Key = ConvertTo-OPIMTenantMapKey -Pillar Directory -Entry $Entry
                            if (-not $Key) { continue }
                            if ($SeenKeys.Add($Key)) { $ConfiguredKeys.Add($Key) }
                        }
                        Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Directory roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- deactivating $($ConfiguredKeys.Count) configured role(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                        foreach ($Key in $ConfiguredKeys) {
                            $ActiveMatches = @($ActiveDirectoryRoles | Where-Object {
                                    [string]::Equals((ConvertTo-OPIMTenantMapKey -Pillar Directory -InputObject $PSItem), $Key, [System.StringComparison]::OrdinalIgnoreCase)
                                })
                            if ($ActiveMatches.Count -gt 1) {
                                # OPIM-17: an entry that matches several active posts names none of them.
                                $PSCmdlet.WriteError((New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Directory `
                                    -Name $Key -Status Active -Candidate $ActiveMatches -Configuration))
                            } elseif ($ActiveMatches.Count -eq 1) {
                                $ActiveMatches[0] | Disable-OPIMDirectoryRole | ConvertTo-OPIMMyRoleResult
                            } else {
                                Write-Verbose "Directory role '$Key' is not currently activated at that scope. No deactivation needed."
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
            }
        } elseif ($PSCmdlet.ShouldProcess('all active directory roles', 'Deactivate')) {
            Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Directory roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- fetching active roles..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare)
            [bool]$ListRead = $false
            try {
                $ActiveDirectoryRoles = Get-OPIMDirectoryRole -Activated -ErrorAction Stop
                $ListRead = $true
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
            }
            if ($ListRead) {
                if ($ActiveDirectoryRoles) {
                    Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Directory roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- deactivating $($ActiveDirectoryRoles.Count) role(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                    $ActiveDirectoryRoles | Disable-OPIMDirectoryRole | ConvertTo-OPIMMyRoleResult
                } else {
                    Write-Verbose 'No active directory roles found.'
                }
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
                [bool]$ListRead = $false
                try {
                    $ActiveGroups = Get-OPIMEntraIDGroup -Activated -ErrorAction Stop
                    $ListRead = $true
                } catch {
                    Remove-OPIMErrorRecord -Record $PSItem
                    $PSCmdlet.WriteError($PSItem)
                }
                if ($ListRead) {
                    if ($Config -is [hashtable] -and $Config.EntraIDGroups) {
                        Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Entra ID groups ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- deactivating $($Config.EntraIDGroups.Count) configured group(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                        foreach ($Entry in $Config.EntraIDGroups) {
                            # groupId_accessId, read through the tenant map's key helper; a blank entry yields no key and
                            # is skipped, so it matches nothing.
                            $Key = ConvertTo-OPIMTenantMapKey -Pillar Group -Entry $Entry
                            if (-not $Key) { continue }
                            $ActiveMatches = @($ActiveGroups | Where-Object {
                                    [string]::Equals((ConvertTo-OPIMTenantMapKey -Pillar Group -InputObject $PSItem), $Key, [System.StringComparison]::OrdinalIgnoreCase)
                                })
                            if ($ActiveMatches.Count -gt 1) {
                                # OPIM-17: an entry that matches several active posts names none of them.
                                $PSCmdlet.WriteError((New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Group `
                                    -Name $Key -Status Active -Candidate $ActiveMatches -Configuration))
                            } elseif ($ActiveMatches.Count -eq 1) {
                                $ActiveMatches[0] | Disable-OPIMEntraIDGroup | ConvertTo-OPIMMyRoleResult
                            } else {
                                Write-Verbose "Entra ID group '$Key' is not currently activated. No deactivation needed."
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
            }
        } elseif ($PSCmdlet.ShouldProcess('all active Entra ID group assignments', 'Deactivate')) {
            Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Entra ID groups ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- fetching active groups..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare)
            [bool]$ListRead = $false
            try {
                $ActiveGroups = Get-OPIMEntraIDGroup -Activated -ErrorAction Stop
                $ListRead = $true
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
            }
            if ($ListRead) {
                if ($ActiveGroups) {
                    Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Entra ID groups ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- deactivating $($ActiveGroups.Count) group(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                    $ActiveGroups | Disable-OPIMEntraIDGroup | ConvertTo-OPIMMyRoleResult
                } else {
                    Write-Verbose 'No active Entra ID group assignments found.'
                }
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
                [bool]$ListRead = $false
                try {
                    $ActiveAzureRoles = Get-OPIMAzureRole -Activated -ErrorAction Stop
                    if ($Config -is [hashtable] -and $Config.AzureRoles) {
                        # The config stores eligible schedule .Name values (same as Enable-OPIMMyRole), read
                        # through the tenant map's key helper; a blank entry yields no key and is skipped, so it
                        # matches nothing. OPIM-22: an entry stored from an active role is Name|ScopeId and selects
                        # the eligibility only at that scope. Active instances are different objects -- correlate
                        # via RoleDefinitionId + ScopeId.
                        $ConfiguredAzureKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($Entry in $Config.AzureRoles) {
                            $Key = ConvertTo-OPIMTenantMapKey -Pillar Azure -Entry $Entry
                            if (-not $Key) { continue }
                            [void]$ConfiguredAzureKeys.Add($Key)
                        }
                        $ConfiguredEligible = Get-OPIMAzureRole -ErrorAction Stop | Where-Object {
                            $ConfiguredAzureKeys.Contains((ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $PSItem)) -or
                            $ConfiguredAzureKeys.Contains((ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $PSItem -WithScope))
                        }
                    }
                    $ListRead = $true
                } catch {
                    Remove-OPIMErrorRecord -Record $PSItem
                    $PSCmdlet.WriteError($PSItem)
                }
                if ($ListRead) {
                    if ($Config -is [hashtable] -and $Config.AzureRoles) {
                        Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Azure RBAC roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- deactivating $($Config.AzureRoles.Count) configured role(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                        foreach ($EligibleRole in $ConfiguredEligible) {
                            $ActiveMatches = @($ActiveAzureRoles | Where-Object {
                                    $_.RoleDefinitionId -eq $EligibleRole.RoleDefinitionId -and
                                    $_.ScopeId -eq $EligibleRole.ScopeId
                                })
                            if ($ActiveMatches.Count -gt 1) {
                                # OPIM-17: an entry that matches several active posts names none of them.
                                $PSCmdlet.WriteError((New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Azure `
                                    -Name $EligibleRole.Name -Status Active -Candidate $ActiveMatches -Configuration))
                            } elseif ($ActiveMatches.Count -eq 1) {
                                $ActiveMatches[0] | Disable-OPIMAzureRole | ConvertTo-OPIMMyRoleResult
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
            }
        } elseif ($PSCmdlet.ShouldProcess('all active Azure RBAC roles', 'Deactivate')) {
            Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Azure RBAC roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- fetching active roles..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare)
            [bool]$ListRead = $false
            try {
                $ActiveAzureRoles = Get-OPIMAzureRole -Activated -ErrorAction Stop
                $ListRead = $true
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
            }
            if ($ListRead) {
                if ($ActiveAzureRoles) {
                    Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Status "Azure RBAC roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- deactivating $($ActiveAzureRoles.Count) role(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                    $ActiveAzureRoles | Disable-OPIMAzureRole | ConvertTo-OPIMMyRoleResult
                } else {
                    Write-Verbose 'No active Azure RBAC roles found.'
                }
            }
        }
        $ProgressPillarIndex++
    }

    Write-Progress -Id 51808 -Activity 'Deactivating PIM roles' -Completed
}
