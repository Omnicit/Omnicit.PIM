using namespace System.Collections.Generic
function Install-OPIMConfiguration {
    <#
    .SYNOPSIS
    Configure Omnicit.PIM shortcuts and settings in the current user's PowerShell environment.
    .DESCRIPTION
    Installs optional quality-of-life improvements into the user's PowerShell profile and configuration:

    - ProfileAlias  : Adds an 'Activate-MyPIM' convenience function and 'pim' alias to $PROFILE.CurrentUserAllHosts
    - TenantMap     : Creates or updates a TenantMap.psd1 file mapping tenant aliases to tenant IDs
    - DefaultParameters : Adds $PSDefaultParameterValues entries to the profile for default settings

    All file operations support -WhatIf and -Confirm.
    .EXAMPLE
    Install-OPIMConfiguration -ProfileAlias
    Add the Activate-MyPIM function and pim alias to the user's profile.
    .EXAMPLE
    Install-OPIMConfiguration -ProfileAlias -WhatIf
    Preview what the ProfileAlias installation would do without making changes.
    .EXAMPLE
    Install-OPIMConfiguration -TenantMap -TenantAlias contoso -TenantId '00000000-0000-0000-0000-000000000000'
    Add or update a tenant alias mapping in TenantMap.psd1.
    .EXAMPLE
    Get-OPIMDirectoryRole | Where-Object { $_.roleDefinition.displayName -like 'Compliance*' } | Install-OPIMConfiguration -TenantMap -TenantAlias contoso -TenantId '<guid>'
    Store specific directory roles as the default activation set for the 'contoso' tenant.
    .EXAMPLE
    Get-OPIMEntraIDGroup | Install-OPIMConfiguration -TenantMap -TenantAlias contoso -TenantId '<guid>'
    Store all eligible group assignments as the default activation set for the 'contoso' tenant.
    .EXAMPLE
    Install-OPIMConfiguration -DefaultParameters -Duration 4
    Add a $PSDefaultParameterValues entry to set the default activation duration to 4 hours.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        #Add the Activate-MyPIM function and 'pim' alias to $PROFILE.CurrentUserAllHosts.
        [Switch]$ProfileAlias,

        #Create or update a TenantMap.psd1 with a tenant alias-to-ID mapping.
        [Switch]$TenantMap,
        #The short alias for the tenant (e.g. 'contoso'). Required with -TenantMap.
        [string]$TenantAlias,
        #The Azure Tenant ID (GUID) for the alias. Required with -TenantMap.
        [string]$TenantId,
        #Path to the TenantMap.psd1 file. Defaults to $env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1.
        [string]$TenantMapPath = "$env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1",

        #Add $PSDefaultParameterValues entries for common Omnicit.PIM parameters to the profile.
        [Switch]$DefaultParameters,
        #Default activation duration in hours for -DefaultParameters.
        [ValidateRange(1, 24)][int]$Duration = 1,

        #Overwrite existing configuration blocks without prompting.
        [Switch]$Force,

        #Role, group, or Azure role eligibility objects piped from Get-OPIMDirectoryRole,
        #Get-OPIMEntraIDGroup, or Get-OPIMAzureRole. Used with -TenantMap to store the
        #default activation set for the tenant. Only objects matching a known OPIM type
        #are collected; others are silently ignored.
        [Parameter(ValueFromPipeline)]
        $InputObject
    )

    begin {
        [List[string]]$_directoryRoleIds = [List[string]]::new()
        [List[string]]$_groupIds         = [List[string]]::new()
        [List[string]]$_azureRoleNames   = [List[string]]::new()
    }
    process {
        if ($null -eq $InputObject) { return }
        switch ($true) {
            { $InputObject.PSTypeNames -contains 'Omnicit.PIM.DirectoryEligibilitySchedule' -or
              $InputObject.PSTypeNames -contains 'Omnicit.PIM.DirectoryAssignmentScheduleInstance' } {
                # Store roleDefinitionId — stable across eligibility renewals
                [void]$_directoryRoleIds.Add($InputObject.roleDefinitionId); break
            }
            { $InputObject.PSTypeNames -contains 'Omnicit.PIM.GroupEligibilitySchedule' -or
              $InputObject.PSTypeNames -contains 'Omnicit.PIM.GroupAssignmentScheduleInstance' } {
                # Store groupId_accessId — stable and encodes member vs owner
                [void]$_groupIds.Add("$($InputObject.groupId)_$($InputObject.accessId)"); break
            }
            { $null -ne $InputObject.RoleDefinitionId -and $null -ne $InputObject.ScopeId } {
                # Azure RBAC eligibility schedule from Get-OPIMAzureRole
                [void]$_azureRoleNames.Add($InputObject.Name); break
            }
        }
    }
    end {

    # Imply -TenantMap when -TenantAlias and -TenantId are provided without the switch
    if ($TenantId -and $TenantAlias -and -not $TenantMap) { $TenantMap = $true }

    # Validate required TenantAlias early when TenantId or pipeline input is given
    if (($TenantId -or $_directoryRoleIds.Count -or $_groupIds.Count -or $_azureRoleNames.Count) -and -not $TenantAlias) {
        throw '-TenantAlias is required when providing -TenantId or piping role/group objects. Example: Get-OPIMEntraIDGroup | Install-OPIMConfiguration -TenantAlias contoso -TenantId <guid>'
    }

    # ── ProfileAlias ──────────────────────────────────────────────────────────
    if ($ProfileAlias) {
        $profilePath = $PROFILE.CurrentUserAllHosts
        $profileDir  = Split-Path $profilePath -Parent

        if (-not (Test-Path $profileDir)) {
            if ($PSCmdlet.ShouldProcess($profileDir, 'Create profile directory')) {
                New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
            }
        }
        if (-not (Test-Path $profilePath)) {
            if ($PSCmdlet.ShouldProcess($profilePath, 'Create profile file')) {
                New-Item -ItemType File -Path $profilePath -Force | Out-Null
            }
        }

        $existingContent = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { '' }
        $marker          = '# Omnicit.PIM - ProfileAlias'
        $shouldWriteProfile = $true

        if ($existingContent -match [regex]::Escape($marker)) {
            if (-not $Force) {
                Write-Warning "ProfileAlias block already exists in $profilePath. Use -Force to overwrite."
                $shouldWriteProfile = $false
            } else {
                # Strip the existing block and write the file back before appending the new one
                $existingContent = $existingContent -replace "(?s)$([regex]::Escape($marker)).*?# End Omnicit.PIM - ProfileAlias", ''
                Set-Content -Path $profilePath -Value $existingContent.TrimEnd() -Encoding UTF8 -NoNewline
            }
        }

        $profileBlock = @"

$marker
# Path to TenantMap.psd1 — update this if you store it elsewhere.
`$OPIMTenantMapPath = '$TenantMapPath'

function Activate-MyPIM {
    <#
    .SYNOPSIS
    Convenience wrapper: connect to Graph and activate all eligible PIM roles and groups.
    .DESCRIPTION
    Connects to Microsoft Graph (requesting required PIM scopes) then activates all eligible
    directory roles and PIM group assignments for the current user.

    If -TenantAlias is supplied the tenant ID is looked up in the TenantMap file at
    `$OPIMTenantMapPath (configured at the top of this block). If -TenantAlias is omitted
    the current MgGraph context is used, or an interactive login for the default tenant.
    .PARAMETER TenantAlias
    Short alias for the target tenant, matched against the TenantMap file.
    Tab completion is available if Get-OPIMTenantAlias is loaded.
    .PARAMETER Duration
    Activation duration in hours. Defaults to 1.
    .PARAMETER Justification
    Optional justification string passed to all activation requests.
    .PARAMETER TenantMapPath
    Path to the TenantMap.psd1 file. Defaults to `$OPIMTenantMapPath.
    .EXAMPLE
    pim
    Activate all eligible roles/groups for 1 hour using the current MgGraph session.
    .EXAMPLE
    pim -TenantAlias contoso -Duration 4 -Justification 'Incident response'
    Connect to the 'contoso' tenant and activate all eligible roles for 4 hours.
    #>
    [CmdletBinding()]
    param(
        [string]`$TenantAlias,
        [ValidateRange(1,24)][int]`$Duration = 1,
        [string]`$Justification,
        [string]`$TenantMapPath = `$OPIMTenantMapPath
    )

    `$graphScopes = @(
        'RoleEligibilitySchedule.ReadWrite.Directory'
        'RoleAssignmentSchedule.ReadWrite.Directory'
        'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup'
        'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup'
        'AdministrativeUnit.Read.All'
    )

    if (`$TenantAlias) {
        if (-not (Test-Path `$TenantMapPath)) {
            throw "TenantMap file not found at '`$TenantMapPath'. Run: Install-OPIMConfiguration -TenantMap -TenantAlias <alias> -TenantId <guid>"
        }
        `$map    = Import-PowerShellDataFile `$TenantMapPath
        `$config = `$map[`$TenantAlias]
        if (-not `$config) {
            `$available = `$map.Keys -join ', '
            throw "Tenant alias '`$TenantAlias' not found in '`$TenantMapPath'. Available aliases: `$available"
        }
        # Support both legacy flat-string format and current nested hashtable format
        `$tenantId = if (`$config -is [hashtable]) { `$config.TenantId } else { `$config }
        Connect-MgGraph -TenantId `$tenantId -Scopes `$graphScopes -NoWelcome -ErrorAction Stop
        if (`$config -is [hashtable] -and `$config.AzureRoles) {
            Connect-AzAccount -TenantId `$tenantId -ErrorAction Stop | Out-Null
        }
    } else {
        `$config = `$null
        # Use existing context if already connected with sufficient scopes, otherwise prompt
        Connect-MgGraph -Scopes `$graphScopes -NoWelcome -ErrorAction Stop
    }

    `$activateParams = @{ Hours = `$Duration }
    if (`$Justification) { `$activateParams.Justification = `$Justification }

    # ── Directory Roles ───────────────────────────────────────────────────────
    `$directoryRoles = Get-OPIMDirectoryRole
    if (`$config -is [hashtable] -and `$config.DirectoryRoles) {
        `$directoryRoles = `$directoryRoles | Where-Object { `$_.roleDefinitionId -in `$config.DirectoryRoles }
    }
    if (`$directoryRoles) {
        `$directoryRoles | Enable-OPIMDirectoryRole @activateParams -Wait
    } else {
        Write-Verbose 'No eligible directory roles found (or none matched the configured set).'
    }

    # ── Entra ID PIM Groups ───────────────────────────────────────────────────
    `$groups = Get-OPIMEntraIDGroup
    if (`$config -is [hashtable] -and `$config.EntraIDGroups) {
        `$groups = `$groups | Where-Object { "`$(`$_.groupId)_`$(`$_.accessId)" -in `$config.EntraIDGroups }
    }
    if (`$groups) {
        `$groups | Enable-OPIMEntraIDGroup @activateParams
    } else {
        Write-Verbose 'No eligible PIM group assignments found (or none matched the configured set).'
    }

    # ── Azure RBAC Roles ──────────────────────────────────────────────────────
    if ((-not (`$config -is [hashtable])) -or `$config.AzureRoles) {
        `$azureRoles = Get-OPIMAzureRole
        if (`$config -is [hashtable] -and `$config.AzureRoles) {
            `$azureRoles = `$azureRoles | Where-Object { `$_.Name -in `$config.AzureRoles }
        }
        if (`$azureRoles) {
            `$azureRoles | Enable-OPIMAzureRole @activateParams
        } else {
            Write-Verbose 'No eligible Azure roles found (or none matched the configured set).'
        }
    }
}
Set-Alias -Name pim -Value Activate-MyPIM
# End Omnicit.PIM - ProfileAlias
"@

        if ($shouldWriteProfile -and $PSCmdlet.ShouldProcess($profilePath, 'Append ProfileAlias block')) {
            Add-Content -Path $profilePath -Value $profileBlock
            Write-Host "ProfileAlias block written to $profilePath" -ForegroundColor Green
        }
    }

    # ── TenantMap ─────────────────────────────────────────────────────────────
    if ($TenantMap) {
        if (-not $TenantAlias) { throw '-TenantAlias is required when using -TenantMap.' }
        if (-not $TenantId)    { throw '-TenantId is required when using -TenantMap.' }
        if ($TenantId -notmatch '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') {
            throw "-TenantId '$TenantId' does not look like a valid GUID."
        }

        $tenantMapDir = Split-Path $TenantMapPath -Parent
        if (-not (Test-Path $tenantMapDir)) {
            if ($PSCmdlet.ShouldProcess($tenantMapDir, 'Create TenantMap directory')) {
                New-Item -ItemType Directory -Path $tenantMapDir -Force | Out-Null
            }
        }

        $mapData = if (Test-Path $TenantMapPath) {
            Import-PowerShellDataFile $TenantMapPath
        } else {
            @{}
        }

        if ($mapData.ContainsKey($TenantAlias) -and -not $Force) {
            Write-Warning "Tenant alias '$TenantAlias' already exists in $TenantMapPath. Use -Force to overwrite."
        } else {
            # Preserve any existing role lists from the current entry unless new ones were piped in
            $existingEntry = if ($mapData[$TenantAlias] -is [hashtable]) { $mapData[$TenantAlias] } else { @{} }

            $entry = [ordered]@{ TenantId = $TenantId }

            $resolvedDirRoles  = if ($_directoryRoleIds.Count) { @($_directoryRoleIds) } elseif ($existingEntry.DirectoryRoles) { $existingEntry.DirectoryRoles }
            $resolvedGroups    = if ($_groupIds.Count)         { @($_groupIds)         } elseif ($existingEntry.EntraIDGroups)  { $existingEntry.EntraIDGroups  }
            $resolvedAzureRole = if ($_azureRoleNames.Count)   { @($_azureRoleNames)   } elseif ($existingEntry.AzureRoles)     { $existingEntry.AzureRoles     }

            if ($resolvedDirRoles)  { $entry.DirectoryRoles = $resolvedDirRoles  }
            if ($resolvedGroups)    { $entry.EntraIDGroups  = $resolvedGroups    }
            if ($resolvedAzureRole) { $entry.AzureRoles     = $resolvedAzureRole }

            $mapData[$TenantAlias] = $entry

            # Serialize to PSD1 with nested hashtable support
            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.AppendLine('@{')
            foreach ($kv in $mapData.GetEnumerator() | Sort-Object Key) {
                $v = $kv.Value
                [void]$sb.AppendLine("    '$($kv.Key)' = @{")
                # Support both legacy string values and current nested hashtable/OrderedDictionary entries
                $tenantIdVal = if ($v -is [System.Collections.IDictionary]) { $v.TenantId } else { $v }
                [void]$sb.AppendLine("        TenantId       = '$tenantIdVal'")
                if ($v -is [System.Collections.IDictionary]) {
                    foreach ($roleKey in 'DirectoryRoles', 'EntraIDGroups', 'AzureRoles') {
                        if ($v[$roleKey]) {
                            $vals = ($v[$roleKey] | ForEach-Object { "'$_'" }) -join ', '
                            [void]$sb.AppendLine("        $(($roleKey).PadRight(14)) = @($vals)")
                        }
                    }
                }
                [void]$sb.AppendLine('    }')
            }
            [void]$sb.Append('}')

            if ($PSCmdlet.ShouldProcess($TenantMapPath, "Write tenant alias '$TenantAlias'")) {
                $sb.ToString() | Set-Content -Path $TenantMapPath -Encoding UTF8
                Write-Host "TenantMap updated at $TenantMapPath" -ForegroundColor Green
            }
        }
    }

    # ── DefaultParameters ─────────────────────────────────────────────────────
    if ($DefaultParameters) {
        $profilePath = $PROFILE.CurrentUserAllHosts
        if (-not (Test-Path $profilePath)) {
            if ($PSCmdlet.ShouldProcess($profilePath, 'Create profile file')) {
                New-Item -ItemType File -Path $profilePath -Force | Out-Null
            }
        }

        $existingContent = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { '' }
        $marker          = '# Omnicit.PIM - DefaultParameters'
        $shouldWriteDP = $true

        if ($existingContent -match [regex]::Escape($marker)) {
            if (-not $Force) {
                Write-Warning "DefaultParameters block already exists in $profilePath. Use -Force to overwrite."
                $shouldWriteDP = $false
            } else {
                $existingContent = $existingContent -replace "(?s)$([regex]::Escape($marker)).*?# End Omnicit.PIM - DefaultParameters", ''
                Set-Content -Path $profilePath -Value $existingContent -Encoding UTF8
            }
        }

        $dpBlock = @"

$marker
`$PSDefaultParameterValues['Enable-OPIM*:Hours'] = $Duration
# End Omnicit.PIM - DefaultParameters
"@

        if ($shouldWriteDP -and $PSCmdlet.ShouldProcess($profilePath, "Append DefaultParameters block (Duration=$Duration)")) {
            Add-Content -Path $profilePath -Value $dpBlock
            Write-Host "DefaultParameters block written to $profilePath" -ForegroundColor Green
        }
    }

    } # end
}
