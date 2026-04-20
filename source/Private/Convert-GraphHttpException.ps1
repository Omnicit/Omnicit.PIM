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

    .PARAMETER InputRecord
    The ErrorRecord wrapping the raw HTTP exception thrown by Invoke-MgGraphRequest. The function
    inspects the exception's Response.Content and falls back to the exception message to locate
    the JSON error payload containing error.code and error.message fields.

    .EXAMPLE
    Convert-GraphHttpException $_

    Converts the current pipeline ErrorRecord to a structured Graph ErrorRecord inside a catch block.
    #>
    [OutputType([ErrorRecord])]
    param(
        [ErrorRecord]$InputRecord
    )

    $Exception = $InputRecord.Exception

    # Try to read the HTTP response body
    $ResponseContent = $null
    if ($Exception.Response -and $Exception.Response.Content) {
        try {
            $ResponseContent = $Exception.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        } catch {
            Write-Verbose "Could not read HTTP response content: $_"
        }
    }

    # Fallback: sometimes the JSON payload is already in the exception message
    if (-not $ResponseContent -and $Exception.Message -like '*"error"*') {
        $ResponseContent = $Exception.Message
    }

    if ($ResponseContent) {
        try {
            $Parsed    = $ResponseContent | ConvertFrom-Json
            $ErrorInfo = $Parsed.error
            if ($ErrorInfo) {
                $ErrorCode   = $ErrorInfo.code
                $ErrorMessage = $ErrorInfo.message
                $Detail       = "$ErrorCode`: $ErrorMessage"
                $NewException = [System.Exception]::new($Detail, $Exception)
                $ErrorRecord  = [ErrorRecord]::new(
                    $NewException,
                    $ErrorCode,
                    [System.Management.Automation.ErrorCategory]::OperationStopped,
                    $null
                )
                $ErrorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Detail)
                return $ErrorRecord
            }
        } catch {
            Write-Verbose "Could not parse Graph error JSON from response body: $_"
        }
    }

    return $InputRecord
}
