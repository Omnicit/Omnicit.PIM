using namespace System.Management.Automation
function Write-CmdletError {
    <#
    .SYNOPSIS
    Emits a structured ErrorRecord through the calling cmdlet's error channel.

    .DESCRIPTION
    Creates a System.Management.Automation.ErrorRecord from the supplied exception and dispatches
    it through the provided cmdlet context. By default the error is non-terminating (WriteError).
    Specify -Terminating to call ThrowTerminatingError instead for pipeline-terminating errors.

    .PARAMETER Message
    The Exception object used to construct the ErrorRecord. Its message and type are preserved in
    the resulting ErrorRecord. Use [System.Exception]::new('text') to wrap a plain string.

    .PARAMETER ErrorId
    A short, stable identifier assigned as the FullyQualifiedErrorId of the ErrorRecord.
    Use a descriptive PascalCase value such as RoleNotFound or RequestFailed.

    .PARAMETER Category
    The ErrorCategory that classifies the error type. Defaults to InvalidOperation.
    Accepts any System.Management.Automation.ErrorCategory enum value.

    .PARAMETER TargetObject
    The object being processed when the error occurred. Defaults to the current pipeline
    object ($PSItem). Surfaced as ErrorRecord.TargetObject for the caller to inspect.

    .PARAMETER cmdlet
    The PSCmdlet instance used to emit the error record. Defaults to $PSCmdlet of the calling
    function. Supply a mock cmdlet object in tests to capture ErrorRecords without side effects.

    .PARAMETER Terminating
    Switch that promotes the error to a terminating error via ThrowTerminatingError. Without this
    switch the error is emitted as a non-terminating error via WriteError.

    .PARAMETER Details
    Optional plain-text detail message attached to the ErrorRecord as ErrorDetails.Message. Shown
    in some hosts in addition to the exception message for extra context.

    .EXAMPLE
    Write-CmdletError -Message ([System.Exception]::new('Role not found')) -ErrorId 'RoleNotFound' -cmdlet $PSCmdlet

    Emits a non-terminating InvalidOperation ErrorRecord from within a cmdlet or advanced function.
    #>
    param(
        [Exception]$Message = 'An Error Occured in the cmdlet',
        [String]$ErrorId,
        [ErrorCategory]$Category = 'InvalidOperation',
        $TargetObject = $PSItem,
        $cmdlet = $PSCmdlet,
        [Switch]$Terminating,
        [String]$Details
    )
    process {
        $errorRecord = [ErrorRecord]::new(
            $Message,
            $ErrorId,
            $Category,
            $TargetObject
        )
        if ($Details) {
            $errorRecord.ErrorDetails = [ErrorDetails]::new($Details)
        }
        if ($Terminating) {
            $cmdlet.ThrowTerminatingError(
                $ErrorRecord
            )
        } else {
            $cmdlet.WriteError(
                $ErrorRecord
            )
        }
    }
}
