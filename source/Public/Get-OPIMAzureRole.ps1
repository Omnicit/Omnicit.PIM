#requires -module Az.Resources
function Get-OPIMAzureRole {
    <#
    .SYNOPSIS
    Get eligible or activated Azure PIM resource roles for the current user.
    .DESCRIPTION
    Retrieves eligible or active Azure RBAC role assignment schedules using Az.Resources cmdlets.

    Without any switch: returns eligible (inactive) Azure roles for the current user.
    With -Activated: returns currently activated Azure role assignment schedule instances.
    With -All: returns BOTH eligible and active Azure roles for the current user.
    With -RoleName (the first positional argument): returns one role named by its display name, or by
    the tab-completed form, as its eligible and its active post.

    -All and -Activated are mutually exclusive.
    .EXAMPLE
    Get-OPIMAzureRole
    List all eligible (inactive) Azure roles for yourself.
    .EXAMPLE
    Get-OPIMAzureRole 'Reader'
    Retrieve a role by its display name: its eligible and its active post, if it has both. A role that
    is eligible at more than one scope is refused with AmbiguousName; add -Scope to pick one.
    .EXAMPLE
    Get-OPIMAzureRole 'Reader' -Scope '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app'
    Retrieve Reader at that resource group only.
    .EXAMPLE
    Get-OPIMAzureRole -Activated
    List all currently activated Azure roles for yourself.
    .EXAMPLE
    Get-OPIMAzureRole -All
    List both eligible and active Azure roles for yourself across all scopes.
    .EXAMPLE
    Get-OPIMAzureRole -Scope '/subscriptions/00000000-...'
    List eligible Azure roles at a specific subscription scope.
    .EXAMPLE
    Get-OPIMAzureRole -Activated -Scope '/subscriptions/00000000-...'
    List activated Azure roles at exactly that subscription scope.
    .EXAMPLE
    Get-OPIMAzureRole -Identity 'eligible-schedule-name'
    Retrieve a specific role by its schedule Name across eligible and active (dual-search).
    .EXAMPLE
    Get-OPIMAzureRole 'Contributor -> My Subscription (elig-name)'
    Retrieve a role by the tab-completed form, with its schedule Name in parentheses (dual-search).
    .PARAMETER Scope
    The Azure scope to query, such as a subscription, resource group, or resource path.
    Accepts pipeline input. Defaults to the root scope '/' which covers all subscriptions; '/' as
    -Scope means every scope. A scope other than '/' means exactly that scope, not the scopes below
    it, and is compared without regard to letter case. A scope that ends in a slash is refused,
    since only the root scope is written '/'.
    With -Activated (alone, or with -Identity) the instances are read at this scope, and only those
    at exactly this scope are returned. With -All, with -RoleName, or with -Identity but not
    -Activated, the roles are read at the root and only those at exactly this scope are kept.
    (On Enable-OPIMAzureRole and Disable-OPIMAzureRole, '/' means only a role at the root scope itself.)
    .PARAMETER All
    Return BOTH eligible and active roles for the current user, read at scope '/' (-Scope narrows
    them to one scope).
    Objects are emitted with the Omnicit.PIM.AzureCombinedSchedule type for consistent table
    formatting with a Status column. Mutually exclusive with -Activated.
    .PARAMETER Activated
    Only return currently activated role assignment schedule instances instead of eligible
    (inactive) role eligibility schedules.
    Mutually exclusive with -All.
    When combined with -Scope, only instances at that exact scope are returned.
    .PARAMETER RoleName
    The display name of the Azure role, or the tab-completed form the argument completer offers.
    Returns the eligible and the active post (only the active instance with -Activated); add -Scope
    to pick one scope when the role is at several. Several matches are refused with AmbiguousName,
    and none with EligibleRoleNotFound (ActiveRoleNotFound with -Activated). -Identity is ignored
    when -RoleName is given.
    .PARAMETER Identity
    The schedule Name (the Name property from Get-OPIMAzureRole output) used to retrieve a specific
    role schedule. When supplied, both eligible and active schedules are searched (dual-search)
    unless -Activated is also specified. The Name is matched among the roles listed for you, never
    requested by itself, so it needs no rights beyond your own; add -Scope to look only at one scope.
    #>
    [Alias('Get-PIMResourceRole')]
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateScript({ $_ -eq '/' -or -not $_.EndsWith('/') }, ErrorMessage = "The scope '{0}' ends with '/'. Give it without the trailing slash; only the root scope is written '/'.")]
        [String]$Scope = '/',
        [Parameter(ParameterSetName = 'All')][Switch]$All,
        [Parameter(ParameterSetName = 'Activated')][Switch]$Activated,
        [Parameter(Position = 0)]
        [ArgumentCompleter([AzureEligibleRoleCompleter])]
        [String]$RoleName,
        [String]$Identity
    )
    process {
        Initialize-OPIMAuth -IncludeARM
        if ($RoleName) {
            # A name -- display name or the old tab-completed form -- resolves like on Enable and
            # Disable: one post per state, AmbiguousName for several, EligibleRoleNotFound for none.
            $ResolveParams = @{ Pillar = 'Azure'; FilterParameter = 'Scope'; ErrorAction = 'Stop' }
            $ResolveParams.Status = if ($Activated) { 'Active' } else { 'Both' }
            # This cmdlet has always read the default '/' as every scope, so '/' is no filter here.
            if ($Scope -ne '/') { $ResolveParams.Scope = $Scope }
            try {
                Resolve-OPIMSchedule -Name $RoleName @ResolveParams
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
            }
            return
        }

        $OdataFilter = 'asTarget()'

        # An explicit -Scope narrows a lookup to the posts at exactly that scope. The default '/' is no
        # filter: this cmdlet has always read it as every scope.
        $ScopeFilter = if ($Scope -ne '/') { $Scope }

        # Dual mode: -All, or a schedule Name was provided and -Activated not explicitly requested
        [bool]$IsDual = $All -or (-not $Activated -and $Identity)

        if ($IsDual) {
            # Return both eligible and active with AzureCombinedSchedule type for consistent formatting.
            # OPIM-23: a Name is found among the posts the asTarget() listing returns and is never asked
            # for with -Name, since a GET by Name at '/' is refused for a normal user
            # (InsufficientPermissions). Both reads are made at the root; -Scope narrows what they return.
            $EligParams   = @{ Scope = '/'; Filter = $OdataFilter; ErrorAction = 'Stop' }
            $ActiveParams = @{ Scope = '/'; Filter = $OdataFilter; ErrorAction = 'Stop' }
            try {
                # SEC (EntraRBAC A19): the ARM gate, inside the try so the catch reports a refusal as itself.
                $ArmRefusal = Get-OPIMArmRefusal
                if ($null -ne $ArmRefusal) { throw $ArmRefusal }
                Get-AzRoleEligibilitySchedule @EligParams |
                    Where-Object { -not $Identity -or $_.Name -eq $Identity } |
                    Where-Object { -not $ScopeFilter -or [string]::Equals($_.ScopeId, $ScopeFilter, [System.StringComparison]::OrdinalIgnoreCase) } |
                    ForEach-Object {
                        $_ | Add-Member -NotePropertyName Status -NotePropertyValue 'Eligible' -Force
                        $_.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
                        $_.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureCombinedSchedule')
                        $_
                    }
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                if ($PSItem.FullyQualifiedErrorId.Split(',')[0] -eq 'InsufficientPermissions') {
                    # OPIM-11: the rewrap keeps no reference to the raw Az record -- no inner
                    # exception, and the scope as its target object instead of the caught record.
                    $Message = "You do not have sufficient rights to view eligible roles at scope (/). This typically requires Owner or UserAccessAdministrator rights."
                    Write-CmdletError -Message ([System.Exception]::new($Message)) `
                        -ErrorId 'InsufficientPermissions' `
                        -Category PermissionDenied `
                        -Details $Message `
                        -TargetObject '/' `
                        -cmdlet $PSCmdlet
                } else {
                    $PSCmdlet.WriteError($PSItem)
                }
            }
            try {
                $ArmRefusal = Get-OPIMArmRefusal
                if ($null -ne $ArmRefusal) { throw $ArmRefusal }
                Get-AzRoleAssignmentScheduleInstance @ActiveParams |
                    Where-Object AssignmentType -EQ 'Activated' |
                    Where-Object { -not $Identity -or $_.Name -eq $Identity } |
                    Where-Object { -not $ScopeFilter -or [string]::Equals($_.ScopeId, $ScopeFilter, [System.StringComparison]::OrdinalIgnoreCase) } |
                    ForEach-Object {
                        $_ | Add-Member -NotePropertyName Status -NotePropertyValue 'Active' -Force
                        $_.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                        $_.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureCombinedSchedule')
                        $_
                    }
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                if ($PSItem.FullyQualifiedErrorId.Split(',')[0] -eq 'InsufficientPermissions') {
                    $Message = "You do not have sufficient rights to view active roles at scope (/). This typically requires Owner or UserAccessAdministrator rights."
                    Write-CmdletError -Message ([System.Exception]::new($Message)) `
                        -ErrorId 'InsufficientPermissions' `
                        -Category PermissionDenied `
                        -Details $Message `
                        -TargetObject '/' `
                        -cmdlet $PSCmdlet
                } else {
                    $PSCmdlet.WriteError($PSItem)
                }
            }
            return
        }

        try {
            # SEC (EntraRBAC A19): the ARM gate for both reads below, inside the try so the catch
            # reports a refusal as itself.
            $ArmRefusal = Get-OPIMArmRefusal
            if ($null -ne $ArmRefusal) { throw $ArmRefusal }
            if ($Activated) {
                Get-AzRoleAssignmentScheduleInstance -Scope $Scope -Filter $OdataFilter -ErrorAction Stop |
                    Where-Object AssignmentType -EQ 'Activated' |
                    Where-Object { -not $ScopeFilter -or [string]::Equals($_.ScopeId, $ScopeFilter, [System.StringComparison]::OrdinalIgnoreCase) } |
                    Where-Object { -not $Identity -or $_.Name -eq $Identity } |
                    ForEach-Object {
                        $_.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                        $_
                    }
            } else {
                # No -Identity here: a Name without -Activated is a dual search above.
                Get-AzRoleEligibilitySchedule -Scope $Scope -Filter $OdataFilter -ErrorAction Stop |
                    ForEach-Object {
                        $_.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
                        $_
                    }
            }
        } catch {
            Remove-OPIMErrorRecord -Record $PSItem
            if (-not ($PSItem.FullyQualifiedErrorId.Split(',')[0] -eq 'InsufficientPermissions')) {
                $PSCmdlet.WriteError($PSItem)
                return
            }
            # OPIM-11: no reference to the raw Az record -- no inner exception, and the scope as the
            # target object instead of the caught record.
            $Message = "Insufficient permissions to list roles at scope ($Scope). If you are trying to view all users' roles, use -All (requires Owner or UserAccessAdministrator)."
            Write-CmdletError -Message ([System.Exception]::new($Message)) `
                -ErrorId 'InsufficientPermissions' `
                -Category PermissionDenied `
                -Details $Message `
                -TargetObject $Scope `
                -cmdlet $PSCmdlet
            return
        }
    }
}
