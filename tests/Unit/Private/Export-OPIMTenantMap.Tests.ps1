BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Export-OPIMTenantMap' {
    Context 'When called with a single entry' {
        It 'calls Set-Content exactly once' {
            InModuleScope Omnicit.PIM {
                Mock Set-Content { }
                $MapData = @{
                    contoso = @{ TenantId = '00000000-0000-0000-0000-000000000001' }
                }
                Export-OPIMTenantMap -MapData $MapData -Path 'TestDrive:\TenantMap.psd1'
                Should -Invoke Set-Content -Times 1 -Scope It
            }
        }

        It 'writes content that contains the tenant alias key' {
            $OutPath = 'TestDrive:\TenantMap_single.psd1'
            InModuleScope Omnicit.PIM -Parameters @{ OutPath = $OutPath } {
                $MapData = @{
                    contoso = @{ TenantId = '00000000-0000-0000-0000-000000000001' }
                }
                Export-OPIMTenantMap -MapData $MapData -Path $OutPath
            }
            Get-Content -Raw -Path $OutPath | Should -Match 'contoso'
        }

        It 'writes content that contains the TenantId value' {
            $OutPath = 'TestDrive:\TenantMap_tenantid.psd1'
            InModuleScope Omnicit.PIM -Parameters @{ OutPath = $OutPath } {
                $MapData = @{
                    contoso = @{ TenantId = '00000000-0000-0000-0000-000000000001' }
                }
                Export-OPIMTenantMap -MapData $MapData -Path $OutPath
            }
            Get-Content -Raw -Path $OutPath | Should -Match '00000000-0000-0000-0000-000000000001'
        }
    }

    Context 'When called with multiple entries' {
        It 'sorts entries alphabetically by key' {
            $OutPath = 'TestDrive:\TenantMap_sorted.psd1'
            InModuleScope Omnicit.PIM -Parameters @{ OutPath = $OutPath } {
                $MapData = @{
                    zebra   = @{ TenantId = '00000000-0000-0000-0000-000000000002' }
                    contoso = @{ TenantId = '00000000-0000-0000-0000-000000000001' }
                }
                Export-OPIMTenantMap -MapData $MapData -Path $OutPath
            }
            $Written = Get-Content -Raw -Path $OutPath
            $ContosoIndex = $Written.IndexOf('contoso')
            $ZebraIndex = $Written.IndexOf('zebra')
            $ContosoIndex | Should -BeGreaterThan -1
            $ZebraIndex | Should -BeGreaterThan -1
            $ContosoIndex | Should -BeLessThan $ZebraIndex
        }
    }

    Context 'When an entry includes optional role arrays' {
        It 'writes DirectoryRoles into the output' {
            $OutPath = 'TestDrive:\TenantMap_roles.psd1'
            InModuleScope Omnicit.PIM -Parameters @{ OutPath = $OutPath } {
                $MapData = @{
                    contoso = @{
                        TenantId       = '00000000-0000-0000-0000-000000000001'
                        DirectoryRoles = @('Global Administrator')
                    }
                }
                Export-OPIMTenantMap -MapData $MapData -Path $OutPath
            }
            $Written = Get-Content -Raw -Path $OutPath
            $Written | Should -Match 'DirectoryRoles'
            $Written | Should -Match 'Global Administrator'
        }
    }

    Context 'When a value holds a single quote (OPIM-26)' {
        It 'writes a file that reads back an apostrophe in the alias and in a value' {
            $OutPath = 'TestDrive:\TenantMap_quote.psd1'
            InModuleScope Omnicit.PIM -Parameters @{ OutPath = $OutPath } {
                $MapData = @{
                    "o'brien" = @{
                        TenantId       = '00000000-0000-0000-0000-000000000001'
                        AzureRoles     = @("elig'az")
                        DirectoryRoles = @("role'x|/")
                        EntraIDGroups  = @("g'1_member")
                    }
                }
                Export-OPIMTenantMap -MapData $MapData -Path $OutPath
            }
            $Read = Import-PowerShellDataFile -Path $OutPath
            $Read.Keys | Should -Be "o'brien"
            $Read["o'brien"].TenantId | Should -BeExactly '00000000-0000-0000-0000-000000000001'
            $Read["o'brien"].AzureRoles | Should -BeExactly "elig'az"
            $Read["o'brien"].DirectoryRoles | Should -BeExactly "role'x|/"
            $Read["o'brien"].EntraIDGroups | Should -BeExactly "g'1_member"
        }

        It 'writes a file that reads back every one of several values that hold a quote' {
            $OutPath = 'TestDrive:\TenantMap_quote_many.psd1'
            InModuleScope Omnicit.PIM -Parameters @{ OutPath = $OutPath } {
                $MapData = @{
                    contoso = @{
                        TenantId   = '00000000-0000-0000-0000-000000000001'
                        AzureRoles = @("a'1", "plain", "b''2")
                    }
                }
                Export-OPIMTenantMap -MapData $MapData -Path $OutPath
            }
            $Read = Import-PowerShellDataFile -Path $OutPath
            @($Read.contoso.AzureRoles).Count | Should -Be 3
            $Read.contoso.AzureRoles[0] | Should -BeExactly "a'1"
            $Read.contoso.AzureRoles[1] | Should -BeExactly 'plain'
            $Read.contoso.AzureRoles[2] | Should -BeExactly "b''2"
        }

        It 'writes a file that reads back the quote <Name> in the alias, the TenantId and every value' -ForEach @(
            @{ Name = 'U+0027'; Code = 0x0027 }
            @{ Name = 'U+2018'; Code = 0x2018 }
            @{ Name = 'U+2019'; Code = 0x2019 }
            @{ Name = 'U+201A'; Code = 0x201A }
            @{ Name = 'U+201B'; Code = 0x201B }
        ) {
            # The tokenizer ends a single-quoted string on all five, so each one has to be doubled.
            # The quote is built with [char] so that this file stays ASCII.
            $Q = [string][char]$Code
            $Alias = "o${Q}brien"
            $TenantIdValue = "tenant${Q}one"
            $DirectoryValue = "role${Q}x|/"
            $GroupValue = "g${Q}1_member"
            $AzureValue = "elig${Q}az"
            $OutPath = 'TestDrive:\TenantMap_quote_{0:X4}.psd1' -f $Code
            InModuleScope Omnicit.PIM -Parameters @{
                OutPath = $OutPath; Alias = $Alias; TenantIdValue = $TenantIdValue
                DirectoryValue = $DirectoryValue; GroupValue = $GroupValue; AzureValue = $AzureValue
            } {
                $MapData = @{
                    $Alias = @{
                        TenantId       = $TenantIdValue
                        DirectoryRoles = @($DirectoryValue)
                        EntraIDGroups  = @($GroupValue)
                        AzureRoles     = @($AzureValue)
                    }
                }
                Export-OPIMTenantMap -MapData $MapData -Path $OutPath
            }
            $Read = Import-PowerShellDataFile -Path $OutPath
            @($Read.Keys).Count | Should -Be 1
            $Read.Keys | Should -BeExactly $Alias
            $Read[$Alias].TenantId | Should -BeExactly $TenantIdValue
            $Read[$Alias].DirectoryRoles | Should -BeExactly $DirectoryValue
            $Read[$Alias].EntraIDGroups | Should -BeExactly $GroupValue
            $Read[$Alias].AzureRoles | Should -BeExactly $AzureValue
        }

        It 'writes a file that reads back a string-form entry with an apostrophe in the alias' {
            $OutPath = 'TestDrive:\TenantMap_quote_string.psd1'
            InModuleScope Omnicit.PIM -Parameters @{ OutPath = $OutPath } {
                $MapData = @{ "o'brien" = '00000000-0000-0000-0000-000000000001' }
                Export-OPIMTenantMap -MapData $MapData -Path $OutPath
            }
            $Read = Import-PowerShellDataFile -Path $OutPath
            $Read.Keys | Should -Be "o'brien"
            $Read["o'brien"].TenantId | Should -BeExactly '00000000-0000-0000-0000-000000000001'
        }

        It 'writes a file that reads back an apostrophe in the TenantId of a string-form entry' {
            $OutPath = 'TestDrive:\TenantMap_quote_stringid.psd1'
            InModuleScope Omnicit.PIM -Parameters @{ OutPath = $OutPath } {
                $MapData = @{ contoso = "tenant'one" }
                Export-OPIMTenantMap -MapData $MapData -Path $OutPath
            }
            $Read = Import-PowerShellDataFile -Path $OutPath
            $Read.contoso.TenantId | Should -BeExactly "tenant'one"
        }

        It 'writes an empty TenantId for an entry that has none' {
            $OutPath = 'TestDrive:\TenantMap_quote_noid.psd1'
            InModuleScope Omnicit.PIM -Parameters @{ OutPath = $OutPath } {
                $MapData = @{ contoso = @{ AzureRoles = @('elig-az') } }
                Export-OPIMTenantMap -MapData $MapData -Path $OutPath
            }
            $Read = Import-PowerShellDataFile -Path $OutPath
            $Read.contoso.TenantId | Should -BeExactly ''
            $Read.contoso.AzureRoles | Should -BeExactly 'elig-az'
        }
    }
}

