Describe 'Disable-OPIMDirectoryRole' {
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
                id                       = 'instance-001'
                roleDefinitionId         = 'role-def-001'
                directoryScopeId         = '/'
                principalId              = 'principal-001'
                roleAssignmentScheduleId = 'schedule-001'
                roleDefinition           = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal                = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{
                    id              = 'deact-req-001'
                    action          = 'SelfDeactivate'
                    status          = 'Provisioned'
                    createdDateTime = '2024-01-01T12:00:00Z'
                }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'calls Resolve-RoleByName for the supplied role name' {
            Disable-OPIMDirectoryRole -RoleName 'Global Administrator (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-RoleByName -Times 1 -Scope It
        }

        It 'calls Invoke-MgGraphRequest with POST to the roleAssignmentScheduleRequests endpoint' {
            Disable-OPIMDirectoryRole -RoleName 'Global Administrator (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*roleAssignmentScheduleRequests*'
            }
        }

        It 'sends SelfDeactivate as the action in the request body' {
            Disable-OPIMDirectoryRole -RoleName 'Global Administrator (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.action -eq 'SelfDeactivate'
            }
        }

        It 'sends the roleAssignmentScheduleId as targetScheduleId in the request body' {
            Disable-OPIMDirectoryRole -RoleName 'Global Administrator (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
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
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{
                    id              = 'deact-req-002'
                    action          = 'SelfDeactivate'
                    status          = 'Provisioned'
                    createdDateTime = '2024-01-01T12:00:00Z'
                }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Restore-GraphProperty { }
        }

        It 'calls Invoke-MgGraphRequest with the roleDefinitionId and directoryScopeId from the piped role' {
            $FakeRole | Disable-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and
                $Body.roleDefinitionId -eq 'role-def-002' -and
                $Body.directoryScopeId -eq '/administrativeUnits/au-001'
            }
        }

        It 'calls Invoke-MgGraphRequest with the principalId from the piped role' {
            $FakeRole | Disable-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
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
            $FakeRole = [PSCustomObject]@{
                id                       = 'instance-001'
                roleDefinitionId         = 'role-def-001'
                directoryScopeId         = '/'
                principalId              = 'principal-001'
                roleAssignmentScheduleId = 'schedule-001'
                roleDefinition           = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal                = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest { } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not call Invoke-MgGraphRequest when -WhatIf is specified' {
            Disable-OPIMDirectoryRole -RoleName 'Global Administrator (instance-001)' -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 0 -Scope It
        }
    }

    Context 'When the Graph API returns a general error' {
        BeforeAll {
            $FakeRole = [PSCustomObject]@{
                id                       = 'instance-001'
                roleDefinitionId         = 'role-def-001'
                directoryScopeId         = '/'
                principalId              = 'principal-001'
                roleAssignmentScheduleId = 'schedule-001'
                roleDefinition           = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal                = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            $FakeRole = [PSCustomObject]@{
                id                       = 'instance-001'
                roleDefinitionId         = 'role-def-001'
                directoryScopeId         = '/'
                principalId              = 'principal-001'
                roleAssignmentScheduleId = 'schedule-001'
                roleDefinition           = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal                = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
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
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return $null }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMDirectoryRole -Identity 'nonexistent-999' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When a DirectoryEligibilitySchedule is piped from Get-OPIMDirectoryRole -All' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest { } -ParameterFilter { $Method -eq 'POST' }
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }
}
