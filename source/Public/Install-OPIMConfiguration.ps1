using namespace System.Collections.Generic
function Install-OPIMConfiguration {
    <#
    .SYNOPSIS
    Create or update a TenantMap.psd1 mapping tenant aliases to tenant IDs and PIM role sets.
    .DESCRIPTION
    Manages the TenantMap.psd1 file used by Enable-OPIMMyRoles (alias: pim) to resolve
    tenant aliases and filter which roles/groups are activated per tenant.

    Pipe eligible role and group objects from Get-OPIMDirectoryRole, Get-OPIMEntraIDGroup, or
    Get-OPIMAzureRole to store them as the default activation set for the tenant alias.
    When roles are piped for a tenant that already exists, the stored list for that category
    is replaced. Categories not supplied in the pipeline retain their existing stored values.

    All file operations support -WhatIf and -Confirm.
    .EXAMPLE
    Install-OPIMConfiguration -TenantAlias contoso -TenantId '00000000-0000-0000-0000-000000000000'
    Add a tenant alias mapping in TenantMap.psd1. Activating with 'pim -TenantAlias contoso'
    will activate ALL eligible roles/groups for that tenant (no filter stored).
    .EXAMPLE
    Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>' -WhatIf
    Preview what the TenantMap write would do without making changes.
    .EXAMPLE
    Get-OPIMDirectoryRole | Where-Object { $_.roleDefinition.displayName -like 'Compliance*' } |
        Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>'
    Store specific directory roles as the default activation set for the 'contoso' tenant.
    .EXAMPLE
    Get-OPIMEntraIDGroup | Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>'
    Store all eligible group assignments as the activation set for the 'contoso' tenant.
    .EXAMPLE
    Get-OPIMAzureRole | Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>'
    Store all eligible Azure roles as the activation set for the 'contoso' tenant.
    .EXAMPLE
    Get-OPIMDirectoryRole | Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>' -Force
    Replace the existing DirectoryRoles list for 'contoso', keeping other stored categories.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # The short alias for the tenant (e.g. 'contoso'). Used with 'pim -TenantAlias <alias>'.
        [Parameter(Mandatory)]
        [string]$TenantAlias,

        # The Azure Tenant ID (GUID) for the alias.
        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
            ErrorMessage = "'{0}' does not look like a valid GUID.")]
        [string]$TenantId,

        # Path to the TenantMap.psd1 file. Defaults to $env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1.
        [string]$TenantMapPath = "$env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1",

        # Overwrite an existing entry including all stored role lists without the duplicate-entry warning.
        [Switch]$Force,

        # Role, group, or Azure role eligibility objects piped from Get-OPIMDirectoryRole,
        # Get-OPIMEntraIDGroup, or Get-OPIMAzureRole. Only objects matching a known OPIM type
        # are collected; others are silently ignored.
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
        # ── Ensure TenantMap directory and file exist ─────────────────────────
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

        $isNew = -not $mapData.ContainsKey($TenantAlias)

        if (-not $isNew -and -not $Force) {
            Write-Warning "Tenant alias '$TenantAlias' already exists in $TenantMapPath. Use -Force to overwrite."
            return
        }

        # ── Build the new entry ───────────────────────────────────────────────
        # Categories not supplied via pipeline retain their existing stored values.
        $existingEntry = if ($mapData[$TenantAlias] -is [hashtable]) { $mapData[$TenantAlias] } else { @{} }

        $entry = [ordered]@{ TenantId = $TenantId }

        $resolvedDirRoles  = if ($_directoryRoleIds.Count) { @($_directoryRoleIds) } elseif ($existingEntry.DirectoryRoles) { @($existingEntry.DirectoryRoles) }
        $resolvedGroups    = if ($_groupIds.Count)         { @($_groupIds)         } elseif ($existingEntry.EntraIDGroups)  { @($existingEntry.EntraIDGroups)  }
        $resolvedAzureRole = if ($_azureRoleNames.Count)   { @($_azureRoleNames)   } elseif ($existingEntry.AzureRoles)     { @($existingEntry.AzureRoles)     }

        if ($resolvedDirRoles)  { $entry.DirectoryRoles = $resolvedDirRoles  }
        if ($resolvedGroups)    { $entry.EntraIDGroups  = $resolvedGroups    }
        if ($resolvedAzureRole) { $entry.AzureRoles     = $resolvedAzureRole }

        # ── Verbose diff report ───────────────────────────────────────────────
        if ($isNew) {
            Write-Verbose "Adding new tenant alias '$TenantAlias' (TenantId: $TenantId)"
            foreach ($roleKey in 'DirectoryRoles', 'EntraIDGroups', 'AzureRoles') {
                if ($entry[$roleKey]) {
                    Write-Host "  $TenantAlias/$roleKey : Adding $($entry[$roleKey].Count) item(s)  — $($entry[$roleKey] -join ', ')" -ForegroundColor Green
                }
            }
        } else {
            $oldTenantId = if ($existingEntry.TenantId) { $existingEntry.TenantId } else { [string]$mapData[$TenantAlias] }
            Write-Verbose "Updating tenant alias '$TenantAlias'"
            if ($oldTenantId -ne $TenantId) {
                Write-Host "  $TenantAlias/TenantId : $oldTenantId  ->  $TenantId" -ForegroundColor Yellow
            }
            foreach ($roleKey in 'DirectoryRoles', 'EntraIDGroups', 'AzureRoles') {
                $oldVals = [string[]]@($existingEntry[$roleKey])
                $newVals = [string[]]@($entry[$roleKey])
                $added   = $newVals | Where-Object { $_ -and $_ -notin $oldVals }
                $removed = $oldVals | Where-Object { $_ -and $_ -notin $newVals }
                $kept    = $newVals | Where-Object { $_ -and $_ -in $oldVals }
                if ($added)   { Write-Host "  $TenantAlias/$roleKey : Adding   $($added.Count) item(s)   — $($added   -join ', ')" -ForegroundColor Green  }
                if ($removed) { Write-Host "  $TenantAlias/$roleKey : Removing $($removed.Count) item(s) — $($removed -join ', ')" -ForegroundColor Red    }
                if ($kept -and -not $added -and -not $removed) {
                    Write-Verbose "  $TenantAlias/$roleKey : No changes ($($kept.Count) item(s) unchanged)"
                }
            }
        }

        $mapData[$TenantAlias] = $entry

        # ── Serialize to PSD1 ─────────────────────────────────────────────────
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine('@{')
        foreach ($kv in $mapData.GetEnumerator() | Sort-Object Key) {
            $v = $kv.Value
            [void]$sb.AppendLine("    '$($kv.Key)' = @{")
            # Support both legacy flat-string format and current nested hashtable/OrderedDictionary
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
        [void]$sb.AppendLine('}')

        $action = if ($isNew) { 'Add' } else { 'Update' }
        if ($PSCmdlet.ShouldProcess($TenantMapPath, "$action tenant alias '$TenantAlias'")) {
            $sb.ToString() | Set-Content -Path $TenantMapPath -Encoding UTF8
            Write-Host "$($action)d tenant alias '$TenantAlias' in $TenantMapPath" -ForegroundColor Green
        }
    }
}
