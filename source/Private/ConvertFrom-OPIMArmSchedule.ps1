function ConvertFrom-OPIMArmSchedule {
    <#
    .SYNOPSIS
    Converts an Azure Resource Manager role schedule, schedule instance or schedule request to the
    object the module returns.

    .DESCRIPTION
    The single owner of the mapping from the ARM JSON of the 2020-10-01 authorization API to the
    objects the Azure role cmdlets return. Each input becomes one PSCustomObject that carries the
    property NAMES and value TYPES the Az.Resources cmdlets returned for the same resource, so
    everything that reads those objects keeps working: every property is a string except the dates,
    which are DateTime values of Kind Utc, and a property that ARM does not return is $null, never an
    empty string. The properties are in alphabetical order, compared ordinally without regard to
    letter case, so the order is the same under every culture. The Az .NET type names are not
    reproduced, and no type name is inserted: the caller tags the object with the module's own.

    There are three kinds. EligibilitySchedule is a role eligibility schedule (27 properties),
    AssignmentScheduleInstance a role assignment schedule instance (30) and
    AssignmentScheduleRequest a role assignment schedule request (35). ResourceGroupName is the
    resource group in the id of the resource, or $null when the id is not in a resource group. A date
    reaches this function as a string with or without an offset, or as a DateTime of any Kind that
    the JSON reader made of it; each is converted to the same instant in UTC. A null input returns
    nothing.

    .PARAMETER InputObject
    The ARM object: one item of a list response, or the response of a request. Accepts pipeline
    input. A null returns nothing.

    .PARAMETER Kind
    The kind of the ARM object: EligibilitySchedule, AssignmentScheduleInstance or
    AssignmentScheduleRequest.

    .EXAMPLE
    (Invoke-OPIMArmRequest -Path $Path -All).value | ConvertFrom-OPIMArmSchedule -Kind EligibilitySchedule

    Converts every eligibility schedule of a listing to the module's object.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()]
        $InputObject,

        [Parameter(Mandatory)]
        [ValidateSet('EligibilitySchedule', 'AssignmentScheduleInstance', 'AssignmentScheduleRequest')]
        [string]$Kind
    )
    begin {
        # [string] would turn a $null into ''; Az gives $null for a property ARM does not return.
        function Get-Text ($Value) { if ($null -eq $Value) { $null } else { [string]$Value } }

        # ConvertTo-OPIMUtcDateTime returns nothing for a null; the property must still exist.
        function Get-UtcDate ($Value) {
            $Date = ConvertTo-OPIMUtcDateTime -Value $Value
            if ($null -eq $Date) { $null } else { $Date }
        }
    }
    process {
        if ($null -eq $InputObject) { return }

        $P = $InputObject.properties
        $X = if ($null -ne $P) { $P.expandedProperties }
        $Id = Get-Text $InputObject.id
        $ResourceGroup = [regex]::Match([string]$Id, '(?i)^/subscriptions/[^/]+/resourceGroups/(?<Rg>[^/]+)/providers/')

        $Out = [ordered]@{
            Condition                          = Get-Text $P.condition
            ConditionVersion                   = Get-Text $P.conditionVersion
            CreatedOn                          = Get-UtcDate $P.createdOn
            ExpandedPropertiesPrincipalId      = Get-Text $X.principal.id
            ExpandedPropertiesPrincipalType    = Get-Text $X.principal.type
            ExpandedPropertiesRoleDefinitionId = Get-Text $X.roleDefinition.id
            Id                                 = $Id
            Name                               = Get-Text $InputObject.name
            PrincipalDisplayName               = Get-Text $X.principal.displayName
            PrincipalEmail                     = Get-Text $X.principal.email
            PrincipalId                        = Get-Text $P.principalId
            PrincipalType                      = Get-Text $P.principalType
            ResourceGroupName                  = if ($ResourceGroup.Success) { $ResourceGroup.Groups['Rg'].Value } else { $null }
            RoleDefinitionDisplayName          = Get-Text $X.roleDefinition.displayName
            RoleDefinitionId                   = Get-Text $P.roleDefinitionId
            RoleDefinitionType                 = Get-Text $X.roleDefinition.type
            Scope                              = Get-Text $P.scope
            ScopeDisplayName                   = Get-Text $X.scope.displayName
            ScopeId                            = Get-Text $X.scope.id
            ScopeType                          = Get-Text $X.scope.type
            Status                             = Get-Text $P.status
            Type                               = Get-Text $InputObject.type
        }

        if ($Kind -ne 'AssignmentScheduleRequest') {
            $Out['EndDateTime'] = Get-UtcDate $P.endDateTime
            $Out['MemberType'] = Get-Text $P.memberType
            $Out['StartDateTime'] = Get-UtcDate $P.startDateTime
        }
        if ($Kind -eq 'EligibilitySchedule') {
            $Out['RequestId'] = Get-Text $P.roleEligibilityScheduleRequestId
            $Out['UpdatedOn'] = Get-UtcDate $P.updatedOn
        }
        if ($Kind -eq 'AssignmentScheduleInstance') {
            $Out['AssignmentType'] = Get-Text $P.assignmentType
            $Out['LinkedRoleEligibilityScheduleId'] = Get-Text $P.linkedRoleEligibilityScheduleId
            $Out['LinkedRoleEligibilityScheduleInstanceId'] = Get-Text $P.linkedRoleEligibilityScheduleInstanceId
            $Out['OriginRoleAssignmentId'] = Get-Text $P.originRoleAssignmentId
            $Out['RoleAssignmentScheduleId'] = Get-Text $P.roleAssignmentScheduleId
        }
        if ($Kind -eq 'AssignmentScheduleRequest') {
            $Out['ApprovalId'] = Get-Text $P.approvalId
            $Out['ExpirationDuration'] = Get-Text $P.scheduleInfo.expiration.duration
            $Out['ExpirationEndDateTime'] = Get-UtcDate $P.scheduleInfo.expiration.endDateTime
            $Out['ExpirationType'] = Get-Text $P.scheduleInfo.expiration.type
            $Out['Justification'] = Get-Text $P.justification
            $Out['LinkedRoleEligibilityScheduleId'] = Get-Text $P.linkedRoleEligibilityScheduleId
            $Out['RequestType'] = Get-Text $P.requestType
            $Out['RequestorId'] = Get-Text $P.requestorId
            $Out['ScheduleInfoStartDateTime'] = Get-UtcDate $P.scheduleInfo.startDateTime
            $Out['TargetRoleAssignmentScheduleId'] = Get-Text $P.targetRoleAssignmentScheduleId
            $Out['TargetRoleAssignmentScheduleInstanceId'] = Get-Text $P.targetRoleAssignmentScheduleInstanceId
            $Out['TicketInfoTicketNumber'] = Get-Text $P.ticketInfo.ticketNumber
            $Out['TicketInfoTicketSystem'] = Get-Text $P.ticketInfo.ticketSystem
        }

        # Ordinal and case-insensitive, so the order is the same under every culture: Sort-Object would
        # sort by the session's culture, which can order letters differently (cs-CZ sorts 'ch' after 'h').
        [string[]]$Keys = @($Out.Keys)
        [System.Array]::Sort($Keys, [System.StringComparer]::OrdinalIgnoreCase)
        $Sorted = [ordered]@{}
        foreach ($Key in $Keys) { $Sorted[$Key] = $Out[$Key] }
        [pscustomobject]$Sorted
    }
}
