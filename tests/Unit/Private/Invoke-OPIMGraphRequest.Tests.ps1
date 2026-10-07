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

        It 'sends nothing under -ErrorAction SilentlyContinue' {
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
        # sign-in that is refused latches the wrapper itself.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMGraphSessionState { $script:_OPIMTestSessionState }
                Mock Get-OPIMSignInRefusal { $script:_OPIMTestRefusal }
                Mock Initialize-OPIMAuth { $script:_OPIMTestRefusal = 'Invoke-OPIMGraphRequest' }
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
                $Caught.TargetObject | Should -BeExactly 'Invoke-OPIMGraphRequest'
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

        It 'latches the wrapper itself, keeps it latched and sends no retry' {
            # Inside Pester the error the caller sees is TenantMismatch: the retry's Initialize-OPIMAuth
            # raises it as a terminating error, and Pester's own try (and this test's) makes it propagate
            # out of the wrapper before the retry's gates run. Outside any try the wrapper carries on to
            # them, and the latch gate finds the wrapper's own frame -- latched, as this test records --
            # and throws SignInRefused; the mocked context above holds that gate.
            InModuleScope Omnicit.PIM {
                $Caught = $null
                try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
                ($script:_OPIMSignInLatch.Latched -join ', ') | Should -BeExactly 'Invoke-OPIMGraphRequest'
                $script:_OPIMSignInLatch.Released.Count | Should -Be 0
            }
        }
    }
}
