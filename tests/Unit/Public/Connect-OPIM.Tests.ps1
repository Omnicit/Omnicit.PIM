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

    Context 'When called with -Environment (OPIM-29)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
        }

        It 'passes -Environment on to Initialize-OPIMAuth when it is given' {
            Connect-OPIM -TenantId 'contoso.onmicrosoft.com' -Environment USGov
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                $Environment -eq 'USGov' -and $TenantId -eq 'contoso.onmicrosoft.com'
            }
        }

        It 'passes the cloud it is given as typed, for Initialize-OPIMAuth to resolve' {
            Connect-OPIM -TenantId 'contoso.onmicrosoft.com' -Environment usgovdod
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                $Environment -ceq 'usgovdod'
            }
        }

        It 'passes -Environment Global on when it is given, so a sovereign session is left' {
            Connect-OPIM -TenantId 'contoso.onmicrosoft.com' -Environment Global
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                $PesterBoundParameters.ContainsKey('Environment') -and $Environment -eq 'Global'
            }
        }

        It 'passes no Environment when it is not given, so the session keeps its cloud' {
            # OPIM-29: Initialize-OPIMAuth keeps the session's cloud for the session's tenant only when the
            # call names none. Connect-OPIM must never name Global on its own.
            Connect-OPIM -TenantId 'contoso.onmicrosoft.com'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It -ParameterFilter {
                $PesterBoundParameters.ContainsKey('Environment')
            }
        }

        It 'passes no Environment when it is not given, also with the other switches' {
            Connect-OPIM -TenantId 'contoso.onmicrosoft.com' -IncludeARM -DeviceCode
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                $IncludeARM -and $DeviceCode -and -not $PesterBoundParameters.ContainsKey('Environment')
            }
        }

        It 'keeps -Environment the last parameter, after -DeviceCode, so no position moves' {
            $Names = @((Get-Command Connect-OPIM).ScriptBlock.Ast.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $Names[-1] | Should -BeExactly 'Environment'
            $Names[-2] | Should -BeExactly 'DeviceCode'
        }

        It 'refuses an unknown -Environment at binding, before the command runs' {
            # The mocked Initialize-OPIMAuth carries the same ValidateSet, so it would refuse the value too,
            # and an error from there looks the same. An alias with no map file tells them apart: if
            # Connect-OPIM's own ValidateSet is missing, its body runs and looks for the map file.
            Mock -ModuleName Omnicit.PIM Test-Path { $false } -ParameterFilter { $Path -like '*.psd1' }
            $Caught = $null
            try {
                Connect-OPIM -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\missing.psd1' -Environment Germany -ErrorAction SilentlyContinue
            } catch {
                $Caught = $PSItem
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'ParameterArgumentValidationError,Connect-OPIM'
            Should -Invoke -ModuleName Omnicit.PIM Test-Path -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
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
