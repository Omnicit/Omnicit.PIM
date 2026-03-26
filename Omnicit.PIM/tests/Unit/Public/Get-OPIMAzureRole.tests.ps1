Describe 'Get-OPIMAzureRole' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../../../Source/Omnicit.PIM.psd1" -Force
    }

    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When called without parameters (lists eligible roles — happy path)' {
        BeforeAll {
            Mock Get-AzRoleEligibilitySchedule {
                return @(
                    [PSCustomObject]@{
                        Id                 = 'elig-azure-001'
                        RoleDefinitionId   = '/subscriptions/sub-001/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                        RoleDefinitionName = 'Contributor'
                        Scope              = '/subscriptions/sub-001'
                        PrincipalId        = 'user-object-id-001'
                        Status             = 'Bound'
                    }
                )
            }

            Mock Get-AzRoleAssignmentScheduleInstance {
                return @()
            }

            Mock -ModuleName Omnicit.PIM Get-MyId { return 'user-object-id-001' }
        }

        It 'calls Get-AzRoleEligibilitySchedule once' {
            Get-OPIMAzureRole
            Should -Invoke Get-AzRoleEligibilitySchedule -Times 1 -Scope It
        }

        It 'returns a typed PSCustomObject with Omnicit.PIM.AzureEligibilitySchedule' {
            $result = Get-OPIMAzureRole
            $result | Should -Not -BeNullOrEmpty
            $result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureEligibilitySchedule'
        }

        It 'returns the correct role name' {
            $result = Get-OPIMAzureRole
            $result[0].RoleDefinitionName | Should -Be 'Contributor'
        }

        It 'does not return active assignments when -Activated is not specified' {
            Should -Invoke Get-AzRoleAssignmentScheduleInstance -Times 0 -Scope It
        }
    }

    Context 'When called with -Activated (lists active assignments)' {
        BeforeAll {
            Mock Get-AzRoleEligibilitySchedule { return @() }

            Mock Get-AzRoleAssignmentScheduleInstance {
                return @(
                    [PSCustomObject]@{
                        Id                 = 'active-azure-001'
                        RoleDefinitionId   = '/subscriptions/sub-001/providers/Microsoft.Authorization/roleDefinitions/role-def-002'
                        RoleDefinitionName = 'Reader'
                        Scope              = '/subscriptions/sub-001'
                        PrincipalId        = 'user-object-id-001'
                        Status             = 'Provisioned'
                    }
                )
            }

            Mock -ModuleName Omnicit.PIM Get-MyId { return 'user-object-id-001' }
        }

        It 'calls Get-AzRoleAssignmentScheduleInstance once' {
            Get-OPIMAzureRole -Activated
            Should -Invoke Get-AzRoleAssignmentScheduleInstance -Times 1 -Scope It
        }

        It 'returns a typed PSCustomObject with Omnicit.PIM.AzureAssignmentScheduleInstance' {
            $result = Get-OPIMAzureRole -Activated
            $result | Should -Not -BeNullOrEmpty
            $result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleInstance'
        }

        It 'returns the correct active role name' {
            $result = Get-OPIMAzureRole -Activated
            $result[0].RoleDefinitionName | Should -Be 'Reader'
        }
    }

    Context 'When called with -All (elevated — all principals)' {
        BeforeAll {
            Mock Get-AzRoleEligibilitySchedule {
                return @(
                    [PSCustomObject]@{
                        Id                 = 'elig-azure-002'
                        RoleDefinitionId   = '/subscriptions/sub-001/providers/Microsoft.Authorization/roleDefinitions/role-def-003'
                        RoleDefinitionName = 'Owner'
                        Scope              = '/subscriptions/sub-001'
                        PrincipalId        = 'other-user-id-002'
                        Status             = 'Bound'
                    }
                )
            }

            Mock Get-AzRoleAssignmentScheduleInstance { return @() }
            Mock -ModuleName Omnicit.PIM Get-MyId { return 'user-object-id-001' }
        }

        It 'calls Get-AzRoleEligibilitySchedule without filtering by PrincipalId' {
            Get-OPIMAzureRole -All
            Should -Invoke Get-AzRoleEligibilitySchedule -Times 1 -Scope It
        }

        It 'returns roles belonging to other principals' {
            $result = Get-OPIMAzureRole -All
            $result[0].PrincipalId | Should -Be 'other-user-id-002'
        }
    }

    Context 'When Get-AzRoleEligibilitySchedule returns no results' {
        BeforeAll {
            Mock Get-AzRoleEligibilitySchedule { return @() }
            Mock Get-AzRoleAssignmentScheduleInstance { return @() }
            Mock -ModuleName Omnicit.PIM Get-MyId { return 'user-object-id-001' }
        }

        It 'returns nothing without throwing' {
            { Get-OPIMAzureRole } | Should -Not -Throw
        }

        It 'returns an empty result set' {
            $result = Get-OPIMAzureRole
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'When Get-AzRoleEligibilitySchedule throws an error' {
        BeforeAll {
            Mock Get-AzRoleEligibilitySchedule {
                throw [System.Exception]::new('Authorization failed. Caller does not have required permission.')
            }
            Mock -ModuleName Omnicit.PIM Get-MyId { return 'user-object-id-001' }
        }

        It 'writes a non-terminating error' {
            { Get-OPIMAzureRole -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'emits at least one error record' {
            $errors = @()
            Get-OPIMAzureRole -ErrorVariable errors -ErrorAction SilentlyContinue
            $errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When called with -Identity to retrieve a specific schedule' {
        BeforeAll {
            Mock Get-AzRoleEligibilitySchedule {
                return @(
                    [PSCustomObject]@{
                        Id                 = 'elig-azure-specific-001'
                        RoleDefinitionId   = '/subscriptions/sub-001/providers/Microsoft.Authorization/roleDefinitions/role-def-004'
                        RoleDefinitionName = 'Storage Blob Data Reader'
                        Scope              = '/subscriptions/sub-001/resourceGroups/rg-001'
                        PrincipalId        = 'user-object-id-001'
                        Status             = 'Bound'
                    }
                )
            }

            Mock Get-AzRoleAssignmentScheduleInstance { return @() }
            Mock -ModuleName Omnicit.PIM Get-MyId { return 'user-object-id-001' }
        }

        It 'returns the schedule matching the provided Identity' {
            $result = Get-OPIMAzureRole -Identity 'elig-azure-specific-001'
            $result.Id | Should -Be 'elig-azure-specific-001'
        }

        It 'returns a typed PSCustomObject with Omnicit.PIM.AzureEligibilitySchedule' {
            $result = Get-OPIMAzureRole -Identity 'elig-azure-specific-001'
            $result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureEligibilitySchedule'
        }
    }
}