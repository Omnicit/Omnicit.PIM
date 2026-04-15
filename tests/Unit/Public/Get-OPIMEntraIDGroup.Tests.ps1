Describe 'Get-OPIMEntraIDGroup' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When called with default parameters (eligible schedules)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{
                    value = @(
                        @{
                            id          = 'elig-001'
                            accessId    = 'member'
                            groupId     = 'group-001'
                            principalId = 'principal-001'
                            group       = @{ displayName = 'PIM Admins' }
                            principal   = @{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }
        }

        It 'calls Invoke-MgGraphRequest targeting eligibilitySchedules' {
            Get-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*eligibilitySchedules*'
            }
        }

        It 'calls Invoke-MgGraphRequest with filterByCurrentUser' {
            Get-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like "*filterByCurrentUser*"
            }
        }

        It 'returns one object' {
            $Result = Get-OPIMEntraIDGroup
            $Result | Should -HaveCount 1
        }

        It 'returns an object tagged with Omnicit.PIM.GroupEligibilitySchedule' {
            $Result = Get-OPIMEntraIDGroup
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupEligibilitySchedule'
        }
    }

    Context 'When -Activated is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{
                    value = @(
                        @{
                            id          = 'active-001'
                            accessId    = 'member'
                            groupId     = 'group-001'
                            principalId = 'principal-001'
                            group       = @{ displayName = 'PIM Admins' }
                            principal   = @{ displayName = 'Jane Doe' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*assignmentScheduleInstances*' }
        }

        It 'calls Invoke-MgGraphRequest targeting assignmentScheduleInstances' {
            Get-OPIMEntraIDGroup -Activated
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*assignmentScheduleInstances*'
            }
        }

        It 'returns an object tagged with Omnicit.PIM.GroupAssignmentScheduleInstance' {
            $Result = Get-OPIMEntraIDGroup -Activated
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleInstance'
        }

        It 'does not call eligibilitySchedules' {
            Get-OPIMEntraIDGroup -Activated
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 0 -Scope It -ParameterFilter {
                $Uri -like '*eligibilitySchedules*'
            }
        }
    }

    Context 'When -All is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*assignmentScheduleInstances*' }
        }

        It 'calls Invoke-MgGraphRequest for eligibilitySchedules with filterByCurrentUser' {
            Get-OPIMEntraIDGroup -All
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*eligibilitySchedules*' -and $Uri -like '*filterByCurrentUser*'
            }
        }

        It 'calls Invoke-MgGraphRequest for assignmentScheduleInstances with filterByCurrentUser' {
            Get-OPIMEntraIDGroup -All
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*assignmentScheduleInstances*' -and $Uri -like '*filterByCurrentUser*'
            }
        }
    }

    Context 'When -All and -Activated are both specified' {
        It 'throws a parameter binding error because they are mutually exclusive' {
            { Get-OPIMEntraIDGroup -All -Activated } | Should -Throw
        }
    }

    Context 'When -Identity is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }
        }

        It 'appends an id eq filter to the request URI' {
            Get-OPIMEntraIDGroup -Identity 'elig-001'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like "*id eq 'elig-001'*"
            }
        }
    }

    Context 'When -Filter is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }
        }

        It 'appends the OData filter string to the request URI' {
            Get-OPIMEntraIDGroup -Filter "groupId eq 'group-001'"
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like "*groupId eq 'group-001'*"
            }
        }
    }

    Context 'When -AccessType is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }
        }

        It 'appends an accessId eq filter for member' {
            Get-OPIMEntraIDGroup -AccessType member
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like "*accessId eq 'member'*"
            }
        }

        It 'appends an accessId eq filter for owner' {
            Get-OPIMEntraIDGroup -AccessType owner
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like "*accessId eq 'owner'*"
            }
        }
    }

    Context 'When -Identity, -AccessType, and -Filter are all specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }
        }

        It 'combines all filter parts with and in the request URI' {
            Get-OPIMEntraIDGroup -Identity 'elig-001' -AccessType member -Filter "principalId eq 'principal-001'"
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like "*id eq 'elig-001'*" -and
                $Uri -like "*accessId eq 'member'*" -and
                $Uri -like "*principalId eq 'principal-001'*"
            }
        }
    }

    Context 'When the result set is empty' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }
        }

        It 'returns nothing without throwing' {
            { Get-OPIMEntraIDGroup } | Should -Not -Throw
        }

        It 'returns no objects' {
            $Result = Get-OPIMEntraIDGroup
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'When the Graph API returns an error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"InsufficientPermissions","message":"Access denied"}}'
                )
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Convert-GraphHttpException {
                $Ex = [System.Exception]::new('Access denied')
                return [System.Management.Automation.ErrorRecord]::new(
                    $Ex, 'InsufficientPermissions', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null
                )
            }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Get-OPIMEntraIDGroup -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'passes the raw exception to Convert-GraphHttpException' {
            $Errors = @()
            Get-OPIMEntraIDGroup -ErrorVariable Errors -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Convert-GraphHttpException -Times 1 -Scope It
        }
    }
}
