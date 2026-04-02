Describe 'Get-OPIMConfiguration' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
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
            Get-OPIMConfiguration -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'does not return any output' {
            $Result = Get-OPIMConfiguration -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'When the TenantMap file exists with multiple aliases' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{
                        TenantId       = '00000000-0000-0000-0000-000000000001'
                        DirectoryRoles = @('role-def-001', 'role-def-002')
                        EntraIDGroups  = @('group-001_member')
                    }
                    fabrikam = @{
                        TenantId = '00000000-0000-0000-0000-000000000002'
                    }
                }
            }
        }

        It 'returns one object per alias' {
            $Result = Get-OPIMConfiguration -TenantMapPath 'TestDrive:\TenantMap.psd1'
            @($Result).Count | Should -Be 2
        }

        It 'tags each object with the correct TypeName' {
            $Result = Get-OPIMConfiguration -TenantMapPath 'TestDrive:\TenantMap.psd1'
            foreach ($Item in $Result) {
                $Item.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.TenantConfiguration'
            }
        }

        It 'exposes TenantAlias on each object' {
            $Result = Get-OPIMConfiguration -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $Aliases = $Result | Select-Object -ExpandProperty TenantAlias
            $Aliases | Should -Contain 'contoso'
            $Aliases | Should -Contain 'fabrikam'
        }

        It 'exposes TenantId on each object' {
            $Result = Get-OPIMConfiguration -TenantMapPath 'TestDrive:\TenantMap.psd1'
            ($Result | Where-Object TenantAlias -EQ 'contoso').TenantId | Should -Be '00000000-0000-0000-0000-000000000001'
        }

        It 'exposes DirectoryRoles array' {
            $Result = Get-OPIMConfiguration -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $Contoso = $Result | Where-Object TenantAlias -EQ 'contoso'
            $Contoso.DirectoryRoles | Should -Contain 'role-def-001'
            $Contoso.DirectoryRoles | Should -Contain 'role-def-002'
        }

        It 'exposes EntraIDGroups array' {
            $Result = Get-OPIMConfiguration -TenantMapPath 'TestDrive:\TenantMap.psd1'
            ($Result | Where-Object TenantAlias -EQ 'contoso').EntraIDGroups | Should -Contain 'group-001_member'
        }

        It 'returns null AzureRoles when none stored' {
            $Result = Get-OPIMConfiguration -TenantMapPath 'TestDrive:\TenantMap.psd1'
            ($Result | Where-Object TenantAlias -EQ 'fabrikam').AzureRoles | Should -BeNullOrEmpty
        }
    }

    Context 'When -TenantAlias filters to a specific alias' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso  = @{ TenantId = '00000000-0000-0000-0000-000000000001' }
                    fabrikam = @{ TenantId = '00000000-0000-0000-0000-000000000002' }
                }
            }
        }

        It 'returns exactly one object' {
            $Result = Get-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            @($Result).Count | Should -Be 1
        }

        It 'returns the correct alias' {
            $Result = Get-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $Result.TenantAlias | Should -Be 'contoso'
        }
    }

    Context 'When -TenantAlias does not exist in the file' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{ TenantId = '00000000-0000-0000-0000-000000000001' }
                }
            }
        }

        It 'writes a non-terminating error mentioning the alias' {
            $Errors = @()
            Get-OPIMConfiguration -TenantAlias 'nonexistent' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
            $Errors[0].Exception.Message | Should -Match 'nonexistent'
        }

        It 'does not return any output' {
            $Result = Get-OPIMConfiguration -TenantAlias 'nonexistent' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
            $Result | Should -BeNullOrEmpty
        }
    }
}
