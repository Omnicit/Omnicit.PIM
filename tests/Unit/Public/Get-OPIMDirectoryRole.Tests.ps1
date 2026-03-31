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
            $Result = Get-OPIMDirectoryRole
            $Result | Should -HaveCount 1
        }

        It 'returns an object tagged with Omnicit.PIM.DirectoryEligibilitySchedule' {
            $Result = Get-OPIMDirectoryRole
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryEligibilitySchedule'
        }

        It 'sets the directoryScope property to the root scope shortcut without a second API call' {
            $Result = Get-OPIMDirectoryRole
            $Result.directoryScope.id | Should -Be '/'
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
            $Result = Get-OPIMDirectoryRole
            $Result.directoryScope.displayName | Should -Be 'Admin Unit 1'
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
            $Result = Get-OPIMDirectoryRole -Activated
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleInstance'
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
            $Result = Get-OPIMDirectoryRole -Activated
            $Result | Should -HaveCount 1
            $Result[0].assignmentType | Should -Be 'Activated'
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
            $Result = Get-OPIMDirectoryRole
            $Result | Should -BeNullOrEmpty
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
                $Ex = [System.Exception]::new('Access denied')
                return [System.Management.Automation.ErrorRecord]::new(
                    $Ex, 'InsufficientPermissions', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null
                )
            }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Get-OPIMDirectoryRole -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'passes the raw exception to Convert-GraphHttpException' {
            $Errors = @()
            Get-OPIMDirectoryRole -ErrorVariable Errors -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Convert-GraphHttpException -Times 1 -Scope It
        }
    }
}
