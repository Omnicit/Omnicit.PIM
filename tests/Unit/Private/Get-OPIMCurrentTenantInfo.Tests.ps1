BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMCurrentTenantInfo' {
    # OPIM-45: the tenant comes from the module's own sign-in (TokenTenantId in the auth state), never
    # from the Graph context in the process, which another Connect-MgGraph may have started. The
    # Get-MgContext mock answers with another tenant, so a helper that read it would return ...099.
    BeforeAll {
        Mock -ModuleName Omnicit.PIM Get-MgContext {
            [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000099'; Account = 'other@fabrikam.com' }
        }
        Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
            @{ value = @(@{ displayName = 'Contoso Ltd'; id = '00000000-0000-0000-0000-000000000001' }) }
        }
        Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionState { 'Own' }
    }

    AfterEach {
        InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
    }

    Context 'When the module holds a sign-in' {
        BeforeEach {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{
                    TenantId                = 'contoso.onmicrosoft.com'
                    TokenTenantId           = '00000000-0000-0000-0000-000000000001'
                    GraphSessionFingerprint = 'x'
                }
            }
        }

        It 'returns the tenant of the module session, not the Graph context' {
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionState { 'Changed' }
            $Result = InModuleScope Omnicit.PIM { Get-OPIMCurrentTenantInfo }
            $Result.TenantId | Should -BeExactly '00000000-0000-0000-0000-000000000001'
            $Result.DisplayName | Should -BeExactly ''
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMGraphSessionState -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-MgContext -Times 0 -Scope It
        }

        It 'returns the tenant of the module session and no display name when the process holds no Graph session' {
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionState { 'Absent' }
            $Result = InModuleScope Omnicit.PIM { Get-OPIMCurrentTenantInfo }
            $Result.TenantId | Should -BeExactly '00000000-0000-0000-0000-000000000001'
            $Result.DisplayName | Should -BeExactly ''
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMGraphSessionState -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-MgContext -Times 0 -Scope It
        }

        It 'returns the tenant of the module session and no display name when no Graph session was recorded' {
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionState { 'Untracked' }
            $Result = InModuleScope Omnicit.PIM { Get-OPIMCurrentTenantInfo }
            $Result.TenantId | Should -BeExactly '00000000-0000-0000-0000-000000000001'
            $Result.DisplayName | Should -BeExactly ''
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMGraphSessionState -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 0 -Scope It
        }

        It 'reads the display name under the module own session' {
            $Result = InModuleScope Omnicit.PIM { Get-OPIMCurrentTenantInfo }
            $Result.TenantId | Should -BeExactly '00000000-0000-0000-0000-000000000001'
            $Result.DisplayName | Should -BeExactly 'Contoso Ltd'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -eq 'v1.0/organization?$select=displayName,id' -and $Method -eq 'GET' -and $ErrorAction -eq 'Stop'
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-MgContext -Times 0 -Scope It
        }

        It 'reads the display name when the organization id differs only in letter case' {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState['TokenTenantId'] = 'aaaaaaaa-0000-0000-0000-00000000000a' }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                @{ value = @(@{ displayName = 'Contoso Ltd'; id = 'AAAAAAAA-0000-0000-0000-00000000000A' }) }
            }
            $Result = InModuleScope Omnicit.PIM { Get-OPIMCurrentTenantInfo }
            $Result.TenantId | Should -BeExactly 'aaaaaaaa-0000-0000-0000-00000000000a'
            $Result.DisplayName | Should -BeExactly 'Contoso Ltd'
        }

        It 'reads no display name of another tenant' {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                @{ value = @(@{ displayName = 'Fabrikam Ltd'; id = '00000000-0000-0000-0000-000000000099' }) }
            }
            $Result = InModuleScope Omnicit.PIM { Get-OPIMCurrentTenantInfo }
            $Result.TenantId | Should -BeExactly '00000000-0000-0000-0000-000000000001'
            $Result.DisplayName | Should -BeExactly ''
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
        }

        It 'returns an empty display name when the organization lists nothing' {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest { @{ value = @() } }
            $Result = InModuleScope Omnicit.PIM { Get-OPIMCurrentTenantInfo }
            $Result.TenantId | Should -BeExactly '00000000-0000-0000-0000-000000000001'
            $Result.DisplayName | Should -BeExactly ''
        }

        It 'returns an empty display name when the organization call fails, and scrubs the record' {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new('Insufficient privileges to read organization')
            }
            Mock -ModuleName Omnicit.PIM Remove-OPIMErrorRecord { }
            $Result = InModuleScope Omnicit.PIM { Get-OPIMCurrentTenantInfo }
            $Result.TenantId | Should -BeExactly '00000000-0000-0000-0000-000000000001'
            $Result.DisplayName | Should -BeExactly ''
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Remove-OPIMErrorRecord -Times 1 -Exactly -Scope It -ParameterFilter {
                $Record.Exception.Message -eq 'Insufficient privileges to read organization'
            }
        }
    }

    Context 'When the module holds no sign-in' {
        It 'returns no tenant when the module holds no sign-in' {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
            $Result = InModuleScope Omnicit.PIM { Get-OPIMCurrentTenantInfo }
            $Result.TenantId | Should -BeNullOrEmpty
            $Result.DisplayName | Should -BeExactly ''
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMGraphSessionState -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-MgContext -Times 0 -Scope It
        }

        It 'returns no tenant for a state that is not a dictionary' {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = 'TokenTenantId' }
            $Result = InModuleScope Omnicit.PIM { Get-OPIMCurrentTenantInfo }
            $Result.TenantId | Should -BeNullOrEmpty
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-MgContext -Times 0 -Scope It
        }

        It 'returns no tenant for the state that holds only the device code mode' {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = @{ DeviceCode = $true } }
            $Result = InModuleScope Omnicit.PIM { Get-OPIMCurrentTenantInfo }
            $Result.TenantId | Should -BeNullOrEmpty
            $Result.DisplayName | Should -BeExactly ''
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMGraphSessionState -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-MgContext -Times 0 -Scope It
        }
    }
}
