function New-OPIMScheduleNameError {
    <#
    .SYNOPSIS
    Builds the error record for a role or group name that is ambiguous or names nothing.

    .DESCRIPTION
    The single owner of the ErrorIds AmbiguousName, EligibleRoleNotFound and ActiveRoleNotFound and
    of their messages; build those records nowhere else. It is pure: it returns an ErrorRecord and
    writes nothing. The caller throws or writes it.

    AmbiguousName (category InvalidArgument) lists every candidate in its old tab-completed form,
    with its scope for a directory or Azure role, and says which parameter tells them apart: -Scope
    when the candidates differ in scope and the caller offers it, -AccessType when they differ in
    access type and the caller offers it, and otherwise the tab-completed form. With -Status Both
    an eligible and an active post for one name are two states of the same thing, so the candidates
    differ in scope (or access type) when they do within each state. It never names one of the
    candidates as the answer.

    EligibleRoleNotFound and ActiveRoleNotFound (category ObjectNotFound) say that no eligible (or
    active) post matches the name, and add what the caller found out: the access type the name
    matches instead, the scopes it matches at instead, that the post is active under another name
    and which, or that the post is eligible but not active (already deactivated, or its activation
    has not finished yet).

    .PARAMETER ErrorId
    AmbiguousName, EligibleRoleNotFound or ActiveRoleNotFound.

    .PARAMETER Pillar
    Directory, Group or Azure; chooses the noun and the properties.

    .PARAMETER Name
    The name or identity as given. It is the record's target object.

    .PARAMETER Status
    Eligible, Active or Both: which list was searched.

    .PARAMETER Candidate
    For AmbiguousName, the posts the name matches.

    .PARAMETER FilterParameter
    The filter parameters the calling command offers (Scope, AccessType). A filter is suggested
    only when the caller has it.

    .PARAMETER Identity
    The value was an -Identity, not a name.

    .PARAMETER OtherAccessType
    For a group name that matched nothing: the access type it matches instead.

    .PARAMETER OtherScope
    For a name that matched nothing at -Scope: the posts it matches at other scopes.

    .PARAMETER AlreadyInactive
    For ActiveRoleNotFound: the name matches an eligible post and no active post carries its label,
    so it is already deactivated -- or its activation (pending approval, or still provisioning) has
    not finished yet and it is no active instance.

    .PARAMETER ActiveForm
    For ActiveRoleNotFound: the active posts that carry the label of the eligible post the name
    matches, under another key. The message names their old tab-completed forms, so the user can
    deactivate by one of them. It takes the place of -AlreadyInactive: a post that is active is
    never also called deactivated.

    .EXAMPLE
    New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Azure -Name 'Reader' -Candidate $Found -FilterParameter Scope

    Returns an AmbiguousName record that lists both Reader eligibilities and suggests -Scope.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'A pure record builder: it changes no state; the New- verb draws the rule onto it.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)][ValidateSet('AmbiguousName', 'EligibleRoleNotFound', 'ActiveRoleNotFound')][string]$ErrorId,
        [Parameter(Mandatory)][ValidateSet('Directory', 'Group', 'Azure')][string]$Pillar,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [ValidateSet('Eligible', 'Active', 'Both')][string]$Status = 'Eligible',
        [AllowEmptyCollection()][object[]]$Candidate = @(),
        [string[]]$FilterParameter = @(),
        [switch]$Identity,
        [ValidateSet('member', 'owner')][string]$OtherAccessType,
        [AllowEmptyCollection()][object[]]$OtherScope = @(),
        [switch]$AlreadyInactive,
        [AllowEmptyCollection()][object[]]$ActiveForm = @()
    )
    $Noun = @{ Directory = 'directory role'; Group = 'group assignment'; Azure = 'Azure role' }[$Pillar]
    $Listing = @{ Directory = 'Get-OPIMDirectoryRole'; Group = 'Get-OPIMEntraIDGroup'; Azure = 'Get-OPIMAzureRole' }[$Pillar]
    $State = @{ Eligible = 'eligible'; Active = 'active'; Both = 'eligible or active' }[$Status]
    $What = if ($Identity) { 'identity' } else { 'name' }
    $Describe = {
        param($Post)
        $Names = Get-OPIMScheduleName -Pillar $Pillar -InputObject $Post
        if ($Pillar -eq 'Group') { "'$($Names.OldForm)'" } else { "'$($Names.OldForm)' at scope '$($Names.ScopeId)'" }
    }

    if ($ErrorId -eq 'AmbiguousName') {
        $All = @($Candidate | ForEach-Object { Get-OPIMScheduleName -Pillar $Pillar -InputObject $PSItem })
        $List = (@($Candidate | ForEach-Object { & $Describe $PSItem })) -join '; '
        # A property tells the candidates apart when its value is distinct within each state: with
        # -Status Both an eligible and an active post may share a scope, and -Scope still resolves it.
        # A candidate without a Status falls in one state of its own (read through PSObject.Properties,
        # which is $null for a missing property even under strict mode).
        $Distinct = {
            param([string]$Property)
            $ByState = @($All | Group-Object -Property {
                    $StatusProperty = $PSItem.InputObject.PSObject.Properties['Status']
                    if ($StatusProperty) { [string]$StatusProperty.Value } else { '' }
                })
            foreach ($Group in $ByState) {
                $Values = @($Group.Group | ForEach-Object { $PSItem.$Property })
                if (@($Values | Sort-Object -Unique).Count -ne $Values.Count) { return $false }
            }
            $true
        }
        $Hint = if ($Pillar -ne 'Group' -and $FilterParameter -contains 'Scope' -and (& $Distinct 'ScopeId')) {
            'They differ in scope: add -Scope with the scope of the one you mean, or give its tab-completed form as listed.'
        } elseif ($Pillar -eq 'Group' -and $FilterParameter -contains 'AccessType' -and (& $Distinct 'AccessId')) {
            'They differ in access type: add -AccessType Member or -AccessType Owner, or give its tab-completed form as listed.'
        } else {
            'Give the tab-completed form of the one you mean, as listed.'
        }
        $Message = "The $What '$Name' matches $($Candidate.Count) $State $($Noun)s, so it names none of them: $List. $Hint"
        $Category = [System.Management.Automation.ErrorCategory]::InvalidArgument
    } else {
        $Parts = [System.Collections.Generic.List[string]]::new()
        $Parts.Add("No $State $Noun matches the $What '$Name'.")
        if ($OtherAccessType) {
            $Title = if ($OtherAccessType -eq 'owner') { 'Owner' } else { 'Member' }
            $Parts.Add("It matches as $($OtherAccessType): add -AccessType $Title.")
        }
        if ($OtherScope.Count -gt 0) {
            $Parts.Add("It matches at another scope: $((@($OtherScope | ForEach-Object { & $Describe $PSItem })) -join '; ').")
        }
        if ($ActiveForm.Count -gt 0) {
            # The post is active under another key: it is never also called deactivated.
            $Forms = @($ActiveForm | ForEach-Object { Get-OPIMScheduleName -Pillar $Pillar -InputObject $PSItem })
            $Quoted = (@($Forms | ForEach-Object { "'$($PSItem.OldForm)'" })) -join ', '
            $How = if ($Forms.Count -gt 1) {
                'one of those names'
            } elseif ($Pillar -eq 'Group' -and $Forms[0].AccessId -eq 'owner') {
                'that name or by its display name with -AccessType Owner'
            } else {
                'that name or by its display name'
            }
            $Parts.Add("It is active as $Quoted; deactivate it by $How.")
        } elseif ($AlreadyInactive) {
            $Parts.Add('It is eligible but not active: it is already deactivated, or its activation has not finished yet.')
        }
        if ($Parts.Count -eq 1) {
            $Shown = if ($Status -eq 'Active') { "$Listing -Activated" } else { $Listing }
            $Parts.Add("Give the display name as $Shown shows it, or use tab completion.")
        }
        $Message = $Parts -join ' '
        $Category = [System.Management.Automation.ErrorCategory]::ObjectNotFound
    }
    [System.Management.Automation.ErrorRecord]::new([System.Exception]::new($Message), $ErrorId, $Category, $Name)
}
