Describe 'Remove-OPIMConfiguration' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
        Mock -ModuleName Omnicit.PIM Set-Content { }
        $PSDefaultParameterValues['Remove-OPIMConfiguration:Confirm'] = $false
    }
    AfterAll {
        $null = $PSDefaultParameterValues.Remove('Remove-OPIMConfiguration:Confirm')
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When the TenantMap file does not exist' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $false }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Remove-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'does not call Set-Content' {
            Remove-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }

    Context 'When the alias does not exist in the file' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    fabrikam = @{ TenantId = '00000000-0000-0000-0000-000000000002' }
                }
            }
        }

        It 'writes a non-terminating error mentioning the alias' {
            $Errors = @()
            Remove-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
            $Errors[0].Exception.Message | Should -Match 'contoso'
        }

        It 'does not call Set-Content' {
            Remove-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }

    Context 'When the alias exists and is removed' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso  = @{ TenantId = '00000000-0000-0000-0000-000000000001' }
                    fabrikam = @{ TenantId = '00000000-0000-0000-0000-000000000002' }
                }
            }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'calls Set-Content once' {
            Remove-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 1 -Scope It
        }

        It 'does not include the removed alias in the PSD1 content' {
            Remove-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Not -Match "'contoso'"
        }

        It 'preserves remaining aliases in the PSD1 content' {
            Remove-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match "'fabrikam'"
        }

        It 'preserves the TenantId of remaining aliases' {
            Remove-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match '00000000-0000-0000-0000-000000000002'
        }
    }

    Context 'When -WhatIf is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{ TenantId = '00000000-0000-0000-0000-000000000001' }
                }
            }
        }

        It 'does not call Set-Content' {
            Remove-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }
}
