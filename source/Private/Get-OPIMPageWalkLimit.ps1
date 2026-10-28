function Get-OPIMPageWalkLimit {
    <#
    .SYNOPSIS
    Returns the number of pages a Microsoft Graph or Azure Resource Manager -All walk may request.

    .DESCRIPTION
    The single owner of the page limit of Invoke-OPIMGraphRequest -All and Invoke-OPIMArmRequest -All,
    ported from Omnicit.EntraRBAC (Get-OERPageWalkLimit). Each transport reads it ONCE per -All call,
    before its paging loop, and refuses the walk -- it fails, it never truncates -- before requesting
    the page after the limit.

    The limit is a backstop against a service that never ends its next links, not a page size: at the
    smallest page a transport serves it is far beyond any real collection in a tenant, so a legitimate
    listing never meets it. A walk that did meet it would otherwise run for ever, so it is refused as
    incomplete and never returned as though it were the whole list.

    The function takes no parameters and makes no request. A test that needs a small limit mocks this
    function in the module scope instead of building a hundred thousand pages.

    .EXAMPLE
    Get-OPIMPageWalkLimit

    Returns 100000.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()
    return [int]100000
}
