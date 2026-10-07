function Lock-OPIMSignIn {
    <#
    .SYNOPSIS
    Latches the command that called Initialize-OPIMAuth, so the module sends nothing for it until its
    sign-in succeeds.

    .DESCRIPTION
    Called only by Initialize-OPIMAuth, directly after its BL-74 check. It finds the invocation of the
    command that called Initialize-OPIMAuth -- the first frame of the call stack, after this function's
    own frame and Initialize-OPIMAuth's, that carries an invocation -- records it in the module's
    sign-in latch, and returns it. That command is a pillar cmdlet (Get-, Enable- and Disable- for
    DirectoryRole, AzureRole and EntraIDGroup), Wait-OPIMDirectoryRole, Connect-OPIM, or
    Invoke-OPIMGraphRequest itself for the sign-in of its claims step-up or its token-rejected retry,
    which it calls from its own body.

    Initialize-OPIMAuth hands that invocation to Unlock-OPIMSignIn when the sign-in succeeds; every
    refusal, terminating error and early return leaves it latched -- except the BL-74 refusal before
    this call, which latches nothing of its own. Both transports then refuse every request that
    command makes: Get-OPIMSignInRefusal finds it on the call stack and the request is refused with
    SignInRefused, in Invoke-OPIMGraphRequest and in the ARM gate Get-OPIMArmRefusal -- except that
    the Graph wrapper's session gate, which comes first, still reports a changed session as
    GraphSessionChanged.

    The latch is keyed on the calling command's invocation rather than held as one module-wide value,
    since a nested command or a pipeline neighbour signs in on its own: its success must release only
    its own entry, never the refused command's. The table ($script:_OPIMSignInLatch, created here on
    first use) is a ConditionalWeakTable and stores only the boolean $true. Its keys are the commands'
    own invocation objects, held weakly, so the table keeps no command alive, and used only for their
    identity: the decision is a lookup by reference and never reads a key, although each one carries
    its command's bound parameters, a tenant among them.

    .EXAMPLE
    $SignInCaller = Lock-OPIMSignIn

    Latches the command that called Initialize-OPIMAuth and keeps its invocation for Unlock-OPIMSignIn.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.InvocationInfo])]
    param()

    # Frame 0 is this function and frame 1 is Initialize-OPIMAuth; the caller is the next frame that
    # carries an invocation. A frame's invocation is the very object $MyInvocation holds in that
    # command (begin, process and end alike), which is what Get-OPIMSignInRefusal looks up.
    # Module-qualified, so a function named Get-PSCallStack defined in the session cannot turn the
    # latch off.
    $Stack = @(Microsoft.PowerShell.Utility\Get-PSCallStack)
    $Caller = $null
    for ($Index = 2; $Index -lt $Stack.Count; $Index++) {
        if ($null -ne $Stack[$Index].InvocationInfo) {
            $Caller = $Stack[$Index].InvocationInfo
            break
        }
    }

    if ($null -eq $script:_OPIMSignInLatch) {
        $script:_OPIMSignInLatch = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
    }
    $script:_OPIMSignInLatch.AddOrUpdate($Caller, $true)
    $Caller
}
