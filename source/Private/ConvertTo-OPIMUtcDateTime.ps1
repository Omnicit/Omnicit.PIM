function ConvertTo-OPIMUtcDateTime {
    <#
    .SYNOPSIS
    Converts a time read from Microsoft Graph or Azure Resource Manager to a UTC DateTime.

    .DESCRIPTION
    Graph and ARM send times in UTC, but the value can reach the module as a string, as a DateTime
    that the JSON reader turned into local time, or as a DateTimeOffset. This returns the same
    instant as a DateTime of Kind Utc, so a deadline compares UTC with UTC on both sides. A DateTime
    of Kind Unspecified is taken as UTC, since that is what the services send; a time a user typed
    is not for this function (ToUniversalTime reads Unspecified as local). Returns nothing for a
    null, an empty or an unreadable value.

    .PARAMETER Value
    The time as read from the service: a string, a DateTime or a DateTimeOffset.

    .EXAMPLE
    ConvertTo-OPIMUtcDateTime -Value $Request.createdDateTime

    Returns the creation time of the request in UTC.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()]$Value
    )
    process {
        if ($null -eq $Value) { return }
        if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime }
        if ($Value -is [datetime]) {
            if ($Value.Kind -eq [DateTimeKind]::Utc) { return $Value }
            if ($Value.Kind -eq [DateTimeKind]::Local) { return $Value.ToUniversalTime() }
            return [datetime]::SpecifyKind($Value, [DateTimeKind]::Utc)
        }
        $Text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($Text)) { return }
        $Parsed = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse($Text, [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed)) {
            return $Parsed.UtcDateTime
        }
    }
}
