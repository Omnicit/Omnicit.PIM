function Get-OPIMRequestOutcome {
    <#
    .SYNOPSIS
    Classifies the status of a PIM activation or deactivation request.

    .DESCRIPTION
    The single owner of what a request status means, for directory roles, groups and Azure roles
    alike. It is pure: it returns one of four words and writes nothing.

    Succeeded: Provisioned, Granted and ScheduleCreated for an activation; Revoked for a
    deactivation.
    AwaitingDecision: PendingApproval, PendingAdminDecision and PendingApprovalProvisioning -- the
    request waits for a person.
    InProgress: PendingProvisioning, PendingScheduleCreation, Accepted, PendingEvaluation,
    ProvisioningStarted, PendingExternalProvisioning and AdminApproved, and PendingRevocation for a
    deactivation -- the service is still working on the request.
    Failed: every other status, an empty one included -- Failed, Denied, Canceled, Revoked for an
    activation, AdminDenied, TimedOut, Invalid, FailedAsResourceIsLocked, and any value the service
    adds later. A request is never counted as a success on a status this function does not know.

    The comparison ignores letter case.

    .PARAMETER Status
    The status of the request, as Microsoft Graph or Azure Resource Manager returned it.

    .PARAMETER Deactivate
    The request is a SelfDeactivate request, whose success status is Revoked.

    .EXAMPLE
    Get-OPIMRequestOutcome -Status 'PendingApproval'

    Returns AwaitingDecision.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Status,
        [switch]$Deactivate
    )
    $Succeeded = if ($Deactivate) { @('Revoked') } else { @('Provisioned', 'Granted', 'ScheduleCreated') }
    $AwaitingDecision = @('PendingApproval', 'PendingAdminDecision', 'PendingApprovalProvisioning')
    $InProgress = @('PendingProvisioning', 'PendingScheduleCreation', 'Accepted', 'PendingEvaluation',
        'ProvisioningStarted', 'PendingExternalProvisioning', 'AdminApproved')
    if ($Deactivate) { $InProgress += 'PendingRevocation' }
    if ([string]::IsNullOrWhiteSpace($Status)) { return 'Failed' }
    if ($Succeeded -contains $Status) { return 'Succeeded' }
    if ($AwaitingDecision -contains $Status) { return 'AwaitingDecision' }
    if ($InProgress -contains $Status) { return 'InProgress' }
    'Failed'
}
