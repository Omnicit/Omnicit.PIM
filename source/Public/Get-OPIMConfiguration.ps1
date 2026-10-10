function Get-OPIMConfiguration {
    <#
    .SYNOPSIS
    Retrieve the TenantMap configuration file and its contents.
    .DESCRIPTION
    Reads the TenantMap.psd1 file managed by Install-OPIMConfiguration and returns one
    typed PSCustomObject per tenant alias. Each object exposes the TenantAlias, TenantId, the
    Environment (the cloud the alias signs in to), and any stored role/group filter lists
    (DirectoryRoles, EntraIDGroups, AzureRoles).

    Environment is the cloud as the file holds it, such as USGov, and Global for an alias that
    stores none, which signs in to the global cloud. A cloud written in the file that Omnicit.PIM
    does not know is shown as written; Connect-OPIM, pim and unpim refuse it.

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
    Path to the TenantMap.psd1 configuration file. Defaults to .config/Omnicit.PIM/TenantMap.psd1
    under your home folder ($HOME; on Windows the same file as before, under $env:USERPROFILE).
    #>
    [Alias('Get-PIMConfig')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$TenantAlias,

        [string]$TenantMapPath = (Join-Path $HOME '.config/Omnicit.PIM/TenantMap.psd1')
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

        # A12: the cloud as stored; the entry can also be the old string form, which stores none.
        $V = $MapData[$TenantAlias]
        $Out = [PSCustomObject]@{
            TenantAlias    = $TenantAlias
            TenantId       = $MapData[$TenantAlias].TenantId
            Environment    = if ($V -is [System.Collections.IDictionary] -and -not [string]::IsNullOrWhiteSpace([string]$V['Environment'])) { [string]$V['Environment'] } else { 'Global' }
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
            Environment    = if ($V -is [System.Collections.IDictionary] -and -not [string]::IsNullOrWhiteSpace([string]$V['Environment'])) { [string]$V['Environment'] } else { 'Global' }
            DirectoryRoles = if ($V -is [System.Collections.IDictionary]) { $V.DirectoryRoles } else { $null }
            EntraIDGroups  = if ($V -is [System.Collections.IDictionary]) { $V.EntraIDGroups } else { $null }
            AzureRoles     = if ($V -is [System.Collections.IDictionary]) { $V.AzureRoles } else { $null }
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.TenantConfiguration')
        $Out
    }
}
