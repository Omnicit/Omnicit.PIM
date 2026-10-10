BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OPIMTestToken.ps1"
    . "$PSScriptRoot/../TestHelpers/OPIMScrubFixture.ps1"

    # The tenant of the device code sessions below; a letter-repeat placeholder, not a version-4 id.
    $SessionTenant = 'aaaaaaaa-0000-0000-0000-00000000000a'

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

    # The Kiota form of a failed Graph request (OPIM-28, EntraRBAC #75). When Kiota's RetryHandler in
    # the Graph SDK's pipeline gives up, the SDK raises an AggregateException around a
    # Microsoft.Kiota.Abstractions.ApiException, which has no .Response member: its HTTP facts are
    # ResponseStatusCode and ResponseHeaders. The type comes from the Kiota assembly that ships with the
    # loaded Microsoft.Graph.Authentication, so a renamed member turns these tests red instead of
    # leaving the wrapper's read silently inert. Nothing here sends a request.
    $GraphModuleBase = (Get-Module Microsoft.Graph.Authentication | Select-Object -First 1).ModuleBase
    $KiotaDll = $null
    if ($GraphModuleBase) {
        $KiotaDll = Get-ChildItem -LiteralPath $GraphModuleBase -Recurse -File -Filter 'Microsoft.Kiota.Abstractions.dll' -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    $script:KiotaApiExceptionType = $null
    if ($KiotaDll) {
        $script:KiotaApiExceptionType = [System.Reflection.Assembly]::LoadFrom($KiotaDll.FullName).GetType('Microsoft.Kiota.Abstractions.ApiException')
    }

    # Builds the failure as the SDK raises it when its retry handler gives up:
    # AggregateException(ApiException). -NestingDepth 0 returns the ApiException itself.
    function New-KiotaFailure {
        param(
            [Parameter(Mandatory)][string]$Message,
            [int]$StatusCode = 0,
            [hashtable]$Header,
            [int]$NestingDepth = 1
        )
        $Api = [Activator]::CreateInstance($script:KiotaApiExceptionType, @($Message))
        if ($StatusCode) { $Api.ResponseStatusCode = $StatusCode }
        if ($Header) {
            $Headers = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.IEnumerable[string]]]::new()
            foreach ($Key in $Header.Keys) { $Headers[$Key] = [string[]]@($Header[$Key]) }
            $Api.ResponseHeaders = $Headers
        }
        $Wrapped = [System.Exception]$Api
        for ($Level = 0; $Level -lt $NestingDepth; $Level++) {
            $Wrapped = [System.AggregateException]::new(
                'Too many retries performed. More than 3 retries encountered while sending the request.',
                [System.Exception[]]@($Wrapped))
        }
        $Wrapped
    }

    # Builds the failure as Kiota's RetryHandler leaves it after several attempts: ONE ApiException per
    # attempt in the AggregateException, OLDEST first. Each -Attempt entry is
    # @{ StatusCode = <int>; Message = <string>; Header = <hashtable, optional> }.
    function New-KiotaAttempts {
        param([Parameter(Mandatory)][hashtable[]]$Attempt)
        $Recorded = foreach ($One in $Attempt) {
            $Params = @{ Message = $One.Message; StatusCode = $One.StatusCode; NestingDepth = 0 }
            if ($One.Header) { $Params.Header = $One.Header }
            New-KiotaFailure @Params
        }
        [System.AggregateException]::new(
            'Too many retries performed. More than 3 retries encountered while sending the request.',
            [System.Exception[]]@($Recorded))
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
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
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
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
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
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
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
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
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
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
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
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                    $ForceRefresh -eq $true
                }
            }
        }
    }

    Context 'When a 401 arrives in either form the Graph SDK raises (OPIM-28)' {
        # The status of a failure is read from the Kiota form (ResponseStatusCode, anywhere in the
        # exception chain) and from the .Response form (an HttpResponseException's response). The
        # messages below name none of the four token texts the wrapper also matches, so only the
        # status can start the refresh.
        BeforeAll {
            $script:KiotaRejectedMessage = 'HTTP request failed with status code: Unauthorized.{"error":{"code":"InvalidToken","message":"The presented access token is not from a trusted issuer."}}'
            InModuleScope Omnicit.PIM {
                Mock Initialize-OPIMAuth {}
                Mock Invoke-MgGraphRequest {
                    $script:_KiotaCalls++
                    if ($script:_KiotaCalls -le @($script:_KiotaQueue).Count) {
                        $Next = $script:_KiotaQueue[$script:_KiotaCalls - 1]
                        if ($Next -is [System.Management.Automation.ErrorRecord]) { $PSCmdlet.ThrowTerminatingError($Next) }
                        throw $Next
                    }
                    @{ value = @(@{ id = 'after-refresh' }) }
                }
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com' }
                $script:_KiotaCalls = 0
                $script:_KiotaQueue = @()
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_KiotaCalls = $null
                $script:_KiotaQueue = $null
            }
        }

        It 'pins the Kiota ApiException member contract the status read is written against' {
            $script:KiotaApiExceptionType | Should -Not -BeNullOrEmpty -Because 'Microsoft.Kiota.Abstractions.dll must be found under the loaded Microsoft.Graph.Authentication; without it nothing below proves anything'
            $Names = $script:KiotaApiExceptionType.GetProperties().Name
            $Names | Should -Contain 'ResponseStatusCode'
            $Names | Should -Contain 'ResponseHeaders'
            $Names | Should -Not -Contain 'Response'
            $script:KiotaApiExceptionType.GetProperty('ResponseStatusCode').PropertyType.FullName | Should -Be 'System.Int32'
            $script:KiotaApiExceptionType.GetProperty('ResponseHeaders').PropertyType.Name | Should -Be 'IDictionary`2'
        }

        It 'refreshes once and sends again on a 401 in the Kiota form' {
            $Rejected = New-KiotaFailure -StatusCode 401 -Message $script:KiotaRejectedMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Rejected) } {
                param($Queue)
                $script:_KiotaQueue = $Queue
                (Invoke-OPIMGraphRequest -Uri 'v1.0/me').value[0].id | Should -Be 'after-refresh'
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ForceRefresh }
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
            }
        }

        It 'reads the status of the Kiota form at a nesting depth of 10' {
            # AggregateException.InnerException IS InnerExceptions[0]; a walk that followed both would
            # enqueue every level twice and stop at its visit ceiling long before depth 10.
            $Rejected = New-KiotaFailure -StatusCode 401 -Message $script:KiotaRejectedMessage -NestingDepth 10
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Rejected) } {
                param($Queue)
                $script:_KiotaQueue = $Queue
                (Invoke-OPIMGraphRequest -Uri 'v1.0/me').value[0].id | Should -Be 'after-refresh'
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ForceRefresh }
            }
        }

        It 'refreshes once and sends again on a 401 in the .Response form' {
            $Rejected = New-ScrubFixture -Status 401 -Content '{"error":{"code":"InvalidToken","message":"The presented access token is not from a trusted issuer."}}'
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Rejected.Record) } {
                param($Queue)
                $script:_KiotaQueue = $Queue
                (Invoke-OPIMGraphRequest -Uri 'v1.0/me').value[0].id | Should -Be 'after-refresh'
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ForceRefresh }
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
            }
            $Rejected.Request.Headers.Contains('Authorization') | Should -BeFalse
        }

        It 'refreshes only once per request when the retry is rejected again' {
            $First = New-KiotaFailure -StatusCode 401 -Message $script:KiotaRejectedMessage
            $Second = New-KiotaFailure -StatusCode 401 -Message $script:KiotaRejectedMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($First, $Second) } {
                param($Queue)
                $script:_KiotaQueue = $Queue
                { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } | Should -Throw -ErrorId 'InvalidToken'
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ForceRefresh }
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
            }
        }

        It 'does not refresh a 403 in the Kiota form' {
            $Forbidden = New-KiotaFailure -StatusCode 403 -Message 'HTTP request failed with status code: Forbidden.{"error":{"code":"Forbidden","message":"Access denied."}}'
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Forbidden) } {
                param($Queue)
                $script:_KiotaQueue = $Queue
                { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } | Should -Throw -ErrorId 'Forbidden'
                Should -Invoke Initialize-OPIMAuth -Times 0 -Scope It
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
            }
        }

        It 'surfaces the Graph error when a chain member carries a non-numeric ResponseStatusCode' {
            # The status is read with -as [int]: a cast would throw on the failure path and replace
            # the Graph error with a conversion error.
            $Odd = [System.Exception]::new('{"error":{"code":"Forbidden","message":"Access denied."}}')
            Add-Member -InputObject $Odd -NotePropertyName ResponseStatusCode -NotePropertyValue 'not-a-number'
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Odd) } {
                param($Queue)
                $script:_KiotaQueue = $Queue
                { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } | Should -Throw -ErrorId 'Forbidden'
                Should -Invoke Initialize-OPIMAuth -Times 0 -Scope It
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
            }
        }

        It 'takes the claims step-up, not the refresh, for a claims challenge in the Kiota form' {
            # Depth 0: the claims text is read from the top-level message.
            $Challenge = New-KiotaFailure -StatusCode 401 -NestingDepth 0 -Message (
                'HTTP request failed with status code: Unauthorized. WWW-Authenticate: Bearer ' +
                'error="insufficient_claims", claims="eyJhY2Nlc3NfdG9rZW4iOnsiYWNycyI6eyJlc3NlbnRpYWwiOnRydWUsInZhbHVlIjoiYzEifX19"')
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Challenge) } {
                param($Queue)
                $script:_KiotaQueue = $Queue
                (Invoke-OPIMGraphRequest -Uri 'v1.0/me').value[0].id | Should -Be 'after-refresh'
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ClaimsChallenge -match 'acrs' }
                Should -Invoke Initialize-OPIMAuth -Times 0 -Scope It -ParameterFilter { $ForceRefresh }
            }
        }
    }

    Context 'When Microsoft Graph throttles a request (OPIM-28)' {
        # Each send throws the next queued failure, or -- when $script:_ThrottleForever is set --
        # that failure on every send; once the queue is spent a send answers. A send past 40 fails the
        # test instead of looping. Start-Sleep is mocked: the wrapper's waits are real sleeps.
        BeforeAll {
            $script:TooManyMessage = 'HTTP request failed with status code: TooManyRequests.{"error":{"code":"TooManyRequests","message":"Too many requests."}}'
            $script:UnavailableMessage = 'HTTP request failed with status code: ServiceUnavailable.{"error":{"code":"ServiceUnavailable","message":"Service unavailable."}}'
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                Mock Initialize-OPIMAuth {}
                Mock Invoke-MgGraphRequest {
                    $script:_ThrottleCalls++
                    if ($script:_ThrottleCalls -gt 40) { throw 'hang guard: the throttle loop did not end' }
                    $Next = $null
                    if ($null -ne $script:_ThrottleForever) {
                        $Next = $script:_ThrottleForever
                    } elseif ($script:_ThrottleCalls -le @($script:_ThrottleQueue).Count) {
                        $Next = $script:_ThrottleQueue[$script:_ThrottleCalls - 1]
                    }
                    if ($null -eq $Next) { return @{ value = @(@{ id = 'after-wait' }) } }
                    if ($Next -is [System.Management.Automation.ErrorRecord]) { $PSCmdlet.ThrowTerminatingError($Next) }
                    throw $Next
                }
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com' }
                $script:_ThrottleCalls = 0
                $script:_ThrottleQueue = @()
                $script:_ThrottleForever = $null
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_ThrottleCalls = $null
                $script:_ThrottleQueue = $null
                $script:_ThrottleForever = $null
            }
        }

        It 'waits the delta-seconds Retry-After of a 429 in the Kiota form and sends again' {
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '60' } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Throttle) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                (Invoke-OPIMGraphRequest -Uri 'v1.0/me').value[0].id | Should -Be 'after-wait'
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 60 }
            }
        }

        It 'waits the Retry-After of a 429 in the .Response form and scrubs every throttled attempt' {
            $First = New-ScrubFixture -Status 429 -Content '{"error":{"code":"TooManyRequests","message":"Too many requests."}}' -RetryAfter '7'
            $Second = New-ScrubFixture -Status 429 -Content '{"error":{"code":"TooManyRequests","message":"Too many requests."}}' -RetryAfter '7'
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($First.Record, $Second.Record) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                (Invoke-OPIMGraphRequest -Uri 'v1.0/me').value[0].id | Should -Be 'after-wait'
                Should -Invoke Invoke-MgGraphRequest -Times 3 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 2 -Exactly -Scope It -ParameterFilter { $Seconds -eq 7 }
            }
            $First.Request.Headers.Contains('Authorization') | Should -BeFalse
            $Second.Request.Headers.Contains('Authorization') | Should -BeFalse
        }

        It 'waits until an HTTP-date Retry-After' {
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = [DateTime]::UtcNow.AddSeconds(100).ToString('R') } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Throttle) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                $null = Invoke-OPIMGraphRequest -Uri 'v1.0/me'
                # A window: the date has one-second resolution and time passes before it is read.
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -ge 95 -and $Seconds -le 100 }
            }
        }

        It 'clamps an HTTP-date Retry-After already past up to one second' {
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = [DateTime]::UtcNow.AddMinutes(-10).ToString('R') } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Throttle) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                $null = Invoke-OPIMGraphRequest -Uri 'v1.0/me'
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 1 }
            }
        }

        It 'reads Retry-After case-insensitively' {
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'retry-after' = '11' } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Throttle) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                $null = Invoke-OPIMGraphRequest -Uri 'v1.0/me'
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 11 }
            }
        }

        It 'reads Retry-After deep in the Kiota exception chain' {
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '45' } -Message $script:TooManyMessage -NestingDepth 10
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Throttle) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                $null = Invoke-OPIMGraphRequest -Uri 'v1.0/me'
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 45 }
            }
        }

        It 'takes the Retry-After from the same exception as the status, not from another one' {
            # The status and its header are one response's facts: an inner exception that carries only
            # a Retry-After is no response, and its header is not borrowed for the outer 429. The
            # exponential fallback (1 s) applies, not the 17 s.
            $Inner = [System.Exception]::new($script:TooManyMessage)
            Add-Member -InputObject $Inner -NotePropertyName ResponseHeaders -NotePropertyValue @{ 'Retry-After' = '17' }
            $Outer = [System.Exception]::new($script:TooManyMessage, $Inner)
            Add-Member -InputObject $Outer -NotePropertyName ResponseStatusCode -NotePropertyValue 429
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Outer) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                $null = Invoke-OPIMGraphRequest -Uri 'v1.0/me'
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 1 }
            }
        }

        It 'waits 120 s, and does not throw, for an HTTP-date Retry-After in the year 9999' {
            # The seconds to such a date overflow Int32; a cast would throw out of the failure path.
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = 'Fri, 31 Dec 9999 23:59:59 GMT' } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Throttle) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                (Invoke-OPIMGraphRequest -Uri 'v1.0/me').value[0].id | Should -Be 'after-wait'
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 120 }
            }
        }

        It 'waits one second, and does not throw, for an HTTP-date Retry-After in the year 1900' {
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = 'Mon, 01 Jan 1900 00:00:00 GMT' } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Throttle) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                (Invoke-OPIMGraphRequest -Uri 'v1.0/me').value[0].id | Should -Be 'after-wait'
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 1 }
            }
        }

        # Kiota's RetryHandler records one exception per attempt, oldest first, and the SDK throws only
        # when every response was a 429, 503 or 504. The newest response decides; its Retry-After is its
        # own; a write is sent again only when every recorded response was a 429.
        It 'does not send a POST again when the newest recorded attempt was a 503' {
            $Failure = New-KiotaAttempts -Attempt @(
                @{ StatusCode = 429; Header = @{ 'Retry-After' = '3' }; Message = $script:TooManyMessage }
                @{ StatusCode = 503; Header = @{ 'Retry-After' = '5' }; Message = $script:UnavailableMessage }
            )
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Failure) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                { Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/some/requests' -Body @{ action = 'selfActivate' } } | Should -Throw
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 0 -Scope It
            }
        }

        It 'does not send a POST again when an earlier recorded attempt was a 503' {
            # The newest answer is a 429, but the 503 before it may have come after Graph acted.
            $Failure = New-KiotaAttempts -Attempt @(
                @{ StatusCode = 503; Header = @{ 'Retry-After' = '5' }; Message = $script:UnavailableMessage }
                @{ StatusCode = 429; Header = @{ 'Retry-After' = '3' }; Message = $script:TooManyMessage }
            )
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Failure) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                { Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/some/requests' -Body @{ action = 'selfActivate' } } | Should -Throw
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 0 -Scope It
            }
        }

        It 'does not send a POST again when an earlier recorded attempt was a 504' {
            # A 504 can come after Graph acted as well; only a chain of 429s lets a write go again.
            $Failure = New-KiotaAttempts -Attempt @(
                @{ StatusCode = 504; Header = @{ 'Retry-After' = '5' }; Message = 'HTTP request failed with status code: GatewayTimeout.{"error":{"code":"GatewayTimeout","message":"Gateway timeout."}}' }
                @{ StatusCode = 429; Header = @{ 'Retry-After' = '3' }; Message = $script:TooManyMessage }
            )
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Failure) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                { Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/some/requests' -Body @{ action = 'selfActivate' } } | Should -Throw
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 0 -Scope It
            }
        }

        It 'waits the Retry-After of the newest recorded attempt, not the oldest' {
            $Failure = New-KiotaAttempts -Attempt @(
                @{ StatusCode = 429; Header = @{ 'Retry-After' = '60' }; Message = $script:TooManyMessage }
                @{ StatusCode = 429; Header = @{ 'Retry-After' = '3' }; Message = $script:TooManyMessage }
            )
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Failure) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                (Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/some/requests' -Body @{ action = 'selfActivate' }).value[0].id | Should -Be 'after-wait'
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 3 }
            }
        }

        It 'sends a GET again after a newest 429 that follows a 503 without Retry-After' {
            $Failure = New-KiotaAttempts -Attempt @(
                @{ StatusCode = 503; Message = $script:UnavailableMessage }
                @{ StatusCode = 429; Header = @{ 'Retry-After' = '4' }; Message = $script:TooManyMessage }
            )
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Failure) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                (Invoke-OPIMGraphRequest -Uri 'v1.0/me').value[0].id | Should -Be 'after-wait'
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 4 }
            }
        }

        It 'does not borrow an older attempt''s Retry-After for a newest 503 that carries none' {
            $Failure = New-KiotaAttempts -Attempt @(
                @{ StatusCode = 429; Header = @{ 'Retry-After' = '60' }; Message = $script:TooManyMessage }
                @{ StatusCode = 503; Message = $script:UnavailableMessage }
            )
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Failure) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } | Should -Throw
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 0 -Scope It
            }
        }

        It 'falls back to exponential backoff when a 429 carries no Retry-After' {
            $First = New-KiotaFailure -StatusCode 429 -Message $script:TooManyMessage
            $Second = New-KiotaFailure -StatusCode 429 -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($First, $Second) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                $null = Invoke-OPIMGraphRequest -Uri 'v1.0/me'
                # 2^0 = 1, then 2^1 = 2.
                Should -Invoke Start-Sleep -Times 2 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 1 }
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 2 }
            }
        }

        It 'falls back to exponential backoff when Retry-After cannot be read, not to zero' {
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = 'soon' } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Throttle) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                $null = Invoke-OPIMGraphRequest -Uri 'v1.0/me'
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 1 }
            }
        }

        It 'falls back, and does not throw, when the header collection is of neither shape' {
            $Odd = [System.Exception]::new($script:TooManyMessage)
            Add-Member -InputObject $Odd -NotePropertyName ResponseStatusCode -NotePropertyValue 429
            Add-Member -InputObject $Odd -NotePropertyName ResponseHeaders -NotePropertyValue 'not-a-header-collection'
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Odd) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                (Invoke-OPIMGraphRequest -Uri 'v1.0/me').value[0].id | Should -Be 'after-wait'
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 1 }
            }
        }

        It 'clamps a Retry-After of 0 up to one second' {
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '0' } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Throttle) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                $null = Invoke-OPIMGraphRequest -Uri 'v1.0/me'
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 1 }
            }
        }

        It 'clamps a Retry-After above 120 seconds to 120' {
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '100000' } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Throttle) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                $null = Invoke-OPIMGraphRequest -Uri 'v1.0/me'
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 120 }
            }
        }

        It 'gives up when the per-REQUEST budget cannot cover the next wait, with the error of before' {
            # 120 s per wait (clamped from 300): 300 s buys two waits; the third 120 s does not fit
            # the 60 s left.
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '300' } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Throttle = $Throttle } {
                param($Throttle)
                $script:_ThrottleForever = $Throttle
                $Records = [System.Collections.Generic.List[object]]::new()
                $Caught = $null
                try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' -Verbose 4>&1 | ForEach-Object { $Records.Add($PSItem) } } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeExactly 'TooManyRequests'
                $Caught.Exception.Message | Should -BeLike 'TooManyRequests: *'
                Should -Invoke Start-Sleep -Times 2 -Exactly -Scope It
                Should -Invoke Invoke-MgGraphRequest -Times 3 -Exactly -Scope It
                $Text = (@($Records | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Message) -join "`n"
                $Text | Should -Match 'Throttled'
                $Text | Should -Match 'per-REQUEST budget remain\. Giving up\.'
            }
        }

        It 'gives up with the HTTP status in the message when the body names no Graph code' {
            $Throttle = New-ScrubFixture -Status 429 -Content '{}' -RetryAfter '300'
            InModuleScope Omnicit.PIM -Parameters @{ Throttle = $Throttle.Record } {
                param($Throttle)
                $script:_ThrottleForever = $Throttle
                $Caught = $null
                try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'HttpFail*'
                $Caught.Exception.Message | Should -BeLike 'HTTP 429: *'
                Should -Invoke Start-Sleep -Times 2 -Exactly -Scope It
            }
        }

        It 'spends the per-REQUEST budget to its last second' {
            # Three waits of 100 s spend exactly 300 s; the fourth answer asks for 1 s, which no
            # longer fits.
            $Hundred = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '100' } -Message $script:TooManyMessage
            $One = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '1' } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Hundred, $Hundred, $Hundred, $One) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } | Should -Throw -ErrorId 'TooManyRequests'
                Should -Invoke Start-Sleep -Times 3 -Exactly -Scope It
                Should -Invoke Invoke-MgGraphRequest -Times 4 -Exactly -Scope It
            }
        }

        It 'stops at the hard cap of 10 retries when Retry-After stays small' {
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '1' } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Throttle = $Throttle } {
                param($Throttle)
                $script:_ThrottleForever = $Throttle
                $Records = [System.Collections.Generic.List[object]]::new()
                $Caught = $null
                try { Invoke-OPIMGraphRequest -Uri 'v1.0/me' -Verbose 4>&1 | ForEach-Object { $Records.Add($PSItem) } } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeExactly 'TooManyRequests'
                Should -Invoke Start-Sleep -Times 10 -Exactly -Scope It
                Should -Invoke Invoke-MgGraphRequest -Times 11 -Exactly -Scope It
                $Text = (@($Records | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Message) -join "`n"
                $Text | Should -Match 'Reached the hard cap of 10 throttle retries'
            }
        }

        It 'waits out a 503 that carries Retry-After on a read' {
            $Unavailable = New-KiotaFailure -StatusCode 503 -Header @{ 'Retry-After' = '5' } -Message $script:UnavailableMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Unavailable) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                (Invoke-OPIMGraphRequest -Uri 'v1.0/me').value[0].id | Should -Be 'after-wait'
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 5 }
            }
        }

        It 'does not wait out a 503 without Retry-After' {
            $Unavailable = New-KiotaFailure -StatusCode 503 -Message $script:UnavailableMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Unavailable) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } | Should -Throw -ErrorId 'ServiceUnavailable'
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 0 -Scope It
            }
        }

        It 'does not send a <Method> again after a 503, even with Retry-After' -ForEach @(
            @{ Method = 'POST' }
            @{ Method = 'PATCH' }
            @{ Method = 'DELETE' }
        ) {
            # A 503 can come after Graph carried a write out; sending an activation again could make a
            # second one. Only a 429, which Graph returns before it acts, is sent again.
            $Unavailable = New-KiotaFailure -StatusCode 503 -Header @{ 'Retry-After' = '5' } -Message $script:UnavailableMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Unavailable); Method = $Method } {
                param($Queue, $Method)
                $script:_ThrottleQueue = $Queue
                { Invoke-OPIMGraphRequest -Method $Method -Uri 'v1.0/some/requests' -Body @{ action = 'selfActivate' } } | Should -Throw -ErrorId 'ServiceUnavailable'
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 0 -Scope It
            }
        }

        It 'sends a POST again after a 429' {
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '3' } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Throttle) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                (Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/some/requests' -Body @{ action = 'selfActivate' }).value[0].id | Should -Be 'after-wait'
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 3 }
            }
        }

        It 'does not wait out an ordinary failure such as 403, even with Retry-After' {
            $Forbidden = New-KiotaFailure -StatusCode 403 -Header @{ 'Retry-After' = '30' } -Message 'HTTP request failed with status code: Forbidden.{"error":{"code":"Forbidden","message":"Access denied."}}'
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Forbidden) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } | Should -Throw -ErrorId 'Forbidden'
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 0 -Scope It
            }
        }

        It 'waits out a throttle, then refreshes a rejected token once and sends again' {
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '3' } -Message $script:TooManyMessage
            $Rejected = New-KiotaFailure -StatusCode 401 -Message 'HTTP request failed with status code: Unauthorized.{"error":{"code":"InvalidToken","message":"The token was rejected."}}'
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Throttle, $Rejected) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                (Invoke-OPIMGraphRequest -Uri 'v1.0/me').value[0].id | Should -Be 'after-wait'
                Should -Invoke Invoke-MgGraphRequest -Times 3 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ForceRefresh }
            }
        }

        It 'ends the request without waiting when the retry after a refresh is throttled' {
            # Review Focus 3: the retries after a refresh and a step-up are single sends, as before.
            $Rejected = New-KiotaFailure -StatusCode 401 -Message 'HTTP request failed with status code: Unauthorized.{"error":{"code":"InvalidToken","message":"The token was rejected."}}'
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '3' } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Rejected, $Throttle) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } | Should -Throw -ErrorId 'TooManyRequests'
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 0 -Scope It
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ForceRefresh }
            }
        }

        It 'runs the session and latch gates before every throttled retry' {
            $First = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '2' } -Message $script:TooManyMessage
            $Second = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '2' } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($First, $Second) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                Mock Get-OPIMGraphSessionState { 'Own' }
                Mock Get-OPIMSignInRefusal { $null }
                $null = Invoke-OPIMGraphRequest -Uri 'v1.0/me'
                Should -Invoke Invoke-MgGraphRequest -Times 3 -Exactly -Scope It
                Should -Invoke Get-OPIMGraphSessionState -Times 3 -Exactly -Scope It
                Should -Invoke Get-OPIMSignInRefusal -Times 3 -Exactly -Scope It
            }
        }

        It 'refuses the throttled retry when the session changed during the wait' {
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '2' } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Throttle) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                $script:_GateReads = 0
                Mock Get-OPIMGraphSessionState { $script:_GateReads++; if ($script:_GateReads -eq 1) { 'Own' } else { 'Changed' } }
                { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } | Should -Throw -ErrorId 'GraphSessionChanged*'
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It
                $script:_GateReads = $null
            }
        }

        It 'refuses the throttled retry when the command was latched during the wait' {
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '2' } -Message $script:TooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Queue = @($Throttle) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                $script:_GateReads = 0
                Mock Get-OPIMSignInRefusal { $script:_GateReads++; if ($script:_GateReads -eq 1) { $null } else { 'Get-OPIMDirectoryRole' } }
                { Invoke-OPIMGraphRequest -Uri 'v1.0/me' } | Should -Throw -ErrorId 'SignInRefused*'
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                $script:_GateReads = $null
            }
        }

        It 'writes one verbose line per retry with the status, the wait, its source and the budgets, and never a header' {
            $First = New-KiotaFailure -StatusCode 429 -Message $script:TooManyMessage -Header @{
                'Retry-After'       = '30'
                'Authorization'     = ('Bearer ' + ('x' * 20) + 'NOT-A-REAL-TOKEN-MUST-NOT-BE-LOGGED')
                'client-request-id' = 'correlation-MUST-NOT-BE-LOGGED'
            }
            $Second = New-KiotaFailure -StatusCode 429 -Message $script:TooManyMessage
            $Verbose = InModuleScope Omnicit.PIM -Parameters @{ Queue = @($First, $Second) } {
                param($Queue)
                $script:_ThrottleQueue = $Queue
                (Invoke-OPIMGraphRequest -Uri 'v1.0/me' -Verbose 4>&1) | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            }
            $Lines = @($Verbose.Message | Where-Object { $_ -match 'Throttled' })
            $Lines.Count | Should -Be 2
            $Lines[0] | Should -BeExactly '[Invoke-OPIMGraphRequest] Throttled (status=429). Waiting 30 s (server-directed) before retry 1; 270 s of per-REQUEST and 870 s of per-CALL budget remain.'
            $Lines[1] | Should -Match 'Waiting 2 s \(exponential fallback\) before retry 2; 268 s of per-REQUEST and 868 s of per-CALL budget remain\.'
            $Text = $Verbose.Message -join "`n"
            $Text | Should -Not -Match 'MUST-NOT-BE-LOGGED'
            $Text | Should -Not -Match '(?i)bearer|authorization'
            $Text | Should -Not -Match 'v1\.0/me'
        }
    }

    Context 'When Microsoft Graph throttles the pages of -All (OPIM-28)' {
        BeforeAll {
            $script:PagedTooManyMessage = 'HTTP request failed with status code: TooManyRequests.{"error":{"code":"TooManyRequests","message":"Too many requests."}}'
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                Mock Initialize-OPIMAuth {}
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com' }
                $script:_PagedCalls = 0
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $script:_PagedCalls = $null
                $script:_PagedThrottle = $null
            }
        }

        It 'gives each page its own per-REQUEST budget' {
            # Two pages, each throttled twice for 120 s (240 s each). One budget shared by both pages
            # would refuse page 2's first wait; a budget per page allows all four.
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '120' } -Message $script:PagedTooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Throttle = $Throttle } {
                param($Throttle)
                $script:_PagedThrottle = $Throttle
                Mock Invoke-MgGraphRequest {
                    $script:_PagedCalls++
                    if ($script:_PagedCalls -gt 40) { throw 'hang guard: the throttle loop did not end' }
                    if ($script:_PagedCalls -in 1, 2, 4, 5) { throw $script:_PagedThrottle }
                    if ($script:_PagedCalls -eq 3) { return @{ value = @(@{ id = 'a' }); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/x?$skiptoken=2' } }
                    @{ value = @(@{ id = 'b' }) }
                }
                $Result = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All
                @($Result.value | ForEach-Object { $_.id }) | Should -Be @('a', 'b')
                Should -Invoke Start-Sleep -Times 4 -Exactly -Scope It -ParameterFilter { $Seconds -eq 120 }
                Should -Invoke Invoke-MgGraphRequest -Times 6 -Exactly -Scope It
            }
        }

        It 'ends a throttled -All read at the per-CALL deadline and returns no shorter list' {
            # Each page is throttled once for 120 s and then answers with a link of its own. The
            # 900 s deadline fits 7 waits (840 s); the 8th does not, so the whole call fails, with the
            # 7 pages read before it as PartialValue.
            $Throttle = New-KiotaFailure -StatusCode 429 -Header @{ 'Retry-After' = '120' } -Message $script:PagedTooManyMessage
            InModuleScope Omnicit.PIM -Parameters @{ Throttle = $Throttle } {
                param($Throttle)
                $script:_PagedThrottle = $Throttle
                Mock Invoke-MgGraphRequest {
                    $script:_PagedCalls++
                    if ($script:_PagedCalls -gt 40) { throw 'hang guard: the per-CALL deadline did not end the walk' }
                    if ($script:_PagedCalls % 2 -eq 1) { throw $script:_PagedThrottle }
                    @{ value = @(@{ id = "p$($script:_PagedCalls)" }); '@odata.nextLink' = "https://graph.microsoft.com/v1.0/x?`$skiptoken=$($script:_PagedCalls)" }
                }
                $Result = $null
                $Caught = $null
                $Records = [System.Collections.Generic.List[object]]::new()
                try { $Result = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All -Verbose 4>&1 | ForEach-Object { $Records.Add($PSItem) } } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeLike 'TooManyRequests*'
                @($Records | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
                Should -Invoke Start-Sleep -Times 7 -Exactly -Scope It
                Should -Invoke Invoke-MgGraphRequest -Times 15 -Exactly -Scope It
                @($Caught.Exception.PartialValue).Count | Should -Be 7
                $Caught.Exception.PageNumber | Should -Be 8
                $Text = (@($Records | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Message) -join "`n"
                $Text | Should -Match 'per-CALL budget remain\. Giving up\.'
                $Text | Should -Not -Match 'skiptoken'
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

        It 'follows a next link on the Graph host of the session''s cloud for a relative -Uri: <Name>' -ForEach @(
            @{ Name = 'Global (the baseline; the other rows and the refusal test tell the clouds apart)'; Cloud = 'Global'; Link = 'https://graph.microsoft.com/v1.0/x?$skiptoken=2' }
            @{ Name = 'USGov'; Cloud = 'USGov'; Link = 'https://graph.microsoft.us/v1.0/x?$skiptoken=2' }
            @{ Name = 'USGovDoD'; Cloud = 'USGovDoD'; Link = 'https://dod-graph.microsoft.us/v1.0/x?$skiptoken=2' }
            @{ Name = 'China'; Cloud = 'China'; Link = 'https://microsoftgraph.chinacloudapi.cn/v1.0/x?$skiptoken=2' }
            @{ Name = 'USGov, link host in another letter case'; Cloud = 'USGov'; Link = 'https://GRAPH.microsoft.us/v1.0/x?$skiptoken=2' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Cloud = $Cloud; Link = $Link } {
                param($Cloud, $Link)
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; Environment = $Cloud }
                $script:_OPIMTestLinks = @($Link)
                $Result = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All
                (@($Result.value) | ForEach-Object { $_.id }) -join ',' | Should -BeExactly '1,2'
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
                $script:_OPIMTestSent[1] | Should -Be $Link
            }
        }

        It 'refuses <Name> for a relative -Uri and sends nothing for it' -ForEach @(
            @{ Name = 'a link to the global Graph host in a USGov session'; Cloud = 'USGov'; Link = 'https://graph.microsoft.com/v1.0/x?$skiptoken=2' }
            @{ Name = 'a link to a USGov Graph host in a Global session'; Cloud = 'Global'; Link = 'https://graph.microsoft.us/v1.0/x?$skiptoken=2' }
            @{ Name = 'a link to the USGov Graph host in a USGovDoD session'; Cloud = 'USGovDoD'; Link = 'https://graph.microsoft.us/v1.0/x?$skiptoken=2' }
            @{ Name = 'a link to the USGovDoD Graph host in a USGov session'; Cloud = 'USGov'; Link = 'https://dod-graph.microsoft.us/v1.0/x?$skiptoken=2' }
            @{ Name = 'a link to the global Graph host in a China session'; Cloud = 'China'; Link = 'https://graph.microsoft.com/v1.0/x?$skiptoken=2' }
            @{ Name = 'a link to a lookalike of the USGov Graph host'; Cloud = 'USGov'; Link = 'https://graph.microsoft.us.evil.example.com/v1.0/x?$skiptoken=2' }
            @{ Name = 'a USGov link over http'; Cloud = 'USGov'; Link = 'http://graph.microsoft.us/v1.0/x?$skiptoken=2' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Cloud = $Cloud; Link = $Link } {
                param($Cloud, $Link)
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; Environment = $Cloud }
                $script:_OPIMTestLinks = @($Link)
                $Caught = $null
                try { $null = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All } catch { $Caught = $PSItem }
                $Caught | Should -Not -BeNullOrEmpty -Because 'a link that is not followed leaves the list incomplete'
                $Caught.Exception.Message | Should -BeExactly 'Page 2: Microsoft Graph returned a next link that is not an https link on the host of the first request, so it was not followed and the list is incomplete.'
                $Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::SecurityError)
                $Caught.Exception.NextLink | Should -BeExactly $Link
                $Caught.Exception.PageNumber | Should -Be 2
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
                @($script:_OPIMTestSent).Count | Should -Be 1 -Because 'the link is never sent'
            }
        }

        It 'keeps graph.microsoft.com for a session that records no cloud: <Name>' -ForEach @(
            @{ Name = 'no state'; State = $null }
            @{ Name = 'a state without an Environment key'; State = @{ TenantId = 'contoso.onmicrosoft.com' } }
            @{ Name = 'a state with an empty Environment'; State = @{ TenantId = 'contoso.onmicrosoft.com'; Environment = '' } }
            @{ Name = 'a state that is not a dictionary'; State = 'not a state' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                $script:_OPIMTestLinks = @('https://graph.microsoft.com/v1.0/x?$skiptoken=2')
                $Result = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All
                (@($Result.value) | ForEach-Object { $_.id }) -join ',' | Should -BeExactly '1,2'
                Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
            }
        }

        It 'refuses a USGov link for a session that records no cloud' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com' }
                $script:_OPIMTestLinks = @('https://graph.microsoft.us/v1.0/x?$skiptoken=2')
                $Caught = $null
                try { $null = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All } catch { $Caught = $PSItem }
                $Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::SecurityError)
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -Scope It
            }
        }

        It 'takes the host of an absolute -Uri over the session''s cloud' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; Environment = 'USGov' }
                $script:_OPIMTestLinks = @('https://graph.example.com/v1.0/x?$skiptoken=2')
                $Result = Invoke-OPIMGraphRequest -Uri 'https://graph.example.com/v1.0/x' -All
                (@($Result.value) | ForEach-Object { $_.id }) -join ',' | Should -BeExactly '1,2'

                # The session's cloud does not widen the set of hosts: its own Graph host is another host.
                $script:_OPIMTestSent.Clear()
                $script:_OPIMTestLinks = @('https://graph.microsoft.us/v1.0/x?$skiptoken=2')
                $Caught = $null
                try { $null = Invoke-OPIMGraphRequest -Uri 'https://graph.example.com/v1.0/x' -All } catch { $Caught = $PSItem }
                $Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::SecurityError)
                @($script:_OPIMTestSent).Count | Should -Be 1
            }
        }

        It 'sends nothing and never falls back to the global host when the state records a cloud outside the table' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; Environment = 'Germany' }
                $script:_OPIMTestLinks = @('https://graph.microsoft.com/v1.0/x?$skiptoken=2')
                $Caught = $null
                try { $null = Invoke-OPIMGraphRequest -Uri 'v1.0/x' -All } catch { $Caught = $PSItem }
                $Caught | Should -Not -BeNullOrEmpty
                $Caught.Exception.Message | Should -Match "no endpoint table entry for the cloud 'Germany'"
                Should -Invoke Invoke-MgGraphRequest -Times 0 -Scope It
                @($script:_OPIMTestSent).Count | Should -Be 0
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
