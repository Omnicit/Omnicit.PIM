function New-OPIMSignInRefusedError {
    <#
    .SYNOPSIS
    Builds the SignInRefused error record.

    .DESCRIPTION
    The single owner of the SignInRefused id and message. The module's transports raise it before a
    request made on behalf of a command whose sign-in was refused -- a command Get-OPIMSignInRefusal
    finds latched on the call stack -- so nothing is sent for that command under the session or the
    token an earlier sign-in left: Invoke-OPIMGraphRequest before every Graph call, and the ARM gate
    Get-OPIMArmRefusal before every Az.Resources call. Invoke-OPIMGraphRequest checks its session
    gate first, so a Graph request made while the Graph SDK session is changed is refused as
    GraphSessionChanged instead. The target is the latched command's name, which is the immediate
    caller of Initialize-OPIMAuth: the cmdlet (a pillar cmdlet, Wait-OPIMDirectoryRole or
    Connect-OPIM), for a sign-in refused at its entry, or Invoke-OPIMGraphRequest, for one refused
    during that wrapper's own claims step-up or token-rejected retry. The message names no tenant, no
    account and no token: it is fixed text, and the command's name is the only value the record
    carries.

    Initialize-OPIMAuth raises it too, as a terminating error before any token call or Connect-MgGraph
    and before it latches its own caller, when a command OUTSIDE the one that called it is latched
    (Get-OPIMSignInRefusal -OutsideCaller): a cmdlet that a refused command calls, or a sign-in made
    inside a refused command's output. The target is then that latched outer command's name, and the
    request the fixed message calls "this request" is the sign-in, which is not made.

    .PARAMETER Command
    The name of the command whose sign-in was refused, as Get-OPIMSignInRefusal returns it, with or
    without -OutsideCaller ('a script block' when the held frame carries no command name). It becomes
    the record's target object.

    .EXAMPLE
    throw (New-OPIMSignInRefusedError -Command 'Get-OPIMDirectoryRole')

    Refuses a request made on behalf of Get-OPIMDirectoryRole after its sign-in was refused.

    .OUTPUTS
    [System.Management.Automation.ErrorRecord]
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory error-record builder; returns an ErrorRecord and performs no state change, so ShouldProcess does not apply.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    [System.Management.Automation.ErrorRecord]::new(
        [System.Exception]::new(
            "The module's sign-in for this command was refused, so Omnicit.PIM sends nothing for " +
            'this command: this request was not sent. Run Connect-OPIM, or run a new command whose ' +
            'sign-in succeeds, to send requests again.'),
        'SignInRefused',
        [System.Management.Automation.ErrorCategory]::AuthenticationError,
        $Command)
}
