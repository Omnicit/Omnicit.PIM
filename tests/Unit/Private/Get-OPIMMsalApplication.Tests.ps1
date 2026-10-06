BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMMsalApplication' {
    Context 'When a cached app exists for the same tenant' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $FakeApp = [PSCustomObject]@{ _FakeId = 'app-001' }
                $script:_OPIMMsalApp = $FakeApp
                $script:_OPIMMsalAppTenantId = 'contoso.onmicrosoft.com'
                # Every Get-MgContext mock in this file throws (R3, held by tests/QA/testhygiene.tests.ps1):
                # past Get-MgContext, Get-OPIMMsalApplication builds a real MSAL application.
                Mock Get-MgContext { throw [System.InvalidOperationException]::new('OPIM test stop: Get-OPIMMsalApplication reached its build path') }
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
                $FakeApp = [PSCustomObject]@{ _FakeId = 'app-fabrikam' }
                $script:_OPIMMsalApp = $FakeApp
                $script:_OPIMMsalAppTenantId = 'fabrikam.onmicrosoft.com'
                Mock Get-MgContext { throw [System.InvalidOperationException]::new('OPIM test stop: Get-OPIMMsalApplication reached its build path') }
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
                # The sentinel proves the cache-hit path was NOT taken and that the call stopped
                # at Get-MgContext, before the MSAL build; the cache is left exactly as it was.
                $Before = $script:_OPIMMsalApp
                $Message = try { Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com'; 'RETURNED' } catch { $_.Exception.Message }
                $Message | Should -BeExactly 'OPIM test stop: Get-OPIMMsalApplication reached its build path'
                Should -Invoke Get-MgContext -Times 1 -Exactly -Scope It
                [object]::ReferenceEquals($script:_OPIMMsalApp, $Before) | Should -BeTrue
                $script:_OPIMMsalApp._FakeId | Should -Be 'app-fabrikam'
                $script:_OPIMMsalAppTenantId | Should -Be 'fabrikam.onmicrosoft.com'
            }
        }
    }

    Context 'When no cache exists' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMMsalApp = $null
                $script:_OPIMMsalAppTenantId = $null
                Mock Get-MgContext { throw [System.InvalidOperationException]::new('OPIM test stop: Get-OPIMMsalApplication reached its build path') }
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
                $Message = try { Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com'; 'RETURNED' } catch { $_.Exception.Message }
                $Message | Should -BeExactly 'OPIM test stop: Get-OPIMMsalApplication reached its build path'
                Should -Invoke Get-MgContext -Times 1 -Exactly -Scope It
                $null -eq $script:_OPIMMsalApp | Should -BeTrue -Because 'the call stopped before the MSAL build, so nothing was cached'
                $null -eq $script:_OPIMMsalAppTenantId | Should -BeTrue
            }
        }
    }
}
