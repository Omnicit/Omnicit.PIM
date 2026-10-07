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

Describe 'Get-OPIMTokenTenantId' {
    Context 'When the token carries a tid claim' {
        It 'returns the tid claim of the token' {
            $Token = New-OPIMTestAccessToken -TenantId 'aaaaaaaa-0000-0000-0000-00000000000a'
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenTenantId -AccessToken $Token
            }
            $Result | Should -Be 'aaaaaaaa-0000-0000-0000-00000000000a'
            $Result | Should -BeOfType [string]
        }

        It 'returns the tid in lower case' {
            $Token = New-OPIMTestAccessToken -TenantId 'AAAAAAAA-0000-0000-0000-00000000000A'
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenTenantId -AccessToken $Token
            }
            $Result | Should -BeExactly 'aaaaaaaa-0000-0000-0000-00000000000a'
        }

        It 'writes nothing to any stream' {
            $Token = New-OPIMTestAccessToken
            $Out = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenTenantId -AccessToken $Token -Verbose *>&1
            }
            @($Out).Count | Should -Be 1
            $Out | Should -BeExactly '11111111-1111-1111-1111-111111111111'
        }
    }

    Context 'When the tenant cannot be read from the value' {
        It 'returns null for a token without a tid claim' {
            $Token = New-OPIMTestAccessToken -NoTenant
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenTenantId -AccessToken $Token
            }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null for a value that is not a JWT' {
            $Result = InModuleScope Omnicit.PIM { Get-OPIMTokenTenantId -AccessToken 'not-a-token' }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null for an empty string' {
            $Result = InModuleScope Omnicit.PIM { Get-OPIMTokenTenantId -AccessToken '' }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null when the payload is not JSON' {
            # bm90IGpzb24 is the base64url of the text 'not json'.
            $Result = InModuleScope Omnicit.PIM {
                Get-OPIMTokenTenantId -AccessToken ('a.' + 'bm90IGpzb24' + '.c') -ErrorAction Stop
            }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null when the payload is not base64url' {
            $Result = InModuleScope Omnicit.PIM {
                Get-OPIMTokenTenantId -AccessToken 'a.%%%%.c' -ErrorAction Stop
            }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null for a tid that is not a GUID' {
            $Token = New-OPIMTestAccessToken -TenantId 'contoso.onmicrosoft.com'
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenTenantId -AccessToken $Token
            }
            $Result | Should -BeNullOrEmpty
        }
    }
}
