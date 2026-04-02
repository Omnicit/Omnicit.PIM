function Get-OPIMConfiguration {
    <#
    .SYNOPSIS
    Retrieve the TenantMap configuration file and its contents.
    .DESCRIPTION
    Reads the TenantMap.psd1 file managed by Install-OPIMConfiguration and returns one
    typed PSCustomObject per tenant alias. Each object exposes the TenantAlias, TenantId,
    and any stored role/group filter lists (DirectoryRoles, EntraIDGroups, AzureRoles).

    Use -TenantAlias to retrieve a single entry. Without it all aliases are returned.
    .EXAMPLE
    Get-OPIMConfiguration
    Return all tenant aliases from the default TenantMap.psd1.
    .EXAMPLE
    Get-OPIMConfiguration -TenantAlias contoso
    Return only the 'contoso' entry from the default TenantMap.psd1.
    .EXAMPLE
    Get-OPIMConfiguration -TenantMapPath 'D:\config\MyTenants.psd1'
    Return all entries from a custom path.
    .PARAMETER TenantAlias
    Optional. Short alias to filter the output to a single entry.
    .PARAMETER TenantMapPath
    Path to the TenantMap.psd1 configuration file. Defaults to $env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1.
    #>
    [Alias('Get-PIMConfig')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$TenantAlias,

        [string]$TenantMapPath = "$env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1"
    )

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

    if ($TenantAlias) {
        if (-not $MapData.ContainsKey($TenantAlias)) {
            $Available = ($MapData.Keys | Sort-Object) -join ', '
            $Err = [System.Management.Automation.ErrorRecord]::new(
                [System.Collections.Generic.KeyNotFoundException]::new("Tenant alias '$TenantAlias' not found in '$TenantMapPath'. Available aliases: $Available"),
                'TenantAliasNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $TenantAlias
            )
            $Err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new("Tenant alias '$TenantAlias' not found in '$TenantMapPath'. Available aliases: $Available")
            $PSCmdlet.WriteError($Err)
            return
        }

        $Out = [PSCustomObject]@{
            TenantAlias    = $TenantAlias
            TenantId       = $MapData[$TenantAlias].TenantId
            DirectoryRoles = $MapData[$TenantAlias].DirectoryRoles
            EntraIDGroups  = $MapData[$TenantAlias].EntraIDGroups
            AzureRoles     = $MapData[$TenantAlias].AzureRoles
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.TenantConfiguration')
        $Out
        return
    }

    foreach ($Kv in $MapData.GetEnumerator() | Sort-Object Key) {
        $V   = $Kv.Value
        $Out = [PSCustomObject]@{
            TenantAlias    = $Kv.Key
            TenantId       = if ($V -is [System.Collections.IDictionary]) { $V.TenantId } else { [string]$V }
            DirectoryRoles = if ($V -is [System.Collections.IDictionary]) { $V.DirectoryRoles } else { $null }
            EntraIDGroups  = if ($V -is [System.Collections.IDictionary]) { $V.EntraIDGroups } else { $null }
            AzureRoles     = if ($V -is [System.Collections.IDictionary]) { $V.AzureRoles } else { $null }
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.TenantConfiguration')
        $Out
    }
}
