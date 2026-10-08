BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Disable-OPIMDirectoryRole' {
    BeforeAll {
        # A post as Get-OPIMDirectoryRole lists it, typed as it types it. Each carries the properties
        # the self-referencing ScriptProperties of its type read (Omnicit.PIM.Types.ps1xml): the
        # instance type reads memberType and endDateTime, and a typed fake without them overflows the
        # stack when a failing assertion formats it.
        function New-DirectoryPost {
            param([string]$Id, [string]$DefinitionId, [string]$RoleName, [string]$ScopeId = '/', [string]$ScopeName, [switch]$Active)
            $Post = [PSCustomObject]@{
                id                       = $Id
                roleDefinitionId         = $DefinitionId
                directoryScopeId         = $ScopeId
                directoryScope           = if ($ScopeName) { [PSCustomObject]@{ id = $ScopeId; displayName = $ScopeName } } else { [PSCustomObject]@{ id = $ScopeId } }
                principalId              = 'principal-001'
                roleAssignmentScheduleId = "schedule-$Id"
                roleDefinition           = [PSCustomObject]@{ displayName = $RoleName }
                principal                = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
                scheduleInfo             = $null
            }
            if ($Active) {
                $Post | Add-Member -NotePropertyName memberType -NotePropertyValue 'Direct'
                $Post | Add-Member -NotePropertyName endDateTime -NotePropertyValue $null
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')
            } else {
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            }
            $Post
        }
    }

    Context 'When called with -RoleName (happy path)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeRole = [PSCustomObject]@{
                id                       = 'instance-001'
                roleDefinitionId         = 'role-def-001'
                directoryScopeId         = '/'
                principalId              = 'principal-001'
                roleAssignmentScheduleId = 'schedule-001'
                roleDefinition           = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal                = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id              = 'deact-req-001'
                    action          = 'SelfDeactivate'
                    status          = 'Provisioned'
                    createdDateTime = '2024-01-01T12:00:00Z'
                }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'calls Resolve-OPIMSchedule for the supplied role name' {
            Disable-OPIMDirectoryRole -RoleName 'Global Administrator (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It
        }

        It 'calls Invoke-OPIMGraphRequest with POST to the roleAssignmentScheduleRequests endpoint' {
            Disable-OPIMDirectoryRole -RoleName 'Global Administrator (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*roleAssignmentScheduleRequests*'
            }
        }

        It 'sends SelfDeactivate as the action in the request body' {
            Disable-OPIMDirectoryRole -RoleName 'Global Administrator (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.action -eq 'SelfDeactivate'
            }
        }

        It 'sends the roleAssignmentScheduleId as targetScheduleId in the request body' {
            Disable-OPIMDirectoryRole -RoleName 'Global Administrator (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.targetScheduleId -eq 'schedule-001'
            }
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.DirectoryAssignmentScheduleRequest' {
            $Result = Disable-OPIMDirectoryRole -RoleName 'Global Administrator (instance-001)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleRequest'
        }
    }

    Context 'When called with pipeline input (-Role parameter set)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeRole = [PSCustomObject]@{
                id                       = 'instance-002'
                roleDefinitionId         = 'role-def-002'
                directoryScopeId         = '/administrativeUnits/au-001'
                principalId              = 'principal-002'
                roleAssignmentScheduleId = 'schedule-002'
                roleDefinition           = [PSCustomObject]@{ displayName = 'User Administrator' }
                principal                = [PSCustomObject]@{ displayName = 'John Smith'; userPrincipalName = 'john@contoso.com' }
            }
            $FakeRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id              = 'deact-req-002'
                    action          = 'SelfDeactivate'
                    status          = 'Provisioned'
                    createdDateTime = '2024-01-01T12:00:00Z'
                }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'calls Invoke-OPIMGraphRequest with the roleDefinitionId and directoryScopeId from the piped role' {
            $FakeRole | Disable-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and
                $Body.roleDefinitionId -eq 'role-def-002' -and
                $Body.directoryScopeId -eq '/administrativeUnits/au-001'
            }
        }

        It 'calls Invoke-OPIMGraphRequest with the principalId from the piped role' {
            $FakeRole | Disable-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.principalId -eq 'principal-002'
            }
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.DirectoryAssignmentScheduleRequest' {
            $Result = $FakeRole | Disable-OPIMDirectoryRole
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleRequest'
        }
    }

    Context 'When -WhatIf is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeRole = [PSCustomObject]@{
                id                       = 'instance-001'
                roleDefinitionId         = 'role-def-001'
                directoryScopeId         = '/'
                principalId              = 'principal-001'
                roleAssignmentScheduleId = 'schedule-001'
                roleDefinition           = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal                = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest { } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not call Invoke-OPIMGraphRequest when -WhatIf is specified' {
            Disable-OPIMDirectoryRole -RoleName 'Global Administrator (instance-001)' -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It
        }
    }

    Context 'When the Graph API returns a general error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeRole = [PSCustomObject]@{
                id                       = 'instance-001'
                roleDefinitionId         = 'role-def-001'
                directoryScopeId         = '/'
                principalId              = 'principal-001'
                roleAssignmentScheduleId = 'schedule-001'
                roleDefinition           = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal                = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"GeneralError","message":"An unexpected error occurred."}}'
                )
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not throw a terminating error' {
            { Disable-OPIMDirectoryRole -RoleName 'Global Administrator (instance-001)' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMDirectoryRole -RoleName 'Global Administrator (instance-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When the API returns an ActiveDurationTooShort error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeRole = [PSCustomObject]@{
                id                       = 'instance-001'
                roleDefinitionId         = 'role-def-001'
                directoryScopeId         = '/'
                principalId              = 'principal-001'
                roleAssignmentScheduleId = 'schedule-001'
                roleDefinition           = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal                = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"ActiveDurationTooShort","message":"Role was not activated long enough to meet the minimum wait period."}}'
                )
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMDirectoryRole -RoleName 'Global Administrator (instance-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'includes the 5-minute cooldown message in the error details' {
            $Errors = @()
            Disable-OPIMDirectoryRole -RoleName 'Global Administrator (instance-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].Exception.Message | Should -Match '5 minutes'
        }
    }

    Context 'When -Identity is specified and the role is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeActive = [PSCustomObject]@{
                id                       = 'instance-002'
                roleDefinitionId         = 'role-def-001'
                directoryScopeId         = '/'
                principalId              = 'principal-001'
                roleAssignmentScheduleId = 'schedule-002'
                roleDefinition           = [PSCustomObject]@{ displayName = 'Reports Reader' }
                principal                = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            $FakeActive.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return $FakeActive }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id              = 'deact-req-002'
                    action          = 'SelfDeactivate'
                    status          = 'Provisioned'
                    createdDateTime = '2024-01-01T12:00:00Z'
                }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'looks up the role via Get-OPIMDirectoryRole -Activated -Identity' {
            Disable-OPIMDirectoryRole -Identity 'instance-002'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 1 -Scope It
        }

        It 'submits the SelfDeactivate request' {
            Disable-OPIMDirectoryRole -Identity 'instance-002'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.DirectoryAssignmentScheduleRequest' {
            $Result = Disable-OPIMDirectoryRole -Identity 'instance-002'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleRequest'
        }
    }

    Context 'When -Identity is specified but no active role is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return $null }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMDirectoryRole -Identity 'nonexistent-999' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'writes IdentityNotFound to its own error stream' {
            $Out = Disable-OPIMDirectoryRole -Identity 'nonexistent-999' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'IdentityNotFound*'
        }
    }

    Context 'When the listing for -Identity fails' {
        # OPIM-12: a listing that cannot be read is reported as itself and stops for that identity;
        # it is never reported as IdentityNotFound. The mock writes the record a listing writes for
        # a failed read (a Graph 403).
        # The mock takes its preference from an explicit -ErrorAction and is Continue otherwise, as a
        # listing is under the default preference: a module-scoped mock body reads the test scope's
        # preference (Stop under the build), never the caller's.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole {
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {}
        }

        It "writes the listing's error as itself" {
            # The command's own error stream, not -ErrorVariable: -ErrorVariable also collects the
            # record the listing raised and the command caught.
            $Out = Disable-OPIMDirectoryRole -Identity 'active-403' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
        }

        It 'does not write IdentityNotFound' {
            $Out = Disable-OPIMDirectoryRole -Identity 'active-403' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            @($Written | Where-Object { $_.FullyQualifiedErrorId -like 'IdentityNotFound*' }).Count | Should -Be 0
        }

        It 'sends no deactivation' {
            Disable-OPIMDirectoryRole -Identity 'active-403' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When the listing for -RoleName fails' {
        # OPIM-12: the listing that cannot be read is written as itself, never as "not found", and
        # nothing is deactivated.
        # The mock takes its preference from an explicit -ErrorAction and is Continue otherwise, as a
        # listing is under the default preference: a module-scoped mock body reads the test scope's
        # preference (Stop under the build), never the caller's.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole {
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {}
        }

        It "writes the listing's error as itself and sends no deactivation" {
            # The command's own error stream, not -ErrorVariable: -ErrorVariable also collects the
            # record the listing raised and the command caught.
            $Out = Disable-OPIMDirectoryRole -RoleName 'Role A (active-a)' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
            @($Written | Where-Object { $_.FullyQualifiedErrorId -like '*NotFound*' }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When a DirectoryEligibilitySchedule is piped from Get-OPIMDirectoryRole -All' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest { } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'skips the eligible-only schedule and does not POST to the Graph API' {
            $EligibleOnly = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
            }
            $EligibleOnly.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            $EligibleOnly | Disable-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When the display name matches the active role at more than one scope' {
        # The real resolver runs; only the listing and the transport are mocked. The listing answers
        # with the active posts only when it is asked for them (-Activated), so a name that is only
        # eligible must not be found.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Eligible = @(
                New-DirectoryPost -Id 'elig-003' -DefinitionId 'role-def-003' -RoleName 'Message Center Privacy Reader'
            )
            $Active = @(
                New-DirectoryPost -Id 'act-001' -DefinitionId 'role-def-001' -RoleName 'Usage Summary Reports Reader' -Active
                New-DirectoryPost -Id 'act-002' -DefinitionId 'role-def-001' -RoleName 'Usage Summary Reports Reader' -ScopeId '/administrativeUnits/au-001' -ScopeName 'Sales AU' -Active
                New-DirectoryPost -Id 'act-004' -DefinitionId 'role-def-004' -RoleName 'Security Reader' -Active
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { $Eligible }
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { $Active } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'deact-req-001'; action = 'SelfDeactivate'; status = 'Provisioned'; createdDateTime = '2024-01-01T12:00:00Z' }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'writes AmbiguousName and sends no deactivation' {
            $Errs = @()
            Disable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -ErrorVariable Errs -ErrorAction SilentlyContinue
            # The active list was read, so the resolver and the catch that writes its record were reached.
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 1 -Exactly -Scope It -ParameterFilter { $Activated }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Disable-OPIMDirectoryRole'
        }

        It 'tells the user that -Scope separates the candidates' {
            $Errs = @()
            Disable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].Exception.Message | Should -BeLike '*-Scope*'
        }

        It 'deactivates the one role that -Scope names' {
            Disable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -Scope '/administrativeUnits/au-001' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.action -eq 'SelfDeactivate' -and
                $Body.directoryScopeId -eq '/administrativeUnits/au-001' -and $Body.targetScheduleId -eq 'schedule-act-002'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }

        It 'deactivates the root role when -Scope is /' {
            Disable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -Scope '/' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.directoryScopeId -eq '/' -and $Body.targetScheduleId -eq 'schedule-act-001'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }

        It 'deactivates a unique display name with its own ids' {
            Disable-OPIMDirectoryRole -RoleName 'security reader' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.roleDefinitionId -eq 'role-def-004' -and
                $Body.targetScheduleId -eq 'schedule-act-004' -and $Body.principalId -eq 'principal-001'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes ActiveRoleNotFound for a role that is eligible but not active' {
            $Errs = @()
            Disable-OPIMDirectoryRole -RoleName 'Message Center Privacy Reader' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound,Disable-OPIMDirectoryRole'
        }
    }

    Context 'When -Identity matches more than one listed post' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-DirectoryPost -Id 'dup-001' -DefinitionId 'role-def-001' -RoleName 'Usage Summary Reports Reader' -Active
                New-DirectoryPost -Id 'dup-001' -DefinitionId 'role-def-001' -RoleName 'Usage Summary Reports Reader' -ScopeId '/administrativeUnits/au-001' -ScopeName 'Sales AU' -Active
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { $Listing }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'deact-req-001'; action = 'SelfDeactivate'; status = 'Provisioned'; createdDateTime = '2024-01-01T12:00:00Z' }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'writes AmbiguousName, not IdentityNotFound, and sends no deactivation' {
            $Errs = @()
            Disable-OPIMDirectoryRole -Identity 'dup-001' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Disable-OPIMDirectoryRole'
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'IdentityNotFound*' }).Count | Should -Be 0
        }
    }

    Context 'When -Scope is given where it does not belong' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest { } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'fails to bind -Scope together with -Identity' {
            { Disable-OPIMDirectoryRole -Identity 'act-001' -Scope '/' } | Should -Throw -ErrorId 'AmbiguousParameterSet*'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }

        It 'puts -Scope in the RoleName parameter set only' {
            # A piped object binds -Role in another set, so -Scope with it selects the RoleName set, whose
            # mandatory name is then missing. Read the sets from the command metadata instead of
            # binding: an interactive host would prompt for the name.
            (Get-Command Disable-OPIMDirectoryRole).Parameters['Scope'].ParameterSets.Keys | Should -Be 'RoleName'
        }

        It 'refuses a -Scope that ends with a slash' {
            { Disable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -Scope '/administrativeUnits/au-001/' } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }

        It 'refuses an empty -Scope' {
            { Disable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -Scope '' } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }
    }

    Context 'When the role is already deactivated (OPIM-40, G8)' {
        # The real resolver runs; only the listing, the transport and the restore are mocked. The
        # first call finds the role active and deactivates it, and that request ends the activation
        # in the mock, so the second call finds the role eligible and no longer active.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Held = @{ IsActive = $true }
            $ActivePost = New-DirectoryPost -Id 'act-001' -DefinitionId 'role-def-001' -RoleName 'Usage Summary Reports Reader' -Active
            $EligiblePost = New-DirectoryPost -Id 'elig-001' -DefinitionId 'role-def-001' -RoleName 'Usage Summary Reports Reader'
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { if ($Held.IsActive) { $ActivePost } } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { $EligiblePost }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $Held.IsActive = $false
                @{ id = 'deact-req-001'; action = 'SelfDeactivate'; status = 'Provisioned'; createdDateTime = '2024-01-01T12:00:00Z' }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'deactivates once and writes one non-terminating ActiveRoleNotFound that says it is already deactivated' {
            $Held.IsActive = $true
            $Out = & {
                Disable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -ErrorAction Continue
                Disable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -ErrorAction Continue
                'reached'
            } 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Results = @($Out | Where-Object { $_ -is [PSCustomObject] -and $_.PSObject.TypeNames -contains 'Omnicit.PIM.DirectoryAssignmentScheduleRequest' })
            # The statement after the second call ran, so the error did not end the script block.
            ($Out -contains 'reached') | Should -BeTrue
            $Results.Count | Should -Be 1
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound,Disable-OPIMDirectoryRole'
            $Written[0].Exception.Message | Should -BeLike '*already deactivated*'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
            # Both lists were read on the second call: the active list, then the eligible one for the hint.
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 2 -Exactly -Scope It -ParameterFilter { $Activated }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 1 -Exactly -Scope It -ParameterFilter { -not $Activated }
        }

        It 'names the active form, and deactivates nothing, for the eligibility key of a role that is active' {
            # What the 0.5.1 completers offered: the role's own key. The role is active as act-001, so the
            # message must not call it deactivated, and the name is not the active instance's.
            $Held.IsActive = $true
            $Out = & {
                Disable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader (elig-001)' -ErrorAction Continue
                'reached'
            } 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            ($Out -contains 'reached') | Should -BeTrue
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound,Disable-OPIMDirectoryRole'
            $Written[0].Exception.Message | Should -Not -BeLike '*already deactivated*'
            $Written[0].Exception.Message | Should -BeLike "*It is active as 'Usage Summary Reports Reader (act-001)'*"
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When the resolver writes an error instead of throwing it' {
        # The cmdlet calls the resolver with -ErrorAction Stop, so an error the resolver only writes
        # ends that name inside the cmdlet's own try and is written as the cmdlet's own error. The
        # mock takes its preference from an explicit -ErrorAction and is Continue otherwise, as the
        # resolver is under the default preference.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {}
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule {
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
        }

        It 'writes the error as its own and deactivates nothing' {
            $Out = Disable-OPIMDirectoryRole -RoleName 'Role A' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            @($Written | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Disable-OPIMDirectoryRole' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }
}
