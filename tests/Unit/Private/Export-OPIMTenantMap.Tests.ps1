Describe 'Export-OPIMTenantMap' {
    BeforeAll {
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

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
}

