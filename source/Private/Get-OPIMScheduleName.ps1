function Get-OPIMScheduleName {
    <#
    .SYNOPSIS
    Returns the names a PIM schedule is known by, for one of the three pillars.

    .DESCRIPTION
    The single owner of which property holds what on a directory role, a PIM for Groups assignment
    or an Azure role schedule: its display name, its key (the id the old tab-completion form ends
    in), its scope, its access type, the old-form label and the old form itself. It is pure: it
    reads the object it is given and calls nothing.

    The old form is the text the completers have always offered: 'Role (id)' or
    'Role -> AU (id)' for a directory role, 'Group - member (id)' for a group, and
    'Role -> Scope (Name)' for an Azure role.

    .PARAMETER Pillar
    Directory, Group or Azure.

    .PARAMETER InputObject
    One schedule or instance object as Get-OPIMDirectoryRole, Get-OPIMEntraIDGroup or
    Get-OPIMAzureRole returns it. A null object returns nothing.

    .EXAMPLE
    Get-OPIMScheduleName -Pillar Directory -InputObject $Role

    Returns DisplayName, Key, ScopeId, ScopeName, AccessId, Label, OldForm and InputObject.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][ValidateSet('Directory', 'Group', 'Azure')][string]$Pillar,
        [Parameter(Mandatory, ValueFromPipeline)][AllowNull()]$InputObject
    )
    process {
        if ($null -eq $InputObject) { return }
        switch ($Pillar) {
            'Directory' {
                $DisplayName = [string]$InputObject.roleDefinition.displayName
                $Key         = [string]$InputObject.id
                $ScopeId     = [string]$InputObject.directoryScopeId
                $AtRoot      = [string]::IsNullOrEmpty($ScopeId) -or $ScopeId -eq '/'
                $ScopeName   = if ($AtRoot) { 'Directory' } else { [string]$InputObject.directoryScope.displayName }
                $AccessId    = $null
                $Label       = if ($AtRoot) { $DisplayName } else { "$DisplayName -> $ScopeName" }
            }
            'Group' {
                $DisplayName = [string]$InputObject.group.displayName
                $Key         = [string]$InputObject.id
                $ScopeId     = $null
                $ScopeName   = $null
                $AccessId    = [string]$InputObject.accessId
                $Label       = "$DisplayName - $AccessId"
            }
            'Azure' {
                $DisplayName = [string]$InputObject.RoleDefinitionDisplayName
                $Key         = [string]$InputObject.Name
                $ScopeId     = [string]$InputObject.ScopeId
                $ScopeName   = [string]$InputObject.ScopeDisplayName
                $AccessId    = $null
                $Label       = "$DisplayName -> $ScopeName"
            }
        }
        [PSCustomObject]@{
            DisplayName = $DisplayName
            Key         = $Key
            ScopeId     = $ScopeId
            ScopeName   = $ScopeName
            AccessId    = $AccessId
            Label       = $Label
            OldForm     = "$Label ($Key)"
            InputObject = $InputObject
        }
    }
}
