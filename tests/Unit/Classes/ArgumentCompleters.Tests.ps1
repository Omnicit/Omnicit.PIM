Describe 'AzureActivatedRoleCompleter' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When activated Azure roles are returned' {
        It 'returns a completion result for each role' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMAzureRole {
                    [PSCustomObject]@{
                        RoleDefinitionDisplayName = 'Contributor'
                        ScopeDisplayName          = 'My Subscription'
                        Name                      = 'elig-001'
                    }
                }
                $Completer = [AzureActivatedRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMAzureRole', 'RoleName', '', $null, @{})
                $Result | Should -Not -BeNullOrEmpty
            }
        }

        It 'filters results when WordToComplete is specified' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMAzureRole {
                    @(
                        [PSCustomObject]@{ RoleDefinitionDisplayName = 'Contributor'; ScopeDisplayName = 'My Subscription'; Name = 'elig-001' },
                        [PSCustomObject]@{ RoleDefinitionDisplayName = 'Reader';      ScopeDisplayName = 'My Subscription'; Name = 'elig-002' }
                    )
                }
                $Completer = [AzureActivatedRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMAzureRole', 'RoleName', 'Contrib', $null, @{})
                $Result.Count | Should -Be 1
            }
        }
    }

    Context 'When Get-OPIMAzureRole throws' {
        It 'returns null without propagating the exception' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMAzureRole { throw 'API unavailable' }
                $Completer = [AzureActivatedRoleCompleter]::new()
                $Result = $null
                { $Result = $Completer.CompleteArgument('Disable-OPIMAzureRole', 'RoleName', '', $null, @{}) } | Should -Not -Throw
                $Result | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'AzureEligibleRoleCompleter' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When eligible Azure roles are returned' {
        It 'returns a completion result for each role' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMAzureRole {
                    [PSCustomObject]@{
                        RoleDefinitionDisplayName = 'Contributor'
                        ScopeDisplayName          = 'My Subscription'
                        Name                      = 'elig-001'
                    }
                }
                $Completer = [AzureEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMAzureRole', 'RoleName', '', $null, @{})
                $Result | Should -Not -BeNullOrEmpty
            }
        }

        It 'filters results when WordToComplete is specified' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMAzureRole {
                    @(
                        [PSCustomObject]@{ RoleDefinitionDisplayName = 'Contributor'; ScopeDisplayName = 'My Subscription'; Name = 'elig-001' },
                        [PSCustomObject]@{ RoleDefinitionDisplayName = 'Reader';      ScopeDisplayName = 'My Subscription'; Name = 'elig-002' }
                    )
                }
                $Completer = [AzureEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMAzureRole', 'RoleName', 'Contrib', $null, @{})
                $Result.Count | Should -Be 1
            }
        }
    }

    Context 'When Get-OPIMAzureRole throws' {
        It 'returns null without propagating the exception' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMAzureRole { throw 'API unavailable' }
                $Completer = [AzureEligibleRoleCompleter]::new()
                $Result = $null
                { $Result = $Completer.CompleteArgument('Enable-OPIMAzureRole', 'RoleName', '', $null, @{}) } | Should -Not -Throw
                $Result | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'DirectoryActivatedRoleCompleter' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When activated directory roles are returned at the root scope' {
        It 'returns a completion result for each role' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMDirectoryRole {
                    [PSCustomObject]@{
                        roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                        directoryScopeId = '/'
                        id               = 'inst-001'
                    }
                }
                $Completer = [DirectoryActivatedRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMDirectoryRole', 'RoleName', '', $null, @{})
                $Result | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'When an activated directory role has a non-root scope' {
        It 'includes the scope display name in the completion string' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMDirectoryRole {
                    [PSCustomObject]@{
                        roleDefinition   = [PSCustomObject]@{ displayName = 'User Administrator' }
                        directoryScopeId = '/administrativeUnits/au-001'
                        directoryScope   = [PSCustomObject]@{ displayName = 'Finance AU' }
                        id               = 'inst-002'
                    }
                }
                $Completer = [DirectoryActivatedRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMDirectoryRole', 'RoleName', '', $null, @{})
                $Result | Should -Not -BeNullOrEmpty
                ($Result | Out-String) | Should -Match 'Finance AU'
            }
        }
    }

    Context 'When Get-OPIMDirectoryRole throws' {
        It 'returns null without propagating the exception' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMDirectoryRole { throw 'API unavailable' }
                $Completer = [DirectoryActivatedRoleCompleter]::new()
                $Result = $null
                { $Result = $Completer.CompleteArgument('Disable-OPIMDirectoryRole', 'RoleName', '', $null, @{}) } | Should -Not -Throw
                $Result | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'DirectoryEligibleRoleCompleter' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When eligible directory roles are returned at the root scope' {
        It 'returns a completion result for each role' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMDirectoryRole {
                    [PSCustomObject]@{
                        roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                        directoryScopeId = '/'
                        id               = 'elig-001'
                    }
                }
                $Completer = [DirectoryEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMDirectoryRole', 'RoleName', '', $null, @{})
                $Result | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'When an eligible directory role has a non-root scope' {
        It 'includes the scope display name in the completion string' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMDirectoryRole {
                    [PSCustomObject]@{
                        roleDefinition   = [PSCustomObject]@{ displayName = 'User Administrator' }
                        directoryScopeId = '/administrativeUnits/au-001'
                        directoryScope   = [PSCustomObject]@{ displayName = 'Finance AU' }
                        id               = 'elig-002'
                    }
                }
                $Completer = [DirectoryEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMDirectoryRole', 'RoleName', '', $null, @{})
                $Result | Should -Not -BeNullOrEmpty
                ($Result | Out-String) | Should -Match 'Finance AU'
            }
        }
    }

    Context 'When Get-OPIMDirectoryRole throws' {
        It 'returns null without propagating the exception' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMDirectoryRole { throw 'API unavailable' }
                $Completer = [DirectoryEligibleRoleCompleter]::new()
                $Result = $null
                { $Result = $Completer.CompleteArgument('Enable-OPIMDirectoryRole', 'RoleName', '', $null, @{}) } | Should -Not -Throw
                $Result | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'GroupActivatedCompleter' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When activated PIM groups are returned' {
        It 'returns a completion result for each group' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMEntraIDGroup {
                    [PSCustomObject]@{
                        group    = [PSCustomObject]@{ displayName = 'Finance Team' }
                        accessId = 'member'
                        id       = 'inst-001'
                    }
                }
                $Completer = [GroupActivatedCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMEntraIDGroup', 'GroupName', '', $null, @{})
                $Result | Should -Not -BeNullOrEmpty
            }
        }

        It 'filters results when WordToComplete is specified' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMEntraIDGroup {
                    @(
                        [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'Finance Team' }; accessId = 'member'; id = 'inst-001' },
                        [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'DevOps Team'  }; accessId = 'owner';  id = 'inst-002' }
                    )
                }
                $Completer = [GroupActivatedCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMEntraIDGroup', 'GroupName', 'Finance', $null, @{})
                $Result.Count | Should -Be 1
            }
        }
    }

    Context 'When Get-OPIMEntraIDGroup throws' {
        It 'returns null without propagating the exception' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMEntraIDGroup { throw 'API unavailable' }
                $Completer = [GroupActivatedCompleter]::new()
                $Result = $null
                { $Result = $Completer.CompleteArgument('Disable-OPIMEntraIDGroup', 'GroupName', '', $null, @{}) } | Should -Not -Throw
                $Result | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'GroupEligibleCompleter' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When eligible PIM groups are returned' {
        It 'returns a completion result for each group' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMEntraIDGroup {
                    [PSCustomObject]@{
                        group    = [PSCustomObject]@{ displayName = 'Finance Team' }
                        accessId = 'member'
                        id       = 'elig-001'
                    }
                }
                $Completer = [GroupEligibleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMEntraIDGroup', 'GroupName', '', $null, @{})
                $Result | Should -Not -BeNullOrEmpty
            }
        }

        It 'filters results when WordToComplete is specified' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMEntraIDGroup {
                    @(
                        [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'Finance Team' }; accessId = 'member'; id = 'elig-001' },
                        [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'DevOps Team'  }; accessId = 'owner';  id = 'elig-002' }
                    )
                }
                $Completer = [GroupEligibleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMEntraIDGroup', 'GroupName', 'Finance', $null, @{})
                $Result.Count | Should -Be 1
            }
        }
    }

    Context 'When Get-OPIMEntraIDGroup throws' {
        It 'returns null without propagating the exception' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMEntraIDGroup { throw 'API unavailable' }
                $Completer = [GroupEligibleCompleter]::new()
                $Result = $null
                { $Result = $Completer.CompleteArgument('Enable-OPIMEntraIDGroup', 'GroupName', '', $null, @{}) } | Should -Not -Throw
                $Result | Should -BeNullOrEmpty
            }
        }
    }
}
