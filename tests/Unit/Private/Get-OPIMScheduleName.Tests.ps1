BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMScheduleName' {
    Context 'When the pillar is Directory' {
        It 'returns the old form of a role at the root scope' {
            InModuleScope Omnicit.PIM {
                $Role = [PSCustomObject]@{
                    id               = 'elig-001'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }
                    directoryScopeId = '/'
                    directoryScope   = $null
                }
                $Role.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
                $Names = Get-OPIMScheduleName -Pillar Directory -InputObject $Role
                $Names.OldForm | Should -Be 'Usage Summary Reports Reader (elig-001)'
                $Names.DisplayName | Should -Be 'Usage Summary Reports Reader'
                $Names.Key | Should -Be 'elig-001'
                $Names.ScopeId | Should -Be '/'
                $Names.ScopeName | Should -Be 'Directory'
                $Names.Label | Should -Be 'Usage Summary Reports Reader'
                $Names.AccessId | Should -BeNullOrEmpty
            }
        }

        It 'returns the administrative unit in the old form of a scoped role' {
            InModuleScope Omnicit.PIM {
                $Role = [PSCustomObject]@{
                    id               = 'elig-002'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }
                    directoryScopeId = '/administrativeUnits/au-001'
                    directoryScope   = [PSCustomObject]@{ displayName = 'Sales AU' }
                }
                $Role.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
                $Names = Get-OPIMScheduleName -Pillar Directory -InputObject $Role
                $Names.OldForm | Should -Be 'Usage Summary Reports Reader -> Sales AU (elig-002)'
                $Names.Label | Should -Be 'Usage Summary Reports Reader -> Sales AU'
                $Names.ScopeId | Should -Be '/administrativeUnits/au-001'
                $Names.ScopeName | Should -Be 'Sales AU'
            }
        }

        It 'treats an empty directoryScopeId as the root scope' {
            InModuleScope Omnicit.PIM {
                $Role = [PSCustomObject]@{
                    id               = 'elig-001'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }
                    directoryScopeId = ''
                    directoryScope   = $null
                }
                $Names = Get-OPIMScheduleName -Pillar Directory -InputObject $Role
                $Names.OldForm | Should -Be 'Usage Summary Reports Reader (elig-001)'
                $Names.OldForm | Should -Not -BeLike '* -> *'
                $Names.ScopeName | Should -Be 'Directory'
            }
        }

        It 'does not throw for a scoped role whose directoryScope is null' {
            InModuleScope Omnicit.PIM {
                $Role = [PSCustomObject]@{
                    id               = 'elig-020'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }
                    directoryScopeId = '/administrativeUnits/au-009'
                    directoryScope   = $null
                }
                $Names = Get-OPIMScheduleName -Pillar Directory -InputObject $Role -ErrorAction Stop
                $Names.ScopeId | Should -Be '/administrativeUnits/au-009'
                $Names.ScopeName | Should -BeNullOrEmpty
            }
        }
    }

    Context 'When the pillar is Group' {
        It 'returns the old form and the access type of a group' {
            InModuleScope Omnicit.PIM {
                $Group = [PSCustomObject]@{
                    id           = 'grp-elig-002'
                    groupId      = 'g-2'
                    accessId     = 'owner'
                    memberType   = 'direct'
                    group        = [PSCustomObject]@{ displayName = 'grp-ops' }
                    scheduleInfo = $null
                }
                $Group.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
                $Names = Get-OPIMScheduleName -Pillar Group -InputObject $Group
                $Names.OldForm | Should -Be 'grp-ops - owner (grp-elig-002)'
                $Names.AccessId | Should -Be 'owner'
                $Names.DisplayName | Should -Be 'grp-ops'
                $Names.Key | Should -Be 'grp-elig-002'
                $Names.ScopeId | Should -BeNullOrEmpty
                $Names.ScopeName | Should -BeNullOrEmpty
            }
        }
    }

    Context 'When the pillar is Azure' {
        It 'returns the old form, the key and the scope of an Azure role' {
            InModuleScope Omnicit.PIM {
                $Role = [PSCustomObject]@{
                    Name                      = 'azure-001'
                    RoleDefinitionDisplayName = 'Reader'
                    ScopeId                   = '/subscriptions/sub-001/resourceGroups/rg-one'
                    ScopeDisplayName          = 'rg-one'
                }
                $Role.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
                $Names = Get-OPIMScheduleName -Pillar Azure -InputObject $Role
                $Names.OldForm | Should -Be 'Reader -> rg-one (azure-001)'
                $Names.Key | Should -Be 'azure-001'
                $Names.DisplayName | Should -Be 'Reader'
                $Names.ScopeId | Should -Be '/subscriptions/sub-001/resourceGroups/rg-one'
                $Names.ScopeName | Should -Be 'rg-one'
            }
        }
    }

    Context 'When the input is unusual' {
        It 'returns nothing for a null object' {
            InModuleScope Omnicit.PIM {
                $Result = Get-OPIMScheduleName -Pillar Directory -InputObject $null
                $Result | Should -BeNullOrEmpty
            }
        }

        It 'keeps the original object in InputObject' {
            InModuleScope Omnicit.PIM {
                $Role = [PSCustomObject]@{
                    Name                      = 'azure-001'
                    RoleDefinitionDisplayName = 'Reader'
                    ScopeId                   = '/subscriptions/sub-001'
                    ScopeDisplayName          = 'sub-001'
                }
                $Names = Get-OPIMScheduleName -Pillar Azure -InputObject $Role
                [object]::ReferenceEquals($Names.InputObject, $Role) | Should -BeTrue
            }
        }

        It 'reads objects from the pipeline' {
            InModuleScope Omnicit.PIM {
                $Roles = @(
                    [PSCustomObject]@{ Name = 'azure-001'; RoleDefinitionDisplayName = 'Reader'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'sub-001' }
                    [PSCustomObject]@{ Name = 'azure-002'; RoleDefinitionDisplayName = 'Owner'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'sub-001' }
                )
                $Names = @($Roles | Get-OPIMScheduleName -Pillar Azure)
                $Names.Count | Should -Be 2
                $Names[1].OldForm | Should -Be 'Owner -> sub-001 (azure-002)'
            }
        }
    }
}
