function ConvertTo-ActiveDurationTooShortError {
    <#
    .SYNOPSIS
    Handles an ActiveDurationTooShort error from a PIM deactivation request.

    .DESCRIPTION
    Shared helper used by Disable-OPIMAzureRole, Disable-OPIMDirectoryRole, and
    Disable-OPIMEntraIDGroup to avoid repeating the cooldown error-handling pattern.

    When the caught ErrorRecord indicates that the activation has not been active long enough
    (ActiveDurationTooShort), the function emits a user-friendly non-terminating error via
    Write-CmdletError and returns $true so the caller knows to exit its current iteration.

    When the caught error is NOT an ActiveDurationTooShort error, the function returns $false
    so the caller can re-emit the original error and continue with its own flow.

    .PARAMETER CaughtError
    The ErrorRecord caught in the deactivation catch block.

    .PARAMETER ResourceType
    Human-readable noun used in the error message (e.g. 'role' or 'group').
    Defaults to 'role'.

    .PARAMETER Cmdlet
    The PSCmdlet of the calling public function. Used to emit the error record correctly
    so that it is attributed to the caller rather than this helper.

    .OUTPUTS
    [bool] $true when the cooldown error was handled; $false when it was not.

    .EXAMPLE
    } catch {
        if (-not (ConvertTo-ActiveDurationTooShortError -CaughtError $PSItem -ResourceType 'role' -Cmdlet $PSCmdlet)) {
            $PSCmdlet.WriteError($PSItem)
        }
        return
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

    $IsActiveDurationTooShort = ($CaughtError.FullyQualifiedErrorId -like 'ActiveDurationTooShort*') -or
                                ($CaughtError.Exception.Message -match 'ActiveDurationTooShort')

    if (-not $IsActiveDurationTooShort) {
        return $false
    }

    $CooldownMsg = "You must wait at least 5 minutes after activating a $ResourceType before you can deactivate it."
    Write-CmdletError `
        -Message ([System.Exception]::new($CooldownMsg, $CaughtError.Exception)) `
        -ErrorId 'ActiveDurationTooShort' `
        -Category ResourceUnavailable `
        -Cmdlet $Cmdlet

    return $true
}
