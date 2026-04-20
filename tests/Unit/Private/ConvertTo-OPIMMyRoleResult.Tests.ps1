Describe 'ConvertTo-OPIMMyRoleResult' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When a DirectoryAssignmentScheduleRequest is piped in' {
        It 'returns an object tagged with Omnicit.PIM.MyRoleResult' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{
                    action           = 'SelfActivate'
                    status           = 'PendingProvisioning'
                    roleDefinitionId = 'role-def-001'
                    directoryScopeId = '/'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                    directoryScope   = $null
                    EndDateTime      = [datetime]'2026-04-20T15:00:00Z'
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')

                $Result = $FakeInput | ConvertTo-OPIMMyRoleResult

                $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.MyRoleResult'
            }
        }

        It 'maps Category to DirectoryRole' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{
                    action           = 'SelfActivate'
                    status           = 'PendingProvisioning'
                    roleDefinitionId = 'role-def-001'
                    directoryScopeId = '/'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                    directoryScope   = $null
                    EndDateTime      = $null
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')

                $Result = $FakeInput | ConvertTo-OPIMMyRoleResult

                $Result.Category | Should -Be 'DirectoryRole'
            }
        }

        It 'maps Scope to "Directory" when directoryScopeId is "/"' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{
                    action           = 'SelfActivate'
                    status           = 'PendingProvisioning'
                    roleDefinitionId = 'role-def-001'
                    directoryScopeId = '/'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                    directoryScope   = $null
                    EndDateTime      = $null
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')

                $Result = $FakeInput | ConvertTo-OPIMMyRoleResult

                $Result.Scope | Should -Be 'Directory'
            }
        }
    }

    Context 'When a GroupAssignmentScheduleRequest is piped in' {
        It 'returns an object tagged with Omnicit.PIM.MyRoleResult' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{
                    action      = 'selfActivate'
                    status      = 'PendingProvisioning'
                    groupId     = 'group-id-001'
                    accessId    = 'member'
                    group       = [PSCustomObject]@{ displayName = 'Security Group' }
                    EndDateTime = $null
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleRequest')

                $Result = $FakeInput | ConvertTo-OPIMMyRoleResult

                $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.MyRoleResult'
            }
        }

        It 'maps Category to EntraIDGroup' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{
                    action      = 'selfActivate'
                    status      = 'PendingProvisioning'
                    groupId     = 'group-id-001'
                    accessId    = 'member'
                    group       = [PSCustomObject]@{ displayName = 'Security Group' }
                    EndDateTime = $null
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleRequest')

                $Result = $FakeInput | ConvertTo-OPIMMyRoleResult

                $Result.Category | Should -Be 'EntraIDGroup'
            }
        }

        It 'maps Scope to the accessId' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{
                    action      = 'selfActivate'
                    status      = 'PendingProvisioning'
                    groupId     = 'group-id-001'
                    accessId    = 'owner'
                    group       = [PSCustomObject]@{ displayName = 'Security Group' }
                    EndDateTime = $null
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleRequest')

                $Result = $FakeInput | ConvertTo-OPIMMyRoleResult

                $Result.Scope | Should -Be 'owner'
            }
        }
    }

    Context 'When an AzureAssignmentScheduleRequest is piped in' {
        It 'returns an object tagged with Omnicit.PIM.MyRoleResult' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{
                    RequestType               = 'SelfActivate'
                    Status                    = 'Provisioned'
                    RoleDefinitionDisplayName = 'Contributor'
                    ScopeDisplayName          = 'MySubscription'
                    ExpirationType            = 'AfterDateTime'
                    ExpirationDuration        = $null
                    ExpirationEndDateTime     = [datetime]'2026-04-20T16:00:00Z'
                    ScheduleInfoStartDateTime = $null
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleRequest')

                $Result = $FakeInput | ConvertTo-OPIMMyRoleResult

                $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.MyRoleResult'
            }
        }

        It 'maps Category to AzureRole' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{
                    RequestType               = 'SelfActivate'
                    Status                    = 'Provisioned'
                    RoleDefinitionDisplayName = 'Contributor'
                    ScopeDisplayName          = 'MySubscription'
                    ExpirationType            = 'AfterDateTime'
                    ExpirationDuration        = $null
                    ExpirationEndDateTime     = $null
                    ScheduleInfoStartDateTime = $null
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleRequest')

                $Result = $FakeInput | ConvertTo-OPIMMyRoleResult

                $Result.Category | Should -Be 'AzureRole'
            }
        }

        It 'computes EndDateTime from start + AfterDuration when ExpirationType is AfterDuration' {
            InModuleScope Omnicit.PIM {
                $StartDt = [datetime]'2026-04-20T12:00:00Z'
                $FakeInput = [PSCustomObject]@{
                    RequestType               = 'SelfActivate'
                    Status                    = 'Provisioned'
                    RoleDefinitionDisplayName = 'Owner'
                    ScopeDisplayName          = 'ProdSub'
                    ExpirationType            = 'AfterDuration'
                    ExpirationDuration        = 'PT2H'
                    ExpirationEndDateTime     = $null
                    ScheduleInfoStartDateTime = $StartDt
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleRequest')

                $Result = $FakeInput | ConvertTo-OPIMMyRoleResult

                $Result.EndDateTime | Should -Be ($StartDt.AddHours(2))
            }
        }
    }

    Context 'When an object with no recognised type is piped in' {
        It 'produces no output' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{ foo = 'bar' }

                $Result = $FakeInput | ConvertTo-OPIMMyRoleResult

                $Result | Should -BeNullOrEmpty
            }
        }
    }
}
