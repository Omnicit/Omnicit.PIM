Describe 'Enable-OPIMMyRole' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force

        Mock -ModuleName Omnicit.PIM Connect-MgGraph { }
        Mock -ModuleName Omnicit.PIM Connect-AzAccount { }
        Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @() }
        Mock -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole { }
        Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @() }
        Mock -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup { }
        Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @() }
        Mock -ModuleName Omnicit.PIM Enable-OPIMAzureRole { }
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When called without -TenantAlias (uses current MgGraph context)' {
        It 'calls Connect-MgGraph without a TenantId' {
            Enable-OPIMMyRole
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Scope It -ParameterFilter {
                -not $TenantId
            }
        }

        It 'does not call Connect-AzAccount' {
            Enable-OPIMMyRole
            Should -Invoke -ModuleName Omnicit.PIM Connect-AzAccount -Times 0 -Scope It
        }

        It 'calls Get-OPIMDirectoryRole to retrieve eligible directory roles' {
            Enable-OPIMMyRole
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 1 -Scope It
        }

        It 'calls Get-OPIMEntraIDGroup to retrieve eligible group assignments' {
            Enable-OPIMMyRole
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 1 -Scope It
        }

        It 'calls Get-OPIMAzureRole to retrieve eligible Azure RBAC roles' {
            Enable-OPIMMyRole
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Scope It
        }
    }

    Context 'When eligible roles are returned (no TenantAlias)' {
        BeforeAll {
            $fakeDirectoryRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe' }
            }
            $fakeDirectoryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')

            $fakeGroup = [PSCustomObject]@{
                id       = 'grp-elig-001'
                groupId  = 'group-id-001'
                accessId = 'member'
            }
            $fakeGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')

            $fakeAzureRole = [PSCustomObject]@{
                Name  = 'az-role-001'
                Scope = '/subscriptions/sub-001'
            }
            $fakeAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')

            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($fakeDirectoryRole) }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @($fakeGroup) }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($fakeAzureRole) }
        }

        It 'calls Enable-OPIMDirectoryRole for each eligible directory role' {
            Enable-OPIMMyRole -Hours 2
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Scope It
        }

        It 'calls Enable-OPIMEntraIDGroup for each eligible group assignment' {
            Enable-OPIMMyRole -Hours 2
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 1 -Scope It
        }

        It 'calls Enable-OPIMAzureRole for each eligible Azure role' {
            Enable-OPIMMyRole -Hours 2
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 1 -Scope It
        }

        It 'passes -Hours to Enable-OPIMDirectoryRole' {
            Enable-OPIMMyRole -Hours 3
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Scope It -ParameterFilter {
                $Hours -eq 3
            }
        }

        It 'passes -Justification when supplied' {
            Enable-OPIMMyRole -Justification 'Incident response'
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Scope It -ParameterFilter {
                $Justification -eq 'Incident response'
            }
        }
    }

    Context 'When called with -TenantAlias (simple string TenantId in TenantMap)' {
        BeforeAll {
            $fakeTenantId = '00000000-0000-0000-0000-000000000001'
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ contoso = $fakeTenantId }
            }
        }

        It 'calls Connect-MgGraph with the resolved TenantId' {
            Enable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Scope It -ParameterFilter {
                $TenantId -eq $fakeTenantId
            }
        }

        It 'does not call Connect-AzAccount when config has no AzureRoles' {
            Enable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Connect-AzAccount -Times 0 -Scope It
        }
    }

    Context 'When called with -TenantAlias pointing to a hashtable config with AzureRoles' {
        BeforeAll {
            $fakeTenantId = '00000000-0000-0000-0000-000000000002'
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    fabrikam = @{
                        TenantId   = $fakeTenantId
                        AzureRoles = @('Contributor')
                    }
                }
            }
        }

        It 'calls Connect-MgGraph with the resolved TenantId' {
            Enable-OPIMMyRole -TenantAlias 'fabrikam' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Scope It -ParameterFilter {
                $TenantId -eq $fakeTenantId
            }
        }

        It 'calls Connect-AzAccount when AzureRoles are configured' {
            Enable-OPIMMyRole -TenantAlias 'fabrikam' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Connect-AzAccount -Times 1 -Scope It -ParameterFilter {
                $TenantId -eq $fakeTenantId
            }
        }
    }

    Context 'When -TenantMapPath does not exist' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
        }

        It 'throws when the TenantMap file is missing' {
            { Enable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\missing.psd1' } | Should -Throw
        }
    }

    Context 'When -TenantAlias is not found in TenantMap' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ contoso = '00000000-0000-0000-0000-000000000001' }
            }
        }

        It 'throws when the alias is absent from the TenantMap' {
            { Enable-OPIMMyRole -TenantAlias 'unknown' -TenantMapPath 'TestDrive:\TenantMap.psd1' } | Should -Throw
        }
    }

    Context 'When no eligible roles or groups are found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @() }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @() }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @() }
        }

        It 'does not call Enable-OPIMDirectoryRole when no directory roles are eligible' {
            Enable-OPIMMyRole
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 0 -Scope It
        }

        It 'does not call Enable-OPIMEntraIDGroup when no groups are eligible' {
            Enable-OPIMMyRole
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 0 -Scope It
        }

        It 'does not call Enable-OPIMAzureRole when no Azure roles are eligible' {
            Enable-OPIMMyRole
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 0 -Scope It
        }
    }

    Context 'When -Wait is specified' {
        BeforeAll {
            $fakeDirectoryRole = [PSCustomObject]@{
                id               = 'elig-w01'
                roleDefinitionId = 'role-def-w01'
                directoryScopeId = '/'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Security Reader' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe' }
            }
            $fakeDirectoryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($fakeDirectoryRole) }
        }

        It 'passes -Wait to Enable-OPIMDirectoryRole' {
            Enable-OPIMMyRole -Wait
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Scope It -ParameterFilter {
                $Wait -eq $true
            }
        }
    }
}
