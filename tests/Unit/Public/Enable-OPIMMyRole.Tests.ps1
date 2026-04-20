Describe 'Enable-OPIMMyRole' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
        Mock -ModuleName Omnicit.PIM Connect-OPIM {}
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
        It 'calls Connect-OPIM with -IncludeARM when -AllEligible is specified' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $true
            }
        }

        

        It 'calls Get-OPIMDirectoryRole to retrieve eligible directory roles' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 1 -Scope It
        }

        It 'calls Get-OPIMEntraIDGroup to retrieve eligible group assignments' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 1 -Scope It
        }

        It 'calls Get-OPIMAzureRole to retrieve eligible Azure RBAC roles' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Scope It
        }
    }

    Context 'When eligible roles are returned (no TenantAlias)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
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
            Enable-OPIMMyRole -AllEligible -Hours 2 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Scope It
        }

        It 'calls Enable-OPIMEntraIDGroup for each eligible group assignment' {
            Enable-OPIMMyRole -AllEligible -Hours 2 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 1 -Scope It
        }

        It 'calls Enable-OPIMAzureRole for each eligible Azure role' {
            Enable-OPIMMyRole -AllEligible -Hours 2 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 1 -Scope It
        }

        It 'passes -Hours to Enable-OPIMDirectoryRole' {
            Enable-OPIMMyRole -AllEligible -Hours 3 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Scope It -ParameterFilter {
                $Hours -eq 3
            }
        }

        It 'passes -Justification when supplied' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false -Justification 'Incident response'
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Scope It -ParameterFilter {
                $Justification -eq 'Incident response'
            }
        }
    }

    Context 'When called with -TenantAlias (simple string TenantId in TenantMap)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $fakeTenantId = '00000000-0000-0000-0000-000000000001'
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ contoso = $fakeTenantId }
            }
        }

        It 'calls Connect-OPIM with the resolved TenantId' {
            Enable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $TenantId -eq $fakeTenantId
            }
        }

        It 'calls Connect-OPIM without -IncludeARM when config has no AzureRoles' {
            Enable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $false
            }
        }
    }

    Context 'When called with -TenantAlias pointing to a hashtable config with AzureRoles' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
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

        It 'calls Connect-OPIM with the resolved TenantId' {
            Enable-OPIMMyRole -TenantAlias 'fabrikam' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $TenantId -eq $fakeTenantId
            }
        }

        It 'calls Connect-OPIM with -IncludeARM when AzureRoles are configured' {
            Enable-OPIMMyRole -TenantAlias 'fabrikam' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $true
            }
        }
    }

    Context 'When -TenantMapPath does not exist' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
        }

        It 'writes a non-terminating error when the TenantMap file is missing' {
            $Errors = @()
            Enable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\missing.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'does not call Connect-OPIM when the TenantMap file is missing' {
            Enable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\missing.psd1' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 0 -Scope It
        }
    }

    Context 'When -TenantAlias is not found in TenantMap' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ contoso = '00000000-0000-0000-0000-000000000001' }
            }
        }

        It 'writes a non-terminating error when the alias is absent from the TenantMap' {
            $Errors = @()
            Enable-OPIMMyRole -TenantAlias 'unknown' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When no eligible roles or groups are found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @() }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @() }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @() }
        }

        It 'does not call Enable-OPIMDirectoryRole when no directory roles are eligible' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 0 -Scope It
        }

        It 'does not call Enable-OPIMEntraIDGroup when no groups are eligible' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 0 -Scope It
        }

        It 'does not call Enable-OPIMAzureRole when no Azure roles are eligible' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 0 -Scope It
        }
    }

    Context 'When -Wait is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
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
            Enable-OPIMMyRole -AllEligible -Wait -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Scope It -ParameterFilter {
                $Wait -eq $true
            }
        }
    }

    Context 'When called with no TenantAlias and no AllEligible switch' {
        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMMyRole -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'does not call Connect-OPIM' {
            Enable-OPIMMyRole -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 0 -Scope It
        }

        It 'does not call any Enable-OPIM* cmdlet' {
            Enable-OPIMMyRole -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 0 -Scope It
        }
    }

    Context 'When -AllEligible is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeDirectoryRole = [PSCustomObject]@{
                id               = 'elig-all-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe' }
            }
            $FakeDirectoryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            $FakeGroup = [PSCustomObject]@{ id = 'grp-all-001'; groupId = 'group-id-001'; accessId = 'member' }
            $FakeGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
            $FakeAzureRole = [PSCustomObject]@{ Name = 'az-all-001'; Scope = '/subscriptions/sub-001' }
            $FakeAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($FakeDirectoryRole) }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @($FakeGroup) }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($FakeAzureRole) }
        }

        It 'activates all three categories when -Confirm:$false is specified' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 1 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 1 -Scope It
        }

        It 'does not activate any category when -WhatIf is specified' {
            Enable-OPIMMyRole -AllEligible -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 0 -Scope It
        }

        It 'calls Connect-OPIM with -IncludeARM when -AllEligible is used' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $true
            }
        }
    }

    Context 'When -AllEligibleDirectoryRoles is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeDirectoryRole = [PSCustomObject]@{
                id               = 'elig-dr-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Security Reader' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe' }
            }
            $FakeDirectoryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($FakeDirectoryRole) }
        }

        It 'activates only directory roles' {
            Enable-OPIMMyRole -AllEligibleDirectoryRoles -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 0 -Scope It
        }

        It 'calls Connect-OPIM without -IncludeARM' {
            Enable-OPIMMyRole -AllEligibleDirectoryRoles -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $false
            }
        }
    }

    Context 'When -AllEligibleEntraIDGroups is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeGroup = [PSCustomObject]@{ id = 'grp-elig-002'; groupId = 'group-id-002'; accessId = 'owner' }
            $FakeGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @($FakeGroup) }
        }

        It 'activates only Entra ID group assignments' {
            Enable-OPIMMyRole -AllEligibleEntraIDGroups -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 1 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 0 -Scope It
        }

        It 'calls Connect-OPIM without -IncludeARM' {
            Enable-OPIMMyRole -AllEligibleDirectoryRoles -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $false
            }
        }
    }

    Context 'When -AllEligibleAzureRoles is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeAzureRole = [PSCustomObject]@{ Name = 'az-role-002'; Scope = '/subscriptions/sub-002' }
            $FakeAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($FakeAzureRole) }
        }

        It 'activates only Azure RBAC roles' {
            Enable-OPIMMyRole -AllEligibleAzureRoles -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 1 -Scope It
        }

        It 'calls Connect-OPIM with -IncludeARM when -AllEligibleAzureRoles is used' {
            Enable-OPIMMyRole -AllEligibleAzureRoles -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $true
            }
        }
    }

    Context 'When -TenantAlias is used with a hashtable config that has no category lists' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeTenantId = '00000000-0000-0000-0000-000000000003'
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ noconfig = @{ TenantId = $FakeTenantId } }
            }
        }

        It 'does not call Get-OPIMDirectoryRole when no DirectoryRoles are configured' {
            Enable-OPIMMyRole -TenantAlias 'noconfig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 0 -Scope It
        }

        It 'does not call Get-OPIMEntraIDGroup when no EntraIDGroups are configured' {
            Enable-OPIMMyRole -TenantAlias 'noconfig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 0 -Scope It
        }

        It 'does not call Get-OPIMAzureRole when no AzureRoles are configured' {
            Enable-OPIMMyRole -TenantAlias 'noconfig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 0 -Scope It
        }
    }
}
