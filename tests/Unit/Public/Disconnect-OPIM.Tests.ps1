BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OPIMTestToken.ps1"
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Disconnect-OPIM' {
    Context 'When called successfully' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Disconnect-MgGraph {}
        }

        It 'calls Disconnect-MgGraph once' {
            Disconnect-OPIM
            Should -Invoke -ModuleName Omnicit.PIM Disconnect-MgGraph -Times 1 -Exactly -Scope It
        }

        It 'produces no output' {
            $Result = Disconnect-OPIM
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'When Disconnect-MgGraph throws (not connected)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Disconnect-MgGraph { throw 'Not connected' }
        }

        It 'does not produce a terminating error' {
            { Disconnect-OPIM } | Should -Not -Throw
        }

        It 'clears the auth state despite the Disconnect-MgGraph error' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com' }
            }
            Disconnect-OPIM
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState | Should -BeNullOrEmpty
            }
        }
    }

    Context 'When the session holds an Azure Resource Manager token' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Disconnect-MgGraph {}
        }

        It 'clears the ARM token with the auth state, and the MSAL application with its tenant' {
            $Token = New-OPIMTestAccessToken -TenantId '22222222-2222-2222-2222-222222222222' -ObjectId '33333333-3333-3333-3333-333333333333'
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    TokenTenantId    = '22222222-2222-2222-2222-222222222222'
                    ObjectId         = '33333333-3333-3333-3333-333333333333'
                    ArmToken         = [System.Net.NetworkCredential]::new('', $Token).SecurePassword
                    ArmTokenExpiry   = [DateTime]::UtcNow.AddHours(1)
                    ArmTokenTenantId = '22222222-2222-2222-2222-222222222222'
                    ArmTokenObjectId = '33333333-3333-3333-3333-333333333333'
                    ArmResourceUrl   = 'https://management.azure.com'
                }
                $script:_OPIMMsalApp = [pscustomobject]@{ Name = 'msal-application-stand-in' }
                $script:_OPIMMsalAppTenantId = 'contoso.onmicrosoft.com'
            }

            Disconnect-OPIM

            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState | Should -BeNullOrEmpty
                $script:_OPIMMsalApp | Should -BeNullOrEmpty
                $script:_OPIMMsalAppTenantId | Should -BeNullOrEmpty
            }
            Should -Invoke -ModuleName Omnicit.PIM Disconnect-MgGraph -Times 1 -Exactly -Scope It
        }
    }

    Context 'When the cached MSAL application was built for a sovereign cloud (OPIM-29)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Disconnect-MgGraph {}
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMMsalApp = $null
                $script:_OPIMMsalAppTenantId = $null
                $script:_OPIMMsalAppEnvironment = $null
            }
        }

        It 'clears the cloud of the cached MSAL app' {
            # The cloud belongs to the application with its tenant; left behind, it would key the next
            # application's cache on the old cloud.
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; Environment = 'USGov' }
                $script:_OPIMMsalApp = [pscustomobject]@{ Name = 'msal-application-stand-in' }
                $script:_OPIMMsalAppTenantId = 'contoso.onmicrosoft.com'
                $script:_OPIMMsalAppEnvironment = 'USGov'
            }

            Disconnect-OPIM

            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState | Should -BeNullOrEmpty
                $script:_OPIMMsalApp | Should -BeNullOrEmpty
                $script:_OPIMMsalAppTenantId | Should -BeNullOrEmpty
                $script:_OPIMMsalAppEnvironment | Should -BeNullOrEmpty
            }
            Should -Invoke -ModuleName Omnicit.PIM Disconnect-MgGraph -Times 1 -Exactly -Scope It
        }
    }

    Context 'When the session signed in with a device code' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Disconnect-MgGraph {}
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

    Context 'Its definition' {
        It 'names and calls no Az command, in its help or its code' {
            # AzAuth's Get-AzToken is no Az command: AzAuth is not one of the Az modules.
            $Definition = (Get-Command -Name Disconnect-OPIM -Module Omnicit.PIM).Definition
            $Definition | Should -Not -Match '\b[A-Z][a-z]+-Az(?!ure|Token\b)[A-Za-z]+'
            $Definition | Should -Not -Match 'Az\.Accounts|Az context|Az module'
        }

        It 'says in its help that the Azure Resource Manager token is cleared with the auth state' {
            $Help = (Get-Command -Name Disconnect-OPIM -Module Omnicit.PIM).ScriptBlock.Ast.GetHelpContent()
            $Help.Description | Should -Match 'Azure Resource Manager token'
        }
    }
}
