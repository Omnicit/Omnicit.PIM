BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OPIMTestToken.ps1"
    . "$PSScriptRoot/../TestHelpers/OPIMScrubFixture.ps1"

    # Two tenants for the tenant-pin tests. Letter-repeat placeholders: neither is a version-4 id.
    $TenantA = 'aaaaaaaa-0000-0000-0000-00000000000a'
    $TenantB = 'bbbbbbbb-0000-0000-0000-00000000000b'

    # The account (the oid claim) of the session's Graph token, and another account. Digit-repeat
    # placeholders: neither is a version-4 id.
    $SessionOid = '22222222-2222-2222-2222-222222222222'
    $OtherOid = '33333333-3333-3333-3333-333333333333'

    # The six Microsoft Graph scopes of the one sign-in prompt, in the order the module asks for them.
    $GraphScopeList = @(
        'RoleEligibilitySchedule.ReadWrite.Directory'
        'RoleAssignmentSchedule.ReadWrite.Directory'
        'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup'
        'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup'
        'AdministrativeUnit.Read.All'
        'User.Read'
    )

    # An auth state as Initialize-OPIMAuth writes it after a Graph sign-in, in device code mode, so a
    # new sign-in from it asks AzAuth for a device code (A16: Get-AzToken signs in to Microsoft Graph).
    # Account is the Identity AzAuth returned; the state records no MSAL authority (R14).
    function New-PinState {
        param(
            [string]$TenantId,
            [string]$TokenTenantId,
            [string]$ObjectId,
            [switch]$Expired
        )
        @{
            TenantId         = $TenantId
            TokenTenantId    = $TokenTenantId
            Account          = 'user@contoso.com'
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

    # The values the Get-AzToken stand-in below reads. They are $script: variables of this file: a mock
    # body runs in the test scope, where it also finds New-OPIMTestAccessToken, which the module scope
    # does not see. The Describe resets them before every It.
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
        $script:GraphNoTid = $false
        $script:GraphNoOid = $false
        $script:GraphWarning = $null
        $script:GraphIdentity = 'user@contoso.com'
        $script:GraphExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
        $script:SeenGraphAuthorityHost = 'Get-AzToken was not called for Microsoft Graph'
        # The token requests that throw instead of answering, by their number in this It (1 is the
        # first request), as a cancelled prompt or a failed sign-in would.
        $script:AzTokenThrowAt = @()
        $script:AzTokenCalls = [System.Collections.Generic.List[object]]::new()
    }

    # The one Get-AzToken stand-in of this file (A16): AzAuth signs in to Microsoft Graph and to Azure
    # Resource Manager, and the two are told apart by the resource asked for (every Graph resource of
    # the cloud table names graph, no ARM resource does). It records every request -- its kind, its
    # resource, the NAMES of the parameters it bound and the AZURE_AUTHORITY_HOST it saw while it ran,
    # which is what Azure.Identity reads when it builds the credential -- and answers with the shape of
    # AzAuth's AzToken, its token built from the $script:Graph* or $script:Arm* values above. A bound
    # -WarningAction sets no preference inside a mock body, which runs in the test scope, so the body
    # takes it from $PesterBoundParameters, as the compiled cmdlet honours it.
    $script:AzTokenMock = {
        param($Resource, $Tenant, $Scope, $ClientId, $Claim, $TimeoutSeconds, [switch]$DeviceCode, [switch]$Interactive, [switch]$Force)
        if ($PesterBoundParameters.ContainsKey('WarningAction')) {
            $WarningPreference = $PesterBoundParameters['WarningAction']
        }
        $Seen = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')
        [bool]$IsGraph = [string]$Resource -like '*graph*'
        $script:AzTokenCalls.Add([pscustomobject]@{
                Kind      = if ($IsGraph) { 'Graph' } else { 'Arm' }
                Resource  = [string]$Resource
                Keys      = @($PesterBoundParameters.Keys)
                Authority = $Seen
            })
        if ($script:AzTokenCalls.Count -in $script:AzTokenThrowAt) {
            throw [System.InvalidOperationException]::new('AzAuth sign-in failure')
        }
        if ($IsGraph) {
            $script:SeenGraphAuthorityHost = $Seen
            if ($script:GraphWarning) { Microsoft.PowerShell.Utility\Write-Warning $script:GraphWarning }
            $GraphTokenArgs = @{ TenantId = $script:GraphTid; ObjectId = $script:GraphOid }
            if ($script:GraphNoTid) { $GraphTokenArgs.NoTenant = $true }
            if ($script:GraphNoOid) { $GraphTokenArgs.NoObjectId = $true }
            [PSCustomObject]@{
                Token     = New-OPIMTestAccessToken @GraphTokenArgs
                ExpiresOn = $script:GraphExpiresOn
                Identity  = $script:GraphIdentity
                TenantId  = $script:GraphTid
            }
        } else {
            # The authority AzAuth would read while it builds its credential (OPIM-29): $null when the
            # variable is absent. Reset-ArmTestFixture puts a marker here before every It.
            $script:SeenAuthorityHost = $Seen
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

    # The recorded token requests of one kind.
    function Get-AzTokenCall {
        param([ValidateSet('Graph', 'Arm')][string]$Kind)
        @($script:AzTokenCalls | Where-Object { $_.Kind -eq $Kind })
    }

    # Exactly $Graph Microsoft Graph and $Arm Azure Resource Manager token requests and no other. Each
    # Graph request carries Force when $GraphForce is $true and none when it is $false, each ARM
    # request likewise by $ArmForce, and -Force sets both; every request carries each parameter named
    # in $Key. The counts come first, so a missing Force never passes on a request that was not made.
    function Assert-AzTokenCall {
        param(
            [int]$Graph,
            [int]$Arm,
            [Nullable[bool]]$Force,
            [Nullable[bool]]$GraphForce,
            [Nullable[bool]]$ArmForce,
            [string[]]$Key = @()
        )
        if ($null -eq $GraphForce) { $GraphForce = $Force }
        if ($null -eq $ArmForce) { $ArmForce = $Force }
        $GraphCalls = @(Get-AzTokenCall -Kind Graph)
        $ArmCalls = @(Get-AzTokenCall -Kind Arm)
        @($script:AzTokenCalls).Count | Should -Be ($Graph + $Arm) -Because 'every token request is recorded, each for Microsoft Graph or Azure Resource Manager'
        $GraphCalls.Count | Should -Be $Graph -Because 'the Microsoft Graph token requests are counted exactly'
        $ArmCalls.Count | Should -Be $Arm -Because 'the Azure Resource Manager token requests are counted exactly'
        foreach ($Call in $GraphCalls) {
            if ($null -ne $GraphForce) {
                ($Call.Keys -contains 'Force') | Should -Be $GraphForce -Because "Force on the Microsoft Graph token request must be $GraphForce"
            }
            foreach ($Name in $Key) {
                ($Call.Keys -contains $Name) | Should -BeTrue -Because "the Microsoft Graph token request carries $Name"
            }
        }
        foreach ($Call in $ArmCalls) {
            if ($null -ne $ArmForce) {
                ($Call.Keys -contains 'Force') | Should -Be $ArmForce -Because "Force on the Azure Resource Manager token request must be $ArmForce"
            }
            foreach ($Name in $Key) {
                ($Call.Keys -contains $Name) | Should -BeTrue -Because "the Azure Resource Manager token request carries $Name"
            }
        }
    }
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Initialize-OPIMAuth' {
    BeforeEach {
        Reset-ArmTestFixture
        # $script:_OPIMLastAuthorityHost is never cleared by Disconnect-OPIM, since AzAuth's
        # process-wide credential outlives it, so nothing in the module resets it. Reset it here, or a
        # sovereign test leaks its authority into the next test, which would then gain a -Force.
        InModuleScope Omnicit.PIM { $script:_OPIMLastAuthorityHost = $null }
        # AZURE_AUTHORITY_HOST is process-wide state that a sign-in reads, sets around the token calls
        # for a sovereign cloud and warns about in the Global cloud (OPIM-29). Every It starts with it
        # absent and puts the operator's own value back afterwards, so no test leaks it, none depends
        # on the environment the suite runs in (a runner that sets it would add a Global warning to
        # the tests that count warnings) and the restore does not rely on the code under test.
        # [NullString]::Value, not $null: $null would leave an empty variable behind.
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

    Context 'When auth state is already cached for the same tenant with a valid token' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = $null
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $true
                }
                Mock Get-AzToken {}
                Mock Connect-MgGraph {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'returns without acquiring a new token (idempotent)' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com'
                Should -Invoke Get-AzToken -Times 0 -Scope It
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
        # R13: AzAuth has no refresh-token path, so a renewal at a command's start signs in again --
        # in the system browser here, since the state records no device code mode.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzToken -MockWith $script:AzTokenMock
            Mock -ModuleName Omnicit.PIM Connect-MgGraph {}
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionFingerprint { 'fp' }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = 'user@contoso.com'
                    GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(-1)  # expired
                    ClaimsSatisfied  = $true
                }
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'signs in to Microsoft Graph again through Get-AzToken, in the system browser and without Force' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com'
            }
            Assert-AzTokenCall -Graph 1 -Arm 0 -Force $false -Key 'Interactive'
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
        }
    }

    Context 'When no auth state exists (first use)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzToken -MockWith $script:AzTokenMock
            Mock -ModuleName Omnicit.PIM Connect-MgGraph {}
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionFingerprint { 'fp' }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'asks Get-AzToken for one Microsoft Graph token' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com'
            }
            Assert-AzTokenCall -Graph 1 -Arm 0
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                $Resource -ceq 'https://graph.microsoft.com/'
            }
        }

        It 'does not use the device code flow without -DeviceCode' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com'
            }
            Assert-AzTokenCall -Graph 1 -Arm 0 -Key 'Interactive'
            (Get-AzTokenCall -Kind Graph)[0].Keys | Should -Not -Contain 'DeviceCode'
        }

        It 'uses organizations as default tenant when no TenantId given, naming no tenant to AzAuth' {
            $After = InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth
                $script:_OPIMAuthState
            }
            Assert-AzTokenCall -Graph 1 -Arm 0
            (Get-AzTokenCall -Kind Graph)[0].Keys | Should -Not -Contain 'Tenant'
            # The session is pinned to the tid of that first token.
            $After.TenantId | Should -BeExactly $TenantA
        }
    }

    Context 'When -ForceRefresh is set and a valid token is already cached' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzToken -MockWith $script:AzTokenMock
            Mock -ModuleName Omnicit.PIM Connect-MgGraph {}
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionFingerprint { 'fp' }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = 'user@contoso.com'
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)  # still valid
                    ClaimsSatisfied  = $false
                }
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'bypasses the cache and re-acquires a token, with Force' {
            InModuleScope Omnicit.PIM {
                # The cached token is valid, so without -ForceRefresh the call would short-circuit
                # and ask AzAuth for nothing. -ForceRefresh must force re-acquisition (R8: with Force).
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -ForceRefresh
            }
            Assert-AzTokenCall -Graph 1 -Arm 0 -Force $true
        }
    }

    Context 'When Microsoft Graph signs in through AzAuth (A16)' {
        # The Graph call is the template's (EntraRBAC, R4): Get-AzToken for the cloud's Graph resource,
        # the six scopes and the Microsoft Graph Command Line Tools client, interactively or with a
        # device code by the session's mode, then Connect-MgGraph with the token as a SecureString.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzToken -MockWith $script:AzTokenMock
            Mock -ModuleName Omnicit.PIM Connect-MgGraph {}
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionFingerprint { 'fp' }
        }
        BeforeEach {
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

        It 'acquires a Graph token via Get-AzToken (interactive) and connects MgGraph' {
            $After = InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                Initialize-OPIMAuth -TenantId $TenantA
                $script:_OPIMAuthState
            }
            $After.TenantId | Should -BeExactly $TenantA
            $After.TokenTenantId | Should -BeExactly $TenantA
            $After.GraphTokenExpiry | Should -BeGreaterThan ([DateTime]::UtcNow)
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                $Resource -ceq 'https://graph.microsoft.com/' -and $Interactive
            }
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
        }

        It 'requests delegated Graph with the Microsoft Graph Command Line Tools client id and exactly the six scopes' {
            $Expected = @($GraphScopeList)
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                Initialize-OPIMAuth -TenantId $TenantA
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                $ClientId -ceq '14d82eec-204b-4c2f-b7e8-296a70dab67e' -and
                $Resource -ceq 'https://graph.microsoft.com/' -and
                @($Scope).Count -eq 6 -and
                (@($Scope) -join ',') -ceq ($Expected -join ',')
            }
        }

        It 'names the tenant <Name> in the Microsoft Graph request' -ForEach @(
            @{ Name = 'asked for by GUID'; Requested = 'aaaaaaaa-0000-0000-0000-00000000000a' }
            @{ Name = 'asked for by domain'; Requested = 'contoso.onmicrosoft.com' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Requested = $Requested } {
                param($Requested)
                Initialize-OPIMAuth -TenantId $Requested
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                $PesterBoundParameters.ContainsKey('Tenant') -and $Tenant -ceq $Requested
            }
        }

        It 'names no tenant in the Microsoft Graph request for <Name>, and pins the session to the token''s tenant' -ForEach @(
            @{ Name = 'a first sign-in that names none'; Arguments = @{} }
            @{ Name = '-TenantId organizations'; Arguments = @{ TenantId = 'organizations' } }
        ) {
            $After = InModuleScope Omnicit.PIM -Parameters @{ Arguments = $Arguments } {
                param($Arguments)
                Initialize-OPIMAuth @Arguments
                $script:_OPIMAuthState
            }
            Assert-AzTokenCall -Graph 1 -Arm 0
            (Get-AzTokenCall -Kind Graph)[0].Keys | Should -Not -Contain 'Tenant'
            $After.TenantId | Should -BeExactly $TenantA
        }

        It 'waits 900 seconds for the Microsoft Graph sign-in, as long as a device code lives, in <Mode>' -ForEach @(
            @{ Mode = 'device code mode'; DeviceCode = $true }
            @{ Mode = 'the system browser'; DeviceCode = $false }
        ) {
            # R5: AzAuth stops waiting after 120 seconds by default, much less than a device code lives.
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA; DeviceCode = $DeviceCode } {
                param($TenantA, $DeviceCode)
                Initialize-OPIMAuth -TenantId $TenantA -DeviceCode:$DeviceCode
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                $Resource -ceq 'https://graph.microsoft.com/' -and $TimeoutSeconds -eq 900
            }
        }

        It 'signs in to Microsoft Graph with <Expected>, and never with <Other>, in <Mode>' -ForEach @(
            @{ Mode = 'device code mode'; DeviceCode = $true; Expected = 'DeviceCode'; Other = 'Interactive' }
            @{ Mode = 'the system browser'; DeviceCode = $false; Expected = 'Interactive'; Other = 'DeviceCode' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA; DeviceCode = $DeviceCode } {
                param($TenantA, $DeviceCode)
                Initialize-OPIMAuth -TenantId $TenantA -DeviceCode:$DeviceCode
            }
            Assert-AzTokenCall -Graph 1 -Arm 0 -Key $Expected
            (Get-AzTokenCall -Kind Graph)[0].Keys | Should -Not -Contain $Other
        }

        It 'steps up with the claims challenge as Claim, in <Mode>' -ForEach @(
            @{ Mode = 'device code mode'; DeviceCode = $true; Expected = 'DeviceCode' }
            @{ Mode = 'the system browser'; DeviceCode = $false; Expected = 'Interactive' }
        ) {
            $Json = '{"access_token":{"acrs":{"essential":true,"value":"c1"}}}'
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
            $State.DeviceCode = $DeviceCode
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State; Json = $Json } {
                param($State, $Json)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -ClaimsChallenge $Json
                $script:_OPIMAuthState
            }
            Assert-AzTokenCall -Graph 1 -Arm 0 -Key 'Claim', $Expected
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                $Claim -ceq $Json -and $Resource -ceq 'https://graph.microsoft.com/'
            }
            $After.ClaimsSatisfied | Should -BeTrue
        }

        It 'passes no Claim without a claims challenge' {
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                Initialize-OPIMAuth -TenantId $TenantA
            }
            Assert-AzTokenCall -Graph 1 -Arm 0
            (Get-AzTokenCall -Kind Graph)[0].Keys | Should -Not -Contain 'Claim'
        }

        It 'records the Identity AzAuth returns as the account, and writes exactly the documented state keys' {
            $script:GraphIdentity = 'admin@contoso.com'
            $After = InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                Initialize-OPIMAuth -TenantId $TenantA -IncludeARM
                $script:_OPIMAuthState
            }
            Assert-AzTokenCall -Graph 1 -Arm 1
            $After.Account | Should -BeExactly 'admin@contoso.com'
            # R14: the MSAL application is gone, and the authority key it was built for with it; the
            # exact key list below holds that.
            $Expected = @('TenantId', 'TokenTenantId', 'Environment', 'Account', 'ObjectId', 'GraphTokenExpiry', 'ClaimsSatisfied',
                'DeviceCode', 'GraphSessionFingerprint', 'ArmToken', 'ArmTokenExpiry', 'ArmTokenTenantId', 'ArmTokenObjectId', 'ArmResourceUrl')
            (@($After.Keys) | Sort-Object) | Should -Be ($Expected | Sort-Object)
        }

        It 'converts the expiry AzAuth returns to UTC' {
            $script:GraphExpiresOn = [DateTimeOffset]::new(2030, 1, 1, 12, 0, 0, [TimeSpan]::FromHours(2))
            $After = InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                Initialize-OPIMAuth -TenantId $TenantA
                $script:_OPIMAuthState
            }
            $After.GraphTokenExpiry | Should -BeOfType [datetime]
            $After.GraphTokenExpiry.Kind | Should -Be ([System.DateTimeKind]::Utc)
            $After.GraphTokenExpiry | Should -Be ([datetime]::new(2030, 1, 1, 10, 0, 0, [System.DateTimeKind]::Utc))
        }
    }

    Context 'When the Microsoft Graph sign-in fails' {
        # R6: the ids stay PIM's -- InteractiveAuthFailed in the system browser, DeviceCodeAuthFailed in
        # device code mode, NoAccessToken for an answer without a token. The record keeps AzAuth's
        # message only: no inner exception, and the tenant asked for as its target object. Each is
        # terminating and leaves the calling command latched (EntraRBAC A19).
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-MgGraph {}
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionFingerprint { 'fp' }
            # Signs in from a first state in the given mode, inside a command that carries on, and
            # returns the error, the latch and the state.
            function Invoke-FailedGraphSignIn {
                param([bool]$DeviceCode, [string]$TenantId)
                InModuleScope Omnicit.PIM -Parameters @{ DeviceCode = $DeviceCode; TenantId = $TenantId } {
                    param($DeviceCode, $TenantId)
                    $script:_OPIMAuthState = if ($DeviceCode) { @{ DeviceCode = $true } } else { $null }
                    function Invoke-GraphSignInCommand {
                        $Result = @{}
                        try { Initialize-OPIMAuth -TenantId $TenantId -IncludeARM } catch { $Result.SignIn = $PSItem }
                        $Result.Refusal = Get-OPIMSignInRefusal
                        $Result.State = $script:_OPIMAuthState
                        $Result
                    }
                    Invoke-GraphSignInCommand
                }
            }
        }
        BeforeEach {
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

        It 'throws <ErrorId> with the AzAuth message only, connects nothing and keeps the caller latched, in <Mode>' -ForEach @(
            @{
                Mode = 'the system browser'; DeviceCode = $false; ErrorId = 'InteractiveAuthFailed'
                Message = 'Interactive authentication failed: AzAuth sign-in failure. On headless systems (Linux without a display server) the system browser cannot be launched. Run this command on a desktop system.'
            }
            @{
                Mode = 'device code mode'; DeviceCode = $true; ErrorId = 'DeviceCodeAuthFailed'
                Message = 'Device code authentication failed: AzAuth sign-in failure A device code expires after about 15 minutes; run the command again for a new code.'
            }
        ) {
            Mock -ModuleName Omnicit.PIM Get-AzToken { throw [System.InvalidOperationException]::new('AzAuth sign-in failure') }
            $Result = Invoke-FailedGraphSignIn -DeviceCode $DeviceCode -TenantId $TenantA
            $Result.SignIn | Should -Not -BeNullOrEmpty -Because 'the failed sign-in must end the function'
            $Result.SignIn.FullyQualifiedErrorId | Should -BeLike "$ErrorId*"
            $Result.SignIn.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
            $Result.SignIn.Exception.Message | Should -BeExactly $Message
            $Result.SignIn.Exception.InnerException | Should -BeNullOrEmpty
            $Result.SignIn.TargetObject | Should -BeExactly $TenantA
            $Result.Refusal | Should -BeExactly 'Invoke-GraphSignInCommand'
            # One Graph request and no ARM request: the failure ends the function before Azure.
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Resource -ceq 'https://graph.microsoft.com/' }
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
            if ($Result.State) { $Result.State.ContainsKey('TenantId') | Should -BeFalse }
        }

        It 'scrubs the record of the failed Microsoft Graph Get-AzToken, in <Mode>, and keeps no reference to it' -ForEach @(
            @{ Mode = 'the system browser'; DeviceCode = $false; ErrorId = 'InteractiveAuthFailed' }
            @{ Mode = 'device code mode'; DeviceCode = $true; ErrorId = 'DeviceCodeAuthFailed' }
        ) {
            # The AzAuth error can carry the request it failed on, and that request the bearer token.
            $script:GraphFailure = New-ScrubFixture
            $script:GraphFailure.Request.Headers.Contains('Authorization') | Should -BeTrue -Because 'the fixture must carry the header the scrub removes'
            Mock -ModuleName Omnicit.PIM Get-AzToken { $PSCmdlet.ThrowTerminatingError($script:GraphFailure.Record) }
            $Result = Invoke-FailedGraphSignIn -DeviceCode $DeviceCode -TenantId $TenantA
            $Result.SignIn.FullyQualifiedErrorId | Should -BeLike "$ErrorId*"
            $Result.SignIn.Exception.InnerException | Should -BeNullOrEmpty
            $Result.SignIn.TargetObject | Should -BeExactly $TenantA
            $Result.SignIn.Exception.Message | Should -Not -BeLike '*NOT-A-REAL-TOKEN*'
            $script:GraphFailure.Request.Headers.Contains('Authorization') | Should -BeFalse
            $script:GraphFailure = $null
        }

        It 'says that AzAuth is missing when the Microsoft Graph Get-AzToken cannot be found, in <Mode>' -ForEach @(
            @{ Mode = 'the system browser'; DeviceCode = $false; ErrorId = 'InteractiveAuthFailed'; Prefix = 'Interactive authentication failed' }
            @{ Mode = 'device code mode'; DeviceCode = $true; ErrorId = 'DeviceCodeAuthFailed'; Prefix = 'Device code authentication failed' }
        ) {
            Mock -ModuleName Omnicit.PIM Get-AzToken {
                throw [System.Management.Automation.CommandNotFoundException]::new("The term 'Get-AzToken' is not recognized as a name of a cmdlet, function, script file, or executable program.")
            }
            $Result = Invoke-FailedGraphSignIn -DeviceCode $DeviceCode -TenantId $TenantA
            $Result.SignIn.FullyQualifiedErrorId | Should -BeLike "$ErrorId*"
            $Result.SignIn.Exception.Message | Should -BeExactly "${Prefix}: the AzAuth module is not installed or could not be loaded. Install AzAuth 2.9.0 from the PowerShell Gallery; it needs PowerShell 7.4 or later."
            $Result.SignIn.Exception.InnerException | Should -BeNullOrEmpty
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
        }

        It 'throws NoAccessToken, connects nothing and keeps the caller latched when Get-AzToken returns <Name>, in <Mode>' -ForEach @(
            @{ Name = 'nothing'; Answer = 'Nothing'; Mode = 'the system browser'; DeviceCode = $false }
            @{ Name = 'no token'; Answer = 'NoToken'; Mode = 'the system browser'; DeviceCode = $false }
            @{ Name = 'nothing'; Answer = 'Nothing'; Mode = 'device code mode'; DeviceCode = $true }
        ) {
            $script:GraphAnswer = $Answer
            Mock -ModuleName Omnicit.PIM Get-AzToken {
                if ($script:GraphAnswer -eq 'NoToken') {
                    [PSCustomObject]@{ ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'user@contoso.com' }
                }
            }
            $Result = Invoke-FailedGraphSignIn -DeviceCode $DeviceCode -TenantId $TenantA
            $Result.SignIn.FullyQualifiedErrorId | Should -BeLike 'NoAccessToken*'
            $Result.Refusal | Should -BeExactly 'Invoke-GraphSignInCommand'
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
            $script:GraphAnswer = $null
        }
    }

    Context 'When -IncludeARM signs in to Azure Resource Manager' {
        # A2, A3, A6. AzAuth's Get-AzToken acquires the ARM token for the tenant of the session's Graph
        # token, interactively or with a device code by the session's mode. The token must carry the
        # tid and the oid of the Graph session, and is kept only as a SecureString. The Graph SDK
        # session is the module's own. The Get-AzToken stand-in of this file answers the ARM request
        # from $script:Arm* and, where an It signs in to Microsoft Graph too (A16), the Graph request
        # from $script:Graph*; the Describe resets both and AZURE_AUTHORITY_HOST before every It.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionState { 'Own' }
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionFingerprint { 'fp' }
            Mock -ModuleName Omnicit.PIM Connect-MgGraph {}
            Mock -ModuleName Omnicit.PIM Get-AzToken -MockWith $script:AzTokenMock
        }
        BeforeEach {
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
                $State = New-PinState -TenantId 'contoso.onmicrosoft.com' -TokenTenantId $TenantA -ObjectId $SessionOid
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Resource -eq 'https://management.azure.com' -and $Tenant -eq 'aaaaaaaa-0000-0000-0000-00000000000a'
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It -ParameterFilter { $Resource -like '*graph*' }
                Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
            }

            It 'signs in interactively, and never with a device code, outside device code mode' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                # The Graph request names no tenant (organizations); the ARM request names the tid of
                # the Graph token it brought back.
                Assert-AzTokenCall -Graph 1 -Arm 1
                (Get-AzTokenCall -Kind Graph)[0].Keys | Should -Not -Contain 'Tenant'
                Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Resource -eq 'https://management.azure.com' -and $Tenant -eq 'aaaaaaaa-0000-0000-0000-00000000000a'
                }
            }

            It 'stores the token as a SecureString with its UTC expiry, tenant, account and resource' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                Assert-AzTokenCall -Graph 1 -Arm 1
                foreach ($Key in @($After.Keys)) {
                    if ($After[$Key] -is [string]) {
                        $After[$Key] | Should -Not -BeLike '*NOT-A-REAL-TOKEN*' -Because "the state key $Key must hold no plaintext token"
                    }
                }
                @($After.Values | Where-Object { $_ -is [securestring] }).Count | Should -Be 1
                $After.ArmToken | Should -BeOfType [securestring]
            }

            It 'releases the calling command once the token is acquired' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                        Account          = 'user@contoso.com'
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
            # R8 (EntraRBAC A17): Force on every device code token request, on -ForceRefresh, and when
            # the cloud's authority differs from the one AzAuth last built a credential at. A first ARM
            # sign-in of a session is no reason on its own: AzAuth builds a new interactive credential on
            # every call, and A3 refuses a token for another account whatever it reuses.
            It 'passes -Force on every ARM sign-in in device code mode, the first of the session included' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM
                }
                Assert-AzTokenCall -Graph 0 -Arm 1 -Force $true -Key 'DeviceCode'
            }

            It 'passes no -Force on the first ARM sign-in of a session in the system browser' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
                $State.DeviceCode = $false
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM
                }
                Assert-AzTokenCall -Graph 0 -Arm 1 -Force $false -Key 'Interactive'
            }

            It 'passes -Force under -ForceRefresh in the system browser, also with a cached ARM token for the same tenant and account' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
                $State.DeviceCode = $false
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -ForceRefresh -IncludeARM
                }
                # The Graph renewal kept the ARM token (same tenant and account); -ForceRefresh still
                # asks for a new one, and forces both requests.
                Assert-AzTokenCall -Graph 1 -Arm 1 -Force $true -Key 'Interactive'
            }

            It 'passes no -Force in the system browser when the state holds an ARM token that is about to expire' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
                $State.DeviceCode = $false
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid -Expiry ([DateTime]::UtcNow.AddMinutes(4))
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM
                }
                Assert-AzTokenCall -Graph 0 -Arm 1 -Force $false
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
                $Result = Invoke-CloudArmSignIn -State $State
                $Result.Caught | Should -BeNullOrEmpty
                @($Result.Warnings).Count | Should -Be 0
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                $script:SeenAuthorityHost | Should -BeExactly $Value
                [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -BeExactly $Value
            }

            It 'does not warn about AZURE_AUTHORITY_HOST when the cloud is sovereign, where it is replaced for the call' {
                [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', 'https://login.example.com/')
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
                $State.Environment = 'USGov'
                $Result = Invoke-CloudArmSignIn -State $State
                $Result.Caught | Should -BeNullOrEmpty
                @($Result.Warnings).Count | Should -Be 0
            }

            It 'signs in to ARM again after a cloud switch, and never reuses the old cloud''s ARM token' {
                # Review Focus 4. The session is in Global with a valid ARM token for its tenant and
                # account; naming USGov signs in again, drops that token and asks AzAuth for a new one,
                # now for the USGov resource. The Graph request carries Force for the moved authority
                # (R8); in device code mode both requests carry it anyway (A17).
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
                $State.Environment = 'Global'
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
                $OldToken = $State.ArmToken
                $Result = Invoke-CloudArmSignIn -State $State -Arguments @{ Environment = 'USGov' }
                $Result.Caught | Should -BeNullOrEmpty
                Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
                Assert-AzTokenCall -Graph 1 -Arm 1 -Force $true
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Resource -ceq 'https://management.usgovcloudapi.net'
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid -Expiry ([DateTime]::UtcNow.AddMinutes($Minutes))
                InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    Initialize-OPIMAuth -IncludeARM
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
            }

            It 'acquires a new token when the cached one is for another tenant' {
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA
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

            It 'refuses to reuse a cached token for a session that records no tenant, and shows no sign-in for one' {
                # T1-R9: two unknown tenants are not the same tenant either. A session that records no
                # tenant for its Graph token reuses no ARM token, even one that records none as well,
                # and is refused with TenantMismatch before Get-AzToken.
                $State = New-PinState -TenantId 'contoso.onmicrosoft.com' -TokenTenantId '' -ObjectId $SessionOid
                $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
                $State.TokenTenantId = $null
                $State.ArmTokenTenantId = $null
                $Caught = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    try { Initialize-OPIMAuth -IncludeARM } catch { $PSItem }
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
                $Caught.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
                $Caught.Exception.Message | Should -BeLike "*could not be read*'contoso.onmicrosoft.com'*"
            }

            It 'reuses no cached ARM token from a state that is not a dictionary, and asks AzAuth for a new one' {
                # The module only ever writes a hashtable; a state of any other shape is no sign-in it
                # made (as Get-OPIMArmRefusal and Get-OPIMGraphSessionState read it), so its ARM token
                # is never reused, whatever its properties say. Only the ARM half is pinned here: how the
                # Microsoft Graph half treats such a state is not what this test proves.
                $Table = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
                $null = Add-ArmTestToken -State $Table -TenantId $TenantA -ObjectId $SessionOid
                $State = [pscustomobject]$Table
                $Replaced = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    $Before = $State.ArmToken
                    Initialize-OPIMAuth -IncludeARM
                    -not [object]::ReferenceEquals($Before, $script:_OPIMAuthState.ArmToken)
                }
                @(Get-AzTokenCall -Kind Arm).Count | Should -Be 1 -Because 'the ARM token of a state that is not a dictionary is never reused'
                $Replaced | Should -BeTrue
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $(if ($NoSessionOid) { '' } else { $SessionOid })
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

            It 'drops the ARM token the state held when it refuses a new token for <Name>, and signs in again on the next call' -ForEach @(
                @{ Name = 'another tenant'; Fixture = @{ ArmTid = 'bbbbbbbb-0000-0000-0000-00000000000b' }; ErrorId = 'TenantMismatch' }
                @{ Name = 'no readable tenant'; Fixture = @{ ArmNoTid = $true }; ErrorId = 'TenantMismatch' }
                @{ Name = 'another account'; Fixture = @{ ArmOid = '33333333-3333-3333-3333-333333333333' }; ErrorId = 'AccountMismatch' }
                @{ Name = 'no readable account'; Fixture = @{ ArmNoOid = $true }; ErrorId = 'AccountMismatch' }
            ) {
                # The state holds an ARM token of the session's own tenant and account with 4 minutes
                # left, so the first call acquires a new one -- and that one is refused. AzAuth's
                # credential has just answered for another tenant or account: the refusal drops the held
                # token too, so no earlier ARM token outlives it and the next call signs in again. In the
                # system browser neither request carries -Force (R8): AzAuth builds a new interactive
                # credential on every call, and A3 refuses another account's token whatever it reuses.
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
                $State.DeviceCode = $false
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
                Assert-AzTokenCall -Graph 0 -Arm 1 -Force $false

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
                Assert-AzTokenCall -Graph 0 -Arm 1 -Force $false
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                # The id itself, not only its start: the record is AzureConnectFailed and no other id.
                ($Result.SignIn.FullyQualifiedErrorId -split ',')[0] | Should -BeExactly 'AzureConnectFailed'
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
                $Caught = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                    param($State)
                    $script:_OPIMAuthState = $State
                    try { Initialize-OPIMAuth -IncludeARM } catch { $PSItem }
                }
                ($Caught.FullyQualifiedErrorId -split ',')[0] | Should -BeExactly 'AzureConnectFailed'
                $Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
                $Caught.Exception.Message | Should -BeExactly 'Azure connection failed: the AzAuth module is not installed or could not be loaded. Install AzAuth 2.9.0 from the PowerShell Gallery; it needs PowerShell 7.4 or later.'
                $Caught.Exception.InnerException | Should -BeNullOrEmpty
                $Caught.TargetObject | Should -BeExactly $TenantA
                Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
                $script:MissingShape = $null
            }

            It 'throws AzureConnectFailed when Get-AzToken returns no token, and keeps the caller latched' {
                Mock -ModuleName Omnicit.PIM Get-AzToken { [PSCustomObject]@{ ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1) } }
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                ($Result.SignIn.FullyQualifiedErrorId -split ',')[0] | Should -BeExactly 'AzureConnectFailed'
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                # One Microsoft Graph request, and none for ARM: the kept token is not asked for again.
                Assert-AzTokenCall -Graph 1 -Arm 0
                $Result.Same | Should -BeTrue
                $Result.State.ArmTokenExpiry | Should -Be $Expiry
                $Result.State.ArmTokenTenantId | Should -BeExactly $TenantA
                $Result.State.ArmTokenObjectId | Should -BeExactly $SessionOid
                $Result.State.ArmResourceUrl | Should -BeExactly 'https://management.azure.com'
            }

            It 'drops the cached ARM token when the new Graph token is for another account' {
                $script:GraphOid = $OtherOid
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                Assert-AzTokenCall -Graph 1 -Arm 0
            }

            It 'drops the cached ARM token when the session signs in to another tenant' {
                $script:GraphTid = $TenantB
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid -Expired:$Account
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
                # Device code mode: both requests carry -Force (A17).
                Assert-AzTokenCall -Graph 1 -Arm 1 -Force $true -Key 'DeviceCode'
                $After.ArmTokenObjectId | Should -BeExactly $script:ArmOid
                $After.ArmTokenTenantId | Should -BeExactly $script:ArmTid
            }

            It 'drops a cached ARM token that records no account when the new Graph token carries none either' {
                # Two unknown accounts are not the same account.
                $script:GraphNoOid = $true
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA
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
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                # The very first sign-in of a process: no auth state and no device code, so AzAuth is
                # asked interactively (the Get-AzToken stand-in answers; nothing opens a browser).
                $script:GraphOid = $SessionOid
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
                Assert-AzTokenCall -Graph 1 -Arm 0 -Force $false -Key 'Interactive'
                (Get-AzTokenCall -Kind Graph)[0].Keys | Should -Not -Contain 'DeviceCode'
                Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
            }
        }
    }

    Context 'When -DeviceCode is set and no auth state exists' {
        BeforeAll {
            # The request names a domain, so any tenant GUID is a token for it.
            InModuleScope Omnicit.PIM -Parameters @{ Token = (New-OPIMTestAccessToken -TenantId $TenantA) } {
                param($Token)
                $script:_OPIMTestToken = $Token
                Mock Get-AzToken {
                    [PSCustomObject]@{
                        Token     = $script:_OPIMTestToken
                        ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                        Identity  = 'user@contoso.com'
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

        It 'acquires the Graph token with a device code and hands it to Connect-MgGraph' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -DeviceCode
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $DeviceCode -and -not $Interactive }
                Should -Invoke Connect-MgGraph -Times 1 -Exactly -Scope It
            }
        }

        It 'requests the fixed Graph scope list' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -DeviceCode
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                    @($Scope).Count -eq 6 -and $Scope -contains 'User.Read' -and
                    $Scope -contains 'RoleAssignmentSchedule.ReadWrite.Directory'
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
        # R13: AzAuth has no refresh-token path, so the token-rejected retry (-ForceRefresh) and the
        # ACRS step-up (-ClaimsChallenge) sign in again -- with a new device code in this mode, which
        # the retries in Invoke-OPIMGraphRequest never pass and the auth state remembers.
        BeforeAll {
            InModuleScope Omnicit.PIM -Parameters @{ Token = (New-OPIMTestAccessToken -TenantId $TenantA) } {
                param($Token)
                $script:_OPIMTestToken = $Token
                Mock Get-AzToken {
                    [PSCustomObject]@{
                        Token     = $script:_OPIMTestToken
                        ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                        Identity  = 'user@contoso.com'
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
                    Account          = 'user@contoso.com'
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $false
                    DeviceCode       = $true
                }
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null; $script:_OPIMTestToken = $null }
        }

        It 'signs in with a new device code on -ForceRefresh, with -Force and never in the browser' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -ForceRefresh
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $DeviceCode -and $Force -and -not $Interactive }
            }
        }

        It 'passes the claims to the device code sign-in on a claims challenge' {
            InModuleScope Omnicit.PIM {
                $Json = '{"access_token":{"acrs":{"essential":true,"value":"c1"}}}'
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -ClaimsChallenge $Json
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Claim -eq '{"access_token":{"acrs":{"essential":true,"value":"c1"}}}' -and $DeviceCode -and $Force -and -not $Interactive
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
                    Account          = 'user@contoso.com'
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $false
                }
                Mock Get-AzToken {}
                Mock Connect-MgGraph {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'keeps the cached token and remembers the device code mode for the next sign-in' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -DeviceCode
                Should -Invoke Get-AzToken -Times 0 -Scope It
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
                $script:_OPIMAuthState.DeviceCode | Should -BeTrue
            }
        }
    }

    Context 'When the device code sign-in returns no token' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                Mock Get-AzToken { $null }
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
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $DeviceCode }
                Should -Invoke Get-AzToken -Times 0 -Scope It -ParameterFilter { $Interactive }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'NoAccessToken*'
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
            }
        }
    }

    Context 'When the device code sign-in fails on the first sign-in' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                # A declined or expired code: AzAuth's Get-AzToken throws.
                Mock Get-AzToken { throw [System.InvalidOperationException]::new('code_expired') }
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
                Should -Invoke Get-AzToken -Times 2 -Exactly -Scope It
                Should -Invoke Get-AzToken -Times 2 -Exactly -Scope It -ParameterFilter { $DeviceCode -and $Force }
                Should -Invoke Get-AzToken -Times 0 -Scope It -ParameterFilter { $Interactive }
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
                $script:_OPIMAuthState.DeviceCode | Should -BeTrue
            }
        }

        It 'ends with DeviceCodeAuthFailed and signs nothing in' {
            InModuleScope Omnicit.PIM {
                $Caught = $null
                try { Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -DeviceCode } catch { $Caught = $PSItem }
                $Caught | Should -Not -BeNullOrEmpty
                $Caught.FullyQualifiedErrorId | Should -BeLike 'DeviceCodeAuthFailed*'
                $Caught.Exception.Message | Should -BeLike '*code_expired*'
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
        # OPIM-07. Each It seeds the auth state and the token the Get-AzToken mock hands back; the
        # sign-in runs in device code mode. The tenant AzAuth is asked for is the Graph request's
        # -Tenant, and 'organizations' names none.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Get-AzToken {
                    [PSCustomObject]@{
                        Token     = $script:_OPIMTestToken
                        ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                        Identity  = 'user@contoso.com'
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
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; TenantA = $TenantA } {
                param($State, $TenantA)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth
                Should -Invoke Get-AzToken -Times 0 -Scope It
                $script:_OPIMAuthState.TenantId | Should -Be $TenantA
            }
        }

        It 'signs in again for the cached tenant on -ForceRefresh without a tenant' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; Token = $Token; TenantA = $TenantA } {
                param($State, $Token, $TenantA)
                $script:_OPIMAuthState = $State
                $script:_OPIMTestToken = $Token
                Initialize-OPIMAuth -ForceRefresh
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Tenant -eq 'aaaaaaaa-0000-0000-0000-00000000000a' }
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It
                $script:_OPIMAuthState.TenantId | Should -Be $TenantA
                $script:_OPIMAuthState.TokenTenantId | Should -Be $TenantA
            }
        }

        It 'does not relabel the session to organizations' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA
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
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA
            $Token = New-OPIMTestAccessToken -TenantId $TenantB
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; Token = $Token; TenantB = $TenantB } {
                param($State, $Token, $TenantB)
                $script:_OPIMAuthState = $State
                $script:_OPIMTestToken = $Token
                Mock Get-OPIMGraphSessionFingerprint { 'fp' }
                Mock Get-MgContext { [pscustomobject]@{ TenantId = 'bbbbbbbb-0000-0000-0000-00000000000b' } }
                Initialize-OPIMAuth -TenantId $TenantB
                Should -Invoke Get-MgContext -Times 0 -Scope It
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Tenant -eq 'bbbbbbbb-0000-0000-0000-00000000000b' }
                Should -Invoke Connect-MgGraph -Times 1 -Exactly -Scope It
                $script:_OPIMAuthState.TokenTenantId | Should -Be $TenantB
            }
        }

        It 'throws TenantMismatch and does not connect Graph when the token is for another tenant' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -Expired
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
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It
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

        It 'trusts the tid claim of the token, never the TenantId AzAuth reports beside it' {
            # R10: AzAuth can echo the requested tenant in AzToken.TenantId, so only the token's own
            # tid claim counts. Here AzAuth reports the tenant asked for, while the token was issued
            # for another one.
            $Token = New-OPIMTestAccessToken -TenantId $TenantB
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMTestToken = $Token
                Mock Get-AzToken {
                    [PSCustomObject]@{
                        Token     = $script:_OPIMTestToken
                        ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                        Identity  = 'user@contoso.com'
                        TenantId  = 'aaaaaaaa-0000-0000-0000-00000000000a'
                    }
                }
                $Caught = $null
                try { Initialize-OPIMAuth -TenantId $TenantA } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
            }
        }

        It "pins the session to the token's tenant on a first sign-in without a tenant" {
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMTestToken = $Token
                Initialize-OPIMAuth
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { -not $PesterBoundParameters.ContainsKey('Tenant') }
                $script:_OPIMAuthState.TenantId | Should -Be $TenantA
                $script:_OPIMAuthState.TokenTenantId | Should -Be $TenantA
                $script:_OPIMAuthState.DeviceCode | Should -BeTrue
            }
        }

        It 'names the pinned tenant on a later sign-in of a session first signed in under organizations' {
            # R14: no MSAL authority any more. The session's tenant is the tid of its first token, and
            # every later request names it, so AzAuth is never asked for 'organizations' again.
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; Token = $Token; TenantA = $TenantA } {
                param($State, $Token, $TenantA)
                $script:_OPIMAuthState = $State
                $script:_OPIMTestToken = $Token
                Initialize-OPIMAuth -ForceRefresh
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Tenant -eq 'aaaaaaaa-0000-0000-0000-00000000000a' }
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It
                $script:_OPIMAuthState.TenantId | Should -Be $TenantA
            }
        }

        It 'compares a later token of an organizations session with the pinned tenant' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA
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
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Tenant -eq 'contoso.onmicrosoft.com' }
                $script:_OPIMAuthState.TenantId | Should -Be 'contoso.onmicrosoft.com'
                $script:_OPIMAuthState.TokenTenantId | Should -Be $TenantA
            }
        }

        It 'compares a later token of a domain session with the recorded tenant' {
            $State = New-PinState -TenantId 'contoso.onmicrosoft.com' -TokenTenantId $TenantA
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
            $State = New-PinState -TenantId 'contoso.onmicrosoft.com' -TokenTenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; TenantA = $TenantA } {
                param($State, $TenantA)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -TenantId $TenantA
                Should -Invoke Get-AzToken -Times 0 -Scope It
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
            }
        }

        It 'signs in for another tenant when it is requested' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA
            $Token = New-OPIMTestAccessToken -TenantId $TenantB
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; Token = $Token; TenantB = $TenantB } {
                param($State, $Token, $TenantB)
                $script:_OPIMAuthState = $State
                $script:_OPIMTestToken = $Token
                Initialize-OPIMAuth -TenantId $TenantB
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Tenant -eq 'bbbbbbbb-0000-0000-0000-00000000000b' }
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It
                $script:_OPIMAuthState.TenantId | Should -Be $TenantB
                $script:_OPIMAuthState.TokenTenantId | Should -Be $TenantB
            }
        }

        It 'stores the requested GUID as the session tenant' {
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; TenantA = $TenantA } {
                param($Token, $TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                $script:_OPIMTestToken = $Token
                Initialize-OPIMAuth -TenantId $TenantA
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Tenant -eq 'aaaaaaaa-0000-0000-0000-00000000000a' }
                $script:_OPIMAuthState.TenantId | Should -Be $TenantA
                $script:_OPIMAuthState.TokenTenantId | Should -Be $TenantA
            }
        }
    }

    Context 'When the session is in a cloud (OPIM-29)' {
        # A11. The cloud is a property of the tenant: a call that names the session's tenant and no cloud
        # keeps the session's cloud, a call for another tenant that names none is Global, and a call that
        # names another cloud than the session's is a new sign-in. The Graph SDK session is the module's
        # own, and the Get-AzToken stand-in of this file answers the Microsoft Graph request with a token
        # built from $script:Graph* (A16); the sessions below are in device code mode.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionState { 'Own' }
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionFingerprint { 'fp' }
            Mock -ModuleName Omnicit.PIM Connect-MgGraph {}
            Mock -ModuleName Omnicit.PIM Get-AzToken -MockWith $script:AzTokenMock
        }
        BeforeEach {
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
            # same session -- no new sign-in, no token request, no Connect-MgGraph.
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
            $State.ContainsKey('Environment') | Should -BeFalse
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment Global
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
        }

        It 'returns the cached session for -Environment Global when the session was signed in to Global' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
            $State.Environment = 'Global'
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment Global
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
        }

        It 'keeps the session''s cloud when a call names neither a tenant nor a cloud' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
            $State.Environment = 'USGov'
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth
                $script:_OPIMAuthState
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
            $After.Environment | Should -BeExactly 'USGov'
        }

        It 'keeps the session''s cloud for the tenant label the session was signed in under' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
            $State.Environment = 'USGov'
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; TenantA = $TenantA } {
                param($State, $TenantA)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -TenantId $TenantA
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
        }

        It 'keeps the session''s cloud for a GUID equal to the session''s token tenant' {
            # A session pinned by domain: the GUID its Graph token was issued for is the same tenant.
            $State = New-PinState -TenantId 'contoso.onmicrosoft.com' -TokenTenantId $TenantA -ObjectId $SessionOid
            $State.Environment = 'USGov'
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State; TenantA = $TenantA } {
                param($State, $TenantA)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -TenantId $TenantA
                $script:_OPIMAuthState
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
            $After.Environment | Should -BeExactly 'USGov'
        }

        It 'signs in again when a call names another cloud than the session''s' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
            $State.Environment = 'Global'
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment USGov
                $script:_OPIMAuthState
            }
            Assert-AzTokenCall -Graph 1 -Arm 0
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Resource -ceq 'https://graph.microsoft.us/' }
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
            $After.Environment | Should -BeExactly 'USGov'
            $After.TenantId | Should -BeExactly $TenantA
        }

        It 'signs in again when a call names another cloud than a session that records none' {
            # A state written before the cloud was recorded is Global, so naming a sovereign cloud is a switch.
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment USGovDoD
                $script:_OPIMAuthState
            }
            Assert-AzTokenCall -Graph 1 -Arm 0
            $After.Environment | Should -BeExactly 'USGovDoD'
        }

        It 'signs in again for Global when the session is in a sovereign cloud and the call names Global' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
            $State.Environment = 'China'
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment Global
                $script:_OPIMAuthState
            }
            Assert-AzTokenCall -Graph 1 -Arm 0
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Resource -ceq 'https://graph.microsoft.com/' }
            $After.Environment | Should -BeExactly 'Global'
        }

        It 'is Global for another tenant that names no cloud, whatever the session''s cloud' {
            $script:GraphTid = $TenantB
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
            $State.Environment = 'USGov'
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State; TenantB = $TenantB } {
                param($State, $TenantB)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -TenantId $TenantB
                $script:_OPIMAuthState
            }
            Assert-AzTokenCall -Graph 1 -Arm 0
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Resource -ceq 'https://graph.microsoft.com/' }
            $After.TenantId | Should -BeExactly $TenantB
            $After.Environment | Should -BeExactly 'Global'
        }

        It 'keeps the cloud on a forced refresh of the session and keeps its ARM token' {
            # The positive control of the cloud term of the ARM token: the same cloud carries the token.
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
            Assert-AzTokenCall -Graph 1 -Arm 0
            $Result.State.Environment | Should -BeExactly 'USGov'
            $Result.Same | Should -BeTrue
        }

        It 'drops the cached ARM token when the session signs in to another cloud' {
            # Review Focus 4: an ARM token minted in one cloud is never carried into another, even for the
            # same tenant and the same account.
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
            $State.Environment = 'USGov'
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment USGOV
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
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
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 0 -Scope It
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

        It 'asks AzAuth for the Microsoft Graph resource of the cloud of the sign-in: <Name>' -ForEach @(
            @{ Name = 'Global'; Expected = 'https://graph.microsoft.com/' }
            @{ Name = 'USGov'; Expected = 'https://graph.microsoft.us/' }
            @{ Name = 'USGovDoD'; Expected = 'https://dod-graph.microsoft.us/' }
            @{ Name = 'China'; Expected = 'https://microsoftgraph.chinacloudapi.cn/' }
        ) {
            $Cloud = $Name
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA; Cloud = $Cloud } {
                param($TenantA, $Cloud)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                Initialize-OPIMAuth -TenantId $TenantA -Environment $Cloud
            }
            Assert-AzTokenCall -Graph 1 -Arm 0
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                $Resource -ceq $Expected -and $Tenant -ceq 'aaaaaaaa-0000-0000-0000-00000000000a'
            }
        }

        It 'asks AzAuth for the Microsoft Graph resource of the canonical cloud when it is typed in another letter case' {
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMAuthState = @{ DeviceCode = $true }
                Initialize-OPIMAuth -TenantId $TenantA -Environment usgovdod
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Resource -ceq 'https://dod-graph.microsoft.us/' }
        }

        It 'asks AzAuth for the Microsoft Graph resource of the session''s cloud on a refresh that names no cloud' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
            $State.Environment = 'USGov'
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -ForceRefresh
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                $Resource -ceq 'https://graph.microsoft.us/' -and $Tenant -ceq 'aaaaaaaa-0000-0000-0000-00000000000a'
            }
        }

        It 'names the session''s tenant, not organizations, on a switch of cloud' {
            # A session first signed in under 'organizations' is pinned to the tid of its first token,
            # and a switch of cloud asks for that tenant.
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
            $State.Environment = 'Global'
            $After = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth -Environment USGov
                $script:_OPIMAuthState
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                $Tenant -ceq 'aaaaaaaa-0000-0000-0000-00000000000a' -and $Resource -ceq 'https://graph.microsoft.us/'
            }
            $After.Environment | Should -BeExactly 'USGov'
        }

        It 'holds the token of a domain session that switches cloud to no tenant, and records its tid' {
            # Nothing in the new cloud is known to compare with, since a tenant has another GUID in another
            # cloud, so a domain-labelled session is pinned afresh to the tid of the new session's first
            # token, as a first sign-in under a domain is.
            $script:GraphTid = $TenantB
            $State = New-PinState -TenantId 'contoso.onmicrosoft.com' -TokenTenantId $TenantA -ObjectId $SessionOid
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
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
            # The Graph resource comes from the same row.
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Resource -ceq 'https://graph.test/' }
        }
    }

    Context 'When the sign-in follows the cloud through AzAuth (A11, A16)' {
        # The template's sovereign-cloud proofs (EntraRBAC), with PIM's names. Every sign-in here starts
        # from no state in the system browser, so -Force is told apart by its cause alone (R8).
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzToken -MockWith $script:AzTokenMock
            Mock -ModuleName Omnicit.PIM Connect-MgGraph {}
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionFingerprint { 'fp' }
            # Signs in from the given state and returns the error it raised (if any), the state
            # afterwards and the messages of the warnings it wrote.
            function Invoke-CloudSignIn {
                param([AllowNull()][hashtable]$State, [hashtable]$Arguments = @{})
                InModuleScope Omnicit.PIM -Parameters @{ State = $State; Arguments = $Arguments } {
                    param($State, $Arguments)
                    $script:_OPIMAuthState = $State
                    $Caught = $null
                    $Warned = $null
                    try {
                        Initialize-OPIMAuth @Arguments -WarningVariable Warned -WarningAction SilentlyContinue
                    } catch {
                        $Caught = $PSItem
                    }
                    @{ Caught = $Caught; State = $script:_OPIMAuthState; Warnings = @($Warned | ForEach-Object { [string]$_.Message }) }
                }
            }
        }
        BeforeEach {
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

        It 'leaves the Global path unchanged: no -Force, no -Environment, no AZURE_AUTHORITY_HOST write' {
            # A value that is not the global authority: observing it unchanged in both requests and
            # afterwards proves no write, where an absent variable could not tell "not written" from
            # "written and cleared".
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', 'https://login.example.com/')
            $Result = Invoke-CloudSignIn -State $null -Arguments @{ TenantId = $TenantA; IncludeARM = $true }
            $Result.Caught | Should -BeNullOrEmpty
            $Result.State.Environment | Should -BeExactly 'Global'
            $Result.State.ArmResourceUrl | Should -BeExactly 'https://management.azure.com'
            # The Global sign-in writes exactly one warning, the one about the operator's authority.
            @($Result.Warnings).Count | Should -Be 1
            Assert-AzTokenCall -Graph 1 -Arm 1 -Force $false
            (Get-AzTokenCall -Kind Graph)[0].Resource | Should -BeExactly 'https://graph.microsoft.com/'
            (Get-AzTokenCall -Kind Arm)[0].Resource | Should -BeExactly 'https://management.azure.com'
            (Get-AzTokenCall -Kind Graph)[0].Authority | Should -BeExactly 'https://login.example.com/'
            (Get-AzTokenCall -Kind Arm)[0].Authority | Should -BeExactly 'https://login.example.com/'
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It -ParameterFilter { $PesterBoundParameters.ContainsKey('Environment') }
            [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -BeExactly 'https://login.example.com/'
        }

        It 'does not create AZURE_AUTHORITY_HOST at all on the Global path' {
            $Result = Invoke-CloudSignIn -State $null -Arguments @{ TenantId = $TenantA; IncludeARM = $true }
            $Result.Caught | Should -BeNullOrEmpty
            Assert-AzTokenCall -Graph 1 -Arm 1
            $null -eq (Get-AzTokenCall -Kind Graph)[0].Authority | Should -BeTrue -Because 'the Global path writes no AZURE_AUTHORITY_HOST for Microsoft Graph'
            $null -eq (Get-AzTokenCall -Kind Arm)[0].Authority | Should -BeTrue -Because 'the Global path writes no AZURE_AUTHORITY_HOST for Azure'
            Test-Path -Path 'Env:AZURE_AUTHORITY_HOST' | Should -BeFalse
        }

        It 'reads Graph, ARM, Connect-MgGraph and the authority host from the <Cloud> endpoint row' -ForEach @(
            @{ Cloud = 'USGov' }
            @{ Cloud = 'USGovDoD' }
            @{ Cloud = 'China' }
        ) {
            $Row = InModuleScope Omnicit.PIM -Parameters @{ Cloud = $Cloud } {
                param($Cloud)
                Get-OPIMCloudEndpoint -Environment $Cloud
            }
            # Guards the assertions below against being satisfied by the global values.
            $Row.AuthorityHost | Should -Not -Be 'https://login.microsoftonline.com/'
            $Row.GraphResource | Should -Not -Be 'https://graph.microsoft.com/'
            $GraphEnvironment = $Row.GraphEnvironment

            $Result = Invoke-CloudSignIn -State $null -Arguments @{ TenantId = $TenantA; Environment = $Cloud; IncludeARM = $true }
            $Result.Caught | Should -BeNullOrEmpty
            $Result.State.Environment | Should -BeExactly $Cloud
            $Result.State.ArmResourceUrl | Should -BeExactly $Row.ArmHost

            # The Graph request moves the authority (Force, R8); the ARM request after it does not repeat it.
            Assert-AzTokenCall -Graph 1 -Arm 1 -GraphForce $true -ArmForce $false -Key 'Interactive'
            $Graph = (Get-AzTokenCall -Kind Graph)[0]
            $Arm = (Get-AzTokenCall -Kind Arm)[0]
            $Graph.Resource | Should -BeExactly $Row.GraphResource
            $Arm.Resource | Should -BeExactly $Row.ArmHost
            # Observed DURING each call: Azure.Identity bakes the authority in when it builds the credential.
            $Graph.Authority | Should -BeExactly $Row.AuthorityHost
            $Arm.Authority | Should -BeExactly $Row.AuthorityHost
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It -ParameterFilter { $Environment -ceq $GraphEnvironment }
            # Borrowed, not taken: the process is handed back exactly as it was found.
            Test-Path -Path 'Env:AZURE_AUTHORITY_HOST' | Should -BeFalse
        }

        It 'does not reuse a Global token for the same tenant and account in USGov' {
            $First = Invoke-CloudSignIn -State $null -Arguments @{ TenantId = $TenantA }
            $First.State.Environment | Should -BeExactly 'Global'
            # Same tenant, same account, a Graph token still valid: only the cloud differs.
            $Second = Invoke-CloudSignIn -State $First.State -Arguments @{ TenantId = $TenantA; Environment = 'USGov' }
            $Second.Caught | Should -BeNullOrEmpty
            $Second.State.Environment | Should -BeExactly 'USGov'
            Assert-AzTokenCall -Graph 2 -Arm 0
            @(Get-AzTokenCall -Kind Graph | Where-Object { $_.Resource -ceq 'https://graph.microsoft.us/' }).Count | Should -Be 1
        }
    }

    Context 'When AZURE_AUTHORITY_HOST is borrowed for the sign-in (A11, R9)' {
        # R9: the variable is set ONCE around both token calls off Global and put back in a finally on
        # every path; the cached return comes before it, so a cached session writes nothing and warns
        # about nothing. The Describe starts every It with the variable absent.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzToken -MockWith $script:AzTokenMock
            Mock -ModuleName Omnicit.PIM Connect-MgGraph {}
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionFingerprint { 'fp' }
            function Invoke-BorrowSignIn {
                param([AllowNull()][hashtable]$State, [hashtable]$Arguments = @{})
                InModuleScope Omnicit.PIM -Parameters @{ State = $State; Arguments = $Arguments } {
                    param($State, $Arguments)
                    $script:_OPIMAuthState = $State
                    $Caught = $null
                    $Warned = $null
                    try {
                        Initialize-OPIMAuth @Arguments -WarningVariable Warned -WarningAction SilentlyContinue
                    } catch {
                        $Caught = $PSItem
                    }
                    @{ Caught = $Caught; State = $script:_OPIMAuthState; Warnings = @($Warned | ForEach-Object { [string]$_.Message }); Tracker = $script:_OPIMLastAuthorityHost }
                }
            }
        }
        BeforeEach {
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

        It 'sets AZURE_AUTHORITY_HOST for the Microsoft Graph call of a USGov sign-in, and puts back the variable that was <Was>' -ForEach @(
            @{ Was = 'absent'; Operator = $null }
            @{ Was = 'set by the operator'; Operator = 'https://login.example.com/' }
        ) {
            if ($null -ne $Operator) { [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $Operator) }
            $Result = Invoke-BorrowSignIn -State $null -Arguments @{ TenantId = $TenantA; Environment = 'USGov' }
            $Result.Caught | Should -BeNullOrEmpty
            Assert-AzTokenCall -Graph 1 -Arm 0
            $script:SeenGraphAuthorityHost | Should -BeExactly 'https://login.microsoftonline.us/'
            Test-Path -Path 'Env:AZURE_AUTHORITY_HOST' | Should -Be ($null -ne $Operator)
            [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -Be $Operator
        }

        It 'restores AZURE_AUTHORITY_HOST when the Microsoft Graph Get-AzToken throws and the variable was <Was>' -ForEach @(
            @{ Was = 'absent'; Operator = $null }
            @{ Was = 'set by the operator'; Operator = 'https://login.example.com/' }
        ) {
            $script:AzTokenThrowAt = @(1)
            if ($null -ne $Operator) { [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $Operator) }
            $Result = Invoke-BorrowSignIn -State $null -Arguments @{ TenantId = $TenantA; Environment = 'China'; IncludeARM = $true }
            $Result.Caught.FullyQualifiedErrorId | Should -BeLike 'InteractiveAuthFailed*'
            Assert-AzTokenCall -Graph 1 -Arm 0
            (Get-AzTokenCall -Kind Graph)[0].Authority | Should -BeExactly 'https://login.chinacloudapi.cn/'
            Test-Path -Path 'Env:AZURE_AUTHORITY_HOST' | Should -Be ($null -ne $Operator)
            [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -Be $Operator
        }

        It 'restores AZURE_AUTHORITY_HOST when Connect-MgGraph throws and the variable was <Was>' -ForEach @(
            @{ Was = 'absent'; Operator = $null }
            @{ Was = 'set by the operator'; Operator = 'https://login.example.com/' }
        ) {
            Mock -ModuleName Omnicit.PIM Connect-MgGraph { throw [System.InvalidOperationException]::new('connect failed') }
            if ($null -ne $Operator) { [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $Operator) }
            $Result = Invoke-BorrowSignIn -State $null -Arguments @{ TenantId = $TenantA; Environment = 'USGovDoD'; IncludeARM = $true }
            $Result.Caught | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
            Assert-AzTokenCall -Graph 1 -Arm 0
            (Get-AzTokenCall -Kind Graph)[0].Authority | Should -BeExactly 'https://login.microsoftonline.us/'
            Test-Path -Path 'Env:AZURE_AUTHORITY_HOST' | Should -Be ($null -ne $Operator)
            [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -Be $Operator
        }

        It 'restores AZURE_AUTHORITY_HOST when the ARM Get-AzToken throws after the Graph sign-in, and the variable was <Was>' -ForEach @(
            @{ Was = 'absent'; Operator = $null }
            @{ Was = 'set by the operator'; Operator = 'https://login.example.com/' }
        ) {
            $script:AzTokenThrowAt = @(2)
            if ($null -ne $Operator) { [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $Operator) }
            $Result = Invoke-BorrowSignIn -State $null -Arguments @{ TenantId = $TenantA; Environment = 'USGov'; IncludeARM = $true }
            $Result.Caught.FullyQualifiedErrorId | Should -BeLike 'AzureConnectFailed*'
            Assert-AzTokenCall -Graph 1 -Arm 1
            (Get-AzTokenCall -Kind Arm)[0].Authority | Should -BeExactly 'https://login.microsoftonline.us/'
            Test-Path -Path 'Env:AZURE_AUTHORITY_HOST' | Should -Be ($null -ne $Operator)
            [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -Be $Operator
        }

        It 'writes no AZURE_AUTHORITY_HOST for a Microsoft Graph sign-in in the Global cloud' {
            $Result = Invoke-BorrowSignIn -State $null -Arguments @{ TenantId = $TenantA }
            $Result.Caught | Should -BeNullOrEmpty
            Assert-AzTokenCall -Graph 1 -Arm 0
            $null -eq $script:SeenGraphAuthorityHost | Should -BeTrue -Because 'the Global path writes no AZURE_AUTHORITY_HOST at all'
            Test-Path -Path 'Env:AZURE_AUTHORITY_HOST' | Should -BeFalse
        }

        It 'warns once per sign-in when AZURE_AUTHORITY_HOST names another authority in the Global cloud (<Name>)' -ForEach @(
            @{ Name = 'Microsoft Graph only'; IncludeARM = $false; Arm = 0 }
            @{ Name = 'Microsoft Graph and Azure'; IncludeARM = $true; Arm = 1 }
        ) {
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', 'https://login.example.com/')
            $Result = Invoke-BorrowSignIn -State $null -Arguments @{ TenantId = $TenantA; IncludeARM = $IncludeARM }
            $Result.Caught | Should -BeNullOrEmpty
            @($Result.Warnings).Count | Should -Be 1
            $Result.Warnings[0] | Should -BeLike '*AZURE_AUTHORITY_HOST is set to ''https://login.example.com/''*'
            $Result.Warnings[0] | Should -BeLike '*global cloud''s authority ''https://login.microsoftonline.com/''*'
            $Result.Warnings[0] | Should -BeLike '*for Microsoft Graph and for Azure*'
            $Result.Warnings[0] | Should -BeLike '*Remove-Item Env:AZURE_AUTHORITY_HOST*'
            Assert-AzTokenCall -Graph 1 -Arm $Arm
            foreach ($Call in $script:AzTokenCalls) {
                $Call.Authority | Should -BeExactly 'https://login.example.com/' -Because 'the Global path writes nothing, and AzAuth sees the operator''s value'
            }
            [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -BeExactly 'https://login.example.com/'
        }

        It 'writes nothing and warns about nothing on a cached return of a <Cloud> session' -ForEach @(
            @{ Cloud = 'Global'; ArmHost = 'https://management.azure.com' }
            @{ Cloud = 'USGov'; ArmHost = 'https://management.usgovcloudapi.net' }
        ) {
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', 'https://login.example.com/')
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
            $State.Environment = $Cloud
            $null = Add-ArmTestToken -State $State -TenantId $TenantA -ObjectId $SessionOid
            $State.ArmResourceUrl = $ArmHost
            $Result = Invoke-BorrowSignIn -State $State -Arguments @{ IncludeARM = $true }
            $Result.Caught | Should -BeNullOrEmpty
            @($Result.Warnings).Count | Should -Be 0
            Assert-AzTokenCall -Graph 0 -Arm 0
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
            # The cached return records no authority: nothing built a credential.
            $Result.Tracker | Should -BeNullOrEmpty
            [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -BeExactly 'https://login.example.com/'
        }
    }

    Context 'When AzAuth rebuilds its credential (Force; EntraRBAC A17, R8)' {
        # AzAuth keeps one credential per process. -Force makes it build a new one: on every device code
        # token request (a reused device code credential never returns, A17), on -ForceRefresh, and when
        # the cloud's authority differs from the one the module last asked AzAuth for
        # ($script:_OPIMLastAuthorityHost, recorded before the token call and never cleared by
        # Disconnect-OPIM). After a Graph acquisition the ARM request keeps Force only for -ForceRefresh
        # or a device code. Every assertion counts the requests exactly, Graph and ARM apart.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzToken -MockWith $script:AzTokenMock
            Mock -ModuleName Omnicit.PIM Connect-MgGraph {}
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionFingerprint { 'fp' }
            # Disconnect-OPIM calls it, and the transport tripwire refuses a real one.
            Mock -ModuleName Omnicit.PIM Disconnect-MgGraph {}
            function Invoke-ForceSignIn {
                param([hashtable]$Parameters)
                InModuleScope Omnicit.PIM -Parameters @{ P = $Parameters } {
                    param($P)
                    Initialize-OPIMAuth @P
                }
            }
            # Moves the cached tokens' expiry, as time passing would.
            function Set-ForceExpiry {
                param([int]$GraphMinutes, [int]$ArmMinutes)
                InModuleScope Omnicit.PIM -Parameters @{ G = $GraphMinutes; A = $ArmMinutes } {
                    param($G, $A)
                    $script:_OPIMAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes($G)
                    $script:_OPIMAuthState.ArmTokenExpiry = [DateTime]::UtcNow.AddMinutes($A)
                }
            }
        }
        BeforeEach {
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

        Context 'a device code sign-in' {
            It 'D1: a first device code sign-in with -IncludeARM sends the Graph and the ARM token request with Force' {
                Invoke-ForceSignIn @{ TenantId = $TenantA; DeviceCode = $true; IncludeARM = $true }
                Assert-AzTokenCall -Graph 1 -Arm 1 -Force $true -Key 'DeviceCode'
            }

            It 'D1b: a first device code sign-in without -IncludeARM sends one Graph token request, with Force' {
                Invoke-ForceSignIn @{ TenantId = $TenantA; DeviceCode = $true }
                Assert-AzTokenCall -Graph 1 -Arm 0 -Force $true -Key 'DeviceCode'
            }

            It 'D2: a command that starts within five minutes of expiry and inherits the session renews both tokens with Force' {
                Invoke-ForceSignIn @{ TenantId = $TenantA; DeviceCode = $true; IncludeARM = $true }
                Set-ForceExpiry -GraphMinutes 2 -ArmMinutes 2
                $script:AzTokenCalls.Clear()
                # No -TenantId and no -DeviceCode: inherited from the session, as every cmdlet does.
                Invoke-ForceSignIn @{ IncludeARM = $true }
                Assert-AzTokenCall -Graph 1 -Arm 1 -Force $true -Key 'DeviceCode'
            }

            It 'D3: an ARM token acquired beside a cached Graph token is requested with Force' {
                Invoke-ForceSignIn @{ TenantId = $TenantA; DeviceCode = $true; IncludeARM = $true }
                Set-ForceExpiry -GraphMinutes 60 -ArmMinutes 2
                $script:AzTokenCalls.Clear()
                Invoke-ForceSignIn @{ IncludeARM = $true }
                Assert-AzTokenCall -Graph 0 -Arm 1 -Force $true -Key 'DeviceCode'
            }

            It 'D4: -ForceRefresh -IncludeARM on a device code session sends both token requests with Force' {
                Invoke-ForceSignIn @{ TenantId = $TenantA; DeviceCode = $true; IncludeARM = $true }
                $script:AzTokenCalls.Clear()
                Invoke-ForceSignIn @{ TenantId = $TenantA; IncludeARM = $true; ForceRefresh = $true }
                Assert-AzTokenCall -Graph 1 -Arm 1 -Force $true -Key 'DeviceCode'
            }

            It 'D5: a claims challenge on a device code session sends one Graph token request with Force and the claims' {
                Invoke-ForceSignIn @{ TenantId = $TenantA; DeviceCode = $true }
                $script:AzTokenCalls.Clear()
                Invoke-ForceSignIn @{ TenantId = $TenantA; ClaimsChallenge = '{"access_token":{"acrs":{"essential":true,"value":"c1"}}}' }
                Assert-AzTokenCall -Graph 1 -Arm 0 -Force $true -Key 'DeviceCode', 'Claim'
            }

            It 'D6: a device code sign-in after Disconnect-OPIM sends both token requests with Force' {
                Invoke-ForceSignIn @{ TenantId = $TenantA; DeviceCode = $true; IncludeARM = $true }
                Disconnect-OPIM
                Should -Invoke -ModuleName Omnicit.PIM Disconnect-MgGraph -Times 1 -Exactly -Scope It
                (InModuleScope Omnicit.PIM { $null -eq $script:_OPIMAuthState }) | Should -BeTrue
                $script:AzTokenCalls.Clear()
                Invoke-ForceSignIn @{ TenantId = $TenantA; DeviceCode = $true; IncludeARM = $true }
                Assert-AzTokenCall -Graph 1 -Arm 1 -Force $true -Key 'DeviceCode'
            }

            It 'D7: a device code session whose tokens are still valid answers from the cache, with no token request' {
                Invoke-ForceSignIn @{ TenantId = $TenantA; DeviceCode = $true; IncludeARM = $true }
                $AfterFirst = $script:AzTokenCalls.Count
                Invoke-ForceSignIn @{ TenantId = $TenantA; DeviceCode = $true; IncludeARM = $true }
                $AfterFirst | Should -Be 2
                Assert-AzTokenCall -Graph 1 -Arm 1 -Force $true
            }
        }

        Context 'a sign-in in the system browser' {
            It 'N1: the first sign-in with -IncludeARM sends both token requests without Force' {
                Invoke-ForceSignIn @{ TenantId = $TenantA; IncludeARM = $true }
                Assert-AzTokenCall -Graph 1 -Arm 1 -Force $false -Key 'Interactive'
            }

            It 'N2: renewing the session at a command''s start sends both token requests without Force' {
                Invoke-ForceSignIn @{ TenantId = $TenantA; IncludeARM = $true }
                Set-ForceExpiry -GraphMinutes 2 -ArmMinutes 2
                $script:AzTokenCalls.Clear()
                Invoke-ForceSignIn @{ TenantId = $TenantA; IncludeARM = $true }
                Assert-AzTokenCall -Graph 1 -Arm 1 -Force $false -Key 'Interactive'
            }

            It 'N3: a claims challenge sends one Graph token request with the claims and without Force' {
                Invoke-ForceSignIn @{ TenantId = $TenantA }
                $script:AzTokenCalls.Clear()
                Invoke-ForceSignIn @{ TenantId = $TenantA; ClaimsChallenge = '{"access_token":{"acrs":{"essential":true,"value":"c1"}}}' }
                Assert-AzTokenCall -Graph 1 -Arm 0 -Force $false -Key 'Interactive', 'Claim'
            }

            It 'N4: a sign-in after Disconnect-OPIM sends both token requests without Force' {
                Invoke-ForceSignIn @{ TenantId = $TenantA; IncludeARM = $true }
                Disconnect-OPIM
                Should -Invoke -ModuleName Omnicit.PIM Disconnect-MgGraph -Times 1 -Exactly -Scope It
                (InModuleScope Omnicit.PIM { $null -eq $script:_OPIMAuthState }) | Should -BeTrue
                $script:AzTokenCalls.Clear()
                Invoke-ForceSignIn @{ TenantId = $TenantA; IncludeARM = $true }
                Assert-AzTokenCall -Graph 1 -Arm 1 -Force $false -Key 'Interactive'
            }

            It 'keeps -Force on both token requests when the caller passed -ForceRefresh' {
                Invoke-ForceSignIn @{ TenantId = $TenantA }
                $script:AzTokenCalls.Clear()
                Invoke-ForceSignIn @{ TenantId = $TenantA; IncludeARM = $true; ForceRefresh = $true }
                Assert-AzTokenCall -Graph 1 -Arm 1 -Force $true -Key 'Interactive'
            }
        }

        Context 'a move of the authority' {
            It 'passes -Force on the Graph request of a cloud switch, and does not repeat it on the ARM request after it' {
                Invoke-ForceSignIn @{ TenantId = $TenantA }
                $script:AzTokenCalls.Clear()
                Invoke-ForceSignIn @{ TenantId = $TenantA; Environment = 'USGov'; IncludeARM = $true }
                Assert-AzTokenCall -Graph 1 -Arm 1 -GraphForce $true -ArmForce $false -Key 'Interactive'
            }

            It 'keeps -Force on an ARM-only request whose authority differs from the last attempt' {
                # 1: the Global Graph token, cached below. 2: a USGov attempt that fails after AzAuth
                # built its credential there. 3: the ARM request of the inherited Global session, alone.
                $script:AzTokenThrowAt = @(2)
                Invoke-ForceSignIn @{ TenantId = $TenantA }
                try { Invoke-ForceSignIn @{ TenantId = $TenantA; Environment = 'USGov' } } catch { $null = $PSItem }
                (InModuleScope Omnicit.PIM { $script:_OPIMAuthState.Environment }) | Should -BeExactly 'Global'
                @(Get-AzTokenCall -Kind Graph).Count | Should -Be 2 -Because 'the failed attempt must have reached AzAuth'
                $script:AzTokenThrowAt = @()
                $script:AzTokenCalls.Clear()
                Invoke-ForceSignIn @{ TenantId = $TenantA; IncludeARM = $true }
                Assert-AzTokenCall -Graph 0 -Arm 1 -Force $true -Key 'Interactive'
            }

            It 'passes -Force on the next Global sign-in after a sovereign sign-in threw' {
                # The authority is recorded before the token call: AzAuth builds its credential and THEN
                # asks for the token, so a failed sovereign attempt still leaves it built there.
                $script:AzTokenThrowAt = @(1)
                try { Invoke-ForceSignIn @{ TenantId = $TenantA; Environment = 'USGov' } } catch { $null = $PSItem }
                @(Get-AzTokenCall -Kind Graph).Count | Should -Be 1 -Because 'the failed attempt must have reached AzAuth'
                (InModuleScope Omnicit.PIM { $null -eq $script:_OPIMAuthState }) | Should -BeTrue
                $script:AzTokenThrowAt = @()
                $script:AzTokenCalls.Clear()
                Invoke-ForceSignIn @{ TenantId = $TenantA }
                (InModuleScope Omnicit.PIM { $script:_OPIMAuthState.Environment }) | Should -BeExactly 'Global'
                Assert-AzTokenCall -Graph 1 -Arm 0 -Force $true
            }

            It 'still passes no -Force on a first Global sign-in in a clean process' {
                Invoke-ForceSignIn @{ TenantId = $TenantA }
                Assert-AzTokenCall -Graph 1 -Arm 0 -Force $false
                (InModuleScope Omnicit.PIM { $script:_OPIMLastAuthorityHost }) | Should -BeExactly 'https://login.microsoftonline.com/'
            }

            It 'passes -Force on a cloud switch and none on a new sign-in in the same cloud' {
                Invoke-ForceSignIn @{ TenantId = $TenantA }
                $script:AzTokenCalls.Clear()
                Invoke-ForceSignIn @{ TenantId = $TenantA; Environment = 'USGov' }
                Assert-AzTokenCall -Graph 1 -Arm 0 -Force $true
                # Another tenant in the same cloud, the second documentation tenant named by domain: the
                # cache misses, and AzAuth's credential is already at this authority.
                $script:GraphTid = $TenantB
                $script:AzTokenCalls.Clear()
                Invoke-ForceSignIn @{ TenantId = 'fabrikam.onmicrosoft.com'; Environment = 'USGov' }
                Assert-AzTokenCall -Graph 1 -Arm 0 -Force $false
                (Get-AzTokenCall -Kind Graph)[0].Keys | Should -Contain 'Tenant'
                (InModuleScope Omnicit.PIM { $script:_OPIMAuthState.TenantId }) | Should -BeExactly 'fabrikam.onmicrosoft.com'
            }

            It 'keeps the recorded authority across Disconnect-OPIM, since AzAuth''s credential outlives it' {
                Invoke-ForceSignIn @{ TenantId = $TenantA; Environment = 'China' }
                Disconnect-OPIM
                (InModuleScope Omnicit.PIM { $script:_OPIMLastAuthorityHost }) | Should -BeExactly 'https://login.chinacloudapi.cn/'
                $script:AzTokenCalls.Clear()
                Invoke-ForceSignIn @{ TenantId = $TenantA }
                Assert-AzTokenCall -Graph 1 -Arm 0 -Force $true
            }
        }
    }

    Context 'When the Graph token and the ARM token are handed on' {
        BeforeAll {
            # SECURITY rule 5: PowerShell module logging (LogPipelineExecutionDetails, event 4103)
            # records every value bound to a command parameter. These three detectors read a function's
            # AST statically: the first It runs them on Initialize-OPIMAuth as the module loaded it, and
            # the known answer after it runs them on texts that break the rule, so a detector that stops
            # seeing a shape turns red there instead of passing the function vacuously.
            #
            # A token member is read by its string VALUE, not by its source text: $Result.AccessToken,
            # $Result.'AccessToken' and $Result."AccessToken" name the same member, and only the first
            # has the text AccessToken. Member names are case-insensitive in PowerShell, so -in (which
            # is too) is right. KNOWN LIMIT: a member named by an expression ($Result.$Name) has no
            # constant value to read; review has to catch that shape.

            # Every command call one of whose arguments reaches an .AccessToken or a .Token member, as
            # 'line <n>: <command name>'.
            function Get-PlaintextTokenCommandArgument {
                param([Parameter(Mandatory)][System.Management.Automation.Language.Ast]$Ast)
                $Commands = @($Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true))
                foreach ($Command in $Commands) {
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
            }

            # Every read of either plaintext member, wherever it sits (an argument, a splatted hashtable's
            # value, an assignment to a local variable, a method call's argument), one entry per read:
            # 'NetworkCredential:<member>' for an argument of the NetworkCredential constructor,
            # 'IfTest:<member>' for a truthiness test in an if condition, and 'line <n>: <parent text>'
            # for any other read. Only the first two are allowed.
            function Get-PlaintextTokenUse {
                param([Parameter(Mandatory)][System.Management.Automation.Language.Ast]$Ast)
                $TokenMembers = @($Ast.FindAll({
                            param($Node)
                            $Node -is [System.Management.Automation.Language.MemberExpressionAst] -and
                            $Node -isnot [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                            $Node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                            $Node.Member.Value -in 'AccessToken', 'Token'
                        }, $true))
                foreach ($Member in $TokenMembers) {
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
            }

            # How the result of every NetworkCredential constructor is read, one entry per constructor:
            # 'SecurePassword' when the constructor is followed directly by .SecurePassword, the form
            # the function writes, and 'line <n>: <parent text>' otherwise. The plaintext property
            # (.Password) or the user name would hand the token on as a string. A constructor wrapped in
            # parentheses is reported even when .SecurePassword follows, which errs on the side of
            # refusing.
            function Get-NetworkCredentialRead {
                param([Parameter(Mandatory)][System.Management.Automation.Language.Ast]$Ast)
                $Constructors = @($Ast.FindAll({
                            param($Node)
                            $Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                            $Node.Member.Extent.Text -eq 'new' -and
                            $Node.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and
                            $Node.Expression.TypeName.FullName -eq 'System.Net.NetworkCredential'
                        }, $true))
                foreach ($Constructor in $Constructors) {
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
            }
        }

        It 'binds the plaintext token to no command' {
            # Static check on the function as the module loaded it: no argument of any command call
            # reaches a .Token member of an AzAuth result (A16: the Microsoft Graph token and the ARM
            # token both come from Get-AzToken) or an .AccessToken member, so the plaintext only ever
            # reaches .NET (the SecureString is what commands receive). The only reads of .Token
            # anywhere in the function -- in a hashtable that is splatted, behind a variable or in a
            # method call as much as in a command's own arguments -- are the NetworkCredential
            # constructor (once for each token) and a truthiness test in an if (once for each token);
            # .AccessToken, the MSAL result's member, is read nowhere; and the constructor's result is
            # read only through .SecurePassword, never .Password.
            $Ast = InModuleScope Omnicit.PIM { (Get-Command Initialize-OPIMAuth).ScriptBlock.Ast }
            $Commands = @($Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true))
            @($Commands | Where-Object { $_.GetCommandName() -eq 'Connect-MgGraph' }).Count |
                Should -Be 1 -Because 'the walk must reach the Connect-MgGraph hand-off; a walk that reads nothing would pass vacuously'
            @($Commands | Where-Object { $_.GetCommandName() -eq 'Get-AzToken' }).Count |
                Should -Be 2 -Because 'the walk must reach both AzAuth calls, with and without the device code pipeline'
            $Hits = Get-PlaintextTokenCommandArgument -Ast $Ast
            $Hits | Should -BeNullOrEmpty

            $Uses = @(Get-PlaintextTokenUse -Ast $Ast)
            @($Uses | Where-Object { $_ -ieq 'NetworkCredential:Token' }).Count | Should -Be 2 -Because 'the Graph token and the ARM token each reach .NET through the NetworkCredential constructor exactly once'
            @($Uses | Where-Object { $_ -ieq 'IfTest:Token' }).Count | Should -Be 2 -Because 'the walk must find the one test, for each token, that the result carries a Token'
            @($Uses | Where-Object { $_ -ilike '*AccessToken*' }) | Should -BeNullOrEmpty -Because 'no MSAL result is read any more'
            @($Uses | Where-Object { $_ -inotmatch '^(NetworkCredential|IfTest):(AccessToken|Token)$' }) | Should -BeNullOrEmpty

            # Every constructor in the function is held to .SecurePassword, not only the two that take a
            # token member.
            $Reads = @(Get-NetworkCredentialRead -Ast $Ast)
            $Reads.Count | Should -Be 2 -Because 'the Graph token and the ARM token each become a SecureString through one constructor'
            @($Reads | Where-Object { $_ -ceq 'SecurePassword' }).Count | Should -Be 2
            @($Reads | Where-Object { $_ -cne 'SecurePassword' }) | Should -BeNullOrEmpty
        }

        It 'flags every way a plaintext token member could reach a command (known answer)' {
            # The negative known answer of the three detectors: each text below breaks the rule in one
            # way and must be reported by the detector named beside it, and the two allowed shapes must
            # be reported by none of them, while still being recognised as what they are. The texts are
            # parsed, never run.
            $ParseShape = {
                param([string]$Text)
                $Errors = $null
                $ShapeAst = [System.Management.Automation.Language.Parser]::ParseInput("function Test-Shape {`n$Text`n}", [ref]$null, [ref]$Errors)
                $Errors | Should -BeNullOrEmpty -Because "the known answer '$Text' must parse"
                $ShapeAst
            }
            $Finding = @{
                CommandArgument = { param($ShapeAst) @(Get-PlaintextTokenCommandArgument -Ast $ShapeAst) }
                Use             = { param($ShapeAst) @(Get-PlaintextTokenUse -Ast $ShapeAst | Where-Object { $_ -inotmatch '^(NetworkCredential|IfTest):(AccessToken|Token)$' }) }
                Read            = { param($ShapeAst) @(Get-NetworkCredentialRead -Ast $ShapeAst | Where-Object { $_ -cne 'SecurePassword' }) }
            }
            $Flagged = @(
                @{ Detector = 'CommandArgument'; Text = 'Write-Verbose $Result.AccessToken' }
                @{ Detector = 'Use'; Text = 'Write-Verbose $Result.AccessToken' }
                @{ Detector = 'Use'; Text = '$Splat = @{ Token = $ArmResult.Token }; Get-Thing @Splat' }
                @{ Detector = 'Use'; Text = '$Plain = $Result.''AccessToken''' }
                @{ Detector = 'Use'; Text = '$List.Add($Result.AccessToken)' }
                @{ Detector = 'Use'; Text = 'if ($Result.AccessToken -eq ''x'') { }' }
                @{ Detector = 'Read'; Text = '[System.Net.NetworkCredential]::new('''', $Result.AccessToken).Password' }
                @{ Detector = 'Read'; Text = '([System.Net.NetworkCredential]::new('''', $Result.AccessToken)).Password' }
            )
            foreach ($Case in $Flagged) {
                $ShapeAst = & $ParseShape $Case.Text
                @(& $Finding[$Case.Detector] $ShapeAst).Count | Should -BeGreaterThan 0 -Because "the $($Case.Detector) detector must report: $($Case.Text)"
            }

            $Allowed = @(
                @{ Text = 'if (-not $Result.AccessToken) { }'; Use = 'IfTest:AccessToken'; Read = $null }
                @{ Text = '[System.Net.NetworkCredential]::new('''', $Result.AccessToken).SecurePassword'; Use = 'NetworkCredential:AccessToken'; Read = 'SecurePassword' }
            )
            foreach ($Case in $Allowed) {
                $ShapeAst = & $ParseShape $Case.Text
                foreach ($Detector in 'CommandArgument', 'Use', 'Read') {
                    @(& $Finding[$Detector] $ShapeAst) | Should -BeNullOrEmpty -Because "the $Detector detector must let this allowed shape pass: $($Case.Text)"
                }
                (@(Get-PlaintextTokenUse -Ast $ShapeAst) -join ',') | Should -BeExactly $Case.Use
                (@(Get-NetworkCredentialRead -Ast $ShapeAst) -join ',') | Should -BeExactly ([string]$Case.Read)
            }
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
                Mock Get-AzToken {
                    [PSCustomObject]@{
                        Token     = $script:_OPIMTestToken
                        ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                        Identity  = 'user@contoso.com'
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
        # OPIM-09 (EntraRBAC A18). The sign-in runs through the Get-AzToken mock, as in the pin context.
        # The Connect-MgGraph mock records that it ran, so the fingerprint mock can tell a read after
        # the connect from one before it.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Get-AzToken {
                    [PSCustomObject]@{
                        Token     = $script:_OPIMTestToken
                        ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                        Identity  = 'user@contoso.com'
                    }
                }
                Mock Connect-MgGraph { $script:_OPIMTestConnected = $true }
                Mock Get-OPIMGraphSessionFingerprint { if ($script:_OPIMTestConnected) { 'fp' } else { 'read-before-the-connect' } }
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
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA
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
                Should -Invoke Get-AzToken -Times 0 -Scope It
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
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA
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
                # Neither a Microsoft Graph nor an ARM token is asked for.
                Should -Invoke Get-AzToken -Times 0 -Scope It
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
            }
        }

        It 'signs in again when the process holds no session' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA
            $State.GraphSessionFingerprint = 'mine'
            $Token = New-OPIMTestAccessToken -TenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ State = $State; Token = $Token } {
                param($State, $Token)
                $script:_OPIMAuthState = $State
                $script:_OPIMTestToken = $Token
                Mock Get-OPIMGraphSessionState { 'Absent' }
                Initialize-OPIMAuth
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It
                Should -Invoke Connect-MgGraph -Times 1 -Exactly -Scope It
                $script:_OPIMAuthState.GraphSessionFingerprint | Should -BeExactly 'fp'
            }
        }

        It 'returns from the cache under its own session' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA
            $State.GraphSessionFingerprint = 'mine'
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Mock Get-OPIMGraphSessionState { 'Own' }
                Initialize-OPIMAuth
                Should -Invoke Get-OPIMGraphSessionState -Times 1 -Exactly -Scope It
                Should -Invoke Get-AzToken -Times 0 -Scope It
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
                Mock Get-AzToken {
                    [PSCustomObject]@{
                        Token     = $script:_OPIMTestToken
                        ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                        Identity  = 'user@contoso.com'
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
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It
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
        # sentinel invocation, and every Unlock assertion names it. The sign-in runs through the
        # Get-AzToken mock, as in the pin context.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Get-AzToken {
                    [PSCustomObject]@{
                        Token     = $script:_OPIMTestToken
                        ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                        Identity  = 'user@contoso.com'
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
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA
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
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -Expired
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Mock Lock-OPIMSignIn { throw [System.InvalidOperationException]::new('stopped at the latch') }
                Mock Get-OPIMGraphSessionState { 'Own' }
                Mock Get-OPIMSignInRefusal {}
                { Initialize-OPIMAuth -TenantId $TenantA -DeviceCode } | Should -Throw '*stopped at the latch*'
                Should -Invoke Get-OPIMSignInRefusal -Times 1 -Exactly -Scope It -ParameterFilter { $OutsideCaller }
                Should -Invoke Get-OPIMGraphSessionState -Times 0 -Scope It
                Should -Invoke Get-AzToken -Times 0 -Scope It
            }
        }

        It 'releases the caller on the cached return' {
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Initialize-OPIMAuth
                Should -Invoke Get-AzToken -Times 0 -Scope It
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
                Mock Get-AzToken {
                    $Answer = if ($Resource -like '*graph*') { $script:_OPIMTestToken } else { $script:_OPIMTestArmToken }
                    [PSCustomObject]@{ Token = $Answer; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'user@contoso.com' }
                }
                Initialize-OPIMAuth -TenantId $TenantA -IncludeARM
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Resource -like '*graph*' }
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter { $Resource -like '*management*' }
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
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA
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
                # A declined or expired code: AzAuth's Get-AzToken throws.
                Mock Get-AzToken { throw [System.InvalidOperationException]::new('code_expired') }
                { Initialize-OPIMAuth -TenantId $TenantA } | Should -Throw -ErrorId 'DeviceCodeAuthFailed*'
                Should -Invoke Lock-OPIMSignIn -Times 1 -Exactly -Scope It
                Should -Invoke Unlock-OPIMSignIn -Times 0 -Scope It
            }
        }

        It 'keeps the caller latched after a failed ARM sign-in' {
            # The Graph token is cached and the ARM sign-in fails: AzureConnectFailed is terminating,
            # so the function ends without releasing the caller.
            $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
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
                Should -Invoke Get-AzToken -Times 0 -Scope It
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
                Mock Get-AzToken {
                    [PSCustomObject]@{
                        Token     = $script:_OPIMTestToken
                        ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                        Identity  = 'user@contoso.com'
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
                Should -Invoke Get-AzToken -Times 1 -Exactly -Scope It
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
                Should -Invoke Get-AzToken -Times 2 -Exactly -Scope It
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
            }
        }
    }

    Context 'When Invoke-OPIMGraphRequest signs in again for a retry (end to end; R13, R17)' {
        # R17: the end-to-end half of the three retry contexts of Invoke-OPIMGraphRequest.Tests.ps1,
        # which mock Initialize-OPIMAuth. Here the real wrapper and the real Initialize-OPIMAuth run
        # together over the Get-AzToken stand-in of this file, with Invoke-MgGraphRequest,
        # Connect-MgGraph and the session fingerprint mocked. R13: AzAuth has no refresh-token path, so
        # the ACRS step-up and the token-rejected retry each sign in to Microsoft Graph again -- with a
        # new device code, and Force (A17), in device code mode, in the system browser otherwise -- and
        # neither asks for an Azure Resource Manager token. The latch table is a recorder that keeps the
        # name of every command it latches and releases (Ruling R-T4b).
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzToken -MockWith $script:AzTokenMock
            Mock -ModuleName Omnicit.PIM Connect-MgGraph {}
            # The session the sign-in records, and the one the retry's session gate then reads.
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionFingerprint { 'fp' }
            # The first send fails with $script:RetryFirstFailure as its message; every later send answers.
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                $script:RetrySends.Add([string]$Uri)
                if ($script:RetrySends.Count -eq 1) {
                    throw [System.Net.Http.HttpRequestException]::new($script:RetryFirstFailure)
                }
                @{ id = 'after-sign-in' }
            }
            # The PIM 400 refusal that asks for the authentication context c1, its claims URL-encoded in
            # the message, as Microsoft Graph refuses an activation under an ACRS policy.
            $AcrsFailure = '{"error":{"code":"RoleAssignmentRequestAcrsValidationFailed",' +
                '"message":"...&claims=%7B%22access_token%22%3A%7B%22acrs%22%3A%7B%22essential%22%3Atrue%2C%20%22value%22%3A%22c1%22%7D%7D%7D"}}'
            # A bearer token Microsoft Graph refused as expired.
            $RejectedFailure = '{"error":{"code":"InvalidAuthenticationToken","message":"Access token has expired."}}'

            # A session as Initialize-OPIMAuth writes it, in the given mode, under its own Graph SDK session.
            function New-RetrySessionState {
                param([bool]$DeviceCode)
                $State = New-PinState -TenantId $TenantA -TokenTenantId $TenantA -ObjectId $SessionOid
                $State.DeviceCode = $DeviceCode
                $State.Environment = 'Global'
                $State.GraphSessionFingerprint = 'fp'
                $State
            }

            # Puts a recorder in place of the latch table: the three methods of the
            # ConditionalWeakTable that Lock-OPIMSignIn, Unlock-OPIMSignIn and Get-OPIMSignInRefusal
            # call, over a real table, each recording the name of the command it is handed.
            function Install-LatchRecorder {
                InModuleScope Omnicit.PIM {
                    $Recorder = [pscustomobject]@{
                        Table    = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
                        Latched  = [System.Collections.Generic.List[string]]::new()
                        Released = [System.Collections.Generic.List[string]]::new()
                    }
                    Add-Member -InputObject $Recorder -MemberType ScriptMethod -Name AddOrUpdate -Value {
                        param($Key, $Value)
                        $this.Latched.Add([string]$Key.MyCommand.Name)
                        $this.Table.AddOrUpdate($Key, $Value)
                    }
                    Add-Member -InputObject $Recorder -MemberType ScriptMethod -Name TryGetValue -Value {
                        param($Key, $Reference)
                        $Found = $null
                        $Held = $this.Table.TryGetValue($Key, [ref]$Found)
                        $Reference.Value = $Found
                        $Held
                    }
                    Add-Member -InputObject $Recorder -MemberType ScriptMethod -Name Remove -Value {
                        param($Key)
                        $this.Released.Add([string]$Key.MyCommand.Name)
                        $this.Table.Remove($Key)
                    }
                    $script:_OPIMSignInLatch = $Recorder
                }
            }
        }
        BeforeEach {
            $script:RetrySends = [System.Collections.Generic.List[string]]::new()
            $script:RetryFirstFailure = $null
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_OPIMSignInLatch = $null
            }
            Install-LatchRecorder
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_OPIMSignInLatch = $null
            }
        }

        It 'steps up with one Microsoft Graph sign-in that carries the claims, <Text>, and sends the request once more, in <Mode>' -ForEach @(
            @{ Mode = 'device code mode'; DeviceCode = $true; Key = @('Claim', 'DeviceCode', 'WarningAction'); Absent = @('Interactive'); Force = $true; Text = 'a new device code and Force' }
            @{ Mode = 'the system browser'; DeviceCode = $false; Key = @('Claim', 'Interactive'); Absent = @('DeviceCode', 'WarningAction'); Force = $false; Text = 'the browser and no Force' }
        ) {
            $script:RetryFirstFailure = $AcrsFailure
            $State = New-RetrySessionState -DeviceCode $DeviceCode
            $Out = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                $Result = Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/some/requests' -Body @{}
                [pscustomobject]@{ Result = $Result; State = $script:_OPIMAuthState; Latch = $script:_OPIMSignInLatch }
            }
            $Out.Result.id | Should -BeExactly 'after-sign-in'
            $script:RetrySends.Count | Should -Be 2 -Because 'the request is sent once, and once more after the step-up'
            # One Microsoft Graph sign-in, never an Azure Resource Manager one (Review Focus 3), in the mode the
            # session's state records -- in device code mode with -WarningAction Continue, so the new code
            # reaches the Information stream (Review Focus 2).
            Assert-AzTokenCall -Graph 1 -Arm 0 -Force $Force -Key $Key
            foreach ($Name in $Absent) {
                (Get-AzTokenCall -Kind Graph)[0].Keys | Should -Not -Contain $Name
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-AzToken -Times 1 -Exactly -Scope It -ParameterFilter {
                $Resource -ceq 'https://graph.microsoft.com/' -and $Claim -match 'acrs' -and $Claim -match '"c1"'
            }
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
            $Out.State.ClaimsSatisfied | Should -BeTrue
            $Out.State.DeviceCode | Should -Be $DeviceCode
            $Out.State.TokenTenantId | Should -BeExactly $TenantA
            # The step-up latched the wrapper's request function and released it once it succeeded.
            ($Out.Latch.Latched -join ', ') | Should -BeExactly 'Invoke-OPIMGraphSingle'
            ($Out.Latch.Released -join ', ') | Should -BeExactly 'Invoke-OPIMGraphSingle'
        }

        It 'signs in to Microsoft Graph again with Force, <Text>, and sends the request once more when the token is rejected, in <Mode>' -ForEach @(
            @{ Mode = 'device code mode'; DeviceCode = $true; Key = @('DeviceCode', 'WarningAction'); Absent = @('Interactive', 'Claim'); Text = 'with a new device code' }
            @{ Mode = 'the system browser'; DeviceCode = $false; Key = @('Interactive'); Absent = @('DeviceCode', 'WarningAction', 'Claim'); Text = 'in the browser' }
        ) {
            $script:RetryFirstFailure = $RejectedFailure
            $State = New-RetrySessionState -DeviceCode $DeviceCode
            $Out = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                $Result = Invoke-OPIMGraphRequest -Uri 'v1.0/some/resource'
                [pscustomobject]@{ Result = $Result; State = $script:_OPIMAuthState; Latch = $script:_OPIMSignInLatch }
            }
            $Out.Result.id | Should -BeExactly 'after-sign-in'
            $script:RetrySends.Count | Should -Be 2 -Because 'the request is sent once, and once more after the new sign-in'
            # -ForceRefresh: Force in either mode (R8), and the mode the session's state records, never the
            # other one -- in device code mode with -WarningAction Continue (Review Focus 2).
            Assert-AzTokenCall -Graph 1 -Arm 0 -Force $true -Key $Key
            foreach ($Name in $Absent) {
                (Get-AzTokenCall -Kind Graph)[0].Keys | Should -Not -Contain $Name
            }
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
            $Out.State.ClaimsSatisfied | Should -BeFalse
            $Out.State.DeviceCode | Should -Be $DeviceCode
            $Out.State.TokenTenantId | Should -BeExactly $TenantA
            ($Out.Latch.Latched -join ', ') | Should -BeExactly 'Invoke-OPIMGraphSingle'
            ($Out.Latch.Released -join ', ') | Should -BeExactly 'Invoke-OPIMGraphSingle'
        }

        It 'refuses a new token for another tenant, keeps the request function latched and sends no retry' {
            # Moved R-T4b. The token-rejected retry signs in again with a device code, and AzAuth hands
            # back a token for another tenant: TenantMismatch before Connect-MgGraph or the auth state.
            # Inside Pester the error the caller sees is TenantMismatch: the retry's Initialize-OPIMAuth
            # raises it as a terminating error, and Pester's own try (and this test's) makes it propagate
            # out of the wrapper before the retry's gates run. Outside any try the wrapper carries on to
            # them, and the latch gate finds the frame of the wrapper's nested Invoke-OPIMGraphSingle,
            # which called Initialize-OPIMAuth and holds the retry's gates -- latched, as this test
            # records -- and throws SignInRefused; Invoke-OPIMGraphRequest.Tests.ps1 holds that gate.
            $script:RetryFirstFailure = $RejectedFailure
            $script:GraphTid = $TenantB
            $State = New-RetrySessionState -DeviceCode $true
            $Out = InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                $Caught = $null
                try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } catch { $Caught = $PSItem }
                [pscustomobject]@{ Caught = $Caught; State = $script:_OPIMAuthState; Latch = $script:_OPIMSignInLatch }
            }
            $Out.Caught.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
            $script:RetrySends.Count | Should -Be 1 -Because 'a refused sign-in sends no retry'
            Assert-AzTokenCall -Graph 1 -Arm 0 -Force $true -Key 'DeviceCode', 'WarningAction'
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 0 -Scope It
            # The session is left as it was.
            $Out.State.TenantId | Should -BeExactly $TenantA
            $Out.State.TokenTenantId | Should -BeExactly $TenantA
            $Out.State.GraphSessionFingerprint | Should -BeExactly 'fp'
            $Out.State.DeviceCode | Should -BeTrue
            ($Out.Latch.Latched -join ', ') | Should -BeExactly 'Invoke-OPIMGraphSingle'
            $Out.Latch.Released.Count | Should -Be 0
        }
    }

    Context 'When a command starts within five minutes of the expiry (D2b, N2; R13)' {
        # The template's D2b and N2 through public cmdlets. The renewal at a command's start is a new
        # sign-in (R13), with Force in device code mode (A17) and none in the system browser. Four
        # minutes left is inside the five-minute margin. Get-OPIMAzureRole signs in with -IncludeARM and
        # renews both tokens, Get-OPIMDirectoryRole only the Microsoft Graph token, and each sends its
        # request after the renewal.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzToken -MockWith $script:AzTokenMock
            Mock -ModuleName Omnicit.PIM Connect-MgGraph {}
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionFingerprint { 'fp' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { [pscustomobject]@{ value = @() } }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest { @{ value = @() } }
        }
        BeforeEach {
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

        It 'renews <Renewed> at the start of <Command>, <Text>, in <Mode>' -ForEach @(
            @{ Command = 'Get-OPIMAzureRole'; Renewed = 'both tokens'; Arm = 1; Mode = 'device code mode'; DeviceCode = $true; Force = $true; Key = @('DeviceCode', 'WarningAction'); Text = 'with Force' }
            @{ Command = 'Get-OPIMAzureRole'; Renewed = 'both tokens'; Arm = 1; Mode = 'the system browser'; DeviceCode = $false; Force = $false; Key = 'Interactive'; Text = 'without Force' }
            @{ Command = 'Get-OPIMDirectoryRole'; Renewed = 'the Microsoft Graph token'; Arm = 0; Mode = 'device code mode'; DeviceCode = $true; Force = $true; Key = @('DeviceCode', 'WarningAction'); Text = 'with Force' }
            @{ Command = 'Get-OPIMDirectoryRole'; Renewed = 'the Microsoft Graph token'; Arm = 0; Mode = 'the system browser'; DeviceCode = $false; Force = $false; Key = 'Interactive'; Text = 'without Force' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA; DeviceCode = $DeviceCode } {
                param($TenantA, $DeviceCode)
                Initialize-OPIMAuth -TenantId $TenantA -IncludeARM -DeviceCode:$DeviceCode
                $script:_OPIMAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(4)
                $script:_OPIMAuthState.ArmTokenExpiry = [DateTime]::UtcNow.AddMinutes(4)
            }
            $script:AzTokenCalls.Clear()

            $null = & $Command -ErrorAction Stop

            # No -TenantId and no -DeviceCode: the cmdlet inherits both from the session, and a device code
            # request still carries -WarningAction Continue (Review Focus 2).
            Assert-AzTokenCall -Graph 1 -Arm $Arm -Force $Force -Key $Key
            if ($Arm) {
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            } else {
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It
            }
            # The first sign-in's Connect-MgGraph and the renewal's.
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 2 -Exactly -Scope It
            $After = InModuleScope Omnicit.PIM { $script:_OPIMAuthState }
            $After.GraphTokenExpiry | Should -BeGreaterThan ([DateTime]::UtcNow.AddMinutes(30))
            $After.DeviceCode | Should -Be $DeviceCode
        }

        It 'renews only the Microsoft Graph token at the start of Get-OPIMAzureRole and keeps an ARM token with more than five minutes left, in <Mode>' -ForEach @(
            @{ Mode = 'device code mode'; DeviceCode = $true; Force = $true; Key = @('DeviceCode', 'WarningAction') }
            @{ Mode = 'the system browser'; DeviceCode = $false; Force = $false; Key = @('Interactive') }
        ) {
            # The new Graph token is for the same tenant, account and cloud, so the ARM token is carried
            # and, with an hour left, reused without a request (silent reuse).
            $ArmBefore = InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA; DeviceCode = $DeviceCode } {
                param($TenantA, $DeviceCode)
                Initialize-OPIMAuth -TenantId $TenantA -IncludeARM -DeviceCode:$DeviceCode
                $script:_OPIMAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(4)
                $script:_OPIMAuthState.ArmTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                $script:_OPIMAuthState.ArmToken
            }
            $script:AzTokenCalls.Clear()

            $null = Get-OPIMAzureRole -ErrorAction Stop

            Assert-AzTokenCall -Graph 1 -Arm 0 -Force $Force -Key $Key
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            $Kept = InModuleScope Omnicit.PIM -Parameters @{ ArmBefore = $ArmBefore } {
                param($ArmBefore)
                [object]::ReferenceEquals($ArmBefore, $script:_OPIMAuthState.ArmToken)
            }
            $Kept | Should -BeTrue
        }

        It 'shows the new device code of a renewal once on the Information stream, and no warning, when the host silenced warnings and information' {
            # Review Focus 2 and R13: the renewal at a command's start is a new device code sign-in, and
            # the mode comes from the session's state, not from a -DeviceCode on this call. A silenced
            # host must still see the code, or the command waits for a code nobody can read.
            $RenewalCodeText = 'To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code RENEWCODE1 to authenticate.'
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                Initialize-OPIMAuth -TenantId $TenantA -DeviceCode
                $script:_OPIMAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(4)
            }
            $script:AzTokenCalls.Clear()
            $script:GraphWarning = $RenewalCodeText
            # The automation host, silenced in the global scope and in this one, as in D8; put back in a
            # finally, so no later test runs silenced.
            $SavedWarningPreference = $global:WarningPreference
            $SavedInformationPreference = $global:InformationPreference
            try {
                $global:WarningPreference = 'SilentlyContinue'
                $global:InformationPreference = 'SilentlyContinue'
                $WarningPreference = 'SilentlyContinue'
                $InformationPreference = 'SilentlyContinue'
                $Out = @(Get-OPIMDirectoryRole -ErrorAction Stop 6>&1 3>&1)
            } finally {
                $global:WarningPreference = $SavedWarningPreference
                $global:InformationPreference = $SavedInformationPreference
            }

            $Information = @($Out | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
            $Information.Count | Should -Be 1 -Because 'the renewal shows its one new code'
            $Information[0].Tags | Should -Contain 'OPIMDeviceCode'
            [string]$Information[0].MessageData | Should -BeExactly $RenewalCodeText
            @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 0
            Assert-AzTokenCall -Graph 1 -Arm 0 -Force $true -Key 'DeviceCode', 'WarningAction'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It
        }
    }

    Context 'When Connect-OPIM signs in with a device code (D7, D8; R13, A17)' {
        # Connect-OPIM -DeviceCode -IncludeARM, the public way to a device code session. AzAuth writes
        # each sign-in instruction as a WARNING; the module re-emits it on the Information stream with
        # the OPIMDeviceCode tag, for Microsoft Graph and for Azure Resource Manager alike, so a host
        # that silenced warnings still shows both codes. The Get-AzToken stand-in writes
        # $script:GraphWarning and $script:ArmWarning, honouring a bound -WarningAction as the compiled
        # cmdlet does.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Get-AzToken -MockWith $script:AzTokenMock
            Mock -ModuleName Omnicit.PIM Connect-MgGraph {}
            Mock -ModuleName Omnicit.PIM Get-OPIMGraphSessionFingerprint { 'fp' }
            $GraphCodeText = 'To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code GRAPHCODE1 to authenticate.'
            $ArmCodeText = 'To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code ARMCODE1 to authenticate.'
        }
        BeforeEach {
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

        It 'asks for two codes, one each -- Microsoft Graph first, then Azure Resource Manager -- and connects once' {
            Connect-OPIM -TenantId $TenantA -DeviceCode -IncludeARM 6>$null
            Assert-AzTokenCall -Graph 1 -Arm 1 -Force $true -Key 'DeviceCode'
            (@($script:AzTokenCalls | ForEach-Object { $_.Kind }) -join ',') | Should -BeExactly 'Graph,Arm'
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
        }

        It 'D7: answers from the cache, with no token request and no Connect-MgGraph, while both tokens have more than five minutes left' {
            Connect-OPIM -TenantId $TenantA -DeviceCode -IncludeARM 6>$null
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(6)
                $script:_OPIMAuthState.ArmTokenExpiry = [DateTime]::UtcNow.AddMinutes(6)
            }
            $script:AzTokenCalls.Clear()

            # The same tenant (the session's), account and cloud.
            Connect-OPIM -DeviceCode -IncludeARM 6>$null

            @($script:AzTokenCalls).Count | Should -Be 0 -Because 'a device code session whose tokens are still valid answers from the cache'
            # The first sign-in's only.
            Should -Invoke -ModuleName Omnicit.PIM Connect-MgGraph -Times 1 -Exactly -Scope It
            $After = InModuleScope Omnicit.PIM { $script:_OPIMAuthState }
            $After.TokenTenantId | Should -BeExactly $TenantA
            $After.DeviceCode | Should -BeTrue
        }

        It 'D8: shows both device codes once on the Information stream with the OPIMDeviceCode tag, Microsoft Graph first, and no warning, <HostState>' -ForEach @(
            @{ HostState = 'when the host silenced warnings and information'; Silenced = $true }
            @{ HostState = 'under the default preferences'; Silenced = $false }
        ) {
            $script:GraphWarning = $GraphCodeText
            $script:ArmWarning = $ArmCodeText
            # The automation host: warnings and information silenced in the global scope, which module
            # code resolves its preferences through, and in this scope, which the stand-in's body reads.
            # Put back in a finally, so no later test runs silenced.
            $SavedWarningPreference = $global:WarningPreference
            $SavedInformationPreference = $global:InformationPreference
            try {
                if ($Silenced) {
                    $global:WarningPreference = 'SilentlyContinue'
                    $global:InformationPreference = 'SilentlyContinue'
                    $WarningPreference = 'SilentlyContinue'
                    $InformationPreference = 'SilentlyContinue'
                }
                $Out = @(Connect-OPIM -TenantId $TenantA -DeviceCode -IncludeARM 6>&1 3>&1)
            } finally {
                $global:WarningPreference = $SavedWarningPreference
                $global:InformationPreference = $SavedInformationPreference
            }

            $Information = @($Out | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
            $Information.Count | Should -Be 2 -Because 'each sign-in shows its own code, once'
            foreach ($Record in $Information) {
                $Record.Tags | Should -Contain 'OPIMDeviceCode'
            }
            [string]$Information[0].MessageData | Should -BeExactly $GraphCodeText
            [string]$Information[1].MessageData | Should -BeExactly $ArmCodeText
            @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 0
            # Force on both device code requests (A17), each asked with -WarningAction Continue so a
            # silenced preference cannot drop the instruction before it is re-emitted.
            Assert-AzTokenCall -Graph 1 -Arm 1 -Force $true -Key 'DeviceCode', 'WarningAction'
        }

        It 'leaves the AzAuth warnings on the warning stream outside device code mode, and asks Get-AzToken with no WarningAction' {
            $script:GraphWarning = 'An unrelated AzAuth warning for Microsoft Graph.'
            $script:ArmWarning = 'An unrelated AzAuth warning for Azure Resource Manager.'

            $Out = @(Connect-OPIM -TenantId $TenantA -IncludeARM 6>&1 3>&1)

            $Warnings = @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $Warnings.Count | Should -Be 2
            $Warnings[0].Message | Should -BeExactly 'An unrelated AzAuth warning for Microsoft Graph.'
            $Warnings[1].Message | Should -BeExactly 'An unrelated AzAuth warning for Azure Resource Manager.'
            @($Out | Where-Object { $_ -is [System.Management.Automation.InformationRecord] }).Count | Should -Be 0
            Assert-AzTokenCall -Graph 1 -Arm 1 -Force $false -Key 'Interactive'
            foreach ($Call in $script:AzTokenCalls) {
                $Call.Keys | Should -Not -Contain 'WarningAction'
            }
        }
    }
}
