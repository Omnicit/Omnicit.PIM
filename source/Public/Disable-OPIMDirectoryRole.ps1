function Disable-OPIMDirectoryRole {
    <#
    .SYNOPSIS
    Deactivate an active Azure AD PIM directory role.
    .DESCRIPTION
    Submits a SelfDeactivate request for an active directory role assignment.
    The role is named by its display name, or by the form tab completion offers for the RoleName
    parameter for your currently active roles. A name that matches the role at more than one scope is
    refused with AmbiguousName and nothing is deactivated: add -Scope to pick one. A name that matches
    no active role is written as a (non-terminating) ActiveRoleNotFound error; when the role is
    eligible but not active, the message says it is already deactivated.
    The request is reported by the status Graph gives it: a deactivation that does not end Revoked
    is written as an ActivationRequestFailed error, and one that waits for approval or is still
    being processed is returned with a warning.
    .EXAMPLE
    Get-OPIMDirectoryRole -Activated | Disable-OPIMDirectoryRole
    Deactivate all currently active directory roles.
    .EXAMPLE
    Disable-OPIMDirectoryRole 'Usage Summary Reports Reader'
    Deactivates the role by its display name. A name that matches the role at more than one scope is
    refused with AmbiguousName; add -Scope '/' or -Scope with the administrative unit.
    .EXAMPLE
    Disable-OPIMDirectoryRole <tab>
    Tab complete active roles; type letters to filter. A name that is unique is offered bare.
    .EXAMPLE
    Get-OPIMDirectoryRole -Activated | Select-Object -First 1 | Disable-OPIMDirectoryRole
    Deactivate the first active role.
    .OUTPUTS
    System.Collections.Hashtable (tagged as Omnicit.PIM.DirectoryAssignmentScheduleRequest)
    .PARAMETER Role
    Active directory role assignment schedule instance object piped from Get-OPIMDirectoryRole -Activated.
    .PARAMETER RoleName
    The display name of the active directory role to deactivate, or the tab-completed form the
    argument completer offers for your currently active roles. A display name is compared exactly,
    without regard to letter case, and takes no wildcards. Several matches are refused with
    AmbiguousName.
    .PARAMETER Identity
    The schedule instance ID from Get-OPIMDirectoryRole -Activated (the id property) to deactivate
    directly without a name. An id that matches more than one instance is refused with
    AmbiguousName. Mutually exclusive with -Role and -RoleName.
    .PARAMETER Scope
    Picks one role when the name matches the role at more than one scope: '/' for the directory
    itself, or an administrative unit's directoryScopeId ('/administrativeUnits/' and its id) or its
    display name. Compared without regard to letter case; a scope that ends in '/' (other than '/') is
    refused. Applies to a name, and cannot be combined with piped objects (-Role) or -Identity:
    piping objects in together with -Scope selects the -RoleName parameter set, so an interactive
    host asks for -RoleName instead of failing to bind.
    #>
    [Alias('Disable-PIMADRole', 'Disable-PIMRole')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'RoleName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'RoleObject', Mandatory, ValueFromPipeline)]
        $Role,
        [ArgumentCompleter([DirectoryActivatedRoleCompleter])]
        [Parameter(ParameterSetName = 'RoleName', Mandatory, Position = 0)]
        [String]$RoleName,
        [Parameter(ParameterSetName = 'ByIdentity', Mandatory)]
        [String]$Identity,
        [Parameter(ParameterSetName = 'RoleName')]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ $_ -eq '/' -or -not $_.EndsWith('/') }, ErrorMessage = "The scope '{0}' ends with '/'. Give it without the trailing slash; only the root scope is written '/'.")]
        [string]$Scope
    )
    process {
        Initialize-OPIMAuth
        if ($Identity) {
            try {
                $FoundByIdentity = @(Get-OPIMDirectoryRole -Activated -Identity $Identity -ErrorAction Stop)
            } catch {
                # OPIM-12: the listing failed; report it as itself and stop for this identity.
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            if ($FoundByIdentity.Count -gt 1) {
                # Never the first of several: refuse with the candidates and act on none.
                $PSCmdlet.WriteError((New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Directory `
                    -Name $Identity -Status Active -Candidate $FoundByIdentity -Identity))
                return
            }
            $Role = $FoundByIdentity | Select-Object -First 1
            if (-not $Role) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("No active directory role found with identity '$Identity'.")) `
                    -ErrorId 'IdentityNotFound' `
                    -Category ObjectNotFound `
                    -TargetObject $Identity `
                    -Cmdlet $PSCmdlet
                return
            }
        }
        if ($RoleName) {
            $ResolveParams = @{ Pillar = 'Directory'; Status = 'Active'; FilterParameter = 'Scope'; ErrorAction = 'Stop' }
            if ($PSBoundParameters.ContainsKey('Scope')) { $ResolveParams.Scope = $Scope }
            try {
                $Role = Resolve-OPIMSchedule -Name $RoleName @ResolveParams
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }

        # Skip eligible-only schedules piped from Get-OPIMDirectoryRole -All
        if ($Role.PSObject.TypeNames -contains 'Omnicit.PIM.DirectoryEligibilitySchedule') {
            Write-Verbose "Skipping eligible-only directory role: $($Role.roleDefinition.displayName)"
            return
        }

        $Request = @{
            action           = 'SelfDeactivate'
            roleDefinitionId = $Role.roleDefinitionId
            directoryScopeId = $Role.directoryScopeId
            principalId      = $Role.principalId
            targetScheduleId = $Role.roleAssignmentScheduleId
        }

        if ($PSCmdlet.ShouldProcess(
                $('{0} ({1})' -f $Role.roleDefinition.displayName, $Role.directoryScopeId),
                'Deactivate Directory Role'
            )) {
            $Response = try {
                Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleAssignmentScheduleRequests' -Body $Request
            } catch {
                Remove-OPIMErrorRecord -Record $PSItem
                $Err = $PSItem
                if (-not (ConvertTo-ActiveDurationTooShortError -CaughtError $Err -ResourceType 'role' -Cmdlet $PSCmdlet)) {
                    $PSCmdlet.WriteError($Err)
                }
                return
            }

            # Rehydrate expanded navigation properties from the active schedule instance
            'roleDefinition', 'principal', 'directoryScope' | Restore-GraphProperty $Request $Response $Role

            # Set a meaningful expiration to the createdDateTime for display
            if (-not $Response.scheduleInfo) { $Response['scheduleInfo'] = @{ expiration = @{} } }
            $Response.scheduleInfo.expiration.type        = 'afterDateTime'
            $Response.scheduleInfo.expiration.endDateTime = $Response.createdDateTime

            # Convert to PSCustomObject so custom Format views apply (hashtable uses Key/Value formatter).
            $Out = [PSCustomObject]$Response
            $Out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')
            $Label = (Get-OPIMScheduleName -Pillar Directory -InputObject $Role).Label
            Write-OPIMRequestOutcome -Request $Out -Status $Out.status -Name $Label -Deactivate -Cmdlet $PSCmdlet
            return
        }
    }
}
