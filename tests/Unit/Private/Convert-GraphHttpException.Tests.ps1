Describe 'Convert-GraphHttpException' {
    BeforeAll {
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

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

        It 'wraps the original exception as the inner exception' {
            InModuleScope Omnicit.PIM {
                $Ex          = [System.Net.Http.HttpRequestException]::new('{"error":{"code":"InsufficientPermissions","message":"Access denied"}}')
                $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                $Result.Exception.InnerException | Should -Be $Ex
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
        It 'returns the original ErrorRecord unchanged' {
            InModuleScope Omnicit.PIM {
                $Ex          = [System.Exception]::new('A generic non-JSON error')
                $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, 'GenericError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                $Result | Should -Be $InputRecord
            }
        }
    }

    Context 'When the exception message contains JSON without a top-level "error" property' {
        It 'returns the original ErrorRecord unchanged' {
            InModuleScope Omnicit.PIM {
                $Ex          = [System.Net.Http.HttpRequestException]::new('{"someOtherKey":"someValue","error":null}')
                $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                $Result | Should -Be $InputRecord
            }
        }
    }

    Context 'When the exception message matches the JSON pattern but contains malformed JSON' {
        It 'returns the original ErrorRecord unchanged' {
            InModuleScope Omnicit.PIM {
                $Ex          = [System.Net.Http.HttpRequestException]::new('not valid json but contains "error" keyword')
                $InputRecord = [System.Management.Automation.ErrorRecord]::new($Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $Result = Convert-GraphHttpException -InputRecord $InputRecord

                $Result | Should -Be $InputRecord
            }
        }
    }

    Context 'When ReadAsStringAsync throws while reading the HTTP response body' {
        It 'returns the original ErrorRecord unchanged' {
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

                $Result | Should -Be $InputRecord
            }
        }
    }
}
