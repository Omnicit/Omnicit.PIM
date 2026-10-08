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
    Set-OPIMConfiguration to add roles to a tenant alias. A directory role is activated only at the
    scope its entry names (roleDefinitionId|directoryScopeId); an entry written by 0.5.x holds the
    roleDefinitionId alone and means the role at the root scope '/' only.

    When an -AllEligible* switch is used without -TenantAlias, all eligible assignments in the
    selected categories are activated. Confirmation is required -- use -WhatIf to preview or
    -Confirm:$false to suppress the prompt.

    The command signs in to Microsoft Graph first and then, when Azure RBAC roles are to be
    activated, to Azure for the same tenant. A failed Graph sign-in stops the command before any
    role or group is listed or activated. A failed Azure sign-in is written as an error and skips
    the Azure RBAC roles only -- except under the error preference Stop ($ErrorActionPreference or
    -ErrorAction), where that error ends the command before any category runs. A list of roles or
    groups that cannot be read is written as its own error, and nothing of that category is
    activated; the other categories still run, except under the error preference Stop, where the
    first such error ends the command.

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
    .EXAMPLE
    pim -TenantAlias contoso -DeviceCode
    Sign in with a device code instead of the system browser, then activate the configured roles.
    .PARAMETER TenantAlias
    Short alias for the target tenant matched against TenantMap.psd1. Run Install-OPIMConfiguration
    to create or update tenant aliases. Only categories explicitly listed in the configuration are
    activated; categories without configuration are skipped with a warning. A directory role is
    activated only at its configured scope, and an entry without a scope means the role at '/' only.
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
    Defaults to .config/Omnicit.PIM/TenantMap.psd1 under your home folder ($HOME; on Windows the
    same file as before, under $env:USERPROFILE).
    .PARAMETER Wait
    Wait until all directory role activations are fully provisioned before returning.
    .PARAMETER TimeoutSeconds
    With -Wait, the most seconds to wait for each directory role activation. Defaults to 300.
    .PARAMETER DeviceCode
    Sign in with a device code instead of the system browser. Passed to Connect-OPIM, which
    remembers the mode for the session; see Get-Help Connect-OPIM -Parameter DeviceCode.
    #>
    [Alias('pim', 'Enable-OPIMMyRoles')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
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
        [string]$TenantMapPath = (Join-Path $HOME '.config/Omnicit.PIM/TenantMap.psd1'),
        [Switch]$Wait,
        [ValidateRange(1, 86400)][int]$TimeoutSeconds = 300,
        [Switch]$DeviceCode
    )

    # -- Guard: require explicit activation target ------------------------------
    if (-not $TenantAlias -and -not $AllEligible -and -not $AllEligibleDirectoryRoles -and
        -not $AllEligibleEntraIDGroups -and -not $AllEligibleAzureRoles) {
        Write-CmdletError `
            -Message ([System.Exception]::new(
                'No activation target specified. Supply -TenantAlias or use ' +
                '-AllEligible, -AllEligibleDirectoryRoles, -AllEligibleEntraIDGroups, or -AllEligibleAzureRoles.')) `
            -ErrorId 'NoActivationTargetSpecified' `
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

    # The Azure pillar runs for -AllEligible, -AllEligibleAzureRoles, a hashtable alias that lists
    # AzureRoles, and the plain string form of an alias, whose Azure pillar activates every eligible
    # Azure role.
    [bool]$NeedsArm = $AllEligible -or $AllEligibleAzureRoles -or
                      ($TenantAlias -and ($Config -isnot [hashtable] -or $Config.AzureRoles))

    # -- Progress --------------------------------------------------------------
    [int]$ProgressPillarCount = ([int][bool]($TenantAlias -or $AllEligible -or $AllEligibleDirectoryRoles)) +
                                ([int][bool]($TenantAlias -or $AllEligible -or $AllEligibleEntraIDGroups)) +
                                ([int][bool]($TenantAlias -or $AllEligible -or $AllEligibleAzureRoles))
    [int]$ProgressShare       = [int](80 / [math]::Max($ProgressPillarCount, 1))
    [int]$ProgressPillarIndex = 0
    Write-Progress -Id 51807 -Activity 'Activating PIM roles' -Status 'Connecting...' -PercentComplete 3

    # OPIM-08: Graph first. A failed Graph sign-in stops the command: nothing is listed or activated,
    # not even in the tenant an earlier sign-in pinned.
    try {
        Connect-OPIM -TenantId $ResolvedTenantId -DeviceCode:$DeviceCode -ErrorAction Stop
    } catch {
        Remove-OPIMErrorRecord -Record $PSItem
        $PSCmdlet.WriteError($PSItem)
        Write-Progress -Id 51807 -Activity 'Activating PIM roles' -Completed
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

    $ActivateParams = @{ Hours = $Hours }
    if ($Justification) { $ActivateParams.Justification = $Justification }
    if ($TicketNumber)  { $ActivateParams.TicketNumber   = $TicketNumber }
    if ($TicketSystem)  { $ActivateParams.TicketSystem   = $TicketSystem }

    # OPIM-12: in every pillar below, a listing that fails is written as its own error and ends that
    # pillar only. $ListRead is set only after the listing returned, so nothing a failed listing
    # read is activated and the failure is never reported as "no eligible ..."; the other pillars
    # still run.

    # -- Directory Roles -------------------------------------------------------
    if ($TenantAlias -or $AllEligible -or $AllEligibleDirectoryRoles) {
        if ($TenantAlias) {
            if ($Config -is [hashtable] -and -not $Config.DirectoryRoles) {
                Write-Verbose "No DirectoryRoles configured for alias '$TenantAlias'. Use Set-OPIMConfiguration to add roles, or run with -AllEligibleDirectoryRoles."
            } else {
                Write-Progress -Id 51807 -Activity 'Activating PIM roles' -Status "Directory roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- fetching eligible roles..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare)
                [bool]$ListRead = $false
                try {
                    $DirectoryRoles = Get-OPIMDirectoryRole -ErrorAction Stop
                    $ListRead = $true
                } catch {
                    Remove-OPIMErrorRecord -Record $PSItem
                    $PSCmdlet.WriteError($PSItem)
                }
                if ($ListRead) {
                    if ($Config -is [hashtable] -and $Config.DirectoryRoles) {
                        # OPIM-10 (A13): a role is activated only at the scope its entry names; an entry from before
                        # 0.6.0 names no scope and means the role at '/' only.
                        $ConfiguredKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($Entry in $Config.DirectoryRoles) { [void]$ConfiguredKeys.Add((ConvertTo-OPIMTenantMapKey -Pillar Directory -Entry $Entry)) }
                        $DirectoryRoles = $DirectoryRoles | Where-Object { $ConfiguredKeys.Contains((ConvertTo-OPIMTenantMapKey -Pillar Directory -InputObject $PSItem)) }
                    }
                    if ($DirectoryRoles) {
                        Write-Progress -Id 51807 -Activity 'Activating PIM roles' -Status "Directory roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- activating $($DirectoryRoles.Count) role(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                        $DirectoryRoles | Enable-OPIMDirectoryRole @ActivateParams -Wait:$Wait -TimeoutSeconds $TimeoutSeconds | ConvertTo-OPIMMyRoleResult
                    } else {
                        Write-Verbose 'No eligible directory roles matched the configured set.'
                    }
                }
            }
        } elseif ($PSCmdlet.ShouldProcess('all eligible directory roles', 'Activate')) {
            Write-Progress -Id 51807 -Activity 'Activating PIM roles' -Status "Directory roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- fetching eligible roles..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare)
            [bool]$ListRead = $false
            try {
                $DirectoryRoles = Get-OPIMDirectoryRole -ErrorAction Stop
                $ListRead = $true
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
            }
            if ($ListRead) {
                if ($DirectoryRoles) {
                    Write-Progress -Id 51807 -Activity 'Activating PIM roles' -Status "Directory roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- activating $($DirectoryRoles.Count) role(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                    $DirectoryRoles | Enable-OPIMDirectoryRole @ActivateParams -Wait:$Wait -TimeoutSeconds $TimeoutSeconds | ConvertTo-OPIMMyRoleResult
                } else {
                    Write-Verbose 'No eligible directory roles found.'
                }
            }
        }
        $ProgressPillarIndex++
    }

    # -- Entra ID PIM Groups ---------------------------------------------------
    if ($TenantAlias -or $AllEligible -or $AllEligibleEntraIDGroups) {
        if ($TenantAlias) {
            if ($Config -is [hashtable] -and -not $Config.EntraIDGroups) {
                Write-Verbose "No EntraIDGroups configured for alias '$TenantAlias'. Use Set-OPIMConfiguration to add groups, or run with -AllEligibleEntraIDGroups."
            } else {
                Write-Progress -Id 51807 -Activity 'Activating PIM roles' -Status "Entra ID groups ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- fetching eligible groups..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare)
                [bool]$ListRead = $false
                try {
                    $Groups = Get-OPIMEntraIDGroup -ErrorAction Stop
                    $ListRead = $true
                } catch {
                    Remove-OPIMErrorRecord -Record $PSItem
                    $PSCmdlet.WriteError($PSItem)
                }
                if ($ListRead) {
                    if ($Config -is [hashtable] -and $Config.EntraIDGroups) {
                        # groupId_accessId, read through the tenant map's key helper. A blank entry yields no key
                        # (the set then holds a null, which no post's key equals), so it matches nothing.
                        $ConfiguredGroupKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($Entry in $Config.EntraIDGroups) { [void]$ConfiguredGroupKeys.Add((ConvertTo-OPIMTenantMapKey -Pillar Group -Entry $Entry)) }
                        $Groups = $Groups | Where-Object { $ConfiguredGroupKeys.Contains((ConvertTo-OPIMTenantMapKey -Pillar Group -InputObject $PSItem)) }
                    }
                    if ($Groups) {
                        Write-Progress -Id 51807 -Activity 'Activating PIM roles' -Status "Entra ID groups ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- activating $($Groups.Count) group(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                        $Groups | Enable-OPIMEntraIDGroup @ActivateParams | ConvertTo-OPIMMyRoleResult
                    } else {
                        Write-Verbose 'No eligible Entra ID group assignments matched the configured set.'
                    }
                }
            }
        } elseif ($PSCmdlet.ShouldProcess('all eligible Entra ID group assignments', 'Activate')) {
            Write-Progress -Id 51807 -Activity 'Activating PIM roles' -Status "Entra ID groups ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- fetching eligible groups..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare)
            [bool]$ListRead = $false
            try {
                $Groups = Get-OPIMEntraIDGroup -ErrorAction Stop
                $ListRead = $true
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
            }
            if ($ListRead) {
                if ($Groups) {
                    Write-Progress -Id 51807 -Activity 'Activating PIM roles' -Status "Entra ID groups ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- activating $($Groups.Count) group(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                    $Groups | Enable-OPIMEntraIDGroup @ActivateParams | ConvertTo-OPIMMyRoleResult
                } else {
                    Write-Verbose 'No eligible Entra ID group assignments found.'
                }
            }
        }
        $ProgressPillarIndex++
    }

    # -- Azure RBAC Roles ------------------------------------------------------
    # Only when Azure is signed in. Without $NeedsArm this is the verbose skip of a hashtable alias
    # that lists no AzureRoles.
    if (($TenantAlias -or $AllEligible -or $AllEligibleAzureRoles) -and (-not $NeedsArm -or $ArmConnected)) {
        if ($TenantAlias) {
            if ($Config -is [hashtable] -and -not $Config.AzureRoles) {
                Write-Verbose "No AzureRoles configured for alias '$TenantAlias'. Use Set-OPIMConfiguration to add roles, or run with -AllEligibleAzureRoles."
            } else {
                Write-Progress -Id 51807 -Activity 'Activating PIM roles' -Status "Azure RBAC roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- fetching eligible roles..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare)
                [bool]$ListRead = $false
                try {
                    $AzureRoles = Get-OPIMAzureRole -ErrorAction Stop
                    $ListRead = $true
                } catch {
                    Remove-OPIMErrorRecord -Record $PSItem
                    $PSCmdlet.WriteError($PSItem)
                }
                if ($ListRead) {
                    if ($Config -is [hashtable] -and $Config.AzureRoles) {
                        # The eligibility schedule Name, read through the tenant map's key helper; a blank entry
                        # yields no key and matches nothing, as above.
                        $ConfiguredAzureKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($Entry in $Config.AzureRoles) { [void]$ConfiguredAzureKeys.Add((ConvertTo-OPIMTenantMapKey -Pillar Azure -Entry $Entry)) }
                        $AzureRoles = $AzureRoles | Where-Object { $ConfiguredAzureKeys.Contains((ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $PSItem)) }
                    }
                    if ($AzureRoles) {
                        Write-Progress -Id 51807 -Activity 'Activating PIM roles' -Status "Azure RBAC roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- activating $($AzureRoles.Count) role(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                        $AzureRoles | Enable-OPIMAzureRole @ActivateParams | ConvertTo-OPIMMyRoleResult
                    } else {
                        Write-Verbose 'No eligible Azure roles matched the configured set.'
                    }
                }
            }
        } elseif ($PSCmdlet.ShouldProcess('all eligible Azure RBAC roles', 'Activate')) {
            Write-Progress -Id 51807 -Activity 'Activating PIM roles' -Status "Azure RBAC roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- fetching eligible roles..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare)
            [bool]$ListRead = $false
            try {
                $AzureRoles = Get-OPIMAzureRole -ErrorAction Stop
                $ListRead = $true
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
            }
            if ($ListRead) {
                if ($AzureRoles) {
                    Write-Progress -Id 51807 -Activity 'Activating PIM roles' -Status "Azure RBAC roles ($($ProgressPillarIndex + 1) of $ProgressPillarCount) -- activating $($AzureRoles.Count) role(s)..." -PercentComplete (10 + $ProgressPillarIndex * $ProgressShare + [int]($ProgressShare / 2))
                    $AzureRoles | Enable-OPIMAzureRole @ActivateParams | ConvertTo-OPIMMyRoleResult
                } else {
                    Write-Verbose 'No eligible Azure RBAC roles found.'
                }
            }
        }
    }

    Write-Progress -Id 51807 -Activity 'Activating PIM roles' -Completed
}
