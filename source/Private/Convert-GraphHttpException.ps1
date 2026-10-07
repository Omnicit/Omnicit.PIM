using namespace System.Management.Automation

function Convert-GraphHttpException {
    <#
    .SYNOPSIS
    Converts a raw Graph API HTTP exception into a structured PowerShell ErrorRecord.

    .DESCRIPTION
    Attempts to extract the JSON error body from the HTTP response content or from the exception
    message and constructs a new ErrorRecord with the parsed error code and message. The original
    exception is deliberately NOT chained as the InnerException of the new record: the raw Graph SDK
    exception holds the HttpRequestMessage, whose Authorization header carries the bearer token in
    plain text, so chaining it would leak the token whenever the error is displayed or logged. The
    Graph error code and message are preserved in the new exception text and ErrorDetails. This
    function ALWAYS returns a freshly built ErrorRecord and NEVER falls through to returning the raw
    InputRecord: the raw record's .Exception is the original Graph SDK exception, which for a
    transport failure (no HTTP response at all, or a non-JSON body such as an HTML gateway page)
    still references that same bearer-carrying HttpRequestMessage, so letting it escape unconverted
    would defeat the whole point of this function. When no Graph error code can be extracted, no
    error id is invented: the new record keeps the id the input record carried -- its
    FullyQualifiedErrorId STRING, never the record or its exception -- or, when that string is empty,
    the input exception's type name. The HTTP status, when the response has one, goes into the
    detail text instead ("HTTP 403: <message>"), and the exception's Message STRING (safe to reuse --
    only the exception OBJECT is dangerous) is the message. Does not require typed Graph SDK classes.

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
            Remove-OPIMErrorRecord -Record $PSItem
            Write-Verbose "Could not read HTTP response content: $_"
        }
    }

    # Fallback: the JSON payload is often embedded in the exception message. It may be the whole
    # message (a single failed request) or wrapped in non-JSON text -- for example a Graph SDK retry
    # AggregateException reads "Too many retries performed... (HTTP request failed... {"error":...})".
    if (-not $ResponseContent -and $Exception.Message -like '*"error"*') {
        $ResponseContent = $Exception.Message
    }

    $ErrorCode    = $null
    $ErrorMessage = $null

    if ($ResponseContent) {
        # Preferred path: the content is a clean JSON error body. -ErrorAction Stop makes a parse
        # failure terminating so the catch below actually runs; without it ConvertFrom-Json writes a
        # non-terminating error that bypasses the catch and is left in the caller's $Error.
        try {
            $ErrorInfo = ($ResponseContent | ConvertFrom-Json -ErrorAction Stop).error
            if ($ErrorInfo) {
                $ErrorCode    = [string]$ErrorInfo.code
                $ErrorMessage = [string]$ErrorInfo.message
            }
        } catch {
            # The content is not pure JSON (for example a wrapped retry/aggregate message, or an HTML
            # gateway page). Remove the parse failure from $Error so it does not pollute the caller's
            # $Error, then fall through to targeted extraction below.
            Remove-OPIMErrorRecord -Record $PSItem
        }

        # Fallback path: pull the first embedded code/message out of wrapped text so throttling
        # (TooManyRequests) and other aggregate failures still convert into a clean, single error.
        if (-not $ErrorMessage -and $ResponseContent -match '"message"\s*:\s*"([^"]+)"') { $ErrorMessage = $Matches[1] }
        if (-not $ErrorCode    -and $ResponseContent -match '"code"\s*:\s*"([^"]+)"')    { $ErrorCode    = $Matches[1] }
    }

    # Some Graph errors return an empty or unextractable code (for example a 403 "Attempted to
    # perform an unauthorized operation.", a transport failure with no response body at all, or an
    # HTML gateway page). No error id is invented for them: the new record keeps the id the caller
    # saw before -- the input record's FullyQualifiedErrorId STRING; the record and its exception
    # are never reused -- or, when that string is empty, the input exception's type name. The HTTP
    # status goes into the detail text instead, so the failure stays diagnosable and this function
    # never has a reason to fall through to returning the raw InputRecord below.
    $HasGraphCode = [bool]$ErrorCode
    $StatusCode = $null
    if (-not $HasGraphCode) {
        try { $StatusCode = [int]$Exception.Response.StatusCode } catch { Remove-OPIMErrorRecord -Record $PSItem }
        $ErrorCode = [string]$InputRecord.FullyQualifiedErrorId
        if ([string]::IsNullOrWhiteSpace($ErrorCode)) {
            $ErrorCode = if ($null -ne $Exception) { $Exception.GetType().FullName } else { [System.Exception].FullName }
        }
    }

    # SECURITY: never fall through to the raw InputRecord. Its .Exception is the original Graph SDK
    # exception, which for a transport failure references the HttpRequestMessage whose Authorization
    # header carries the bearer token in plain text. The exception's Message STRING is safe to reuse
    # here (it is just text); the exception OBJECT is not, so it is never chained as -InnerException.
    if (-not $ErrorMessage) { $ErrorMessage = $Exception.Message }
    $Detail = if ($HasGraphCode) {
        if ($ErrorMessage) { "$ErrorCode`: $ErrorMessage" } else { [string]$ErrorCode }
    } else {
        $StatusText = if ($StatusCode) { "HTTP $StatusCode" } else { $null }
        if ($StatusText -and $ErrorMessage) { "$StatusText`: $ErrorMessage" }
        elseif ($StatusText) { $StatusText }
        elseif ($ErrorMessage) { [string]$ErrorMessage }
        else { [string]$ErrorCode }
    }

    $NewException = [System.Exception]::new($Detail)
    $ErrorRecord  = [ErrorRecord]::new(
        $NewException,
        $ErrorCode,
        [System.Management.Automation.ErrorCategory]::OperationStopped,
        $null
    )
    $ErrorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Detail)
    return $ErrorRecord
}
