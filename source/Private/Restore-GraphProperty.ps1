filter Restore-GraphProperty {
    <#
    .SYNOPSIS
    Restores a named property from a request object into a Graph API response object.

    .DESCRIPTION
    Graph API responses often omit expanded sub-objects that were present in the original request.
    This filter copies a named property from the request (or an explicit DataObject) back into the
    response hashtable, after validating that the corresponding ID field is unchanged to confirm
    both objects refer to the same underlying resource.

    .PARAMETER Request
    The original request object or hashtable that contains the property value to be restored.
    Used as the ID reference for validation and as the property source when DataObject is omitted.

    .PARAMETER Response
    The Graph API response object or hashtable whose missing property will be populated in-place.
    The corresponding ID field must match the Request ID field before the copy is performed.

    .PARAMETER DataObject
    An optional alternative source from which the named property value is copied into the Response.
    When omitted the property value is sourced from Request instead of DataObject.

    .PARAMETER Property
    The name of the property to restore, e.g. roleDefinition or directoryScope. The matching ID
    key is derived by appending Id, e.g. roleDefinitionId. Accepts pipeline input.

    .EXAMPLE
    'roleDefinition' | Restore-GraphProperty -Request $request -Response $response

    Copies the roleDefinition object from $request into $response after validating that
    roleDefinitionId matches between both objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)]$Response,
        $DataObject = $Request,
        [Parameter(Mandatory, ValueFromPipeline)]$Property
    )

    if ($Response[$("${property}Id")] -ne $Request[$("${property}Id")]) {
        throw "The returned ${property}Id does not match the request. This is a bug"
    }
    $Response.$property = $DataObject.$property
}
