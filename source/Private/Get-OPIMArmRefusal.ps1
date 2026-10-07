function Get-OPIMArmRefusal {
    <#
    .SYNOPSIS
    The ARM gate: returns the record that refuses an Az.Resources call, or nothing.

    .DESCRIPTION
    Called inside the try that holds every Az.Resources call in the module, directly before it --
    Get-OPIMAzureRole, Enable-OPIMAzureRole (the activation request and every round of its -Wait
    poll) and Disable-OPIMAzureRole. The caller throws the record it returns, so the cmdlet's own
    catch reports it as itself, and the Az.Resources call is never made.

    It refuses a call made on behalf of a command whose sign-in was refused: when
    Get-OPIMSignInRefusal finds a latched command on the call stack, it returns the SignInRefused
    record (New-OPIMSignInRefusedError) naming that command. Initialize-OPIMAuth latches the command
    that called it at entry and releases it only when its sign-in succeeds, and outside any try a
    cmdlet carries on past its refused sign-in, so without this gate it would act under the Azure
    context an earlier sign-in left.

    It returns at once and calls nothing when the module holds no sign-in latch at all, which is
    the case until Initialize-OPIMAuth has run once in this module instance: unit tests that mock
    Initialize-OPIMAuth never create one.

    .EXAMPLE
    $ArmRefusal = Get-OPIMArmRefusal
    if ($null -ne $ArmRefusal) { throw $ArmRefusal }

    Refuses the Az.Resources call that follows when the calling command's sign-in was refused.

    .OUTPUTS
    [System.Management.Automation.ErrorRecord]
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param()

    # No latch table: Initialize-OPIMAuth never ran in this module instance, so no sign-in can have
    # been refused. Nothing is called.
    if ($null -eq $script:_OPIMSignInLatch) {
        return
    }

    # SEC (EntraRBAC A19): never an Az.Resources call for a command whose sign-in was refused.
    $Refused = Get-OPIMSignInRefusal
    if ($null -ne $Refused) {
        return (New-OPIMSignInRefusedError -Command $Refused)
    }
}
