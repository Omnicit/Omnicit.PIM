BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OPIMTestToken.ps1"

    # Two tenants for the tenant-pin tests. Letter-repeat placeholders: neither is a version-4 id.
    $TenantA = 'aaaaaaaa-0000-0000-0000-00000000000a'
    $TenantB = 'bbbbbbbb-0000-0000-0000-00000000000b'

    # An auth state as Initialize-OPIMAuth writes it after a Graph sign-in, in device code mode so the
    # tests drive the acquisition through the Invoke-OPIMDeviceCodeAuth mock.
    function New-PinState {
        param(
            [string]$TenantId,
            [string]$TokenTenantId,
            [string]$AuthorityTenant,
            [switch]$Expired
        )
        @{
            TenantId         = $TenantId
            TokenTenantId    = $TokenTenantId
            AuthorityTenant  = $AuthorityTenant
            Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
            GraphTokenExpiry = if ($Expired) { [DateTime]::UtcNow.AddMinutes(-1) } else { [DateTime]::UtcNow.AddHours(1) }
            ClaimsSatisfied  = $false
            DeviceCode       = $true
        }
    }
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Initialize-OPIMAuth' {
    Context 'When auth state is already cached for the same tenant with a valid token' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = $null
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $true
                }
                Mock Get-OPIMMsalApplication {}
                Mock Connect-MgGraph {}
                Mock Connect-AzAccount {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'returns without acquiring a new token (idempotent)' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com'
                Should -Invoke Get-OPIMMsalApplication -Times 0 -Scope It
            }
        }

        It 'does not call Connect-MgGraph' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com'
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
            }
        }
    }

    Context 'When auth state is expired' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $FakeAccount = [PSCustomObject]@{ Username = 'user@contoso.com' }
                $FakeResult  = [PSCustomObject]@{
                    AccessToken = 'fake-graph-token'
                    ExpiresOn   = [DateTimeOffset]::UtcNow.AddHours(1)
                    Account     = $FakeAccount
                }
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = $FakeAccount
                    GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(-1)  # expired
                    ClaimsSatisfied  = $true
                }

                # Build a fake MSAL app that returns fake tokens via reflection-like mocks
                $FakeSilentBuilder = [PSCustomObject]@{}
                Add-Member -InputObject $FakeSilentBuilder -MemberType ScriptMethod -Name 'WithAccount'      -Value { return $this }
                Add-Member -InputObject $FakeSilentBuilder -MemberType ScriptMethod -Name 'WithForceRefresh' -Value { return $this }
                Add-Member -InputObject $FakeSilentBuilder -MemberType ScriptMethod -Name 'ExecuteAsync'     -Value { return $using:FakeResult }

                $FakeMsalApp = [PSCustomObject]@{}
                Add-Member -InputObject $FakeMsalApp -MemberType ScriptMethod -Name 'AcquireTokenSilent' -Value {
                    param($Scopes, $Account)
                    return $using:FakeSilentBuilder
                }

                Mock Get-OPIMMsalApplication { return $FakeMsalApp }
                Mock Connect-MgGraph {}
                Mock Connect-AzAccount {}
                Mock ConvertTo-SecureString { return [System.Security.SecureString]::new() }
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'calls Get-OPIMMsalApplication to get a fresh token' {
            InModuleScope Omnicit.PIM {
                # AcquireTokenSilent will throw in unit test context (PSCustomObject GetMethods()
                # won't find MSAL methods); the function falls through to interactive which also
                # throws. We only verify that the MSAL app entry point was reached.
                try { Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' } catch {}
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Scope It
            }
        }
    }

    Context 'When no auth state exists (first use)' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $FakeMsalApp = [PSCustomObject]@{}
                Add-Member -InputObject $FakeMsalApp -MemberType ScriptMethod -Name 'AcquireTokenSilent' -Value {
                    param($Scopes, $Account)
                    throw [System.Exception]::new('MsalUiRequiredException: UI required')
                }
                Mock Get-OPIMMsalApplication { return $FakeMsalApp }
                Mock Invoke-OPIMDeviceCodeAuth {}
                Mock Connect-MgGraph {}
                Mock Connect-AzAccount {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'calls Get-OPIMMsalApplication' {
            InModuleScope Omnicit.PIM {
                try { Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' } catch {}
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Scope It
            }
        }

        It 'does not use the device code flow without -DeviceCode' {
            InModuleScope Omnicit.PIM {
                try { Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' } catch {}
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 0 -Scope It
            }
        }

        It 'uses organizations as default tenant when no TenantId given' {
            InModuleScope Omnicit.PIM {
                try { Initialize-OPIMAuth } catch {}
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Scope It -ParameterFilter {
                    $TenantId -eq 'organizations'
                }
            }
        }
    }

    Context 'When -ForceRefresh is set and a valid token is already cached' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)  # still valid
                    ClaimsSatisfied  = $false
                }
                $FakeMsalApp = [PSCustomObject]@{}
                Add-Member -InputObject $FakeMsalApp -MemberType ScriptMethod -Name 'AcquireTokenSilent' -Value {
                    param($Scopes, $Account)
                    throw [System.Exception]::new('MsalUiRequiredException: UI required')
                }
                Mock Get-OPIMMsalApplication { return $FakeMsalApp }
                Mock Connect-MgGraph {}
                Mock Connect-AzAccount {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'bypasses the cache and re-acquires a token' {
            InModuleScope Omnicit.PIM {
                # The cached token is valid, so without -ForceRefresh the call would short-circuit
                # and never touch the MSAL app. -ForceRefresh must force re-acquisition.
                try { Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -ForceRefresh } catch {}
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Scope It
            }
        }
    }

    Context 'When -IncludeARM and Graph token is cached but Azure is not connected' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $false
                }
                Mock Get-AzContext { return $null }
                Mock Update-AzConfig {}
                Mock Connect-AzAccount {}
                Mock Get-OPIMMsalApplication {}
                Mock Connect-MgGraph {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'calls Connect-AzAccount to establish Azure connection' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM
                Should -Invoke Connect-AzAccount -Times 1 -Scope It
            }
        }

        It 'does not call Get-OPIMMsalApplication when Graph token is still valid' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM
                Should -Invoke Get-OPIMMsalApplication -Times 0 -Scope It
            }
        }

        It 'passes -Tenant to Connect-AzAccount when tenant is not organizations' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM
                Should -Invoke Connect-AzAccount -Times 1 -Scope It -ParameterFilter {
                    $Tenant -eq 'contoso.onmicrosoft.com'
                }
            }
        }

        It 'does not pass -Tenant to Connect-AzAccount when tenant is organizations' {
            InModuleScope Omnicit.PIM {
                # Temporarily update state to match 'organizations' tenant
                $script:_OPIMAuthState.TenantId = 'organizations'
                Initialize-OPIMAuth -IncludeARM
                $script:_OPIMAuthState.TenantId = 'contoso.onmicrosoft.com'
                Should -Invoke Connect-AzAccount -Times 1 -Scope It -ParameterFilter {
                    -not $Tenant
                }
            }
        }

        It 'does not pass -UseDeviceAuthentication without device code mode' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM
                Should -Invoke Connect-AzAccount -Times 1 -Exactly -Scope It -ParameterFilter {
                    -not $UseDeviceAuthentication
                }
            }
        }
    }

    Context 'When -IncludeARM and both Graph token and Azure context are already valid' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $FakeAzCtx = [PSCustomObject]@{
                    Tenant  = [PSCustomObject]@{ Id  = 'contoso.onmicrosoft.com' }
                    Account = [PSCustomObject]@{ Id  = 'user@contoso.com' }
                }
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $false
                }
                # Return value inlined -- $FakeAzCtx is a local variable in the BeforeAll
                # scriptblock and is not accessible inside a mock body (late-binding scope).
                Mock Get-AzContext {
                    return [PSCustomObject]@{
                        Tenant  = [PSCustomObject]@{ Id  = 'contoso.onmicrosoft.com' }
                        Account = [PSCustomObject]@{ Id  = 'user@contoso.com' }
                    }
                }
                # The cached context is now validated by minting an ARM token silently. A
                # successful Get-AzAccessToken proves the context is usable, preserving the
                # idempotent skip of Connect-AzAccount.
                Mock Get-AzAccessToken { return [PSCustomObject]@{ Token = 'fake-arm-token' } }
                Mock Connect-AzAccount {}
                Mock Get-OPIMMsalApplication {}
                Mock Connect-MgGraph {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'returns early without calling Connect-AzAccount (fully idempotent)' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM
                Should -Invoke Connect-AzAccount -Times 0 -Scope It
            }
        }

        It 'does not call Get-OPIMMsalApplication when both Graph and Azure are cached' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM
                Should -Invoke Get-OPIMMsalApplication -Times 0 -Scope It
            }
        }
    }

    Context 'When -IncludeARM and a stale autosaved Az context cannot acquire a token' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $false
                }
                # Return value inlined -- BeforeAll locals are not visible inside mock bodies.
                Mock Get-AzContext {
                    return [PSCustomObject]@{
                        Tenant  = [PSCustomObject]@{ Id  = 'contoso.onmicrosoft.com' }
                        Account = [PSCustomObject]@{ Id  = 'user@contoso.com' }
                    }
                }
                # A stale autosaved context resurfaces for the right tenant, but the underlying
                # token has expired / needs an interactive step-up: silent token minting fails.
                Mock Get-AzAccessToken { throw [System.Exception]::new('interaction required') }
                Mock Update-AzConfig {}
                Mock Connect-AzAccount {}
                Mock Get-OPIMMsalApplication {}
                Mock Connect-MgGraph {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'calls Connect-AzAccount when the cached Az context cannot acquire a token silently' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM
                Should -Invoke Connect-AzAccount -Times 1 -Scope It
            }
        }
    }

    Context 'When -IncludeARM and Azure connection fails' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $false
                }
                Mock Get-AzContext { return $null }
                Mock Update-AzConfig {}
                Mock Connect-AzAccount { throw [System.Exception]::new('Azure auth failure') }
                Mock Get-OPIMMsalApplication {}
                Mock Connect-MgGraph {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'writes a non-terminating error and does not throw' {
            InModuleScope Omnicit.PIM {
                $Errors = @()
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM `
                    -ErrorVariable Errors -ErrorAction SilentlyContinue
                $Errors.Count | Should -BeGreaterThan 0
            }
        }

        It 'includes AzureConnectFailed in the error id' {
            InModuleScope Omnicit.PIM {
                $Errors = @()
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM `
                    -ErrorVariable Errors -ErrorAction SilentlyContinue
                # $Errors may contain an auto-created record from the raw throw in the mock
                # (added by PowerShell's error machinery before the catch block runs) plus
                # the WriteError record with 'AzureConnectFailed'. Search all collected errors.
                ($Errors | Where-Object { $_.FullyQualifiedErrorId -match 'AzureConnectFailed' }) |
                    Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'When -DeviceCode is set and no auth state exists' {
        BeforeAll {
            # The request names a domain, so any tenant GUID is a token for it.
            InModuleScope Omnicit.PIM -Parameters @{ Token = (New-OPIMTestAccessToken -TenantId $TenantA) } {
                param($Token)
                $script:_OPIMTestToken = $Token
                Mock Get-OPIMMsalApplication { [PSCustomObject]@{} }
                Mock Invoke-OPIMDeviceCodeAuth {
                    [PSCustomObject]@{
                        AccessToken = $script:_OPIMTestToken
                        ExpiresOn   = [DateTimeOffset]::UtcNow.AddHours(1)
                        Account     = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    }
                }
                Mock Connect-MgGraph {}
                # Read once, by the fingerprint recorded after Connect-MgGraph.
                Mock Get-MgContext { $null }
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null; $script:_OPIMTestToken = $null }
        }

        It 'acquires the Graph token with the device code flow and hands it to Connect-MgGraph' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -DeviceCode
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It
                Should -Invoke Connect-MgGraph -Times 1 -Exactly -Scope It
            }
        }

        It 'requests the fixed Graph scope list' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -DeviceCode
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Scopes.Count -eq 6 -and $Scopes -contains 'User.Read' -and
                    $Scopes -contains 'RoleAssignmentSchedule.ReadWrite.Directory'
                }
            }
        }

        It 'remembers the device code mode in the auth state' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -DeviceCode
                $script:_OPIMAuthState.DeviceCode | Should -BeTrue
            }
        }
    }

    Context 'When the auth state remembers device code mode and a retry signs in again' {
        BeforeAll {
            InModuleScope Omnicit.PIM -Parameters @{ Token = (New-OPIMTestAccessToken -TenantId $TenantA) } {
                param($Token)
                $script:_OPIMTestToken = $Token
                # An empty object: the silent path finds no AcquireTokenSilent and falls through.
                Mock Get-OPIMMsalApplication { [PSCustomObject]@{} }
                Mock Invoke-OPIMDeviceCodeAuth {
                    [PSCustomObject]@{
                        AccessToken = $script:_OPIMTestToken
                        ExpiresOn   = [DateTimeOffset]::UtcNow.AddHours(1)
                        Account     = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    }
                }
                Mock Connect-MgGraph {}
                # Read once, by the fingerprint recorded after Connect-MgGraph.
                Mock Get-MgContext { $null }
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    TokenTenantId    = $TenantA
                    AuthorityTenant  = 'contoso.onmicrosoft.com'
                    Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $false
                    DeviceCode       = $true
                }
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null; $script:_OPIMTestToken = $null }
        }

        It 'uses the device code flow on -ForceRefresh, not the browser' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -ForceRefresh
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It
            }
        }

        It 'passes the claims to the device code flow on a claims challenge' {
            InModuleScope Omnicit.PIM {
                $Json = '{"access_token":{"acrs":{"essential":true,"value":"c1"}}}'
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -ClaimsChallenge $Json
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                    $ClaimsChallenge -eq '{"access_token":{"acrs":{"essential":true,"value":"c1"}}}'
                }
            }
        }

        It 'keeps the device code mode after the new sign-in' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -ForceRefresh
                $script:_OPIMAuthState.DeviceCode | Should -BeTrue
            }
        }
    }

    Context 'When -DeviceCode is passed while a valid token is cached' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $false
                }
                Mock Get-OPIMMsalApplication {}
                Mock Invoke-OPIMDeviceCodeAuth {}
                Mock Connect-MgGraph {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'keeps the cached token and remembers the device code mode for the next sign-in' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -DeviceCode
                Should -Invoke Get-OPIMMsalApplication -Times 0 -Scope It
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 0 -Scope It
                $script:_OPIMAuthState.DeviceCode | Should -BeTrue
            }
        }
    }

    Context 'When the device code flow returns no token' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                Mock Get-OPIMMsalApplication { [PSCustomObject]@{} }
                Mock Invoke-OPIMDeviceCodeAuth { $null }
                Mock Connect-MgGraph {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'throws NoAccessToken and never falls back to the browser' {
            InModuleScope Omnicit.PIM {
                $Caught = $null
                try { Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -DeviceCode } catch { $Caught = $PSItem }
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It
                $Caught.FullyQualifiedErrorId | Should -BeLike 'NoAccessToken*'
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
            }
        }
    }

    Context 'When the device code flow fails on the first sign-in' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMMsalApplication { [PSCustomObject]@{} }
                # The helper's own terminating error, as Write-CmdletError -Terminating raises it.
                # Pester's mock wrapper has [CmdletBinding()], so $PSCmdlet is available.
                Mock Invoke-OPIMDeviceCodeAuth {
                    $PSCmdlet.ThrowTerminatingError(
                        [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('code_expired'),
                            'DeviceCodeAuthFailed',
                            [System.Management.Automation.ErrorCategory]::AuthenticationError,
                            $null
                        )
                    )
                }
                Mock Connect-MgGraph {}
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'keeps the device code mode, so the next call asks for a code again and never opens the browser' {
            InModuleScope Omnicit.PIM {
                try { Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -DeviceCode } catch { $null = $PSItem }
                try { Initialize-OPIMAuth } catch { $null = $PSItem }
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 2 -Exactly -Scope It
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
                $script:_OPIMAuthState.DeviceCode | Should -BeTrue
            }
        }

        It 'ends with the helper DeviceCodeAuthFailed error and signs nothing in' {
            InModuleScope Omnicit.PIM {
                $Caught = $null
                try { Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -DeviceCode } catch { $Caught = $PSItem }
                $Caught | Should -Not -BeNullOrEmpty
                $Caught.FullyQualifiedErrorId | Should -BeLike 'DeviceCodeAuthFailed*'
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
            }
        }

        It 'never counts the state that holds only the mode as a signed-in session' {
            InModuleScope Omnicit.PIM {
                try { Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -DeviceCode } catch { $null = $PSItem }
                $script:_OPIMAuthState.ContainsKey('TenantId') | Should -BeFalse
                $script:_OPIMAuthState.ContainsKey('GraphTokenExpiry') | Should -BeFalse
            }
        }
    }

    Context 'When -IncludeARM in device code mode and Azure is not connected' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $false
                    DeviceCode       = $true
                }
                Mock Get-AzContext { return $null }
                Mock Update-AzConfig {}
                Mock Connect-AzAccount {}
                Mock Get-OPIMMsalApplication {}
                Mock Connect-MgGraph {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'signs in to Azure with -UseDeviceAuthentication and the same tenant' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM
                Should -Invoke Connect-AzAccount -Times 1 -Exactly -Scope It -ParameterFilter {
                    $UseDeviceAuthentication -and $Tenant -eq 'contoso.onmicrosoft.com'
                }
            }
        }
    }

    Context 'When the session is pinned to a tenant' {
        # OPIM-07. Each It seeds the auth state and the token the device code mock hands back; the
        # acquisition runs through Invoke-OPIMDeviceCodeAuth (device code mode), so no reflection
        # into MSAL is involved. Get-OPIMMsalApplication is mocked: its -TenantId is the authority.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMMsalApplication { [PSCustomObject]@{} }
                Mock Invoke-OPIMDeviceCodeAuth {
                    [PSCustomObject]@{
                        AccessToken = $script:_OPIMTestToken
                        ExpiresOn   = [DateTimeOffset]::UtcNow.AddHours(1)
                        Account     = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    }
                }
                Mock Connect-MgGraph {}
                Mock Get-MgContext { $null }
            }
        }
        BeforeEach {
            # No token unless the It hands one out: an It that expects no sign-in then fails with
            # NoAccessToken if one happens, instead of riding on a token an earlier It left behind.
            InModuleScope Omnicit.PIM { $script:_OPIMTestToken = $null }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null; $script:_OPIMTestToken = $null }
        }

        It 'keeps the cached tenant when no tenant is given' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; TenantA = $TenantA } {
                param($State, $TenantA)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth
                Should -Invoke Get-OPIMMsalApplication -Times 0 -Scope It
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 0 -Scope It
                $script:_OPIMAuthState.TenantId | Should -Be $TenantA
            }
        }

        It 'signs in again for the cached tenant on -ForceRefresh without a tenant' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; Token = $Token; TenantA = $TenantA } {
                param($State, $Token, $TenantA)
                $script:_OPIMAuthState = $State
                $script:_OPIMTestToken = $Token
                Initialize-OPIMAuth -ForceRefresh
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It -ParameterFilter { $TenantId -eq 'aaaaaaaa-0000-0000-0000-00000000000a' }
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It
                $script:_OPIMAuthState.TenantId | Should -Be $TenantA
                $script:_OPIMAuthState.TokenTenantId | Should -Be $TenantA
            }
        }

        It 'never relabels the session to organizations' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; TenantA = $TenantA } {
                param($State, $TenantA)
                $script:_OPIMAuthState = $State
                Mock Get-MgContext { [pscustomobject]@{ TenantId = 'bbbbbbbb-0000-0000-0000-00000000000b' } }
                Initialize-OPIMAuth
                $script:_OPIMAuthState.TenantId | Should -Be $TenantA
                $script:_OPIMAuthState.TokenTenantId | Should -Be $TenantA
            }
        }

        It 'never adopts a Graph context the module did not make' {
            # OPIM-09: a Connect-MgGraph made outside the module, for the tenant now asked for, is not
            # taken over as the module's session; the module signs in for that tenant itself. The
            # session fingerprint recorded after the module's own Connect-MgGraph is the one read of
            # Get-MgContext on this path; it is mocked here, so any read of Get-MgContext is an adoption.
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA
            $Token = New-OPIMTestAccessToken -TenantId $TenantB
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; Token = $Token; TenantB = $TenantB } {
                param($State, $Token, $TenantB)
                $script:_OPIMAuthState = $State
                $script:_OPIMTestToken = $Token
                Mock Get-OPIMGraphSessionFingerprint { 'fp' }
                Mock Get-MgContext { [pscustomobject]@{ TenantId = 'bbbbbbbb-0000-0000-0000-00000000000b' } }
                Initialize-OPIMAuth -TenantId $TenantB
                Should -Invoke Get-MgContext -Times 0 -Scope It
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It -ParameterFilter { $TenantId -eq 'bbbbbbbb-0000-0000-0000-00000000000b' }
                Should -Invoke Connect-MgGraph -Times 1 -Exactly -Scope It
                $script:_OPIMAuthState.TokenTenantId | Should -Be $TenantB
            }
        }

        It 'throws TenantMismatch and does not connect Graph when the token is for another tenant' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -Expired
            $Token = New-OPIMTestAccessToken -TenantId $TenantB
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; Token = $Token; TenantA = $TenantA; TenantB = $TenantB } {
                param($State, $Token, $TenantA, $TenantB)
                $script:_OPIMAuthState = $State
                $script:_OPIMTestToken = $Token
                $Expiry = $State.GraphTokenExpiry
                $Caught = $null
                try { Initialize-OPIMAuth -TenantId $TenantA } catch { $Caught = $PSItem }
                $Caught | Should -Not -BeNullOrEmpty
                $Caught.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
                $Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
                $Caught.Exception.Message | Should -BeLike "*'$TenantA'*"
                $Caught.Exception.Message | Should -Not -BeLike "*$TenantB*"
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
                $script:_OPIMAuthState.TenantId | Should -Be $TenantA
                $script:_OPIMAuthState.TokenTenantId | Should -Be $TenantA
                $script:_OPIMAuthState.GraphTokenExpiry | Should -Be $Expiry
            }
        }

        It 'throws TenantMismatch when the token carries no tenant' {
            # A first sign-in that names no tenant has no tenant to compare with yet, so this is the
            # path on which only the unreadable-tid check can stop the token.
            $Token = New-OPIMTestAccessToken -NoTenant
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMTestToken = $Token
                $Caught = $null
                try { Initialize-OPIMAuth } catch { $Caught = $PSItem }
                $Caught | Should -Not -BeNullOrEmpty
                $Caught.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
                $Caught.Exception.Message | Should -BeLike '*could not be read*'
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
                $script:_OPIMAuthState.ContainsKey('TenantId') | Should -BeFalse
            }
        }

        It 'throws TenantMismatch when the token carries no tenant for a tenant asked for by GUID' {
            $Token = New-OPIMTestAccessToken -NoTenant
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMTestToken = $Token
                $Caught = $null
                try { Initialize-OPIMAuth -TenantId $TenantA } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
                $script:_OPIMAuthState.ContainsKey('TenantId') | Should -BeFalse
            }
        }

        It "pins the session to the token's tenant on a first sign-in without a tenant" {
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMTestToken = $Token
                Initialize-OPIMAuth
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It -ParameterFilter { $TenantId -eq 'organizations' }
                $script:_OPIMAuthState.TenantId | Should -Be $TenantA
                $script:_OPIMAuthState.TokenTenantId | Should -Be $TenantA
                $script:_OPIMAuthState.AuthorityTenant | Should -Be 'organizations'
                $script:_OPIMAuthState.DeviceCode | Should -BeTrue
            }
        }

        It 'reuses the organizations app on a later refresh of that session' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant 'organizations'
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; Token = $Token; TenantA = $TenantA } {
                param($State, $Token, $TenantA)
                $script:_OPIMAuthState = $State
                $script:_OPIMTestToken = $Token
                Initialize-OPIMAuth -ForceRefresh
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It -ParameterFilter { $TenantId -eq 'organizations' }
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It
                $script:_OPIMAuthState.TenantId | Should -Be $TenantA
                $script:_OPIMAuthState.AuthorityTenant | Should -Be 'organizations'
            }
        }

        It 'compares a later token of an organizations session with the pinned tenant' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant 'organizations'
            $Token = New-OPIMTestAccessToken -TenantId $TenantB
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; Token = $Token; TenantA = $TenantA } {
                param($State, $Token, $TenantA)
                $script:_OPIMAuthState = $State
                $script:_OPIMTestToken = $Token
                $Caught = $null
                try { Initialize-OPIMAuth -ForceRefresh } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
                $script:_OPIMAuthState.TokenTenantId | Should -Be $TenantA
            }
        }

        It "records the token's tenant for a tenant named by domain" {
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMTestToken = $Token
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com'
                $script:_OPIMAuthState.TenantId | Should -Be 'contoso.onmicrosoft.com'
                $script:_OPIMAuthState.TokenTenantId | Should -Be $TenantA
                $script:_OPIMAuthState.AuthorityTenant | Should -Be 'contoso.onmicrosoft.com'
            }
        }

        It 'compares a later token of a domain session with the recorded tenant' {
            $State = New-PinState -TenantId 'contoso.onmicrosoft.com' -TokenTenantId $TenantA -AuthorityTenant 'contoso.onmicrosoft.com'
            $Token = New-OPIMTestAccessToken -TenantId $TenantB
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; Token = $Token; TenantA = $TenantA } {
                param($State, $Token, $TenantA)
                $script:_OPIMAuthState = $State
                $script:_OPIMTestToken = $Token
                $Caught = $null
                # As the token-rejected retry in Invoke-OPIMGraphRequest calls it.
                try { Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -ForceRefresh } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
                $Caught.Exception.Message | Should -BeLike "*'contoso.onmicrosoft.com'*"
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
                $script:_OPIMAuthState.TokenTenantId | Should -Be $TenantA
            }
        }

        It 'accepts a GUID for the same tenant as a domain session without a new sign-in' {
            $State = New-PinState -TenantId 'contoso.onmicrosoft.com' -TokenTenantId $TenantA -AuthorityTenant 'contoso.onmicrosoft.com'
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; TenantA = $TenantA } {
                param($State, $TenantA)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -TenantId $TenantA
                Should -Invoke Get-OPIMMsalApplication -Times 0 -Scope It
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
            }
        }

        It 'builds a new app when another tenant is requested' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA
            $Token = New-OPIMTestAccessToken -TenantId $TenantB
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; Token = $Token; TenantB = $TenantB } {
                param($State, $Token, $TenantB)
                $script:_OPIMAuthState = $State
                $script:_OPIMTestToken = $Token
                Initialize-OPIMAuth -TenantId $TenantB
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It -ParameterFilter { $TenantId -eq 'bbbbbbbb-0000-0000-0000-00000000000b' }
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It
                $script:_OPIMAuthState.TenantId | Should -Be $TenantB
                $script:_OPIMAuthState.TokenTenantId | Should -Be $TenantB
                $script:_OPIMAuthState.AuthorityTenant | Should -Be $TenantB
            }
        }

        It 'stores the requested GUID as the session tenant' {
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMTestToken = $Token
                Initialize-OPIMAuth -TenantId $TenantA
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It -ParameterFilter { $TenantId -eq 'aaaaaaaa-0000-0000-0000-00000000000a' }
                $script:_OPIMAuthState.TenantId | Should -Be $TenantA
                $script:_OPIMAuthState.TokenTenantId | Should -Be $TenantA
                $script:_OPIMAuthState.AuthorityTenant | Should -Be $TenantA
            }
        }
    }

    Context 'When the Graph token is handed on' {
        It 'binds the plaintext token to no command' {
            # SECURITY rule 5: PowerShell module logging (LogPipelineExecutionDetails, event 4103)
            # records every value bound to a command parameter. Static check on the function as the
            # module loaded it: no argument of any command call reaches an .AccessToken member, so
            # the plaintext only ever reaches .NET (the SecureString is what commands receive).
            $Ast = InModuleScope Omnicit.PIM { (Get-Command Initialize-OPIMAuth).ScriptBlock.Ast }
            $Commands = @($Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true))
            @($Commands | Where-Object { $_.GetCommandName() -eq 'Connect-MgGraph' }).Count |
                Should -Be 1 -Because 'the walk must reach the Connect-MgGraph hand-off; a walk that reads nothing would pass vacuously'
            $Hits = foreach ($Command in $Commands) {
                foreach ($Element in @($Command.CommandElements | Select-Object -Skip 1)) {
                    $Member = $Element.Find({
                            param($Node)
                            $Node -is [System.Management.Automation.Language.MemberExpressionAst] -and
                            $Node.Member.Extent.Text -eq 'AccessToken'
                        }, $true)
                    if ($Member) { 'line {0}: {1}' -f $Command.Extent.StartLineNumber, $Command.GetCommandName() }
                }
            }
            $Hits | Should -BeNullOrEmpty
        }
    }

    Context 'When Connect-MgGraph fails to take the token' {
        BeforeAll {
            InModuleScope Omnicit.PIM -Parameters @{ Token = (New-OPIMTestAccessToken -TenantId $TenantA) } {
                param($Token)
                $script:_OPIMTestToken = $Token
                Mock Get-OPIMMsalApplication { [PSCustomObject]@{} }
                Mock Invoke-OPIMDeviceCodeAuth {
                    [PSCustomObject]@{
                        AccessToken = $script:_OPIMTestToken
                        ExpiresOn   = [DateTimeOffset]::UtcNow.AddHours(1)
                        Account     = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    }
                }
                # Throws the queued record exactly as a cmdlet throws its own.
                Mock Connect-MgGraph { $PSCmdlet.ThrowTerminatingError($script:_ConnectRecord) }
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_OPIMTestToken = $null
                $script:_ConnectRecord = $null
            }
        }

        It 'ends with the Connect-MgGraph error and writes no auth state' {
            $Record = [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new('connect failed'), 'ConnectMgGraphFailed', 'AuthenticationError', $null)
            InModuleScope Omnicit.PIM -Parameters @{ Record = $Record; TenantA = $TenantA } {
                param($Record, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_ConnectRecord = $Record
                $Caught = $null
                try { Initialize-OPIMAuth -TenantId $TenantA } catch { $Caught = $PSItem }
                $Caught | Should -Not -BeNullOrEmpty
                $Caught.FullyQualifiedErrorId | Should -BeLike 'ConnectMgGraphFailed*'
                Should -Invoke Connect-MgGraph -Times 1 -Exactly -Scope It
                $script:_OPIMAuthState.ContainsKey('TenantId') | Should -BeFalse
                $script:_OPIMAuthState.ContainsKey('GraphTokenExpiry') | Should -BeFalse
            }
        }

        It 'scrubs the request of the failed Connect-MgGraph' {
            # The token is built at runtime and says what it is, so no token-shaped literal sits here.
            $Request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, 'https://graph.microsoft.com/v1.0/me')
            $null = $Request.Headers.TryAddWithoutValidation('Authorization', ('Bearer ' + ('x' * 40) + 'NOT-A-REAL-TOKEN'))
            $Record = [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new('connect failed'), 'ConnectMgGraphFailed', 'AuthenticationError', $Request)
            $Request.Headers.Contains('Authorization') | Should -BeTrue -Because 'the fixture must carry the header the scrub removes'
            InModuleScope Omnicit.PIM -Parameters @{ Record = $Record; TenantA = $TenantA } {
                param($Record, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_ConnectRecord = $Record
                $Caught = $null
                try { Initialize-OPIMAuth -TenantId $TenantA } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'ConnectMgGraphFailed*'
            }
            $Request.Headers.Contains('Authorization') | Should -BeFalse
        }
    }

    Context 'When another Connect-MgGraph replaced the module session' {
        # OPIM-09 (EntraRBAC A18). The acquisition runs through the Invoke-OPIMDeviceCodeAuth mock, as in
        # the pin context. The Connect-MgGraph mock records that it ran, so the fingerprint mock can
        # tell a read after the connect from one before it.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMMsalApplication { [PSCustomObject]@{} }
                Mock Invoke-OPIMDeviceCodeAuth {
                    [PSCustomObject]@{
                        AccessToken = $script:_OPIMTestToken
                        ExpiresOn   = [DateTimeOffset]::UtcNow.AddHours(1)
                        Account     = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    }
                }
                Mock Connect-MgGraph { $script:_OPIMTestConnected = $true }
                Mock Get-OPIMGraphSessionFingerprint { if ($script:_OPIMTestConnected) { 'fp' } else { 'read-before-the-connect' } }
                Mock Get-AzContext {}
                Mock Update-AzConfig {}
                Mock Connect-AzAccount {}
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM {
                $script:_OPIMTestToken = $null
                $script:_OPIMTestConnected = $false
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_OPIMTestToken = $null
                $script:_OPIMTestConnected = $null
            }
        }

        It 'throws GraphSessionChanged before the cached return' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA
            $State.GraphSessionFingerprint = 'mine'
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; TenantA = $TenantA } {
                param($State, $TenantA)
                $script:_OPIMAuthState = $State
                Mock Get-OPIMGraphSessionState { 'Changed' }
                { Initialize-OPIMAuth } | Should -Throw -ErrorId 'GraphSessionChanged*'
                $Caught = $null
                try { Initialize-OPIMAuth } catch { $Caught = $PSItem }
                $Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
                $Caught.TargetObject | Should -Be $TenantA
                Should -Invoke Get-OPIMGraphSessionState -Times 2 -Exactly -Scope It
                Should -Invoke Get-OPIMMsalApplication -Times 0 -Scope It
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
                $script:_OPIMAuthState.GraphSessionFingerprint | Should -BeExactly 'mine'
            }
        }

        It 'never connects Graph again by itself after a change (<Name>)' -ForEach @(
            @{ Name = '-ForceRefresh'; Parameters = @{ ForceRefresh = $true } }
            @{ Name = 'a claims challenge'; Parameters = @{ ClaimsChallenge = '{"access_token":{"acrs":{"essential":true,"value":"c1"}}}' } }
            @{ Name = 'another tenant'; Parameters = @{ TenantId = 'bbbbbbbb-0000-0000-0000-00000000000b' } }
            @{ Name = '-IncludeARM'; Parameters = @{ IncludeARM = $true } }
        ) {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA
            $State.GraphSessionFingerprint = 'mine'
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; Token = $Token; P = $Parameters; TenantA = $TenantA } {
                param($State, $Token, $P, $TenantA)
                $script:_OPIMAuthState = $State
                $script:_OPIMTestToken = $Token
                Mock Get-OPIMGraphSessionState { 'Changed' }
                $Caught = $null
                try { Initialize-OPIMAuth @P } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'GraphSessionChanged*'
                # The module's own tenant, never the one the call named.
                $Caught.TargetObject | Should -Be $TenantA
                Should -Invoke Get-OPIMMsalApplication -Times 0 -Scope It
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 0 -Scope It
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
                Should -Invoke Get-AzContext -Times 0 -Scope It
                Should -Invoke Connect-AzAccount -Times 0 -Scope It
            }
        }

        It 'signs in again when the process holds no session' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA
            $State.GraphSessionFingerprint = 'mine'
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; Token = $Token } {
                param($State, $Token)
                $script:_OPIMAuthState = $State
                $script:_OPIMTestToken = $Token
                Mock Get-OPIMGraphSessionState { 'Absent' }
                Initialize-OPIMAuth
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It
                Should -Invoke Connect-MgGraph -Times 1 -Exactly -Scope It
                $script:_OPIMAuthState.GraphSessionFingerprint | Should -BeExactly 'fp'
            }
        }

        It 'returns from the cache under its own session' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA
            $State.GraphSessionFingerprint = 'mine'
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Mock Get-OPIMGraphSessionState { 'Own' }
                Initialize-OPIMAuth
                Should -Invoke Get-OPIMGraphSessionState -Times 1 -Exactly -Scope It
                Should -Invoke Get-OPIMMsalApplication -Times 0 -Scope It
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
            }
        }

        It 'records the session it connected' {
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMTestToken = $Token
                Initialize-OPIMAuth -TenantId $TenantA
                $script:_OPIMAuthState.ContainsKey('GraphSessionFingerprint') | Should -BeTrue
                # 'fp' is what the mock gives only once Connect-MgGraph has run.
                $script:_OPIMAuthState.GraphSessionFingerprint | Should -BeExactly 'fp'
                Should -Invoke Get-OPIMGraphSessionFingerprint -Times 1 -Exactly -Scope It
                Should -Invoke Connect-MgGraph -Times 1 -Exactly -Scope It
            }
        }

        It 'records the key even when the process shows no session after the connect' {
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMTestToken = $Token
                Mock Get-OPIMGraphSessionFingerprint { $null }
                Initialize-OPIMAuth -TenantId $TenantA
                $script:_OPIMAuthState.ContainsKey('GraphSessionFingerprint') | Should -BeTrue
                $script:_OPIMAuthState.GraphSessionFingerprint | Should -BeNullOrEmpty
            }
        }
    }

    Context 'When another Connect-MgGraph replaced the module session (end to end)' {
        # The real Get-OPIMGraphSessionState and Get-OPIMGraphSessionFingerprint over a stateful
        # Get-MgContext mock: no session until the module's own Connect-MgGraph, then the module's
        # session, until a test puts another sign-in's session in its place.
        BeforeAll {
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMTestOwnContext = [pscustomobject]@{
                    AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
                    ClientId = 'cccccccc-0000-0000-0000-00000000000c'; TenantId = $TenantA
                    Account = 'user@contoso.com'; AppName = 'opim-test-app'; Environment = 'Global'; Scopes = @('User.Read')
                }
                Mock Get-OPIMMsalApplication { [PSCustomObject]@{} }
                Mock Invoke-OPIMDeviceCodeAuth {
                    [PSCustomObject]@{
                        AccessToken = $script:_OPIMTestToken
                        ExpiresOn   = [DateTimeOffset]::UtcNow.AddHours(1)
                        Account     = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    }
                }
                Mock Connect-MgGraph { $script:_OPIMTestSession = $script:_OPIMTestOwnContext }
                Mock Get-MgContext { $script:_OPIMTestSession }
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_OPIMTestToken = $null
                $script:_OPIMTestOwnContext = $null
                $script:_OPIMTestSession = $null
            }
        }

        It 'refuses its cached token once another Connect-MgGraph replaced the session it recorded' {
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMTestToken = $Token
                $script:_OPIMTestSession = $null

                Initialize-OPIMAuth -TenantId $TenantA
                $Recorded = $script:_OPIMAuthState.GraphSessionFingerprint
                $Recorded | Should -BeExactly (Get-OPIMGraphSessionFingerprint -Context $script:_OPIMTestOwnContext)
                # Under its own session the next call returns from the cache.
                Initialize-OPIMAuth
                Should -Invoke Connect-MgGraph -Times 1 -Exactly -Scope It

                $script:_OPIMTestSession = [pscustomobject]@{
                    AuthType = 'AppOnly'; TokenCredentialType = 'ClientCertificate'
                    ClientId = 'dddddddd-0000-0000-0000-00000000000d'; TenantId = 'bbbbbbbb-0000-0000-0000-00000000000b'
                    Account = $null; AppName = 'another-app'; Environment = 'Global'; Scopes = @()
                }
                $Caught = $null
                try { Initialize-OPIMAuth } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'GraphSessionChanged*'
                $Caught.TargetObject | Should -Be $TenantA
                $Caught.Exception.Message | Should -Not -BeLike '*bbbbbbbb-0000-0000-0000-00000000000b*'
                $Caught.Exception.Message | Should -Not -BeLike '*dddddddd-0000-0000-0000-00000000000d*'
                Should -Invoke Connect-MgGraph -Times 1 -Exactly -Scope It
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It
                $script:_OPIMAuthState.GraphSessionFingerprint | Should -BeExactly $Recorded
            }
        }

        It 'signs in again with its own token after Disconnect-MgGraph left no session' {
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMTestToken = $Token
                $script:_OPIMTestSession = $null

                Initialize-OPIMAuth -TenantId $TenantA
                $script:_OPIMTestSession = $null
                Initialize-OPIMAuth
                Should -Invoke Connect-MgGraph -Times 2 -Exactly -Scope It
                $script:_OPIMAuthState.GraphSessionFingerprint |
                    Should -BeExactly (Get-OPIMGraphSessionFingerprint -Context $script:_OPIMTestOwnContext)
            }
        }
    }
}
