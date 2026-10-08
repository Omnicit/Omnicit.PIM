BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OPIMTestToken.ps1"

    # The tenant of the device code sessions below; a letter-repeat placeholder, not a version-4 id.
    $SessionTenant = 'aaaaaaaa-0000-0000-0000-00000000000a'

    # A failed Graph call as the SDK leaves it: a request message carrying an Authorization header,
    # the response pointing back at it, and an HttpResponseException holding the response. The
    # token is built at runtime and says what it is, so no token-shaped literal sits in this file.
    function New-ScrubFixture {
        param(
            [int]$Status = 403,
            [string]$Content = '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges."}}'
        )
        $Token = 'Bearer ' + ('x' * 40) + 'NOT-A-REAL-TOKEN'
        $Request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, 'https://graph.microsoft.com/v1.0/me')
        $null = $Request.Headers.TryAddWithoutValidation('Authorization', $Token)
        $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Status)
        $Response.RequestMessage = $Request
        $Response.Content = [System.Net.Http.StringContent]::new($Content)
        $Exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Response status code does not indicate success.', $Response)
        [pscustomobject]@{
            Request = $Request
            Record  = [System.Management.Automation.ErrorRecord]::new($Exception, 'HttpFail', 'InvalidOperation', $Request)
        }
    }

    # Runs a script in Omnicit.PIM's scope in a nested pipeline of this runspace and returns what it
    # wrote. Pester runs every It inside a try, and while any try is up the call stack a throw always
    # propagates. A nested pipeline has none above it: a throw in a catch under SilentlyContinue
    # resumes after that try there, and propagates under an outer try (measured 2026-10-07,
    # PowerShell 7.6). So it shows what a caller outside any try receives. The mocks stay in force,
    # since the nested pipeline shares this runspace and the module's session state.
    # The nested script starts from $ErrorActionPreference = 'Continue', a console's default, and a
    # script that needs another preference sets its own after it. Without the pin it inherits the
    # GLOBAL preference, which the workflow's shell: pwsh steps set to Stop: there a terminating error
    # that a Continue caller would see end only its statement ends the whole nested pipeline instead,
    # and Invoke throws (CI run 37657935494, green locally under Continue).
    function Invoke-OutsideAnyTry {
        param([Parameter(Mandatory)][string]$Script)
        $Shell = [powershell]::Create([System.Management.Automation.RunspaceMode]::CurrentRunspace)
        try {
            $null = $Shell.AddScript('param($Module) & $Module { $ErrorActionPreference = ''Continue''; ' + $Script + '}').AddArgument((Get-Module Omnicit.PIM))
            $Output = $Shell.Invoke()
            [pscustomobject]@{ Output = @($Output | Where-Object { $null -ne $_ }) }
        } finally {
            $Shell.Dispose()
        }
    }
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Invoke-OPIMGraphRequest' {
    Context 'When the request succeeds on the first attempt' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Invoke-MgGraphRequest {
                    return @{ value = @(@{ id = 'result-001' }) }
                } -ParameterFilter { $Method -eq 'GET' }
            }
        }

        It 'returns the response from Invoke-MgGraphRequest' {
            InModuleScope Omnicit.PIM {
                $Result = Invoke-OPIMGraphRequest -Uri 'v1.0/some/resource'
                $Result.value | Should -HaveCount 1
                $Result.value[0].id | Should -Be 'result-001'
            }
        }

        It 'passes the URI to Invoke-MgGraphRequest' {
            InModuleScope Omnicit.PIM {
                Invoke-OPIMGraphRequest -Uri 'v1.0/some/resource'
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                    $Uri -eq 'v1.0/some/resource'
                }
            }
        }
    }

    Context 'When called with POST method and a body' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Invoke-MgGraphRequest {
                    return @{ id = 'req-001'; status = 'Provisioned' }
                } -ParameterFilter { $Method -eq 'POST' }
            }
        }

        It 'passes the Method and Body to Invoke-MgGraphRequest' {
            InModuleScope Omnicit.PIM {
                $Result = Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/some/requests' -Body @{ action = 'selfActivate' }
                $Result.id | Should -Be 'req-001'
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                    $Method -eq 'POST' -and $Uri -eq 'v1.0/some/requests'
                }
            }
        }
    }

    Context 'When Invoke-MgGraphRequest throws a non-ACRS error' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'test-tenant'; ClaimsSatisfied = $true }
                Mock Invoke-MgGraphRequest {
                    throw [System.Net.Http.HttpRequestException]::new(
                        '{"error":{"code":"InsufficientPermissions","message":"Access denied"}}'
                    )
                }
                Mock Convert-GraphHttpException {
                    return [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Access denied'),
                        'InsufficientPermissions',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied,
                        $null
                    )
                }
                Mock Initialize-OPIMAuth {}
            }
        }

        It 'throws a converted error record' {
            InModuleScope Omnicit.PIM {
                { Invoke-OPIMGraphRequest -Uri 'v1.0/some/resource' } | Should -Throw
            }
        }

        It 'does not retry on non-ACRS errors' {
            InModuleScope Omnicit.PIM {
                try { Invoke-OPIMGraphRequest -Uri 'v1.0/some/resource' } catch {}
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Scope It
            }
        }
    }

    Context 'When a failed call points at a request message that carries a token' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                # Each call throws the next queued record, exactly as the SDK throws its own.
                Mock Invoke-MgGraphRequest {
                    $Next = $script:_ScrubRecords[$script:_ScrubCalls]
                    $script:_ScrubCalls++
                    $PSCmdlet.ThrowTerminatingError($Next)
                }
                Mock Initialize-OPIMAuth {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_ScrubRecords = $null
                $script:_ScrubCalls = $null
            }
        }

        It 'scrubs the request of a failure it converts' {
            $F = New-ScrubFixture -Status 403
            InModuleScope Omnicit.PIM -ArgumentList $F.Record {
                param($Record)
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com' }
                $script:_ScrubRecords = @($Record)
                $script:_ScrubCalls = 0
                $Thrown = $null
                try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } catch { $Thrown = $PSItem }
                $Thrown.FullyQualifiedErrorId | Should -Be 'Authorization_RequestDenied'
                $Thrown.TargetObject | Should -BeNullOrEmpty
                $Thrown.Exception.InnerException | Should -BeNullOrEmpty
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
            }
            $F.Request.Headers.Contains('Authorization') | Should -BeFalse
        }

        It 'scrubs the request of a retry that fails after a claims step-up' {
            $Challenge = New-ScrubFixture -Status 400 -Content (
                '{"error":{"code":"RoleAssignmentRequestAcrsValidationFailed",' +
                '"message":"...&claims=%7B%22access_token%22%3A%7B%22acrs%22%3A%7B%22essential%22%3Atrue%2C%20%22value%22%3A%22c1%22%7D%7D%7D"}}')
            $Retry = New-ScrubFixture -Status 403
            InModuleScope Omnicit.PIM -ArgumentList $Challenge.Record, $Retry.Record {
                param($First, $Second)
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com' }
                $script:_ScrubRecords = @($First, $Second)
                $script:_ScrubCalls = 0
                $Thrown = $null
                try { Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/some/requests' -Body @{} } catch { $Thrown = $PSItem }
                $Thrown.FullyQualifiedErrorId | Should -Be 'Authorization_RequestDenied'
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ClaimsChallenge -match 'acrs' }
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
            }
            $Challenge.Request.Headers.Contains('Authorization') | Should -BeFalse
            $Retry.Request.Headers.Contains('Authorization') | Should -BeFalse -Because 'the claims retry has its own catch, which must scrub as well'
        }

        It 'scrubs the request of a retry that fails after a token refresh' {
            $Rejected = New-ScrubFixture -Status 401 -Content '{"error":{"code":"InvalidAuthenticationToken","message":"Access token has expired."}}'
            $Retry = New-ScrubFixture -Status 403
            InModuleScope Omnicit.PIM -ArgumentList $Rejected.Record, $Retry.Record {
                param($First, $Second)
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com' }
                $script:_ScrubRecords = @($First, $Second)
                $script:_ScrubCalls = 0
                $Thrown = $null
                try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } catch { $Thrown = $PSItem }
                $Thrown.FullyQualifiedErrorId | Should -Be 'Authorization_RequestDenied'
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ForceRefresh }
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
            }
            $Rejected.Request.Headers.Contains('Authorization') | Should -BeFalse
            $Retry.Request.Headers.Contains('Authorization') | Should -BeFalse -Because 'the refresh retry has its own catch, which must scrub as well'
        }
    }

    Context 'When a retry fails and no try stands up the call stack' {
        # Under -ErrorAction SilentlyContinue with no try up the call stack a throw inside a catch
        # resumes after the whole try statement (Invoke-OutsideAnyTry). A failed claims retry must
        # still end the request -- never fall on into the token-rejected retry, a refresh and a third
        # send -- and a failed refresh retry must end it with its own error only. Each send throws the
        # next queued record; a send past the queue answers, as a third attempt that got through would.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Invoke-MgGraphRequest {
                    $Next = if ($script:_ScrubCalls -lt @($script:_ScrubRecords).Count) { $script:_ScrubRecords[$script:_ScrubCalls] } else { $null }
                    $script:_ScrubCalls++
                    if ($null -eq $Next) { return @{ id = 'third-send' } }
                    $PSCmdlet.ThrowTerminatingError($Next)
                }
                Mock Initialize-OPIMAuth {}
                Mock Convert-GraphHttpException {
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('converted'), 'Converted', 'InvalidOperation', $null)
                }
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_ScrubRecords = $null
                $script:_ScrubCalls = $null
            }
        }

        It 'ends a request whose claims retry fails, with no refresh and no third send' {
            # A 401 that carries a claims challenge: the token-rejected test matches it too, so a
            # failed claims retry that fell on would refresh and send a third time.
            $Challenge = New-ScrubFixture -Status 401 -Content (
                '{"error":{"code":"InvalidAuthenticationToken",' +
                '"message":"...&claims=%7B%22access_token%22%3A%7B%22acrs%22%3A%7B%22essential%22%3Atrue%2C%20%22value%22%3A%22c1%22%7D%7D%7D"}}')
            $Retry = New-ScrubFixture -Status 403
            InModuleScope Omnicit.PIM -ArgumentList $Challenge.Record, $Retry.Record {
                param($First, $Second)
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com' }
                $script:_ScrubRecords = @($First, $Second)
                $script:_ScrubCalls = 0
            }
            $Run = Invoke-OutsideAnyTry -Script '$ErrorActionPreference = ''SilentlyContinue''; $R = Invoke-OPIMGraphRequest -Method POST -Uri ''v1.0/some/requests'' -Body @{}; $R'
            $Run.Output.Count | Should -Be 0 -Because 'a third send that got through would answer'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ClaimsChallenge -match 'acrs' }
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It -ParameterFilter { $ForceRefresh }
            Should -Invoke -ModuleName Omnicit.PIM Convert-GraphHttpException -Times 1 -Exactly -Scope It
            $Retry.Request.Headers.Contains('Authorization') | Should -BeFalse
        }

        It 'ends a request whose refresh retry fails with that retry''s error only' {
            # Falling on past the failed refresh retry would convert and throw the first failure as a
            # second error.
            $Rejected = New-ScrubFixture -Status 401 -Content '{"error":{"code":"InvalidAuthenticationToken","message":"Access token has expired."}}'
            $Retry = New-ScrubFixture -Status 403
            InModuleScope Omnicit.PIM -ArgumentList $Rejected.Record, $Retry.Record {
                param($First, $Second)
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com' }
                $script:_ScrubRecords = @($First, $Second)
                $script:_ScrubCalls = 0
            }
            $Run = Invoke-OutsideAnyTry -Script '$ErrorActionPreference = ''SilentlyContinue''; $R = Invoke-OPIMGraphRequest -Uri ''v1.0/me''; $R'
            $Run.Output.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ForceRefresh }
            Should -Invoke -ModuleName Omnicit.PIM Convert-GraphHttpException -Times 1 -Exactly -Scope It
            $Retry.Request.Headers.Contains('Authorization') | Should -BeFalse
        }
    }

    Context 'When an ACRS claims challenge is received and retry succeeds' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'test-tenant'; ClaimsSatisfied = $false }
                $script:_CallCount = 0
                Mock Invoke-MgGraphRequest {
                    $script:_CallCount++
                    if ($script:_CallCount -eq 1) {
                                # Embed claims challenge in the message -- the implementation's fallback path
                        $Ex = [System.Net.Http.HttpRequestException]::new(
                            'Bearer realm="00000003-0000-0000-c000-000000000000", claims="eyJhY3JzIjpbImMxIl19", error="insufficient_claims"'
                        )
                        throw $Ex
                    }
                    return @{ id = 'req-001'; status = 'Provisioned' }
                }
                Mock Initialize-OPIMAuth {}
                Mock Convert-GraphHttpException {
                    return [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('ACRS failed'),
                        'RoleAssignmentRequestAcrsValidationFailed',
                        [System.Management.Automation.ErrorCategory]::AuthenticationError,
                        $null
                    )
                }
            }
        }

        It 'calls Initialize-OPIMAuth with the claims challenge on retry' {
            InModuleScope Omnicit.PIM {
                try { Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/some/requests' -Body @{} } catch {}
                Should -Invoke Initialize-OPIMAuth -Times 1 -Scope It -ParameterFilter {
                    $ClaimsChallenge -ne $null
                }
            }
        }
    }

    Context 'When a PIM 400 body-form ACRS challenge is received and retry succeeds' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'test-tenant'; ClaimsSatisfied = $false }
                $script:_CallCount = 0
                Mock Invoke-MgGraphRequest {
                    $script:_CallCount++
                    if ($script:_CallCount -eq 1) {
                        # RoleAssignmentRequestAcrsValidationFailed: claims arrive URL-encoded
                        # in the error body as &claims=%7B...%7D (NOT base64, NOT quoted).
                        throw [System.Net.Http.HttpRequestException]::new(
                            '{"error":{"code":"RoleAssignmentRequestAcrsValidationFailed",' +
                            '"message":"...&claims=%7B%22access_token%22%3A%7B%22acrs%22%3A%7B%22essential%22%3Atrue%2C%20%22value%22%3A%22c1%22%7D%7D%7D"}}'
                        )
                    }
                    return @{ id = 'req-001'; status = 'Provisioned' }
                }
                Mock Initialize-OPIMAuth {}
            }
        }

        It 'decodes the URL-encoded claims and passes them to Initialize-OPIMAuth' {
            InModuleScope Omnicit.PIM {
                $Result = Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/some/requests' -Body @{}
                $Result.id | Should -Be 'req-001'
                Should -Invoke Initialize-OPIMAuth -Times 1 -Scope It -ParameterFilter {
                    $ClaimsChallenge -match 'access_token' -and
                    $ClaimsChallenge -match 'acrs' -and
                    $ClaimsChallenge -match 'c1'
                }
            }
        }
    }

    Context 'When the token is rejected as invalid/expired (no claims)' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'test-tenant'; ClaimsSatisfied = $false }
                $script:_CallCount = 0
                Mock Invoke-MgGraphRequest {
                    $script:_CallCount++
                    if ($script:_CallCount -eq 1) {
                        throw [System.Net.Http.HttpRequestException]::new(
                            '{"error":{"code":"InvalidAuthenticationToken","message":"Access token has expired."}}'
                        )
                    }
                    return @{ value = @(@{ id = 'after-refresh' }) }
                }
                Mock Initialize-OPIMAuth {}
            }
        }

        It 'forces a token refresh and retries once' {
            InModuleScope Omnicit.PIM {
                $Result = Invoke-OPIMGraphRequest -Uri 'v1.0/some/resource'
                $Result.value[0].id | Should -Be 'after-refresh'
                Should -Invoke Initialize-OPIMAuth -Times 1 -Scope It -ParameterFilter {
                    $ForceRefresh -eq $true
                }
            }
        }
    }

    Context 'When a device code session has its token rejected' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Invoke-MgGraphRequest {
                    $script:_CallCount++
                    if ($script:_CallCount -eq 1) {
                        throw [System.Net.Http.HttpRequestException]::new(
                            '{"error":{"code":"InvalidAuthenticationToken","message":"Access token has expired."}}'
                        )
                    }
                    return @{ value = @(@{ id = 'after-refresh' }) }
                }
                # Initialize-OPIMAuth runs for real here, so the retry is seen choosing its flow.
                Mock Get-OPIMMsalApplication { [PSCustomObject]@{} }
                Mock Invoke-OPIMDeviceCodeAuth {
                    [PSCustomObject]@{
                        AccessToken = $script:_OPIMTestToken
                        ExpiresOn   = [DateTimeOffset]::UtcNow.AddHours(1)
                        Account     = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    }
                }
                Mock Connect-MgGraph {}
                # The session the sign-in records, and the one the retry's session gate then reads.
                Mock Get-OPIMGraphSessionFingerprint { 'fp' }
            }
        }
        BeforeEach {
            # A session as Initialize-OPIMAuth writes it, and a new token for the same tenant.
            $Token = New-OPIMTestAccessToken -TenantId $SessionTenant
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; SessionTenant = $SessionTenant } {
                param($Token, $SessionTenant)
                $script:_CallCount = 0
                $script:_OPIMTestToken = $Token
                $script:_OPIMAuthState = @{
                    TenantId         = $SessionTenant
                    TokenTenantId    = $SessionTenant
                    AuthorityTenant  = $SessionTenant
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

        It 'signs in again with the device code flow before it retries' {
            InModuleScope Omnicit.PIM {
                $Result = Invoke-OPIMGraphRequest -Uri 'v1.0/some/resource'
                $Result.value[0].id | Should -Be 'after-refresh'
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It
            }
        }

        It 'refuses a new token for another tenant and sends no retry' {
            # OPIM-07 end to end: the refresh hands back a token for another tenant. Called inside a
            # try, as the pillar cmdlets call the wrapper.
            $Other = New-OPIMTestAccessToken -TenantId 'bbbbbbbb-0000-0000-0000-00000000000b'
            InModuleScope Omnicit.PIM -Parameters @{ Other = $Other } {
                param($Other)
                $script:_OPIMTestToken = $Other
                $Caught = $null
                try { Invoke-OPIMGraphRequest -Uri 'v1.0/some/resource' } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
                $script:_OPIMAuthState.TokenTenantId | Should -Be 'aaaaaaaa-0000-0000-0000-00000000000a'
            }
        }
    }

    Context 'When a device code session receives an ACRS claims challenge' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Invoke-MgGraphRequest {
                    $script:_CallCount++
                    if ($script:_CallCount -eq 1) {
                        throw [System.Net.Http.HttpRequestException]::new(
                            '{"error":{"code":"RoleAssignmentRequestAcrsValidationFailed",' +
                            '"message":"...&claims=%7B%22access_token%22%3A%7B%22acrs%22%3A%7B%22essential%22%3Atrue%2C%20%22value%22%3A%22c1%22%7D%7D%7D"}}'
                        )
                    }
                    return @{ id = 'req-001'; status = 'Provisioned' }
                }
                Mock Get-OPIMMsalApplication { [PSCustomObject]@{} }
                Mock Invoke-OPIMDeviceCodeAuth {
                    [PSCustomObject]@{
                        AccessToken = $script:_OPIMTestToken
                        ExpiresOn   = [DateTimeOffset]::UtcNow.AddHours(1)
                        Account     = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    }
                }
                Mock Connect-MgGraph {}
                # The session the step-up records, and the one the retry's session gate then reads.
                Mock Get-OPIMGraphSessionFingerprint { 'fp' }
            }
        }
        BeforeEach {
            $Token = New-OPIMTestAccessToken -TenantId $SessionTenant
            InModuleScope Omnicit.PIM -Parameters @{ Token = $Token; SessionTenant = $SessionTenant } {
                param($Token, $SessionTenant)
                $script:_CallCount = 0
                $script:_OPIMTestToken = $Token
                $script:_OPIMAuthState = @{
                    TenantId         = $SessionTenant
                    TokenTenantId    = $SessionTenant
                    AuthorityTenant  = $SessionTenant
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

        It 'steps up with the device code flow and the decoded claims' {
            InModuleScope Omnicit.PIM {
                $Result = Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/some/requests' -Body @{}
                $Result.id | Should -Be 'req-001'
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                    $ClaimsChallenge -match 'acrs' -and $ClaimsChallenge -match 'c1'
                }
            }
        }
    }

    Context 'When the Graph SDK session has changed' {
        # OPIM-09 (EntraRBAC A18). Get-OPIMGraphSessionState answers what the test sets in
        # $script:_OPIMTestSessionState; the Initialize-OPIMAuth mock of a retry test changes it, as a
        # Connect-MgGraph made elsewhere during the retry's sign-in would.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMGraphSessionState { $script:_OPIMTestSessionState }
                Mock Initialize-OPIMAuth { $script:_OPIMTestSessionState = 'Changed' }
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM -Parameters @{ SessionTenant = $SessionTenant } {
                param($SessionTenant)
                $script:_OPIMAuthState = @{ TenantId = $SessionTenant; GraphSessionFingerprint = 'mine' }
                $script:_OPIMTestSessionState = 'Changed'
                $script:_CallCount = 0
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_OPIMTestSessionState = $null
                $script:_CallCount = $null
            }
        }

        It 'refuses with GraphSessionChanged and sends nothing' {
            InModuleScope Omnicit.PIM -Parameters @{ SessionTenant = $SessionTenant } {
                param($SessionTenant)
                Mock Invoke-MgGraphRequest {}
                { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } | Should -Throw -ErrorId 'GraphSessionChanged*'
                $Caught = $null
                try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } catch { $Caught = $PSItem }
                $Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
                $Caught.TargetObject | Should -Be $SessionTenant
                Should -Invoke Invoke-MgGraphRequest -Times 0 -Scope It
                Should -Invoke Initialize-OPIMAuth -Times 0 -Scope It
            }
        }

        It 'throws GraphSessionChanged to a try under -ErrorAction SilentlyContinue and sends nothing' {
            # Inside Pester a terminating error always propagates (Pester runs every It in its own try,
            # measured 2026-10-07), so the child script block sits in a try as well; the static It below
            # holds the return that stops a caller outside any try.
            InModuleScope Omnicit.PIM {
                Mock Invoke-MgGraphRequest {}
                $Caught = $null
                try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' -ErrorAction SilentlyContinue } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'GraphSessionChanged*'
                $Caught = $null
                try {
                    & { $ErrorActionPreference = 'SilentlyContinue'; Invoke-OPIMGraphRequest -Uri 'v1.0/me' }
                } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'GraphSessionChanged*'
                Should -Invoke Invoke-MgGraphRequest -Times 0 -Scope It
            }
        }

        It 'refuses the retry after a token refresh when the session changed meanwhile' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMTestSessionState = 'Own'
                Mock Invoke-MgGraphRequest {
                    $script:_CallCount++
                    throw [System.Net.Http.HttpRequestException]::new(
                        '{"error":{"code":"InvalidAuthenticationToken","message":"Access token has expired."}}'
                    )
                }
                $Caught = $null
                try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'GraphSessionChanged*'
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ForceRefresh }
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Get-OPIMGraphSessionState -Times 2 -Exactly -Scope It
            }
        }

        It 'refuses the retry after a claims step-up when the session changed meanwhile' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMTestSessionState = 'Own'
                Mock Invoke-MgGraphRequest {
                    $script:_CallCount++
                    throw [System.Net.Http.HttpRequestException]::new(
                        '{"error":{"code":"RoleAssignmentRequestAcrsValidationFailed",' +
                        '"message":"...&claims=%7B%22access_token%22%3A%7B%22acrs%22%3A%7B%22essential%22%3Atrue%2C%20%22value%22%3A%22c1%22%7D%7D%7D"}}'
                    )
                }
                $Caught = $null
                try { Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/some/requests' -Body @{} } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'GraphSessionChanged*'
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ClaimsChallenge -match 'acrs' }
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Get-OPIMGraphSessionState -Times 2 -Exactly -Scope It
            }
        }

        It 'sends the request when the session is <State>' -ForEach @(
            @{ State = 'Own' }
            @{ State = 'Untracked' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMTestSessionState = $State
                Mock Invoke-MgGraphRequest { @{ id = 'me-001' } }
                (Invoke-OPIMGraphRequest -Uri 'v1.0/me').id | Should -Be 'me-001'
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
            }
        }

        It 'checks the session before each of its three requests, outside the try, and returns after the throw' {
            # Static check on the function as the module loaded it. Under -ErrorAction SilentlyContinue
            # with no try up the call stack a function carries on past its own throw (measured
            # 2026-10-07, PowerShell 7.6.6), so each gate is a throw followed by a return, and it stands
            # before the try that sends -- inside it, the catch would convert the refusal.
            $Ast = InModuleScope Omnicit.PIM { (Get-Command Invoke-OPIMGraphRequest).ScriptBlock.Ast }
            $Sends = @($Ast.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.CommandAst] -and
                        $Node.GetCommandName() -eq 'Invoke-MgGraphRequest'
                    }, $true))
            $Sends.Count | Should -Be 3 -Because 'the walk must reach the first attempt, the claims retry and the refresh retry'
            # OPIM-13: every send sits in the nested Invoke-OPIMGraphSingle, the one function a single
            # request and every page of a -All read go through, so the gates below stand before every
            # request the wrapper makes.
            foreach ($Send in $Sends) {
                $Owner = $Send.Parent
                while ($Owner -and $Owner -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $Owner = $Owner.Parent }
                $Owner.Name | Should -BeExactly 'Invoke-OPIMGraphSingle' -Because "the request at line $($Send.Extent.StartLineNumber) must sit in the nested request function"
            }
            $Single = @($Ast.Body.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                        $Node.Name -eq 'Invoke-OPIMGraphSingle'
                    }, $true))
            $Single.Count | Should -Be 1
            [object]::ReferenceEquals($Single[0].Parent.Parent, $Ast.Body) |
                Should -BeTrue -Because 'the request function is defined in the wrapper''s own body'
            $IsGate = {
                param($Statement)
                $Statement -is [System.Management.Automation.Language.IfStatementAst] -and
                $Statement.Clauses.Count -eq 1 -and -not $Statement.ElseClause -and
                $Statement.Clauses[0].Item1.Extent.Text -match 'Get-OPIMGraphSessionState' -and
                $Statement.Clauses[0].Item1.Extent.Text -match "-eq\s+'Changed'"
            }
            foreach ($Send in $Sends) {
                $Try = $Send.Parent
                while ($Try -and $Try -isnot [System.Management.Automation.Language.TryStatementAst]) { $Try = $Try.Parent }
                $Try | Should -Not -BeNullOrEmpty -Because "the request at line $($Send.Extent.StartLineNumber) sits in a try"
                $Block = $Try.Parent
                $Index = $Block.Statements.IndexOf($Try)
                $Gate = $null
                for ($I = $Index - 1; $I -ge 0; $I--) {
                    $Before = $Block.Statements[$I]
                    if ($Before -is [System.Management.Automation.Language.TryStatementAst]) { break }
                    if (& $IsGate $Before) { $Gate = $Before; break }
                }
                $Gate | Should -Not -BeNullOrEmpty -Because "a session gate must stand before the try of the request at line $($Send.Extent.StartLineNumber)"
                $Body = $Gate.Clauses[0].Item2.Statements
                $Body.Count | Should -Be 2
                $Body[0] | Should -BeOfType [System.Management.Automation.Language.ThrowStatementAst]
                $Body[0].Extent.Text | Should -Match 'New-OPIMGraphSessionChangedError'
                $Body[1] | Should -BeOfType [System.Management.Automation.Language.ReturnStatementAst]
            }
        }
    }

    Context 'When the calling command is latched' {
        # SEC (EntraRBAC A19). Get-OPIMSignInRefusal answers what the test sets in
        # $script:_OPIMTestRefusal; the Initialize-OPIMAuth mock of a retry test latches, as a retry
        # sign-in that is refused latches the wrapper's nested request function, Invoke-OPIMGraphSingle.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMGraphSessionState { $script:_OPIMTestSessionState }
                Mock Get-OPIMSignInRefusal { $script:_OPIMTestRefusal }
                Mock Initialize-OPIMAuth { $script:_OPIMTestRefusal = 'Invoke-OPIMGraphSingle' }
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM -Parameters @{ SessionTenant = $SessionTenant } {
                param($SessionTenant)
                $script:_OPIMAuthState = @{ TenantId = $SessionTenant; GraphSessionFingerprint = 'mine' }
                $script:_OPIMTestSessionState = 'Own'
                $script:_OPIMTestRefusal = 'Get-OPIMDirectoryRole'
                $script:_CallCount = 0
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_OPIMTestSessionState = $null
                $script:_OPIMTestRefusal = $null
                $script:_CallCount = $null
            }
        }

        It 'refuses with SignInRefused and sends nothing' {
            InModuleScope Omnicit.PIM {
                Mock Invoke-MgGraphRequest {}
                { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } | Should -Throw -ErrorId 'SignInRefused*'
                $Caught = $null
                try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } catch { $Caught = $PSItem }
                $Caught.TargetObject | Should -BeExactly 'Get-OPIMDirectoryRole'
                $Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
                Should -Invoke Invoke-MgGraphRequest -Times 0 -Scope It
                Should -Invoke Initialize-OPIMAuth -Times 0 -Scope It
            }
        }

        It 'refuses under -ErrorAction SilentlyContinue' {
            # Inside Pester a terminating error always propagates, so the calls sit in a try; the static
            # It below holds the return that stops a caller outside any try.
            InModuleScope Omnicit.PIM {
                Mock Invoke-MgGraphRequest {}
                $Caught = $null
                try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' -ErrorAction SilentlyContinue } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
                $Caught = $null
                try {
                    & { $ErrorActionPreference = 'SilentlyContinue'; Invoke-OPIMGraphRequest -Uri 'v1.0/me' }
                } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
                Should -Invoke Invoke-MgGraphRequest -Times 0 -Scope It
            }
        }

        It 'refuses the retry after a refresh whose sign-in was refused' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMTestRefusal = $null
                Mock Invoke-MgGraphRequest {
                    $script:_CallCount++
                    throw [System.Net.Http.HttpRequestException]::new(
                        '{"error":{"code":"InvalidAuthenticationToken","message":"Access token has expired."}}'
                    )
                }
                $Caught = $null
                try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
                $Caught.TargetObject | Should -BeExactly 'Invoke-OPIMGraphSingle'
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ForceRefresh }
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Get-OPIMSignInRefusal -Times 2 -Exactly -Scope It
            }
        }

        It 'refuses the retry after a claims step-up whose sign-in was refused' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMTestRefusal = $null
                Mock Invoke-MgGraphRequest {
                    $script:_CallCount++
                    throw [System.Net.Http.HttpRequestException]::new(
                        '{"error":{"code":"RoleAssignmentRequestAcrsValidationFailed",' +
                        '"message":"...&claims=%7B%22access_token%22%3A%7B%22acrs%22%3A%7B%22essential%22%3Atrue%2C%20%22value%22%3A%22c1%22%7D%7D%7D"}}'
                    )
                }
                $Caught = $null
                try { Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/some/requests' -Body @{} } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ClaimsChallenge -match 'acrs' }
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Get-OPIMSignInRefusal -Times 2 -Exactly -Scope It
            }
        }

        It 'reports GraphSessionChanged first when both apply' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMTestSessionState = 'Changed'
                Mock Invoke-MgGraphRequest {}
                { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } | Should -Throw -ErrorId 'GraphSessionChanged*'
                Should -Invoke Get-OPIMSignInRefusal -Times 0 -Scope It
                Should -Invoke Invoke-MgGraphRequest -Times 0 -Scope It
            }
        }

        It 'sends the request when no command is latched' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMTestRefusal = $null
                Mock Invoke-MgGraphRequest { @{ id = 'me-001' } }
                (Invoke-OPIMGraphRequest -Uri 'v1.0/me').id | Should -Be 'me-001'
                Should -Invoke Get-OPIMSignInRefusal -Times 1 -Exactly -Scope It
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
            }
        }

        It 'checks the latch before each of its three requests, after the session gate, outside the try, and returns after the throw' {
            # Static check on the function as the module loaded it, alongside the session gate check
            # above. Each latch gate is $SignInRefusal = Get-OPIMSignInRefusal and an if that throws
            # SignInRefused and returns; it stands between the session gate and the try that sends.
            $Ast = InModuleScope Omnicit.PIM { (Get-Command Invoke-OPIMGraphRequest).ScriptBlock.Ast }
            $Sends = @($Ast.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.CommandAst] -and
                        $Node.GetCommandName() -eq 'Invoke-MgGraphRequest'
                    }, $true))
            $Sends.Count | Should -Be 3 -Because 'the walk must reach the first attempt, the claims retry and the refresh retry'
            foreach ($Send in $Sends) {
                # OPIM-13: in the nested request function, the frame a refused retry sign-in latches.
                $Owner = $Send.Parent
                while ($Owner -and $Owner -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $Owner = $Owner.Parent }
                $Owner.Name | Should -BeExactly 'Invoke-OPIMGraphSingle' -Because "the latch gate of the request at line $($Send.Extent.StartLineNumber) must read the frame the retry's sign-in latched"
                $Try = $Send.Parent
                while ($Try -and $Try -isnot [System.Management.Automation.Language.TryStatementAst]) { $Try = $Try.Parent }
                $Block = $Try.Parent
                $Index = $Block.Statements.IndexOf($Try)
                $Index | Should -BeGreaterOrEqual 3 -Because "the request at line $($Send.Extent.StartLineNumber) needs a session gate and a latch gate before its try"
                $Gate = $Block.Statements[$Index - 1]
                $Read = $Block.Statements[$Index - 2]
                $Session = $Block.Statements[$Index - 3]
                $Read | Should -BeOfType [System.Management.Automation.Language.AssignmentStatementAst]
                $Read.Left.Extent.Text | Should -BeExactly '$SignInRefusal'
                $Read.Right.Extent.Text | Should -BeExactly 'Get-OPIMSignInRefusal'
                $Gate | Should -BeOfType [System.Management.Automation.Language.IfStatementAst]
                $Gate.Clauses.Count | Should -Be 1
                $Gate.ElseClause | Should -BeNullOrEmpty
                $Gate.Clauses[0].Item1.Extent.Text | Should -Match '\$null\s+-ne\s+\$SignInRefusal'
                $Body = $Gate.Clauses[0].Item2.Statements
                $Body.Count | Should -Be 2
                $Body[0] | Should -BeOfType [System.Management.Automation.Language.ThrowStatementAst]
                $Body[0].Extent.Text | Should -Match 'New-OPIMSignInRefusedError\s+-Command\s+\$SignInRefusal'
                $Body[1] | Should -BeOfType [System.Management.Automation.Language.ReturnStatementAst]
                # The session gate comes first, so a changed session is still GraphSessionChanged.
                $Session | Should -BeOfType [System.Management.Automation.Language.IfStatementAst]
                $Session.Clauses[0].Item1.Extent.Text | Should -Match 'Get-OPIMGraphSessionState'
            }
        }
    }

    Context 'When the sign-in of a retry is refused (real Initialize-OPIMAuth)' {
        # Ruling R-T4b. Initialize-OPIMAuth runs for real inside the token-rejected retry, as in the
        # device code context above, and the refresh hands back a token for another tenant. The latch
        # table is a recorder that keeps the name of every command it latches and releases.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Invoke-MgGraphRequest {
                    $script:_CallCount++
                    throw [System.Net.Http.HttpRequestException]::new(
                        '{"error":{"code":"InvalidAuthenticationToken","message":"Access token has expired."}}'
                    )
                }
                Mock Get-OPIMMsalApplication { [PSCustomObject]@{} }
                Mock Invoke-OPIMDeviceCodeAuth {
                    [PSCustomObject]@{
                        AccessToken = $script:_OPIMTestToken
                        ExpiresOn   = [DateTimeOffset]::UtcNow.AddHours(1)
                        Account     = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    }
                }
                Mock Connect-MgGraph {}
                Mock Get-OPIMGraphSessionFingerprint { 'fp' }
            }
        }
        BeforeEach {
            $Other = New-OPIMTestAccessToken -TenantId 'bbbbbbbb-0000-0000-0000-00000000000b'
            InModuleScope Omnicit.PIM -Parameters @{ Other = $Other; SessionTenant = $SessionTenant } {
                param($Other, $SessionTenant)
                $script:_CallCount = 0
                $script:_OPIMTestToken = $Other
                $script:_OPIMAuthState = @{
                    TenantId                = $SessionTenant
                    TokenTenantId           = $SessionTenant
                    AuthorityTenant         = $SessionTenant
                    Account                 = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    GraphTokenExpiry        = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied         = $false
                    DeviceCode              = $true
                    GraphSessionFingerprint = 'fp'
                }
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
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_OPIMTestToken = $null
                $script:_OPIMSignInLatch = $null
                $script:_CallCount = $null
            }
        }

        It 'latches the wrapper''s request function, keeps it latched and sends no retry' {
            # Inside Pester the error the caller sees is TenantMismatch: the retry's Initialize-OPIMAuth
            # raises it as a terminating error, and Pester's own try (and this test's) makes it propagate
            # out of the wrapper before the retry's gates run. Outside any try the wrapper carries on to
            # them, and the latch gate finds the frame of the wrapper's nested Invoke-OPIMGraphSingle,
            # which called Initialize-OPIMAuth and holds the retry's gates -- latched, as this test
            # records -- and throws SignInRefused; the mocked context above holds that gate.
            InModuleScope Omnicit.PIM {
                $Caught = $null
                try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
                ($script:_OPIMSignInLatch.Latched -join ', ') | Should -BeExactly 'Invoke-OPIMGraphSingle'
                $script:_OPIMSignInLatch.Released.Count | Should -Be 0
            }
        }
    }

    Context 'When -All reads a list of several pages' {
        # OPIM-13. Graph answers a list in pages, each but the last carrying @odata.nextLink. The mock
        # answers three pages by URI, and refuses any other URI, so a link that is rebuilt or lost
        # shows as a failed request.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Initialize-OPIMAuth {}
                Mock Invoke-MgGraphRequest {
                    param($Method, $Uri)
                    switch -CaseSensitive ($Uri) {
                        'v1.0/x' {
                            return @{ value = @(@{ id = '1' }); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/x?$skiptoken=2' }
                        }
                        'https://graph.microsoft.com/v1.0/x?$skiptoken=2' {
                            return @{ value = @(@{ id = '2' }); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/x?$skiptoken=3' }
                        }
                        'https://graph.microsoft.com/v1.0/x?$skiptoken=3' {
                            return @{ value = @(@{ id = '3' }) }
                        }
                        'v1.0/empty' {
                            return @{ value = @() }
                        }
                        'v1.0/single' {
                            return @{ value = @(@{ id = 'only' }) }
                        }
                    }
                    throw "The mock answers no request for $Uri."
                }
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'returns the items of every page' {
            InModuleScope Omnicit.PIM {
                $Result = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All
                $Result | Should -BeOfType ([hashtable])
                (@($Result.value) | ForEach-Object { $_.id }) -join ',' | Should -BeExactly '1,2,3'
            }
        }

        It 'follows the next link verbatim' {
            InModuleScope Omnicit.PIM {
                $null = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Uri -ceq 'https://graph.microsoft.com/v1.0/x?$skiptoken=2'
                }
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Uri -ceq 'https://graph.microsoft.com/v1.0/x?$skiptoken=3'
                }
            }
        }

        It 'requests each page once' {
            InModuleScope Omnicit.PIM {
                $null = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All
                Should -Invoke Invoke-MgGraphRequest -Times 3 -Exactly -Scope It
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Uri -ceq 'v1.0/x' }
            }
        }

        It 'returns an empty value for a list with no items' {
            InModuleScope Omnicit.PIM {
                $Result = Invoke-OPIMGraphRequest -Uri 'v1.0/empty' -All
                $Result | Should -BeOfType ([hashtable])
                $Result.ContainsKey('value') | Should -BeTrue
                @($Result.value).Count | Should -Be 0
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
            }
        }

        It 'stops at a page without a next link' {
            InModuleScope Omnicit.PIM {
                $Result = Invoke-OPIMGraphRequest -Uri 'v1.0/single' -All
                (@($Result.value) | ForEach-Object { $_.id }) -join ',' | Should -BeExactly 'only'
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
            }
        }

        It 'writes the page number and item count to the verbose stream, never the next link' {
            # Ruling R-T7a: a next link can carry a skip token, so verbose output names the page by its
            # number only.
            InModuleScope Omnicit.PIM {
                $Records = @(Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All -Verbose 4>&1 |
                        Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
                $Text = ($Records | ForEach-Object { $_.Message }) -join "`n"
                $Records.Count | Should -BeGreaterOrEqual 3
                $Text | Should -Match 'page 3'
                $Text | Should -Not -Match 'skiptoken'
                $Text | Should -Not -Match 'https?://'
                $Text | Should -Not -Match 'v1\.0/x'
            }
        }

        It 'sends one request without -All and ignores its next link' {
            InModuleScope Omnicit.PIM {
                $Result = Invoke-OPIMGraphRequest -Uri 'v1.0/x'
                (@($Result.value) | ForEach-Object { $_.id }) -join ',' | Should -BeExactly '1'
                $Result['@odata.nextLink'] | Should -BeExactly 'https://graph.microsoft.com/v1.0/x?$skiptoken=2'
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
            }
        }
    }

    Context 'When a later page fails' {
        # Page 1 answers with a next link; page 2 fails with a Graph 500, thrown as the SDK throws it:
        # a record pointing at a request message that carries an Authorization header.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Initialize-OPIMAuth {}
                Mock Invoke-MgGraphRequest {
                    param($Method, $Uri)
                    if ($Uri -ceq 'v1.0/x') {
                        return @{ value = @(@{ id = '1' }); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/x?$skiptoken=2' }
                    }
                    $PSCmdlet.ThrowTerminatingError($script:_OPIMTestPageFailure)
                }
            }
        }
        BeforeEach {
            $script:PageFailure = New-ScrubFixture -Status 500 -Content '{"error":{"code":"generalException","message":"An unexpected error occurred."}}'
            InModuleScope Omnicit.PIM -Parameters @{ Record = $script:PageFailure.Record } {
                param($Record)
                $script:_OPIMAuthState = $null
                $script:_OPIMTestPageFailure = $Record
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMTestPageFailure = $null }
        }

        It 'throws the page error as itself' {
            InModuleScope Omnicit.PIM {
                $Caught = $null
                try { $null = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All } catch { $Caught = $PSItem }
                $Caught | Should -Not -BeNullOrEmpty
                $Caught.FullyQualifiedErrorId | Should -BeExactly 'generalException'
                $Caught.Exception.Message | Should -BeExactly 'generalException: An unexpected error occurred.'
                $Caught.Exception.InnerException | Should -BeNullOrEmpty
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
            }
            $script:PageFailure.Request.Headers.Contains('Authorization') | Should -BeFalse -Because 'the failed page is scrubbed as a single request is'
        }

        It 'carries the items read before the failure as PartialValue' {
            InModuleScope Omnicit.PIM {
                $Caught = $null
                try { $null = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All } catch { $Caught = $PSItem }
                $Caught.Exception.PSObject.Properties['PartialValue'] | Should -Not -BeNullOrEmpty
                $Partial = $Caught.Exception.PartialValue
                , $Partial | Should -BeOfType ([object[]])
                $Partial.Count | Should -Be 1
                $Partial[0].id | Should -BeExactly '1'
            }
        }

        It 'carries the failed page''s link and number' {
            InModuleScope Omnicit.PIM {
                $Caught = $null
                try { $null = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All } catch { $Caught = $PSItem }
                $Caught.Exception.NextLink | Should -BeExactly 'https://graph.microsoft.com/v1.0/x?$skiptoken=2'
                $Caught.Exception.PageNumber | Should -Be 2
                $Caught.Exception.PageNumber | Should -BeOfType ([int])
            }
        }

        It 'returns nothing when a later page fails under -ErrorAction SilentlyContinue' {
            # Outside any try a throw inside a catch resumes after that try under SilentlyContinue; the
            # loop must then return nothing, never page 1 as if it were the whole list.
            $Run = Invoke-OutsideAnyTry -Script '$ErrorActionPreference = ''SilentlyContinue''; $R = Invoke-OPIMGraphRequest -Uri ''v1.0/x'' -All; $R'
            $Run.Output.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
            $Run = Invoke-OutsideAnyTry -Script '$R = Invoke-OPIMGraphRequest -Uri ''v1.0/x'' -All -ErrorAction SilentlyContinue; $R'
            $Run.Output.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 4 -Exactly -Scope It
        }
    }

    Context 'When the first page fails' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Initialize-OPIMAuth {}
                Mock Invoke-MgGraphRequest { $PSCmdlet.ThrowTerminatingError($script:_OPIMTestPageFailure) }
            }
        }
        BeforeEach {
            $Failure = New-ScrubFixture -Status 500 -Content '{"error":{"code":"generalException","message":"An unexpected error occurred."}}'
            InModuleScope Omnicit.PIM -Parameters @{ Record = $Failure.Record } {
                param($Record)
                $script:_OPIMAuthState = $null
                $script:_OPIMTestPageFailure = $Record
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMTestPageFailure = $null }
        }

        It 'throws with an empty PartialValue' {
            InModuleScope Omnicit.PIM {
                $Caught = $null
                try { $null = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeExactly 'generalException'
                $Caught.Exception.PSObject.Properties['PartialValue'] | Should -Not -BeNullOrEmpty
                , $Caught.Exception.PartialValue | Should -BeOfType ([object[]])
                $Caught.Exception.PartialValue.Count | Should -Be 0
                $Caught.Exception.NextLink | Should -BeExactly 'v1.0/x'
                $Caught.Exception.PageNumber | Should -Be 1
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
            }
        }
    }

    Context 'When a page comes back with no body' {
        # A later page with no body is a failed read, never the end of the list. Page 1 answers with
        # a next link and page 2 with nothing at all; a list whose first page has no body answers
        # nothing on its only page.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Initialize-OPIMAuth {}
                Mock Invoke-MgGraphRequest {
                    param($Method, $Uri)
                    if ($Uri -ceq 'v1.0/x') {
                        return @{ value = @(@{ id = '1' }); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/x?$skiptoken=2' }
                    }
                    return $null
                }
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'throws a failed read with the items read before it when a later page has no body' {
            InModuleScope Omnicit.PIM {
                $Caught = $null
                try { $null = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All } catch { $Caught = $PSItem }
                $Caught | Should -Not -BeNullOrEmpty -Because 'a later page with no body leaves the list incomplete'
                $Caught.Exception.Message | Should -BeExactly 'Page 2: Microsoft Graph returned no body for this page of the list, so the list is incomplete.'
                $Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidResult)
                # No error id: the record's id is only the name of the command that raised it
                # (measured 2026-10-07).
                $Caught.FullyQualifiedErrorId | Should -BeExactly 'Invoke-OPIMGraphRequest'
                $Caught.TargetObject | Should -BeNullOrEmpty
                (@($Caught.Exception.PartialValue) | ForEach-Object { $_.id }) -join ',' | Should -BeExactly '1'
                , $Caught.Exception.PartialValue | Should -BeOfType ([object[]])
                $Caught.Exception.NextLink | Should -BeExactly 'https://graph.microsoft.com/v1.0/x?$skiptoken=2'
                $Caught.Exception.PageNumber | Should -Be 2
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
            }
        }

        It 'returns nothing outside any try when a later page has no body' {
            $Run = Invoke-OutsideAnyTry -Script '$ErrorActionPreference = ''SilentlyContinue''; $R = Invoke-OPIMGraphRequest -Uri ''v1.0/x'' -All; $R'
            $Run.Output.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
            $Run = Invoke-OutsideAnyTry -Script '$R = Invoke-OPIMGraphRequest -Uri ''v1.0/x'' -All -ErrorAction SilentlyContinue; $R'
            $Run.Output.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 4 -Exactly -Scope It
        }

        It 'returns an empty value when the first page has no body' {
            InModuleScope Omnicit.PIM {
                $Result = Invoke-OPIMGraphRequest -Uri 'v1.0/blank' -All
                $Result | Should -BeOfType ([hashtable])
                $Result.ContainsKey('value') | Should -BeTrue
                @($Result.value).Count | Should -Be 0
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
            }
        }
    }

    Context 'When a next link names a host other than the first request''s' {
        # OPIM-46 (SEC). A next link is followed only when it is an absolute https URI on the host of
        # the first request: that host is the host of an absolute -Uri over https, else
        # graph.microsoft.com. Any other link is an error with no error id (category SecurityError)
        # and is never sent, since the request carries the session's bearer token. The mock answers
        # page n with the item id n and the n-th link of $script:_OPIMTestLinks (none past the end of
        # the array), and records every URI it is asked for, so a link that is followed by mistake
        # shows in the sent list and in the call count.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Initialize-OPIMAuth {}
                Mock Invoke-MgGraphRequest {
                    param($Method, $Uri)
                    $script:_OPIMTestSent.Add($Uri)
                    $Index = $script:_OPIMTestSent.Count
                    $Page = @{ value = @(@{ id = [string]$Index }) }
                    if ($Index -le @($script:_OPIMTestLinks).Count -and $script:_OPIMTestLinks[$Index - 1]) {
                        $Page['@odata.nextLink'] = $script:_OPIMTestLinks[$Index - 1]
                    }
                    return $Page
                }
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_OPIMTestSent = [System.Collections.Generic.List[string]]::new()
                $script:_OPIMTestLinks = @()
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMTestSent = $null
                $script:_OPIMTestLinks = $null
            }
        }

        It 'follows <Name>' -ForEach @(
            @{ Name = 'a link on graph.microsoft.com'; FirstUri = 'v1.0/x'; Links = @('https://graph.microsoft.com/v1.0/x?$skiptoken=2') }
            @{ Name = 'a link whose host differs only in letter case'; FirstUri = 'v1.0/x'; Links = @('https://GRAPH.microsoft.com/v1.0/x?$skiptoken=2') }
            @{ Name = 'a link on the host of an absolute first -Uri'; FirstUri = 'https://graph.microsoft.com/v1.0/x'; Links = @('https://graph.microsoft.com/v1.0/x?$skiptoken=2') }
            @{ Name = 'a link on the host of an absolute first -Uri on another host'; FirstUri = 'https://graph.example.com/v1.0/x'; Links = @('https://graph.example.com/v1.0/x?$skiptoken=2') }
            @{ Name = 'a graph.microsoft.com link when the first -Uri is not over https'; FirstUri = 'http://graph.example.com/v1.0/x'; Links = @('https://graph.microsoft.com/v1.0/x?$skiptoken=2') }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ FirstUri = $FirstUri; Links = $Links } {
                param($FirstUri, $Links)
                $script:_OPIMTestLinks = @($Links)
                $Result = Invoke-OPIMGraphRequest -Uri $FirstUri -All
                (@($Result.value) | ForEach-Object { $_.id }) -join ',' | Should -BeExactly '1,2'
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
                # The mock's -Uri is a [System.Uri], as the SDK's is, which lower-cases the host: the
                # link is compared by value, not by letter case.
                $script:_OPIMTestSent[0] | Should -Be $FirstUri
                $script:_OPIMTestSent[1] | Should -Be $Links[0]
            }
        }

        It 'refuses <Name> and sends nothing for it' -ForEach @(
            @{ Name = 'a link to another host'; FirstUri = 'v1.0/x'; Links = @('https://evil.example.com/v1.0/x?$skiptoken=2') }
            @{ Name = 'a link over http'; FirstUri = 'v1.0/x'; Links = @('http://graph.microsoft.com/v1.0/x?$skiptoken=2') }
            @{ Name = 'a relative link'; FirstUri = 'v1.0/x'; Links = @('v1.0/x?$skiptoken=2') }
            @{ Name = 'a link on a subdomain of an unrelated host that starts with the right name'; FirstUri = 'v1.0/x'; Links = @('https://graph.microsoft.com.evil.example.com/v1.0/x?$skiptoken=2') }
            @{ Name = 'a link whose user info names the right host'; FirstUri = 'v1.0/x'; Links = @('https://graph.microsoft.com@evil.example.com/v1.0/x?$skiptoken=2') }
            @{ Name = 'a link with another scheme'; FirstUri = 'v1.0/x'; Links = @('ftp://graph.microsoft.com/v1.0/x?$skiptoken=2') }
            @{ Name = 'a scheme-relative link'; FirstUri = 'v1.0/x'; Links = @('//evil.example.com/v1.0/x?$skiptoken=2') }
            @{ Name = 'a link that is no URI'; FirstUri = 'v1.0/x'; Links = @('not a uri $skiptoken=2') }
            @{ Name = 'a graph.microsoft.com link after an absolute first -Uri on another host'; FirstUri = 'https://graph.example.com/v1.0/x'; Links = @('https://graph.microsoft.com/v1.0/x?$skiptoken=2') }
            @{ Name = 'a link on the first -Uri host when that -Uri is not over https'; FirstUri = 'http://graph.example.com/v1.0/x'; Links = @('https://graph.example.com/v1.0/x?$skiptoken=2') }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ FirstUri = $FirstUri; Links = $Links } {
                param($FirstUri, $Links)
                $script:_OPIMTestLinks = @($Links)
                $Caught = $null
                try { $null = Invoke-OPIMGraphRequest -Uri $FirstUri -All } catch { $Caught = $PSItem }
                $Caught | Should -Not -BeNullOrEmpty -Because 'a link that is not followed leaves the list incomplete'
                $Caught.Exception.Message | Should -BeExactly 'Page 2: Microsoft Graph returned a next link that is not an https link on the host of the first request, so it was not followed and the list is incomplete.'
                $Caught.Exception.Message | Should -Not -Match 'evil|example|skiptoken|://|\.com'
                $Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::SecurityError)
                # No error id: the record's id is only the name of the command that raised it.
                $Caught.FullyQualifiedErrorId | Should -BeExactly 'Invoke-OPIMGraphRequest'
                $Caught.TargetObject | Should -BeNullOrEmpty
                (@($Caught.Exception.PartialValue) | ForEach-Object { $_.id }) -join ',' | Should -BeExactly '1'
                , $Caught.Exception.PartialValue | Should -BeOfType ([object[]])
                $Caught.Exception.NextLink | Should -BeExactly $Links[0]
                $Caught.Exception.PageNumber | Should -Be 2
                $Caught.Exception.PageNumber | Should -BeOfType ([int])
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                @($script:_OPIMTestSent).Count | Should -Be 1 -Because 'the link is never sent'
            }
        }

        It 'numbers the page that would have been read and keeps what was read before it' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMTestLinks = @(
                    'https://graph.microsoft.com/v1.0/x?$skiptoken=2'
                    'https://evil.example.com/v1.0/x?$skiptoken=3'
                )
                $Caught = $null
                try { $null = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All } catch { $Caught = $PSItem }
                $Caught.Exception.Message | Should -BeExactly 'Page 3: Microsoft Graph returned a next link that is not an https link on the host of the first request, so it was not followed and the list is incomplete.'
                $Caught.Exception.PageNumber | Should -Be 3
                (@($Caught.Exception.PartialValue) | ForEach-Object { $_.id }) -join ',' | Should -BeExactly '1,2'
                $Caught.Exception.NextLink | Should -BeExactly 'https://evil.example.com/v1.0/x?$skiptoken=3'
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
            }
        }

        It 'writes neither the link nor its host to the verbose stream' {
            # Outside any try, so the verbose records written before the refusal are not lost with the
            # terminating error (inside an It the throw would end the whole statement).
            InModuleScope Omnicit.PIM { $script:_OPIMTestLinks = @('https://evil.example.com/v1.0/x?$skiptoken=2') }
            $Run = Invoke-OutsideAnyTry -Script '$ErrorActionPreference = ''SilentlyContinue''; Invoke-OPIMGraphRequest -Uri ''v1.0/x'' -All -Verbose 4>&1'
            $Records = @($Run.Output | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
            $Text = ($Records | ForEach-Object { $_.Message }) -join "`n"
            $Records.Count | Should -BeGreaterOrEqual 1 -Because 'the page that was read is still reported'
            $Text | Should -Match 'page 1'
            $Text | Should -Not -Match 'evil|example|skiptoken'
        }

        It 'returns nothing outside any try when a link names another host' {
            # ThrowTerminatingError ends the function even under SilentlyContinue; the return after it
            # keeps the loop from ever handing back page 1 as if it were the whole list.
            InModuleScope Omnicit.PIM { $script:_OPIMTestLinks = @('https://evil.example.com/v1.0/x?$skiptoken=2') }
            $Run = Invoke-OutsideAnyTry -Script '$ErrorActionPreference = ''SilentlyContinue''; $R = Invoke-OPIMGraphRequest -Uri ''v1.0/x'' -All; $R'
            $Run.Output.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
            InModuleScope Omnicit.PIM { $script:_OPIMTestSent.Clear() }
            $Run = Invoke-OutsideAnyTry -Script '$R = Invoke-OPIMGraphRequest -Uri ''v1.0/x'' -All -ErrorAction SilentlyContinue; $R'
            $Run.Output.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
        }
    }

    Context 'When a gate refuses a later page' {
        # Every page passes the session gate and the latch gate, as a single request does. The gate
        # mocks answer 'Own' and nothing for page 1 and refuse from their second call on.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Initialize-OPIMAuth {}
                Mock Invoke-MgGraphRequest {
                    param($Method, $Uri)
                    $script:_OPIMTestSends++
                    if ($Uri -ceq 'v1.0/x') {
                        return @{ value = @(@{ id = '1' }); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/x?$skiptoken=2' }
                    }
                    return @{ value = @(@{ id = '2' }) }
                }
                Mock Get-OPIMGraphSessionState {
                    $script:_OPIMTestSessionReads++
                    if ($script:_OPIMTestFlip -eq 'session' -and $script:_OPIMTestSessionReads -ge 2) { 'Changed' } else { 'Own' }
                }
                Mock Get-OPIMSignInRefusal {
                    $script:_OPIMTestLatchReads++
                    if ($script:_OPIMTestFlip -eq 'latch' -and $script:_OPIMTestLatchReads -ge 2) { 'Get-OPIMDirectoryRole' }
                }
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM -Parameters @{ SessionTenant = $SessionTenant } {
                param($SessionTenant)
                $script:_OPIMAuthState = @{ TenantId = $SessionTenant; GraphSessionFingerprint = 'mine' }
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_OPIMTestFlip = $null
                $script:_OPIMTestSends = $null
                $script:_OPIMTestSessionReads = $null
                $script:_OPIMTestLatchReads = $null
            }
        }

        It 'refuses every page through the session and latch gates' {
            InModuleScope Omnicit.PIM {
                foreach ($Case in @(
                        @{ Flip = 'session'; ErrorId = 'GraphSessionChanged*' }
                        @{ Flip = 'latch'; ErrorId = 'SignInRefused*' }
                    )) {
                    $script:_OPIMTestFlip = $Case.Flip
                    $script:_OPIMTestSends = 0
                    $script:_OPIMTestSessionReads = 0
                    $script:_OPIMTestLatchReads = 0
                    $Caught = $null
                    try { $null = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All } catch { $Caught = $PSItem }
                    $Caught.FullyQualifiedErrorId | Should -BeLike $Case.ErrorId -Because "the $($Case.Flip) gate refuses page 2"
                    $script:_OPIMTestSends | Should -Be 1 -Because "the $($Case.Flip) gate sends nothing for page 2"
                    $Caught.Exception.PageNumber | Should -Be 2
                    @($Caught.Exception.PartialValue).Count | Should -Be 1
                }
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
            }
        }
    }
}
