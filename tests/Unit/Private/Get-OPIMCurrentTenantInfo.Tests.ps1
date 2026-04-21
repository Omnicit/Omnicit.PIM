Describe 'Get-OPIMCurrentTenantInfo' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When connected and the organization call succeeds' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-MgContext {
                return [PSCustomObject]@{
                    TenantId = 'aaaaaaaa-0000-0000-0000-000000000001'
                    Account  = 'user@contoso.com'
                }
            }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{
                    value = @(
                        @{ displayName = 'Contoso Ltd'; id = 'aaaaaaaa-0000-0000-0000-000000000001' }
                    )
                }
            }
        }

        It 'returns the TenantId from the Graph context' {
            InModuleScope Omnicit.PIM {
                $Result = Get-OPIMCurrentTenantInfo
                $Result.TenantId | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
            }
        }

        It 'returns the DisplayName from the organization API' {
            InModuleScope Omnicit.PIM {
                $Result = Get-OPIMCurrentTenantInfo
                $Result.DisplayName | Should -Be 'Contoso Ltd'
            }
        }
    }

    Context 'When connected but the organization call fails' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-MgContext {
                return [PSCustomObject]@{
                    TenantId = 'bbbbbbbb-0000-0000-0000-000000000002'
                    Account  = 'user@fabrikam.com'
                }
            }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to read organization"}}'
                )
            }
        }

        It 'returns the TenantId from the Graph context' {
            InModuleScope Omnicit.PIM {
                $Result = Get-OPIMCurrentTenantInfo
                $Result.TenantId | Should -Be 'bbbbbbbb-0000-0000-0000-000000000002'
            }
        }

        It 'returns an empty DisplayName' {
            InModuleScope Omnicit.PIM {
                $Result = Get-OPIMCurrentTenantInfo
                $Result.DisplayName | Should -BeNullOrEmpty
            }
        }

        It 'does not throw' {
            InModuleScope Omnicit.PIM {
                { Get-OPIMCurrentTenantInfo } | Should -Not -Throw
            }
        }
    }

    Context 'When not connected to Graph' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-MgContext { return $null }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest { }
        }

        It 'returns a null TenantId' {
            InModuleScope Omnicit.PIM {
                $Result = Get-OPIMCurrentTenantInfo
                $Result.TenantId | Should -BeNullOrEmpty
            }
        }

        It 'returns a null DisplayName' {
            InModuleScope Omnicit.PIM {
                $Result = Get-OPIMCurrentTenantInfo
                $Result.DisplayName | Should -BeNullOrEmpty
            }
        }

        It 'does not call Invoke-MgGraphRequest' {
            InModuleScope Omnicit.PIM {
                Get-OPIMCurrentTenantInfo
            }
            Should -Invoke Invoke-MgGraphRequest -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }
}
