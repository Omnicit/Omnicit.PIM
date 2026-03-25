using namespace System.Management.Automation

function Convert-GraphHttpException {
    <#
    .SYNOPSIS
    Parses raw Graph API HTTP error responses into structured ErrorRecords.
    Works with raw Invoke-MgGraphRequest errors without requiring typed Graph SDK classes.
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
