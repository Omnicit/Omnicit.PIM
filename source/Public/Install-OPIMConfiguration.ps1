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
    .PARAMETER TenantAlias
    Short alias for the tenant (e.g. 'contoso'). Used with Enable-OPIMMyRoles -TenantAlias to select the tenant.
    .PARAMETER TenantId
    Azure Tenant ID (GUID) that the alias maps to. Must be a valid GUID format.
    .PARAMETER TenantMapPath
    Path to the TenantMap.psd1 configuration file. Defaults to $env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1.
    .PARAMETER Force
    Overwrite an existing tenant alias entry including all stored role lists without the duplicate-entry warning.
    .PARAMETER InputObject
    Role, group, or Azure role eligibility objects piped from Get-OPIMDirectoryRole, Get-OPIMEntraIDGroup, or Get-OPIMAzureRole. Objects not matching a known Omnicit.PIM type are silently ignored.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$TenantAlias,

        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
            ErrorMessage = "'{0}' does not look like a valid GUID.")]
        [string]$TenantId,

        [string]$TenantMapPath = "$env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1",

        [Switch]$Force,

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
        $TenantMapDir = Split-Path $TenantMapPath -Parent
        if (-not (Test-Path $TenantMapDir)) {
            if ($PSCmdlet.ShouldProcess($TenantMapDir, 'Create TenantMap directory')) {
                New-Item -ItemType Directory -Path $TenantMapDir -Force | Out-Null
            }
        }

        $MapData = if (Test-Path $TenantMapPath) {
            Import-PowerShellDataFile $TenantMapPath
        } else {
            @{}
        }

        $IsNew = -not $MapData.ContainsKey($TenantAlias)

        if (-not $IsNew -and -not $Force) {
            Write-Warning "Tenant alias '$TenantAlias' already exists in $TenantMapPath. Use -Force to overwrite."
            return
        }

        # ── Build the new entry ───────────────────────────────────────────────
        # Categories not supplied via pipeline retain their existing stored values.
        $ExistingEntry = if ($MapData[$TenantAlias] -is [hashtable]) { $MapData[$TenantAlias] } else { @{} }

        $Entry = [ordered]@{ TenantId = $TenantId }

        $ResolvedDirRoles  = if ($_directoryRoleIds.Count) { @($_directoryRoleIds) } elseif ($ExistingEntry.DirectoryRoles) { @($ExistingEntry.DirectoryRoles) }
        $ResolvedGroups    = if ($_groupIds.Count)         { @($_groupIds)         } elseif ($ExistingEntry.EntraIDGroups)  { @($ExistingEntry.EntraIDGroups)  }
        $ResolvedAzureRole = if ($_azureRoleNames.Count)   { @($_azureRoleNames)   } elseif ($ExistingEntry.AzureRoles)     { @($ExistingEntry.AzureRoles)     }

        if ($ResolvedDirRoles)  { $Entry.DirectoryRoles = $ResolvedDirRoles  }
        if ($ResolvedGroups)    { $Entry.EntraIDGroups  = $ResolvedGroups    }
        if ($ResolvedAzureRole) { $Entry.AzureRoles     = $ResolvedAzureRole }

        # ── Verbose diff report ───────────────────────────────────────────────
        if ($IsNew) {
            Write-Verbose "Adding new tenant alias '$TenantAlias' (TenantId: $TenantId)"
            foreach ($RoleKey in 'DirectoryRoles', 'EntraIDGroups', 'AzureRoles') {
                if ($Entry[$RoleKey]) {
                    Write-Information "  $TenantAlias/$RoleKey : Adding $($Entry[$RoleKey].Count) item(s) - $($Entry[$RoleKey] -join ', ')"
                }
            }
        } else {
            $OldTenantId = if ($ExistingEntry.TenantId) { $ExistingEntry.TenantId } else { [string]$MapData[$TenantAlias] }
            Write-Verbose "Updating tenant alias '$TenantAlias'"
            if ($OldTenantId -ne $TenantId) {
                Write-Information "  $TenantAlias/TenantId : $OldTenantId  ->  $TenantId"
            }
            foreach ($RoleKey in 'DirectoryRoles', 'EntraIDGroups', 'AzureRoles') {
                $OldVals = [string[]]@($ExistingEntry[$RoleKey])
                $NewVals = [string[]]@($Entry[$RoleKey])
                $Added   = $NewVals | Where-Object { $_ -and $_ -notin $OldVals }
                $Removed = $OldVals | Where-Object { $_ -and $_ -notin $NewVals }
                $Kept    = $NewVals | Where-Object { $_ -and $_ -in $OldVals }
                if ($Added)   { Write-Information "  $TenantAlias/$RoleKey : Adding   $($Added.Count) item(s) - $($Added   -join ', ')" }
                if ($Removed) { Write-Information "  $TenantAlias/$RoleKey : Removing $($Removed.Count) item(s) - $($Removed -join ', ')" }
                if ($Kept -and -not $Added -and -not $Removed) {
                    Write-Verbose "  $TenantAlias/$RoleKey : No changes ($($Kept.Count) item(s) unchanged)"
                }
            }
        }

        $MapData[$TenantAlias] = $Entry

        # ── Serialize to PSD1 ─────────────────────────────────────────────────
        $Sb = [System.Text.StringBuilder]::new()
        [void]$Sb.AppendLine('@{')
        foreach ($Kv in $MapData.GetEnumerator() | Sort-Object Key) {
            $V = $Kv.Value
            [void]$Sb.AppendLine("    '$($Kv.Key)' = @{")
            # Support both legacy flat-string format and current nested hashtable/OrderedDictionary
            $TenantIdVal = if ($V -is [System.Collections.IDictionary]) { $V.TenantId } else { $V }
            [void]$Sb.AppendLine("        TenantId       = '$TenantIdVal'")
            if ($V -is [System.Collections.IDictionary]) {
                foreach ($RoleKey in 'DirectoryRoles', 'EntraIDGroups', 'AzureRoles') {
                    if ($V[$RoleKey]) {
                        $Vals = ($V[$RoleKey] | ForEach-Object { "'$_'" }) -join ', '
                        [void]$Sb.AppendLine("        $(($RoleKey).PadRight(14)) = @($Vals)")
                    }
                }
            }
            [void]$Sb.AppendLine('    }')
        }
        [void]$Sb.AppendLine('}')

        $Action = if ($IsNew) { 'Add' } else { 'Update' }
        if ($PSCmdlet.ShouldProcess($TenantMapPath, "$Action tenant alias '$TenantAlias'")) {
            $Sb.ToString() | Set-Content -Path $TenantMapPath -Encoding UTF8
            Write-Information "$($Action)d tenant alias '$TenantAlias' in $TenantMapPath"
        }
    }
}
