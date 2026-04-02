using namespace System.Collections.Generic
function Install-OPIMConfiguration {
    <#
    .SYNOPSIS
    Create a new tenant alias entry in the TenantMap.psd1 configuration file.
    .DESCRIPTION
    Initialises a new entry in the TenantMap.psd1 file used by Enable-OPIMMyRoles (alias: pim)
    to resolve tenant aliases and filter which roles/groups are activated per tenant.

    This cmdlet is for creating new aliases only. To update an existing alias use
    Set-OPIMConfiguration. To remove an alias use Remove-OPIMConfiguration. To read the
    current configuration use Get-OPIMConfiguration.

    Pipe eligible role and group objects from Get-OPIMDirectoryRole, Get-OPIMEntraIDGroup, or
    Get-OPIMAzureRole to store them as the default activation set for the tenant alias.

    All file operations support -WhatIf and -Confirm.
    .EXAMPLE
    Install-OPIMConfiguration -TenantAlias contoso -TenantId '00000000-0000-0000-0000-000000000000'
    Add a new tenant alias mapping in TenantMap.psd1. Activating with 'pim -TenantAlias contoso'
    will activate ALL eligible roles/groups for that tenant (no filter stored).
    .EXAMPLE
    Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>' -WhatIf
    Preview what the TenantMap write would do without making changes.
    .EXAMPLE
    Get-OPIMDirectoryRole | Where-Object { $_.roleDefinition.displayName -like 'Compliance*' } |
        Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>'
    Store specific directory roles as the default activation set for the new 'contoso' tenant alias.
    .EXAMPLE
    Get-OPIMEntraIDGroup | Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>'
    Store all eligible group assignments as the activation set for the new 'contoso' tenant alias.
    .EXAMPLE
    Get-OPIMAzureRole | Install-OPIMConfiguration -TenantAlias contoso -TenantId '<guid>'
    Store all eligible Azure roles as the activation set for the new 'contoso' tenant alias.
    .PARAMETER TenantAlias
    Short alias for the tenant (e.g. 'contoso'). Used with Enable-OPIMMyRoles -TenantAlias to select the tenant.
    Must not already exist in the TenantMap file. Use Set-OPIMConfiguration to update an existing alias.
    .PARAMETER TenantId
    Azure Tenant ID (GUID) that the alias maps to. Must be a valid GUID format.
    .PARAMETER TenantMapPath
    Path to the TenantMap.psd1 configuration file. Defaults to $env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1.
    .PARAMETER InputObject
    Role, group, or Azure role eligibility objects piped from Get-OPIMDirectoryRole, Get-OPIMEntraIDGroup, or Get-OPIMAzureRole.
    Objects not matching a known Omnicit.PIM type are silently ignored.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$TenantAlias,

        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
            ErrorMessage = "'{0}' does not look like a valid GUID.")]
        [string]$TenantId,

        [string]$TenantMapPath = "$env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1",

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

        if ($MapData.ContainsKey($TenantAlias)) {
            $Err = [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new("Tenant alias '$TenantAlias' already exists in $TenantMapPath. Use Set-OPIMConfiguration to update an existing alias."),
                'TenantAliasAlreadyExists',
                [System.Management.Automation.ErrorCategory]::ResourceExists,
                $TenantAlias
            )
            $Err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new("Tenant alias '$TenantAlias' already exists in $TenantMapPath. Use Set-OPIMConfiguration to update an existing alias.")
            $PSCmdlet.WriteError($Err)
            return
        }

        # ── Build the new entry ───────────────────────────────────────────────
        $Entry = [ordered]@{ TenantId = $TenantId }

        if ($_directoryRoleIds.Count) { $Entry.DirectoryRoles = @($_directoryRoleIds) }
        if ($_groupIds.Count)         { $Entry.EntraIDGroups  = @($_groupIds)         }
        if ($_azureRoleNames.Count)   { $Entry.AzureRoles     = @($_azureRoleNames)   }

        Write-Verbose "Adding new tenant alias '$TenantAlias' (TenantId: $TenantId)"
        foreach ($RoleKey in 'DirectoryRoles', 'EntraIDGroups', 'AzureRoles') {
            if ($Entry[$RoleKey]) {
                Write-Information "  $TenantAlias/$RoleKey : Adding $($Entry[$RoleKey].Count) item(s) - $($Entry[$RoleKey] -join ', ')"
            }
        }

        $MapData[$TenantAlias] = $Entry

        if ($PSCmdlet.ShouldProcess($TenantMapPath, "Add tenant alias '$TenantAlias'")) {
            Export-OPIMTenantMap -MapData $MapData -Path $TenantMapPath
            Write-Information "Added tenant alias '$TenantAlias' in $TenantMapPath"
        }
    }
}
