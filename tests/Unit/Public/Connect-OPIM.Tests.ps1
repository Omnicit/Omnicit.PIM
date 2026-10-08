BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Connect-OPIM' {
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

        It 'passes -DeviceCode to Initialize-OPIMAuth when specified' {
            Connect-OPIM -TenantId 'contoso.onmicrosoft.com' -DeviceCode
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                $DeviceCode -eq $true -and $TenantId -eq 'contoso.onmicrosoft.com'
            }
        }

        It 'does not ask for device code mode without -DeviceCode' {
            Connect-OPIM -TenantId 'contoso.onmicrosoft.com'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                -not $DeviceCode
            }
        }

        It 'passes no tenant to Initialize-OPIMAuth when none is given, so the session keeps its own' {
            # OPIM-07: an empty -TenantId keeps the signed-in tenant; Connect-OPIM must never send
            # 'organizations' on its own.
            Connect-OPIM
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                [string]::IsNullOrEmpty($TenantId)
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

        It 'passes -DeviceCode with the resolved TenantId' {
            Connect-OPIM -TenantAlias 'fabrikam' -TenantMapPath 'TestDrive:\TenantMap.psd1' -DeviceCode
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                $DeviceCode -eq $true -and $TenantId -eq '00000000-0000-0000-0000-000000000002'
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

    Context 'The default -TenantMapPath (OPIM-21)' {
        BeforeAll {
            $Param = (Get-Command Connect-OPIM).ScriptBlock.Ast.Body.ParamBlock.Parameters |
                Where-Object { $_.Name.VariablePath.UserPath -eq 'TenantMapPath' }
            $DefaultText = $Param.DefaultValue.Extent.Text
            $ExpectedPath = if ($IsWindows) {
                "$env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1"
            } else {
                "$HOME/.config/Omnicit.PIM/TenantMap.psd1"
            }
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { $script:SeenPaths.Add($Path); $false }
        }
        BeforeEach {
            $script:SeenPaths = [System.Collections.Generic.List[string]]::new()
        }

        It 'builds the default from $HOME' {
            $Param | Should -Not -BeNullOrEmpty
            $DefaultText | Should -BeExactly "(Join-Path `$HOME '.config/Omnicit.PIM/TenantMap.psd1')"
        }

        It 'gives the same path as before on Windows and a path under $HOME elsewhere' {
            $Actual = & ([scriptblock]::Create($DefaultText))
            $Actual | Should -BeExactly $ExpectedPath
        }

        It 'reads that path when -TenantMapPath is not given' {
            Connect-OPIM -TenantAlias 'contoso' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $script:SeenPaths | Should -Contain $ExpectedPath
            $Errs[-1].FullyQualifiedErrorId | Should -BeLike 'TenantMapNotFound*'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }
    }
}
