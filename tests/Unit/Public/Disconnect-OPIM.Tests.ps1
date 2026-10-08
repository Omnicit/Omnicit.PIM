BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Disconnect-OPIM' {
    Context 'When called successfully' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Disconnect-MgGraph {}
            Mock -ModuleName Omnicit.PIM Disconnect-AzAccount {}
        }

        It 'calls Disconnect-MgGraph' {
            Disconnect-OPIM
            Should -Invoke -ModuleName Omnicit.PIM Disconnect-MgGraph -Times 1 -Scope It
        }

        It 'calls Disconnect-AzAccount' {
            Disconnect-OPIM
            Should -Invoke -ModuleName Omnicit.PIM Disconnect-AzAccount -Times 1 -Scope It
        }

        It 'produces no output' {
            $Result = Disconnect-OPIM
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'When Disconnect-MgGraph throws (not connected)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Disconnect-MgGraph { throw 'Not connected' }
            Mock -ModuleName Omnicit.PIM Disconnect-AzAccount {}
        }

        It 'does not produce a terminating error' {
            { Disconnect-OPIM } | Should -Not -Throw
        }

        It 'calls Disconnect-AzAccount as well, despite the Disconnect-MgGraph error' {
            Disconnect-OPIM
            Should -Invoke -ModuleName Omnicit.PIM Disconnect-AzAccount -Times 1 -Scope It
        }
    }

    Context 'When the session signed in with a device code' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Disconnect-MgGraph {}
            Mock -ModuleName Omnicit.PIM Disconnect-AzAccount {}
        }

        It 'clears the remembered device code mode with the auth state' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; DeviceCode = $true }
            }
            Disconnect-OPIM
            Should -Invoke -ModuleName Omnicit.PIM Disconnect-MgGraph -Times 1 -Exactly -Scope It
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState | Should -BeNullOrEmpty
            }
        }
    }
}
