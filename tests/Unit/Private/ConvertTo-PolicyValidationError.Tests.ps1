BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
}

AfterAll {
    Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-PolicyValidationError' {

    # Helper to build a fake ErrorRecord used across multiple contexts
    BeforeAll {
        function New-FakeErrorRecord {
            param(
                [string]$Message = 'generic error',
                [string]$ErrorId = 'UnknownError',
                [System.Exception]$InnerException = $null
            )
            $Ex = if ($InnerException) {
                [System.Exception]::new($Message, $InnerException)
            } else {
                [System.Exception]::new($Message)
            }
            [System.Management.Automation.ErrorRecord]::new(
                $Ex,
                $ErrorId,
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                $null
            )
        }

        $FakeCmdlet = [PSCustomObject]@{}
        Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
    }

    Context 'When the error contains JustificationRule in the error ID' {

        BeforeAll {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}
        }

        It 'returns $true' {
            InModuleScope Omnicit.PIM {
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Policy validation'),
                    'RoleAssignmentRequestPolicyValidationFailed.JustificationRule',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $Result = ConvertTo-PolicyValidationError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
                $Result | Should -Be $true
            }
        }

        It 'calls Write-CmdletError with ErrorId RoleAssignmentRequestPolicyValidationFailed' {
            InModuleScope Omnicit.PIM {
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Policy validation'),
                    'RoleAssignmentRequestPolicyValidationFailed.JustificationRule',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $null = ConvertTo-PolicyValidationError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
            }
            Should -Invoke Write-CmdletError -ModuleName Omnicit.PIM -Times 1 -Scope It `
                -ParameterFilter { $ErrorId -eq 'RoleAssignmentRequestPolicyValidationFailed' }
        }

        It 'mentions -Justification in the error message' {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}
            InModuleScope Omnicit.PIM {
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Policy validation'),
                    'RoleAssignmentRequestPolicyValidationFailed.JustificationRule',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $null = ConvertTo-PolicyValidationError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
            }
            Should -Invoke Write-CmdletError -ModuleName Omnicit.PIM -Times 1 -Scope It `
                -ParameterFilter { $Message.Message -match '-Justification' }
        }

        It 'includes the resource type in the message' {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}
            InModuleScope Omnicit.PIM {
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Policy validation'),
                    'RoleAssignmentRequestPolicyValidationFailed.JustificationRule',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $null = ConvertTo-PolicyValidationError -CaughtError $FakeRecord -ResourceType 'group' -Cmdlet $FakeCmdlet
            }
            Should -Invoke Write-CmdletError -ModuleName Omnicit.PIM -Times 1 -Scope It `
                -ParameterFilter { $Message.Message -match 'group' }
        }
    }

    Context 'When the error contains JustificationRule in the exception message' {

        BeforeAll {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}
        }

        It 'returns $true' {
            InModuleScope Omnicit.PIM {
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('JustificationRule is not satisfied'),
                    'SomeOtherErrorId',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $Result = ConvertTo-PolicyValidationError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
                $Result | Should -Be $true
            }
        }
    }

    Context 'When the error contains JustificationRule in the inner exception message' {

        BeforeAll {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}
        }

        It 'returns $true' {
            InModuleScope Omnicit.PIM {
                $InnerEx = [System.Exception]::new('JustificationRule is not satisfied')
                $OuterEx = [System.Exception]::new('Policy validation failed', $InnerEx)
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    $OuterEx,
                    'SomeOtherErrorId',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $Result = ConvertTo-PolicyValidationError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
                $Result | Should -Be $true
            }
        }
    }

    Context 'When the error contains ExpirationRule' {

        BeforeAll {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}
        }

        It 'returns $true' {
            InModuleScope Omnicit.PIM {
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('ExpirationRule validation failed'),
                    'SomeOtherErrorId',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $Result = ConvertTo-PolicyValidationError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
                $Result | Should -Be $true
            }
        }

        It 'calls Write-CmdletError with ErrorId RoleAssignmentRequestPolicyValidationFailed' {
            InModuleScope Omnicit.PIM {
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('ExpirationRule validation failed'),
                    'SomeOtherErrorId',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $null = ConvertTo-PolicyValidationError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
            }
            Should -Invoke Write-CmdletError -ModuleName Omnicit.PIM -Times 1 -Scope It `
                -ParameterFilter { $ErrorId -eq 'RoleAssignmentRequestPolicyValidationFailed' }
        }

        It 'mentions -NotAfter in the error message' {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}
            InModuleScope Omnicit.PIM {
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('ExpirationRule validation failed'),
                    'SomeOtherErrorId',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $null = ConvertTo-PolicyValidationError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
            }
            Should -Invoke Write-CmdletError -ModuleName Omnicit.PIM -Times 1 -Scope It `
                -ParameterFilter { $Message.Message -match '-NotAfter' }
        }
    }

    Context 'When the error is NOT a recognised policy violation' {

        BeforeAll {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}
        }

        It 'returns $false' {
            InModuleScope Omnicit.PIM {
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Network error'),
                    'NetworkFailure',
                    [System.Management.Automation.ErrorCategory]::NotSpecified,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $Result = ConvertTo-PolicyValidationError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
                $Result | Should -Be $false
            }
        }

        It 'does not call Write-CmdletError' {
            InModuleScope Omnicit.PIM {
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Network error'),
                    'NetworkFailure',
                    [System.Management.Automation.ErrorCategory]::NotSpecified,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $null = ConvertTo-PolicyValidationError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
            }
            Should -Invoke Write-CmdletError -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }

    Context 'ResourceType defaults to role' {

        BeforeAll {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}
        }

        It 'uses role in the message when -ResourceType is omitted' {
            InModuleScope Omnicit.PIM {
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('JustificationRule not satisfied'),
                    'PolicyFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $null = ConvertTo-PolicyValidationError -CaughtError $FakeRecord -Cmdlet $FakeCmdlet
            }
            Should -Invoke Write-CmdletError -ModuleName Omnicit.PIM -Times 1 -Scope It `
                -ParameterFilter { $Message.Message -match 'role' }
        }
    }
}
