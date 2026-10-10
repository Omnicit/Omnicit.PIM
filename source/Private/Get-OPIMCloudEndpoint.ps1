function Get-OPIMCloudEndpoint {
    <#
    .SYNOPSIS
    Returns the Microsoft Graph and Azure Resource Manager endpoint set for a cloud.

    .DESCRIPTION
    Single owner of the cloud-to-endpoint table. Every place in this module that needs a sign-in
    authority host, a Graph service root, a Graph environment name, or an Azure Resource Manager
    resource or host for a given cloud reads it from here instead of hardcoding a second copy. The
    helper is pure: it makes no Graph or ARM call, acquires no token, reads and writes no module
    state, and only looks up a value in a fixed table. The table is ported from Omnicit.EntraRBAC.

    Returns an object with seven string properties, in this order:
      - Environment      the cloud key itself, in its canonical letter case ('Global', 'USGov',
                         'USGovDoD', 'China'), whatever case the caller typed.
      - GraphResource    the Microsoft Graph token audience. Keeps a trailing slash.
      - GraphEnvironment the Graph environment name for Connect-MgGraph -Environment (it matches
                         Environment in every row today; kept as its own property because it names
                         a Graph-specific concept and is not guaranteed to track Environment
                         one-for-one forever).
      - GraphServiceRoot the versioned Graph service root. Carries the API version and has NO
                         trailing slash. It is the host a Graph next link must stay on.
      - ArmResource      the ARM token audience. Keeps a trailing slash.
      - ArmHost          the bare ARM host for the cloud, with NO trailing slash. It is the value
                         the module hands to AzAuth's Get-AzToken -Resource and the host every ARM
                         request is sent to; for Global it is byte-identical to the literal the
                         module used before this table existed.
      - AuthorityHost    the Microsoft Entra ID authority (STS) host for the cloud, with a trailing
                         slash, so the MSAL authority is this value followed by the tenant.

    GraphResource and GraphServiceRoot are deliberately SEPARATE properties and are not
    interchangeable: conflating them would emit a URL such as
    'https://graph.microsoft.com//v1.0/...' (the audience, with its trailing slash, plus the
    versioned root concatenated on top). Read the one each caller actually needs.

    Microsoft 365 GCC is a commercial-cloud tenant -- it uses the worldwide endpoints and is
    selected with 'Global', not a cloud of its own. There is no 'GCC' row because GCC is not a
    distinct sovereign boundary; it signs in and calls Graph and ARM like any other commercial
    tenant.

    The Microsoft Graph SDK also names 'DelosCloud', 'BleuCloud' and 'GovSGCloud' as environments.
    They are deliberately absent from this table: this module pairs every Graph endpoint with an
    Azure Resource Manager endpoint, and none of those three has an ARM counterpart here. Adding one
    would mean guessing an ArmResource and ArmHost pair this module cannot verify.

    -Environment deliberately carries NO ValidateSet on this private helper. The closed set of
    supported clouds is enforced at the PUBLIC boundary instead: every command that takes
    -Environment attaches a ValidateSet naming exactly the four clouds this table answers, so no
    caller reaches this helper with a value a user typed by hand. That leaves one way an unsupported
    value can still arrive here: a cloud added to one of those ValidateSets without a matching row
    being added to the switch below, or a cloud name read back from a file such as the tenant map.
    An unknown value must throw and never fall back to the Global row -- a silent fallback would
    send a sovereign-tenant credential and request at the wrong cloud boundary -- and leaving this
    parameter unvalidated is what keeps that throw reachable and provable by a test instead of
    merely asserted by inspection. See tests/Unit/Private/Get-OPIMCloudEndpoint.Tests.ps1, which
    also holds every ValidateSet to this table.

    The object is private working data and is not type-tagged: it is never written to the pipeline
    by a public command.

    .PARAMETER Environment
    The cloud to resolve endpoints for: 'Global', 'USGov', 'USGovDoD' or 'China', matched without
    regard to letter case and returned under its canonical name. Defaults to 'Global', the only
    cloud the module supported before this table existed, whose row stays byte-for-byte identical
    to the literals it replaced. Any other value, an empty string included, throws; the description
    above explains why this parameter carries no ValidateSet of its own.

    .EXAMPLE
    Get-OPIMCloudEndpoint

    Returns the worldwide (Global) endpoint set, the default.

    .EXAMPLE
    Get-OPIMCloudEndpoint -Environment 'USGovDoD'

    Returns the endpoint set for the US Government DoD cloud.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$Environment = 'Global'
    )

    switch ($Environment) {
        'Global' {
            return [PSCustomObject]@{
                Environment      = 'Global'
                GraphResource    = 'https://graph.microsoft.com/'
                GraphEnvironment = 'Global'
                GraphServiceRoot = 'https://graph.microsoft.com/v1.0'
                ArmResource      = 'https://management.azure.com/'
                ArmHost          = 'https://management.azure.com'
                AuthorityHost    = 'https://login.microsoftonline.com/'
            }
        }
        'USGov' {
            return [PSCustomObject]@{
                Environment      = 'USGov'
                GraphResource    = 'https://graph.microsoft.us/'
                GraphEnvironment = 'USGov'
                GraphServiceRoot = 'https://graph.microsoft.us/v1.0'
                ArmResource      = 'https://management.usgovcloudapi.net/'
                ArmHost          = 'https://management.usgovcloudapi.net'
                AuthorityHost    = 'https://login.microsoftonline.us/'
            }
        }
        'USGovDoD' {
            return [PSCustomObject]@{
                Environment      = 'USGovDoD'
                GraphResource    = 'https://dod-graph.microsoft.us/'
                GraphEnvironment = 'USGovDoD'
                GraphServiceRoot = 'https://dod-graph.microsoft.us/v1.0'
                ArmResource      = 'https://management.usgovcloudapi.net/'
                ArmHost          = 'https://management.usgovcloudapi.net'
                AuthorityHost    = 'https://login.microsoftonline.us/'
            }
        }
        'China' {
            return [PSCustomObject]@{
                Environment      = 'China'
                GraphResource    = 'https://microsoftgraph.chinacloudapi.cn/'
                GraphEnvironment = 'China'
                GraphServiceRoot = 'https://microsoftgraph.chinacloudapi.cn/v1.0'
                ArmResource      = 'https://management.chinacloudapi.cn/'
                ArmHost          = 'https://management.chinacloudapi.cn'
                AuthorityHost    = 'https://login.chinacloudapi.cn/'
            }
        }
        default {
            # No ValidateSet guards -Environment (see .DESCRIPTION), so this is reachable, not merely
            # defensive. Never fall back to the Global row: that would route a sovereign-tenant
            # credential and request at the wrong cloud boundary.
            throw "Get-OPIMCloudEndpoint: no endpoint table entry for the cloud '$Environment'. Add a row to source/Private/Get-OPIMCloudEndpoint.ps1 before adding the cloud to an -Environment ValidateSet."
        }
    }
}
