BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Enable-OPIMDirectoryRole' {
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
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id               = 'req-001'
                    action           = 'SelfActivate'
                    roleDefinitionId = 'role-def-001'
                    directoryScopeId = '/'
                    principalId      = 'principal-001'
                    status           = 'Provisioned'
                }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'calls Resolve-OPIMSchedule for the supplied role name' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It
        }

        It 'calls Invoke-OPIMGraphRequest with POST to the roleAssignmentScheduleRequests endpoint' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*roleAssignmentScheduleRequests*'
            }
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.DirectoryAssignmentScheduleRequest' {
            $Result = Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleRequest'
        }

        It 'sends SelfActivate as the action in the request body' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.action -eq 'SelfActivate'
            }
        }

        It 'uses AfterDuration expiration type by default' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.type -eq 'AfterDuration'
            }
        }

        It 'passes a PT1H ISO 8601 duration when -Hours defaults to 1' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.duration -eq 'PT1H'
            }
        }
    }

    Context 'When called with multiple role names' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRoleA = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            $fakeRoleB = [PSCustomObject]@{
                id               = 'elig-002'
                roleDefinitionId = 'role-def-002'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'User Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule {
                if ($Name -like '*elig-001*') { return $fakeRoleA } else { return $fakeRoleB }
            }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id               = [System.Guid]::NewGuid().ToString()
                    action           = 'SelfActivate'
                    roleDefinitionId = $Body.roleDefinitionId
                    directoryScopeId = '/'
                    principalId      = 'principal-001'
                    status           = 'Provisioned'
                }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'calls Invoke-OPIMGraphRequest once per role name supplied' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)', 'User Administrator (elig-002)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When called with pipeline input (-Role parameter set)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-002'
                roleDefinitionId = 'role-def-002'
                directoryScopeId = '/administrativeUnits/au-001'
                principalId      = 'principal-002'
                roleDefinition   = [PSCustomObject]@{ displayName = 'User Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'John Smith'; userPrincipalName = 'john@contoso.com' }
            }
            $fakeRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id               = 'req-002'
                    action           = 'SelfActivate'
                    roleDefinitionId = 'role-def-002'
                    directoryScopeId = '/administrativeUnits/au-001'
                    principalId      = 'principal-002'
                    status           = 'Provisioned'
                }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'calls Invoke-OPIMGraphRequest with the roleDefinitionId and directoryScopeId from the piped role' {
            $fakeRole | Enable-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and
                $Body.roleDefinitionId -eq 'role-def-002' -and
                $Body.directoryScopeId -eq '/administrativeUnits/au-001'
            }
        }

        It 'calls Invoke-OPIMGraphRequest with the principalId from the piped role' {
            $fakeRole | Enable-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.principalId -eq 'principal-002'
            }
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.DirectoryAssignmentScheduleRequest' {
            $Result = $fakeRole | Enable-OPIMDirectoryRole
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleRequest'
        }
    }

    Context 'When -Until is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            $script:UntilDateTime = [DateTime]::Now.AddHours(3)
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id               = 'req-001'
                    action           = 'SelfActivate'
                    roleDefinitionId = 'role-def-001'
                    directoryScopeId = '/'
                    principalId      = 'principal-001'
                    status           = 'Provisioned'
                }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'uses AfterDateTime expiration type when -Until is provided' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -Until $script:UntilDateTime
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.type -eq 'AfterDateTime'
            }
        }

        It 'does not include a duration in the request body when -Until is specified' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -Until $script:UntilDateTime
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and -not $Body.scheduleInfo.expiration.duration
            }
        }
    }

    Context 'When -Hours overrides the default duration' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id               = 'req-001'
                    action           = 'SelfActivate'
                    roleDefinitionId = 'role-def-001'
                    directoryScopeId = '/'
                    principalId      = 'principal-001'
                    status           = 'Provisioned'
                }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'passes PT4H ISO 8601 duration when -Hours 4 is specified' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -Hours 4
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.duration -eq 'PT4H'
            }
        }

        It 'passes PT8H ISO 8601 duration when -Hours 8 is specified' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -Hours 8
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.duration -eq 'PT8H'
            }
        }
    }

    Context 'When ticket information is provided' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id               = 'req-001'
                    action           = 'SelfActivate'
                    roleDefinitionId = 'role-def-001'
                    directoryScopeId = '/'
                    principalId      = 'principal-001'
                    status           = 'Provisioned'
                }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'passes TicketNumber and TicketSystem in the ticketInfo request body' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -TicketNumber 'INC-123' -TicketSystem 'ServiceNow'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and
                $Body.ticketInfo.ticketNumber -eq 'INC-123' -and
                $Body.ticketInfo.ticketSystem -eq 'ServiceNow'
            }
        }
    }

    Context 'When -Justification is provided' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id               = 'req-001'
                    action           = 'SelfActivate'
                    roleDefinitionId = 'role-def-001'
                    directoryScopeId = '/'
                    principalId      = 'principal-001'
                    status           = 'Provisioned'
                }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'passes the justification text in the request body' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -Justification 'Deploying hotfix'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.justification -eq 'Deploying hotfix'
            }
        }
    }

    Context 'When -WhatIf is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest { } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not call Invoke-OPIMGraphRequest when -WhatIf is specified' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It
        }
    }

    Context 'When the Graph API returns a general error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"GeneralError","message":"An unexpected error occurred."}}'
                )
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not throw a terminating error' {
            { Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When the API returns a JustificationRule policy violation' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"RoleAssignmentRequestPolicyValidationFailed","message":"Policy validation failed: JustificationRule requires a justification."}}'
                )
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'sets error details with a hint to use the -Justification parameter' {
            $Errors = @()
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].Exception.Message | Should -BeLike '*-Justification*'
        }
    }

    Context 'When the API returns an ExpirationRule policy violation' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"RoleAssignmentRequestPolicyValidationFailed","message":"Policy validation failed: ExpirationRule duration exceeded."}}'
                )
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'sets error details with a hint to use the -NotAfter parameter' {
            $Errors = @()
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].Exception.Message | Should -BeLike '*-NotAfter*'
        }
    }

    Context 'When -Wait is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id               = 'req-001'
                    action           = 'SelfActivate'
                    roleDefinitionId = 'role-def-001'
                    directoryScopeId = '/'
                    principalId      = 'principal-001'
                    status           = 'Provisioned'
                }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
            Mock -ModuleName Omnicit.PIM Wait-OPIMDirectoryRole { }
        }

        It 'calls Wait-OPIMDirectoryRole when -Wait is specified' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -Wait
            Should -Invoke -ModuleName Omnicit.PIM Wait-OPIMDirectoryRole -Times 1 -Scope It
        }

        It 'does not call Wait-OPIMDirectoryRole when -Wait is not specified' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Wait-OPIMDirectoryRole -Times 0 -Scope It
        }
    }

    Context 'When API returns RoleAssignmentRequestPolicyValidationFailed with an unrecognized rule' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"RoleAssignmentRequestPolicyValidationFailed","message":"Policy validation failed: UnknownRuleViolation."}}'
                )
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not throw a terminating error' {
            { Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When the API returns RoleAssignmentRequestAcrsValidationFailed (throws from Invoke-OPIMGraphRequest)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('RoleAssignmentRequestAcrsValidationFailed: ACRS validation failed'),
                        'RoleAssignmentRequestAcrsValidationFailed',
                        [System.Management.Automation.ErrorCategory]::AuthenticationError,
                        $null
                    )
                )
            }
        }

        It 'does not throw a terminating error' {
            { Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'calls Invoke-OPIMGraphRequest once only (ACRS retry is handled inside Invoke-OPIMGraphRequest)' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It
        }
    }

    Context 'When -Identity is specified and the role is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeElig = [PSCustomObject]@{
                id               = 'elig-010'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Reports Reader' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return $FakeElig }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id               = 'req-010'
                    action           = 'SelfActivate'
                    roleDefinitionId = 'role-def-001'
                    directoryScopeId = '/'
                    principalId      = 'principal-001'
                    status           = 'Provisioned'
                }
            }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'looks up the role via Get-OPIMDirectoryRole -Identity' {
            Enable-OPIMDirectoryRole -Identity 'elig-010'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 1 -Scope It
        }

        It 'submits the SelfActivate request' {
            Enable-OPIMDirectoryRole -Identity 'elig-010'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.DirectoryAssignmentScheduleRequest' {
            $Result = Enable-OPIMDirectoryRole -Identity 'elig-010'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleRequest'
        }
    }

    Context 'When -Identity is specified but no eligible role is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return $null }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMDirectoryRole -Identity 'nonexistent-999' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'writes IdentityNotFound to its own error stream' {
            $Out = Enable-OPIMDirectoryRole -Identity 'nonexistent-999' -ErrorAction Continue 2>&1
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
            $Out = Enable-OPIMDirectoryRole -Identity 'elig-403' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
        }

        It 'does not write IdentityNotFound' {
            $Out = Enable-OPIMDirectoryRole -Identity 'elig-403' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            @($Written | Where-Object { $_.FullyQualifiedErrorId -like 'IdentityNotFound*' }).Count | Should -Be 0
        }

        It 'sends no activation' {
            Enable-OPIMDirectoryRole -Identity 'elig-403' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When the real listing for -Identity answers 403' {
        # OPIM-12 acceptance, end to end: the real Get-OPIMDirectoryRole reads through the transport
        # mock, which answers the list with the record the wrapper throws for a Graph 403.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: Insufficient privileges to complete the operation.'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' -or $Uri -like '*roleAssignmentScheduleInstances*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {} -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes the 403 as itself, reads no further list and sends no activation' {
            $Out = Enable-OPIMDirectoryRole -Identity 'elig-403' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleEligibilitySchedules*' -or $Uri -like '*roleAssignmentScheduleInstances*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When the listing for -RoleName fails' {
        # OPIM-12: each name resolves on its own. A listing that cannot be read is written as itself
        # for that name, never as "not found", and the next name still runs.
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

        It "writes the listing's error as itself for each name and activates nothing" {
            # The command's own error stream, not -ErrorVariable: -ErrorVariable also collects the
            # record the listing raised and the command caught.
            $Out = Enable-OPIMDirectoryRole -RoleName 'Role A (elig-a)', 'Role B (elig-b)' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 2
            @($Written | Where-Object { $_.FullyQualifiedErrorId -like 'Forbidden*' }).Count | Should -Be 2
            @($Written | Where-Object { $_.FullyQualifiedErrorId -like '*NotFound*' }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 2 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When positional parameters are used' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeElig = [PSCustomObject]@{
                id               = 'elig-pos-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Reports Reader' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeElig }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id               = 'req-pos-001'
                    action           = 'SelfActivate'
                    roleDefinitionId = 'role-def-001'
                    directoryScopeId = '/'
                    principalId      = 'principal-001'
                    status           = 'Provisioned'
                }
            }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'accepts RoleName as position 0, Justification as position 1, Hours as position 2' {
            Enable-OPIMDirectoryRole 'Reports Reader (elig-pos-001)' 'Incident response' 4
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Body.justification -eq 'Incident response' -and
                $Body.scheduleInfo.expiration.duration -eq 'PT4H'
            }
        }
    }

    Context 'When a DirectoryAssignmentScheduleInstance is piped from Get-OPIMDirectoryRole -All' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest { }
        }

        It 'skips the already-active instance and does not POST to the Graph API' {
            $AlreadyActive = [PSCustomObject]@{
                id               = 'active-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
            }
            $AlreadyActive.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')
            $AlreadyActive | Enable-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It
        }
    }

    Context 'When the display name matches the role at more than one scope' {
        # The real resolver runs; only the listing and the transport are mocked.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-DirectoryPost -Id 'elig-001' -DefinitionId 'role-def-001' -RoleName 'Usage Summary Reports Reader'
                New-DirectoryPost -Id 'elig-002' -DefinitionId 'role-def-001' -RoleName 'Usage Summary Reports Reader' -ScopeId '/administrativeUnits/au-001' -ScopeName 'Sales AU'
                New-DirectoryPost -Id 'elig-003' -DefinitionId 'role-def-003' -RoleName 'Message Center Privacy Reader'
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { $Listing }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'req-001'; action = 'SelfActivate'; status = 'Provisioned' }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'writes AmbiguousName and sends no activation' {
            $Errs = @()
            Enable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -ErrorVariable Errs -ErrorAction SilentlyContinue
            # The listing was read, so the resolver and the catch that writes its record were reached.
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Enable-OPIMDirectoryRole'
        }

        It 'tells the user that -Scope separates the candidates' {
            $Errs = @()
            Enable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].Exception.Message | Should -BeLike '*-Scope*'
        }

        It 'activates the one role that -Scope names' {
            Enable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -Scope '/administrativeUnits/au-001' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.directoryScopeId -eq '/administrativeUnits/au-001' -and $Body.roleDefinitionId -eq 'role-def-001'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }

        It 'activates the one role that the administrative unit display name names' {
            Enable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -Scope 'sales au' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.directoryScopeId -eq '/administrativeUnits/au-001'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }

        It 'activates the root role when -Scope is /' {
            Enable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -Scope '/' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.directoryScopeId -eq '/' -and $Body.roleDefinitionId -eq 'role-def-001'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes EligibleRoleNotFound when no role is at the -Scope given' {
            $Errs = @()
            Enable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -Scope '/administrativeUnits/au-999' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'EligibleRoleNotFound,Enable-OPIMDirectoryRole'
        }
    }

    Context 'When the display name is unique' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-DirectoryPost -Id 'elig-001' -DefinitionId 'role-def-001' -RoleName 'Usage Summary Reports Reader'
                New-DirectoryPost -Id 'elig-003' -DefinitionId 'role-def-003' -RoleName 'Message Center Privacy Reader'
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { $Listing }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'req-001'; action = 'SelfActivate'; status = 'Provisioned' }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'activates that role with its own ids' {
            Enable-OPIMDirectoryRole -RoleName 'message center privacy reader' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.roleDefinitionId -eq 'role-def-003' -and
                $Body.directoryScopeId -eq '/' -and $Body.principalId -eq 'principal-001'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When several names are given and one of them is unknown' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-DirectoryPost -Id 'elig-001' -DefinitionId 'role-def-001' -RoleName 'Usage Summary Reports Reader'
                New-DirectoryPost -Id 'elig-003' -DefinitionId 'role-def-003' -RoleName 'Message Center Privacy Reader'
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { $Listing }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'req-001'; action = 'SelfActivate'; status = 'Provisioned' }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'writes EligibleRoleNotFound for the unknown name and still activates the other (<Names>)' -ForEach @(
            @{ Names = 'unknown first'; List = @('Unknown Role', 'Message Center Privacy Reader') }
            @{ Names = 'unknown last'; List = @('Message Center Privacy Reader', 'Unknown Role') }
        ) {
            $Errs = @()
            Enable-OPIMDirectoryRole -RoleName $List -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'EligibleRoleNotFound,Enable-OPIMDirectoryRole'
            # -ErrorVariable also collects the record the resolver threw, so count the one the cmdlet wrote.
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'EligibleRoleNotFound,Enable-OPIMDirectoryRole' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.roleDefinitionId -eq 'role-def-003'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When -Identity matches more than one listed post' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-DirectoryPost -Id 'dup-001' -DefinitionId 'role-def-001' -RoleName 'Usage Summary Reports Reader'
                New-DirectoryPost -Id 'dup-001' -DefinitionId 'role-def-001' -RoleName 'Usage Summary Reports Reader' -ScopeId '/administrativeUnits/au-001' -ScopeName 'Sales AU'
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { $Listing }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'req-001'; action = 'SelfActivate'; status = 'Provisioned' }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'writes AmbiguousName, not IdentityNotFound, and sends no activation' {
            $Errs = @()
            Enable-OPIMDirectoryRole -Identity 'dup-001' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Enable-OPIMDirectoryRole'
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
            { Enable-OPIMDirectoryRole -Identity 'elig-001' -Scope '/' } | Should -Throw -ErrorId 'AmbiguousParameterSet*'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }

        It 'puts -Scope in the RoleName parameter set only' {
            # A piped object binds -Role in another set, so -Scope with it selects the RoleName set, whose
            # mandatory name is then missing. Read the sets from the command metadata instead of
            # binding: an interactive host would prompt for the name.
            (Get-Command Enable-OPIMDirectoryRole).Parameters['Scope'].ParameterSets.Keys | Should -Be 'RoleName'
        }

        It 'refuses a -Scope that ends with a slash' {
            { Enable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -Scope '/administrativeUnits/au-001/' } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }

        It 'refuses an empty -Scope' {
            { Enable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -Scope '' } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
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

        It 'writes the error as its own for each name and activates nothing' {
            $Out = Enable-OPIMDirectoryRole -RoleName 'Role A', 'Role B' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 2
            @($Written | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Enable-OPIMDirectoryRole' }).Count | Should -Be 2
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 2 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When Graph answers the request with a status' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Post = New-DirectoryPost -Id 'elig-001' -DefinitionId 'role-def-001' -RoleName 'Usage Summary Reports Reader'
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { $Post }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
            # The answer is read when the POST is made, so each test sets the status it wants.
            $Answer = @{ Status = 'Provisioned' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $Response = @{ id = 'req-001'; action = 'SelfActivate'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/'; principalId = 'principal-001' }
                if ($null -ne $Answer.Status) { $Response.status = $Answer.Status }
                $Response
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'returns the request and writes neither a warning nor an error for <Status>' -ForEach @(
            @{ Status = 'Provisioned' }
            @{ Status = 'Granted' }
            @{ Status = 'ScheduleCreated' }
            @{ Status = 'provisioned' }
        ) {
            $Answer.Status = $Status
            $Result = Enable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleRequest'
            $Result.status | Should -BeExactly $Status
            @($Warns).Count | Should -Be 0
            @($Errs).Count | Should -Be 0
        }

        It 'returns the request with one warning that names <Status>' -ForEach @(
            @{ Status = 'PendingApproval'; Message = 'Usage Summary Reports Reader: the activation request is PendingApproval. It waits for a decision and has not taken effect yet.' }
            @{ Status = 'PendingAdminDecision'; Message = 'Usage Summary Reports Reader: the activation request is PendingAdminDecision. It waits for a decision and has not taken effect yet.' }
            @{ Status = 'PendingProvisioning'; Message = 'Usage Summary Reports Reader: the activation request is PendingProvisioning and has not taken effect yet.' }
        ) {
            $Answer.Status = $Status
            $Result = Enable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.status | Should -BeExactly $Status
            @($Warns).Count | Should -Be 1
            "$($Warns[0])" | Should -BeExactly $Message
            @($Errs).Count | Should -Be 0
        }

        It 'writes ActivationRequestFailed and returns nothing for <Status>' -ForEach @(
            @{ Status = 'Failed' }
            @{ Status = 'Denied' }
            @{ Status = 'Canceled' }
            @{ Status = 'Revoked' }
            @{ Status = 'AdminDenied' }
            @{ Status = 'SomethingNew' }
        ) {
            $Answer.Status = $Status
            $Result = Enable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Enable-OPIMDirectoryRole'
            $Errs[-1].Exception.Message | Should -BeExactly "Usage Summary Reports Reader: the activation request ended with status '$Status' and did not take effect."
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'ActivationRequestFailed*' }).Count | Should -Be 1
            @($Warns).Count | Should -Be 0
        }

        It 'writes ActivationRequestFailed for an answer that carries no status' {
            $Answer.Status = $null
            $Result = Enable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' `
                -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Enable-OPIMDirectoryRole'
            $Errs[-1].Exception.Message | Should -BeLike '*ended with no status*'
        }
    }

    Context 'When the first of two requests comes back Failed' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $PostA = New-DirectoryPost -Id 'elig-001' -DefinitionId 'role-def-001' -RoleName 'Usage Summary Reports Reader'
            $PostB = New-DirectoryPost -Id 'elig-003' -DefinitionId 'role-def-003' -RoleName 'Message Center Privacy Reader'
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule {
                if ($Name -like 'Usage*') { $PostA } else { $PostB }
            }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $State = if ($Body.roleDefinitionId -eq 'role-def-001') { 'Failed' } else { 'Provisioned' }
                @{ id = "req-$($Body.roleDefinitionId)"; action = 'SelfActivate'; roleDefinitionId = $Body.roleDefinitionId; status = $State }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes one error and still requests and returns the second role' {
            $Result = Enable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader', 'Message Center Privacy Reader' `
                -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'ActivationRequestFailed,Enable-OPIMDirectoryRole' }).Count | Should -Be 1
            $Errs[-1].Exception.Message | Should -BeLike 'Usage Summary Reports Reader: *'
            @($Result).Count | Should -Be 1
            $Result.roleDefinitionId | Should -BeExactly 'role-def-003'
            $Result.status | Should -BeExactly 'Provisioned'
        }
    }

    Context 'When -Wait is given and the request comes back Failed' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Post = New-DirectoryPost -Id 'elig-001' -DefinitionId 'role-def-001' -RoleName 'Usage Summary Reports Reader'
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { $Post }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
            $Answer = @{ Status = 'Failed' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'req-001'; action = 'SelfActivate'; roleDefinitionId = 'role-def-001'; status = $Answer.Status }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Wait-OPIMDirectoryRole { }
        }

        It 'reports it as ActivationRequestFailed and never waits for it' {
            $Answer.Status = 'Failed'
            $Result = Enable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -Wait -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Wait-OPIMDirectoryRole -Times 0 -Exactly -Scope It
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'ActivationRequestFailed,Enable-OPIMDirectoryRole' }).Count | Should -Be 1
            @($Result).Count | Should -Be 0
        }

        It 'still hands a request that waits for a decision to Wait-OPIMDirectoryRole' {
            $Answer.Status = 'PendingApproval'
            $null = Enable-OPIMDirectoryRole -RoleName 'Usage Summary Reports Reader' -Wait -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Wait-OPIMDirectoryRole -Times 1 -Exactly -Scope It
            @($Errs).Count | Should -Be 0
        }
    }
}
