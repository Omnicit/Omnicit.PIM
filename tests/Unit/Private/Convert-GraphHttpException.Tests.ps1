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
                $ex = [System.Net.Http.HttpRequestException]::new('{"error":{"code":"InsufficientPermissions","message":"Access denied"}}')
                $inputRecord = [System.Management.Automation.ErrorRecord]::new($ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $result = Convert-GraphHttpException -errorRecord $inputRecord

                $result.FullyQualifiedErrorId | Should -Be 'InsufficientPermissions'
            }
        }

        It 'returns a new ErrorRecord whose exception message is formatted as "code: message"' {
            InModuleScope Omnicit.PIM {
                $ex = [System.Net.Http.HttpRequestException]::new('{"error":{"code":"InsufficientPermissions","message":"Access denied"}}')
                $inputRecord = [System.Management.Automation.ErrorRecord]::new($ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $result = Convert-GraphHttpException -errorRecord $inputRecord

                $result.Exception.Message | Should -Be 'InsufficientPermissions: Access denied'
            }
        }

        It 'wraps the original exception as the inner exception' {
            InModuleScope Omnicit.PIM {
                $ex = [System.Net.Http.HttpRequestException]::new('{"error":{"code":"InsufficientPermissions","message":"Access denied"}}')
                $inputRecord = [System.Management.Automation.ErrorRecord]::new($ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $result = Convert-GraphHttpException -errorRecord $inputRecord

                $result.Exception.InnerException | Should -Be $ex
            }
        }

        It 'sets ErrorDetails on the returned ErrorRecord' {
            InModuleScope Omnicit.PIM {
                $ex = [System.Net.Http.HttpRequestException]::new('{"error":{"code":"InsufficientPermissions","message":"Access denied"}}')
                $inputRecord = [System.Management.Automation.ErrorRecord]::new($ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $result = Convert-GraphHttpException -errorRecord $inputRecord

                $result.ErrorDetails | Should -Not -BeNullOrEmpty
                $result.ErrorDetails.Message | Should -Be 'InsufficientPermissions: Access denied'
            }
        }

        It 'sets the category to OperationStopped on the returned ErrorRecord' {
            InModuleScope Omnicit.PIM {
                $ex = [System.Net.Http.HttpRequestException]::new('{"error":{"code":"InsufficientPermissions","message":"Access denied"}}')
                $inputRecord = [System.Management.Automation.ErrorRecord]::new($ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $result = Convert-GraphHttpException -errorRecord $inputRecord

                $result.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::OperationStopped)
            }
        }
    }

    Context 'When the exception has a Response body with a parseable JSON error (response body path)' {
        It 'returns a new ErrorRecord parsed from the response body' {
            InModuleScope Omnicit.PIM {
                $json = '{"error":{"code":"Forbidden","message":"You do not have permission"}}'
                $content = [System.Net.Http.StringContent]::new($json)
                $fakeResponse = [PSCustomObject]@{ Content = $content }
                $ex = [System.Exception]::new('HTTP error')
                $ex | Add-Member -MemberType NoteProperty -Name 'Response' -Value $fakeResponse
                $inputRecord = [System.Management.Automation.ErrorRecord]::new($ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $result = Convert-GraphHttpException -errorRecord $inputRecord

                $result.FullyQualifiedErrorId | Should -Be 'Forbidden'
                $result.Exception.Message | Should -Be 'Forbidden: You do not have permission'
            }
        }
    }

    Context 'When the exception has no parseable JSON content' {
        It 'returns the original ErrorRecord unchanged' {
            InModuleScope Omnicit.PIM {
                $ex = [System.Exception]::new('A generic non-JSON error')
                $inputRecord = [System.Management.Automation.ErrorRecord]::new($ex, 'GenericError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)

                $result = Convert-GraphHttpException -errorRecord $inputRecord

                $result | Should -Be $inputRecord
            }
        }
    }

    Context 'When the exception message contains JSON without a top-level "error" property' {
        It 'returns the original ErrorRecord unchanged' {
            InModuleScope Omnicit.PIM {
                $ex = [System.Net.Http.HttpRequestException]::new('{"someOtherKey":"someValue","error":null}')
                $inputRecord = [System.Management.Automation.ErrorRecord]::new($ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $result = Convert-GraphHttpException -errorRecord $inputRecord

                $result | Should -Be $inputRecord
            }
        }
    }

    Context 'When the exception message matches the JSON pattern but contains malformed JSON' {
        It 'returns the original ErrorRecord unchanged' {
            InModuleScope Omnicit.PIM {
                $ex = [System.Net.Http.HttpRequestException]::new('not valid json but contains "error" keyword')
                $inputRecord = [System.Management.Automation.ErrorRecord]::new($ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

                $result = Convert-GraphHttpException -errorRecord $inputRecord

                $result | Should -Be $inputRecord
            }
        }
    }
}
