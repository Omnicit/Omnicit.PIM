function Get-OPIMArmRefusal {
    <#
    .SYNOPSIS
    The ARM gate: returns the record that refuses an Azure Resource Manager request, or nothing.

    .DESCRIPTION
    Called by Invoke-OPIMArmRequest before every request it sends -- the first attempt, each
    throttled retry, the retry after a 401 refresh and every page of a -All read -- and the request
    is never sent when it returns a record: the transport throws the record and returns.

    It refuses a request made on behalf of a command whose sign-in was refused: when
    Get-OPIMSignInRefusal finds a latched command on the call stack, it returns the SignInRefused
    record (New-OPIMSignInRefusedError) naming that command. Initialize-OPIMAuth latches the command
    that called it at entry and releases it only when its sign-in succeeds, and outside any try a
    cmdlet carries on past its refused sign-in, so without this gate it would send the ARM token an
    earlier sign-in left. The latch is read only while the module holds a latch table, which is the
    case once Initialize-OPIMAuth has run in this module instance.

    It then refuses a request whose Azure Resource Manager token was not issued for the module's
    Graph session (OPIM-08, A3). It reads the ARM token's own claims -- the tid and the oid of the
    SecureString Initialize-OPIMAuth -IncludeARM keeps in the auth state, through
    Get-OPIMTokenTenantId and Get-OPIMTokenObjectId -- and compares them with the tenant of the
    session's Graph token (TokenTenantId) and the account it signed in with (ObjectId). A token for
    another tenant is TenantMismatch (New-OPIMTenantMismatchError -Source Azure), and so is a token
    whose tenant cannot be read (-Unreadable); a token for another account is AccountMismatch
    (New-OPIMAccountMismatchError), and so is a token or a state whose account cannot be read
    (-Unreadable). Both records name only the session's tenant. The tenant is compared before the
    account, and both without regard to case. No Az context is read.

    Without a module sign-in -- no state, a state that is not a dictionary, or a state that holds
    only the device code mode -- and without an ARM token in the state, it reads nothing and returns
    nothing: Invoke-OPIMArmRequest refuses a request without a token itself
    (ArmTokenAcquisitionFailed).

    .EXAMPLE
    $ArmRefusal = Get-OPIMArmRefusal
    if ($null -ne $ArmRefusal) { throw $ArmRefusal }

    Refuses the ARM request that follows when the calling command's sign-in was refused, or when the
    session's ARM token was issued for another tenant or another account than its Graph sign-in.

    .OUTPUTS
    [System.Management.Automation.ErrorRecord]
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param()

    # SEC (EntraRBAC A19): never an ARM request for a command whose sign-in was refused. Without a
    # latch table Initialize-OPIMAuth never ran in this module instance, so no sign-in can have been
    # refused, and the latch is not read.
    if ($null -ne $script:_OPIMSignInLatch) {
        $Refused = Get-OPIMSignInRefusal
        if ($null -ne $Refused) {
            return (New-OPIMSignInRefusedError -Command $Refused)
        }
    }

    # SEC (OPIM-08, A3): never an ARM request with a token for another tenant or another account than the
    # module's Graph session. The token's own claims are read, before every request. Without a module
    # sign-in, or without an ARM token, nothing is read: Invoke-OPIMArmRequest refuses a missing token
    # itself (ArmTokenAcquisitionFailed).
    $State = $script:_OPIMAuthState
    if (-not ($State -is [System.Collections.IDictionary]) -or -not $State['TokenTenantId']) {
        return
    }
    $ArmToken = $State['ArmToken']
    if (-not ($ArmToken -is [System.Security.SecureString]) -or $ArmToken.Length -eq 0) {
        return
    }
    [string]$SessionTenant = $State['TokenTenantId']
    [string]$TokenTenant = Get-OPIMTokenTenantId -AccessToken $ArmToken
    if (-not $TokenTenant) {
        return (New-OPIMTenantMismatchError -RequestedTenant $SessionTenant -Source Azure -Unreadable)
    }
    if ($TokenTenant -ne $SessionTenant) {
        return (New-OPIMTenantMismatchError -RequestedTenant $SessionTenant -Source Azure)
    }
    [string]$SessionObjectId = $State['ObjectId']
    [string]$TokenObjectId = Get-OPIMTokenObjectId -AccessToken $ArmToken
    if (-not $TokenObjectId -or -not $SessionObjectId) {
        return (New-OPIMAccountMismatchError -RequestedTenant $SessionTenant -Unreadable)
    }
    if ($TokenObjectId -ne $SessionObjectId) {
        return (New-OPIMAccountMismatchError -RequestedTenant $SessionTenant)
    }
}
