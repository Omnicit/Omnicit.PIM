using namespace System.Management.Automation

function Convert-GraphHttpException {
    <#
    .SYNOPSIS
    Converts a raw Graph API HTTP exception into a structured PowerShell ErrorRecord.

    .DESCRIPTION
    Attempts to extract the JSON error body from the HTTP response content or from the exception
    message and constructs a new ErrorRecord with the parsed error code and message. The original
    exception is preserved as the InnerException of the new record. If no parseable JSON body is
    found, the original ErrorRecord is returned unchanged. Does not require typed Graph SDK classes.

    .PARAMETER errorRecord
    The ErrorRecord wrapping the raw HTTP exception thrown by Invoke-MgGraphRequest. The function
    inspects the exception's Response.Content and falls back to the exception message to locate
    the JSON error payload containing error.code and error.message fields.

    .EXAMPLE
    Convert-GraphHttpException -errorRecord $_

    Converts the current pipeline ErrorRecord to a structured Graph ErrorRecord inside a catch block.
    #>
    [OutputType([ErrorRecord])]
    param(
        [ErrorRecord]$errorRecord
    )

    $ex = $errorRecord.Exception

    # Try to read the HTTP response body
    $responseContent = $null
    if ($ex.Response -and $ex.Response.Content) {
        try {
            $responseContent = $ex.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        } catch {}
    }

    # Fallback: sometimes the JSON payload is already in the exception message
    if (-not $responseContent -and $ex.Message -like '*"error"*') {
        $responseContent = $ex.Message
    }

    if ($responseContent) {
        try {
            $parsed    = $responseContent | ConvertFrom-Json
            $errorInfo = $parsed.error
            if ($errorInfo) {
                $code      = $errorInfo.code
                $message   = $errorInfo.message
                $detail    = "$code`: $message"
                $newEx     = [System.Exception]::new($detail, $ex)
                $errRecord = [ErrorRecord]::new(
                    $newEx,
                    $code,
                    [System.Management.Automation.ErrorCategory]::OperationStopped,
                    $null
                )
                $errRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($detail)
                return $errRecord
            }
        } catch {}
    }

    return $errorRecord
}
