BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OPIMTestToken.ps1"

    # Two tenants for the tenant-pin tests. Letter-repeat placeholders: neither is a version-4 id.
    $TenantA = 'aaaaaaaa-0000-0000-0000-00000000000a'
    $TenantB = 'bbbbbbbb-0000-0000-0000-00000000000b'

    # The account (the oid claim) of the session's Graph token, and another account. Digit-repeat
    # placeholders: neither is a version-4 id.
    $SessionOid = '22222222-2222-2222-2222-222222222222'
    $OtherOid = '33333333-3333-3333-3333-333333333333'

    # An auth state as Initialize-OPIMAuth writes it after a Graph sign-in, in device code mode so the
    # tests drive the acquisition through the Invoke-OPIMDeviceCodeAuth mock.
    function New-PinState {
        param(
            [string]$TenantId,
            [string]$TokenTenantId,
            [string]$AuthorityTenant,
            [string]$ObjectId,
            [switch]$Expired
        )
        @{
            TenantId         = $TenantId
            TokenTenantId    = $TokenTenantId
            AuthorityTenant  = $AuthorityTenant
            Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
            ObjectId         = if ($ObjectId) { $ObjectId } else { $null }
            GraphTokenExpiry = if ($Expired) { [DateTime]::UtcNow.AddMinutes(-1) } else { [DateTime]::UtcNow.AddHours(1) }
            ClaimsSatisfied  = $false
            DeviceCode       = $true
        }
    }

    # Adds the five keys Initialize-OPIMAuth writes once an Azure Resource Manager token has passed its
    # tid and oid checks. The token itself is a SecureString, as the module keeps it (A6).
    function Add-ArmTestToken {
        param(
            [Parameter(Mandatory)]
            [hashtable]$State,
            [string]$TenantId,
            [string]$ObjectId,
            [datetime]$Expiry = [DateTime]::UtcNow.AddHours(1)
        )
        $State.ArmToken = [System.Net.NetworkCredential]::new('', (New-OPIMTestAccessToken -TenantId $TenantId -ObjectId $ObjectId)).SecurePassword
        $State.ArmTokenExpiry = $Expiry
        $State.ArmTokenTenantId = $TenantId
        $State.ArmTokenObjectId = $ObjectId
        $State.ArmResourceUrl = 'https://management.azure.com'
        $State
    }

    # The values the Get-AzToken and Invoke-OPIMDeviceCodeAuth mocks of the ARM contexts read. They are
    # $script: variables of this file: a mock body runs in the test scope, where it also finds
    # New-OPIMTestAccessToken, which the module scope does not see.
    function Reset-ArmTestFixture {
        $script:ArmTid = 'aaaaaaaa-0000-0000-0000-00000000000a'
        $script:ArmOid = '22222222-2222-2222-2222-222222222222'
        $script:ArmNoTid = $false
        $script:ArmNoOid = $false
        $script:ArmWarning = $null
        $script:ArmExpiresOn = [DateTimeOffset]::new(2030, 1, 1, 12, 0, 0, [TimeSpan]::FromHours(2))
        $script:GraphTid = 'aaaaaaaa-0000-0000-0000-00000000000a'
        $script:GraphOid = '22222222-2222-2222-2222-222222222222'
        $script:GraphNoOid = $false
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
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It
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
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'calls Get-OPIMMsalApplication' {
            InModuleScope Omnicit.PIM {
                try { Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' } catch {}
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It
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
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It -ParameterFilter {
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
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It
            }
        }
    }

    Context 'When -IncludeARM signs in to Azure Resource Manager' {
        # A2, A3, A6. AzAuth's Get-AzToken acquires the ARM token for the tenant of the session's Graph
        # token, interactively or with a device code by the session's mode. The token must carry the
        # tid and the oid of the Graph session, and is kept only as a SecureString. The Graph SDK
        # session is the module's own. The Get-AzToken mock builds its token from this file's
        # $script:Arm* values, and the Invoke-OPIMDeviceCodeAuth mock (a Graph sign-in, where an It
        # needs one) from $script:Graph*; Reset-ArmTestFixture sets both before every It. A bound
        # -WarningAction sets no preference inside a mock body, which runs in the test scope, so the
        # Get-AzToken mock takes it from $PesterBoundParameters, as the compiled cmdlet honours it.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionState { 'Own' }
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionFingerprint { 'fp' }
            Mock -ModuleName Omnicit.PIM Get-OPIMMsalApplication { [PSCustomObject]@{} }
            Mock -ModuleName Omnicit.PIM Connect-MgGraph {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMDeviceCodeAuth {
                $GraphTokenArgs = @{ TenantId = $script:GraphTid; ObjectId = $script:GraphOid }
                if ($script:GraphNoOid) { $GraphTokenArgs.NoObjectId = $true }
                [PSCustomObject]@{
                    AccessToken = New-OPIMTestAccessToken @GraphTokenArgs
                    ExpiresOn   = [DateTimeOffset]::UtcNow.AddHours(1)
                    Account     = [PSCustomObject]@{ Username = 'user@contoso.com' }
                }
            }
            Mock -ModuleName Omnicit.PIM Get-AzToken {
                param($Resource, $Tenant, [switch]$DeviceCode, [switch]$Interactive, [switch]$Force)
                if ($PesterBoundParameters.ContainsKey('WarningAction')) {
                    $WarningPreference = $PesterBoundParameters['WarningAction']
                }
                if ($script:ArmWarning) { Microsoft.PowerShell.Utility\Write-Warning $script:ArmWarning }
                $ArmTokenArgs = @{ TenantId = $script:ArmTid; ObjectId = $script:ArmOid }
                if ($script:ArmNoTid) { $ArmTokenArgs.NoTenant = $true }
                if ($script:ArmNoOid) { $ArmTokenArgs.NoObjectId = $true }
                [PSCustomObject]@{
                    Token     = New-OPIMTestAccessToken @ArmTokenArgs
                    ExpiresOn = $script:ArmExpiresOn
                    TenantId  = $script:ArmTid
                    Identity  = 'user@contoso.com'
                }
            }
        }
        BeforeEach {
            Reset-ArmTestFixture
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_OPIMSignInLatch = $null
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_OPIMSignInLatch = $null
            }
        }

        Context 'When no ARM token is cached' {
            It 'calls Get-AzToken once for the ARM resource and the tenant of the Graph token' {
                # A session pinned by domain: AzAuth gets the GUID its Graph token was issued for.
                $State = New-PinState -TenantId 'contoso.onmicrosoft.com' -TokenTenantId $TenantA -AuthorityTenant 'contoso.onmicrosoft.com' -ObjectId $SessionOid
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Resource -eq 'https://management.azure.com' -and $Tenant -eq 'aaaaaaaa-0000-0000-0000-00000000000a'
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 0 -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
            }

            It 'signs in interactively, and never with a device code, outside device code mode' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $State.DeviceCode = $false
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Interactive -and -not $DeviceCode }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It -ParameterFilter { $DeviceCode }
            }

            It 'signs in with a device code, and never interactively, in device code mode' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $DeviceCode -and -not $Interactive }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It -ParameterFilter { $Interactive }
            }

            It 'passes the tenant of the new Graph token in the call that first signs in under organizations' {
                InModuleScope Omnicit.PIM {
                    $script:_OPIMAuthState = @{ DeviceCode = $true }
                    Initialize-OPIMAuth -IncludeARM
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 1 -Exactly -Scope It -ParameterFilter { $TenantId -eq 'organizations' }
                Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Tenant -eq 'aaaaaaaa-0000-0000-0000-00000000000a'
                }
            }

            It 'stores the token as a SecureString with its UTC expiry, tenant, account and resource' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM
                    $script:_OPIMAuthState
                }
                $After.ArmToken | Should -BeOfType [securestring]
                $After.ArmTokenExpiry | Should -BeOfType [datetime]
                $After.ArmTokenExpiry.Kind | Should -Be ([System.DateTimeKind]::Utc)
                # AzAuth's ExpiresOn is 12:00 at UTC+2 in the fixture.
                $After.ArmTokenExpiry | Should -Be ([datetime]::new(2030, 1, 1, 10, 0, 0, [System.DateTimeKind]::Utc))
                $After.ArmTokenTenantId | Should -BeExactly $TenantA
                $After.ArmTokenObjectId | Should -BeExactly $SessionOid
                $After.ArmResourceUrl | Should -BeExactly 'https://management.azure.com'
            }

            It 'keeps no token in plaintext in the state, and the ARM token only as a SecureString' {
                # A first sign-in: a new Graph token and a new ARM token in one call (A6).
                $After = InModuleScope Omnicit.PIM {
                    $script:_OPIMAuthState = @{ DeviceCode = $true }
                    Initialize-OPIMAuth -IncludeARM
                    $script:_OPIMAuthState
                }
                Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                foreach ($Key in @($After.Keys)) {
                    if ($After[$Key] -is [string]) {
                        $After[$Key] | Should -Not -BeLike '*NOT-A-REAL-TOKEN*' -Because "the state key $Key must hold no plaintext token"
                    }
                }
                @($After.Values | Where-Object { $_ -is [securestring] }).Count | Should -Be 1
                $After.ArmToken | Should -BeOfType [securestring]
            }

            It 'releases the calling command once the token is acquired' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $Refusal = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    function Invoke-ArmSignInCommand {
                        Initialize-OPIMAuth -IncludeARM
                        Get-OPIMSignInRefusal
                    }
                    Invoke-ArmSignInCommand
                }
                $Refusal | Should -BeNullOrEmpty
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
            }

            It 'refuses ARM with TenantMismatch, before any Get-AzToken, when the state records no tenant' {
                # A state the module built always records the token's tenant; one without it is refused
                # rather than signed in to Azure without a tenant.
                $Caught = InModuleScope Omnicit.PIM {
                    $script:_OPIMAuthState = @{
                        TenantId         = 'contoso.onmicrosoft.com'
                        Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
                        GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                        ClaimsSatisfied  = $false
                    }
                    try { Initialize-OPIMAuth -IncludeARM } catch { $PSItem }
                }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
                $Caught.Exception.Message | Should -BeLike "*could not be read*'contoso.onmicrosoft.com'*"
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
            }

            It 'returns from the cache without an ARM sign-in when -IncludeARM is not given' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $Refusal = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    function Invoke-GraphSignInCommand {
                        Initialize-OPIMAuth
                        Get-OPIMSignInRefusal
                    }
                    Invoke-GraphSignInCommand
                }
                $Refusal | Should -BeNullOrEmpty
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
            }
        }

        Context 'When the ARM sign-in rebuilds the AzAuth credential' {
            It 'passes -Force on the first ARM sign-in of the session' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Force }
            }

            It 'passes -Force under -ForceRefresh, also with a cached ARM token for the same tenant and account' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -ForceRefresh -IncludeARM
                }
                # The Graph refresh kept the ARM token (same tenant and account); -ForceRefresh still forces.
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Force }
            }

            It 'passes no -Force when the state holds an ARM token that is about to expire' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid -Expiry ([DateTime]::UtcNow.AddMinutes(4))
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { -not $Force }
            }
        }

        Context 'When an ARM token is cached' {
            It 'reuses a token with more than 5 minutes left for the same tenant and account, without a call' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
                $Kept = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    $Before = $State.ArmToken
                    Initialize-OPIMAuth -IncludeARM
                    [object]::ReferenceEquals($Before, $script:_OPIMAuthState.ArmToken)
                }
                $Kept | Should -BeTrue
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
            }

            It 'releases the calling command once when the Graph token and the ARM token are cached' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Mock Unlock-OPIMSignIn {}
                    Initialize-OPIMAuth -IncludeARM
                    Should -Invoke Unlock-OPIMSignIn -Times 1 -Exactly -Scope It
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
            }

            It 'acquires a new token when the cached one has <Minutes> minutes or less left' -ForEach @(
                @{ Minutes = 5 }
                @{ Minutes = 1 }
            ) {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid -Expiry ([DateTime]::UtcNow.AddMinutes($Minutes))
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
            }

            It 'acquires a new token when the cached one is for another tenant' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $null = Add-ArmTestToken -State $State -TenantId $TenantB -ObjectId $SessionOid
                $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM
                    $script:_OPIMAuthState
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                $After.ArmTokenTenantId | Should -BeExactly $TenantA
            }

            It 'acquires a new token when the cached one is for another account' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $OtherOid
                $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM
                    $script:_OPIMAuthState
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                $After.ArmTokenObjectId | Should -BeExactly $SessionOid
            }

            It 'acquires a new token when the state records an expiry but holds no token' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
                $State.ArmToken = $null
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
            }

            It 'never reuses a cached token for a session that records no account' {
                # Two unknown accounts are not the same account: the call is made, and the oid check
                # after it refuses.
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId ''
                $State.ArmTokenObjectId = $null
                $Caught = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    try { Initialize-OPIMAuth -IncludeARM } catch { $PSItem }
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                $Caught.FullyQualifiedErrorId | Should -BeLike 'AccountMismatch*'
            }
        }

        Context 'When the ARM token is not for the tenant and the account of the Graph session' {
            # SEC (A3, OPIM-47). Each refusal is terminating, stores nothing of the token and leaves the
            # calling command latched. The command is a module-scope test function with a try of its
            # own, so it carries on and reads the latch after the refusal.
            It 'refuses a token for <Name> with <ErrorId>, stores nothing and keeps the caller latched' -ForEach @(
                @{ Name = 'another tenant'; Fixture = @{ ArmTid = 'bbbbbbbb-0000-0000-0000-00000000000b' }; NoSessionOid = $false; ErrorId = 'TenantMismatch'; Message = 'Azure is signed in to another tenant than *' }
                @{ Name = 'no readable tenant'; Fixture = @{ ArmNoTid = $true }; NoSessionOid = $false; ErrorId = 'TenantMismatch'; Message = 'The tenant of the Azure Resource Manager token could not be read*' }
                @{ Name = 'another account'; Fixture = @{ ArmOid = '33333333-3333-3333-3333-333333333333' }; NoSessionOid = $false; ErrorId = 'AccountMismatch'; Message = 'The Azure Resource Manager token was issued to another account*' }
                @{ Name = 'no readable account'; Fixture = @{ ArmNoOid = $true }; NoSessionOid = $false; ErrorId = 'AccountMismatch'; Message = 'The account of the Azure Resource Manager token could not be read*' }
                @{ Name = 'a session that records no account'; Fixture = @{}; NoSessionOid = $true; ErrorId = 'AccountMismatch'; Message = 'The account of the Azure Resource Manager token could not be read*' }
            ) {
                foreach ($Entry in $Fixture.GetEnumerator()) {
                    Set-Variable -Scope Script -Name $Entry.Key -Value $Entry.Value
                }
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $(if ($NoSessionOid) { '' } else { $SessionOid })
                $Result = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    function Invoke-ArmSignInCommand {
                        $Result = @{}
                        try { Initialize-OPIMAuth -IncludeARM } catch { $Result.SignIn = $PSItem }
                        $Result.Refusal = Get-OPIMSignInRefusal
                        $Result.State = $script:_OPIMAuthState
                        $Result
                    }
                    Invoke-ArmSignInCommand
                }
                $Result.SignIn | Should -Not -BeNullOrEmpty -Because 'the refusal must end the function'
                $Result.SignIn.FullyQualifiedErrorId | Should -BeLike "$ErrorId*"
                $Result.SignIn.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
                $Result.SignIn.TargetObject | Should -BeExactly $TenantA
                $Result.SignIn.Exception.Message | Should -BeLike $Message
                $Result.SignIn.Exception.Message | Should -BeLike "*'$TenantA'*"
                $Result.SignIn.Exception.Message | Should -Not -BeLike '*bbbbbbbb*'
                $Result.SignIn.Exception.Message | Should -Not -BeLike '*33333333*'
                foreach ($Key in 'ArmToken', 'ArmTokenExpiry', 'ArmTokenTenantId', 'ArmTokenObjectId', 'ArmResourceUrl') {
                    $Result.State[$Key] | Should -BeNullOrEmpty -Because "nothing of a refused token may be stored ($Key)"
                }
                $Result.Refusal | Should -BeExactly 'Invoke-ArmSignInCommand'
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
            }
        }

        Context 'When the ARM sign-in fails' {
            It 'throws AzureConnectFailed with the AzAuth message only, and keeps the caller latched, in <Mode>' -ForEach @(
                @{ Mode = 'device code mode'; DeviceCode = $true }
                @{ Mode = 'the system browser'; DeviceCode = $false }
            ) {
                Mock -ModuleName Omnicit.PIM Get-AzToken { throw [System.InvalidOperationException]::new('AzAuth sign-in failure') }
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $State.DeviceCode = $DeviceCode
                $Result = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    function Invoke-ArmSignInCommand {
                        $Result = @{}
                        try { Initialize-OPIMAuth -IncludeARM } catch { $Result.SignIn = $PSItem }
                        $Result.Refusal = Get-OPIMSignInRefusal
                        $Result.State = $script:_OPIMAuthState
                        $Result
                    }
                    Invoke-ArmSignInCommand
                }
                $Result.SignIn.FullyQualifiedErrorId | Should -BeLike 'AzureConnectFailed*'
                $Result.SignIn.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
                $Result.SignIn.Exception.Message | Should -BeExactly 'Azure connection failed: AzAuth sign-in failure'
                $Result.SignIn.Exception.InnerException | Should -BeNullOrEmpty
                $Result.SignIn.TargetObject | Should -BeExactly $TenantA
                $Result.State.ArmToken | Should -BeNullOrEmpty
                $Result.State.ArmTokenTenantId | Should -BeNullOrEmpty
                $Result.Refusal | Should -BeExactly 'Invoke-ArmSignInCommand'
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
            }

            It 'throws AzureConnectFailed when Get-AzToken returns no token, and keeps the caller latched' {
                Mock -ModuleName Omnicit.PIM Get-AzToken { [PSCustomObject]@{ ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1) } }
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $Result = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    function Invoke-ArmSignInCommand {
                        $Result = @{}
                        try { Initialize-OPIMAuth -IncludeARM } catch { $Result.SignIn = $PSItem }
                        $Result.Refusal = Get-OPIMSignInRefusal
                        $Result.State = $script:_OPIMAuthState
                        $Result
                    }
                    Invoke-ArmSignInCommand
                }
                $Result.SignIn.FullyQualifiedErrorId | Should -BeLike 'AzureConnectFailed*'
                $Result.SignIn.Exception.Message | Should -BeExactly 'Azure connection failed: the Azure sign-in returned no access token.'
                $Result.SignIn.TargetObject | Should -BeExactly $TenantA
                $Result.State.ArmToken | Should -BeNullOrEmpty
                $Result.Refusal | Should -BeExactly 'Invoke-ArmSignInCommand'
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
            }

            It 'scrubs the record of the failed Get-AzToken and keeps no reference to it' {
                # The AzAuth error can carry the request it failed on. AzureConnectFailed keeps its
                # message only: no inner exception, and the session tenant as its target object. The
                # token is built at runtime and says what it is, so no token-shaped literal sits here.
                $Request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, 'https://management.azure.com/subscriptions')
                $null = $Request.Headers.TryAddWithoutValidation('Authorization', ('Bearer ' + ('x' * 40) + 'NOT-A-REAL-TOKEN'))
                $script:ArmFailureRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new('Azure sign-in failed'), 'GetAzTokenFailed', 'AuthenticationError', $Request)
                $Request.Headers.Contains('Authorization') | Should -BeTrue -Because 'the fixture must carry the header the scrub removes'
                Mock -ModuleName Omnicit.PIM Get-AzToken { $PSCmdlet.ThrowTerminatingError($script:ArmFailureRecord) }
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $Caught = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    try { Initialize-OPIMAuth -IncludeARM } catch { $PSItem }
                }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'AzureConnectFailed*'
                $Caught.Exception.Message | Should -BeLike '*Azure sign-in failed*'
                $Caught.Exception.InnerException | Should -BeNullOrEmpty
                $Caught.TargetObject | Should -BeExactly $TenantA
                $Request.Headers.Contains('Authorization') | Should -BeFalse
                $script:ArmFailureRecord = $null
            }
        }

        Context 'When the ARM sign-in shows a device code' {
            # AzAuth writes its sign-in instruction on the WARNING stream. In device code mode the module
            # re-emits it on the Information stream with the OPIMDeviceCode tag, as the Graph device
            # code is, so a host that silenced warnings still shows it (Review Focus 2).
            BeforeAll {
                $DeviceCodeText = 'To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code TESTCODE1 to authenticate.'
            }

            It 're-emits the instruction once on the Information stream with the OPIMDeviceCode tag, and no warning' {
                $script:ArmWarning = $DeviceCodeText
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $Out = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM 6>&1 3>&1
                }
                $Information = @($Out | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
                $Information.Count | Should -Be 1
                $Information[0].Tags | Should -Contain 'OPIMDeviceCode'
                [string]$Information[0].MessageData | Should -BeExactly $DeviceCodeText
                @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 0
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $DeviceCode }
            }

            It 'still shows the instruction when the host silenced warnings and information' {
                $script:ArmWarning = $DeviceCodeText
                $WarningPreference = 'SilentlyContinue'
                $InformationPreference = 'SilentlyContinue'
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $Out = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $WarningPreference = 'SilentlyContinue'
                    $InformationPreference = 'SilentlyContinue'
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM 6>&1 3>&1
                }
                $Information = @($Out | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
                $Information.Count | Should -Be 1
                $Information[0].Tags | Should -Contain 'OPIMDeviceCode'
                [string]$Information[0].MessageData | Should -BeExactly $DeviceCodeText
            }

            It 'writes the instruction whatever information preference the caller has' {
                # -InformationAction Continue on the module's own Write-Information: under a preference of
                # Ignore the record would otherwise not be written at all.
                $script:ArmWarning = $DeviceCodeText
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $Out = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $InformationPreference = 'Ignore'
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM 6>&1 3>&1
                }
                $Information = @($Out | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
                $Information.Count | Should -Be 1
                [string]$Information[0].MessageData | Should -BeExactly $DeviceCodeText
            }

            It 'leaves an AzAuth warning on the warning stream outside device code mode' {
                $script:ArmWarning = 'An unrelated AzAuth warning.'
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $State.DeviceCode = $false
                $Out = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM 6>&1 3>&1
                }
                $Warnings = @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
                $Warnings.Count | Should -Be 1
                $Warnings[0].Message | Should -BeExactly 'An unrelated AzAuth warning.'
                @($Out | Where-Object { $_ -is [System.Management.Automation.InformationRecord] }).Count | Should -Be 0
            }
        }

        Context 'When the Graph sign-in changes while an ARM token is cached' {
            # SEC (A3, Review Focus 1). An ARM token survives a new Graph token only when it was issued
            # for the same tenant and the same account; otherwise it is dropped and never sent.
            It 'keeps the cached ARM token on a forced Graph refresh for the same tenant and account' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
                $Expiry = $State.ArmTokenExpiry
                $Result = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    $Before = $State.ArmToken
                    Initialize-OPIMAuth -ForceRefresh
                    @{
                        Same  = [object]::ReferenceEquals($Before, $script:_OPIMAuthState.ArmToken)
                        State = $script:_OPIMAuthState
                    }
                }
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It
                $Result.Same | Should -BeTrue
                $Result.State.ArmTokenExpiry | Should -Be $Expiry
                $Result.State.ArmTokenTenantId | Should -BeExactly $TenantA
                $Result.State.ArmTokenObjectId | Should -BeExactly $SessionOid
                $Result.State.ArmResourceUrl | Should -BeExactly 'https://management.azure.com'
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
            }

            It 'drops the cached ARM token when the new Graph token is for another account' {
                $script:GraphOid = $OtherOid
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
                $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -ForceRefresh
                    $script:_OPIMAuthState
                }
                $After.ObjectId | Should -BeExactly $OtherOid
                foreach ($Key in 'ArmToken', 'ArmTokenExpiry', 'ArmTokenTenantId', 'ArmTokenObjectId', 'ArmResourceUrl') {
                    $After.ContainsKey($Key) | Should -BeTrue
                    $After[$Key] | Should -BeNullOrEmpty -Because "the ARM token of another account must be dropped ($Key)"
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
            }

            It 'drops the cached ARM token when the session signs in to another tenant' {
                $script:GraphTid = $TenantB
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
                $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State; TenantB = $TenantB } {
                    param($State, $TenantB)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -TenantId $TenantB
                    $script:_OPIMAuthState
                }
                $After.TokenTenantId | Should -BeExactly $TenantB
                foreach ($Key in 'ArmToken', 'ArmTokenExpiry', 'ArmTokenTenantId', 'ArmTokenObjectId', 'ArmResourceUrl') {
                    $After[$Key] | Should -BeNullOrEmpty -Because "the ARM token of another tenant must be dropped ($Key)"
                }
            }

            It 'acquires a new ARM token with -Force in the same call after <Name>' -ForEach @(
                @{ Name = 'the Graph account changed'; Account = $true }
                @{ Name = 'the session moved to another tenant'; Account = $false }
            ) {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid -Expired:$Account
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
                if ($Account) {
                    # An expired Graph token: a new sign-in without -ForceRefresh, answered by another account.
                    $script:GraphOid = $OtherOid
                    $script:ArmOid = $OtherOid
                    $Parameters = @{ IncludeARM = $true }
                } else {
                    $script:GraphTid = $TenantB
                    $script:ArmTid = $TenantB
                    $Parameters = @{ IncludeARM = $true; TenantId = $TenantB }
                }
                $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State; P = $Parameters } {
                    param($State, $P)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth @P
                    $script:_OPIMAuthState
                }
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Force }
                $After.ArmTokenObjectId | Should -BeExactly $script:ArmOid
                $After.ArmTokenTenantId | Should -BeExactly $script:ArmTid
            }

            It 'drops a cached ARM token that records no account when the new Graph token carries none either' {
                # Two unknown accounts are not the same account.
                $script:GraphNoOid = $true
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId ''
                $State.ArmTokenObjectId = $null
                $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -ForceRefresh
                    $script:_OPIMAuthState
                }
                $After.ObjectId | Should -BeNullOrEmpty
                foreach ($Key in 'ArmToken', 'ArmTokenExpiry', 'ArmTokenTenantId', 'ArmTokenObjectId', 'ArmResourceUrl') {
                    $After[$Key] | Should -BeNullOrEmpty -Because "an ARM token of an unknown account must be dropped ($Key)"
                }
            }

            It 'carries no ARM key over from a state that holds no ARM token' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
                $State.ArmToken = $null
                $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -ForceRefresh
                    $script:_OPIMAuthState
                }
                foreach ($Key in 'ArmToken', 'ArmTokenExpiry', 'ArmTokenTenantId', 'ArmTokenObjectId', 'ArmResourceUrl') {
                    $After[$Key] | Should -BeNullOrEmpty -Because "no ARM key outlives the token it describes ($Key)"
                }
            }
        }

        Context 'When a Graph sign-in writes the session' {
            It 'writes the oid of the Graph token as ObjectId, in lower case' {
                $script:GraphOid = 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'
                $After = InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                    param($TenantA)
                    $script:_OPIMAuthState = @{ DeviceCode = $true }
                    Initialize-OPIMAuth -TenantId $TenantA
                    $script:_OPIMAuthState
                }
                $After.ObjectId | Should -BeExactly 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            }

            It 'writes no ObjectId for a Graph token without an oid, and still signs in' {
                $script:GraphNoOid = $true
                $After = InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                    param($TenantA)
                    $script:_OPIMAuthState = @{ DeviceCode = $true }
                    Initialize-OPIMAuth -TenantId $TenantA
                    $script:_OPIMAuthState
                }
                $After.ContainsKey('ObjectId') | Should -BeTrue
                $After.ObjectId | Should -BeNullOrEmpty
                $After.TokenTenantId | Should -BeExactly $TenantA
                Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
            }

            It 'writes the session and its ObjectId on a first sign-in in the system browser with no state at all' {
                # The very first sign-in of a process: no auth state and no device code. A compiled
                # stand-in with the shape of MSAL's interactive flow (AcquireTokenInteractive,
                # WithUseEmbeddedWebView, ExecuteAsync) stands in for the MSAL application; nothing
                # opens a browser.
                if (-not ('OPIMTest.InteractiveApp' -as [type])) {
                    Add-Type -TypeDefinition @'
namespace OPIMTest {
    public class InteractiveAccount {
        public string Username { get; set; }
    }
    public class InteractiveResult {
        public string AccessToken { get; set; }
        public System.DateTimeOffset ExpiresOn { get; set; }
        public InteractiveAccount Account { get; set; }
    }
    public class InteractiveBuilder {
        private readonly InteractiveResult result;
        public InteractiveBuilder(InteractiveResult result) { this.result = result; }
        public InteractiveBuilder WithUseEmbeddedWebView(bool useEmbeddedWebView) { return this; }
        public System.Threading.Tasks.Task<InteractiveResult> ExecuteAsync() { return System.Threading.Tasks.Task.FromResult(result); }
    }
    public class InteractiveApp {
        public InteractiveResult Result { get; set; }
        public InteractiveBuilder AcquireTokenInteractive(System.Collections.Generic.IEnumerable<string> scopes) { return new InteractiveBuilder(Result); }
    }
}
'@
                }
                $App = [OPIMTest.InteractiveApp]::new()
                $App.Result = [OPIMTest.InteractiveResult]::new()
                $App.Result.AccessToken = New-OPIMTestAccessToken -TenantId $TenantA -ObjectId $SessionOid
                $App.Result.ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                $App.Result.Account = [OPIMTest.InteractiveAccount]::new()
                $App.Result.Account.Username = 'user@contoso.com'
                $script:InteractiveApp = $App
                Mock -ModuleName Omnicit.PIM Get-OPIMMsalApplication { $script:InteractiveApp }
                $After = InModuleScope Omnicit.PIM {
                    $script:_OPIMAuthState = $null
                    Initialize-OPIMAuth -ErrorAction Stop
                    $script:_OPIMAuthState
                }
                $After.TenantId | Should -BeExactly $TenantA
                $After.TokenTenantId | Should -BeExactly $TenantA
                $After.ObjectId | Should -BeExactly $SessionOid
                $After.DeviceCode | Should -BeFalse
                $After.ArmToken | Should -BeNullOrEmpty
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMDeviceCodeAuth -Times 0 -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
                $script:InteractiveApp = $null
            }
        }

        Context 'When the ARM sign-in runs' {
            It 'calls no Az.Accounts command in <Mode>' -ForEach @(
                @{ Mode = 'device code mode'; DeviceCode = $true }
                @{ Mode = 'the system browser'; DeviceCode = $false }
            ) {
                Mock -ModuleName Omnicit.PIM Connect-AzAccount {}
                Mock -ModuleName Omnicit.PIM Get-AzContext {}
                Mock -ModuleName Omnicit.PIM Get-AzAccessToken {}
                Mock -ModuleName Omnicit.PIM Update-AzConfig {}
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $State.DeviceCode = $DeviceCode
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Connect-AzAccount -Times 0 -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzContext -Times 0 -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzAccessToken -Times 0 -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Update-AzConfig -Times 0 -Scope It
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

        It 'does not count the state that holds only the mode as a signed-in session' {
            InModuleScope Omnicit.PIM {
                try { Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -DeviceCode } catch { $null = $PSItem }
                $script:_OPIMAuthState.ContainsKey('TenantId') | Should -BeFalse
                $script:_OPIMAuthState.ContainsKey('GraphTokenExpiry') | Should -BeFalse
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

        It 'does not relabel the session to organizations' {
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

        It 'does not adopt a Graph context the module did not make' {
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

    Context 'When the Graph token and the ARM token are handed on' {
        It 'binds the plaintext token to no command' {
            # SECURITY rule 5: PowerShell module logging (LogPipelineExecutionDetails, event 4103)
            # records every value bound to a command parameter. Static check on the function as the
            # module loaded it: no argument of any command call reaches an .AccessToken member of the
            # Graph result or a .Token member of the ARM result, so the plaintext only ever reaches
            # .NET (the SecureString is what commands receive). The only reads of .Token are the
            # NetworkCredential constructor and a truthiness test in an if.
            $Ast = InModuleScope Omnicit.PIM { (Get-Command Initialize-OPIMAuth).ScriptBlock.Ast }
            $Commands = @($Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true))
            @($Commands | Where-Object { $_.GetCommandName() -eq 'Connect-MgGraph' }).Count |
                Should -Be 1 -Because 'the walk must reach the Connect-MgGraph hand-off; a walk that reads nothing would pass vacuously'
            @($Commands | Where-Object { $_.GetCommandName() -eq 'Get-AzToken' }).Count |
                Should -Be 2 -Because 'the walk must reach both AzAuth calls, with and without the device code pipeline'
            $Hits = foreach ($Command in $Commands) {
                foreach ($Element in @($Command.CommandElements | Select-Object -Skip 1)) {
                    $Member = $Element.Find({
                            param($Node)
                            $Node -is [System.Management.Automation.Language.MemberExpressionAst] -and
                            $Node.Member.Extent.Text -in 'AccessToken', 'Token'
                        }, $true)
                    if ($Member) { 'line {0}: {1}' -f $Command.Extent.StartLineNumber, $Command.GetCommandName() }
                }
            }
            $Hits | Should -BeNullOrEmpty

            $TokenMembers = @($Ast.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.MemberExpressionAst] -and
                        $Node -isnot [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                        $Node.Member.Extent.Text -eq 'Token'
                    }, $true))
            $Uses = foreach ($Member in $TokenMembers) {
                $Parent = $Member.Parent
                if ($Parent -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                    $Parent.Member.Extent.Text -eq 'new' -and
                    $Parent.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and
                    $Parent.Expression.TypeName.FullName -eq 'System.Net.NetworkCredential' -and
                    @($Parent.Arguments | Where-Object { [object]::ReferenceEquals($_, $Member) }).Count -eq 1) {
                    'NetworkCredential'
                    continue
                }
                # A truthiness test: from the member up to an if condition through -not, -or, -and,
                # parentheses and the condition's own pipeline only.
                $Node = $Member
                $InIfCondition = $false
                while ($null -ne $Node.Parent) {
                    $Up = $Node.Parent
                    if (($Up -is [System.Management.Automation.Language.UnaryExpressionAst] -and $Up.TokenKind -in 'Not', 'Exclaim') -or
                        ($Up -is [System.Management.Automation.Language.BinaryExpressionAst] -and $Up.Operator -in 'Or', 'And') -or
                        $Up -is [System.Management.Automation.Language.ParenExpressionAst] -or
                        $Up -is [System.Management.Automation.Language.CommandExpressionAst] -or
                        $Up -is [System.Management.Automation.Language.PipelineAst]) {
                        $Node = $Up
                        continue
                    }
                    if ($Up -is [System.Management.Automation.Language.IfStatementAst] -and
                        @($Up.Clauses | Where-Object { [object]::ReferenceEquals($_.Item1, $Node) }).Count -eq 1) {
                        $InIfCondition = $true
                    }
                    break
                }
                if ($InIfCondition) { 'IfTest' } else { 'line {0}: {1}' -f $Member.Extent.StartLineNumber, $Member.Parent.Extent.Text }
            }
            @($Uses | Where-Object { $_ -eq 'NetworkCredential' }).Count | Should -Be 1 -Because 'the ARM token reaches .NET through the NetworkCredential constructor exactly once'
            @($Uses | Where-Object { $_ -eq 'IfTest' }).Count | Should -BeGreaterOrEqual 1 -Because 'the walk must find the test that the ARM result carries a token'
            @($Uses | Where-Object { $_ -notin 'NetworkCredential', 'IfTest' }) | Should -BeNullOrEmpty
        }

        It 'reads AzAuth through no command parameter in device code mode' {
            # A6: the device code pipeline re-emits AzAuth's warnings, and its last element is a script
            # block (& { process { ... } }), never ForEach-Object or Where-Object, so the token object
            # AzAuth returns is bound to no command parameter (module logging records every bound value).
            $Ast = InModuleScope Omnicit.PIM { (Get-Command Initialize-OPIMAuth).ScriptBlock.Ast }
            $Pipelines = @($Ast.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.PipelineAst] -and
                        @($Node.PipelineElements | Where-Object {
                                $_ -is [System.Management.Automation.Language.CommandAst] -and $_.GetCommandName() -eq 'Get-AzToken'
                            }).Count -gt 0
                    }, $true))
            $Piped = @($Pipelines | Where-Object { $_.PipelineElements.Count -gt 1 })
            $Piped.Count | Should -Be 1 -Because 'the device code call is the one Get-AzToken pipeline; a walk that finds none would pass vacuously'
            $Elements = @($Piped[0].PipelineElements)
            $Elements[0].GetCommandName() | Should -Be 'Get-AzToken'
            foreach ($Element in @($Elements | Select-Object -Skip 1)) {
                $Element | Should -BeOfType [System.Management.Automation.Language.CommandAst]
                $Element.InvocationOperator | Should -Be ([System.Management.Automation.Language.TokenKind]::Ampersand)
                $Element.CommandElements[0] | Should -BeOfType [System.Management.Automation.Language.ScriptBlockExpressionAst]
            }
            @($Pipelines | ForEach-Object { $_.PipelineElements } | Where-Object {
                    $_ -is [System.Management.Automation.Language.CommandAst] -and
                    $_.GetCommandName() -in 'ForEach-Object', 'Where-Object', '%', '?', 'foreach', 'where'
                }) | Should -BeNullOrEmpty
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
                Mock Get-AzToken {}
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

        It 'does not connect Graph again by itself after a change (<Name>)' -ForEach @(
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
                Should -Invoke Get-AzToken -Times 0 -Scope It
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

        It 'sends nothing for a command that carries on after a Connect-MgGraph to another session' {
            # Acceptance (OPIM-09): the module signs in, another Connect-MgGraph replaces the session,
            # and a command that carries on past its refused sign-in sends no Graph call and no ARM
            # call. The real Initialize-OPIMAuth, session functions, latch and Graph wrapper. Inside
            # Pester a terminating error always propagates (Pester's own try), so the command that
            # carries on is a module-scope test function with a try of its own around each step.
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMSignInLatch = $null
                $script:_OPIMTestToken = $Token
                $script:_OPIMTestSession = $null
                Mock Invoke-MgGraphRequest { @{ id = 'me-001' } }

                Initialize-OPIMAuth -TenantId $TenantA
                $script:_OPIMTestSession = [pscustomobject]@{
                    AuthType = 'AppOnly'; TokenCredentialType = 'ClientCertificate'
                    ClientId = 'dddddddd-0000-0000-0000-00000000000d'; TenantId = 'bbbbbbbb-0000-0000-0000-00000000000b'
                    Account = $null; AppName = 'another-app'; Environment = 'Global'; Scopes = @()
                }
                function Invoke-CarryOnCommand {
                    $Result = @{}
                    try { Initialize-OPIMAuth } catch { $Result.SignIn = $PSItem }
                    try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } catch { $Result.Graph = $PSItem }
                    $Result.Arm = Get-OPIMArmRefusal
                    $Result
                }
                $Result = Invoke-CarryOnCommand
                $Result.SignIn.FullyQualifiedErrorId | Should -BeLike 'GraphSessionChanged*'
                # The session gate comes before the latch gate in the wrapper.
                $Result.Graph.FullyQualifiedErrorId | Should -BeLike 'GraphSessionChanged*'
                # The refused sign-in latched the command, so the ARM gate refuses as well.
                $Result.Arm.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
                $Result.Arm.TargetObject | Should -BeExactly 'Invoke-CarryOnCommand'
                Should -Invoke Invoke-MgGraphRequest -Times 0 -Scope It
                Should -Invoke Connect-MgGraph -Times 1 -Exactly -Scope It
            }
        }

        It 'refuses Get-OPIMDirectoryRole after a Connect-MgGraph to another session and sends nothing' {
            # Acceptance (OPIM-09) at the public cmdlet: the real Initialize-OPIMAuth inside the real
            # Get-OPIMDirectoryRole, with every transport mocked.
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMSignInLatch = $null
                $script:_OPIMTestToken = $Token
                $script:_OPIMTestSession = $null
                Mock Invoke-MgGraphRequest { @{ value = @() } }

                Initialize-OPIMAuth -TenantId $TenantA
                # Not vacuous: under its own session the cmdlet reaches Graph.
                $null = Get-OPIMDirectoryRole
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It

                $script:_OPIMTestSession = [pscustomobject]@{
                    AuthType = 'AppOnly'; TokenCredentialType = 'ClientCertificate'
                    ClientId = 'dddddddd-0000-0000-0000-00000000000d'; TenantId = 'bbbbbbbb-0000-0000-0000-00000000000b'
                    Account = $null; AppName = 'another-app'; Environment = 'Global'; Scopes = @()
                }
                { Get-OPIMDirectoryRole } | Should -Throw -ErrorId 'GraphSessionChanged*'
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Connect-MgGraph -Times 1 -Exactly -Scope It
            }
        }
    }

    Context 'When a sign-in is refused (the latch)' {
        # SEC (EntraRBAC A19). Lock-OPIMSignIn and Unlock-OPIMSignIn are mocked: Lock hands back a
        # sentinel invocation, and every Unlock assertion names it. The acquisition runs through the
        # Invoke-OPIMDeviceCodeAuth mock, as in the pin context.
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
                Mock Lock-OPIMSignIn { $script:_OPIMTestSentinel }
                Mock Unlock-OPIMSignIn {}
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM {
                $script:_OPIMTestSentinel = $MyInvocation
                $script:_OPIMTestToken = $null
                $script:_OPIMSignInLatch = $null
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_OPIMTestToken = $null
                $script:_OPIMTestSentinel = $null
                $script:_OPIMSignInLatch = $null
                $script:_OPIMTestArmToken = $null
            }
        }

        It 'latches its caller once' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth
                Should -Invoke Lock-OPIMSignIn -Times 1 -Exactly -Scope It
            }
        }

        It 'latches its caller before anything else' {
            # Only the BL-74 check comes first. A Lock-OPIMSignIn that stops the function shows that
            # nothing else ran before it.
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -Expired
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Mock Lock-OPIMSignIn { throw [System.InvalidOperationException]::new('stopped at the latch') }
                Mock Get-OPIMGraphSessionState { 'Own' }
                Mock Get-OPIMSignInRefusal {}
                { Initialize-OPIMAuth -TenantId $TenantA -DeviceCode } | Should -Throw '*stopped at the latch*'
                Should -Invoke Get-OPIMSignInRefusal -Times 1 -Exactly -Scope It -ParameterFilter { $OutsideCaller }
                Should -Invoke Get-OPIMGraphSessionState -Times 0 -Scope It
                Should -Invoke Get-OPIMMsalApplication -Times 0 -Scope It
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 0 -Scope It
            }
        }

        It 'releases the caller on the cached return' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth
                Should -Invoke Get-OPIMMsalApplication -Times 0 -Scope It
                Should -Invoke Unlock-OPIMSignIn -Times 1 -Exactly -Scope It
                Should -Invoke Unlock-OPIMSignIn -Times 1 -Exactly -Scope It -ParameterFilter {
                    [object]::ReferenceEquals($Invocation, $script:_OPIMTestSentinel)
                }
            }
        }

        It 'releases the caller after a new sign-in that went the whole way' {
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMTestToken = $Token
                Initialize-OPIMAuth -TenantId $TenantA
                Should -Invoke Connect-MgGraph -Times 1 -Exactly -Scope It
                Should -Invoke Unlock-OPIMSignIn -Times 1 -Exactly -Scope It
                Should -Invoke Unlock-OPIMSignIn -Times 1 -Exactly -Scope It -ParameterFilter {
                    [object]::ReferenceEquals($Invocation, $script:_OPIMTestSentinel)
                }
            }
        }

        It 'releases the caller after a new sign-in and an ARM token' {
            # The Graph token and the ARM token carry the same tenant and the same (default) account.
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            $ArmToken = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; ArmToken = $ArmToken; TenantA = $TenantA } {
                param($Token, $ArmToken, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMTestToken = $Token
                $script:_OPIMTestArmToken = $ArmToken
                Mock Get-AzToken { [PSCustomObject]@{ Token = $script:_OPIMTestArmToken; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1) } }
                Initialize-OPIMAuth -TenantId $TenantA -IncludeARM
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke Unlock-OPIMSignIn -Times 1 -Exactly -Scope It
                Should -Invoke Unlock-OPIMSignIn -Times 1 -Exactly -Scope It -ParameterFilter {
                    [object]::ReferenceEquals($Invocation, $script:_OPIMTestSentinel)
                }
            }
        }

        It 'keeps the caller latched after TenantMismatch' {
            $Token = New-OPIMTestAccessToken -TenantId $TenantB
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMTestToken = $Token
                { Initialize-OPIMAuth -TenantId $TenantA } | Should -Throw -ErrorId 'TenantMismatch*'
                Should -Invoke Lock-OPIMSignIn -Times 1 -Exactly -Scope It
                Should -Invoke Unlock-OPIMSignIn -Times 0 -Scope It
            }
        }

        It 'keeps the caller latched after GraphSessionChanged' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA
            $State.GraphSessionFingerprint = 'mine'
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Mock Get-OPIMGraphSessionState { 'Changed' }
                { Initialize-OPIMAuth } | Should -Throw -ErrorId 'GraphSessionChanged*'
                Should -Invoke Lock-OPIMSignIn -Times 1 -Exactly -Scope It
                Should -Invoke Unlock-OPIMSignIn -Times 0 -Scope It
            }
        }

        It 'keeps the caller latched after a failed device code sign-in' {
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
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
                { Initialize-OPIMAuth -TenantId $TenantA } | Should -Throw -ErrorId 'DeviceCodeAuthFailed*'
                Should -Invoke Lock-OPIMSignIn -Times 1 -Exactly -Scope It
                Should -Invoke Unlock-OPIMSignIn -Times 0 -Scope It
            }
        }

        It 'keeps the caller latched after a failed ARM sign-in' {
            # The Graph token is cached and the ARM sign-in fails: AzureConnectFailed is terminating,
            # so the function ends without releasing the caller.
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Mock Get-AzToken { throw [System.Exception]::new('Azure auth failure') }
                { Initialize-OPIMAuth -IncludeARM } | Should -Throw -ErrorId 'AzureConnectFailed*'
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke Lock-OPIMSignIn -Times 1 -Exactly -Scope It
                Should -Invoke Unlock-OPIMSignIn -Times 0 -Scope It
            }
        }

        It 'refuses a sign-in under a refused outer command without a prompt' {
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMTestToken = $Token
                Mock Get-OPIMSignInRefusal { 'Enable-OPIMDirectoryRole' } -ParameterFilter { $OutsideCaller }
                Mock Get-OPIMGraphSessionState { 'Untracked' }
                { Initialize-OPIMAuth -TenantId $TenantA } | Should -Throw -ErrorId 'SignInRefused*'
                $Caught = $null
                try { Initialize-OPIMAuth -TenantId $TenantA } catch { $Caught = $PSItem }
                $Caught.TargetObject | Should -BeExactly 'Enable-OPIMDirectoryRole'
                $Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
                Should -Invoke Get-OPIMMsalApplication -Times 0 -Scope It
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 0 -Scope It
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
                Should -Invoke Get-OPIMGraphSessionState -Times 0 -Scope It
                Should -Invoke Lock-OPIMSignIn -Times 0 -Scope It
                Should -Invoke Unlock-OPIMSignIn -Times 0 -Scope It
            }
        }
    }

    Context 'When a command carries on past its refused sign-in (end to end)' {
        # Acceptance "Sparren" (EntraRBAC A19): a refused sign-in followed by a Graph and an ARM call
        # in the same command gives SignInRefused and sends nothing. The real latch, the real
        # Initialize-OPIMAuth and the real Graph wrapper, with every transport mocked. Inside Pester a
        # terminating error always propagates (Pester's own try), so the command that carries on is a
        # module-scope test function with its own try around each step, which is the shape a cmdlet
        # has outside any try.
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
                Mock Invoke-MgGraphRequest { @{ id = 'me-001' } }
                Mock Get-AzContext {}
                Mock Get-MgContext { $null }
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMSignInLatch = $null
                $script:_OPIMTestToken = $null
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_OPIMSignInLatch = $null
                $script:_OPIMTestToken = $null
            }
        }

        It 'refuses the Graph and the ARM call of the command and sends nothing' {
            $Token = New-OPIMTestAccessToken -TenantId $TenantB
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMTestToken = $Token
                function Invoke-RefusedCommand {
                    $Result = @{}
                    try { Initialize-OPIMAuth -TenantId $TenantA } catch { $Result.SignIn = $PSItem }
                    try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } catch { $Result.Graph = $PSItem }
                    $Result.Arm = Get-OPIMArmRefusal
                    $Result
                }
                $Result = Invoke-RefusedCommand
                $Result.SignIn.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
                $Result.Graph.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
                $Result.Graph.TargetObject | Should -BeExactly 'Invoke-RefusedCommand'
                $Result.Arm.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
                $Result.Arm.TargetObject | Should -BeExactly 'Invoke-RefusedCommand'
                Should -Invoke Invoke-MgGraphRequest -Times 0 -Scope It
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
            }
        }

        It 'sends again from a new command whose sign-in succeeds' {
            $Other = New-OPIMTestAccessToken -TenantId $TenantB
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Other = $Other; Token = $Token; TenantA = $TenantA } {
                param($Other, $Token, $TenantA)
                function Invoke-RefusedCommand {
                    $Result = @{}
                    try { Initialize-OPIMAuth -TenantId $TenantA } catch { $Result.SignIn = $PSItem }
                    try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } catch { $Result.Graph = $PSItem }
                    $Result
                }
                function Invoke-NextCommand {
                    $Result = @{}
                    Initialize-OPIMAuth -TenantId $TenantA
                    $Result.Graph = Invoke-OPIMGraphRequest -Uri 'v1.0/me'
                    $Result.Arm = Get-OPIMArmRefusal
                    $Result
                }
                # OPIM-08: the ARM gate also compares the Az context with the session's tenant.
                Mock Get-AzContext { [PSCustomObject]@{ Tenant = [PSCustomObject]@{ Id = 'aaaaaaaa-0000-0000-0000-00000000000a' } } }
                $script:_OPIMTestToken = $Other
                $First = Invoke-RefusedCommand
                $First.Graph.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
                $script:_OPIMTestToken = $Token
                $Next = Invoke-NextCommand
                $Next.Graph.id | Should -Be 'me-001'
                $Next.Arm | Should -BeNullOrEmpty
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Connect-MgGraph -Times 1 -Exactly -Scope It
            }
        }

        It 'refuses the ARM call of a signed-in command whose Az context is for another tenant' {
            # Acceptance (OPIM-08): the state the real sign-in wrote, and an Az context for another
            # tenant, give TenantMismatch at the ARM gate before any ARM call.
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMTestToken = $Token
                Mock Get-AzContext { [PSCustomObject]@{ Tenant = [PSCustomObject]@{ Id = 'bbbbbbbb-0000-0000-0000-00000000000b' } } }
                function Invoke-SignedInCommand {
                    Initialize-OPIMAuth -TenantId $TenantA
                    Get-OPIMArmRefusal
                }
                $Arm = Invoke-SignedInCommand
                $Arm.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch'
                $Arm.TargetObject | Should -BeExactly $TenantA
                Should -Invoke Connect-MgGraph -Times 1 -Exactly -Scope It
            }
        }

        It 'refuses a nested sign-in under the refused command' {
            # BL-74: a command the refused one calls is refused at its own sign-in, before any prompt.
            $Token = New-OPIMTestAccessToken -TenantId $TenantB
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMTestToken = $Token
                function Invoke-NestedSignIn {
                    try { Initialize-OPIMAuth -TenantId $TenantA } catch { $PSItem }
                }
                function Invoke-RefusedCommand {
                    $Result = @{}
                    try { Initialize-OPIMAuth -TenantId $TenantA } catch { $Result.SignIn = $PSItem }
                    $Result.Nested = Invoke-NestedSignIn
                    $Result
                }
                $Result = Invoke-RefusedCommand
                $Result.SignIn.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
                $Result.Nested.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
                $Result.Nested.TargetObject | Should -BeExactly 'Invoke-RefusedCommand'
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Exactly -Scope It
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
            }
        }

        It 'lets the refused command sign in again itself' {
            # The caller's own latched frame does not count for BL-74, so the same command may retry
            # its sign-in; a success then releases it and its next request is sent.
            $Other = New-OPIMTestAccessToken -TenantId $TenantB
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Other = $Other; Token = $Token; TenantA = $TenantA } {
                param($Other, $Token, $TenantA)
                function Invoke-RetryingCommand {
                    $Result = @{}
                    $script:_OPIMTestToken = $Other
                    try { Initialize-OPIMAuth -TenantId $TenantA } catch { $Result.SignIn = $PSItem }
                    $script:_OPIMTestToken = $Token
                    Initialize-OPIMAuth -TenantId $TenantA
                    $Result.Graph = Invoke-OPIMGraphRequest -Uri 'v1.0/me'
                    $Result
                }
                $Result = Invoke-RetryingCommand
                $Result.SignIn.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
                $Result.Graph.id | Should -Be 'me-001'
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 2 -Exactly -Scope It
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
            }
        }
    }
}
