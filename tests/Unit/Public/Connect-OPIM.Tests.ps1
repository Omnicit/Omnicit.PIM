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
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                $TenantId -eq 'contoso.onmicrosoft.com'
            }
        }

        It 'passes -IncludeARM when specified' {
            Connect-OPIM -TenantId 'contoso.onmicrosoft.com' -IncludeARM
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
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

    Context 'When the tenant alias stores a cloud (A12)' {
        # A real tenant map in TestDrive: the alias's cloud is read from the file by the module.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $script:MapPath = Join-Path $TestDrive 'TenantMap-cloud.psd1'
            $MapLines = @(
                '@{'
                "    usgov = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Environment = 'USGov' }"
                "    lower = @{ TenantId = '00000000-0000-0000-0000-000000000002'; Environment = 'usgovdod' }"
                "    plain = @{ TenantId = '00000000-0000-0000-0000-000000000003' }"
                "    empty = @{ TenantId = '00000000-0000-0000-0000-000000000003'; Environment = '' }"
                "    global = @{ TenantId = '00000000-0000-0000-0000-000000000003'; Environment = 'Global' }"
                "    odd = @{ TenantId = '00000000-0000-0000-0000-000000000004'; Environment = 'Germany' }"
                "    oldstyle = '00000000-0000-0000-0000-000000000005'"
                '}'
            )
            [System.IO.File]::WriteAllText($script:MapPath, ($MapLines -join "`n"))
        }
        BeforeEach {
            # A session in another cloud, to show that an alias's cloud does not come from the session.
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = '00000000-0000-0000-0000-000000000099'; TokenTenantId = '00000000-0000-0000-0000-000000000099'; Environment = 'China' }
            }
        }
        AfterEach {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'signs in to the cloud the alias stores' {
            Connect-OPIM -TenantAlias 'usgov' -TenantMapPath $script:MapPath
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                $Environment -ceq 'USGov' -and $TenantId -eq '00000000-0000-0000-0000-000000000001'
            }
        }

        It 'signs in to the canonical name of a cloud stored in another letter case' {
            Connect-OPIM -TenantAlias 'lower' -TenantMapPath $script:MapPath
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                $Environment -ceq 'USGovDoD'
            }
        }

        It 'keeps the other switches with the cloud of the alias' {
            Connect-OPIM -TenantAlias 'usgov' -TenantMapPath $script:MapPath -IncludeARM -DeviceCode
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                $Environment -ceq 'USGov' -and $IncludeARM -and $DeviceCode
            }
        }

        It 'signs in to Global for an alias that stores no cloud, whatever the session''s cloud' -ForEach @(
            @{ Alias = 'plain' }
            @{ Alias = 'empty' }
            @{ Alias = 'global' }
            @{ Alias = 'oldstyle' }
        ) {
            Connect-OPIM -TenantAlias $Alias -TenantMapPath $script:MapPath
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                $PesterBoundParameters.ContainsKey('Environment') -and $Environment -ceq 'Global'
            }
        }

        It 'lets -Environment override the alias''s cloud' -ForEach @(
            @{ Alias = 'usgov'; Named = 'China'; Expected = 'China' }
            @{ Alias = 'usgov'; Named = 'Global'; Expected = 'Global' }
            @{ Alias = 'plain'; Named = 'USGov'; Expected = 'USGov' }
            @{ Alias = 'odd'; Named = 'USGov'; Expected = 'USGov' }
        ) {
            Connect-OPIM -TenantAlias $Alias -TenantMapPath $script:MapPath -Environment $Named -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                $Environment -ceq $Expected
            }
        }

        It 'passes the cloud it is given as typed when -Environment overrides the alias' {
            Connect-OPIM -TenantAlias 'usgov' -TenantMapPath $script:MapPath -Environment china
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                $Environment -ceq 'china'
            }
        }

        It 'refuses an alias with an unknown cloud and signs in nothing' {
            Connect-OPIM -TenantAlias 'odd' -TenantMapPath $script:MapPath -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -BeGreaterThan 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'Connect-OPIM'
            $Errs[-1].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidArgument)
            $Errs[-1].TargetObject | Should -BeExactly 'odd'
            $Errs[-1].Exception.Message | Should -Match "Tenant alias 'odd'"
            $Errs[-1].Exception.Message | Should -Match "the cloud 'Germany'"
            $Errs[-1].Exception.Message | Should -Match 'Use Global, USGov, USGovDoD or China'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }

        It 'names the tenant map in the message of the refusal' {
            Connect-OPIM -TenantAlias 'odd' -TenantMapPath $script:MapPath -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].Exception.Message | Should -BeLike "*in '$($script:MapPath)' names the cloud*"
        }

        It 'writes the refusal once to the error stream' {
            $Out = Connect-OPIM -TenantAlias 'odd' -TenantMapPath $script:MapPath -ErrorAction Continue 2>&1
            @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 1
        }

        It 'scrubs the record first and ends with the Stop error preference too' {
            Mock -ModuleName Omnicit.PIM Remove-OPIMErrorRecord { }
            { Connect-OPIM -TenantAlias 'odd' -TenantMapPath $script:MapPath -ErrorAction Stop } | Should -Throw
            Should -Invoke -ModuleName Omnicit.PIM Remove-OPIMErrorRecord -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }

        It 'does not read the stored cloud of an alias when no alias is named' {
            Connect-OPIM -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath $script:MapPath
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                -not $PesterBoundParameters.ContainsKey('Environment')
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
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
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
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
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
