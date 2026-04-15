Describe 'Disable-OPIMAzureRole' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When called with -RoleName (happy path)' {
        BeforeAll {
            $FakeRole = [PSCustomObject]@{
                Name                      = 'active-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                return [PSCustomObject]@{
                    Name        = [System.Guid]::NewGuid().ToString()
                    Scope       = '/subscriptions/sub-001'
                    RequestType = 'SelfDeactivate'
                }
            }
        }

        It 'calls Resolve-RoleByName for the supplied role name' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-RoleByName -Times 1 -Scope It
        }

        It 'calls New-AzRoleAssignmentScheduleRequest with SelfDeactivate RequestType' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $RequestType -eq 'SelfDeactivate'
            }
        }

        It 'calls New-AzRoleAssignmentScheduleRequest with the role scope' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $Scope -eq '/subscriptions/sub-001'
            }
        }

        It 'uses the active assignment Name as LinkedRoleEligibilityScheduleId' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $LinkedRoleEligibilityScheduleId -eq 'active-001'
            }
        }

        It 'tags the response with Omnicit.PIM.AzureAssignmentScheduleRequest type name' {
            $Result = Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleRequest'
        }
    }

    Context 'When called with pipeline input (-Role parameter set)' {
        BeforeAll {
            $FakeRole = [PSCustomObject]@{
                Name                      = 'active-002'
                ScopeId                   = '/subscriptions/sub-002'
                ScopeDisplayName          = 'Dev Subscription'
                PrincipalId               = 'principal-002'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-002'
                RoleDefinitionDisplayName = 'Owner'
            }
            $FakeRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                return [PSCustomObject]@{
                    Name        = [System.Guid]::NewGuid().ToString()
                    Scope       = '/subscriptions/sub-002'
                    RequestType = 'SelfDeactivate'
                }
            }
        }

        It 'calls New-AzRoleAssignmentScheduleRequest with the piped role scope and principal' {
            $FakeRole | Disable-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $Scope -eq '/subscriptions/sub-002' -and $PrincipalId -eq 'principal-002'
            }
        }

        It 'uses the piped role Name as LinkedRoleEligibilityScheduleId' {
            $FakeRole | Disable-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $LinkedRoleEligibilityScheduleId -eq 'active-002'
            }
        }
    }

    Context 'When -WhatIf is specified' {
        BeforeAll {
            $FakeRole = [PSCustomObject]@{
                Name                      = 'active-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest { }
        }

        It 'does not call New-AzRoleAssignmentScheduleRequest when -WhatIf is specified' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
        }
    }

    Context 'When the API returns a general error' {
        BeforeAll {
            $FakeRole = [PSCustomObject]@{
                Name                      = 'active-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Unexpected API error'),
                        'UnexpectedApiError',
                        [System.Management.Automation.ErrorCategory]::InvalidOperation,
                        $null
                    )
                )
            }
        }

        It 'does not throw a terminating error' {
            { Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When the API returns an ActiveDurationTooShort error' {
        BeforeAll {
            $FakeRole = [PSCustomObject]@{
                Name                      = 'active-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                throw [System.Exception]::new('ActiveDurationTooShort: Role was not activated long enough.')
            }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'includes the 5-minute cooldown message in the error details' {
            $Errors = @()
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].Exception.Message | Should -Match '5 minutes'
        }
    }

    Context 'When -Identity is specified and the role is found' {
        BeforeAll {
            $FakeActive = [PSCustomObject]@{
                Name                      = 'active-002'
                AssignmentType            = 'Activated'
                ScopeId                   = '/subscriptions/sub-002'
                ScopeDisplayName          = 'Dev Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-002'
                RoleDefinitionDisplayName = 'Reader'
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return $FakeActive }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                return [PSCustomObject]@{
                    Name        = [System.Guid]::NewGuid().ToString()
                    Scope       = '/subscriptions/sub-002'
                    RequestType = 'SelfDeactivate'
                }
            }
        }

        It 'looks up the role via Get-OPIMAzureRole -Activated and filters by Name' {
            Disable-OPIMAzureRole -Identity 'active-002'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Scope It
        }

        It 'submits the SelfDeactivate request via New-AzRoleAssignmentScheduleRequest' {
            Disable-OPIMAzureRole -Identity 'active-002'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It
        }
    }

    Context 'When -Identity is specified but no active role is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return $null }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMAzureRole -Identity 'nonexistent-999' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }
}
