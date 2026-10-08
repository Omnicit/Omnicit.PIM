function Find-OPIMScheduleMatch {
    <#
    .SYNOPSIS
    Finds the PIM schedules a name stands for, among posts that were already listed.

    .DESCRIPTION
    Pure matching for the resolver and the completers; it lists nothing and calls no transport.
    The explicit filters apply first: -Scope keeps the directory or Azure posts at that scope
    (case-insensitive; for a directory role an administrative unit's display name is accepted
    too), and -AccessType keeps the group posts with that access type. Then:

    1. The old form. When the name ends in parentheses and the text in the LAST of them is the key
       of a remaining post (directory and group id, Azure Name), those posts are the match.
    2. Otherwise the whole string is a display name, compared exactly and case-insensitively. For
       a group a display name means the membership unless -AccessType was given.

    A name of only white space matches nothing.

    .PARAMETER Pillar
    Directory, Group or Azure.

    .PARAMETER Name
    The name as the user typed it: a display name or the old tab-completed form.

    .PARAMETER InputObject
    The listed posts to match against.

    .PARAMETER Scope
    A directoryScopeId or administrative unit display name (Directory), or an ARM scope (Azure).
    Ignored for groups.

    .PARAMETER AccessType
    member or owner. Ignored outside groups.

    .EXAMPLE
    Find-OPIMScheduleMatch -Pillar Azure -Name 'Reader' -InputObject $Roles -Scope '/subscriptions/sub-001/resourceGroups/rg-one'

    Returns the Reader eligibility at that resource group, if the list holds one.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][ValidateSet('Directory', 'Group', 'Azure')][string]$Pillar,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$InputObject,
        [string]$Scope,
        [ValidateSet('member', 'owner')][string]$AccessType
    )
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $Ignore = [System.StringComparison]::OrdinalIgnoreCase

    $Candidates = @(foreach ($Item in @($InputObject)) {
        if ($null -eq $Item) { continue }
        $Names = Get-OPIMScheduleName -Pillar $Pillar -InputObject $Item
        if ($Scope -and $Pillar -ne 'Group') {
            $InScope = [string]::Equals($Names.ScopeId, $Scope, $Ignore) -or (
                $Pillar -eq 'Directory' -and $Names.ScopeId -ne '/' -and
                [string]::Equals($Names.ScopeName, $Scope, $Ignore))
            if (-not $InScope) { continue }
        }
        if ($AccessType -and $Pillar -eq 'Group' -and -not [string]::Equals($Names.AccessId, $AccessType, $Ignore)) {
            continue
        }
        $Names
    })

    # 1. The old form: the key in the last parentheses wins when a listed post carries it.
    if ($Name -match '\(([^()]+)\)\s*$') {
        $Key = $Matches[1]
        $ByKey = @($Candidates | Where-Object { [string]::Equals($PSItem.Key, $Key, $Ignore) })
        if ($ByKey.Count -gt 0) { return $ByKey.InputObject }
    }

    # 2. The whole string as a display name; a group name means the membership by default.
    $DefaultAccess = if ($Pillar -eq 'Group' -and -not $AccessType) { 'member' }
    foreach ($Candidate in $Candidates) {
        if ($DefaultAccess -and -not [string]::Equals($Candidate.AccessId, $DefaultAccess, $Ignore)) { continue }
        if ([string]::Equals($Candidate.DisplayName, $Name, $Ignore)) { $Candidate.InputObject }
    }
}
