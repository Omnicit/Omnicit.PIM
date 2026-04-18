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
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
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

        It 'calls Invoke-OPIMGraphRequest targeting roleEligibilitySchedules' {
            Get-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*roleEligibilitySchedules*'
            }
        }

        It 'calls Invoke-OPIMGraphRequest with filterByCurrentUser' {
            Get-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It
        }
    }

    Context 'When an item has a non-root directoryScopeId' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
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

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ id = '/administrativeUnits/au-001'; displayName = 'Admin Unit 1' }
            } -ParameterFilter { $Uri -like '*directory/administrativeUnits*' }
        }

        It 'calls Invoke-OPIMGraphRequest a second time to rehydrate the directoryScope' {
            Get-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
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
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
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

        It 'calls Invoke-OPIMGraphRequest targeting roleAssignmentScheduleInstances' {
            Get-OPIMDirectoryRole -Activated
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
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
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
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

        It 'returns all items from roleAssignmentScheduleInstances without post-filtering by assignmentType' {
            $Result = Get-OPIMDirectoryRole -Activated
            $Result | Should -HaveCount 2
        }
    }

    Context 'When -All is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
        }

        It 'calls Invoke-OPIMGraphRequest for roleEligibilitySchedules with filterByCurrentUser' {
            Get-OPIMDirectoryRole -All
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*roleEligibilitySchedules*' -and $Uri -like '*filterByCurrentUser*'
            }
        }

        It 'calls Invoke-OPIMGraphRequest for roleAssignmentScheduleInstances with filterByCurrentUser' {
            Get-OPIMDirectoryRole -All
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleInstances*' -and $Uri -like '*filterByCurrentUser*'
            }
        }
    }

    Context 'When -All and -Activated are both specified' {
        It 'throws a parameter binding error because they are mutually exclusive' {
            { Get-OPIMDirectoryRole -All -Activated } | Should -Throw
        }
    }

    Context 'When -Identity is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
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

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
        }

        It 'queries both eligible and active endpoints with the id filter (dual-search)' {
            Get-OPIMDirectoryRole -Identity 'elig-001'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Scope It -ParameterFilter {
                $Uri -like "*id eq 'elig-001'*"
            }
        }

        It 'returns an object tagged with Omnicit.PIM.DirectoryCombinedSchedule' {
            $Result = Get-OPIMDirectoryRole -Identity 'elig-001'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryCombinedSchedule'
        }

        It 'returns an object with Status set to Eligible for eligible items' {
            $Result = Get-OPIMDirectoryRole -Identity 'elig-001'
            $Result.Status | Should -Be 'Eligible'
        }
    }

    Context 'When -Filter is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
        }

        It 'queries both eligible and active endpoints with the OData filter (dual-search)' {
            Get-OPIMDirectoryRole -Filter "roleDefinitionId eq 'role-def-001'"
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Scope It -ParameterFilter {
                $Uri -like "*roleDefinitionId eq 'role-def-001'*"
            }
        }
    }

    Context 'When the result set is empty' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
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
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
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
    }

    Context 'When -All returns both eligible and active results' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
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

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    value = @(
                        @{
                            id               = 'active-001'
                            roleDefinitionId = 'role-def-001'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'Global Administrator' }
                            principal        = @{ displayName = 'Jane Doe' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
        }

        It 'tags all results with Omnicit.PIM.DirectoryCombinedSchedule' {
            $Result = Get-OPIMDirectoryRole -All
            $Result | ForEach-Object {
                $_.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryCombinedSchedule'
            }
        }

        It 'sets Status to Eligible on eligible items and Active on active items' {
            $Result = Get-OPIMDirectoryRole -All
            ($Result | Where-Object Status -EQ 'Eligible').Count | Should -Be 1
            ($Result | Where-Object Status -EQ 'Active').Count | Should -Be 1
        }

        It 'retains the original TypeName for pipeline binding on eligible items' {
            $Result = Get-OPIMDirectoryRole -All
            ($Result | Where-Object Status -EQ 'Eligible').PSObject.TypeNames |
                Should -Contain 'Omnicit.PIM.DirectoryEligibilitySchedule'
        }

        It 'retains the original TypeName for pipeline binding on active items' {
            $Result = Get-OPIMDirectoryRole -All
            ($Result | Where-Object Status -EQ 'Active').PSObject.TypeNames |
                Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleInstance'
        }
    }

    Context 'When -RoleName is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
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

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
        }

        It 'extracts the schedule ID from trailing parentheses and performs dual-search' {
            Get-OPIMDirectoryRole -RoleName 'Global Administrator -> Directory (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Scope It -ParameterFilter {
                $Uri -like "*id eq 'elig-001'*"
            }
        }

        It 'returns an object tagged with Omnicit.PIM.DirectoryCombinedSchedule' {
            $Result = Get-OPIMDirectoryRole -RoleName 'Global Administrator -> Directory (elig-001)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryCombinedSchedule'
        }
    }
}
