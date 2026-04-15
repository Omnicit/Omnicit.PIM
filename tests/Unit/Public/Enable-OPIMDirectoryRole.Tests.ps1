Describe 'Enable-OPIMDirectoryRole' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When called with -RoleName (happy path)' {
        BeforeAll {
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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

        It 'calls Resolve-RoleByName for the supplied role name' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-RoleByName -Times 1 -Scope It
        }

        It 'calls Invoke-MgGraphRequest with POST to the roleAssignmentScheduleRequests endpoint' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*roleAssignmentScheduleRequests*'
            }
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.DirectoryAssignmentScheduleRequest' {
            $Result = Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleRequest'
        }

        It 'sends SelfActivate as the action in the request body' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.action -eq 'SelfActivate'
            }
        }

        It 'uses AfterDuration expiration type by default' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.type -eq 'AfterDuration'
            }
        }

        It 'passes a PT1H ISO 8601 duration when -Hours defaults to 1' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.duration -eq 'PT1H'
            }
        }
    }

    Context 'When called with multiple role names' {
        BeforeAll {
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
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName {
                if ($RoleName -like '*elig-001*') { return $fakeRoleA } else { return $fakeRoleB }
            }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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

        It 'calls Invoke-MgGraphRequest once per role name supplied' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)', 'User Administrator (elig-002)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 2 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When called with pipeline input (-Role parameter set)' {
        BeforeAll {
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-002'
                roleDefinitionId = 'role-def-002'
                directoryScopeId = '/administrativeUnits/au-001'
                principalId      = 'principal-002'
                roleDefinition   = [PSCustomObject]@{ displayName = 'User Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'John Smith'; userPrincipalName = 'john@contoso.com' }
            }
            $fakeRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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

        It 'calls Invoke-MgGraphRequest with the roleDefinitionId and directoryScopeId from the piped role' {
            $fakeRole | Enable-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and
                $Body.roleDefinitionId -eq 'role-def-002' -and
                $Body.directoryScopeId -eq '/administrativeUnits/au-001'
            }
        }

        It 'calls Invoke-MgGraphRequest with the principalId from the piped role' {
            $fakeRole | Enable-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
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
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            $script:UntilDateTime = [DateTime]::Now.AddHours(3)
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.type -eq 'AfterDateTime'
            }
        }

        It 'does not include a duration in the request body when -Until is specified' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -Until $script:UntilDateTime
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and -not $Body.scheduleInfo.expiration.duration
            }
        }
    }

    Context 'When -Hours overrides the default duration' {
        BeforeAll {
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.duration -eq 'PT4H'
            }
        }

        It 'passes PT8H ISO 8601 duration when -Hours 8 is specified' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -Hours 8
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.duration -eq 'PT8H'
            }
        }
    }

    Context 'When ticket information is provided' {
        BeforeAll {
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and
                $Body.ticketInfo.ticketNumber -eq 'INC-123' -and
                $Body.ticketInfo.ticketSystem -eq 'ServiceNow'
            }
        }
    }

    Context 'When -Justification is provided' {
        BeforeAll {
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.justification -eq 'Deploying hotfix'
            }
        }
    }

    Context 'When -WhatIf is specified' {
        BeforeAll {
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest { } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not call Invoke-MgGraphRequest when -WhatIf is specified' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 0 -Scope It
        }
    }

    Context 'When the Graph API returns a general error' {
        BeforeAll {
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            $fakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            $FakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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

    Context 'When the API returns RoleAssignmentRequestAcrsValidationFailed' {
        BeforeAll {
            $FakeRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-GraphWithAcrsRetry {
                return @{
                    _AcrsError   = $true
                    _ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('RoleAssignmentRequestAcrsValidationFailed: ACRS validation failed'),
                        'RoleAssignmentRequestAcrsValidationFailed',
                        [System.Management.Automation.ErrorCategory]::OperationStopped,
                        $null
                    )
                    _AllMsgs     = 'RoleAssignmentRequestAcrsValidationFailed ACRS validation failed'
                    _NoMsal      = $true
                }
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

        It 'sets the FullyQualifiedErrorId to RoleAssignmentRequestAcrsValidationFailed' {
            $Errors = @()
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].FullyQualifiedErrorId | Should -BeLike '*RoleAssignmentRequestAcrsValidationFailed*'
        }

        It 'includes a hint to run Connect-MgGraph in the error message' {
            $Errors = @()
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].Exception.Message | Should -BeLike '*Connect-MgGraph*'
        }

        It 'calls Invoke-GraphWithAcrsRetry once only (no double retry)' {
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-GraphWithAcrsRetry -Times 1 -Scope It
        }

        It 'does not call Disconnect-MgGraph' {
            Mock -ModuleName Omnicit.PIM Disconnect-MgGraph { }
            Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Disconnect-MgGraph -Times 0 -Scope It
        }
    }

    Context 'When -Identity is specified and the role is found' {
        BeforeAll {
            $FakeElig = [PSCustomObject]@{
                id               = 'elig-010'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Reports Reader' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return $FakeElig }
            Mock -ModuleName Omnicit.PIM Invoke-GraphWithAcrsRetry {
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-GraphWithAcrsRetry -Times 1 -Scope It
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.DirectoryAssignmentScheduleRequest' {
            $Result = Enable-OPIMDirectoryRole -Identity 'elig-010'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleRequest'
        }
    }

    Context 'When -Identity is specified but no eligible role is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return $null }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMDirectoryRole -Identity 'nonexistent-999' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When positional parameters are used' {
        BeforeAll {
            $FakeElig = [PSCustomObject]@{
                id               = 'elig-pos-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                principalId      = 'principal-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Reports Reader' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeElig }
            Mock -ModuleName Omnicit.PIM Invoke-GraphWithAcrsRetry {
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-GraphWithAcrsRetry -Times 1 -Scope It -ParameterFilter {
                $Body.justification -eq 'Incident response' -and
                $Body.scheduleInfo.expiration.duration -eq 'PT4H'
            }
        }
    }

    Context 'When a DirectoryAssignmentScheduleInstance is piped from Get-OPIMDirectoryRole -All' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-GraphWithAcrsRetry { }
        }

        It 'skips the already-active instance and does not POST to the Graph API' {
            $AlreadyActive = [PSCustomObject]@{
                id               = 'active-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
            }
            $AlreadyActive.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')
            $AlreadyActive | Enable-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-GraphWithAcrsRetry -Times 0 -Scope It
        }
    }
}
