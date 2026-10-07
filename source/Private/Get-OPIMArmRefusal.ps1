function Get-OPIMArmRefusal {
    <#
    .SYNOPSIS
    The ARM gate: returns the record that refuses an Az.Resources call, or nothing.

    .DESCRIPTION
    Called directly before every Az.Resources call in the module, and the Az.Resources call is
    never made when it returns a record. In Get-OPIMAzureRole, Disable-OPIMAzureRole and the
    activation request of Enable-OPIMAzureRole it stands inside the try that holds the call: the
    caller throws the record it returns, so the cmdlet's own catch reports it as itself. Before
    every round of Enable-OPIMAzureRole's -Wait poll it stands outside the poll's try on purpose,
    since that catch ends the command: the caller writes the record as a non-terminating error and
    stops waiting. The activation request was already sent, and the cmdlet still returns it.

    It refuses a call made on behalf of a command whose sign-in was refused: when
    Get-OPIMSignInRefusal finds a latched command on the call stack, it returns the SignInRefused
    record (New-OPIMSignInRefusedError) naming that command. Initialize-OPIMAuth latches the command
    that called it at entry and releases it only when its sign-in succeeds, and outside any try a
    cmdlet carries on past its refused sign-in, so without this gate it would act under the Azure
    context an earlier sign-in left. The latch is read only while the module holds a latch table,
    which is the case once Initialize-OPIMAuth has run in this module instance.

    It then refuses a call when Azure is signed in to another tenant than the module's Graph
    session (OPIM-08): when the auth state records the tenant of the session's Graph token
    (TokenTenantId) and the Az context is for another tenant, or there is none, it returns the
    TenantMismatch record (New-OPIMTenantMismatchError -Source Azure) naming the session's tenant.
    The Az context can change after Initialize-OPIMAuth checked it -- Connect-AzAccount or
    Set-AzContext in the same process -- so the gate compares it again before every call. The
    tenant check comes after the latch check, and reads nothing, not even Get-AzContext, while the
    module holds no sign-in: unit tests that mock Initialize-OPIMAuth never record one.

    .EXAMPLE
    $ArmRefusal = Get-OPIMArmRefusal
    if ($null -ne $ArmRefusal) { throw $ArmRefusal }

    Refuses the Az.Resources call that follows when the calling command's sign-in was refused, or
    when Azure is signed in to another tenant than the Graph session.

    .OUTPUTS
    [System.Management.Automation.ErrorRecord]
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param()

    # SEC (EntraRBAC A19): never an Az.Resources call for a command whose sign-in was refused. Without
    # a latch table Initialize-OPIMAuth never ran in this module instance, so no sign-in can have been
    # refused, and the latch is not read.
    if ($null -ne $script:_OPIMSignInLatch) {
        $Refused = Get-OPIMSignInRefusal
        if ($null -ne $Refused) {
            return (New-OPIMSignInRefusedError -Command $Refused)
        }
    }

    # SEC (OPIM-08): never an Az.Resources call under an Az context for another tenant than the
    # module's Graph session. Without a module sign-in -- no state, or a state that holds only the
    # device code mode -- there is no session tenant, and nothing is read.
    $State = $script:_OPIMAuthState
    if (-not ($State -is [System.Collections.IDictionary]) -or -not $State['TokenTenantId']) {
        return
    }
    [string]$SessionTenant = $State['TokenTenantId']
    $AzContext = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $AzContext -or [string]$AzContext.Tenant.Id -ne $SessionTenant) {
        return (New-OPIMTenantMismatchError -RequestedTenant $SessionTenant -Source Azure)
    }
}
