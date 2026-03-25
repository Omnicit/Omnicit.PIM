function Enable-OPIMDirectoryRole {
    <#
    .SYNOPSIS
    Activate an Azure AD PIM eligible directory role.
    .DESCRIPTION
    Activates an eligible directory role assignment for the current user. By default activates for 1 hour.
    The RoleName parameter supports tab completion for available eligible roles.
    .NOTES
    The default activation period is 1 hour. Override with -Hours. Make it persistent in your profile:

    $PSDefaultParameterValues['Enable-OPIM*:Hours'] = 5

    .EXAMPLE
    Get-OPIMDirectoryRole | Enable-OPIMDirectoryRole
    Activate all eligible directory roles for 1 hour.
    .EXAMPLE
    Enable-OPIMDirectoryRole <tab>
    Tab complete all eligible directory roles.
    .EXAMPLE
    Get-OPIMDirectoryRole | Select -First 1 | Enable-OPIMDirectoryRole -Hours 4
    Activate the first eligible role for 4 hours.
    .EXAMPLE
    Get-OPIMDirectoryRole | Select -First 1 | Enable-OPIMDirectoryRole -NotBefore '4pm' -Until '5pm'
    Activate a role from 4pm to 5pm today.
    .OUTPUTS
    System.Collections.Hashtable (tagged as Omnicit.PIM.DirectoryAssignmentScheduleRequest)
    #>
    [Alias('Enable-PIMADRole', 'Enable-PIMRole')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'RoleName')]
    [OutputType([System.Collections.Hashtable])]
    param(
        #Eligible role schedule object from Get-OPIMDirectoryRole.
        [Parameter(ParameterSetName = 'RoleObject', Mandatory, ValueFromPipeline)]
        $Role,
        #Friendly name of the eligible role. Supports tab completion. Accepts multiple values.
        [Parameter(Position = 0, ParameterSetName = 'RoleName', Mandatory)]
        [ArgumentCompleter([DirectoryEligibleRoleCompleter])]
        [string[]]$RoleName,
        #Justification for the activation. May be required by your PIM policy.
        [string]$Justification,
        #Ticket number associated with this activation.
        [string]$TicketNumber,
        #Ticket system containing the above ticket number.
        [string]$TicketSystem,
        #Duration in hours. Defaults to 1 hour.
        [ValidateNotNullOrEmpty()][int]$Hours = 1,
        #Date and time when the role activation begins. Defaults to now.
        [ValidateNotNullOrEmpty()][DateTime]$NotBefore = [DateTime]::Now,
        #Explicit end date/time for the role activation. Takes precedence over -Hours when specified.
        [DateTime][Alias('NotAfter')]$Until,
        #Wait until the role is fully provisioned before returning.
        [Switch]$Wait
    )
    begin {
        [System.Collections.Generic.List[PSObject]]$_pendingWait = [System.Collections.Generic.List[PSObject]]::new()
    }
    process {
        $resolvedRoles = if ($RoleName) {
            $RoleName | ForEach-Object { Resolve-RoleByName -AD $_ }
        } else {
            @($Role)
        }

        foreach ($Role in $resolvedRoles) {
            $scheduleInfo = @{
                startDateTime = $NotBefore.ToString('o')
                expiration    = @{}
            }

            $expiration = $scheduleInfo.expiration
            if ($Until) {
                $expiration.type        = 'AfterDateTime'
                $expiration.endDateTime = $Until.ToString('o')
                [string]$roleExpireTime = $Until
            } else {
                $expiration.type     = 'AfterDuration'
                $expiration.duration = [System.Xml.XmlConvert]::ToString([TimeSpan]::FromHours($Hours))
                [string]$roleExpireTime = $NotBefore.AddHours($Hours)
            }

            $request = @{
                action           = 'SelfActivate'
                justification    = $Justification
                roleDefinitionId = $Role.roleDefinitionId
                directoryScopeId = $Role.directoryScopeId
                principalId      = $Role.principalId
                scheduleInfo     = $scheduleInfo
                ticketInfo       = @{
                    ticketNumber = $TicketNumber
                    ticketSystem = $TicketSystem
                }
            }

            $userPrincipalName = $Role.principal.userPrincipalName
            if ($PSCmdlet.ShouldProcess(
                    $userPrincipalName,
                    "Activate $($Role.roleDefinition.displayName) for scope $($Role.directoryScopeId) from $NotBefore to $roleExpireTime"
                )) {
                $response = try {
                    Invoke-MgGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleAssignmentScheduleRequests' -Body $request -Verbose:$false -ErrorAction Stop
                } catch {
                    $err = Convert-GraphHttpException $PSItem
                    if (-not ($err.FullyQualifiedErrorId -like 'RoleAssignmentRequestPolicyValidationFailed*')) {
                        $PSCmdlet.WriteError($err)
                        continue
                    }
                    if ($err -match 'JustificationRule') {
                        $err.ErrorDetails = 'Your PIM policy requires a justification for this role. Use the -Justification parameter.'
                    }
                    if ($err -match 'ExpirationRule') {
                        $err.ErrorDetails = 'Your PIM policy requires a shorter expiration. Use -NotAfter to specify an earlier time.'
                    }
                    $PSCmdlet.WriteError($err)
                    continue
                }

                # Rehydrate expanded navigation properties from the eligibility schedule
                'roleDefinition', 'principal', 'directoryScope' | Restore-GraphProperty $request $response $Role

                # Convert to PSCustomObject so custom Format views apply (hashtable uses Key/Value formatter).
                $out = [PSCustomObject]$response
                $out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')

                if ($Wait) {
                    $_pendingWait.Add($out)
                } else {
                    $out
                }
            }
        }
    }
    end {
        if ($_pendingWait.Count -gt 0) {
            $_pendingWait | Wait-OPIMDirectoryRole -PassThru
        }
    }
}
