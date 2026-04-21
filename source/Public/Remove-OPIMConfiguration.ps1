function Remove-OPIMConfiguration {
    <#
    .SYNOPSIS
    Remove a tenant alias entry from the TenantMap configuration file.
    .DESCRIPTION
    Removes a single tenant alias from the TenantMap.psd1 file managed by
    Install-OPIMConfiguration, then re-serializes the remaining entries.

    If the alias does not exist a non-terminating error is emitted. If the file does not
    exist a non-terminating error is emitted. The remaining entries in the file are preserved.

    All file operations support -WhatIf and -Confirm.
    .EXAMPLE
    Remove-OPIMConfiguration -TenantAlias contoso
    Remove the 'contoso' entry from the default TenantMap.psd1.
    .EXAMPLE
    Remove-OPIMConfiguration -TenantAlias contoso -WhatIf
    Preview the removal without making changes.
    .EXAMPLE
    Remove-OPIMConfiguration -TenantAlias contoso -TenantMapPath 'D:\config\MyTenants.psd1'
    Remove the 'contoso' entry from a custom TenantMap file.
    .PARAMETER TenantAlias
    Short alias to remove. Must already exist in the TenantMap file.
    .PARAMETER TenantMapPath
    Path to the TenantMap.psd1 configuration file. Defaults to $env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1.
    #>
    [Alias('Remove-PIMConfig')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
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

    $StoredEntry    = $MapData[$TenantAlias]
    $StoredTenantId = if ($StoredEntry -is [System.Collections.IDictionary]) { $StoredEntry.TenantId } else { [string]$StoredEntry }

    if ($MapData.Count -eq 1) {
        Write-Warning "Removing '$TenantAlias' will leave the TenantMap file empty."
    }

    if ($PSCmdlet.ShouldProcess($TenantMapPath, "Remove alias '$TenantAlias' (mapped to tenant $StoredTenantId)")) {
        [void]$MapData.Remove($TenantAlias)
        Export-OPIMTenantMap -MapData $MapData -Path $TenantMapPath
        Write-Information "Removed tenant alias '$TenantAlias' from $TenantMapPath"
    }
}
