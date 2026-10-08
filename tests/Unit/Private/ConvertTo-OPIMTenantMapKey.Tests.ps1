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

        It 'returns nothing for a blank or null <Pillar> entry, so it matches no post' -ForEach @(
            @{ Pillar = 'Directory' }
            @{ Pillar = 'Group' }
            @{ Pillar = 'Azure' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Pillar = $Pillar } {
                param($Pillar)
                foreach ($Blank in @('', '   ', $null)) {
                    @(ConvertTo-OPIMTenantMapKey -Pillar $Pillar -Entry $Blank -ErrorAction Stop).Count | Should -Be 0
                }
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

    Context 'When it builds the scoped key of a post (-WithScope)' {
        # The form an active Azure role is stored under: an eligibility at its own scope matches it.
        It 'returns Name|ScopeId for an Azure eligibility' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{ Name = 'elig-az-001'; RoleDefinitionId = 'role-az-001'; ScopeId = '/subscriptions/sub-001' }
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
                ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Post -WithScope | Should -BeExactly 'elig-az-001|/subscriptions/sub-001'
            }
        }

        It 'returns the same key for an active Azure role as without the switch' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{
                    Name                            = 'az-active-001'
                    LinkedRoleEligibilityScheduleId = 'elig-az-001'
                    RoleDefinitionId                = 'role-az-001'
                    ScopeId                         = '/subscriptions/sub-001'
                }
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Post -WithScope | Should -BeExactly 'elig-az-001|/subscriptions/sub-001'
            }
        }

        It 'returns the same key for a directory role and a group as without the switch' {
            InModuleScope Omnicit.PIM {
                $Role = [PSCustomObject]@{ roleDefinitionId = 'role-def-001'; directoryScopeId = '/administrativeUnits/au-001' }
                $Group = [PSCustomObject]@{ groupId = 'group-001'; accessId = 'member' }
                ConvertTo-OPIMTenantMapKey -Pillar Directory -InputObject $Role -WithScope | Should -BeExactly 'role-def-001|/administrativeUnits/au-001'
                ConvertTo-OPIMTenantMapKey -Pillar Group -InputObject $Group -WithScope | Should -BeExactly 'group-001_member'
            }
        }
    }

    Context 'When it builds the key of an active Azure role (OPIM-22)' {
        # An active instance is stored by the eligibility schedule it was activated from -- the last
        # segment of its LinkedRoleEligibilityScheduleId, which is the Name of that eligibility -- and
        # by its own scope: '<eligibility Name>|<instance ScopeId>'. pim matches that entry only with
        # the eligibility at that scope, so the scope is proven when the entry is read.
        It 'returns the eligibility a typed active instance was activated from and its own scope, not its own Name' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{
                    Name                            = 'az-active-001'
                    LinkedRoleEligibilityScheduleId = '/subscriptions/sub-001/providers/Microsoft.Authorization/roleEligibilitySchedules/elig-az-001'
                    RoleDefinitionId                = 'role-az-001'
                    ScopeId                         = '/subscriptions/sub-001'
                }
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Post | Should -BeExactly 'elig-az-001|/subscriptions/sub-001'
            }
        }

        It 'stores an instance whose link is <Label> with the instance scope' -ForEach @(
            # Measured in Microsoft Learn (Role Assignment Schedule Instances - Get, api 2020-10-01):
            # ARM returns linkedRoleEligibilityScheduleId as a bare GUID, and Enable-OPIMAzureRole
            # sends the bare Name.
            @{ Label = 'a bare name'; Linked = 'elig-az-002'; ScopeId = '/subscriptions/sub-001'; Expected = 'elig-az-002|/subscriptions/sub-001' }
            @{ Label = 'a bare name, below the scope of the eligibility'; Linked = 'elig-az-002'; ScopeId = '/subscriptions/sub-001/resourceGroups/rg-001'; Expected = 'elig-az-002|/subscriptions/sub-001/resourceGroups/rg-001' }
            @{ Label = 'the provider-only form'; Linked = '/providers/Microsoft.Authorization/roleEligibilitySchedules/elig-az-002'; ScopeId = '/subscriptions/sub-001'; Expected = 'elig-az-002|/subscriptions/sub-001' }
            @{ Label = 'the provider-only form, at the root scope'; Linked = '/providers/Microsoft.Authorization/roleEligibilitySchedules/elig-az-002'; ScopeId = '/'; Expected = 'elig-az-002|/' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Linked = $Linked; ScopeId = $ScopeId; Expected = $Expected } {
                param($Linked, $ScopeId, $Expected)
                $Post = [PSCustomObject]@{
                    Name                            = 'az-active-002'
                    LinkedRoleEligibilityScheduleId = $Linked
                    RoleDefinitionId                = 'role-az-002'
                    ScopeId                         = $ScopeId
                }
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Post -ErrorAction Stop | Should -BeExactly $Expected
            }
        }

        It 'refuses an instance activated at a narrower scope than its eligibility' {
            InModuleScope Omnicit.PIM {
                # The portal's Scope tab activates a subscription eligibility at one resource group: the
                # instance is at the resource group, its link names the subscription eligibility. Storing that
                # eligibility would make pim activate the whole subscription.
                $Post = [PSCustomObject]@{
                    Name                            = 'az-active-010'
                    LinkedRoleEligibilityScheduleId = '/subscriptions/sub-001/providers/Microsoft.Authorization/roleEligibilitySchedules/elig-az-010'
                    RoleDefinitionId                = 'role-az-010'
                    RoleDefinitionDisplayName       = 'Contributor'
                    ScopeId                         = '/subscriptions/sub-001/resourceGroups/rg-001'
                    ScopeDisplayName                = 'rg-001'
                }
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                $Err = { ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Post } | Should -Throw -PassThru
                $Err.FullyQualifiedErrorId | Should -BeLike 'LinkedEligibilityNotFound*'
                $Err.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
                [object]::ReferenceEquals($Err.TargetObject, $Post) | Should -BeTrue
                $Err.Exception.Message | Should -BeExactly (
                    "The active Azure role 'Contributor' at scope 'rg-001' cannot be shown to be active at the scope " +
                    'of the eligibility it was activated from, so it is not stored: pim activates an eligibility at ' +
                    'its own scope, which can be wider. Pipe the eligible role from Get-OPIMAzureRole instead.')
            }
        }

        It 'stores an instance at the scope of its eligibility, compared without regard to letter case' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{
                    Name                            = 'az-active-012'
                    LinkedRoleEligibilityScheduleId = '/subscriptions/sub-001/providers/Microsoft.Authorization/roleEligibilitySchedules/elig-az-012'
                    RoleDefinitionId                = 'role-az-012'
                    ScopeId                         = '/SUBSCRIPTIONS/SUB-001'
                }
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Post | Should -BeExactly 'elig-az-012|/SUBSCRIPTIONS/SUB-001'
            }
        }

        It 'finds the eligibility provider segment of the link without regard to letter case, and so refuses a link at another scope' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{
                    Name                            = 'az-active-013'
                    LinkedRoleEligibilityScheduleId = '/subscriptions/sub-001/PROVIDERS/microsoft.authorization/ROLEELIGIBILITYSCHEDULES/elig-az-013'
                    RoleDefinitionId                = 'role-az-013'
                    ScopeId                         = '/subscriptions/sub-002'
                }
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
                # Found, the segment shows a full link at another scope than the instance, which is refused.
                { ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Post } |
                    Should -Throw -ErrorId 'LinkedEligibilityNotFound*' -ExpectedMessage '*cannot be shown to be active at the scope of the eligibility*'
            }
        }

        It 'returns the linked eligibility and the scope of an untyped instance that carries the property, as Az returns it' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{
                    Name                            = 'az-active-003'
                    LinkedRoleEligibilityScheduleId = '/providers/Microsoft.Management/managementGroups/mg-001/providers/Microsoft.Authorization/roleEligibilitySchedules/elig-az-003'
                    RoleDefinitionId                = 'role-az-003'
                    ScopeId                         = '/providers/Microsoft.Management/managementGroups/mg-001'
                }
                ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $Post |
                    Should -BeExactly 'elig-az-003|/providers/Microsoft.Management/managementGroups/mg-001'
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
                ConvertTo-OPIMTenantMapKey -Pillar Azure -InputObject $ActiveRow | Should -BeExactly 'elig-az-004|/subscriptions/sub-001'
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
                    Should -Throw -ErrorId 'LinkedEligibilityNotFound*' -ExpectedMessage "*'role-az-007' at scope '/subscriptions/sub-001' names no eligibility schedule it was activated from*"
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
                    "The active Azure role 'Contributor' at scope 'ProdSub' names no eligibility schedule it was " +
                    'activated from, so it is not stored. Pipe the eligible role from Get-OPIMAzureRole instead.')
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
