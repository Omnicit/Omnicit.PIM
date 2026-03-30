Describe 'Get-OPIMDirectoryRole' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When called with default parameters (eligible roles, root scope)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{
                    value = @(
                        @{
                            id               = 'elig-001'
                            roleDefinitionId = 'role-def-001'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'Global Administrator' }
                            principal        = @{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }
        }

        It 'calls Invoke-MgGraphRequest targeting roleEligibilitySchedules' {
            Get-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*roleEligibilitySchedules*'
            }
        }

        It 'calls Invoke-MgGraphRequest with filterByCurrentUser' {
            Get-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like "*filterByCurrentUser*"
            }
        }

        It 'returns one object' {
            $result = Get-OPIMDirectoryRole
            $result | Should -HaveCount 1
        }

        It 'returns an object tagged with Omnicit.PIM.DirectoryEligibilitySchedule' {
            $result = Get-OPIMDirectoryRole
            $result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryEligibilitySchedule'
        }

        It 'sets the directoryScope property to the root scope shortcut without a second API call' {
            $result = Get-OPIMDirectoryRole
            $result.directoryScope.id | Should -Be '/'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It
        }
    }

    Context 'When an item has a non-root directoryScopeId' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{
                    value = @(
                        @{
                            id               = 'elig-002'
                            roleDefinitionId = 'role-def-001'
                            directoryScopeId = '/administrativeUnits/au-001'
                            roleDefinition   = @{ displayName = 'User Administrator' }
                            principal        = @{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{ id = '/administrativeUnits/au-001'; displayName = 'Admin Unit 1' }
            } -ParameterFilter { $Uri -like '*directory/administrativeUnits*' }
        }

        It 'calls Invoke-MgGraphRequest a second time to rehydrate the directoryScope' {
            Get-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*directory/administrativeUnits*'
            }
        }

        It 'sets the directoryScope property from the second API response' {
            $result = Get-OPIMDirectoryRole
            $result.directoryScope.displayName | Should -Be 'Admin Unit 1'
        }
    }

    Context 'When -Activated is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{
                    value = @(
                        @{
                            id               = 'active-001'
                            assignmentType   = 'Activated'
                            roleDefinitionId = 'role-def-001'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'Global Administrator' }
                            principal        = @{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
        }

        It 'calls Invoke-MgGraphRequest targeting roleAssignmentScheduleInstances' {
            Get-OPIMDirectoryRole -Activated
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleInstances*'
            }
        }

        It 'returns an object tagged with Omnicit.PIM.DirectoryAssignmentScheduleInstance' {
            $result = Get-OPIMDirectoryRole -Activated
            $result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleInstance'
        }
    }

    Context 'When -Activated returns mixed assignment types' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{
                    value = @(
                        @{
                            id               = 'active-001'
                            assignmentType   = 'Activated'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'Global Administrator' }
                            principal        = @{ displayName = 'Jane Doe' }
                        },
                        @{
                            id               = 'inherited-001'
                            assignmentType   = 'Assigned'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'Reader' }
                            principal        = @{ displayName = 'Jane Doe' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
        }

        It 'filters out non-Activated items and returns only the Activated entry' {
            $result = Get-OPIMDirectoryRole -Activated
            $result | Should -HaveCount 1
            $result[0].assignmentType | Should -Be 'Activated'
        }
    }

    Context 'When -All is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' -and $Uri -notlike '*filterByCurrentUser*' }
        }

        It 'calls Invoke-MgGraphRequest without filterByCurrentUser' {
            Get-OPIMDirectoryRole -All
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*roleEligibilitySchedules*' -and $Uri -notlike '*filterByCurrentUser*'
            }
        }
    }

    Context 'When -Identity is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{
                    value = @(
                        @{
                            id               = 'elig-001'
                            roleDefinitionId = 'role-def-001'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'Global Administrator' }
                            principal        = @{ displayName = 'Jane Doe' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }
        }

        It 'appends an id eq filter to the request URI' {
            Get-OPIMDirectoryRole -Identity 'elig-001'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like "*id eq 'elig-001'*"
            }
        }
    }

    Context 'When -Filter is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }
        }

        It 'appends the OData filter string to the request URI' {
            Get-OPIMDirectoryRole -Filter "roleDefinitionId eq 'role-def-001'"
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like "*roleDefinitionId eq 'role-def-001'*"
            }
        }
    }

    Context 'When the result set is empty' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }
        }

        It 'returns nothing without throwing' {
            { Get-OPIMDirectoryRole } | Should -Not -Throw
        }

        It 'returns no objects' {
            $result = Get-OPIMDirectoryRole
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'When the Graph API returns an error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"InsufficientPermissions","message":"Access denied"}}'
                )
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Convert-GraphHttpException {
                $ex = [System.Exception]::new('Access denied')
                return [System.Management.Automation.ErrorRecord]::new(
                    $ex, 'InsufficientPermissions', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null
                )
            }
        }

        It 'throws a terminating error' {
            { Get-OPIMDirectoryRole } | Should -Throw
        }

        It 'passes the raw exception to Convert-GraphHttpException' {
            { Get-OPIMDirectoryRole } | Should -Throw
            Should -Invoke -ModuleName Omnicit.PIM Convert-GraphHttpException -Times 1 -Scope It
        }
    }
}
