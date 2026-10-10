function Get-OPIMTenantMapEnvironment {
    <#
    .SYNOPSIS
    Reads the cloud a tenant alias stores in the tenant map, or refuses a cloud Omnicit.PIM does not know.

    .DESCRIPTION
    Single owner of how a tenant map entry names its cloud (A12). The tenant map remembers the cloud
    of an alias in an optional Environment key, so that Connect-OPIM, Enable-OPIMMyRole (pim) and
    Disable-OPIMMyRole (unpim) sign in to the cloud of the alias without being told. This helper
    reads that key and returns the cloud under its canonical name, 'Global', 'USGov', 'USGovDoD' or
    'China', whatever letter case the file holds. It makes no Graph or ARM call and reads and writes
    no module state.

    An entry names no cloud, and the answer is 'Global', when it is in the old string form
    ('alias' = 'tenant id'), when it is $null, when it is a table without an Environment key, or when
    the key is empty or only white space. 'Global' is what such an alias has always signed in to.

    A cloud the cloud table (Get-OPIMCloudEndpoint) does not answer is never read as 'Global': a
    sign-in in the wrong cloud would send the credentials of a sovereign tenant to the wrong
    authority. The helper throws a terminating error through $PSCmdlet.ThrowTerminatingError instead,
    in the category InvalidArgument with the alias as its target and NO error id, as the module's
    other validation errors that name no id. A caller that catches it writes it with its own
    $PSCmdlet.WriteError, and the record then reads as the caller's command in its
    FullyQualifiedErrorId, such as Connect-OPIM. The message names the alias, the file, the value and
    the four clouds, and says that nothing was signed in.

    .PARAMETER Entry
    The tenant map value of the alias, as Import-PowerShellDataFile returned it: a table (a
    dictionary) in the current form, or a string in the old form. $null is allowed and names no
    cloud.

    .PARAMETER TenantAlias
    The alias the entry belongs to. It is the target of the error and named in its message.

    .PARAMETER TenantMapPath
    The path of the tenant map file, named in the message of the error. Optional; without it the
    message says 'the tenant map' instead of a path.

    .EXAMPLE
    $Cloud = Get-OPIMTenantMapEnvironment -Entry $Map['contoso'] -TenantAlias 'contoso' -TenantMapPath $TenantMapPath

    Returns 'USGov' for an entry that stores Environment = 'usgov', 'Global' for an entry that
    stores none, and throws the terminating error for an entry that stores Environment = 'Germany'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Entry,

        [Parameter(Mandatory)]
        [string]$TenantAlias,

        [string]$TenantMapPath
    )

    # No cloud stored: the old string form, $null, or a table without a usable Environment key.
    if ($Entry -isnot [System.Collections.IDictionary]) { return 'Global' }
    [string]$Stored = [string]$Entry['Environment']
    if ([string]::IsNullOrWhiteSpace($Stored)) { return 'Global' }

    # The cloud table is the only owner of which clouds exist, and it matches without regard to letter
    # case and answers with the canonical name. It throws for anything else; that throw is turned into
    # the record below and the value is never read as Global.
    try {
        return (Get-OPIMCloudEndpoint -Environment $Stored -ErrorAction Stop).Environment
    } catch {
        $Where = if ($TenantMapPath) { "'$TenantMapPath'" } else { 'the tenant map' }
        # The suggested command is meant to be pasted, so the alias is a single-quoted string of its
        # own, with every kind of single quote in it doubled; an alias with a space or an apostrophe
        # then still runs as written.
        $QuotedAlias = "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($TenantAlias) + "'"
        $Message = "Tenant alias '$TenantAlias' in $Where names the cloud '$Stored', which Omnicit.PIM does not know, " +
            'so nothing was signed in. Use Global, USGov, USGovDoD or China, for example with ' +
            "Set-OPIMConfiguration -TenantAlias $QuotedAlias -Environment USGov."
        $Record = [System.Management.Automation.ErrorRecord]::new(
            [System.ArgumentException]::new($Message),
            $null,
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $TenantAlias
        )
        $PSCmdlet.ThrowTerminatingError($Record)
    }
}
