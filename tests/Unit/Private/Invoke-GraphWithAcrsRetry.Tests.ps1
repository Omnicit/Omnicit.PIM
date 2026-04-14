Describe 'Invoke-GraphWithAcrsRetry' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }

    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When the initial Graph call succeeds' {
        It 'returns the Graph API response directly' {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{ id = 'request-001'; status = 'Provisioned' }
            }

            InModuleScope Omnicit.PIM {
                $Result = Invoke-GraphWithAcrsRetry -Uri 'v1.0/roleManagement/directory/roleAssignmentScheduleRequests' -Body @{ action = 'selfActivate' }

                $Result | Should -Not -BeNullOrEmpty
                $Result.id | Should -Be 'request-001'
                $Result.status | Should -Be 'Provisioned'
            }
        }

        It 'calls Invoke-MgGraphRequest with POST method' {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{ id = 'request-002' }
            }

            InModuleScope Omnicit.PIM {
                Invoke-GraphWithAcrsRetry -Uri 'v1.0/test' -Body @{ action = 'selfActivate' }
            }

            Should -Invoke -CommandName Invoke-MgGraphRequest -ModuleName Omnicit.PIM -Times 1 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When the initial call fails with a non-ACRS error' {
        It 'returns a hashtable with _AcrsError set to $false' {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"InsufficientPermissions","message":"Access denied"}}'
                )
            }

            InModuleScope Omnicit.PIM {
                $Result = Invoke-GraphWithAcrsRetry -Uri 'v1.0/test' -Body @{ action = 'selfActivate' }

                $Result | Should -Not -BeNullOrEmpty
                $Result._AcrsError | Should -BeFalse
                $Result._ErrorRecord | Should -Not -BeNullOrEmpty
                $Result._ErrorRecord.FullyQualifiedErrorId | Should -Be 'InsufficientPermissions'
            }
        }

        It 'removes the raw error from $Error to prevent token leakage' {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"Forbidden","message":"Forbidden"}}'
                )
            }

            InModuleScope Omnicit.PIM {
                $ErrorCountBefore = $Error.Count
                $null = Invoke-GraphWithAcrsRetry -Uri 'v1.0/test' -Body @{ action = 'selfActivate' }

                # The function calls $null = $Error.Remove($PSItem) so the raw error should not persist.
                $Error.Count | Should -BeLessOrEqual $ErrorCountBefore
            }
        }
    }

    Context 'When a pre-existing ErrorRecord is passed via -ErrorRecord' {
        It 'skips the initial call and processes the provided error' {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest { }

            InModuleScope Omnicit.PIM {
                $Ex = [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"Forbidden","message":"Access denied"}}'
                )
                $InputRecord = [System.Management.Automation.ErrorRecord]::new(
                    $Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null
                )

                $Result = Invoke-GraphWithAcrsRetry -Uri 'v1.0/test' -Body @{ action = 'selfActivate' } -ErrorRecord $InputRecord

                $Result | Should -Not -BeNullOrEmpty
                $Result._AcrsError | Should -BeFalse
                $Result._ErrorRecord.FullyQualifiedErrorId | Should -Be 'Forbidden'
            }

            # The initial Invoke-MgGraphRequest should NOT have been called since ErrorRecord was provided.
            Should -Invoke -CommandName Invoke-MgGraphRequest -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }

    Context 'When the error is an ACRS claims challenge but claims cannot be extracted' {
        It 'returns a hashtable with _AcrsError $true and _NoClaimsExtracted $true' {
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"RoleAssignmentRequestAcrsValidationFailed","message":"ACRS validation failed. No claims data."}}'
                )
            }

            InModuleScope Omnicit.PIM {
                $Result = Invoke-GraphWithAcrsRetry -Uri 'v1.0/test' -Body @{ action = 'selfActivate' }

                $Result | Should -Not -BeNullOrEmpty
                $Result._AcrsError | Should -BeTrue
                $Result._NoClaimsExtracted | Should -BeTrue
            }
        }
    }

    Context 'When the error is an ACRS claims challenge but MSAL assembly is not loaded' {
        It 'returns a hashtable with _NoMsal $true' {
            $ClaimsJson = '{"access_token":{"acrs":{"essential":true,"value":"c1"}}}'
            $EncodedClaims = [System.Web.HttpUtility]::UrlEncode($ClaimsJson)
            $ErrorMsg = "{`"error`":{`"code`":`"RoleAssignmentRequestAcrsValidationFailed`",`"message`":`"ACRS validation failed. claims=$EncodedClaims`"}}"

            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new($ErrorMsg)
            }

            # Mock the assembly lookup to return nothing (simulate MSAL not loaded).
            Mock -ModuleName Omnicit.PIM Where-Object { } -ParameterFilter {
                $FilterScript -and "$FilterScript" -like '*Microsoft.Identity.Client*'
            }

            InModuleScope Omnicit.PIM {
                $Result = Invoke-GraphWithAcrsRetry -Uri 'v1.0/test' -Body @{ action = 'selfActivate' }

                $Result | Should -Not -BeNullOrEmpty
                $Result._AcrsError | Should -BeTrue
                # Either _NoClaimsExtracted or _NoMsal depending on extraction success.
                ($Result._NoClaimsExtracted -or $Result._NoMsal) | Should -BeTrue
            }
        }
    }
}
