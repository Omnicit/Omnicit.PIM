BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'AzureActivatedRoleCompleter' {
    Context 'When activated Azure roles are returned' {
        It 'returns a completion result for each role' {
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole {
                [PSCustomObject]@{
                    RoleDefinitionDisplayName = 'Contributor'
                    ScopeDisplayName          = 'My Subscription'
                    Name                      = 'elig-001'
                }
            }
            InModuleScope Omnicit.PIM {
                $Completer = [AzureActivatedRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMAzureRole', 'RoleName', '', $null, @{})
                $Result | Should -Not -BeNullOrEmpty
            }
        }

        It 'filters results when WordToComplete is specified' {
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole {
                @(
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Contributor'; ScopeDisplayName = 'My Subscription'; Name = 'elig-001' },
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Reader';      ScopeDisplayName = 'My Subscription'; Name = 'elig-002' }
                )
            }
            InModuleScope Omnicit.PIM {
                $Completer = [AzureActivatedRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMAzureRole', 'RoleName', 'Contrib', $null, @{})
                $Result.Count | Should -Be 1
            }
        }
    }

    Context 'When Get-OPIMAzureRole throws' {
        It 'returns null without propagating the exception' {
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { throw 'API unavailable' }
            InModuleScope Omnicit.PIM {
                $Completer = [AzureActivatedRoleCompleter]::new()
                { $Completer.CompleteArgument('Disable-OPIMAzureRole', 'RoleName', '', $null, @{}) } | Should -Not -Throw
                $Completer.CompleteArgument('Disable-OPIMAzureRole', 'RoleName', '', $null, @{}) | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'AzureEligibleRoleCompleter' {
    Context 'When eligible Azure roles are returned' {
        It 'returns a completion result for each role' {
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole {
                [PSCustomObject]@{
                    RoleDefinitionDisplayName = 'Contributor'
                    ScopeDisplayName          = 'My Subscription'
                    Name                      = 'elig-001'
                }
            }
            InModuleScope Omnicit.PIM {
                $Completer = [AzureEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMAzureRole', 'RoleName', '', $null, @{})
                $Result | Should -Not -BeNullOrEmpty
            }
        }

        It 'filters results when WordToComplete is specified' {
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole {
                @(
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Contributor'; ScopeDisplayName = 'My Subscription'; Name = 'elig-001' },
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Reader';      ScopeDisplayName = 'My Subscription'; Name = 'elig-002' }
                )
            }
            InModuleScope Omnicit.PIM {
                $Completer = [AzureEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMAzureRole', 'RoleName', 'Contrib', $null, @{})
                $Result.Count | Should -Be 1
            }
        }
    }

    Context 'When Get-OPIMAzureRole throws' {
        It 'returns null without propagating the exception' {
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { throw 'API unavailable' }
            InModuleScope Omnicit.PIM {
                $Completer = [AzureEligibleRoleCompleter]::new()
                { $Completer.CompleteArgument('Enable-OPIMAzureRole', 'RoleName', '', $null, @{}) } | Should -Not -Throw
                $Completer.CompleteArgument('Enable-OPIMAzureRole', 'RoleName', '', $null, @{}) | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'DirectoryActivatedRoleCompleter' {
    Context 'When activated directory roles are returned at the root scope' {
        It 'returns a completion result for each role' {
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole {
                [PSCustomObject]@{
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                    directoryScopeId = '/'
                    id               = 'inst-001'
                }
            }
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryActivatedRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMDirectoryRole', 'RoleName', '', $null, @{})
                $Result | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'When an activated directory role has a non-root scope' {
        It 'includes the scope display name in the completion string' {
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole {
                [PSCustomObject]@{
                    roleDefinition   = [PSCustomObject]@{ displayName = 'User Administrator' }
                    directoryScopeId = '/administrativeUnits/au-001'
                    directoryScope   = [PSCustomObject]@{ displayName = 'Finance AU' }
                    id               = 'inst-002'
                }
            }
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryActivatedRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMDirectoryRole', 'RoleName', '', $null, @{})
                $Result | Should -Not -BeNullOrEmpty
                ($Result | Out-String) | Should -Match 'Finance AU'
            }
        }
    }

    Context 'When Get-OPIMDirectoryRole throws' {
        It 'returns null without propagating the exception' {
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { throw 'API unavailable' }
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryActivatedRoleCompleter]::new()
                { $Completer.CompleteArgument('Disable-OPIMDirectoryRole', 'RoleName', '', $null, @{}) } | Should -Not -Throw
                $Completer.CompleteArgument('Disable-OPIMDirectoryRole', 'RoleName', '', $null, @{}) | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'DirectoryEligibleRoleCompleter' {
    Context 'When eligible directory roles are returned at the root scope' {
        It 'returns a completion result for each role' {
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole {
                [PSCustomObject]@{
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                    directoryScopeId = '/'
                    id               = 'elig-001'
                }
            }
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMDirectoryRole', 'RoleName', '', $null, @{})
                $Result | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'When an eligible directory role has a non-root scope' {
        It 'includes the scope display name in the completion string' {
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole {
                [PSCustomObject]@{
                    roleDefinition   = [PSCustomObject]@{ displayName = 'User Administrator' }
                    directoryScopeId = '/administrativeUnits/au-001'
                    directoryScope   = [PSCustomObject]@{ displayName = 'Finance AU' }
                    id               = 'elig-002'
                }
            }
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMDirectoryRole', 'RoleName', '', $null, @{})
                $Result | Should -Not -BeNullOrEmpty
                ($Result | Out-String) | Should -Match 'Finance AU'
            }
        }
    }

    Context 'When Get-OPIMDirectoryRole throws' {
        It 'returns null without propagating the exception' {
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { throw 'API unavailable' }
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryEligibleRoleCompleter]::new()
                { $Completer.CompleteArgument('Enable-OPIMDirectoryRole', 'RoleName', '', $null, @{}) } | Should -Not -Throw
                $Completer.CompleteArgument('Enable-OPIMDirectoryRole', 'RoleName', '', $null, @{}) | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'GroupActivatedCompleter' {
    Context 'When activated PIM groups are returned' {
        It 'returns a completion result for each group' {
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup {
                [PSCustomObject]@{
                    group    = [PSCustomObject]@{ displayName = 'Finance Team' }
                    accessId = 'member'
                    id       = 'inst-001'
                }
            }
            InModuleScope Omnicit.PIM {
                $Completer = [GroupActivatedCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMEntraIDGroup', 'GroupName', '', $null, @{})
                $Result | Should -Not -BeNullOrEmpty
            }
        }

        It 'filters results when WordToComplete is specified' {
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup {
                @(
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'Finance Team' }; accessId = 'member'; id = 'inst-001' },
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'DevOps Team'  }; accessId = 'owner';  id = 'inst-002' }
                )
            }
            InModuleScope Omnicit.PIM {
                $Completer = [GroupActivatedCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMEntraIDGroup', 'GroupName', 'Finance', $null, @{})
                $Result.Count | Should -Be 1
            }
        }
    }

    Context 'When Get-OPIMEntraIDGroup throws' {
        It 'returns null without propagating the exception' {
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { throw 'API unavailable' }
            InModuleScope Omnicit.PIM {
                $Completer = [GroupActivatedCompleter]::new()
                { $Completer.CompleteArgument('Disable-OPIMEntraIDGroup', 'GroupName', '', $null, @{}) } | Should -Not -Throw
                $Completer.CompleteArgument('Disable-OPIMEntraIDGroup', 'GroupName', '', $null, @{}) | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'GroupEligibleCompleter' {
    Context 'When eligible PIM groups are returned' {
        It 'returns a completion result for each group' {
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup {
                [PSCustomObject]@{
                    group    = [PSCustomObject]@{ displayName = 'Finance Team' }
                    accessId = 'member'
                    id       = 'elig-001'
                }
            }
            InModuleScope Omnicit.PIM {
                $Completer = [GroupEligibleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMEntraIDGroup', 'GroupName', '', $null, @{})
                $Result | Should -Not -BeNullOrEmpty
            }
        }

        It 'filters results when WordToComplete is specified' {
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup {
                @(
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'Finance Team' }; accessId = 'member'; id = 'elig-001' },
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'DevOps Team'  }; accessId = 'owner';  id = 'elig-002' }
                )
            }
            InModuleScope Omnicit.PIM {
                $Completer = [GroupEligibleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMEntraIDGroup', 'GroupName', 'Finance', $null, @{})
                $Result.Count | Should -Be 1
            }
        }
    }

    Context 'When Get-OPIMEntraIDGroup throws' {
        It 'returns null without propagating the exception' {
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { throw 'API unavailable' }
            InModuleScope Omnicit.PIM {
                $Completer = [GroupEligibleCompleter]::new()
                { $Completer.CompleteArgument('Enable-OPIMEntraIDGroup', 'GroupName', '', $null, @{}) } | Should -Not -Throw
                $Completer.CompleteArgument('Enable-OPIMEntraIDGroup', 'GroupName', '', $null, @{}) | Should -BeNullOrEmpty
            }
        }
    }
}


