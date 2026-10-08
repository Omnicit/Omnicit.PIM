function Get-OPIMCompletionText {
    <#
    .SYNOPSIS
    Builds the tab-completion text for listed PIM schedules.

    .DESCRIPTION
    Pure; used by the six argument completer classes. For each post it offers the bare display name
    when that name, under the filters already typed (-Scope, -AccessType) and the Member default for
    groups, names exactly that post; otherwise the old form 'Name (id)', 'Name -> AU (id)',
    'Group - member (id)' or 'Role -> Scope (Name)', which is unique. A post the typed filters
    exclude is not offered. Every text is single-quoted with its apostrophes doubled (OPIM-26), and
    the word typed so far is compared with StartsWith, case-insensitively, never as a wildcard.

    .PARAMETER Pillar
    Directory, Group or Azure.

    .PARAMETER InputObject
    The posts the completer listed.

    .PARAMETER WordToComplete
    The word typed so far, possibly with an opening quote and doubled apostrophes.

    .PARAMETER FakeBoundParameters
    The parameters already typed on the command line.

    .PARAMETER CommandName
    The command being completed. On a Get- command '/' as -Scope means every scope, so it filters
    nothing.

    .EXAMPLE
    Get-OPIMCompletionText -Pillar Directory -InputObject $Roles -WordToComplete "'Usage"

    Returns "'Usage Summary Reports Reader'" when that name is unique.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][ValidateSet('Directory', 'Group', 'Azure')][string]$Pillar,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$InputObject,
        [AllowEmptyString()][string]$WordToComplete,
        [AllowNull()][System.Collections.IDictionary]$FakeBoundParameters,
        [AllowEmptyString()][string]$CommandName
    )
    $Ignore = [System.StringComparison]::OrdinalIgnoreCase
    $Filters = @{}
    if ($FakeBoundParameters) {
        $TypedScope = [string]$FakeBoundParameters['Scope']
        if ($Pillar -ne 'Group' -and $TypedScope -and -not ($TypedScope -eq '/' -and $CommandName -like 'Get-*')) {
            $Filters.Scope = $TypedScope
        }
        $TypedAccess = [string]$FakeBoundParameters['AccessType']
        if ($Pillar -eq 'Group' -and $TypedAccess -in 'member', 'owner') {
            $Filters.AccessType = $TypedAccess.ToLowerInvariant()
        }
    }

    # The engine hands the word as an opening quote, the UNESCAPED value and a closing quote ('O''Br
    # arrives as 'O'Br', measured under TabExpansion2); a caller that passes the text as typed still
    # has its doubled apostrophes, so those are undone too. The word is then a plain prefix.
    $Word = [string]$WordToComplete
    if ($Word.Length -gt 0 -and $Word[0] -in [char]"'", [char]'"') { $Word = $Word.Substring(1) }
    if ($Word.Length -gt 0 -and $Word[-1] -in [char]"'", [char]'"') { $Word = $Word.Substring(0, $Word.Length - 1) }
    $Word = $Word.Replace("''", "'")

    $Items = @($InputObject | Where-Object { $null -ne $PSItem })
    foreach ($Item in $Items) {
        $Names = Get-OPIMScheduleName -Pillar $Pillar -InputObject $Item
        # A post the typed filters exclude is not offered: its own old form must still find it.
        if (@(Find-OPIMScheduleMatch -Pillar $Pillar -Name $Names.OldForm -InputObject $Items @Filters).Count -eq 0) {
            continue
        }
        $ByName = @(Find-OPIMScheduleMatch -Pillar $Pillar -Name $Names.DisplayName -InputObject $Items @Filters)
        $Unique = $ByName.Count -eq 1 -and
            (Get-OPIMScheduleName -Pillar $Pillar -InputObject $ByName[0]).Key -eq $Names.Key
        $Text = if ($Unique) { $Names.DisplayName } else { $Names.OldForm }
        if ($Word -and -not $Text.StartsWith($Word, $Ignore)) { continue }
        "'" + $Text.Replace("'", "''") + "'"
    }
}
