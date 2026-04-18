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
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
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

        It 'calls Invoke-OPIMGraphRequest with POST to the group assignmentScheduleRequests endpoint' {
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*privilegedAccess/group/assignmentScheduleRequests*'
            }
        }

        It 'sends selfDeactivate as the action in the request body' {
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.action -eq 'selfDeactivate'
            }
        }

        It 'sends the accessId from the resolved group in the request body' {
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
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
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-002'
                accessId    = 'owner'
                groupId     = 'group-002'
                principalId = 'principal-002'
                group       = [PSCustomObject]@{ displayName = 'DevOps Team' }
            }
            $FakeGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleInstance')
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
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

        It 'calls Invoke-OPIMGraphRequest with the groupId and principalId from the piped group' {
            $FakeGroup | Disable-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and
                $Body.groupId -eq 'group-002' -and
                $Body.principalId -eq 'principal-002'
            }
        }

        It 'calls Invoke-OPIMGraphRequest with the accessId from the piped group' {
            $FakeGroup | Disable-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
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
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest { } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not call Invoke-OPIMGraphRequest when -WhatIf is specified' {
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)' -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It
        }
    }

    Context 'When the Graph API returns a general error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
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
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
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

    Context 'When the API response does not include a group property' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-004'
                accessId    = 'member'
                groupId     = 'group-004'
                principalId = 'principal-004'
                group       = [PSCustomObject]@{ displayName = 'Engineering Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id          = 'deact-req-004'
                    action      = 'selfDeactivate'
                    accessId    = 'member'
                    groupId     = 'group-004'
                    principalId = 'principal-004'
                    status      = 'Provisioned'
                    # 'group' key intentionally omitted to exercise the restore branch
                }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'restores the group property from the resolved schedule object' {
            $Result = Disable-OPIMEntraIDGroup -GroupName 'Engineering Team (instance-004)'
            $Result.group.displayName | Should -Be 'Engineering Team'
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.GroupAssignmentScheduleRequest' {
            $Result = Disable-OPIMEntraIDGroup -GroupName 'Engineering Team (instance-004)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
        }
    }

    Context 'When -Identity is specified and the group is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeActive = [PSCustomObject]@{
                id          = 'instance-005'
                accessId    = 'member'
                groupId     = 'group-002'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Security Team' }
            }
            $FakeActive.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleInstance')
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return $FakeActive }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id          = 'deact-req-005'
                    action      = 'selfDeactivate'
                    accessId    = 'member'
                    groupId     = 'group-002'
                    principalId = 'principal-001'
                    status      = 'Provisioned'
                    group       = @{ displayName = 'Security Team' }
                }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'looks up the group via Get-OPIMEntraIDGroup -Activated -Identity' {
            Disable-OPIMEntraIDGroup -Identity 'instance-005'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 1 -Scope It
        }

        It 'submits the selfDeactivate request' {
            Disable-OPIMEntraIDGroup -Identity 'instance-005'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.GroupAssignmentScheduleRequest' {
            $Result = Disable-OPIMEntraIDGroup -Identity 'instance-005'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
        }
    }

    Context 'When -Identity is specified but no active group is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return $null }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMEntraIDGroup -Identity 'nonexistent-999' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When a GroupEligibilitySchedule is piped from Get-OPIMEntraIDGroup -All' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest { } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'skips the eligible-only schedule and does not POST to the Graph API' {
            $EligibleOnly = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = @{ displayName = 'PIM Admins' }
            }
            $EligibleOnly.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
            $EligibleOnly | Disable-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }
}
