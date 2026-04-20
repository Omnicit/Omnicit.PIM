function Export-OPIMTenantMap {
    <#
    .SYNOPSIS
    Serializes a TenantMap hashtable to PSD1 format and writes it to disk.

    .DESCRIPTION
    Shared internal helper used by Install-OPIMConfiguration, Set-OPIMConfiguration, and
    Remove-OPIMConfiguration to serialize the in-memory TenantMap to a PowerShell data file.
    All entries are sorted alphabetically by alias key.

    .PARAMETER MapData
    The full TenantMap hashtable to serialize. Each value must be a hashtable with at minimum
    a TenantId key. Optional keys: DirectoryRoles, EntraIDGroups, AzureRoles (each an array).

    .PARAMETER Path
    Absolute path to the target .psd1 file.

    .EXAMPLE
    Export-OPIMTenantMap -MapData $MapData -Path "$env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1"
    Serialize the in-memory tenant map hashtable to the default PSD1 configuration file.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$MapData,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $StringBuilder = [System.Text.StringBuilder]::new()
    [void]$StringBuilder.AppendLine('@{')
    foreach ($Kv in $MapData.GetEnumerator() | Sort-Object Key) {
        $ConfigValue = $Kv.Value
        [void]$StringBuilder.AppendLine("    '$($Kv.Key)' = @{")
        # Support both legacy flat-string format and current nested hashtable/OrderedDictionary
        $TenantIdVal = if ($ConfigValue -is [System.Collections.IDictionary]) { $ConfigValue.TenantId } else { $ConfigValue }
        [void]$StringBuilder.AppendLine("        TenantId       = '$TenantIdVal'")
        if ($ConfigValue -is [System.Collections.IDictionary]) {
            foreach ($RoleKey in 'DirectoryRoles', 'EntraIDGroups', 'AzureRoles') {
                if ($ConfigValue[$RoleKey]) {
                    $RoleValues = ($ConfigValue[$RoleKey] | ForEach-Object { "'$_'" }) -join ', '
                    [void]$StringBuilder.AppendLine("        $(($RoleKey).PadRight(14)) = @($RoleValues)")
                }
            }
        }
        [void]$StringBuilder.AppendLine('    }')
    }
    [void]$StringBuilder.AppendLine('}')

    $StringBuilder.ToString() | Set-Content -Path $Path -Encoding UTF8
}
