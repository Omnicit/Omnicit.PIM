using namespace System.Collections.Generic
function Set-OPIMConfiguration {
    <#
    .SYNOPSIS
    Update an existing tenant alias entry in the TenantMap configuration file.
    .DESCRIPTION
    Updates an existing entry in the TenantMap.psd1 file managed by Install-OPIMConfiguration.
    Use this cmdlet to change the TenantId for an alias or to replace the stored role/group
    activation lists by piping new objects from Get-OPIMDirectoryRole, Get-OPIMEntraIDGroup,
    or Get-OPIMAzureRole.

    Categories not supplied via pipeline retain their existing stored values. To remove a stored
    list for a category, use Remove-OPIMConfiguration followed by Install-OPIMConfiguration, or
    edit the TenantMap.psd1 file directly.

    All file operations support -WhatIf and -Confirm.

    Use Install-OPIMConfiguration to create a new alias. Set-OPIMConfiguration requires the alias
    to exist and will emit a non-terminating error if it does not.
    .EXAMPLE
    Set-OPIMConfiguration -TenantAlias contoso -TenantId '00000000-0000-0000-0000-000000000000'
    Update only the TenantId for the 'contoso' alias, preserving all stored role lists.
    .EXAMPLE
    Get-OPIMDirectoryRole | Where-Object { $_.roleDefinition.displayName -like 'Compliance*' } |
        Set-OPIMConfiguration -TenantAlias contoso
    Replace the stored DirectoryRoles list for 'contoso' with filtered directory roles.
    .EXAMPLE
    Get-OPIMEntraIDGroup | Set-OPIMConfiguration -TenantAlias contoso
    Replace the stored EntraIDGroups list for 'contoso' with all eligible group assignments.
    .EXAMPLE
    Get-OPIMAzureRole | Set-OPIMConfiguration -TenantAlias contoso -WhatIf
    Preview what the AzureRoles update would write without making changes.
    .PARAMETER TenantAlias
    Short alias for the tenant to update. Must already exist in the TenantMap file.
    .PARAMETER TenantId
    New Azure Tenant ID (GUID) to store for this alias. When omitted the existing TenantId is preserved.
    .PARAMETER TenantMapPath
    Path to the TenantMap.psd1 configuration file. Defaults to .config/Omnicit.PIM/TenantMap.psd1
    under your home folder ($HOME; on Windows the same file as before, under $env:USERPROFILE).
    .PARAMETER InputObject
    Role, group, or Azure role eligibility objects piped from Get-OPIMDirectoryRole, Get-OPIMEntraIDGroup,
    or Get-OPIMAzureRole. The piped category replaces the stored list; categories not supplied via pipeline
    retain their existing values. A directory role is stored with its scope, as
    roleDefinitionId|directoryScopeId, so pim and unpim act on it only at that scope; a group is stored as
    groupId_accessId, and an Azure role as the Name of its eligibility schedule. An active Azure role (from
    Get-OPIMAzureRole -Activated, or an active row of -All) is stored by the eligibility schedule it was
    activated from; one that names none is written as the error LinkedEligibilityNotFound and not stored,
    and the other piped objects still are. Each key is stored once, without regard to letter case, in the
    order first piped. Objects not matching a known Omnicit.PIM type are silently ignored.
    #>
    [Alias('Set-PIMConfig')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$TenantAlias,

        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
            ErrorMessage = "'{0}' does not look like a valid GUID.")]
        [string]$TenantId,

        [string]$TenantMapPath = (Join-Path $HOME '.config/Omnicit.PIM/TenantMap.psd1'),

        [Parameter(ValueFromPipeline)]
        $InputObject
    )

    begin {
        # One ordered list per pillar, and a case-insensitive set beside it so that each key is stored
        # once (Get-OPIM* -All returns the eligible and the active post of one role).
        $StoredKeys = @{
            Directory = [List[string]]::new()
            Group     = [List[string]]::new()
            Azure     = [List[string]]::new()
        }
        $SeenKeys = @{
            Directory = [HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            Group     = [HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            Azure     = [HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        }
    }
    process {
        if ($null -eq $InputObject) { return }
        $Pillar = switch ($true) {
            { $InputObject.PSTypeNames -contains 'Omnicit.PIM.DirectoryEligibilitySchedule' -or
              $InputObject.PSTypeNames -contains 'Omnicit.PIM.DirectoryAssignmentScheduleInstance' } {
                'Directory'; break
            }
            { $InputObject.PSTypeNames -contains 'Omnicit.PIM.GroupEligibilitySchedule' -or
              $InputObject.PSTypeNames -contains 'Omnicit.PIM.GroupAssignmentScheduleInstance' } {
                'Group'; break
            }
            { $null -ne $InputObject.RoleDefinitionId -and $null -ne $InputObject.ScopeId } {
                'Azure'; break
            }
        }
        if (-not $Pillar) { return }
        # OPIM-22: an active Azure role that names no eligibility is refused by the key helper with
        # LinkedEligibilityNotFound; it is written and skipped, and the other piped objects are stored.
        try {
            $Key = ConvertTo-OPIMTenantMapKey -Pillar $Pillar -InputObject $InputObject -ErrorAction Stop
        } catch {
            Remove-OPIMErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        if ($SeenKeys[$Pillar].Add($Key)) { $StoredKeys[$Pillar].Add($Key) }
    }
    end {
        if (-not (Test-Path $TenantMapPath)) {
            $Err = [System.Management.Automation.ErrorRecord]::new(
                [System.IO.FileNotFoundException]::new("TenantMap file not found at '$TenantMapPath'. Run Install-OPIMConfiguration to create it."),
                'TenantMapNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $TenantMapPath
            )
            $Err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new("TenantMap file not found at '$TenantMapPath'. Run Install-OPIMConfiguration to create it.")
            $PSCmdlet.WriteError($Err)
            return
        }

        $MapData = Import-PowerShellDataFile $TenantMapPath

        if (-not $MapData.ContainsKey($TenantAlias)) {
            $Available = ($MapData.Keys | Sort-Object) -join ', '
            $Err = [System.Management.Automation.ErrorRecord]::new(
                [System.Collections.Generic.KeyNotFoundException]::new("Tenant alias '$TenantAlias' not found in '$TenantMapPath'. Use Install-OPIMConfiguration to add a new alias. Available aliases: $Available"),
                'TenantAliasNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $TenantAlias
            )
            $Err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new("Tenant alias '$TenantAlias' not found in '$TenantMapPath'. Use Install-OPIMConfiguration to add a new alias. Available aliases: $Available")
            $PSCmdlet.WriteError($Err)
            return
        }

        # OPIM-20: an alias stored in the 0.4-era string form (contoso = '<tenant id>') is not a dictionary;
        # its value IS the tenant id, so carry it over instead of starting from an empty entry (which wrote
        # TenantId = '' and sent pim -TenantAlias to 'organizations').
        $Stored = $MapData[$TenantAlias]
        $ExistingEntry = if ($Stored -is [System.Collections.IDictionary]) { $Stored } else { @{ TenantId = [string]$Stored } }

        $ResolvedTenantId  = if ($TenantId)                  { $TenantId                  } else { $ExistingEntry.TenantId }
        $ResolvedDirRoles  = if ($StoredKeys.Directory.Count) { @($StoredKeys.Directory) } elseif ($ExistingEntry.DirectoryRoles) { @($ExistingEntry.DirectoryRoles) }
        $ResolvedGroups    = if ($StoredKeys.Group.Count)     { @($StoredKeys.Group)     } elseif ($ExistingEntry.EntraIDGroups)  { @($ExistingEntry.EntraIDGroups)  }
        $ResolvedAzureRole = if ($StoredKeys.Azure.Count)     { @($StoredKeys.Azure)     } elseif ($ExistingEntry.AzureRoles)     { @($ExistingEntry.AzureRoles)     }

        $Entry = [ordered]@{ TenantId = $ResolvedTenantId }
        if ($ResolvedDirRoles)  { $Entry.DirectoryRoles = $ResolvedDirRoles  }
        if ($ResolvedGroups)    { $Entry.EntraIDGroups  = $ResolvedGroups    }
        if ($ResolvedAzureRole) { $Entry.AzureRoles     = $ResolvedAzureRole }

        Write-Verbose "Updating tenant alias '$TenantAlias' in $TenantMapPath"

        # -- Get tenant display name for the confirmation prompt (best-effort) ---
        $TenantInfo = Get-OPIMCurrentTenantInfo
        $TenantDisplayName = if ($TenantInfo.DisplayName) { $TenantInfo.DisplayName } else { 'N/A' }

        $MapData[$TenantAlias] = $Entry

        if ($PSCmdlet.ShouldProcess($TenantMapPath, "Update alias '$TenantAlias' -> tenant '$TenantDisplayName' ($ResolvedTenantId)")) {
            Export-OPIMTenantMap -MapData $MapData -Path $TenantMapPath
            Write-Information "Updated tenant alias '$TenantAlias' in $TenantMapPath"
        }
    }
}
