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
    .PARAMETER Scope
    The Azure scope to query, such as a subscription, resource group, or resource path.
    Accepts pipeline input. Defaults to the root scope '/' which covers all subscriptions.
    When -Activated is used with a specific scope, only instances at that exact scope are returned.
    .PARAMETER All
    Return BOTH eligible and active roles for the current user at scope '/'.
    Mutually exclusive with -Activated.
    .PARAMETER Activated
    Only return currently activated role assignment schedule instances instead of eligible
    (inactive) role eligibility schedules.
    Mutually exclusive with -All.
    When combined with -Scope, only instances at that exact scope are returned.
    #>
    [Alias('Get-PIMResourceRole')]
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)][Alias('Id')][String]$Scope = '/',
        [Parameter(ParameterSetName = 'All')][Switch]$All,
        [Parameter(ParameterSetName = 'Activated')][Switch]$Activated
    )
    process {
        $OdataFilter = 'asTarget()'

        if ($All) {
            # Return both eligible and active for the current user at root scope
            try {
                Get-AzRoleEligibilitySchedule -Scope '/' -Filter $OdataFilter -ErrorAction Stop |
                    ForEach-Object {
                        $_.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
                        $_
                    }
            } catch {
                if ($PSItem.FullyQualifiedErrorId.Split(',')[0] -eq 'InsufficientPermissions') {
                    $Message = "You do not have sufficient rights to view eligible roles at scope (/). This typically requires Owner or UserAccessAdministrator rights."
                    Write-CmdletError -Message ([System.Exception]::new($Message, $PSItem.Exception)) `
                        -ErrorId 'InsufficientPermissions' `
                        -Category PermissionDenied `
                        -Details $Message `
                        -cmdlet $PSCmdlet
                } else {
                    $PSCmdlet.WriteError($PSItem)
                }
            }
            try {
                Get-AzRoleAssignmentScheduleInstance -Scope '/' -Filter $OdataFilter -ErrorAction Stop |
                    Where-Object AssignmentType -EQ 'Activated' |
                    ForEach-Object {
                        $_.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                        $_
                    }
            } catch {
                if ($PSItem.FullyQualifiedErrorId.Split(',')[0] -eq 'InsufficientPermissions') {
                    $Message = "You do not have sufficient rights to view active roles at scope (/). This typically requires Owner or UserAccessAdministrator rights."
                    Write-CmdletError -Message ([System.Exception]::new($Message, $PSItem.Exception)) `
                        -ErrorId 'InsufficientPermissions' `
                        -Category PermissionDenied `
                        -Details $Message `
                        -cmdlet $PSCmdlet
                } else {
                    $PSCmdlet.WriteError($PSItem)
                }
            }
            return
        }

        try {
            if ($Activated) {
                Get-AzRoleAssignmentScheduleInstance -Scope $Scope -Filter $OdataFilter -ErrorAction Stop |
                    Where-Object AssignmentType -EQ 'Activated' |
                    Where-Object { $Scope -eq '/' -or $_.ScopeId -eq $Scope } |
                    ForEach-Object {
                        $_.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                        $_
                    }
            } else {
                Get-AzRoleEligibilitySchedule -Scope $Scope -Filter $OdataFilter -ErrorAction Stop |
                    ForEach-Object {
                        $_.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
                        $_
                    }
            }
        } catch {
            if (-not ($PSItem.FullyQualifiedErrorId.Split(',')[0] -eq 'InsufficientPermissions')) {
                $PSCmdlet.WriteError($PSItem)
                return
            }
            $Message = "Insufficient permissions to list roles at scope ($Scope). If you are trying to view all users' roles, use -All (requires Owner or UserAccessAdministrator)."
            Write-CmdletError -Message ([System.Exception]::new($Message, $PSItem.Exception)) `
                -ErrorId 'InsufficientPermissions' `
                -Category PermissionDenied `
                -Details $Message `
                -cmdlet $PSCmdlet
            return
        }
    }
}
