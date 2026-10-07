function Resolve-OPIMSchedule {
    <#
    .SYNOPSIS
    Resolves a role or group name to exactly one PIM schedule, or refuses it.

    .DESCRIPTION
    Lists the user's eligible (or active, or both) posts for one pillar through Get-OPIMDirectoryRole,
    Get-OPIMEntraIDGroup or Get-OPIMAzureRole, and matches the name with Find-OPIMScheduleMatch:
    the old tab-completed form 'Name (id)' when its id is listed, otherwise the display name,
    case-insensitively and exactly, under -Scope and -AccessType (a group name means the
    membership unless -AccessType says otherwise).

    Outcomes:
    - one match: the post is returned. With -Status Both one eligible and one active post may both
      be returned, since they are different states of the same thing.
    - no match: the terminating EligibleRoleNotFound (ActiveRoleNotFound for -Status Active).
    - several: the terminating AmbiguousName, listing the candidates. The first match is never taken.

    A listing that fails is thrown as its own record, never reported as not found (OPIM-12).

    .PARAMETER Pillar
    Directory, Group or Azure.

    .PARAMETER Name
    A display name, or the old tab-completed form.

    .PARAMETER Status
    Eligible (default), Active, or Both.

    .PARAMETER Scope
    A directoryScopeId or administrative unit display name (Directory), or an ARM scope (Azure). A
    scope that ends in a slash, other than the root '/', is refused.

    .PARAMETER AccessType
    member or owner, for groups.

    .PARAMETER FilterParameter
    The filter parameters the calling command offers, so that an AmbiguousName message suggests
    only what the user can type.

    .EXAMPLE
    Resolve-OPIMSchedule -Pillar Azure -Name 'Reader' -Scope '/subscriptions/sub-001/resourceGroups/rg-one' -FilterParameter Scope

    Returns the Reader eligibility at that resource group.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][ValidateSet('Directory', 'Group', 'Azure')][string]$Pillar,
        [Parameter(Mandatory)][string]$Name,
        [ValidateSet('Eligible', 'Active', 'Both')][string]$Status = 'Eligible',
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ $_ -eq '/' -or -not $_.EndsWith('/') }, ErrorMessage = "The scope '{0}' ends with '/'. Give it without the trailing slash; only the root scope is written '/'.")]
        [string]$Scope,
        [ValidateSet('member', 'owner')][string]$AccessType,
        [string[]]$FilterParameter = @()
    )
    $Filters = @{}
    if ($PSBoundParameters.ContainsKey('Scope'))      { $Filters.Scope = $Scope }
    if ($PSBoundParameters.ContainsKey('AccessType')) { $Filters.AccessType = $AccessType }

    $ListParams = @{ ErrorAction = 'Stop' }
    if ($Status -eq 'Active')   { $ListParams.Activated = $true }
    elseif ($Status -eq 'Both') { $ListParams.All = $true }

    # OPIM-12: a listing that fails is thrown as itself; -ErrorAction Stop turns the error it writes
    # into one that ends it, and the rethrow keeps its id.
    try {
        $Items = @(switch ($Pillar) {
            'Directory' { Get-OPIMDirectoryRole @ListParams }
            'Group'     { Get-OPIMEntraIDGroup @ListParams }
            'Azure'     { Get-OPIMAzureRole @ListParams }
        })
    } catch {
        Remove-OPIMErrorRecord -Record $PSItem
        throw $PSItem
    }

    $Found = @(Find-OPIMScheduleMatch -Pillar $Pillar -Name $Name -InputObject $Items @Filters)

    # An eligible post and an active post for the same name are two states, not two candidates.
    $Ambiguous = if ($Status -eq 'Both') {
        @($Found | Group-Object -Property { [string]$PSItem.Status } | Where-Object { $PSItem.Count -gt 1 }).Count -gt 0
    } else {
        $Found.Count -gt 1
    }
    if ($Ambiguous) {
        $PSCmdlet.ThrowTerminatingError((New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar $Pillar `
            -Name $Name -Status $Status -Candidate $Found -FilterParameter $FilterParameter))
    }
    if ($Found.Count -gt 0) {
        # One output per post. PSUseOutputTypeCorrectly reads a returned array as an object[] output.
        foreach ($Post in $Found) { $Post }
        return
    }

    $Hint = @{}
    if ($Pillar -eq 'Group') {
        $Asked = if ($Filters.ContainsKey('AccessType')) { $AccessType } else { 'member' }
        $Other = if ($Asked -eq 'member') { 'owner' } else { 'member' }
        if (@(Find-OPIMScheduleMatch -Pillar Group -Name $Name -InputObject $Items -AccessType $Other).Count -gt 0) {
            $Hint.OtherAccessType = $Other
        }
    } elseif ($Filters.ContainsKey('Scope')) {
        $Elsewhere = @(Find-OPIMScheduleMatch -Pillar $Pillar -Name $Name -InputObject $Items)
        if ($Elsewhere.Count -gt 0) { $Hint.OtherScope = $Elsewhere }
    }
    $NotFoundId = if ($Status -eq 'Active') { 'ActiveRoleNotFound' } else { 'EligibleRoleNotFound' }
    $PSCmdlet.ThrowTerminatingError((New-OPIMScheduleNameError -ErrorId $NotFoundId -Pillar $Pillar `
        -Name $Name -Status $Status @Hint))
}
