Describe 'Resolve-RoleByName' {
    BeforeAll {
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When -AD is specified and a matching role exists' {
        It 'calls Get-OPIMDirectoryRole to resolve the schedule' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMDirectoryRole {
                    [PSCustomObject]@{ id = 'abc-123'; roleDefinition = [PSCustomObject]@{ displayName = 'Global Administrator' } }
                }
                Resolve-RoleByName -RoleName 'Global Administrator (abc-123)' -AD
                Should -Invoke Get-OPIMDirectoryRole -Times 1 -Scope It
            }
        }

        It 'returns the role whose id matches the extracted schedule id' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMDirectoryRole {
                    [PSCustomObject]@{ id = 'abc-123'; roleDefinition = [PSCustomObject]@{ displayName = 'Global Administrator' } }
                }
                $result = Resolve-RoleByName -RoleName 'Global Administrator (abc-123)' -AD
                $result.id | Should -Be 'abc-123'
            }
        }
    }

    Context 'When -Group is specified and a matching group exists' {
        It 'calls Get-OPIMEntraIDGroup to resolve the schedule' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMEntraIDGroup {
                    [PSCustomObject]@{ id = 'grp-001'; displayName = 'Security Admins' }
                }
                Resolve-RoleByName -RoleName 'Security Admins (grp-001)' -Group
                Should -Invoke Get-OPIMEntraIDGroup -Times 1 -Scope It
            }
        }

        It 'returns the group whose id matches the extracted schedule id' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMEntraIDGroup {
                    [PSCustomObject]@{ id = 'grp-001'; displayName = 'Security Admins' }
                }
                $result = Resolve-RoleByName -RoleName 'Security Admins (grp-001)' -Group
                $result.id | Should -Be 'grp-001'
            }
        }
    }

    Context 'When neither -AD nor -Group is specified (Azure RBAC default)' {
        It 'calls Get-OPIMAzureRole to resolve the schedule' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMAzureRole {
                    [PSCustomObject]@{ Name = 'azure-001'; displayName = 'Contributor' }
                }
                Resolve-RoleByName -RoleName 'Contributor (azure-001)'
                Should -Invoke Get-OPIMAzureRole -Times 1 -Scope It
            }
        }

        It 'returns the role whose Name matches the extracted schedule id' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMAzureRole {
                    [PSCustomObject]@{ Name = 'azure-001'; displayName = 'Contributor' }
                }
                $result = Resolve-RoleByName -RoleName 'Contributor (azure-001)'
                $result.Name | Should -Be 'azure-001'
            }
        }
    }

    Context 'When -Activated is specified' {
        It 'passes -Activated to the underlying Get-OPIMDirectoryRole call' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMDirectoryRole {
                    [PSCustomObject]@{ id = 'abc-123' }
                }
                Resolve-RoleByName -RoleName 'Global Administrator (abc-123)' -AD -Activated
                Should -Invoke Get-OPIMDirectoryRole -Times 1 -Scope It -ParameterFilter { $Activated -eq $true }
            }
        }
    }

    Context 'When RoleName is null' {
        It 'throws indicating null RoleName is a bug' {
            InModuleScope Omnicit.PIM {
                { Resolve-RoleByName -RoleName $null } | Should -Throw '*RoleName was null*'
            }
        }
    }

    Context 'When no role matching the schedule ID is found' {
        It 'throws mentioning the schedule ID was not found' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMDirectoryRole { return @() }
                { Resolve-RoleByName -RoleName 'Global Administrator (abc-123)' -AD } |
                    Should -Throw '*was not found*'
            }
        }
    }

    Context 'When multiple roles share the same schedule ID' {
        It 'throws mentioning multiple roles were found' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMDirectoryRole {
                    @(
                        [PSCustomObject]@{ id = 'abc-123' },
                        [PSCustomObject]@{ id = 'abc-123' }
                    )
                }
                { Resolve-RoleByName -RoleName 'Global Administrator (abc-123)' -AD } |
                    Should -Throw '*Multiple roles found*'
            }
        }
    }
}
