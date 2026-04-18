Describe 'Get-OPIMMsalApplication' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When a cached app exists for the same tenant' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $FakeApp = [PSCustomObject]@{ _FakeId = 'app-001' }
                $script:_OPIMMsalApp = $FakeApp
                $script:_OPIMMsalAppTenantId = 'contoso.onmicrosoft.com'
                Mock Get-MgContext {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMMsalApp = $null
                $script:_OPIMMsalAppTenantId = $null
            }
        }

        It 'returns the cached app without rebuilding' {
            InModuleScope Omnicit.PIM {
                $Result = Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com'
                [object]::ReferenceEquals($Result, $script:_OPIMMsalApp) | Should -Be $true
            }
        }

        It 'does not call Get-MgContext when cache is valid' {
            InModuleScope Omnicit.PIM {
                Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com'
                Should -Invoke Get-MgContext -Times 0 -Scope It
            }
        }
    }

    Context 'When a cached app exists but for a different tenant' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $FakeApp = [PSCustomObject]@{ _FakeId = 'app-old-tenant' }
                $script:_OPIMMsalApp = $FakeApp
                $script:_OPIMMsalAppTenantId = 'old-tenant.onmicrosoft.com'
                Mock Get-MgContext {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMMsalApp = $null
                $script:_OPIMMsalAppTenantId = $null
            }
        }

        It 'attempts to rebuild the app (calls Get-MgContext to load assemblies)' {
            InModuleScope Omnicit.PIM {
                # The builder will fail in unit test environment (no real MSAL build context)
                # We only assert that the cache-hit path was NOT taken (Get-MgContext is called)
                try { Get-OPIMMsalApplication -TenantId 'new-tenant.onmicrosoft.com' } catch {}
                Should -Invoke Get-MgContext -Times 1 -Scope It
            }
        }
    }

    Context 'When no cache exists' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMMsalApp = $null
                $script:_OPIMMsalAppTenantId = $null
                Mock Get-MgContext {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMMsalApp = $null
                $script:_OPIMMsalAppTenantId = $null
            }
        }

        It 'calls Get-MgContext to force-load the MSAL assembly' {
            InModuleScope Omnicit.PIM {
                try { Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com' } catch {}
                Should -Invoke Get-MgContext -Times 1 -Scope It
            }
        }
    }
}
