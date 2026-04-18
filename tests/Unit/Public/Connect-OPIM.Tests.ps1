Describe 'Connect-OPIM' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When called with -TenantId' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
        }

        It 'calls Initialize-OPIMAuth with the supplied TenantId' {
            Connect-OPIM -TenantId 'contoso.onmicrosoft.com'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Scope It -ParameterFilter {
                $TenantId -eq 'contoso.onmicrosoft.com'
            }
        }

        It 'passes -IncludeARM when specified' {
            Connect-OPIM -TenantId 'contoso.onmicrosoft.com' -IncludeARM
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $true
            }
        }
    }

    Context 'When called with -TenantAlias (simple string config)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ contoso = '00000000-0000-0000-0000-000000000001' }
            }
        }

        It 'resolves the TenantId from the TenantMap and calls Initialize-OPIMAuth' {
            Connect-OPIM -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Scope It -ParameterFilter {
                $TenantId -eq '00000000-0000-0000-0000-000000000001'
            }
        }
    }

    Context 'When called with -TenantAlias (hashtable config)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ fabrikam = @{ TenantId = '00000000-0000-0000-0000-000000000002' } }
            }
        }

        It 'resolves the TenantId from the hashtable and calls Initialize-OPIMAuth' {
            Connect-OPIM -TenantAlias 'fabrikam' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Scope It -ParameterFilter {
                $TenantId -eq '00000000-0000-0000-0000-000000000002'
            }
        }
    }

    Context 'When the TenantMap file does not exist' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
        }

        It 'writes a non-terminating error with TenantMapNotFound ErrorId' {
            $Errors = @()
            Connect-OPIM -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\missing.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
            $Errors[0].FullyQualifiedErrorId | Should -BeLike 'TenantMapNotFound*'
        }

        It 'does not call Initialize-OPIMAuth' {
            Connect-OPIM -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\missing.psd1' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }
    }

    Context 'When the TenantAlias is not found in the TenantMap' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ contoso = '00000000-0000-0000-0000-000000000001' }
            }
        }

        It 'writes a non-terminating error with TenantAliasNotFound ErrorId' {
            $Errors = @()
            Connect-OPIM -TenantAlias 'unknown' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
            $Errors[0].FullyQualifiedErrorId | Should -BeLike 'TenantAliasNotFound*'
        }

        It 'does not call Initialize-OPIMAuth' {
            Connect-OPIM -TenantAlias 'unknown' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }
    }
}
