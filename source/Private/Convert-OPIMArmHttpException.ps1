function Convert-OPIMArmHttpException {
    <#
    .SYNOPSIS
    Converts a non-success Azure Resource Manager HTTP response into a structured ErrorRecord.

    .DESCRIPTION
    The ARM sibling of Convert-GraphHttpException. Invoke-OPIMArmRequest sends every Azure Resource
    Manager request with Invoke-WebRequest -SkipHttpErrorCheck, so a non-2xx response is returned
    rather than thrown, and is normalized to a plain object with StatusCode, Content and Headers
    before it reaches this function.

    This function reads StatusCode and Content only. The header collection is never read, never put
    in the message and never attached to the record: ARM response headers carry correlation ids and
    quota telemetry, and only Invoke-OPIMArmRequest reads one of them (Retry-After). The status is
    read with -as [int], so a status that is not a number reads as 0 instead of throwing.

    The ARM error body is { "error": { "code", "message", "details" } }. With an error code, the
    record's FullyQualifiedErrorId is that code and its message is "<code>: <message>" (the code alone
    when the body carries no message). Without one, the id is ArmTransportError and the message is
    "HTTP <status>: <message>", or "HTTP <status>: Azure Resource Manager returned no error code."
    when the body carries no message either -- an HTML gateway page, an empty body. No other id is
    made up from the status. When error.details holds entries -- ARM's nested reasons for an opaque
    code such as InvalidPolicy -- each entry's "<code>: <message>" is appended in parentheses,
    separated by "; ". A body that is not pure JSON is searched for its first "code" and "message"
    with regular expressions; the parse failure is scrubbed with Remove-OPIMErrorRecord.

    ErrorDetails carries the same text, set through its constructor. The category is
    OperationStopped and the target object is -Path. No exception is chained.

    .PARAMETER Response
    The normalized response Invoke-OPIMArmRequest built: an object with StatusCode and Content. A
    Headers property, when present, is never read.

    .PARAMETER Path
    The ARM request path, used as the TargetObject of the record.

    .EXAMPLE
    throw (Convert-OPIMArmHttpException -Response $Response -Path $Path)

    Converts a failed ARM response into an ErrorRecord whose id is the ARM error code and throws it.

    .OUTPUTS
    [System.Management.Automation.ErrorRecord]
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [object]$Response,

        [string]$Path
    )

    # -as [int], never a cast: a status that is not numeric must not throw from the failure path and
    # replace the ARM error with a conversion error.
    $StatusCode = $Response.StatusCode -as [int]
    if ($null -eq $StatusCode) { $StatusCode = 0 }
    $Content = [string]$Response.Content

    $ErrorCode = $null
    $ErrorMessage = $null
    $NestedDetail = $null
    if ($Content) {
        # Preferred path: clean ARM error JSON. -ErrorAction Stop makes a parse failure terminating so
        # the catch runs and the failure is removed from $Error.
        try {
            $ErrorInfo = ($Content | ConvertFrom-Json -ErrorAction Stop).error
            if ($ErrorInfo) {
                $ErrorCode = [string]$ErrorInfo.code
                $ErrorMessage = [string]$ErrorInfo.message
                # ARM hides the actionable reason for an opaque code (InvalidPolicy: which rule or field)
                # under error.details. Appended only when present, so a simple error keeps its message.
                if ($ErrorInfo.details) {
                    $DetailParts = foreach ($Item in @($ErrorInfo.details)) {
                        $ItemCode = [string]$Item.code
                        $ItemMessage = [string]$Item.message
                        if ($ItemCode -and $ItemMessage) { "$ItemCode`: $ItemMessage" }
                        elseif ($ItemMessage) { $ItemMessage }
                        elseif ($ItemCode) { $ItemCode }
                    }
                    $DetailParts = @($DetailParts | Where-Object { $_ })
                    if ($DetailParts.Count -gt 0) { $NestedDetail = $DetailParts -join '; ' }
                }
            }
        } catch {
            Remove-OPIMErrorRecord -Record $PSItem
        }

        # Fallback: the first embedded code and message of a body that is not pure JSON.
        if (-not $ErrorMessage -and $Content -match '"message"\s*:\s*"([^"]+)"') { $ErrorMessage = $Matches[1] }
        if (-not $ErrorCode -and $Content -match '"code"\s*:\s*"([^"]+)"') { $ErrorCode = $Matches[1] }
    }

    if ($ErrorCode) {
        $Detail = if ($ErrorMessage) { "$ErrorCode`: $ErrorMessage" } else { [string]$ErrorCode }
    } else {
        # No ARM error code: no id is made up from the status (no StatusLabels table).
        $ErrorCode = 'ArmTransportError'
        $Detail = if ($ErrorMessage) {
            "HTTP $StatusCode`: $ErrorMessage"
        } else {
            "HTTP $StatusCode`: Azure Resource Manager returned no error code."
        }
    }
    if ($NestedDetail) { $Detail = "$Detail ($NestedDetail)" }

    $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
        [System.Exception]::new($Detail),
        $ErrorCode,
        [System.Management.Automation.ErrorCategory]::OperationStopped,
        $Path
    )
    $ErrorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Detail)
    $ErrorRecord
}
