function Write-OPIMRequestOutcome {
    <#
    .SYNOPSIS
    Reports a PIM request by its status: returns it, returns it with a warning, or writes an error.

    .DESCRIPTION
    The one place that turns a request status into what the user sees, for the Enable- and Disable-
    cmdlets and Wait-OPIMDirectoryRole. It first writes the status back onto the request object --
    a note property is added when the object has none, and a read-only status (an Az.Resources
    object) is left as it is -- and then, by Get-OPIMRequestOutcome:

    Succeeded: returns the request.
    InProgress or AwaitingDecision: writes a warning through -Cmdlet and returns the request, which
    is never counted as a success.
    Failed: writes ActivationRequestFailed (New-OPIMRequestError) through -Cmdlet as a
    non-terminating error and returns nothing.

    .PARAMETER Request
    The request object to report.

    .PARAMETER Status
    The status of the request.

    .PARAMETER Name
    The label of the role or group, as Get-OPIMScheduleName gives it.

    .PARAMETER Deactivate
    The request is a deactivation, whose success status is Revoked.

    .PARAMETER Cmdlet
    The calling cmdlet's $PSCmdlet; warnings and errors are written through it.

    .EXAMPLE
    Write-OPIMRequestOutcome -Request $Out -Status $Out.status -Name $Label -Cmdlet $PSCmdlet

    Returns $Out when Graph provisioned it, with a warning when it is pending, or writes
    ActivationRequestFailed.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]$Request,
        [string]$Status,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [switch]$Deactivate,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Cmdlet
    )
    $Property = $Request.PSObject.Properties['status']
    if ($null -eq $Property) {
        $Request | Add-Member -NotePropertyName status -NotePropertyValue $Status
    } elseif ($Property.IsSettable) {
        $Property.Value = $Status
    }
    $Action = if ($Deactivate) { 'deactivation' } else { 'activation' }
    $Outcome = Get-OPIMRequestOutcome -Status $Status -Deactivate:$Deactivate
    if ($Outcome -eq 'Succeeded') {
        return $Request
    }
    if ($Outcome -eq 'AwaitingDecision') {
        $Cmdlet.WriteWarning("$($Name): the $Action request is $Status. It waits for a decision and has not taken effect yet.")
        return $Request
    }
    if ($Outcome -eq 'InProgress') {
        $Cmdlet.WriteWarning("$($Name): the $Action request is $Status and has not taken effect yet.")
        return $Request
    }
    $Cmdlet.WriteError((New-OPIMRequestError -ErrorId ActivationRequestFailed -Name $Name -Status $Status -Deactivate:$Deactivate -Request $Request))
}
