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

    The record is the one Convert-OPIMArmHttpException (Azure Resource Manager) or
    Convert-GraphHttpException (Microsoft Graph) built: its FullyQualifiedErrorId is the service's
    error.code and its exception message carries error.message (for ARM also error.details), with no
    inner exception. The keywords are searched in the id and the message only; an inner exception is
    never read.

    .PARAMETER CaughtError
    The ErrorRecord caught in the activation catch block, as built by Convert-OPIMArmHttpException
    or Convert-GraphHttpException.

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

    # The combined text of the error ID and the message body: the service's error.code and error.message
    # (and error.details for ARM), as Convert-OPIMArmHttpException and Convert-GraphHttpException put them
    # into the record. No inner exception is read -- neither of them chains one.
    $AllMsgs = "$($CaughtError.FullyQualifiedErrorId) $($CaughtError.Exception.Message)"

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
        $ExpMsg = 'Your PIM policy requires a shorter expiration. Use -Hours, or -Until on the Enable-OPIM* cmdlets, to ask for a shorter activation.'
        Write-CmdletError `
            -Message ([System.Exception]::new($ExpMsg, $CaughtError.Exception)) `
            -ErrorId 'RoleAssignmentRequestPolicyValidationFailed' `
            -Category OperationStopped `
            -Cmdlet $Cmdlet
        return $true
    }

    return $false
}
