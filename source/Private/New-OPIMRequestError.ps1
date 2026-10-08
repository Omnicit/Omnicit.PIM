function New-OPIMRequestError {
    <#
    .SYNOPSIS
    Builds the error record for a request that failed or a wait that timed out.

    .DESCRIPTION
    The single owner of the ErrorIds ActivationRequestFailed and ActivationWaitTimedOut and of
    their messages; build those records nowhere else. It is pure: it returns an ErrorRecord and
    writes nothing. The caller writes it.

    ActivationRequestFailed (category InvalidResult): Microsoft Graph or Azure accepted the request
    and answered it with a status that is no success and no pending state (Get-OPIMRequestOutcome
    returns Failed), so it did not take effect.

    ActivationWaitTimedOut (category OperationTimeout): the request was still in progress when the
    wait reached -TimeoutSeconds. The request itself stays submitted.

    The record's target object is the request.

    .PARAMETER ErrorId
    ActivationRequestFailed or ActivationWaitTimedOut.

    .PARAMETER Name
    The label of the role or group the request is for, as Get-OPIMScheduleName gives it.

    .PARAMETER Status
    The last status of the request.

    .PARAMETER Deactivate
    The request is a deactivation; the message says so.

    .PARAMETER TimeoutSeconds
    For ActivationWaitTimedOut, the limit the wait reached.

    .PARAMETER Request
    The request object; it becomes the record's target object.

    .EXAMPLE
    New-OPIMRequestError -ErrorId ActivationRequestFailed -Name 'Reader -> rg-app' -Status 'Denied' -Request $Response

    Returns the record for an activation that Azure denied.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'A pure record builder: it changes no state; the New- verb draws the rule onto it.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)][ValidateSet('ActivationRequestFailed', 'ActivationWaitTimedOut')][string]$ErrorId,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [string]$Status,
        [switch]$Deactivate,
        [int]$TimeoutSeconds,
        $Request
    )
    $Action = if ($Deactivate) { 'deactivation' } else { 'activation' }
    if ($ErrorId -eq 'ActivationRequestFailed') {
        $Shown = if ([string]::IsNullOrWhiteSpace($Status)) { 'no status' } else { "status '$Status'" }
        $Message = "$($Name): the $Action request ended with $Shown and did not take effect."
        $Category = [System.Management.Automation.ErrorCategory]::InvalidResult
    } else {
        $Message = "$($Name): the $Action request has not completed within $TimeoutSeconds seconds (last status: $Status). The wait has ended; the request stays submitted and may still complete."
        $Category = [System.Management.Automation.ErrorCategory]::OperationTimeout
    }
    [System.Management.Automation.ErrorRecord]::new([System.Exception]::new($Message), $ErrorId, $Category, $Request)
}
