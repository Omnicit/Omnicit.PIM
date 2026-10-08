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
}
