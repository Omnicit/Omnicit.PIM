#requires -module Az.Resources
function Get-OPIMAzureRole {
    <#
    .SYNOPSIS
    Get eligible or activated Azure PIM resource roles for the current user.
    .DESCRIPTION
    Retrieves eligible or active Azure RBAC role assignment schedules using Az.Resources cmdlets.
    .EXAMPLE
    Get-OPIMAzureRole
    List all eligible (inactive) Azure roles for yourself.
    .EXAMPLE
    Get-OPIMAzureRole -Activated
    List all currently activated Azure roles for yourself.
    .EXAMPLE
    Get-OPIMAzureRole -Scope '/subscriptions/00000000-...'
    List eligible Azure roles at a specific subscription scope.
    #>
    [Alias('Get-PIMResourceRole')]
    [CmdletBinding()]
    param(
        #The scope to query (subscription, resource group, or resource). Defaults to root '/'.
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)][Alias('Id')][String]$Scope = '/',
        #Return roles for ALL principals, not just your own. Requires Owner or UserAccessAdministrator at the scope.
        #By default (without -All) only your own eligible or active roles are returned.
        [Switch]$All,
        #Only return currently activated role assignment instances.
        [Parameter(ParameterSetName = 'Activated')][Switch]$Activated
    )
    process {
        $filter = if (-not $All) { 'asTarget()' }
        try {
            if ($Activated) {
                Get-AzRoleAssignmentScheduleInstance -Scope $Scope -Filter $filter -ErrorAction Stop |
                    Where-Object AssignmentType -EQ 'Activated' |
                    ForEach-Object {
                        $_.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                        $_
                    }
            } else {
                Get-AzRoleEligibilitySchedule -Scope $Scope -Filter $filter -ErrorAction Stop |
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
            $PSItem.ErrorDetails = if ($All) {
                "You do not have sufficient rights to view all roles at scope ($Scope). This typically requires Owner or UserAccessAdministrator rights."
            } else {
                "Insufficient permissions to list roles at scope ($Scope). If you are trying to view all users' roles, use -All (requires Owner or UserAccessAdministrator)."
            }
            $PSCmdlet.WriteError($PSItem)
            return
        }
    }
}
