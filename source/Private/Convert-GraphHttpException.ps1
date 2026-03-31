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

    $Ex = $errorRecord.Exception

    # Try to read the HTTP response body
    $ResponseContent = $null
    if ($Ex.Response -and $Ex.Response.Content) {
        try {
            $ResponseContent = $Ex.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        } catch {
            Write-Verbose "Could not read HTTP response content: $_"
        }
    }

    # Fallback: sometimes the JSON payload is already in the exception message
    if (-not $ResponseContent -and $Ex.Message -like '*"error"*') {
        $ResponseContent = $Ex.Message
    }

    if ($ResponseContent) {
        try {
            $Parsed    = $ResponseContent | ConvertFrom-Json
            $ErrorInfo = $Parsed.error
            if ($ErrorInfo) {
                $Code      = $ErrorInfo.code
                $Message   = $ErrorInfo.message
                $Detail    = "$Code`: $Message"
                $NewEx     = [System.Exception]::new($Detail, $Ex)
                $ErrRecord = [ErrorRecord]::new(
                    $NewEx,
                    $Code,
                    [System.Management.Automation.ErrorCategory]::OperationStopped,
                    $null
                )
                $ErrRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Detail)
                return $ErrRecord
            }
        } catch {
            Write-Verbose "Could not parse Graph error JSON from response body: $_"
        }
    }

    return $errorRecord
}
