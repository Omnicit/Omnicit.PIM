function Set-OPIMCompletionState {
    <#
    .SYNOPSIS
    Marks whether a tab completion is listing roles or groups right now.
    .DESCRIPTION
    Sets the module flag $script:_OPIMCompletionInProgress, which both transports read at their
    decision to wait out throttling: during a tab completion they never wait, so a completion under
    throttling fails at once instead of holding the prompt (scope 5b). The six argument completers set
    it before their listing and clear it in a finally block, through [scriptblock]::Create, as they
    call the listing.
    .PARAMETER InProgress
    $true while a completion lists, $false after it.
    .EXAMPLE
    Set-OPIMCompletionState -InProgress $true
    Marks a completion as running.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Sets an internal module flag that only the transports read; it changes no state a user sees, and the completers must set and clear it unconditionally.')]
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)][bool]$InProgress
    )
    $script:_OPIMCompletionInProgress = $InProgress
}
