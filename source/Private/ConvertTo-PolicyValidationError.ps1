function ConvertTo-PolicyValidationError {
    <#
    .SYNOPSIS
    Handles PIM policy validation failures from activation requests.

    .DESCRIPTION
    Shared helper used by Enable-OPIMAzureRole, Enable-OPIMDirectoryRole, and
    Enable-OPIMEntraIDGroup to avoid repeating the JustificationRule/ExpirationRule
    error-handling pattern.

    Inspects the caught ErrorRecord for well-known policy rule keywords and emits a
    user-friendly non-terminating error via Write-CmdletError. Returns $true when a
    policy violation was recognised so the caller can continue to the next item.
    Returns $false when the error is not a recognised policy violation so the caller
    can re-emit the original error.

    .PARAMETER CaughtError
    The ErrorRecord caught in the activation catch block.

    .PARAMETER ResourceType
    Human-readable noun used in the error message (e.g. 'role' or 'group').
    Defaults to 'role'.

    .PARAMETER Cmdlet
    The PSCmdlet of the calling public function. Used to emit the error record correctly
    so that it is attributed to the caller rather than this helper.

    .OUTPUTS
    [bool] $true when a policy violation was handled; $false when it was not.

    .EXAMPLE
    } catch {
        if (-not (ConvertTo-PolicyValidationError -CaughtError $PSItem -ResourceType 'role' -Cmdlet $PSCmdlet)) {
            $PSCmdlet.WriteError($PSItem)
        }
        continue
    }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$CaughtError,

        [string]$ResourceType = 'role',

        [Parameter(Mandatory)]
        $Cmdlet
    )

    # Build a combined message string that covers both the error ID and message body,
    # plus the inner exception message when present (Az.Resources wraps the detail there).
    $AllMsgs = "$($CaughtError.FullyQualifiedErrorId) $($CaughtError.Exception.Message)"
    if ($CaughtError.Exception.InnerException) {
        $AllMsgs += ' ' + $CaughtError.Exception.InnerException.Message
    }

    if ($AllMsgs -match 'JustificationRule') {
        $JustMsg = "Your PIM policy requires a justification for this $ResourceType. Use the -Justification parameter."
        Write-CmdletError `
            -Message ([System.Exception]::new($JustMsg, $CaughtError.Exception)) `
            -ErrorId 'RoleAssignmentRequestPolicyValidationFailed' `
            -Category OperationStopped `
            -Cmdlet $Cmdlet
        return $true
    }

    if ($AllMsgs -match 'ExpirationRule') {
        $ExpMsg = 'Your PIM policy requires a shorter expiration. Use -NotAfter to specify an earlier time.'
        Write-CmdletError `
            -Message ([System.Exception]::new($ExpMsg, $CaughtError.Exception)) `
            -ErrorId 'RoleAssignmentRequestPolicyValidationFailed' `
            -Category OperationStopped `
            -Cmdlet $Cmdlet
        return $true
    }

    return $false
}
