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
        $script:SeenAuthorityHost = 'Get-AzToken was not called'
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
                # The authority AzAuth would read while it builds its credential (OPIM-29): $null when
                # the variable is absent. Reset-ArmTestFixture puts a marker here before every It.
                $script:SeenAuthorityHost = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')
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
            # AZURE_AUTHORITY_HOST is process-wide state that the Azure sign-in reads, sets around
            # Get-AzToken for a sovereign cloud and warns about in the Global cloud (OPIM-29). Every It
            # here starts with it absent and puts the operator's own value back afterwards, so no test
            # leaks it, none depends on the environment the suite runs in (a runner that sets it would add
            # a Global warning to the tests that count warnings) and the restore does not rely on the code
            # under test. [NullString]::Value, not $null: $null would leave an empty variable behind.
            $script:SavedAuthorityHost = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
        }
        AfterEach {
            if ($null -eq $script:SavedAuthorityHost) {
                [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
            } else {
                [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $script:SavedAuthorityHost)
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

            It 'waits 900 seconds for the Azure sign-in, as long as a device code lives, in <Mode>' -ForEach @(
                @{ Mode = 'device code mode'; DeviceCode = $true }
                @{ Mode = 'the system browser'; DeviceCode = $false }
            ) {
                # AzAuth stops waiting after 120 seconds by default, much less than a device code lives.
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $State.DeviceCode = $DeviceCode
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $TimeoutSeconds -eq 900 }
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

        Context 'When the Azure sign-in follows the cloud (OPIM-29)' {
            # A11. AzAuth is asked for the ARM resource of the session's cloud, and the authority
            # Azure.Identity signs in at moves with it through AZURE_AUTHORITY_HOST. That variable is
            # process-wide state the module borrows: it is set only off Global, only around Get-AzToken,
            # and put back on every path. The enclosing -IncludeARM context starts every It with the
            # variable absent and puts the operator's own value back afterwards. The Get-AzToken mock
            # above records what it saw in $script:SeenAuthorityHost ($null for an absent variable).
            BeforeAll {
                # Signs in with -IncludeARM on a state and returns the error it raised (if any), the state
                # afterwards and the warnings it wrote.
                function Invoke-CloudArmSignIn {
                    param([hashtable]$State, [hashtable]$Arguments = @{})
                    InModuleScope Omnicit.PIM -Parameters @{ State = $State; Arguments = $Arguments } {
                        param($State, $Arguments)
                        $script:_OPIMAuthState = $State
                        $Caught = $null
                        $Warned = $null
                        try {
                            Initialize-OPIMAuth -IncludeARM @Arguments -WarningVariable Warned -WarningAction SilentlyContinue
                        } catch {
                            $Caught = $PSItem
                        }
                        @{ Caught = $Caught; State = $script:_OPIMAuthState; Warnings = @($Warned) }
                    }
                }
            }

            It 'asks AzAuth for the ARM resource of <Name>, and the new state records it' -ForEach @(
                @{ Name = 'Global'; Cloud = 'Global'; Expected = 'https://management.azure.com' }
                @{ Name = 'a session that records no cloud'; Cloud = $null; Expected = 'https://management.azure.com' }
                @{ Name = 'USGov'; Cloud = 'USGov'; Expected = 'https://management.usgovcloudapi.net' }
                @{ Name = 'USGovDoD'; Cloud = 'USGovDoD'; Expected = 'https://management.usgovcloudapi.net' }
                @{ Name = 'China'; Cloud = 'China'; Expected = 'https://management.chinacloudapi.cn' }
            ) {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                if ($Cloud) { $State.Environment = $Cloud }
                $Result = Invoke-CloudArmSignIn -State $State
                $Result.Caught | Should -BeNullOrEmpty
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Resource -ceq $Expected -and $Tenant -ceq 'aaaaaaaa-0000-0000-0000-00000000000a'
                }
                $Result.State.ArmResourceUrl | Should -BeExactly $Expected
            }

            It 'asks AzAuth for the ARM resource of the cloud a call names, in a first sign-in' {
                $Result = Invoke-CloudArmSignIn -State @{ DeviceCode = $true } -Arguments @{ TenantId = $TenantA; Environment = 'China' }
                $Result.Caught | Should -BeNullOrEmpty
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Resource -ceq 'https://management.chinacloudapi.cn'
                }
                $Result.State.Environment | Should -BeExactly 'China'
                $Result.State.ArmResourceUrl | Should -BeExactly 'https://management.chinacloudapi.cn'
            }

            It 'sets AZURE_AUTHORITY_HOST to the authority of <Name> while Get-AzToken runs' -ForEach @(
                @{ Name = 'USGov'; Cloud = 'USGov'; DeviceCode = $true; Expected = 'https://login.microsoftonline.us/' }
                @{ Name = 'USGovDoD'; Cloud = 'USGovDoD'; DeviceCode = $true; Expected = 'https://login.microsoftonline.us/' }
                @{ Name = 'China'; Cloud = 'China'; DeviceCode = $true; Expected = 'https://login.chinacloudapi.cn/' }
                @{ Name = 'USGov in the system browser'; Cloud = 'USGov'; DeviceCode = $false; Expected = 'https://login.microsoftonline.us/' }
            ) {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $State.Environment = $Cloud
                $State.DeviceCode = $DeviceCode
                $Result = Invoke-CloudArmSignIn -State $State
                $Result.Caught | Should -BeNullOrEmpty
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                $script:SeenAuthorityHost | Should -BeExactly $Expected
            }

            It 'writes no AZURE_AUTHORITY_HOST in the Global cloud (<Name>)' -ForEach @(
                @{ Name = 'a session in Global'; Cloud = 'Global' }
                @{ Name = 'a session that records no cloud'; Cloud = $null }
            ) {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                if ($Cloud) { $State.Environment = $Cloud }
                $Result = Invoke-CloudArmSignIn -State $State
                $Result.Caught | Should -BeNullOrEmpty
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                $null -eq $script:SeenAuthorityHost | Should -BeTrue -Because 'the Global path writes no AZURE_AUTHORITY_HOST at all'
                Test-Path Env:AZURE_AUTHORITY_HOST | Should -BeFalse
            }

            It 'removes AZURE_AUTHORITY_HOST again after a <Cloud> sign-in when it was not set' -ForEach @(
                @{ Cloud = 'USGov' }
                @{ Cloud = 'China' }
            ) {
                # Review Focus 2. Absent stays absent: not '', which Test-Path Env: would still find.
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $State.Environment = $Cloud
                $Result = Invoke-CloudArmSignIn -State $State
                $Result.Caught | Should -BeNullOrEmpty
                $script:SeenAuthorityHost | Should -Not -BeNullOrEmpty -Because 'the variable was set while Get-AzToken ran'
                Test-Path Env:AZURE_AUTHORITY_HOST | Should -BeFalse
                $null -eq [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -BeTrue
            }

            It 'puts the operator''s own AZURE_AUTHORITY_HOST back after a <Cloud> sign-in' -ForEach @(
                @{ Cloud = 'USGov'; Expected = 'https://login.microsoftonline.us/' }
                @{ Cloud = 'China'; Expected = 'https://login.chinacloudapi.cn/' }
            ) {
                # Review Focus 2. A value the operator set is put back exactly, not deleted.
                [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', 'https://login.example.com/')
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $State.Environment = $Cloud
                $Result = Invoke-CloudArmSignIn -State $State
                $Result.Caught | Should -BeNullOrEmpty
                $script:SeenAuthorityHost | Should -BeExactly $Expected -Because 'the cloud''s authority replaces the operator''s value for the call'
                [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -BeExactly 'https://login.example.com/'
            }

            It 'restores AZURE_AUTHORITY_HOST when Get-AzToken throws and the variable was <Was>' -ForEach @(
                @{ Was = 'absent'; Operator = $null }
                @{ Was = 'set by the operator'; Operator = 'https://login.example.com/' }
            ) {
                Mock -ModuleName Omnicit.PIM Get-AzToken { throw [System.InvalidOperationException]::new('AzAuth sign-in failure') }
                if ($null -ne $Operator) { [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $Operator) }
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $State.Environment = 'USGov'
                $Result = Invoke-CloudArmSignIn -State $State
                $Result.Caught.FullyQualifiedErrorId | Should -BeLike 'AzureConnectFailed*'
                $Result.Caught.Exception.Message | Should -BeExactly 'Azure connection failed: AzAuth sign-in failure'
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                Test-Path Env:AZURE_AUTHORITY_HOST | Should -Be ($null -ne $Operator)
                [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -Be $Operator
            }

            It 'restores AZURE_AUTHORITY_HOST when the ARM token is refused and the variable was <Was>' -ForEach @(
                @{ Was = 'absent'; Operator = $null }
                @{ Was = 'set by the operator'; Operator = 'https://login.example.com/' }
            ) {
                $script:ArmTid = $TenantB
                if ($null -ne $Operator) { [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $Operator) }
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $State.Environment = 'USGov'
                $Result = Invoke-CloudArmSignIn -State $State
                $Result.Caught.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                $script:SeenAuthorityHost | Should -BeExactly 'https://login.microsoftonline.us/'
                Test-Path Env:AZURE_AUTHORITY_HOST | Should -Be ($null -ne $Operator)
                [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -Be $Operator
            }

            It 'warns when AZURE_AUTHORITY_HOST names another authority in the Global cloud, and leaves it as it is' {
                [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', 'https://login.example.com/')
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $Result = Invoke-CloudArmSignIn -State $State
                $Result.Caught | Should -BeNullOrEmpty
                @($Result.Warnings).Count | Should -Be 1
                $Result.Warnings[0].Message | Should -BeLike '*AZURE_AUTHORITY_HOST is set to ''https://login.example.com/''*'
                $Result.Warnings[0].Message | Should -BeLike '*global cloud''s authority ''https://login.microsoftonline.com/''*'
                $Result.Warnings[0].Message | Should -BeLike '*Remove-Item Env:AZURE_AUTHORITY_HOST*'
                # The Global path writes nothing: AzAuth was still called, and saw the operator's value.
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                $script:SeenAuthorityHost | Should -BeExactly 'https://login.example.com/'
                [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -BeExactly 'https://login.example.com/'
            }

            It 'does not warn when AZURE_AUTHORITY_HOST names the global authority <Spelling>' -ForEach @(
                @{ Spelling = 'with a trailing slash'; Value = 'https://login.microsoftonline.com/' }
                @{ Spelling = 'without a trailing slash'; Value = 'https://login.microsoftonline.com' }
            ) {
                [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $Value)
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $Result = Invoke-CloudArmSignIn -State $State
                $Result.Caught | Should -BeNullOrEmpty
                @($Result.Warnings).Count | Should -Be 0
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                $script:SeenAuthorityHost | Should -BeExactly $Value
                [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -BeExactly $Value
            }

            It 'does not warn about AZURE_AUTHORITY_HOST when the cloud is sovereign, where it is replaced for the call' {
                [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', 'https://login.example.com/')
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $State.Environment = 'USGov'
                $Result = Invoke-CloudArmSignIn -State $State
                $Result.Caught | Should -BeNullOrEmpty
                @($Result.Warnings).Count | Should -Be 0
            }

            It 'passes -Force on the ARM sign-in after a cloud switch, and never reuses the old cloud''s ARM token' {
                # Review Focus 4. The session is in Global with a valid ARM token for its tenant and
                # account; naming USGov signs in again, drops that token and rebuilds AzAuth's credential
                # (it keeps one per process and bakes its authority in), now for the USGov resource.
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $State.Environment = 'Global'
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
                $OldToken = $State.ArmToken
                $Result = Invoke-CloudArmSignIn -State $State -Arguments @{ Environment = 'USGov' }
                $Result.Caught | Should -BeNullOrEmpty
                Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Force -and $Resource -ceq 'https://management.usgovcloudapi.net'
                }
                [object]::ReferenceEquals($OldToken, $Result.State.ArmToken) | Should -BeFalse
                $Result.State.Environment | Should -BeExactly 'USGov'
                $Result.State.ArmResourceUrl | Should -BeExactly 'https://management.usgovcloudapi.net'
            }

            It 'does not reuse an ARM token recorded for another cloud''s resource' {
                # Unreachable by construction -- a cloud switch drops the token, and a state records its
                # cloud and its resource together -- so this guards the resource term of the cache check:
                # a USGov session, a valid Graph token and an ARM token for the same tenant and account
                # with an hour left, but minted for the global resource.
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $State.Environment = 'USGov'
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
                $State.ArmResourceUrl | Should -BeExactly 'https://management.azure.com'
                $OldToken = $State.ArmToken
                $Result = Invoke-CloudArmSignIn -State $State
                $Result.Caught | Should -BeNullOrEmpty
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Force -and $Resource -ceq 'https://management.usgovcloudapi.net'
                }
                [object]::ReferenceEquals($OldToken, $Result.State.ArmToken) | Should -BeFalse
                $Result.State.ArmResourceUrl | Should -BeExactly 'https://management.usgovcloudapi.net'
            }

            It 'reuses an ARM token recorded for the resource of the session''s own cloud, without a call' {
                # The positive control of the test above: the same token, minted for the session's own
                # resource, is reused.
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $State.Environment = 'USGov'
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
                $State.ArmResourceUrl = 'https://management.usgovcloudapi.net'
                $OldToken = $State.ArmToken
                $Result = Invoke-CloudArmSignIn -State $State
                $Result.Caught | Should -BeNullOrEmpty
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
                [object]::ReferenceEquals($OldToken, $Result.State.ArmToken) | Should -BeTrue
                $Result.State.ArmResourceUrl | Should -BeExactly 'https://management.usgovcloudapi.net'
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

            It 'refuses to reuse a cached token for a session that records no account, and shows no sign-in for one' {
                # Two unknown accounts are not the same account, and no ARM token can be kept for a
                # session without one: AccountMismatch before Get-AzToken, so AzAuth shows no sign-in.
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId ''
                $State.ArmTokenObjectId = $null
                $Caught = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    try { Initialize-OPIMAuth -IncludeARM } catch { $PSItem }
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
                $Caught.FullyQualifiedErrorId | Should -BeLike 'AccountMismatch*'
                $Caught.Exception.Message | Should -BeLike 'The account of the Azure Resource Manager token could not be read*'
                $Caught.TargetObject | Should -BeExactly $TenantA
            }
        }

        Context 'When the ARM token is not for the tenant and the account of the Graph session' {
            # SEC (A3, OPIM-47). Each refusal is terminating, stores nothing of the token and leaves the
            # calling command latched. The command is a module-scope test function with a try of its
            # own, so it carries on and reads the latch after the refusal.
            It 'refuses a token for <Name> with <ErrorId>, stores nothing and keeps the caller latched' -ForEach @(
                @{ Name = 'another tenant'; Fixture = @{ ArmTid = 'bbbbbbbb-0000-0000-0000-00000000000b' }; NoSessionOid = $false; ErrorId = 'TenantMismatch'; Message = 'The Azure Resource Manager token was issued for another tenant than *'; Calls = 1 }
                @{ Name = 'no readable tenant'; Fixture = @{ ArmNoTid = $true }; NoSessionOid = $false; ErrorId = 'TenantMismatch'; Message = 'The tenant of the Azure Resource Manager token could not be read*'; Calls = 1 }
                @{ Name = 'another account'; Fixture = @{ ArmOid = '33333333-3333-3333-3333-333333333333' }; NoSessionOid = $false; ErrorId = 'AccountMismatch'; Message = 'The Azure Resource Manager token was issued to another account*'; Calls = 1 }
                @{ Name = 'no readable account'; Fixture = @{ ArmNoOid = $true }; NoSessionOid = $false; ErrorId = 'AccountMismatch'; Message = 'The account of the Azure Resource Manager token could not be read*'; Calls = 1 }
                # Refused before Get-AzToken: no ARM token can be kept for a session without an account,
                # so no AzAuth sign-in is shown for one.
                @{ Name = 'a session that records no account'; Fixture = @{}; NoSessionOid = $true; ErrorId = 'AccountMismatch'; Message = 'The account of the Azure Resource Manager token could not be read*'; Calls = 0 }
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
                if ($Calls -eq 0) {
                    Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
                } else {
                    Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times $Calls -Exactly -Scope It
                }
            }

            It 'drops the ARM token the state held when it refuses a new token for <Name>, and rebuilds the credential on the next sign-in' -ForEach @(
                @{ Name = 'another tenant'; Fixture = @{ ArmTid = 'bbbbbbbb-0000-0000-0000-00000000000b' }; ErrorId = 'TenantMismatch' }
                @{ Name = 'no readable tenant'; Fixture = @{ ArmNoTid = $true }; ErrorId = 'TenantMismatch' }
                @{ Name = 'another account'; Fixture = @{ ArmOid = '33333333-3333-3333-3333-333333333333' }; ErrorId = 'AccountMismatch' }
                @{ Name = 'no readable account'; Fixture = @{ ArmNoOid = $true }; ErrorId = 'AccountMismatch' }
            ) {
                # The state holds an ARM token of the session's own tenant and account with 4 minutes
                # left, so the first call acquires a new one WITHOUT -Force -- and that one is refused.
                # AzAuth's credential has just answered for another tenant or account: the refusal drops
                # the held token too, so the next sign-in rebuilds the credential (-Force).
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid -Expiry ([DateTime]::UtcNow.AddMinutes(4))
                foreach ($Entry in $Fixture.GetEnumerator()) {
                    Set-Variable -Scope Script -Name $Entry.Key -Value $Entry.Value
                }
                $First = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    function Invoke-ArmSignInCommand {
                        $Result = @{}
                        try { Initialize-OPIMAuth -IncludeARM } catch { $Result.SignIn = $PSItem }
                        $Result.State = $script:_OPIMAuthState
                        $Result
                    }
                    Invoke-ArmSignInCommand
                }
                $First.SignIn.FullyQualifiedErrorId | Should -BeLike "$ErrorId*"
                foreach ($Key in 'ArmToken', 'ArmTokenExpiry', 'ArmTokenTenantId', 'ArmTokenObjectId', 'ArmResourceUrl') {
                    $First.State.ContainsKey($Key) | Should -BeTrue
                    $First.State[$Key] | Should -BeNullOrEmpty -Because "a refused token drops the ARM token the state held ($Key)"
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It -ParameterFilter { $Force }

                # The next sign-in, of a new command: AzAuth now answers for the session's tenant and account.
                Reset-ArmTestFixture
                $Next = InModuleScope Omnicit.PIM {
                    function Invoke-NextSignInCommand {
                        Initialize-OPIMAuth -IncludeARM
                        $script:_OPIMAuthState
                    }
                    Invoke-NextSignInCommand
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 2 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Force }
                $Next.ArmToken | Should -BeOfType [securestring]
                $Next.ArmTokenObjectId | Should -BeExactly $SessionOid
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

            It 'says that AzAuth is missing when Get-AzToken cannot be found (<Name>)' -ForEach @(
                @{ Name = 'the error a missing command raises'; Shape = 'Missing' }
                @{ Name = 'a CommandNotFoundException under another error id'; Shape = 'Exception' }
                @{ Name = 'the CommandNotFoundException error id with another exception'; Shape = 'ErrorId' }
            ) {
                $script:MissingShape = $Shape
                Mock -ModuleName Omnicit.PIM Get-AzToken {
                    $Missing = [System.Management.Automation.CommandNotFoundException]::new("The term 'Get-AzToken' is not recognized as a name of a cmdlet, function, script file, or executable program.")
                    switch ($script:MissingShape) {
                        'Missing' { throw $Missing }
                        'Exception' {
                            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                                    $Missing, 'GetAzTokenFailed', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null))
                        }
                        'ErrorId' {
                            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                                    [System.Exception]::new("The term 'Get-AzToken' is not recognized."), 'CommandNotFoundException',
                                    [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null))
                        }
                    }
                }
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
                $Caught = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    try { Initialize-OPIMAuth -IncludeARM } catch { $PSItem }
                }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'AzureConnectFailed*'
                $Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
                $Caught.Exception.Message | Should -BeExactly 'Azure connection failed: the AzAuth module is not installed or could not be loaded. Install AzAuth 2.9.0 from the PowerShell Gallery; it needs PowerShell 7.4 or later.'
                $Caught.Exception.InnerException | Should -BeNullOrEmpty
                $Caught.TargetObject | Should -BeExactly $TenantA
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                $script:MissingShape = $null
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

            It 'shows the instruction when the host silenced warnings and information' {
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

    Context 'When the session is in a cloud (OPIM-29)' {
        # A11. The cloud is a property of the tenant: a call that names the session's tenant and no cloud
        # keeps the session's cloud, a call for another tenant that names none is Global, and a call that
        # names another cloud than the session's is a new sign-in. The mocks are those of the -IncludeARM
        # context: the Graph SDK session is the module's own, and Invoke-OPIMDeviceCodeAuth hands back a
        # token built from this file's $script:Graph* values (Reset-ArmTestFixture sets them before every
        # It), so the acquisition runs in device code mode and reflects into no MSAL.
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
            # A stand-in for the MSAL application, with the one shape the silent step reflects into
            # (AcquireTokenSilent(IEnumerable<string>, IAccount), found by parameter type NAME) and a
            # counter, so a test can see which cloud's application was asked for a token. It makes no
            # call and holds no token cache; SilentFails stands for an application with nothing cached.
            if (-not ('OPIMTestMsal.FakeApp' -as [type])) {
                Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
namespace OPIMTestMsal {
    public interface IAccount { string Username { get; } }
    public class FakeAccount : IAccount { public string Username { get; set; } }
    public class FakeMetadata { public string TokenSource = "Cache"; }
    public class FakeResult {
        public string AccessToken;
        public DateTimeOffset ExpiresOn;
        public IAccount Account;
        public FakeMetadata AuthenticationResultMetadata = new FakeMetadata();
    }
    public class FakeSilentBuilder {
        private readonly FakeApp _app;
        public FakeSilentBuilder(FakeApp app) { _app = app; }
        public Task<FakeResult> ExecuteAsync() {
            if (_app.SilentFails) { throw new InvalidOperationException("nothing cached in this application"); }
            return Task.FromResult(_app.Result);
        }
    }
    public class FakeApp {
        public string Name;
        public int SilentCalls;
        public bool SilentFails;
        public FakeResult Result;
        public FakeSilentBuilder AcquireTokenSilent(IEnumerable<string> scopes, IAccount account) {
            SilentCalls++;
            return new FakeSilentBuilder(this);
        }
    }
}
'@
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

        It 'records the cloud it signed in to as Environment in the state' {
            $After = InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                Initialize-OPIMAuth -TenantId $TenantA -Environment USGov
                $WithCloud = $script:_OPIMAuthState
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMSignInLatch = $null
                Initialize-OPIMAuth -TenantId $TenantA
                @{ WithCloud = $WithCloud; WithoutCloud = $script:_OPIMAuthState }
            }
            $After.WithCloud.ContainsKey('Environment') | Should -BeTrue
            $After.WithCloud.Environment | Should -BeExactly 'USGov'
            $After.WithoutCloud.ContainsKey('Environment') | Should -BeTrue
            $After.WithoutCloud.Environment | Should -BeExactly 'Global'
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 2 -Exactly -Scope It
        }

        It 'returns the cached session for -Environment Global when the session was signed in without one' {
            # Review Focus 3: a state written before the cloud was recorded is Global, so naming Global is the
            # same session -- no new sign-in, no MSAL application, no Connect-MgGraph.
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
            $State.ContainsKey('Environment') | Should -BeFalse
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment Global
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMDeviceCodeAuth -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
        }

        It 'returns the cached session for -Environment Global when the session was signed in to Global' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
            $State.Environment = 'Global'
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment Global
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMDeviceCodeAuth -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
        }

        It 'keeps the session''s cloud when a call names neither a tenant nor a cloud' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
            $State.Environment = 'USGov'
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth
                $script:_OPIMAuthState
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
            $After.Environment | Should -BeExactly 'USGov'
        }

        It 'keeps the session''s cloud for the tenant label the session was signed in under' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
            $State.Environment = 'USGov'
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; TenantA = $TenantA } {
                param($State, $TenantA)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -TenantId $TenantA
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
        }

        It 'keeps the session''s cloud for a GUID equal to the session''s token tenant' {
            # A session pinned by domain: the GUID its Graph token was issued for is the same tenant.
            $State = New-PinState -TenantId 'contoso.onmicrosoft.com' -TokenTenantId $TenantA -AuthorityTenant 'contoso.onmicrosoft.com' -ObjectId $SessionOid
            $State.Environment = 'USGov'
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State; TenantA = $TenantA } {
                param($State, $TenantA)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -TenantId $TenantA
                $script:_OPIMAuthState
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
            $After.Environment | Should -BeExactly 'USGov'
        }

        It 'signs in again when a call names another cloud than the session''s' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
            $State.Environment = 'Global'
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment USGov
                $script:_OPIMAuthState
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
            $After.Environment | Should -BeExactly 'USGov'
            $After.TenantId | Should -BeExactly $TenantA
        }

        It 'signs in again when a call names another cloud than a session that records none' {
            # A state written before the cloud was recorded is Global, so naming a sovereign cloud is a switch.
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment USGovDoD
                $script:_OPIMAuthState
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 1 -Exactly -Scope It
            $After.Environment | Should -BeExactly 'USGovDoD'
        }

        It 'signs in again for Global when the session is in a sovereign cloud and the call names Global' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
            $State.Environment = 'China'
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment Global
                $script:_OPIMAuthState
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 1 -Exactly -Scope It
            $After.Environment | Should -BeExactly 'Global'
        }

        It 'is Global for another tenant that names no cloud, whatever the session''s cloud' {
            $script:GraphTid = $TenantB
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
            $State.Environment = 'USGov'
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State; TenantB = $TenantB } {
                param($State, $TenantB)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -TenantId $TenantB
                $script:_OPIMAuthState
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 1 -Exactly -Scope It
            $After.TenantId | Should -BeExactly $TenantB
            $After.Environment | Should -BeExactly 'Global'
        }

        It 'keeps the cloud on a forced refresh of the session and keeps its ARM token' {
            # The positive control of the cloud term of the ARM token: the same cloud carries the token.
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
            $State.Environment = 'USGov'
            $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
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
            $Result.State.Environment | Should -BeExactly 'USGov'
            $Result.Same | Should -BeTrue
        }

        It 'drops the cached ARM token when the session signs in to another cloud' {
            # Review Focus 4: an ARM token minted in one cloud is never carried into another, even for the
            # same tenant and the same account.
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
            $State.Environment = 'Global'
            $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment USGov
                $script:_OPIMAuthState
            }
            $After.Environment | Should -BeExactly 'USGov'
            foreach ($Key in 'ArmToken', 'ArmTokenExpiry', 'ArmTokenTenantId', 'ArmTokenObjectId', 'ArmResourceUrl') {
                $After.ContainsKey($Key) | Should -BeTrue
                $After[$Key] | Should -BeNullOrEmpty -Because "the ARM token of another cloud must be dropped ($Key)"
            }
        }

        It 'reads the cloud name in any letter case and records the canonical name' {
            $After = InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                Initialize-OPIMAuth -TenantId $TenantA -Environment usgov
                $script:_OPIMAuthState
            }
            $After.Environment | Should -BeExactly 'USGov'
        }

        It 'does not treat the same cloud in another letter case as a switch' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
            $State.Environment = 'USGov'
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment USGOV
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
        }

        It 'refuses a cloud outside the ValidateSet before anything is called' {
            $Caught = InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $Caught = $null
                try { Initialize-OPIMAuth -Environment Germany } catch { $Caught = $PSItem }
                $Caught
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'ParameterArgumentValidationError,Initialize-OPIMAuth'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMDeviceCodeAuth -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
        }

        It 'names the cloud in the verbose line of a sign-in' {
            $Out = InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                Initialize-OPIMAuth -TenantId $TenantA -Environment USGov -Verbose 4>&1
            }
            $Lines = @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
            @($Lines | Where-Object { $_ -like "*Acquiring Graph token for tenant*cloud 'USGov'*" }).Count | Should -Be 1
        }

        It 'builds the MSAL app for the cloud of the sign-in: <Name>' -ForEach @(
            @{ Name = 'Global' }
            @{ Name = 'USGov' }
            @{ Name = 'USGovDoD' }
            @{ Name = 'China' }
        ) {
            $Cloud = $Name
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA; Cloud = $Cloud } {
                param($TenantA, $Cloud)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                Initialize-OPIMAuth -TenantId $TenantA -Environment $Cloud
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 1 -Exactly -Scope It -ParameterFilter {
                $Environment -ceq $Cloud -and $TenantId -ceq 'aaaaaaaa-0000-0000-0000-00000000000a'
            }
        }

        It 'builds the MSAL app for the canonical name of a cloud typed in another letter case' {
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                Initialize-OPIMAuth -TenantId $TenantA -Environment usgovdod
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 1 -Exactly -Scope It -ParameterFilter { $Environment -ceq 'USGovDoD' }
        }

        It 'builds the MSAL app for the session''s cloud on a refresh that names no cloud' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant 'organizations' -ObjectId $SessionOid
            $State.Environment = 'USGov'
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -ForceRefresh
            }
            # The same cloud keeps the authority the session was built with, so the app and its token
            # cache are reused; only the cloud decides which application that is.
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 1 -Exactly -Scope It -ParameterFilter {
                $Environment -ceq 'USGov' -and $TenantId -ceq 'organizations'
            }
        }

        It 'asks the new cloud''s MSAL application, not the old cloud''s, for a token on a switch of cloud' {
            # Carried from the Task 2 review (load-bearing): the session was signed in to Global with an
            # account cached. Naming USGov must build and use the USGov application; the Global
            # application, which holds a token of the Global cloud, is never asked for one.
            $script:GlobalApp = [OPIMTestMsal.FakeApp]@{ Name = 'Global app' }
            $script:UsGovApp = [OPIMTestMsal.FakeApp]@{ Name = 'USGov app'; SilentFails = $true }
            Mock -ModuleName Omnicit.PIM Get-OPIMMsalApplication { $script:GlobalApp } -ParameterFilter { $Environment -ceq 'Global' }
            Mock -ModuleName Omnicit.PIM Get-OPIMMsalApplication { $script:UsGovApp } -ParameterFilter { $Environment -ceq 'USGov' }
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
            $State.Environment = 'Global'
            $State.Account = [OPIMTestMsal.FakeAccount]@{ Username = 'user@contoso.com' }
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment USGov
                $script:_OPIMAuthState
            }
            $script:GlobalApp.SilentCalls | Should -Be 0
            $script:UsGovApp.SilentCalls | Should -Be 1 -Because 'the silent step runs against the application of the cloud being signed in to, which has nothing cached'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 1 -Exactly -Scope It -ParameterFilter { $Environment -ceq 'USGov' }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 0 -Scope It -ParameterFilter { $Environment -ceq 'Global' }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It -ParameterFilter { $MsalApp.Name -ceq 'USGov app' }
            $After.Environment | Should -BeExactly 'USGov'
        }

        It 'asks the MSAL application of the same cloud for a token on a refresh' {
            # The positive control of the test above: the stand-in does record a silent call when the code
            # asks it, so a count of 0 there means the old cloud's application was not asked.
            $script:UsGovApp = [OPIMTestMsal.FakeApp]@{
                Name   = 'USGov app'
                Result = [OPIMTestMsal.FakeResult]@{
                    AccessToken = New-OPIMTestAccessToken -TenantId $TenantA -ObjectId $SessionOid
                    ExpiresOn   = [DateTimeOffset]::UtcNow.AddHours(1)
                    Account     = [OPIMTestMsal.FakeAccount]@{ Username = 'user@contoso.com' }
                }
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMMsalApplication { $script:UsGovApp } -ParameterFilter { $Environment -ceq 'USGov' }
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
            $State.Environment = 'USGov'
            $State.Account = [OPIMTestMsal.FakeAccount]@{ Username = 'user@contoso.com' }
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -ForceRefresh
            }
            $script:UsGovApp.SilentCalls | Should -Be 1
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMDeviceCodeAuth -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
        }

        It 'builds the MSAL app for the requested tenant, not the session''s authority, on a switch of cloud' {
            # Carried from the Task 2 review: the session was built under 'organizations'. A refresh in the
            # same cloud reuses that authority (the test above); a switch of cloud is a new application and
            # authority, built for the tenant the call asked for.
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant 'organizations' -ObjectId $SessionOid
            $State.Environment = 'Global'
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment USGov
                $script:_OPIMAuthState
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 1 -Exactly -Scope It -ParameterFilter {
                $TenantId -ceq 'aaaaaaaa-0000-0000-0000-00000000000a' -and $Environment -ceq 'USGov'
            }
            $After.AuthorityTenant | Should -BeExactly $TenantA
            $After.Environment | Should -BeExactly 'USGov'
        }

        It 'holds the token of a domain session that switches cloud to no tenant, and records its tid' {
            # Carried from the Task 2 review: nothing in the new cloud is known to compare with (a tenant has
            # another GUID in another cloud), so a domain-labelled session is pinned afresh to the tid of
            # the first token of the new session, as a first sign-in under a domain is.
            $script:GraphTid = $TenantB
            $State = New-PinState -TenantId 'contoso.onmicrosoft.com' -TokenTenantId $TenantA -AuthorityTenant 'contoso.onmicrosoft.com' -ObjectId $SessionOid
            $State.Environment = 'Global'
            $Result = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                $Caught = $null
                try { Initialize-OPIMAuth -Environment USGov } catch { $Caught = $PSItem }
                @{ Caught = $Caught; State = $script:_OPIMAuthState }
            }
            $Result.Caught | Should -BeNullOrEmpty
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
            $Result.State.TenantId | Should -BeExactly 'contoso.onmicrosoft.com'
            $Result.State.TokenTenantId | Should -BeExactly $TenantB
            $Result.State.Environment | Should -BeExactly 'USGov'
        }

        It 'refuses the token of another tenant when a GUID session switches cloud, and leaves the session as it was' {
            $script:GraphTid = $TenantB
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
            $State.Environment = 'Global'
            $Result = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                $Caught = $null
                try { Initialize-OPIMAuth -Environment USGov } catch { $Caught = $PSItem }
                @{ Caught = $Caught; State = $script:_OPIMAuthState }
            }
            $Result.Caught | Should -Not -BeNullOrEmpty
            $Result.Caught.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
            $Result.State.Environment | Should -BeExactly 'Global' -Because 'a refused token leaves the session as it was'
            $Result.State.TokenTenantId | Should -BeExactly $TenantA
        }

        It 'passes only the access token, no welcome and the error action to Connect-MgGraph in the Global cloud' {
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                Initialize-OPIMAuth -TenantId $TenantA
            }
            # The Global call stays the call the module always made: no -Environment key at all.
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It -ParameterFilter {
                (($PesterBoundParameters.Keys | Sort-Object) -join ',') -ceq 'AccessToken,ErrorAction,NoWelcome' -and
                $PesterBoundParameters.AccessToken -is [System.Security.SecureString] -and
                $NoWelcome -and
                $ErrorAction -ceq 'Stop'
            }
        }

        It 'passes no -Environment to Connect-MgGraph when it names Global' {
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                Initialize-OPIMAuth -TenantId $TenantA -Environment Global
            }
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It -ParameterFilter { $PesterBoundParameters.ContainsKey('Environment') }
        }

        It 'passes no -Environment to Connect-MgGraph on a switch back to Global from a sovereign cloud' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -AuthorityTenant $TenantA -ObjectId $SessionOid
            $State.Environment = 'China'
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment Global
            }
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It -ParameterFilter { $PesterBoundParameters.ContainsKey('Environment') }
        }

        It 'passes the Graph environment of the table to Connect-MgGraph in <Name>' -ForEach @(
            @{ Name = 'USGov' }
            @{ Name = 'USGovDoD' }
            @{ Name = 'China' }
        ) {
            $Cloud = $Name
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA; Cloud = $Cloud } {
                param($TenantA, $Cloud)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                Initialize-OPIMAuth -TenantId $TenantA -Environment $Cloud
            }
            # Pester lists the aliases of a bound parameter among the bound keys (Environment answers to
            # EnvironmentName and NationalCloud), so they are left out of the key list.
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It -ParameterFilter {
                $PesterBoundParameters.ContainsKey('Environment') -and $Environment -ceq $Cloud -and
                (($PesterBoundParameters.Keys | Where-Object { $_ -notin 'EnvironmentName', 'NationalCloud' } | Sort-Object) -join ',') -ceq 'AccessToken,Environment,ErrorAction,NoWelcome' -and
                $PesterBoundParameters.AccessToken -is [System.Security.SecureString]
            }
        }

        It 'takes the Graph environment name from the table''s GraphEnvironment, not from the cloud name' {
            Mock -ModuleName Omnicit.PIM Get-OPIMCloudEndpoint {
                [PSCustomObject]@{
                    Environment      = 'USGov'
                    GraphResource    = 'https://graph.test/'
                    GraphEnvironment = 'TableGraphName'
                    GraphServiceRoot = 'https://graph.test/v1.0'
                    ArmResource      = 'https://arm.test/'
                    ArmHost          = 'https://arm.test'
                    AuthorityHost    = 'https://login.test/'
                }
            }
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                Initialize-OPIMAuth -TenantId $TenantA -Environment USGov
            }
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It -ParameterFilter { $Environment -ceq 'TableGraphName' }
        }
    }

    Context 'When the Graph token and the ARM token are handed on' {
        It 'binds the plaintext token to no command' {
            # SECURITY rule 5: PowerShell module logging (LogPipelineExecutionDetails, event 4103)
            # records every value bound to a command parameter. Static check on the function as the
            # module loaded it: no argument of any command call reaches an .AccessToken member of the
            # Graph result or a .Token member of the ARM result, so the plaintext only ever reaches
            # .NET (the SecureString is what commands receive). The only reads of .AccessToken and
            # .Token anywhere in the function -- in a hashtable that is splatted, behind a variable or
            # in a method call as much as in a command's own arguments -- are the NetworkCredential
            # constructor (once for each) and a truthiness test in an if (once for each), and the
            # constructor's result is read only through .SecurePassword, never .Password.
            $Ast = InModuleScope Omnicit.PIM { (Get-Command Initialize-OPIMAuth).ScriptBlock.Ast }
            $Commands = @($Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true))
            @($Commands | Where-Object { $_.GetCommandName() -eq 'Connect-MgGraph' }).Count |
                Should -Be 1 -Because 'the walk must reach the Connect-MgGraph hand-off; a walk that reads nothing would pass vacuously'
            @($Commands | Where-Object { $_.GetCommandName() -eq 'Get-AzToken' }).Count |
                Should -Be 2 -Because 'the walk must reach both AzAuth calls, with and without the device code pipeline'
            # The member is read by its string VALUE, not by its source text: $Result.AccessToken,
            # $Result.'AccessToken' and $Result."AccessToken" name the same member, and only the first
            # has the text AccessToken. Member names are case-insensitive in PowerShell, so -in (which
            # is too) is right. KNOWN LIMIT: a member named by an expression ($Result.$Name) has no
            # constant value to read; review has to catch that shape.
            $Hits = foreach ($Command in $Commands) {
                foreach ($Element in @($Command.CommandElements | Select-Object -Skip 1)) {
                    $Member = $Element.Find({
                            param($Node)
                            $Node -is [System.Management.Automation.Language.MemberExpressionAst] -and
                            $Node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                            $Node.Member.Value -in 'AccessToken', 'Token'
                        }, $true)
                    if ($Member) { 'line {0}: {1}' -f $Command.Extent.StartLineNumber, $Command.GetCommandName() }
                }
            }
            $Hits | Should -BeNullOrEmpty

            # Every read of either plaintext member, wherever it sits (an argument, a splatted hashtable's
            # value, an assignment to a local variable, a method call's argument): it is allowed in the
            # NetworkCredential constructor and in an if condition, and nowhere else.
            $TokenMembers = @($Ast.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.MemberExpressionAst] -and
                        $Node -isnot [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                        $Node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                        $Node.Member.Value -in 'AccessToken', 'Token'
                    }, $true))
            $Uses = foreach ($Member in $TokenMembers) {
                $Parent = $Member.Parent
                if ($Parent -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                    $Parent.Member.Extent.Text -eq 'new' -and
                    $Parent.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and
                    $Parent.Expression.TypeName.FullName -eq 'System.Net.NetworkCredential' -and
                    @($Parent.Arguments | Where-Object { [object]::ReferenceEquals($_, $Member) }).Count -eq 1) {
                    'NetworkCredential:{0}' -f $Member.Member.Value
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
                if ($InIfCondition) { 'IfTest:{0}' -f $Member.Member.Value } else { 'line {0}: {1}' -f $Member.Extent.StartLineNumber, $Member.Parent.Extent.Text }
            }
            foreach ($Name in 'AccessToken', 'Token') {
                @($Uses | Where-Object { $_ -ieq "NetworkCredential:$Name" }).Count | Should -Be 1 -Because "the $Name member reaches .NET through the NetworkCredential constructor exactly once"
                @($Uses | Where-Object { $_ -ieq "IfTest:$Name" }).Count | Should -Be 1 -Because "the walk must find the one test that the result carries a $Name"
            }
            @($Uses | Where-Object { $_ -inotmatch '^(NetworkCredential|IfTest):(AccessToken|Token)$' }) | Should -BeNullOrEmpty

            # The constructor's result is read only through .SecurePassword: the plaintext property
            # (.Password) or the user name would hand the token on as a string. Every constructor in the
            # function is held to it, not only the two that take a token member.
            $Constructors = @($Ast.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                        $Node.Member.Extent.Text -eq 'new' -and
                        $Node.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and
                        $Node.Expression.TypeName.FullName -eq 'System.Net.NetworkCredential'
                    }, $true))
            $Constructors.Count | Should -Be 2 -Because 'the Graph token and the ARM token each become a SecureString through one constructor'
            $Reads = foreach ($Constructor in $Constructors) {
                $Up = $Constructor.Parent
                if ($Up -is [System.Management.Automation.Language.MemberExpressionAst] -and
                    $Up -isnot [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                    [object]::ReferenceEquals($Up.Expression, $Constructor) -and
                    $Up.Member.Extent.Text -ceq 'SecurePassword') {
                    'SecurePassword'
                } else {
                    'line {0}: {1}' -f $Constructor.Extent.StartLineNumber, $Up.Extent.Text
                }
            }
            @($Reads | Where-Object { $_ -ceq 'SecurePassword' }).Count | Should -Be 2
            @($Reads | Where-Object { $_ -cne 'SecurePassword' }) | Should -BeNullOrEmpty
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
                # No param block either: a pipeline parameter of the script block would bind the token
                # object, and module logging records every bound value.
                $Element.CommandElements[0].ScriptBlock.ParamBlock | Should -BeNullOrEmpty
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
                # OPIM-08, A3: the ARM gate reads the session's ARM token, never an Az context; this
                # Graph-only sign-in holds none, so the gate has nothing to refuse.
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

        It 'refuses the ARM call of a signed-in command whose ARM token is for another tenant' {
            # Acceptance (OPIM-08, A3): the state the real sign-in wrote, holding an ARM token for
            # another tenant, gives TenantMismatch at the ARM gate before any ARM call. The gate reads
            # the token's own tid, never an Az context.
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            $ArmToken = [System.Net.NetworkCredential]::new('', (New-OPIMTestAccessToken -TenantId $TenantB)).SecurePassword
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; ArmToken = $ArmToken; TenantA = $TenantA } {
                param($Token, $ArmToken, $TenantA)
                $script:_OPIMTestToken = $Token
                function Invoke-SignedInCommand {
                    Initialize-OPIMAuth -TenantId $TenantA
                    $script:_OPIMAuthState.ArmToken = $ArmToken
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
