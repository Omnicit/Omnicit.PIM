Describe 'Invoke-OPIMGraphRequest' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

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

    Context 'When an ACRS claims challenge is received and retry succeeds' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'test-tenant'; ClaimsSatisfied = $false }
                $script:_CallCount = 0
                Mock Invoke-MgGraphRequest {
                    $script:_CallCount++
                    if ($script:_CallCount -eq 1) {
                                # Embed claims challenge in the message — the implementation's fallback path
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
}
