BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire

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
                        AccessToken = 'fake-graph-token'
                        ExpiresOn   = [DateTimeOffset]::UtcNow.AddHours(1)
                        Account     = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    }
                }
                Mock Connect-MgGraph {}
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM {
                $script:_CallCount = 0
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $false
                    DeviceCode       = $true
                }
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'signs in again with the device code flow before it retries' {
            InModuleScope Omnicit.PIM {
                $Result = Invoke-OPIMGraphRequest -Uri 'v1.0/some/resource'
                $Result.value[0].id | Should -Be 'after-refresh'
                Should -Invoke Invoke-OPIMDeviceCodeAuth -Times 1 -Exactly -Scope It
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
                        AccessToken = 'fake-graph-token'
                        ExpiresOn   = [DateTimeOffset]::UtcNow.AddHours(1)
                        Account     = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    }
                }
                Mock Connect-MgGraph {}
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM {
                $script:_CallCount = 0
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $false
                    DeviceCode       = $true
                }
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
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
}
