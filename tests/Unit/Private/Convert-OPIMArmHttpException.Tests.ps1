BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Convert-OPIMArmHttpException' {
    Context 'When the body carries an ARM error code' {
        It 'returns a record whose id is the code and whose message is the code and the message' {
            InModuleScope Omnicit.PIM {
                $Response = [PSCustomObject]@{
                    StatusCode = 409
                    Content    = '{"error":{"code":"RoleAssignmentExists","message":"The role assignment already exists."}}'
                }
                $Record = Convert-OPIMArmHttpException -Response $Response -Path '/subscriptions/x'
                $Record | Should -BeOfType ([System.Management.Automation.ErrorRecord])
                $Record.FullyQualifiedErrorId | Should -BeExactly 'RoleAssignmentExists'
                $Record.Exception.Message | Should -BeExactly 'RoleAssignmentExists: The role assignment already exists.'
                $Record.ErrorDetails.Message | Should -BeExactly 'RoleAssignmentExists: The role assignment already exists.'
                $Record.TargetObject | Should -BeExactly '/subscriptions/x'
                $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::OperationStopped)
                $Record.Exception.InnerException | Should -BeNullOrEmpty
            }
        }

        It 'appends every entry of error.details to the message' {
            InModuleScope Omnicit.PIM {
                $Response = [PSCustomObject]@{
                    StatusCode = 400
                    Content    = '{"error":{"code":"InvalidPolicy","message":"The policy is invalid.","details":[{"code":"RoleManagementPolicyRuleValidationError","message":"Permanent eligible assignment is not allowed for this role."},{"code":"OnlyCode"},{"message":"Only a message."}]}}'
                }
                $Record = Convert-OPIMArmHttpException -Response $Response
                $Record.FullyQualifiedErrorId | Should -BeExactly 'InvalidPolicy'
                $Expected = 'InvalidPolicy: The policy is invalid. (RoleManagementPolicyRuleValidationError: Permanent eligible assignment is not allowed for this role.; OnlyCode; Only a message.)'
                $Record.Exception.Message | Should -BeExactly $Expected
                $Record.ErrorDetails.Message | Should -BeExactly $Expected
            }
        }

        It 'returns the code alone when the body carries no message' {
            InModuleScope Omnicit.PIM {
                $Response = [PSCustomObject]@{ StatusCode = 404; Content = '{"error":{"code":"RoleDefinitionDoesNotExist"}}' }
                $Record = Convert-OPIMArmHttpException -Response $Response
                $Record.FullyQualifiedErrorId | Should -BeExactly 'RoleDefinitionDoesNotExist'
                $Record.Exception.Message | Should -BeExactly 'RoleDefinitionDoesNotExist'
                $Record.ErrorDetails.Message | Should -BeExactly 'RoleDefinitionDoesNotExist'
            }
        }

        It 'reads the code and the message out of a body that is not pure JSON, and scrubs the parse failure' {
            InModuleScope Omnicit.PIM {
                $Before = $global:Error.Count
                $Response = [PSCustomObject]@{
                    StatusCode = 429
                    Content    = 'Some wrapper text {"code":"TooManyRequests","message":"Rate limited."} trailing'
                }
                $Record = Convert-OPIMArmHttpException -Response $Response
                $Record.FullyQualifiedErrorId | Should -BeExactly 'TooManyRequests'
                $Record.Exception.Message | Should -BeExactly 'TooManyRequests: Rate limited.'
                $global:Error.Count | Should -Be $Before
            }
        }

        It 'calls Remove-OPIMErrorRecord for the parse failure of a body that is not JSON' {
            InModuleScope Omnicit.PIM {
                Mock Remove-OPIMErrorRecord {}
                $Response = [PSCustomObject]@{
                    StatusCode = 400
                    Content    = 'Some wrapper text {"code":"BadRequest","message":"Broken."} trailing'
                }
                $null = Convert-OPIMArmHttpException -Response $Response -Path '/subscriptions/x'
                Should -Invoke Remove-OPIMErrorRecord -Times 1 -Exactly -Scope It
            }
        }
    }

    Context 'When the body carries no ARM error code' {
        It 'returns ArmTransportError naming the status and the message' {
            InModuleScope Omnicit.PIM {
                $Response = [PSCustomObject]@{
                    StatusCode = 409
                    Content    = '{"error":{"code":"","message":"Attempted to perform an unauthorized operation."}}'
                }
                $Record = Convert-OPIMArmHttpException -Response $Response -Path '/x'
                $Record.FullyQualifiedErrorId | Should -BeExactly 'ArmTransportError'
                $Record.Exception.Message | Should -BeExactly 'HTTP 409: Attempted to perform an unauthorized operation.'
                $Record.ErrorDetails.Message | Should -BeExactly 'HTTP 409: Attempted to perform an unauthorized operation.'
                $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::OperationStopped)
                $Record.TargetObject | Should -BeExactly '/x'
            }
        }

        It 'returns ArmTransportError saying no code was returned for <Name>' -ForEach @(
            @{ Name = 'an HTML 502 page'; Status = 502; Content = '<html><head><title>502 Bad Gateway</title></head><body>Bad Gateway</body></html>' }
            @{ Name = 'an empty body'; Status = 418; Content = '' }
            @{ Name = 'a null body'; Status = 500; Content = $null }
            @{ Name = 'a JSON body without an error object'; Status = 400; Content = '{"value":[]}' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Status = $Status; Content = $Content } {
                param($Status, $Content)
                $Response = [PSCustomObject]@{ StatusCode = $Status; Content = $Content }
                $Record = Convert-OPIMArmHttpException -Response $Response
                $Record.FullyQualifiedErrorId | Should -BeExactly 'ArmTransportError'
                $Record.Exception.Message | Should -BeExactly "HTTP $Status`: Azure Resource Manager returned no error code."
                $Record.ErrorDetails.Message | Should -BeExactly "HTTP $Status`: Azure Resource Manager returned no error code."
            }
        }

        It 'reads a status that is not numeric as 0 and does not throw' {
            InModuleScope Omnicit.PIM {
                $Response = [PSCustomObject]@{ StatusCode = 'not-a-status'; Content = '' }
                $Record = Convert-OPIMArmHttpException -Response $Response
                $Record.FullyQualifiedErrorId | Should -BeExactly 'ArmTransportError'
                $Record.Exception.Message | Should -BeExactly 'HTTP 0: Azure Resource Manager returned no error code.'
            }
        }
    }

    Context 'When the response carries headers' {
        It 'reads no header: a Headers property that throws when read does not stop the conversion' {
            InModuleScope Omnicit.PIM {
                $Response = [PSCustomObject]@{
                    StatusCode  = 403
                    Content     = '{"error":{"code":"AuthorizationFailed","message":"denied"}}'
                    HeaderReads = 0
                }
                # Counts every read, then throws. PowerShell hands a member read whose getter throws back
                # as $null outside strict mode, so the count is what shows a read.
                $Response | Add-Member -MemberType ScriptProperty -Name Headers -Value {
                    $this.HeaderReads = $this.HeaderReads + 1
                    throw 'the headers were read'
                }
                $Record = Convert-OPIMArmHttpException -Response $Response -Path '/x'
                $Record.FullyQualifiedErrorId | Should -BeExactly 'AuthorizationFailed'
                $Record.Exception.Message | Should -BeExactly 'AuthorizationFailed: denied'
                $Response.HeaderReads | Should -Be 0
                # Control: a read of the property is counted.
                $null = $Response.Headers
                $Response.HeaderReads | Should -Be 1
            }
        }

        It 'surfaces no header in the record' {
            InModuleScope Omnicit.PIM {
                $Response = [PSCustomObject]@{
                    StatusCode = 429
                    Content    = '{"error":{"code":"TooManyRequests","message":"slow down"}}'
                    Headers    = @{ 'Retry-After' = @('30'); 'Authorization' = @('Bearer NOT-A-REAL-TOKEN') }
                }
                $Record = Convert-OPIMArmHttpException -Response $Response -Path '/x?api-version=2020-10-01'
                $Record.FullyQualifiedErrorId | Should -BeExactly 'TooManyRequests'
                $Record.Exception.Message | Should -BeExactly 'TooManyRequests: slow down'
                [string]$Record.ErrorDetails.Message | Should -Not -Match '(?i)bearer|retry-after|NOT-A-REAL-TOKEN'
                [string]$Record.TargetObject | Should -BeExactly '/x?api-version=2020-10-01'
            }
        }
    }
}
