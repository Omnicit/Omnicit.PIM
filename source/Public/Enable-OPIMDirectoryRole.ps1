function Enable-OPIMDirectoryRole {
    <#
    .SYNOPSIS
    Activate an Azure AD PIM eligible directory role.
    .DESCRIPTION
    Activates an eligible directory role assignment for the current user. By default activates for 1 hour.
    The role is named by its display name, or by the form tab completion offers for the RoleName
    parameter ('Role (id)', and 'Role -> Administrative unit (id)' below the root scope). A name that
    matches the role at more than one scope is refused with AmbiguousName and nothing is activated:
    add -Scope to pick one. A name that matches no eligible role is written as an EligibleRoleNotFound
    error. Several names are resolved one by one, each on its own, so a name that fails does not stop
    the next one.
    The request is reported by the status Graph gives it: a request that failed, was denied or was
    canceled is written as an ActivationRequestFailed error, and one that waits for approval or is
    still being provisioned is returned with a warning.
    .NOTES
    The default activation period is 1 hour. Override with -Hours. Make it persistent in your profile:

    $PSDefaultParameterValues['Enable-OPIM*:Hours'] = 5

    .EXAMPLE
    Get-OPIMDirectoryRole | Enable-OPIMDirectoryRole
    Activate all eligible directory roles for 1 hour.
    .EXAMPLE
    Enable-OPIMDirectoryRole 'Usage Summary Reports Reader' -Justification 'Monthly report'
    Activates the role by its display name. A name that matches the role at more than one scope is
    refused with AmbiguousName; add -Scope '/' or -Scope with the administrative unit.
    .EXAMPLE
    Enable-OPIMDirectoryRole 'Usage Summary Reports Reader', 'Reports Reader' -Scope '/' -Hours 4
    Activates both roles at the root scope for 4 hours. Each name is resolved on its own: one that is
    ambiguous or unknown is written as an error, and the other is still activated.
    .EXAMPLE
    Enable-OPIMDirectoryRole 'Usage Summary Reports Reader (elig-001)'
    The form tab completion offers, with the schedule id in parentheses, still works.
    .EXAMPLE
    Enable-OPIMDirectoryRole <tab>
    Tab complete all eligible directory roles. A name that is unique is offered bare; one that is not
    is offered in the longer form.
    .EXAMPLE
    Get-OPIMDirectoryRole | Select -First 1 | Enable-OPIMDirectoryRole -Hours 4
    Activate the first eligible role for 4 hours.
    .EXAMPLE
    Get-OPIMDirectoryRole | Select -First 1 | Enable-OPIMDirectoryRole -NotBefore '4pm' -Until '5pm'
    Activate a role from 4pm to 5pm today.
    .OUTPUTS
    System.Collections.Hashtable (tagged as Omnicit.PIM.DirectoryAssignmentScheduleRequest)
    .PARAMETER Role
    Eligible directory role schedule object piped from Get-OPIMDirectoryRole. Used when activating
    by object rather than by name. Mutually exclusive with -RoleName.
    .PARAMETER RoleName
    The display name of the eligible directory role, or the tab-completed form the argument completer
    offers ('Role (id)'). A display name is compared exactly, without regard to letter case, and takes
    no wildcards. Accepts multiple values, each resolved on its own; -Scope applies to every one of
    them. Several matches are refused with AmbiguousName. Mutually exclusive with -Role.
    .PARAMETER Identity
    The schedule item ID from Get-OPIMDirectoryRole (the id property) to activate directly without
    a name. An id that matches more than one schedule is refused with AmbiguousName. Mutually
    exclusive with -Role and -RoleName.
    .PARAMETER Justification
    Free-text justification for the activation request. May be required by your PIM policy.
    .PARAMETER TicketNumber
    Ticket or work item number associated with this activation for auditing purposes.
    .PARAMETER TicketSystem
    Name of the ticket system that issued the above ticket number, e.g. ServiceNow or Jira.
    .PARAMETER Hours
    Activation duration in hours. Defaults to 1. Ignored when -Until is specified.
    .PARAMETER NotBefore
    Date and time when the role activation begins. Defaults to the current date and time.
    .PARAMETER Until
    Explicit end date and time for the activation. Takes precedence over -Hours when specified.
    Aliased as -NotAfter.
    .PARAMETER Scope
    Picks one role when the name matches the role at more than one scope: '/' for the directory
    itself, or an administrative unit's directoryScopeId ('/administrativeUnits/' and its id) or its
    display name. Compared without regard to letter case; a scope that ends in '/' (other than '/') is
    refused. Applies to every name in -RoleName, and cannot be combined with piped objects (-Role) or
    -Identity: piping objects in together with -Scope selects the -RoleName parameter set, so an
    interactive host asks for -RoleName instead of failing to bind.
    .PARAMETER Wait
    Hand the requests to Wait-OPIMDirectoryRole -PassThru, which waits for each until it is
    provisioned and its role assignment appears, up to -TimeoutSeconds, and returns the activated
    assignments and the requests that ended without one. A request Graph has already refused is
    reported here and not waited for.
    .PARAMETER TimeoutSeconds
    With -Wait, the most seconds to wait for each request, counted from the time Graph created it.
    Defaults to 300. A request that waits for approval ends its wait at once, with a warning; one
    still in progress at the limit is written as an ActivationWaitTimedOut error and stays
    submitted.
    #>
    [Alias('Enable-PIMADRole', 'Enable-PIMRole')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'RoleName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'RoleObject', Mandatory, ValueFromPipeline)]
        $Role,
        [Parameter(Position = 0, ParameterSetName = 'RoleName', Mandatory)]
        [ArgumentCompleter([DirectoryEligibleRoleCompleter])]
        [string[]]$RoleName,
        [Parameter(ParameterSetName = 'ByIdentity', Mandatory)]
        [string]$Identity,
        [Parameter(Position = 1)][string]$Justification,
        [string]$TicketNumber,
        [string]$TicketSystem,
        [Parameter(Position = 2)][ValidateNotNullOrEmpty()][int]$Hours = 1,
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
        Initialize-OPIMAuth
        [System.Collections.Generic.List[PSObject]]$_pendingWait = [System.Collections.Generic.List[PSObject]]::new()
    }
    process {
        if ($Identity) {
            try {
                $FoundByIdentity = @(Get-OPIMDirectoryRole -Identity $Identity -ErrorAction Stop)
            } catch {
                # OPIM-12: the listing failed; report it as itself and stop for this identity.
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            if ($FoundByIdentity.Count -gt 1) {
                # Never the first of several: refuse with the candidates and act on none.
                $PSCmdlet.WriteError((New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Directory `
                    -Name $Identity -Status Both -Candidate $FoundByIdentity -Identity))
                return
            }
            $Role = $FoundByIdentity | Select-Object -First 1
            if (-not $Role) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("No eligible directory role found with identity '$Identity'.")) `
                    -ErrorId 'IdentityNotFound' `
                    -Category ObjectNotFound `
                    -TargetObject $Identity `
                    -Cmdlet $PSCmdlet
                return
            }
        }
        $ResolvedRoles = if ($RoleName) {
            $ResolveParams = @{ Pillar = 'Directory'; FilterParameter = 'Scope'; ErrorAction = 'Stop' }
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
            # Skip already-active instances piped from Get-OPIMDirectoryRole -All
            if ($Role.PSObject.TypeNames -contains 'Omnicit.PIM.DirectoryAssignmentScheduleInstance') {
                Write-Verbose "Skipping already-active directory role: $($Role.roleDefinition.displayName)"
                continue
            }
            $ScheduleInfo = @{
                startDateTime = $NotBefore.ToString('o')
                expiration    = @{}
            }

            $Expiration = $ScheduleInfo.expiration
            if ($Until) {
                $Expiration.type        = 'AfterDateTime'
                $Expiration.endDateTime = $Until.ToString('o')
                [string]$RoleExpireTime = $Until
            } else {
                $Expiration.type     = 'AfterDuration'
                $Expiration.duration = [System.Xml.XmlConvert]::ToString([TimeSpan]::FromHours($Hours))
                [string]$RoleExpireTime = $NotBefore.AddHours($Hours)
            }

            $Request = @{
                action           = 'SelfActivate'
                justification    = $Justification
                roleDefinitionId = $Role.roleDefinitionId
                directoryScopeId = $Role.directoryScopeId
                principalId      = $Role.principalId
                scheduleInfo     = $ScheduleInfo
                ticketInfo       = @{
                    ticketNumber = $TicketNumber
                    ticketSystem = $TicketSystem
                }
            }

            $UserPrincipalName = $Role.principal.userPrincipalName
            if ($PSCmdlet.ShouldProcess(
                    $UserPrincipalName,
                    "Activate $($Role.roleDefinition.displayName) for scope $($Role.directoryScopeId) from $NotBefore to $RoleExpireTime"
                )) {
                $GraphUri = 'v1.0/roleManagement/directory/roleAssignmentScheduleRequests'
                $Response = try {
                    Invoke-OPIMGraphRequest -Method POST -Uri $GraphUri -Body $Request
                } catch {
                    Remove-OPIMErrorRecord -Record $PSItem
                    $Err = $PSItem
                    if (-not (ConvertTo-PolicyValidationError -CaughtError $Err -ResourceType 'role' -Cmdlet $PSCmdlet)) {
                        $PSCmdlet.WriteError($Err)
                    }
                    continue
                }
                if ($null -eq $Response) { continue }

                # Rehydrate expanded navigation properties from the eligibility schedule
                'roleDefinition', 'principal', 'directoryScope' | Restore-GraphProperty $Request $Response $Role

                # Convert to PSCustomObject so custom Format views apply (hashtable uses Key/Value formatter).
                $Out = [PSCustomObject]$Response
                $Out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')

                $Label = (Get-OPIMScheduleName -Pillar Directory -InputObject $Role).Label
                if ($Wait -and (Get-OPIMRequestOutcome -Status $Out.status) -ne 'Failed') {
                    # Wait-OPIMDirectoryRole reads the status again and reports it. A request Graph has
                    # already refused is reported here and never waited for.
                    $_pendingWait.Add($Out)
                } else {
                    Write-OPIMRequestOutcome -Request $Out -Status $Out.status -Name $Label -Cmdlet $PSCmdlet
                }
            }
        }
    }
    end {
        if ($_pendingWait.Count -gt 0) {
            $_pendingWait | Wait-OPIMDirectoryRole -PassThru -TimeoutSeconds $TimeoutSeconds
        }
    }
}
