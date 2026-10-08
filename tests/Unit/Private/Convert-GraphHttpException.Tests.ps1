BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire

    # A failed Graph read as the SDK leaves it: a request message carrying an Authorization header,
    # the response pointing back at it, and an HttpResponseException holding the response. The
    # token is built at runtime and says what it is, so no token-shaped literal sits in this file.
    function New-ScrubFixture {
        param([int]$Status = 403)
        $Token = 'Bearer ' + ('x' * 40) + 'NOT-A-REAL-TOKEN'
        $Request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, 'https://graph.microsoft.com/v1.0/me')
        $null = $Request.Headers.TryAddWithoutValidation('Authorization', $Token)
        $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Status)
        $Response.RequestMessage = $Request
        $Response.Content = [System.Net.Http.StringContent]::new('{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges."}}')
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

Describe 'Convert-GraphHttpException' {
    Context 'When the exception message contains a parseable JSON error body (message fallback path)' {
        It 'returns a new ErrorRecord with the parsed error code as FullyQualifiedErrorId' {
            InModuleScope Omnicit.PIM {
                $Ex          = [System.Net.Http.HttpRequestException]::new('{"error":{"code":"InsufficientPermissions","message":"Access denied"}}')
                $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                $Result.FullyQualifiedErrorId | Should -Be 'InsufficientPermissions'
            }
        }

        It 'returns a new ErrorRecord whose exception message is formatted as "code: message"' {
            InModuleScope Omnicit.PIM {
                $Ex          = [System.Net.Http.HttpRequestException]::new('{"error":{"code":"InsufficientPermissions","message":"Access denied"}}')
                $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                $Result.Exception.Message | Should -Be 'InsufficientPermissions: Access denied'
            }
        }

        It 'does not chain the original exception' {
            InModuleScope Omnicit.PIM {
                $Ex          = [System.Net.Http.HttpRequestException]::new('{"error":{"code":"InsufficientPermissions","message":"Access denied"}}')
                $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                $Result.Exception.InnerException | Should -BeNullOrEmpty
            }
        }

        It 'sets ErrorDetails on the returned ErrorRecord' {
            InModuleScope Omnicit.PIM {
                $Ex          = [System.Net.Http.HttpRequestException]::new('{"error":{"code":"InsufficientPermissions","message":"Access denied"}}')
                $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                $Result.ErrorDetails | Should -Not -BeNullOrEmpty
                $Result.ErrorDetails.Message | Should -Be 'InsufficientPermissions: Access denied'
            }
        }

        It 'sets the category to OperationStopped on the returned ErrorRecord' {
            InModuleScope Omnicit.PIM {
                $Ex          = [System.Net.Http.HttpRequestException]::new('{"error":{"code":"InsufficientPermissions","message":"Access denied"}}')
                $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                $Result.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::OperationStopped)
            }
        }
    }

    Context 'When the exception has a Response body with a parseable JSON error (response body path)' {
        It 'returns a new ErrorRecord parsed from the response body' {
            InModuleScope Omnicit.PIM {
                $Json         = '{"error":{"code":"Forbidden","message":"You do not have permission"}}'
                $Content      = [System.Net.Http.StringContent]::new($Json)
                $FakeResponse = [PSCustomObject]@{ Content = $Content }
                $Ex           = [System.Exception]::new('HTTP error')
                $Ex | Add-Member -MemberType NoteProperty -Name 'Response' -Value $FakeResponse
                $InputRecord  = [System.Management.Automation.ErrorRecord]::new($Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                $Result.FullyQualifiedErrorId | Should -Be 'Forbidden'
                $Result.Exception.Message | Should -Be 'Forbidden: You do not have permission'
            }
        }
    }

    Context 'When the exception has no parseable JSON content' {
        It 'returns a new record and never the input record' {
            InModuleScope Omnicit.PIM {
                $Ex          = [System.Exception]::new('A generic non-JSON error')
                $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, 'GenericError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                $Result | Should -BeOfType ([System.Management.Automation.ErrorRecord])
                [object]::ReferenceEquals($Result, $InputRecord) | Should -BeFalse
                [object]::ReferenceEquals($Result.Exception, $Ex) | Should -BeFalse
                $Result.Exception.InnerException | Should -BeNullOrEmpty
            }
        }

        It "keeps the input record's id when the body has no error code" {
            InModuleScope Omnicit.PIM {
                $Ex          = [System.Exception]::new('A generic non-JSON error')
                $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, 'GenericError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                $Result.FullyQualifiedErrorId | Should -Be 'GenericError'
            }
        }

        It 'keeps the exception message text as the detail' {
            InModuleScope Omnicit.PIM {
                $Ex          = [System.Exception]::new('A generic non-JSON error')
                $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, 'GenericError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                $Result.Exception.Message | Should -Be 'A generic non-JSON error'
                $Result.ErrorDetails.Message | Should -Be 'A generic non-JSON error'
            }
        }

        It 'uses the exception type name when the input record has no id' {
            InModuleScope Omnicit.PIM {
                $Ex          = [System.Net.Http.HttpRequestException]::new('A generic non-JSON error')
                $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, '', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
                $InputRecord.FullyQualifiedErrorId | Should -BeNullOrEmpty -Because 'the fixture must carry no id, or the fallback is never reached'

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                $Result.FullyQualifiedErrorId | Should -Be 'System.Net.Http.HttpRequestException'
            }
        }
    }

    Context 'When the exception message contains JSON without a top-level "error" property' {
        It 'returns a new record and never the input record' {
            InModuleScope Omnicit.PIM {
                $Ex          = [System.Net.Http.HttpRequestException]::new('{"someOtherKey":"someValue","error":null}')
                $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                [object]::ReferenceEquals($Result, $InputRecord) | Should -BeFalse
                $Result.FullyQualifiedErrorId | Should -Be 'HttpError'
                $Result.Exception.InnerException | Should -BeNullOrEmpty
            }
        }
    }

    Context 'When the exception message matches the JSON pattern but contains malformed JSON' {
        It 'returns a new record and never the input record' {
            InModuleScope Omnicit.PIM {
                $Ex          = [System.Net.Http.HttpRequestException]::new('not valid json but contains "error" keyword')
                $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                [object]::ReferenceEquals($Result, $InputRecord) | Should -BeFalse
                $Result.FullyQualifiedErrorId | Should -Be 'HttpError'
                $Result.Exception.Message | Should -Be 'not valid json but contains "error" keyword'
            }
        }
    }

    Context 'When ReadAsStringAsync throws while reading the HTTP response body' {
        It 'returns a new record and never the input record' {
            InModuleScope Omnicit.PIM {
                $FakeContent = [PSCustomObject]@{}
                $FakeContent | Add-Member -MemberType ScriptMethod -Name ReadAsStringAsync -Value {
                    throw [System.IO.IOException]::new('Stream read error')
                }
                $FakeResponse = [PSCustomObject]@{ Content = $FakeContent }
                $Ex           = [System.Exception]::new('HTTP connection error')
                $Ex | Add-Member -MemberType NoteProperty -Name Response -Value $FakeResponse
                $InputRecord  = [System.Management.Automation.ErrorRecord]::new($Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                [object]::ReferenceEquals($Result, $InputRecord) | Should -BeFalse
                $Result.FullyQualifiedErrorId | Should -Be 'HttpError'
                $Result.Exception.Message | Should -Be 'HTTP connection error'
            }
        }
    }

    Context 'When the body has no error code but the response has a status' {
        It "keeps the input record's id when the body has no error code" {
            InModuleScope Omnicit.PIM {
                $Ex = [System.Exception]::new('Attempted to perform an unauthorized operation.')
                $Ex | Add-Member -MemberType NoteProperty -Name Response -Value ([PSCustomObject]@{ StatusCode = 403 })
                $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                $Result.FullyQualifiedErrorId | Should -Be 'HttpError' -Because 'a status code must never become an error id of its own'
                [object]::ReferenceEquals($Result, $InputRecord) | Should -BeFalse
            }
        }

        It 'names the HTTP status in the detail' {
            InModuleScope Omnicit.PIM {
                foreach ($Case in @(
                        @{ Status = 403; Message = 'Attempted to perform an unauthorized operation.' }
                        @{ Status = 418; Message = 'I am a teapot' }
                    )) {
                    $Ex = [System.Exception]::new($Case.Message)
                    $Ex | Add-Member -MemberType NoteProperty -Name Response -Value ([PSCustomObject]@{ StatusCode = $Case.Status })
                    $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                    $Result = Convert-GraphHttpException -InputRecord $InputRecord

                    $Result.Exception.Message | Should -Be ('HTTP {0}: {1}' -f $Case.Status, $Case.Message)
                    $Result.ErrorDetails.Message | Should -Be ('HTTP {0}: {1}' -f $Case.Status, $Case.Message)
                    $Result.FullyQualifiedErrorId | Should -Be 'HttpError'
                }
            }
        }
    }

    Context 'When the input record reaches a request message that carries a token' {
        It 'returns no record that reaches the request message' {
            $F = New-ScrubFixture -Status 403
            InModuleScope Omnicit.PIM -ArgumentList $F.Record {
                param($InputRecord)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                $Result.FullyQualifiedErrorId | Should -Be 'Authorization_RequestDenied'
                $Result.TargetObject | Should -BeNullOrEmpty
                $Result.Exception.InnerException | Should -BeNullOrEmpty
                [object]::ReferenceEquals($Result.Exception, $InputRecord.Exception) | Should -BeFalse
            }
        }
    }
}
