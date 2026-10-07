function Unlock-OPIMSignIn {
    <#
    .SYNOPSIS
    Releases the sign-in latch of one command, after its sign-in succeeded.

    .DESCRIPTION
    Called only by Initialize-OPIMAuth, where a sign-in succeeded: at its cached return, and as the
    last statement of a new sign-in that went the whole way. It removes the given invocation -- the
    one Lock-OPIMSignIn returned at entry -- from the module's sign-in latch, and nothing else, so a
    nested command's or a pipeline neighbour's success never releases another command that is still
    latched. It does nothing when the latch table has not been created, and creates none.

    .PARAMETER Invocation
    The invocation of the command whose sign-in succeeded, exactly as Lock-OPIMSignIn returned it at
    the entry of the same Initialize-OPIMAuth call.

    .EXAMPLE
    Unlock-OPIMSignIn -Invocation $SignInCaller

    Releases the command Lock-OPIMSignIn latched at the entry of this Initialize-OPIMAuth call.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.InvocationInfo]$Invocation
    )

    if ($null -ne $script:_OPIMSignInLatch) {
        $null = $script:_OPIMSignInLatch.Remove($Invocation)
    }
}
