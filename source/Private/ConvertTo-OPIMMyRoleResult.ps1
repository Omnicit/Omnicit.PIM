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

    An error record that comes down the pipeline -- the error stream of a pillar cmdlet, redirected
    with 2>&1 -- is written through the calling command's own runtime (-Cmdlet), so it reaches that
    command's -ErrorVariable and error stream (OPIM-52). A pillar cmdlet piped into this function is
    not the last command of its pipeline, and such a command's errors never reach the caller's
    -ErrorVariable. Before the record is written, the pillar's own entry of it is removed from
    $global:Error, so it is listed there once. Nothing is emitted for an error record.
    .PARAMETER InputObject
    A request or role object from a pillar cmdlet, or an error record from its redirected error
    stream.
    .PARAMETER Cmdlet
    The $PSCmdlet of the calling command (Enable-OPIMMyRole or Disable-OPIMMyRole), through which an
    error record is written.
    .EXAMPLE
    $Roles | Enable-OPIMDirectoryRole 2>&1 | ConvertTo-OPIMMyRoleResult -Cmdlet $PSCmdlet
    Normalises each activation into an Omnicit.PIM.MyRoleResult object and writes each refusal as an
    error of the calling command.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        $InputObject,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )
    process {
        $InputItem = $InputObject
        if ($InputItem -is [System.Management.Automation.ErrorRecord]) {
            # OPIM-52: through the caller's runtime, so the caller's -ErrorVariable gets it. The pillar
            # already put the record in $global:Error once; drop that entry, as the write adds one.
            Remove-OPIMErrorRecord -Record $InputItem
            $Cmdlet.WriteError($InputItem)
            return
        }
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
