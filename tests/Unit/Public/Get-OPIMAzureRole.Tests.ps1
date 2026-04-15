Describe 'Get-OPIMAzureRole' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When called with default parameters (eligible roles)' {
        BeforeAll {
            $FakeEligible = [PSCustomObject]@{
                Name                      = 'elig-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule { return $FakeEligible } -ParameterFilter { $Filter -eq 'asTarget()' }
        }

        It 'calls Get-AzRoleEligibilitySchedule with the asTarget() filter' {
            Get-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 1 -Scope It -ParameterFilter { $Filter -eq 'asTarget()' }
        }

        It 'returns objects tagged with Omnicit.PIM.AzureEligibilitySchedule' {
            $Result = Get-OPIMAzureRole
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureEligibilitySchedule'
        }
    }

    Context 'When -Activated is specified' {
        BeforeAll {
            $FakeActive = [PSCustomObject]@{
                Name                      = 'active-001'
                AssignmentType            = 'Activated'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance { return $FakeActive } -ParameterFilter { $Filter -eq 'asTarget()' }
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule { }
        }

        It 'calls Get-AzRoleAssignmentScheduleInstance with the asTarget() filter' {
            Get-OPIMAzureRole -Activated
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 1 -Scope It -ParameterFilter { $Filter -eq 'asTarget()' }
        }

        It 'does not call Get-AzRoleEligibilitySchedule' {
            Get-OPIMAzureRole -Activated
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 0 -Scope It
        }

        It 'returns objects tagged with Omnicit.PIM.AzureAssignmentScheduleInstance' {
            $Result = Get-OPIMAzureRole -Activated
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleInstance'
        }
    }

    Context 'When -Activated returns mixed assignment types' {
        BeforeAll {
            $FakeActive = [PSCustomObject]@{
                Name           = 'active-001'
                AssignmentType = 'Activated'
                PrincipalId    = 'principal-001'
            }
            $FakeInherited = [PSCustomObject]@{
                Name           = 'inherited-001'
                AssignmentType = 'Assigned'
                PrincipalId    = 'principal-001'
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance { return @($FakeInherited, $FakeActive) }
        }

        It 'filters out non-Activated assignment types and returns only Activated entries' {
            $Result = Get-OPIMAzureRole -Activated
            $Result | Should -HaveCount 1
            $Result[0].AssignmentType | Should -Be 'Activated'
        }
    }

    Context 'When -All is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule { return @() } -ParameterFilter { $Filter -eq 'asTarget()' }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance { return @() } -ParameterFilter { $Filter -eq 'asTarget()' }
        }

        It 'calls Get-AzRoleEligibilitySchedule with the asTarget() filter' {
            Get-OPIMAzureRole -All
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 1 -Scope It -ParameterFilter { $Filter -eq 'asTarget()' }
        }

        It 'calls Get-AzRoleAssignmentScheduleInstance with the asTarget() filter' {
            Get-OPIMAzureRole -All
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 1 -Scope It -ParameterFilter { $Filter -eq 'asTarget()' }
        }
    }

    Context 'When -All returns both eligible and active results' {
        BeforeAll {
            $FakeEligible = [PSCustomObject]@{
                Name                      = 'elig-001'
                RoleDefinitionDisplayName = 'Contributor'
                ScopeDisplayName          = 'My Subscription'
                ScopeId                   = '/subscriptions/sub-001'
                PrincipalId               = 'principal-001'
            }
            $FakeActive = [PSCustomObject]@{
                Name                      = 'active-001'
                AssignmentType            = 'Activated'
                RoleDefinitionDisplayName = 'Contributor'
                ScopeDisplayName          = 'My Subscription'
                ScopeId                   = '/subscriptions/sub-001'
                PrincipalId               = 'principal-001'
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule { return $FakeEligible } -ParameterFilter { $Filter -eq 'asTarget()' }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance { return $FakeActive } -ParameterFilter { $Filter -eq 'asTarget()' }
        }

        It 'tags all results with Omnicit.PIM.AzureCombinedSchedule' {
            $Result = Get-OPIMAzureRole -All
            $Result | ForEach-Object {
                $_.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureCombinedSchedule'
            }
        }

        It 'sets Status to Eligible on eligible items and Active on active items' {
            $Result = Get-OPIMAzureRole -All
            ($Result | Where-Object Status -EQ 'Eligible').Count | Should -Be 1
            ($Result | Where-Object Status -EQ 'Active').Count | Should -Be 1
        }
    }

    Context 'When -Identity is specified' {
        BeforeAll {
            $FakeEligible = [PSCustomObject]@{
                Name                      = 'elig-001'
                RoleDefinitionDisplayName = 'Contributor'
                ScopeId                   = '/subscriptions/sub-001'
                PrincipalId               = 'principal-001'
            }
            # Name and Filter are mutually exclusive parameter sets in Az.Resources cmdlets.
            # When -Name is specified, -Filter is NOT passed.
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {
                return $FakeEligible
            } -ParameterFilter { $Name -eq 'elig-001' }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance {
                return @()
            } -ParameterFilter { $Name -eq 'elig-001' }
        }

        It 'passes the Name to both eligible and active cmdlets (dual-search)' {
            Get-OPIMAzureRole -Identity 'elig-001'
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 1 -Scope It -ParameterFilter { $Name -eq 'elig-001' }
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 1 -Scope It -ParameterFilter { $Name -eq 'elig-001' }
        }

        It 'returns an object tagged with Omnicit.PIM.AzureCombinedSchedule' {
            $Result = Get-OPIMAzureRole -Identity 'elig-001'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureCombinedSchedule'
        }

        It 'returns an object with Status set to Eligible' {
            $Result = Get-OPIMAzureRole -Identity 'elig-001'
            $Result.Status | Should -Be 'Eligible'
        }
    }

    Context 'When -RoleName is specified' {
        BeforeAll {
            $FakeEligible = [PSCustomObject]@{
                Name                      = 'elig-001'
                RoleDefinitionDisplayName = 'Contributor'
                ScopeId                   = '/subscriptions/sub-001'
                PrincipalId               = 'principal-001'
            }
            # Name and Filter are mutually exclusive parameter sets in Az.Resources cmdlets.
            # When -Name is specified, -Filter is NOT passed.
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {
                return $FakeEligible
            } -ParameterFilter { $Name -eq 'elig-001' }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance {
                return @()
            } -ParameterFilter { $Name -eq 'elig-001' }
        }

        It 'extracts the schedule Name from trailing parentheses and performs dual-search' {
            Get-OPIMAzureRole -RoleName 'Contributor -> My Subscription (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 1 -Scope It -ParameterFilter { $Name -eq 'elig-001' }
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 1 -Scope It -ParameterFilter { $Name -eq 'elig-001' }
        }

        It 'returns an object tagged with Omnicit.PIM.AzureCombinedSchedule' {
            $Result = Get-OPIMAzureRole -RoleName 'Contributor -> My Subscription (elig-001)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureCombinedSchedule'
        }
    }

    Context 'When -All and -Activated are both specified' {
        It 'throws a parameter binding error because they are mutually exclusive' {
            { Get-OPIMAzureRole -All -Activated } | Should -Throw
        }
    }

    Context 'When -Activated -Scope filters to a specific scope' {
        BeforeAll {
            $FakeActiveOnScope = [PSCustomObject]@{
                Name           = 'active-sub-001'
                AssignmentType = 'Activated'
                ScopeId        = '/subscriptions/sub-001'
            }
            $FakeActiveOnParent = [PSCustomObject]@{
                Name           = 'active-parent-001'
                AssignmentType = 'Activated'
                ScopeId        = '/'
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance {
                return @($FakeActiveOnScope, $FakeActiveOnParent)
            } -ParameterFilter { $Filter -eq 'asTarget()' }
        }

        It 'returns only instances matching the exact scope' {
            $Result = Get-OPIMAzureRole -Activated -Scope '/subscriptions/sub-001'
            $Result | Should -HaveCount 1
            $Result[0].ScopeId | Should -Be '/subscriptions/sub-001'
        }
    }

    Context 'When -Scope is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule { return @() }
        }

        It 'passes the scope to Get-AzRoleEligibilitySchedule' {
            Get-OPIMAzureRole -Scope '/subscriptions/sub-001'
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 1 -Scope It -ParameterFilter {
                $Scope -eq '/subscriptions/sub-001'
            }
        }
    }

    Context 'When the result set is empty' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule { return @() }
        }

        It 'returns nothing without throwing' {
            { Get-OPIMAzureRole } | Should -Not -Throw
        }

        It 'returns no objects' {
            $Result = Get-OPIMAzureRole
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'When the API returns an InsufficientPermissions error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {
                Write-Error -Message 'Insufficient permissions' `
                    -ErrorId 'InsufficientPermissions' `
                    -Category PermissionDenied `
                    -ErrorAction Stop
            }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Get-OPIMAzureRole -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'includes guidance to use -All in the error message' {
            $Errors = @()
            Get-OPIMAzureRole -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].ErrorDetails.Message | Should -Match '\-All'
        }
    }

    Context 'When -All is specified and the API returns an InsufficientPermissions error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient permissions'),
                        'InsufficientPermissions',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied,
                        $null
                    )
                )
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance { return @() }
            Mock -ModuleName Omnicit.PIM Write-CmdletError { } -Verifiable
        }

        It 'writes a non-terminating error with Owner or UserAccessAdministrator guidance' {
            $Errors = @()
            Get-OPIMAzureRole -All -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When the API returns a non-permissions error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {
                Write-Error -Message 'Service unavailable' `
                    -ErrorId 'ServiceUnavailable' `
                    -Category ResourceUnavailable `
                    -ErrorAction Stop
            }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Get-OPIMAzureRole -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When scope is provided via pipeline' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule { return @() }
        }

        It 'calls Get-AzRoleEligibilitySchedule once per piped scope' {
            '/subscriptions/sub-001', '/subscriptions/sub-002' | Get-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 2 -Scope It
        }
    }
}
