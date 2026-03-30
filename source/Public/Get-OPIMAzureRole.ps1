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
    .PARAMETER Scope
    The Azure scope to query, such as a subscription, resource group, or resource path.
    Accepts pipeline input. Defaults to the root scope '/' which covers all subscriptions.
    .PARAMETER All
    Return eligible or active roles for ALL principals at the scope, not just your own.
    Requires Owner or UserAccessAdministrator rights at the target scope.
    .PARAMETER Activated
    Only return currently activated role assignment schedule instances instead of eligible
    (inactive) role eligibility schedules.
    #>
    [Alias('Get-PIMResourceRole')]
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)][Alias('Id')][String]$Scope = '/',
        [Switch]$All,
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
            $message = if ($All) {
                "You do not have sufficient rights to view all roles at scope ($Scope). This typically requires Owner or UserAccessAdministrator rights."
            } else {
                "Insufficient permissions to list roles at scope ($Scope). If you are trying to view all users' roles, use -All (requires Owner or UserAccessAdministrator)."
            }
            $PSItem.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($message)
            $PSCmdlet.WriteError($PSItem)
            return
        }
    }
}
