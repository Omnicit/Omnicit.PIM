Describe 'Set-OPIMConfiguration' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
        Mock -ModuleName Omnicit.PIM Set-Content { }
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When the TenantMap file does not exist' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Test-Path { return $false }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'does not call Set-Content' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }

    Context 'When the alias does not exist in the file' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    fabrikam = @{ TenantId = '00000000-0000-0000-0000-000000000002' }
                }
            }
        }

        It 'writes a non-terminating error mentioning the alias' {
            $Errors = @()
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
            $Errors[0].Exception.Message | Should -Match 'contoso'
        }

        It 'does not call Set-Content' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }

    Context 'When updating the TenantId for an existing alias' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{ TenantId = '00000000-0000-0000-0000-000000000001' }
                }
            }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'calls Set-Content once' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 1 -Scope It
        }

        It 'writes the new TenantId into the PSD1 content' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match '00000000-0000-0000-0000-000000000099'
        }
    }

    Context 'When a directory role object is piped' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{
                        TenantId       = '00000000-0000-0000-0000-000000000001'
                        DirectoryRoles = @('old-role-def-001')
                    }
                }
            }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }

            $script:dirRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'new-role-def-001'
                directoryScopeId = '/'
            }
            $script:dirRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'replaces the DirectoryRoles list with the piped roleDefinitionId' {
            $script:dirRole | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match 'new-role-def-001'
        }

        It 'removes the old roleDefinitionId from the content' {
            $script:dirRole | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Not -Match 'old-role-def-001'
        }
    }

    Context 'When a group object is piped' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{
                        TenantId      = '00000000-0000-0000-0000-000000000001'
                        EntraIDGroups = @('old-group-001_member')
                    }
                }
            }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }

            $script:groupObj = [PSCustomObject]@{
                id       = 'assign-001'
                groupId  = 'new-group-001'
                accessId = 'member'
            }
            $script:groupObj.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'replaces the EntraIDGroups list with the piped groupId_accessId' {
            $script:groupObj | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match 'new-group-001_member'
        }
    }

    Context 'When an Azure role object is piped' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{
                        TenantId   = '00000000-0000-0000-0000-000000000001'
                        AzureRoles = @('old-azure-elig-001')
                    }
                }
            }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }

            $script:azRole = [PSCustomObject]@{
                Name             = 'new-azure-elig-001'
                RoleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/abc'
                ScopeId          = '/subscriptions/sub-001'
            }
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'replaces the AzureRoles list with the piped schedule Name' {
            $script:azRole | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match 'new-azure-elig-001'
        }
    }

    Context 'When no pipeline input is provided and only TenantId is changed' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{
                        TenantId       = '00000000-0000-0000-0000-000000000001'
                        DirectoryRoles = @('preserved-role-def-001')
                        EntraIDGroups  = @('preserved-group_member')
                        AzureRoles     = @('preserved-azure-001')
                    }
                }
            }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'preserves the existing DirectoryRoles' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match 'preserved-role-def-001'
        }

        It 'preserves the existing EntraIDGroups' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match 'preserved-group_member'
        }

        It 'preserves the existing AzureRoles' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match 'preserved-azure-001'
        }
    }

    Context 'When -WhatIf is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{ TenantId = '00000000-0000-0000-0000-000000000001' }
                }
            }
        }

        It 'does not call Set-Content' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }
}
