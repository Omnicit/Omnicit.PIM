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

    The remaining posts are indexed once per call, by key and by display name, in the order they
    were listed, and every name is answered from that index: -Name returns the posts for one name,
    and -NameList answers a whole list of names from the same index (OPIM-51).

    .PARAMETER Pillar
    Directory, Group or Azure.

    .PARAMETER Name
    The name as the user typed it: a display name or the old tab-completed form.

    .PARAMETER NameList
    Many names, each a display name or an old tab-completed form. The result is one
    Dictionary[string, object[]] with an ordinal comparer: each distinct string of the list is a
    key, and its value holds the posts -Name returns for that string, in the same order, or is an
    empty array.

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

    .EXAMPLE
    $Answers = Find-OPIMScheduleMatch -Pillar Directory -NameList 'Reader', 'Reader -> Sales AU (elig-002)' -InputObject $Roles

    Answers both names from one index of $Roles: $Answers['Reader'] holds the posts that
    -Name 'Reader' returns.
    #>
    [CmdletBinding(DefaultParameterSetName = 'One')]
    [OutputType([PSCustomObject], ParameterSetName = 'One')]
    [OutputType([System.Collections.Generic.Dictionary[string, object[]]], ParameterSetName = 'Many')]
    param(
        [Parameter(Mandatory)][ValidateSet('Directory', 'Group', 'Azure')][string]$Pillar,
        [Parameter(Mandatory, ParameterSetName = 'One')][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory, ParameterSetName = 'Many')][AllowNull()][AllowEmptyString()][AllowEmptyCollection()][string[]]$NameList,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$InputObject,
        [string]$Scope,
        [ValidateSet('member', 'owner')][string]$AccessType
    )
    $Many = $PSCmdlet.ParameterSetName -eq 'Many'
    if (-not $Many -and [string]::IsNullOrWhiteSpace($Name)) { return }
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

    # One index by key and one by display name, each appended in the order of the candidates, so a
    # post listed twice and the order of the posts survive. They are built with indexers and array
    # operators: a .NET method call per post (List.Add, TryGetValue) cost ten times as much when
    # measured on PowerShell 7.6.
    $ByKey = [System.Collections.Generic.Dictionary[string, object[]]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ByDisplayName = [System.Collections.Generic.Dictionary[string, object[]]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Candidate in $Candidates) {
        $IndexKey = [string]$Candidate.Key
        $Entry = $ByKey[$IndexKey]
        if ($null -eq $Entry) { $ByKey[$IndexKey] = @($Candidate) } else { $ByKey[$IndexKey] = $Entry + $Candidate }
        $IndexKey = [string]$Candidate.DisplayName
        $Entry = $ByDisplayName[$IndexKey]
        if ($null -eq $Entry) { $ByDisplayName[$IndexKey] = @($Candidate) } else { $ByDisplayName[$IndexKey] = $Entry + $Candidate }
    }

    $DefaultAccess = if ($Pillar -eq 'Group' -and -not $AccessType) { 'member' }
    $Asked = if ($Many) { $NameList } else { @($Name) }
    $Answer = [System.Collections.Generic.Dictionary[string, object[]]]::new([System.StringComparer]::Ordinal)
    foreach ($Each in $Asked) {
        if ($Answer.ContainsKey($Each)) { continue }
        # A name of only white space matches nothing.
        $KeyHits = $null
        $NameHits = $null
        if (-not [string]::IsNullOrWhiteSpace($Each)) {
            if ($Each -match '\(([^()]+)\)\s*$') { $KeyHits = $ByKey[$Matches[1]] }
            if ($null -eq $KeyHits) { $NameHits = $ByDisplayName[$Each] }
        }
        $Answer[$Each] = @(
            # 1. The old form: the key in the last parentheses wins when a listed post carries it.
            foreach ($Hit in $KeyHits) { $Hit.InputObject }
            # 2. The whole string as a display name; a group name means the membership by default.
            foreach ($Hit in $NameHits) {
                if ($DefaultAccess -and -not [string]::Equals($Hit.AccessId, $DefaultAccess, $Ignore)) { continue }
                $Hit.InputObject
            }
        )
    }

    if ($Many) {
        # Named, not positional: a positional argument is gathered into a List[object] first.
        Write-Output -NoEnumerate -InputObject $Answer
        return
    }
    foreach ($Post in $Answer[$Name]) { $Post }
}
