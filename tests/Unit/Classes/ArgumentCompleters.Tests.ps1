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

    Context 'When a role is active at two scopes' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole {
                @(
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Reader'; ScopeId = '/subscriptions/sub-001/resourceGroups/rg-one'; ScopeDisplayName = 'rg-one'; Name = 'inst-001' }
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Reader'; ScopeId = '/subscriptions/sub-001/resourceGroups/rg-two'; ScopeDisplayName = 'rg-two'; Name = 'inst-002' }
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Contributor'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'Subscription One'; Name = 'inst-003' }
                )
            } -ParameterFilter { $Activated }
        }

        It 'offers the old forms of that role and the bare name of the other' {
            InModuleScope Omnicit.PIM {
                $Completer = [AzureActivatedRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMAzureRole', 'RoleName', '', $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'Reader -> rg-one (inst-001)'|'Reader -> rg-two (inst-002)'|'Contributor'"
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -ParameterFilter { $Activated } -Times 1 -Exactly -Scope It
        }

        It 'offers the bare name when the typed -Scope names one of them' {
            InModuleScope Omnicit.PIM {
                $Completer = [AzureActivatedRoleCompleter]::new()
                $Bound = @{ Scope = '/subscriptions/sub-001/resourceGroups/rg-two' }
                $Result = $Completer.CompleteArgument('Disable-OPIMAzureRole', 'RoleName', '', $null, $Bound)
                (@($Result.CompletionText) -join '|') | Should -Be "'Reader'"
            }
        }
    }

    Context 'When a role name holds an apostrophe or a wildcard character' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole {
                @(
                    [PSCustomObject]@{ RoleDefinitionDisplayName = "O'Brien Reader"; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'Subscription One'; Name = 'inst-004' }
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Reader [Preview]'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'Subscription One'; Name = 'inst-005' }
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Reader X'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'Subscription One'; Name = 'inst-006' }
                )
            } -ParameterFilter { $Activated }
        }

        It 'doubles the apostrophe of the name it offers' {
            InModuleScope Omnicit.PIM {
                $Completer = [AzureActivatedRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMAzureRole', 'RoleName', "'O''Br", $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'O''Brien Reader'"
            }
        }

        It 'takes the brackets of the typed word as plain characters' {
            InModuleScope Omnicit.PIM {
                $Completer = [AzureActivatedRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMAzureRole', 'RoleName', 'Reader [', $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'Reader [Preview]'"
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

    Context 'When a role is eligible at two scopes' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole {
                @(
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Reader'; ScopeId = '/subscriptions/sub-001/resourceGroups/rg-one'; ScopeDisplayName = 'rg-one'; Name = 'azure-001' }
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Reader'; ScopeId = '/subscriptions/sub-001/resourceGroups/rg-two'; ScopeDisplayName = 'rg-two'; Name = 'azure-002' }
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Contributor'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'Subscription One'; Name = 'azure-003' }
                )
            } -ParameterFilter { -not $Activated }
        }

        It 'offers the old forms of that role and the bare name of the other' {
            InModuleScope Omnicit.PIM {
                $Completer = [AzureEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMAzureRole', 'RoleName', '', $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'Reader -> rg-one (azure-001)'|'Reader -> rg-two (azure-002)'|'Contributor'"
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -ParameterFilter { -not $Activated } -Times 1 -Exactly -Scope It
        }

        It 'offers the bare name when the typed -Scope names one of them' {
            InModuleScope Omnicit.PIM {
                $Completer = [AzureEligibleRoleCompleter]::new()
                $Bound = @{ Scope = '/subscriptions/sub-001/resourceGroups/rg-one' }
                $Result = $Completer.CompleteArgument('Enable-OPIMAzureRole', 'RoleName', '', $null, $Bound)
                (@($Result.CompletionText) -join '|') | Should -Be "'Reader'"
            }
        }

        It 'offers every post when Get-OPIMAzureRole is completed with the root scope' {
            InModuleScope Omnicit.PIM {
                $Completer = [AzureEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Get-OPIMAzureRole', 'RoleName', '', $null, @{ Scope = '/' })
                (@($Result.CompletionText) -join '|') | Should -Be "'Reader -> rg-one (azure-001)'|'Reader -> rg-two (azure-002)'|'Contributor'"
            }
        }

        It 'offers no post when Enable-OPIMAzureRole is completed with the root scope' {
            InModuleScope Omnicit.PIM {
                $Completer = [AzureEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMAzureRole', 'RoleName', '', $null, @{ Scope = '/' })
                @($Result).Count | Should -Be 0
            }
        }
    }

    Context 'When a role name holds an apostrophe or a wildcard character' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole {
                @(
                    [PSCustomObject]@{ RoleDefinitionDisplayName = "O'Brien Reader"; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'Subscription One'; Name = 'azure-004' }
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Reader [Preview]'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'Subscription One'; Name = 'azure-005' }
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Reader X'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'Subscription One'; Name = 'azure-006' }
                )
            } -ParameterFilter { -not $Activated }
        }

        It 'doubles the apostrophe of the name it offers' {
            InModuleScope Omnicit.PIM {
                $Completer = [AzureEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMAzureRole', 'RoleName', "'O''Br", $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'O''Brien Reader'"
            }
        }

        It 'takes the brackets of the typed word as plain characters' {
            InModuleScope Omnicit.PIM {
                $Completer = [AzureEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMAzureRole', 'RoleName', 'Reader [', $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'Reader [Preview]'"
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
        It 'offers the bare display name of a role that is unique' {
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
                (@($Result.CompletionText) -join '|') | Should -Be "'User Administrator'"
            }
        }
    }

    Context 'When a role is active at the root scope and in an administrative unit' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole {
                @(
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'User Administrator' }; directoryScopeId = '/'; id = 'inst-001' }
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'User Administrator' }; directoryScopeId = '/administrativeUnits/au-001'; directoryScope = [PSCustomObject]@{ displayName = 'Finance AU' }; id = 'inst-002' }
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Global Reader' }; directoryScopeId = '/'; id = 'inst-003' }
                )
            } -ParameterFilter { $Activated }
        }

        It 'offers the old forms of that role, with the scope display name, and the bare name of the other' {
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryActivatedRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMDirectoryRole', 'RoleName', '', $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'User Administrator (inst-001)'|'User Administrator -> Finance AU (inst-002)'|'Global Reader'"
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -ParameterFilter { $Activated } -Times 1 -Exactly -Scope It
        }

        It 'offers the bare name when the typed -Scope is the root scope' {
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryActivatedRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMDirectoryRole', 'RoleName', '', $null, @{ Scope = '/' })
                (@($Result.CompletionText) -join '|') | Should -Be "'User Administrator'|'Global Reader'"
            }
        }

        It 'offers only the names that start with the typed word' {
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryActivatedRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMDirectoryRole', 'RoleName', "'Global", $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'Global Reader'"
            }
        }
    }

    Context 'When a role name holds an apostrophe or a wildcard character' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole {
                @(
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = "O'Brien Reader" }; directoryScopeId = '/'; id = 'inst-004' }
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Reader [Preview]' }; directoryScopeId = '/'; id = 'inst-005' }
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Reader X' }; directoryScopeId = '/'; id = 'inst-006' }
                )
            } -ParameterFilter { $Activated }
        }

        It 'doubles the apostrophe of the name it offers' {
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryActivatedRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMDirectoryRole', 'RoleName', "'O''Br", $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'O''Brien Reader'"
            }
        }

        It 'takes the brackets of the typed word as plain characters' {
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryActivatedRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMDirectoryRole', 'RoleName', 'Reader [', $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'Reader [Preview]'"
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
        It 'offers the bare display name of a role that is unique' {
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
                (@($Result.CompletionText) -join '|') | Should -Be "'User Administrator'"
            }
        }
    }

    Context 'When a role is eligible at the root scope and in an administrative unit' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole {
                @(
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }; directoryScopeId = '/'; id = 'elig-001' }
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }; directoryScopeId = '/administrativeUnits/au-001'; directoryScope = [PSCustomObject]@{ displayName = 'Sales AU' }; id = 'elig-002' }
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Message Center Privacy Reader' }; directoryScopeId = '/'; id = 'elig-003' }
                )
            } -ParameterFilter { -not $Activated }
        }

        It 'offers the old forms of that role, with the scope display name, and the bare name of the other' {
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMDirectoryRole', 'RoleName', '', $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'Usage Summary Reports Reader (elig-001)'|'Usage Summary Reports Reader -> Sales AU (elig-002)'|'Message Center Privacy Reader'"
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -ParameterFilter { -not $Activated } -Times 1 -Exactly -Scope It
        }

        It 'offers the bare names, without the administrative unit post, when the typed -Scope is the root scope' {
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMDirectoryRole', 'RoleName', '', $null, @{ Scope = '/' })
                (@($Result.CompletionText) -join '|') | Should -Be "'Usage Summary Reports Reader'|'Message Center Privacy Reader'"
            }
        }

        It 'offers the bare name of the administrative unit post when the typed -Scope is its display name' {
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMDirectoryRole', 'RoleName', '', $null, @{ Scope = 'Sales AU' })
                (@($Result.CompletionText) -join '|') | Should -Be "'Usage Summary Reports Reader'"
            }
        }

        It 'offers only the names that start with the typed, quoted word' {
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMDirectoryRole', 'RoleName', "'Message", $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'Message Center Privacy Reader'"
            }
        }
    }

    Context 'When a role name holds an apostrophe or a wildcard character' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole {
                @(
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = "O'Brien Reader" }; directoryScopeId = '/'; id = 'elig-012' }
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Reader [Preview]' }; directoryScopeId = '/'; id = 'elig-013' }
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Reader X' }; directoryScopeId = '/'; id = 'elig-014' }
                )
            } -ParameterFilter { -not $Activated }
        }

        It 'doubles the apostrophe of the name it offers' {
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMDirectoryRole', 'RoleName', "'O''Br", $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'O''Brien Reader'"
            }
        }

        It 'takes the brackets of the typed word as plain characters' {
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMDirectoryRole', 'RoleName', 'Reader [', $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'Reader [Preview]'"
            }
        }

        It 'takes an asterisk in the typed word as a plain character' {
            InModuleScope Omnicit.PIM {
                $Completer = [DirectoryEligibleRoleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMDirectoryRole', 'RoleName', 'Reader*', $null, @{})
                @($Result).Count | Should -Be 0
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

    Context 'When a group is active as member and as owner' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup {
                @(
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'opim-grp' }; accessId = 'member'; id = 'grp-inst-001' }
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'opim-grp' }; accessId = 'owner'; id = 'grp-inst-002' }
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'Finance Team' }; accessId = 'member'; id = 'grp-inst-003' }
                )
            } -ParameterFilter { $Activated }
        }

        It 'offers the bare name of the membership, the old form of the ownership and the bare name of the other group' {
            InModuleScope Omnicit.PIM {
                $Completer = [GroupActivatedCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMEntraIDGroup', 'GroupName', '', $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'opim-grp'|'opim-grp - owner (grp-inst-002)'|'Finance Team'"
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -ParameterFilter { $Activated } -Times 1 -Exactly -Scope It
        }

        It 'offers the bare name of the ownership alone when the typed -AccessType is Owner' {
            InModuleScope Omnicit.PIM {
                $Completer = [GroupActivatedCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMEntraIDGroup', 'GroupName', '', $null, @{ AccessType = 'Owner' })
                (@($Result.CompletionText) -join '|') | Should -Be "'opim-grp'"
            }
        }
    }

    Context 'When a group name holds an apostrophe or a wildcard character' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup {
                @(
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = "O'Brien Team" }; accessId = 'member'; id = 'grp-inst-004' }
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'Team [Preview]' }; accessId = 'member'; id = 'grp-inst-005' }
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'Team X' }; accessId = 'member'; id = 'grp-inst-006' }
                )
            } -ParameterFilter { $Activated }
        }

        It 'doubles the apostrophe of the name it offers' {
            InModuleScope Omnicit.PIM {
                $Completer = [GroupActivatedCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMEntraIDGroup', 'GroupName', "'O''Br", $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'O''Brien Team'"
            }
        }

        It 'takes the brackets of the typed word as plain characters' {
            InModuleScope Omnicit.PIM {
                $Completer = [GroupActivatedCompleter]::new()
                $Result = $Completer.CompleteArgument('Disable-OPIMEntraIDGroup', 'GroupName', 'Team [', $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'Team [Preview]'"
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

    Context 'When a group is eligible as member and as owner' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup {
                @(
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'opim-grp' }; accessId = 'member'; id = 'grp-elig-001' }
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'opim-grp' }; accessId = 'owner'; id = 'grp-elig-002' }
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'Finance Team' }; accessId = 'member'; id = 'grp-elig-003' }
                )
            } -ParameterFilter { -not $Activated }
        }

        It 'offers the bare name of the membership, the old form of the ownership and the bare name of the other group' {
            InModuleScope Omnicit.PIM {
                $Completer = [GroupEligibleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMEntraIDGroup', 'GroupName', '', $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'opim-grp'|'opim-grp - owner (grp-elig-002)'|'Finance Team'"
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -ParameterFilter { -not $Activated } -Times 1 -Exactly -Scope It
        }

        It 'offers the bare name of the ownership alone when the typed -AccessType is Owner' {
            InModuleScope Omnicit.PIM {
                $Completer = [GroupEligibleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMEntraIDGroup', 'GroupName', '', $null, @{ AccessType = 'Owner' })
                (@($Result.CompletionText) -join '|') | Should -Be "'opim-grp'"
            }
        }

        It 'offers only the names that start with the typed, quoted word' {
            InModuleScope Omnicit.PIM {
                $Completer = [GroupEligibleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMEntraIDGroup', 'GroupName', "'Fin", $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'Finance Team'"
            }
        }
    }

    Context 'When a group name holds an apostrophe or a wildcard character' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup {
                @(
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = "O'Brien Team" }; accessId = 'member'; id = 'grp-elig-004' }
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'Team [Preview]' }; accessId = 'member'; id = 'grp-elig-005' }
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'Team X' }; accessId = 'member'; id = 'grp-elig-006' }
                )
            } -ParameterFilter { -not $Activated }
        }

        It 'doubles the apostrophe of the name it offers' {
            InModuleScope Omnicit.PIM {
                $Completer = [GroupEligibleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMEntraIDGroup', 'GroupName', "'O''Br", $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'O''Brien Team'"
            }
        }

        It 'takes the brackets of the typed word as plain characters' {
            InModuleScope Omnicit.PIM {
                $Completer = [GroupEligibleCompleter]::new()
                $Result = $Completer.CompleteArgument('Enable-OPIMEntraIDGroup', 'GroupName', 'Team [', $null, @{})
                (@($Result.CompletionText) -join '|') | Should -Be "'Team [Preview]'"
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

Describe 'The six completer classes' {

    # Each class lists through its own Get-OPIM* call and hands the listing, the pillar and what the
    # engine gave it to Get-OPIMCompletionText. The stand-ins answer with what they were given, so
    # the text of the one completion result shows every argument.
    It 'hands the listing, the pillar, the word, the bound parameters and the command name of <Class> to Get-OPIMCompletionText' -ForEach @(
        @{ Class = 'AzureActivatedRoleCompleter'; Pillar = 'Azure'; Command = 'Disable-OPIMAzureRole'; Listed = 'True' }
        @{ Class = 'AzureEligibleRoleCompleter'; Pillar = 'Azure'; Command = 'Enable-OPIMAzureRole'; Listed = 'False' }
        @{ Class = 'DirectoryActivatedRoleCompleter'; Pillar = 'Directory'; Command = 'Disable-OPIMDirectoryRole'; Listed = 'True' }
        @{ Class = 'DirectoryEligibleRoleCompleter'; Pillar = 'Directory'; Command = 'Enable-OPIMDirectoryRole'; Listed = 'False' }
        @{ Class = 'GroupActivatedCompleter'; Pillar = 'Group'; Command = 'Disable-OPIMEntraIDGroup'; Listed = 'True' }
        @{ Class = 'GroupEligibleCompleter'; Pillar = 'Group'; Command = 'Enable-OPIMEntraIDGroup'; Listed = 'False' }
    ) {
        Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { [PSCustomObject]@{ Activated = [bool]$Activated } }
        Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { [PSCustomObject]@{ Activated = [bool]$Activated } }
        Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { [PSCustomObject]@{ Activated = [bool]$Activated } }
        Mock -ModuleName Omnicit.PIM Get-OPIMCompletionText {
            "'{0}|{1}|{2}|{3}|{4}'" -f $Pillar, $WordToComplete, $CommandName, $FakeBoundParameters['Scope'], (@($InputObject).Activated -join ',')
        }
        $Got = InModuleScope Omnicit.PIM -Parameters @{ Class = $Class; Command = $Command } {
            param($Class, $Command)
            $Completer = switch ($Class) {
                'AzureActivatedRoleCompleter'     { [AzureActivatedRoleCompleter]::new() }
                'AzureEligibleRoleCompleter'      { [AzureEligibleRoleCompleter]::new() }
                'DirectoryActivatedRoleCompleter' { [DirectoryActivatedRoleCompleter]::new() }
                'DirectoryEligibleRoleCompleter'  { [DirectoryEligibleRoleCompleter]::new() }
                'GroupActivatedCompleter'         { [GroupActivatedCompleter]::new() }
                'GroupEligibleCompleter'          { [GroupEligibleCompleter]::new() }
            }
            $Completer.CompleteArgument($Command, 'Name', 'typed', $null, @{ Scope = 'scope-x' }).CompletionText
        }
        @($Got) | Should -Be @("'$Pillar|typed|$Command|scope-x|$Listed'")
    }
}

# The acceptance criterion names TabExpansion2, so these run the real engine: the mocks are scoped
# to the module and the call is made OUTSIDE InModuleScope, as a user's prompt would make it.
Describe 'TabExpansion2' {
    Context 'When a directory role name is completed' {
        BeforeEach {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole {
                @(
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }; directoryScopeId = '/'; id = 'elig-001' }
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }; directoryScopeId = '/administrativeUnits/au-001'; directoryScope = [PSCustomObject]@{ displayName = 'Sales AU' }; id = 'elig-002' }
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Message Center Privacy Reader' }; directoryScopeId = '/'; id = 'elig-003' }
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = "O'Brien Reader" }; directoryScopeId = '/'; id = 'elig-012' }
                )
            } -ParameterFilter { -not $Activated }
        }

        It 'offers the bare name of a unique role and the old forms of an ambiguous one' {
            $Line = 'Enable-OPIMDirectoryRole '
            $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
            (@($Completion.CompletionMatches.CompletionText) -join '|') | Should -Be "'Usage Summary Reports Reader (elig-001)'|'Usage Summary Reports Reader -> Sales AU (elig-002)'|'Message Center Privacy Reader'|'O''Brien Reader'"
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -ParameterFilter { -not $Activated } -Times 1 -Exactly -Scope It
        }

        It 'offers the bare name for a word with an opening quote and a doubled apostrophe' {
            $Line = "Enable-OPIMDirectoryRole -RoleName 'O''Br"
            $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
            (@($Completion.CompletionMatches.CompletionText) -join '|') | Should -Be "'O''Brien Reader'"
        }

        It 'offers the bare name of the role in an administrative unit when -Scope names it' {
            $Line = "Enable-OPIMDirectoryRole -Scope '/administrativeUnits/au-001' -RoleName "
            $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
            (@($Completion.CompletionMatches.CompletionText) -join '|') | Should -Be "'Usage Summary Reports Reader'"
        }

        It 'offers the bare names under the root scope' {
            $Line = 'Enable-OPIMDirectoryRole -Scope / -RoleName '
            $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
            (@($Completion.CompletionMatches.CompletionText) -join '|') | Should -Be "'Usage Summary Reports Reader'|'Message Center Privacy Reader'|'O''Brien Reader'"
        }
    }

    Context 'When an active directory role name is completed' {
        It 'lists the active roles and offers their names' {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole {
                @(
                    [PSCustomObject]@{ roleDefinition = [PSCustomObject]@{ displayName = 'Global Reader' }; directoryScopeId = '/'; id = 'inst-001' }
                )
            } -ParameterFilter { $Activated }
            $Line = 'Disable-OPIMDirectoryRole -RoleName '
            $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
            (@($Completion.CompletionMatches.CompletionText) -join '|') | Should -Be "'Global Reader'"
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -ParameterFilter { $Activated } -Times 1 -Exactly -Scope It
        }
    }

    Context 'When a group name is completed' {
        BeforeEach {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup {
                @(
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'opim-grp' }; accessId = 'member'; id = 'grp-elig-001' }
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'opim-grp' }; accessId = 'owner'; id = 'grp-elig-002' }
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'Finance Team' }; accessId = 'member'; id = 'grp-elig-003' }
                )
            } -ParameterFilter { -not $Activated }
        }

        It 'offers the bare name of the membership and the old form of the ownership' {
            $Line = 'Enable-OPIMEntraIDGroup '
            $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
            (@($Completion.CompletionMatches.CompletionText) -join '|') | Should -Be "'opim-grp'|'opim-grp - owner (grp-elig-002)'|'Finance Team'"
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -ParameterFilter { -not $Activated } -Times 1 -Exactly -Scope It
        }

        It 'offers the bare name of the ownership alone when -AccessType Owner was typed' {
            $Line = 'Enable-OPIMEntraIDGroup -AccessType Owner -GroupName '
            $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
            (@($Completion.CompletionMatches.CompletionText) -join '|') | Should -Be "'opim-grp'"
        }
    }

    Context 'When an active group name is completed' {
        It 'lists the active groups and offers their names' {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup {
                @(
                    [PSCustomObject]@{ group = [PSCustomObject]@{ displayName = 'Finance Team' }; accessId = 'member'; id = 'grp-inst-001' }
                )
            } -ParameterFilter { $Activated }
            $Line = 'Disable-OPIMEntraIDGroup -GroupName '
            $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
            (@($Completion.CompletionMatches.CompletionText) -join '|') | Should -Be "'Finance Team'"
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -ParameterFilter { $Activated } -Times 1 -Exactly -Scope It
        }
    }

    Context 'When an Azure role name is completed' {
        BeforeEach {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole {
                @(
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Reader'; ScopeId = '/subscriptions/sub-001/resourceGroups/rg-one'; ScopeDisplayName = 'rg-one'; Name = 'azure-001' }
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Reader'; ScopeId = '/subscriptions/sub-001/resourceGroups/rg-two'; ScopeDisplayName = 'rg-two'; Name = 'azure-002' }
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Contributor'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'Subscription One'; Name = 'azure-003' }
                )
            } -ParameterFilter { -not $Activated }
        }

        It 'offers the old forms of a role held at two scopes and the bare name of the other' {
            $Line = 'Enable-OPIMAzureRole '
            $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
            (@($Completion.CompletionMatches.CompletionText) -join '|') | Should -Be "'Reader -> rg-one (azure-001)'|'Reader -> rg-two (azure-002)'|'Contributor'"
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -ParameterFilter { -not $Activated } -Times 1 -Exactly -Scope It
        }

        It 'offers the bare name when -Scope names one of the two scopes' {
            $Line = "Enable-OPIMAzureRole -Scope '/subscriptions/sub-001/resourceGroups/rg-one' -RoleName "
            $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
            (@($Completion.CompletionMatches.CompletionText) -join '|') | Should -Be "'Reader'"
        }

        It 'offers every post on Get-OPIMAzureRole, where the root scope filters nothing' {
            $Line = 'Get-OPIMAzureRole -Scope / -RoleName '
            $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
            (@($Completion.CompletionMatches.CompletionText) -join '|') | Should -Be "'Reader -> rg-one (azure-001)'|'Reader -> rg-two (azure-002)'|'Contributor'"
        }
    }

    Context 'When an active Azure role name is completed' {
        It 'lists the active roles and offers their names' {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole {
                @(
                    [PSCustomObject]@{ RoleDefinitionDisplayName = 'Reader'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'Subscription One'; Name = 'inst-001' }
                )
            } -ParameterFilter { $Activated }
            $Line = 'Disable-OPIMAzureRole -RoleName '
            $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
            (@($Completion.CompletionMatches.CompletionText) -join '|') | Should -Be "'Reader'"
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -ParameterFilter { $Activated } -Times 1 -Exactly -Scope It
        }
    }
}
