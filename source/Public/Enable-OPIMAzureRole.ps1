using namespace System.Xml

#requires -module Az.Resources
function Enable-OPIMAzureRole {
    <#
    .SYNOPSIS
    Activate an Azure PIM eligible resource role.
    .DESCRIPTION
    Activates an eligible Azure RBAC role assignment for the current user. By default activates for 1 hour.
    The role is named by its display name, or by the form tab completion offers for the RoleName
    parameter ('Role -> Scope name (Name)'). A name that matches the role at more than one scope is
    refused with AmbiguousName and nothing is activated: add -Scope to pick one. A name that matches
    no eligible role is written as an EligibleRoleNotFound error. Several names are resolved one by
    one, each on its own, so a name that fails does not stop the next one.
    The request is reported by the status Azure gives it: a request that failed, was denied or was
    canceled is written as an ActivationRequestFailed error, and one that waits for approval or is
    still being provisioned is returned with a warning.
    A role that is already active at that scope (listed by Get-OPIMAzureRole -Activated) is not
    requested again: a warning is written and nothing is sent for it, and when that list cannot be
    read, its error is written and nothing more is sent. The list is read once per command, and a
    role named or piped twice is requested once, with a warning for the second. A role object that
    names no Azure scope (no ScopeId starting with '/') is written as an error and nothing is sent
    for it; the next role still runs.
    .NOTES
    The default activation period is 1 hour. Override with -Hours. Make it persistent in your profile:

    $PSDefaultParameterValues['Enable-OPIM*:Hours'] = 5

    .EXAMPLE
    Get-OPIMAzureRole | Enable-OPIMAzureRole
    Activate all eligible Azure roles for 1 hour.
    .EXAMPLE
    Enable-OPIMAzureRole 'Reader' -Scope '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app'
    Activates Reader on that resource group only. Without -Scope, a role that is eligible at more than
    one scope is refused with AmbiguousName.
    .EXAMPLE
    Enable-OPIMAzureRole 'Reader', 'Contributor' -Scope '/subscriptions/00000000-0000-0000-0000-000000000000'
    Activates both roles at that subscription. Each name is resolved on its own.
    .EXAMPLE
    Enable-OPIMAzureRole 'Reader' -Scope '/subscriptions/00000000-0000-0000-0000-000000000000' -NotBefore '4pm' -Until '6pm'
    Schedules Reader at that subscription from 4pm to 6pm local time today. The start is sent to Azure
    in UTC, and the request comes back as a scheduled activation (ScheduleCreated).
    .EXAMPLE
    Enable-OPIMAzureRole <tab>
    Tab complete all eligible Azure roles. A name that is unique is offered bare; one that is not is
    offered in the longer form.
    .EXAMPLE
    Get-OPIMAzureRole | Select-Object -First 1 | Enable-OPIMAzureRole -Hours 4
    Activate the first eligible Azure role for 4 hours.
    .PARAMETER Role
    Eligible Azure RBAC role schedule object piped from Get-OPIMAzureRole. Used when activating
    by object rather than by name. Mutually exclusive with -RoleName.
    .PARAMETER RoleName
    The display name of the eligible Azure role (for example Reader), or the tab-completed form the
    argument completer offers ('Role -> Scope name (Name)'). A display name is compared exactly,
    without regard to letter case, and takes no wildcards. Accepts multiple values, each resolved on
    its own; -Scope applies to every one of them. Several matches are refused with AmbiguousName.
    Mutually exclusive with -Role.
    .PARAMETER Identity
    The schedule name from Get-OPIMAzureRole (the Name property) to activate directly without
    a role name. A name that matches more than one schedule is refused with AmbiguousName. Mutually
    exclusive with -Role and -RoleName.
    .PARAMETER Justification
    Free-text justification for the activation request. May be required by your PIM policy.
    .PARAMETER TicketNumber
    Ticket or work item number associated with this activation for auditing purposes.
    .PARAMETER TicketSystem
    Name of the ticket system that issued the above ticket number, e.g. ServiceNow or Jira.
    .PARAMETER Hours
    Activation duration in hours, from 1 to 24. Defaults to 1. Ignored when -Until is specified. Your PIM
    policy can allow less; a longer request is refused by the policy as before.
    .PARAMETER NotBefore
    Date and time when the role activation begins, sent to Azure. Defaults to now. A time without an
    offset, such as '4pm', is local time. A start in the future makes a scheduled activation
    (ScheduleCreated), reported as a success.
    .PARAMETER Until
    Explicit end date and time for the activation. Takes precedence over -Hours when specified.
    Aliased as -NotAfter.
    .PARAMETER Scope
    Picks one role when the name matches the role at more than one scope: the ARM scope of the
    eligibility, such as a subscription or a resource group. It means exactly that scope, not the
    scopes below it, and it is compared without regard to letter case. Unlike on Get-OPIMAzureRole,
    where '/' means every scope, '/' here means only a role that is eligible at the root scope
    itself. A scope that ends in '/' (other than '/') is refused. Applies to every name in
    -RoleName, and cannot be combined with piped objects (-Role) or -Identity: piping objects in
    together with -Scope selects the -RoleName parameter set, so an interactive host asks for
    -RoleName instead of failing to bind.
    .PARAMETER Wait
    Wait while the request is in progress before returning: the requests you made at the scope of
    the role are read every 5 seconds, up to -TimeoutSeconds, and the role is then reported by the
    last status Azure gives the request, on the request as last read. A failed read is written as
    its own error for that role only.
    .PARAMETER TimeoutSeconds
    With -Wait, the most seconds to wait for the request to finish, counted from the start of the
    wait. Defaults to 300. A request that waits for approval ends the wait at once, with a warning;
    one still in progress at the limit is written as an ActivationWaitTimedOut error and stays
    submitted.
    #>
    [Alias('Enable-PIMResourceRole')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'RoleName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'RoleObject', Mandatory, ValueFromPipeline)]
        $Role,
        [Parameter(Position = 0, ParameterSetName = 'RoleName', Mandatory)]
        [ArgumentCompleter([AzureEligibleRoleCompleter])]
        [string[]]$RoleName,
        [Parameter(ParameterSetName = 'ByIdentity', Mandatory)]
        [string]$Identity,
        [Parameter(Position = 1)][string]$Justification,
        [string]$TicketNumber,
        [string]$TicketSystem,
        [Parameter(Position = 2)][ValidateRange(1, 24)][int]$Hours = 1,
        [ValidateNotNullOrEmpty()][DateTime]$NotBefore = [DateTime]::Now,
        [DateTime][Alias('NotAfter')]$Until,
        [Parameter(ParameterSetName = 'RoleName')]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ $_ -eq '/' -or -not $_.EndsWith('/') }, ErrorMessage = "The scope '{0}' ends with '/'. Give it without the trailing slash; only the root scope is written '/'.")]
        [string]$Scope,
        [Switch]$Wait,
        [ValidateRange(1, 86400)][int]$TimeoutSeconds = 300
    )
    begin {
        # OPIM-39: the active list is read at most once per command, at the first role that needs it,
        # and every post this command has requested is kept, so no post is requested twice.
        $ActivePosts = $null
        $ActiveReadFailed = $false
        $RequestedPosts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
    process {
        Initialize-OPIMAuth -IncludeARM
        if ($Identity) {
            try {
                $FoundByIdentity = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object Name -EQ $Identity)
            } catch {
                # OPIM-12: the listing failed; report it as itself and stop for this identity.
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            if ($FoundByIdentity.Count -gt 1) {
                # Never the first of several: refuse with the candidates and act on none.
                $PSCmdlet.WriteError((New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Azure `
                    -Name $Identity -Status Eligible -Candidate $FoundByIdentity -Identity))
                return
            }
            $Role = $FoundByIdentity | Select-Object -First 1
            if (-not $Role) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("No eligible Azure role found with identity '$Identity'.")) `
                    -ErrorId 'IdentityNotFound' `
                    -Category ObjectNotFound `
                    -TargetObject $Identity `
                    -Cmdlet $PSCmdlet
                return
            }
        }
        $ResolvedRoles = if ($RoleName) {
            $ResolveParams = @{ Pillar = 'Azure'; FilterParameter = 'Scope'; ErrorAction = 'Stop' }
            if ($PSBoundParameters.ContainsKey('Scope')) { $ResolveParams.Scope = $Scope }
            foreach ($EachName in $RoleName) {
                try {
                    Resolve-OPIMSchedule -Name $EachName @ResolveParams
                } catch {
                    # Each name resolves on its own: a name that is ambiguous, unknown or cannot be
                    # listed is written as itself, and the next name still runs (OPIM-12).
                    Remove-OPIMErrorRecord -Record $PSItem
                    $PSCmdlet.WriteError($PSItem)
                }
            }
        } else {
            @($Role)
        }

        foreach ($Role in $ResolvedRoles) {
            # Skip already-active instances piped from Get-OPIMAzureRole -All
            if ($Role.PSObject.TypeNames -contains 'Omnicit.PIM.AzureAssignmentScheduleInstance') {
                Write-Verbose "Skipping already-active Azure role: $($Role.RoleDefinitionDisplayName) on $($Role.ScopeDisplayName)"
                continue
            }
            $Label = (Get-OPIMScheduleName -Pillar Azure -InputObject $Role).Label
            # SECURITY 4: the request is made at the role's own ARM scope. A role whose ScopeId is no ARM
            # scope -- empty, or without its leading slash -- names none, and its path would land at the
            # root scope or off the ARM host, so nothing is sent for it. Before the OPIM-39 bookkeeping:
            # a refused role reads no active list and is never counted as requested. No error id, as the
            # transport's refusal of a next link.
            if (-not ([string]$Role.ScopeId).StartsWith('/', [System.StringComparison]::Ordinal)) {
                Write-CmdletError -Message ([System.Exception]::new("$Label`: the role names no Azure scope, so no request was sent.")) `
                    -Category InvalidArgument -TargetObject $null -Cmdlet $PSCmdlet
                continue
            }
            # OPIM-39: never send a second request for a post that is already active -- a repeated
            # request can end the active one. A list that cannot be read is no proof that nothing is
            # active, so nothing more is sent by this command (G3).
            if ($ActiveReadFailed) { continue }
            if ($null -eq $ActivePosts) {
                try {
                    $ActivePosts = @(Get-OPIMAzureRole -Activated -ErrorAction Stop)
                } catch {
                    Remove-OPIMErrorRecord -Record $PSItem
                    $PSCmdlet.WriteError($PSItem)
                    $ActiveReadFailed = $true
                    continue
                }
            }
            if (@($ActivePosts | Where-Object {
                        [string]::Equals($_.RoleDefinitionId, $Role.RoleDefinitionId, [System.StringComparison]::OrdinalIgnoreCase) -and
                        [string]::Equals($_.ScopeId, $Role.ScopeId, [System.StringComparison]::OrdinalIgnoreCase)
                    }).Count -gt 0) {
                $PSCmdlet.WriteWarning("$Label is already active, so no new request was sent and the active assignment is left as it is.")
                continue
            }
            # The same post named twice, or piped twice, is requested once (G8): the active list was
            # read before the first request and does not show it.
            $PostKey = "$($Role.RoleDefinitionId)|$($Role.ScopeId)"
            if ($RequestedPosts.Contains($PostKey)) {
                $PSCmdlet.WriteWarning("$Label was already requested by this command, so no second request was sent.")
                continue
            }
            # The request is built for the module's own ARM transport: the name of the request is a new
            # id, and the body carries one eligibility, one role definition at one scope, for the
            # requested duration, and nothing else (SECURITY 4).
            $RequestName = [string](New-Guid)
            $Expiration = if ($Until) {
                [string]$RoleExpireTime = $Until
                [ordered]@{ type = 'AfterDateTime'; endDateTime = $Until.ToUniversalTime().ToString('o') }
            } else {
                [string]$RoleExpireTime = $NotBefore.AddHours($Hours)
                [ordered]@{ type = 'AfterDuration'; duration = [XmlConvert]::ToString([TimeSpan]::FromHours($Hours)) }
            }
            $ScheduleInfo = [ordered]@{ expiration = $Expiration }
            # OPIM-15: the start is sent only when -NotBefore was given; without it ARM starts the
            # activation now. Times go to ARM in UTC (a time without an offset is local, OPIM-18).
            if ($PSBoundParameters.ContainsKey('NotBefore')) {
                $ScheduleInfo.startDateTime = $NotBefore.ToUniversalTime().ToString('o')
            }
            $RequestProperties = [ordered]@{
                principalId                     = $Role.PrincipalId
                roleDefinitionId                = $Role.RoleDefinitionId
                requestType                     = 'SelfActivate'
                linkedRoleEligibilityScheduleId = $Role.Name
                scheduleInfo                    = $ScheduleInfo
            }
            if ($Justification) { $RequestProperties.justification = $Justification }
            if ($TicketNumber -or $TicketSystem) {
                $TicketInfo = [ordered]@{}
                if ($TicketNumber) { $TicketInfo.ticketNumber = $TicketNumber }
                if ($TicketSystem) { $TicketInfo.ticketSystem = $TicketSystem }
                $RequestProperties.ticketInfo = $TicketInfo
            }
            # The root scope has no prefix: its path starts with /providers, never with //providers.
            $RequestScope = if ($Role.ScopeId -eq '/') { '' } else { $Role.ScopeId }
            $RequestPath = '{0}/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/{1}?api-version=2020-10-01' -f $RequestScope, $RequestName

            if ($PSCmdlet.ShouldProcess(
                    "$($Role.RoleDefinitionDisplayName) on $($Role.ScopeDisplayName) ($($Role.ScopeId))",
                    "Activate Azure Role from $NotBefore to $RoleExpireTime"
                )) {
                # Counted before it is sent, so a request that fails still is not sent again.
                $null = $RequestedPosts.Add($PostKey)
                try {
                    # The transport gates the request itself (SignInRefused, TenantMismatch,
                    # AccountMismatch) and throws a refusal or an ARM error as a record, which this
                    # catch writes as itself.
                    $Response = ConvertFrom-OPIMArmSchedule -Kind AssignmentScheduleRequest -InputObject (
                        Invoke-OPIMArmRequest -Method PUT -Path $RequestPath -Body @{ properties = $RequestProperties })
                } catch {
                    Remove-OPIMErrorRecord -Record $PSItem
                    if (-not (ConvertTo-PolicyValidationError -CaughtError $PSItem -ResourceType 'role' -Cmdlet $PSCmdlet)) {
                        $PSCmdlet.WriteError($PSItem)
                    }
                    continue
                }

                # The request reported is the last one read: the response, or the polled request that
                # carries the final status.
                $Current = $Response
                $Status = [string]$Response.Status
                $TimedOut = $false
                if ($Wait) {
                    # OPIM-14: poll while the request is in progress, up to -TimeoutSeconds, counted in UTC.
                    $Deadline = (Get-Date -AsUTC).AddSeconds($TimeoutSeconds)
                    $PollFailed = $false
                    while ((Get-OPIMRequestOutcome -Status $Status) -eq 'InProgress') {
                        if ((Get-Date -AsUTC) -ge $Deadline) { $TimedOut = $true; break }
                        Start-Sleep -Seconds 5
                        try {
                            # The transport gates every round of the poll itself, so a refusal is thrown
                            # here, written as itself by the catch, and ends the wait for this role
                            # only; the request above was already sent and stays submitted.
                            # asTarget() lists the requests made for the signed-in user and needs no role
                            # at the scope. asRequestor() would fail exactly while the poll is needed:
                            # ARM refuses it to a user who holds no active role there yet
                            # (InsufficientPermissions, measured live 2026-10-08). The list is read
                            # across every page (-All), and the root scope has no prefix.
                            $PollScope = if ($Response.Scope -eq '/') { '' } else { $Response.Scope }
                            $PollPath = '{0}/providers/Microsoft.Authorization/roleAssignmentScheduleRequests?$filter=asTarget()&api-version=2020-10-01' -f $PollScope
                            $Polled = @((Invoke-OPIMArmRequest -Path $PollPath -All).value |
                                    Where-Object { $_.name -eq $Response.Name } |
                                    ConvertFrom-OPIMArmSchedule -Kind AssignmentScheduleRequest)
                        } catch {
                            # An ARM failure record can point at the request and its bearer token:
                            # scrub it, then report it as itself for this role only.
                            Remove-OPIMErrorRecord -Record $PSItem
                            $PSCmdlet.WriteError($PSItem)
                            $PollFailed = $true
                            break
                        }
                        # Not listed yet: the request is still in progress.
                        if ($Polled.Count -eq 1) {
                            $Current = $Polled[0]
                            $Status = [string]$Current.Status
                        }
                    }
                    if ($PollFailed) { continue }
                }
                $Current.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleRequest')
                if ($TimedOut) {
                    $PSCmdlet.WriteError((New-OPIMRequestError -ErrorId ActivationWaitTimedOut -Name $Label `
                        -Status $Status -TimeoutSeconds $TimeoutSeconds -Request $Current))
                    continue
                }
                Write-OPIMRequestOutcome -Request $Current -Status $Status -Name $Label -Cmdlet $PSCmdlet
            }
        }
    }
}
