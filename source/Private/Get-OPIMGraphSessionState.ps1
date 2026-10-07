function Get-OPIMGraphSessionState {
    <#
    .SYNOPSIS
    Compares the Microsoft Graph PowerShell SDK session in the process with the one this module connected.

    .DESCRIPTION
    Returns one of four values:

    Untracked -- the module holds no session it connected itself: no auth state, a state that is
    not a dictionary, or a state that carries no GraphSessionFingerprint key (before the first
    sign-in, or a state the module did not write). Nothing is compared and Get-MgContext is not
    called.

    Own -- the process holds the session the module connected.

    Absent -- the process holds no session at all, for example after Disconnect-MgGraph.

    Changed -- the process holds a session the module did not connect: another Connect-MgGraph has
    replaced it.

    Initialize-OPIMAuth calls this at every entry and Invoke-OPIMGraphRequest before every Graph
    call. The fingerprint itself is Get-OPIMGraphSessionFingerprint's; this function only compares,
    ordinally.

    .EXAMPLE
    if ((Get-OPIMGraphSessionState) -eq 'Changed') { throw (New-OPIMGraphSessionChangedError) }

    Refuses a Graph call when another Connect-MgGraph has replaced the module's session.

    .OUTPUTS
    [string] Untracked, Own, Absent or Changed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $State = $script:_OPIMAuthState
    if (-not ($State -is [System.Collections.IDictionary]) -or -not $State.Contains('GraphSessionFingerprint')) {
        return 'Untracked'
    }
    $Current = Get-OPIMGraphSessionFingerprint
    if ($null -eq $Current) {
        return 'Absent'
    }
    # Ordinal, not -ceq: -ceq compares with the invariant culture, which ignores characters of zero
    # weight -- a soft hyphen in one value compared equal to none (measured in Omnicit.EntraRBAC,
    # 2026-10-05). A stored $null casts to '', which never equals the non-empty fingerprint of a
    # session that exists, so it stays Changed.
    if ([string]::Equals($Current, [string]$State['GraphSessionFingerprint'], [System.StringComparison]::Ordinal)) {
        return 'Own'
    }
    'Changed'
}
