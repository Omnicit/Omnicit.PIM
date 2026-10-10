BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMConfiguration' {
    Context 'When the TenantMap file does not exist' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
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
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
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
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
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

    Context 'When the tenant map stores clouds (A12)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    usgov    = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Environment = 'USGov'; DirectoryRoles = @('role-def-001|/') }
                    lower    = @{ TenantId = '00000000-0000-0000-0000-000000000002'; Environment = 'usgovdod' }
                    unknown  = @{ TenantId = '00000000-0000-0000-0000-000000000003'; Environment = 'Germany' }
                    nocloud  = @{ TenantId = '00000000-0000-0000-0000-000000000004' }
                    empty    = @{ TenantId = '00000000-0000-0000-0000-000000000005'; Environment = '' }
                    blank    = @{ TenantId = '00000000-0000-0000-0000-000000000099'; Environment = '  ' }
                    oldstyle = '00000000-0000-0000-0000-000000000001'
                }
            }
        }

        It 'returns the stored cloud as Environment' {
            $Result = Get-OPIMConfiguration -TenantMapPath 'TestDrive:\TenantMap.psd1'
            ($Result | Where-Object TenantAlias -EQ 'usgov').Environment | Should -BeExactly 'USGov'
        }

        It 'returns the stored cloud as it is written, also in another letter case and when unknown' {
            # The listing shows what the file holds; it is the sign-in commands that read and refuse a cloud.
            $Result = Get-OPIMConfiguration -TenantMapPath 'TestDrive:\TenantMap.psd1'
            ($Result | Where-Object TenantAlias -EQ 'lower').Environment | Should -BeExactly 'usgovdod'
            ($Result | Where-Object TenantAlias -EQ 'unknown').Environment | Should -BeExactly 'Germany'
        }

        It 'returns Global for an alias without a cloud and for the old string form' {
            $Result = Get-OPIMConfiguration -TenantMapPath 'TestDrive:\TenantMap.psd1'
            ($Result | Where-Object TenantAlias -EQ 'nocloud').Environment | Should -BeExactly 'Global'
            ($Result | Where-Object TenantAlias -EQ 'oldstyle').Environment | Should -BeExactly 'Global'
        }

        It 'returns Global for an alias whose cloud is empty or white space' {
            $Result = Get-OPIMConfiguration -TenantMapPath 'TestDrive:\TenantMap.psd1'
            ($Result | Where-Object TenantAlias -EQ 'empty').Environment | Should -BeExactly 'Global'
            ($Result | Where-Object TenantAlias -EQ 'blank').Environment | Should -BeExactly 'Global'
        }

        It 'puts Environment right after TenantId in the object' {
            $Result = Get-OPIMConfiguration -TenantMapPath 'TestDrive:\TenantMap.psd1' | Select-Object -First 1
            # The count properties after them are the ScriptProperty members of the Types file.
            (@($Result.PSObject.Properties.Name | Select-Object -First 6) -join ',') | Should -BeExactly 'TenantAlias,TenantId,Environment,DirectoryRoles,EntraIDGroups,AzureRoles'
        }

        It 'still tags the object with Omnicit.PIM.TenantConfiguration' {
            $Result = Get-OPIMConfiguration -TenantMapPath 'TestDrive:\TenantMap.psd1'
            foreach ($Item in $Result) {
                $Item.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.PIM.TenantConfiguration'
            }
        }

        It 'returns the stored cloud for -TenantAlias <Alias>' -ForEach @(
            @{ Alias = 'usgov'; Expected = 'USGov' }
            @{ Alias = 'lower'; Expected = 'usgovdod' }
            @{ Alias = 'unknown'; Expected = 'Germany' }
            @{ Alias = 'nocloud'; Expected = 'Global' }
            @{ Alias = 'empty'; Expected = 'Global' }
            @{ Alias = 'oldstyle'; Expected = 'Global' }
        ) {
            $Result = Get-OPIMConfiguration -TenantAlias $Alias -TenantMapPath 'TestDrive:\TenantMap.psd1'
            @($Result).Count | Should -Be 1
            $Result.Environment | Should -BeExactly $Expected
            # The count properties after them are the ScriptProperty members of the Types file.
            (@($Result.PSObject.Properties.Name | Select-Object -First 6) -join ',') | Should -BeExactly 'TenantAlias,TenantId,Environment,DirectoryRoles,EntraIDGroups,AzureRoles'
        }

        It 'shows the cloud in the table view of Omnicit.PIM.TenantConfiguration' {
            $Text = Get-OPIMConfiguration -TenantMapPath 'TestDrive:\TenantMap.psd1' | Where-Object TenantAlias -In 'usgov', 'nocloud' | Out-String -Width 200
            $Header = ($Text -split '\r?\n' | Where-Object { $_ -match 'TenantAlias' } | Select-Object -First 1)
            $Header | Should -Match 'TenantAlias\s+TenantId\s+Environment\s+'
            $Text | Should -Match 'usgov\s+00000000-0000-0000-0000-000000000001\s+USGov\s+'
            $Text | Should -Match 'nocloud\s+00000000-0000-0000-0000-000000000004\s+Global\s+'
        }
    }

    Context 'When the Format file defines the TenantConfiguration view (A12)' {
        BeforeAll {
            $script:FormatXml = [xml](Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../../../source/Formats/Omnicit.PIM.Format.ps1xml'))
            $script:View = $script:FormatXml.Configuration.ViewDefinitions.View | Where-Object { $_.Name -eq 'Omnicit.PIM.TenantConfiguration' }
        }

        It 'has a column header for each of its column items' {
            $script:View | Should -Not -BeNullOrEmpty
            $Headers = @($script:View.TableControl.TableHeaders.TableColumnHeader)
            $Items = @($script:View.TableControl.TableRowEntries.TableRowEntry.TableColumnItems.TableColumnItem)
            $Headers.Count | Should -Be $Items.Count
        }

        It 'lists the columns in order, with Environment after TenantId' {
            $Items = @($script:View.TableControl.TableRowEntries.TableRowEntry.TableColumnItems.TableColumnItem)
            (($Items | ForEach-Object { $_.PropertyName }) -join ',') | Should -BeExactly 'TenantAlias,TenantId,Environment,DirectoryRoleCount,EntraIDGroupCount,AzureRoleCount'
        }
    }

    Context 'When -TenantAlias does not exist in the file' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
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

    Context 'The default -TenantMapPath (OPIM-21)' {
        BeforeAll {
            $Param = (Get-Command Get-OPIMConfiguration).ScriptBlock.Ast.Body.ParamBlock.Parameters |
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
            Get-OPIMConfiguration -ErrorVariable Errs -ErrorAction SilentlyContinue
            $script:SeenPaths | Should -Contain $ExpectedPath
            $Errs[-1].FullyQualifiedErrorId | Should -BeLike 'TenantMapNotFound*'
        }
    }
}
