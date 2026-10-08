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
    Add a new tenant alias mapping in TenantMap.psd1, with no roles or groups stored yet.
    'pim -TenantAlias contoso' then activates nothing for that tenant: it skips every category the
    entry does not list, with a verbose message. Pipe roles or groups to Set-OPIMConfiguration to
    add them, or use pim -AllEligible to activate everything eligible.
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
    Azure Tenant ID (GUID) that the alias maps to. Must be a valid GUID format. When omitted, the
    tenant Omnicit.PIM is signed in to is used (Connect-OPIM, or the first role or group command);
    without a sign-in of the module the command writes the error TenantIdNotResolvable and stores
    nothing. A Microsoft Graph session started with Connect-MgGraph outside the module is never
    used. A TenantId that differs from the signed-in tenant writes a warning, and the confirmation
    shows the tenant's display name only for the signed-in tenant.
    .PARAMETER TenantMapPath
    Path to the TenantMap.psd1 configuration file. Defaults to .config/Omnicit.PIM/TenantMap.psd1
    under your home folder ($HOME; on Windows the same file as before, under $env:USERPROFILE).
    .PARAMETER InputObject
    Role, group, or Azure role eligibility objects piped from Get-OPIMDirectoryRole, Get-OPIMEntraIDGroup, or Get-OPIMAzureRole.
    A directory role is stored with its scope, as roleDefinitionId|directoryScopeId, so pim and unpim
    act on it only at that scope; a group is stored as groupId_accessId, and an Azure role as the
    Name of its eligibility schedule. An active Azure role (from Get-OPIMAzureRole -Activated, or an
    active row of -All) is stored as the eligibility schedule it was activated from plus its own
    scope (Name|ScopeId), and pim activates it only while that eligibility is at that scope. One
    activated at another scope than its eligibility is refused when its link names the
    eligibility's scope -- the error LinkedEligibilityNotFound, and nothing stored -- and otherwise
    matches no eligible role, so pim activates nothing for it; one that names no eligibility is
    refused the same way. Pipe the eligible role to activate it at its own scope. The other piped
    objects still are stored. Each key is stored once, without regard to letter case, in the order
    first piped; an eligible role and its activation at its own scope are one key. Objects not
    matching a known Omnicit.PIM type are silently ignored.
    #>
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
                # roleDefinitionId|directoryScopeId -- the role at the one scope it was piped at
                'Directory'; break
            }
            { $InputObject.PSTypeNames -contains 'Omnicit.PIM.GroupEligibilitySchedule' -or
              $InputObject.PSTypeNames -contains 'Omnicit.PIM.GroupAssignmentScheduleInstance' } {
                # groupId_accessId -- stable and encodes member vs owner
                'Group'; break
            }
            { $null -ne $InputObject.RoleDefinitionId -and $null -ne $InputObject.ScopeId } {
                # Azure role from Get-OPIMAzureRole: the Name of its eligibility schedule, or for an
                # active role the eligibility it was activated from and its own scope
                'Azure'; break
            }
        }
        if (-not $Pillar) { return }
        # OPIM-22: an active Azure role that names no eligibility, or names it at another scope, is refused
        # by the key helper with LinkedEligibilityNotFound; it is written and skipped, and the other piped
        # objects are stored.
        try {
            $Key = ConvertTo-OPIMTenantMapKey -Pillar $Pillar -InputObject $InputObject -ErrorAction Stop
            # An Azure eligibility (stored as its Name) and an active role of it at its own scope (stored as
            # Name|ScopeId) are one post, so both are seen under the scoped key and the first piped is stored.
            $SeenKey = ConvertTo-OPIMTenantMapKey -Pillar $Pillar -InputObject $InputObject -WithScope -ErrorAction Stop
        } catch {
            Remove-OPIMErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        if ($SeenKeys[$Pillar].Add($SeenKey)) { $StoredKeys[$Pillar].Add($Key) }
    }
    end {
        # -- Resolve TenantId from the module's own sign-in when not supplied ---
        # OPIM-45: the tenant of the module's sign-in (its Graph token), never the tenant of a Graph
        # session another Connect-MgGraph started; without a sign-in of the module, refuse.
        $TenantInfo = Get-OPIMCurrentTenantInfo
        [string]$SessionTenantId = $TenantInfo.TenantId
        if (-not $TenantId) {
            if (-not $SessionTenantId) {
                $Message = 'No -TenantId was supplied and Omnicit.PIM holds no sign-in. ' +
                    'Either give -TenantId, or run Connect-OPIM first. ' +
                    'A session started with Connect-MgGraph outside the module is not used.'
                $Err = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new($Message),
                    'TenantIdNotResolvable',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $Err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Message)
                $PSCmdlet.WriteError($Err)
                return
            }
            $TenantId = $SessionTenantId
            Write-Verbose "TenantId taken from the sign-in of Omnicit.PIM: $TenantId"
        } elseif ($SessionTenantId -and -not [string]::Equals($TenantId, $SessionTenantId, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Warning "The provided TenantId ($TenantId) differs from the tenant Omnicit.PIM is signed in to ($SessionTenantId). Confirm you are configuring the correct tenant."
        }
        # The display name belongs to the session tenant, so it is shown only for that tenant.
        $TenantDisplayName = if ($TenantInfo.DisplayName -and $SessionTenantId -and
            [string]::Equals($TenantId, $SessionTenantId, [System.StringComparison]::OrdinalIgnoreCase)) {
            $TenantInfo.DisplayName
        } else {
            'N/A'
        }

        # -- Ensure TenantMap directory and file exist -------------------------
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

        # -- Build the new entry -----------------------------------------------
        $Entry = [ordered]@{ TenantId = $TenantId }

        if ($StoredKeys.Directory.Count) { $Entry.DirectoryRoles = @($StoredKeys.Directory) }
        if ($StoredKeys.Group.Count)     { $Entry.EntraIDGroups  = @($StoredKeys.Group)     }
        if ($StoredKeys.Azure.Count)     { $Entry.AzureRoles     = @($StoredKeys.Azure)     }

        Write-Verbose "Adding new tenant alias '$TenantAlias' (TenantId: $TenantId)"
        foreach ($RoleKey in 'DirectoryRoles', 'EntraIDGroups', 'AzureRoles') {
            if ($Entry[$RoleKey]) {
                Write-Information "  $TenantAlias/$RoleKey : Adding $($Entry[$RoleKey].Count) item(s) - $($Entry[$RoleKey] -join ', ')"
            }
        }

        $MapData[$TenantAlias] = $Entry

        if ($PSCmdlet.ShouldProcess($TenantMapPath, "Add alias '$TenantAlias' for tenant '$TenantDisplayName' ($TenantId)")) {
            Export-OPIMTenantMap -MapData $MapData -Path $TenantMapPath
            Write-Information "Added tenant alias '$TenantAlias' in $TenantMapPath"
        }
    }
}
