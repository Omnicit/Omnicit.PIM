Describe 'Disable-OPIMEntraIDGroup' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When called with -GroupName (happy path)' {
        BeforeAll {
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{
                    id          = 'deact-req-001'
                    action      = 'selfDeactivate'
                    accessId    = 'member'
                    groupId     = 'group-001'
                    principalId = 'principal-001'
                    status      = 'Provisioned'
                    group       = @{ displayName = 'Finance Team' }
                }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'calls Resolve-RoleByName for the supplied group name' {
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-RoleByName -Times 1 -Scope It
        }

        It 'calls Invoke-MgGraphRequest with POST to the group assignmentScheduleRequests endpoint' {
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*privilegedAccess/group/assignmentScheduleRequests*'
            }
        }

        It 'sends selfDeactivate as the action in the request body' {
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.action -eq 'selfDeactivate'
            }
        }

        It 'sends the accessId from the resolved group in the request body' {
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.accessId -eq 'member'
            }
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.GroupAssignmentScheduleRequest' {
            $Result = Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
        }
    }

    Context 'When called with pipeline input (-Group parameter set)' {
        BeforeAll {
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-002'
                accessId    = 'owner'
                groupId     = 'group-002'
                principalId = 'principal-002'
                group       = [PSCustomObject]@{ displayName = 'DevOps Team' }
            }
            $FakeGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleInstance')
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{
                    id          = 'deact-req-002'
                    action      = 'selfDeactivate'
                    accessId    = 'owner'
                    groupId     = 'group-002'
                    principalId = 'principal-002'
                    status      = 'Provisioned'
                    group       = @{ displayName = 'DevOps Team' }
                }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'calls Invoke-MgGraphRequest with the groupId and principalId from the piped group' {
            $FakeGroup | Disable-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and
                $Body.groupId -eq 'group-002' -and
                $Body.principalId -eq 'principal-002'
            }
        }

        It 'calls Invoke-MgGraphRequest with the accessId from the piped group' {
            $FakeGroup | Disable-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.accessId -eq 'owner'
            }
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.GroupAssignmentScheduleRequest' {
            $Result = $FakeGroup | Disable-OPIMEntraIDGroup
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
        }
    }

    Context 'When -WhatIf is specified' {
        BeforeAll {
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest { } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not call Invoke-MgGraphRequest when -WhatIf is specified' {
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)' -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 0 -Scope It
        }
    }

    Context 'When the Graph API returns a general error' {
        BeforeAll {
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"GeneralError","message":"An unexpected error occurred."}}'
                )
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not throw a terminating error' {
            { Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When the API returns an ActiveDurationTooShort error' {
        BeforeAll {
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"ActiveDurationTooShort","message":"Group was not activated long enough to meet the minimum wait period."}}'
                )
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'includes the 5-minute cooldown message in the error details' {
            $Errors = @()
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].Exception.Message | Should -Match '5 minutes'
        }
    }
}
