function ConvertTo-OPIMMyRoleResult {
    <#
    .SYNOPSIS
    Internal helper used by Enable-OPIMMyRole and Disable-OPIMMyRole to normalise output objects
    from the three PIM pillars into a uniform Omnicit.PIM.MyRoleResult object so that all rows
    render in a single consistent table regardless of which pillar produced them.
    .DESCRIPTION
    Accepts pipeline input from Enable-OPIMDirectoryRole, Enable-OPIMEntraIDGroup,
    Enable-OPIMAzureRole, Disable-OPIMDirectoryRole, Disable-OPIMEntraIDGroup, and
    Disable-OPIMAzureRole. Each of those functions returns a different type with different
    property names. This function maps each type to a canonical shape (Category, Action, Status,
    DisplayName, Scope, EndDateTime) and tags the result with the Omnicit.PIM.MyRoleResult type
    name so that the single unified format view in Omnicit.PIM.Format.ps1xml applies to all rows.
    .EXAMPLE
    Enable-OPIMDirectoryRole -RoleName 'Global Administrator' | ConvertTo-OPIMMyRoleResult
    Normalises the directory role activation result into a Omnicit.PIM.MyRoleResult object.
    #>
    process {
        $InputItem = $PSItem
        $TypeName = $InputItem.PSObject.TypeNames | Where-Object { $_ -like 'Omnicit.PIM.*' } | Select-Object -First 1

        $Out = switch -Wildcard ($TypeName) {
            'Omnicit.PIM.DirectoryAssignment*' {
                [PSCustomObject]@{
                    Category    = 'DirectoryRole'
                    Action      = $InputItem.action
                    Status      = $InputItem.status
                    DisplayName = $InputItem.roleDefinition.displayName
                    Scope       = if ($InputItem.directoryScopeId -eq '/') { 'Directory' }
                                  else { $InputItem.directoryScope.displayName ?? $InputItem.directoryScopeId }
                    EndDateTime = $InputItem.EndDateTime
                }
            }
            'Omnicit.PIM.GroupAssignment*' {
                [PSCustomObject]@{
                    Category    = 'EntraIDGroup'
                    Action      = $InputItem.action
                    Status      = $InputItem.status
                    DisplayName = $InputItem.group.displayName
                    Scope       = $InputItem.accessId
                    EndDateTime = $InputItem.EndDateTime
                }
            }
            'Omnicit.PIM.AzureAssignment*' {
                $EndDt = if ($InputItem.ExpirationType -eq 'AfterDuration' -and $InputItem.ExpirationDuration) {
                    try {
                        $Duration = if ($InputItem.ExpirationDuration -is [timespan]) {
                            $InputItem.ExpirationDuration
                        } else {
                            [System.Xml.XmlConvert]::ToTimeSpan([string]$InputItem.ExpirationDuration)
                        }
                        ([datetime]$InputItem.ScheduleInfoStartDateTime) + $Duration
                    } catch { $null }
                } else {
                    $InputItem.ExpirationEndDateTime
                }
                [PSCustomObject]@{
                    Category    = 'AzureRole'
                    Action      = $InputItem.RequestType
                    Status      = $InputItem.Status
                    DisplayName = $InputItem.RoleDefinitionDisplayName
                    Scope       = $InputItem.ScopeDisplayName
                    EndDateTime = $EndDt
                }
            }
        }

        if ($Out) {
            $Out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.MyRoleResult')
            $Out
        }
    }
}
