BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'ConvertTo-OPIMTenantMapKey' {
    Context 'When it builds the key of a directory role' {
        It 'returns roleDefinitionId|directoryScopeId for an eligibility at the root' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{ roleDefinitionId = 'role-def-001'; directoryScopeId = '/' }
                ConvertTo-OPIMTenantMapKey -Pillar Directory -InputObject $Post | Should -BeExactly 'role-def-001|/'
            }
        }

        It 'returns the administrative unit path for a post at an administrative unit' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{ roleDefinitionId = 'role-def-001'; directoryScopeId = '/administrativeUnits/au-001' }
                ConvertTo-OPIMTenantMapKey -Pillar Directory -InputObject $Post | Should -BeExactly 'role-def-001|/administrativeUnits/au-001'
            }
        }
    }

    Context 'When it reads a stored directory entry' {
        It 'reads an entry without a scope as the role at the root (A13)' {
            InModuleScope Omnicit.PIM {
                ConvertTo-OPIMTenantMapKey -Pillar Directory -Entry 'role-def-001' | Should -BeExactly 'role-def-001|/'
            }
        }

        It 'returns an entry with a scope as it is' {
            InModuleScope Omnicit.PIM {
                ConvertTo-OPIMTenantMapKey -Pillar Directory -Entry 'role-def-001|/administrativeUnits/au-001' |
                    Should -BeExactly 'role-def-001|/administrativeUnits/au-001'
            }
        }

        It 'returns a group or Azure entry as it is' {
            InModuleScope Omnicit.PIM {
                ConvertTo-OPIMTenantMapKey -Pillar Group -Entry 'group-001_member' | Should -BeExactly 'group-001_member'
                ConvertTo-OPIMTenantMapKey -Pillar Azure -Entry 'elig-az-001' | Should -BeExactly 'elig-az-001'
            }
        }
    }

    Context 'When it builds the key of a group or an Azure eligibility' {
        It 'returns groupId_accessId for a group' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{ id = 'elig-grp-001'; groupId = 'group-001'; accessId = 'owner' }
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
                ConvertTo-OPIMTenantMapKey -Pillar Group -InputObject $Post | Should -BeExactly 'group-001_owner'
            }
        }

        It 'returns the schedule Name for an Azure eligibility' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{
                    Name             = 'elig-az-001'
                    RoleDefinitionId = 'role-az-001'
                    ScopeId          = '/subscriptions/sub-001'
                }
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
                ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Post | Should -BeExactly 'elig-az-001'
            }
        }

        It 'returns nothing for a null object' {
            InModuleScope Omnicit.PIM {
                ConvertTo-OPIMTenantMapKey -Pillar Directory -InputObject $null | Should -BeNullOrEmpty
                @(ConvertTo-OPIMTenantMapKey -Pillar Directory -InputObject $null).Count | Should -Be 0
            }
        }
    }

    Context 'When it builds the key of an active Azure role (OPIM-22)' {
        # An active instance is stored by the eligibility schedule it was activated from: the last
        # segment of its LinkedRoleEligibilityScheduleId, which is the Name of that eligibility.
        It 'returns the eligibility a typed active instance was activated from, not its own Name' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{
                    Name                            = 'az-active-001'
                    LinkedRoleEligibilityScheduleId = '/subscriptions/sub-001/providers/Microsoft.Authorization/roleEligibilitySchedules/elig-az-001'
                    RoleDefinitionId                = 'role-az-001'
                    ScopeId                         = '/subscriptions/sub-001'
                }
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Post | Should -BeExactly 'elig-az-001'
            }
        }

        It 'returns a bare linked id as it is' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{
                    Name                            = 'az-active-002'
                    LinkedRoleEligibilityScheduleId = 'elig-az-002'
                    RoleDefinitionId                = 'role-az-002'
                    ScopeId                         = '/subscriptions/sub-001'
                }
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Post | Should -BeExactly 'elig-az-002'
            }
        }

        It 'returns the linked eligibility of an untyped instance that carries the property, as Az returns it' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{
                    Name                            = 'az-active-003'
                    LinkedRoleEligibilityScheduleId = '/providers/Microsoft.Management/managementGroups/mg-001/providers/Microsoft.Authorization/roleEligibilitySchedules/elig-az-003'
                    RoleDefinitionId                = 'role-az-003'
                    ScopeId                         = '/providers/Microsoft.Management/managementGroups/mg-001'
                }
                ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Post | Should -BeExactly 'elig-az-003'
            }
        }

        It 'returns the linked eligibility of an active row of -All, and the Name of an eligible row' {
            InModuleScope Omnicit.PIM {
                $ActiveRow = [PSCustomObject]@{
                    Name                            = 'az-active-004'
                    LinkedRoleEligibilityScheduleId = '/subscriptions/sub-001/providers/Microsoft.Authorization/roleEligibilitySchedules/elig-az-004'
                    RoleDefinitionId                = 'role-az-004'
                    ScopeId                         = '/subscriptions/sub-001'
                    Status                          = 'Active'
                }
                $ActiveRow.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                $ActiveRow.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureCombinedSchedule')
                $EligibleRow = [PSCustomObject]@{
                    Name             = 'elig-az-005'
                    RoleDefinitionId = 'role-az-005'
                    ScopeId          = '/subscriptions/sub-001'
                    Status           = 'Eligible'
                }
                $EligibleRow.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
                $EligibleRow.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureCombinedSchedule')
                ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $ActiveRow | Should -BeExactly 'elig-az-004'
                ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $EligibleRow | Should -BeExactly 'elig-az-005'
            }
        }

        It 'throws LinkedEligibilityNotFound for an active instance whose linked id is <Label>' -ForEach @(
            @{ Label = 'null'; Linked = $null }
            @{ Label = 'empty'; Linked = '' }
            @{ Label = 'blank'; Linked = '   ' }
            @{ Label = 'an id that ends in a slash'; Linked = '/subscriptions/sub-001/providers/Microsoft.Authorization/roleEligibilitySchedules/' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Linked = $Linked } {
                param($Linked)
                $Post = [PSCustomObject]@{
                    Name                            = 'az-active-006'
                    LinkedRoleEligibilityScheduleId = $Linked
                    RoleDefinitionId                = 'role-az-006'
                    ScopeId                         = '/subscriptions/sub-001'
                }
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                { ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Post } |
                    Should -Throw -ErrorId 'LinkedEligibilityNotFound*'
            }
        }

        It 'throws LinkedEligibilityNotFound for a typed active instance without the property' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{
                    Name             = 'az-active-007'
                    RoleDefinitionId = 'role-az-007'
                    ScopeId          = '/subscriptions/sub-001'
                }
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                { ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Post } |
                    Should -Throw -ErrorId 'LinkedEligibilityNotFound*'
            }
        }

        It 'builds the record with category ObjectNotFound, the instance as its target, and the role and scope in its message' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{
                    Name                            = 'az-active-008'
                    LinkedRoleEligibilityScheduleId = $null
                    RoleDefinitionId                = 'role-az-008'
                    RoleDefinitionDisplayName       = 'Contributor'
                    ScopeId                         = '/subscriptions/sub-001'
                    ScopeDisplayName                = 'ProdSub'
                }
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                $Err = { ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Post } | Should -Throw -PassThru
                $Err.FullyQualifiedErrorId | Should -BeLike 'LinkedEligibilityNotFound*'
                $Err.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
                [object]::ReferenceEquals($Err.TargetObject, $Post) | Should -BeTrue
                $Err.Exception.Message | Should -BeExactly (
                    "The active Azure role 'Contributor' at scope 'ProdSub' names no eligibility it was activated " +
                    'from (its LinkedRoleEligibilityScheduleId is empty), so it is not stored. Pipe the eligible ' +
                    'role from Get-OPIMAzureRole instead.')
            }
        }

        It 'names the scope id and the role definition id when the display names are missing' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{
                    Name                            = 'az-active-009'
                    LinkedRoleEligibilityScheduleId = ''
                    RoleDefinitionId                = 'role-az-009'
                    ScopeId                         = '/subscriptions/sub-001'
                }
                $Err = { ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Post } | Should -Throw -PassThru
                $Err.Exception.Message | Should -BeLike "The active Azure role 'role-az-009' at scope '/subscriptions/sub-001' names no eligibility*"
            }
        }
    }
}
