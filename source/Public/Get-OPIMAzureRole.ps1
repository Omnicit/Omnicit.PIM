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

    -All and -Activated are mutually exclusive.
    .EXAMPLE
    Get-OPIMAzureRole
    List all eligible (inactive) Azure roles for yourself.
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
    Tab-complete and retrieve details for a role by name (dual-search).
    .PARAMETER Scope
    The Azure scope to query, such as a subscription, resource group, or resource path.
    Accepts pipeline input. Defaults to the root scope '/' which covers all subscriptions.
    When -Activated is used with a specific scope, only instances at that exact scope are returned.
    .PARAMETER All
    Return BOTH eligible and active roles for the current user at scope '/'.
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
    unless -Activated is also specified.
    #>
    [Alias('Get-PIMResourceRole')]
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)][String]$Scope = '/',
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
        [string]$ResolvedName = $Identity

        $OdataFilter = 'asTarget()'

        # Dual mode: -All, or a schedule Name was provided and -Activated not explicitly requested
        [bool]$IsDual = $All -or (-not $Activated -and $ResolvedName)

        if ($IsDual) {
            # Return both eligible and active with AzureCombinedSchedule type for consistent formatting
            # When a Name is supplied, use the Get parameter set (Name + Scope) - Filter and Name are
            # mutually exclusive parameter sets in Az.Resources cmdlets.
            if ($ResolvedName) {
                $EligParams   = @{ Scope = '/'; Name = $ResolvedName; ErrorAction = 'Stop' }
                $ActiveParams = @{ Scope = '/'; Name = $ResolvedName; ErrorAction = 'Stop' }
            } else {
                $EligParams   = @{ Scope = '/'; Filter = $OdataFilter; ErrorAction = 'Stop' }
                $ActiveParams = @{ Scope = '/'; Filter = $OdataFilter; ErrorAction = 'Stop' }
            }
            try {
                # SEC (EntraRBAC A19): the ARM gate, inside the try so the catch reports a refusal as itself.
                $ArmRefusal = Get-OPIMArmRefusal
                if ($null -ne $ArmRefusal) { throw $ArmRefusal }
                Get-AzRoleEligibilitySchedule @EligParams |
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
                    Where-Object { $Scope -eq '/' -or $_.ScopeId -eq $Scope } |
                    Where-Object { -not $ResolvedName -or $_.Name -eq $ResolvedName } |
                    ForEach-Object {
                        $_.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                        $_
                    }
            } else {
                Get-AzRoleEligibilitySchedule -Scope $Scope -Filter $OdataFilter -ErrorAction Stop |
                    Where-Object { -not $ResolvedName -or $_.Name -eq $ResolvedName } |
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
