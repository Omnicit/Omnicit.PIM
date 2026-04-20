BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
}

AfterAll {
    Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-ActiveDurationTooShortError' {

    # Build a minimal fake $PSCmdlet substitute that records what Write-CmdletError
    # receives.  The helper only needs .WriteError() for the passthrough path; the
    # happy path goes through the Write-CmdletError mock, so we don't need a real one.
    BeforeAll {
        $FakeCmdlet = [PSCustomObject]@{}
        Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($Err) }
    }

    Context 'When the error IS an ActiveDurationTooShort error (via FullyQualifiedErrorId)' {

        BeforeAll {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}

            $FakeException = [System.Exception]::new('Activation still pending')
            $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                $FakeException,
                'ActiveDurationTooShortForRole,Microsoft.Azure.Commands.Resources.Cmdlets',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $null
            )
        }

        It 'returns $true' {
            InModuleScope Omnicit.PIM {
                $FakeException = [System.Exception]::new('Activation still pending')
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    $FakeException,
                    'ActiveDurationTooShortForRole',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $Result = ConvertTo-ActiveDurationTooShortError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
                $Result | Should -Be $true
            }
        }

        It 'calls Write-CmdletError once with ErrorId ActiveDurationTooShort' {
            InModuleScope Omnicit.PIM {
                $FakeException = [System.Exception]::new('Activation still pending')
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    $FakeException,
                    'ActiveDurationTooShortForRole',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $null = ConvertTo-ActiveDurationTooShortError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
            }
            Should -Invoke Write-CmdletError -ModuleName Omnicit.PIM -Times 1 -Scope It `
                -ParameterFilter { $ErrorId -eq 'ActiveDurationTooShort' }
        }

        It 'includes the resource type word in the error message' {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}
            InModuleScope Omnicit.PIM {
                $FakeException = [System.Exception]::new('Activation still pending')
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    $FakeException,
                    'ActiveDurationTooShortForGroup',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $null = ConvertTo-ActiveDurationTooShortError -CaughtError $FakeRecord -ResourceType 'group' -Cmdlet $FakeCmdlet
            }
            Should -Invoke Write-CmdletError -ModuleName Omnicit.PIM -Times 1 -Scope It `
                -ParameterFilter { $Message.Message -match 'group' }
        }
    }

    Context 'When the error IS an ActiveDurationTooShort error (via Exception.Message)' {

        BeforeAll {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}
        }

        It 'returns $true when the exception message contains the keyword' {
            InModuleScope Omnicit.PIM {
                $FakeException = [System.Exception]::new('ActiveDurationTooShort: must wait')
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    $FakeException,
                    'SomeOtherErrorId',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $Result = ConvertTo-ActiveDurationTooShortError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
                $Result | Should -Be $true
            }
        }

        It 'calls Write-CmdletError with Category ResourceUnavailable' {
            InModuleScope Omnicit.PIM {
                $FakeException = [System.Exception]::new('ActiveDurationTooShort: must wait')
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    $FakeException,
                    'SomeOtherErrorId',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $null = ConvertTo-ActiveDurationTooShortError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
            }
            Should -Invoke Write-CmdletError -ModuleName Omnicit.PIM -Times 1 -Scope It `
                -ParameterFilter { $Category -eq 'ResourceUnavailable' }
        }
    }

    Context 'When the error is NOT an ActiveDurationTooShort error' {

        BeforeAll {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}
        }

        It 'returns $false' {
            InModuleScope Omnicit.PIM {
                $FakeException = [System.Exception]::new('Some unrelated error')
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    $FakeException,
                    'UnrelatedError',
                    [System.Management.Automation.ErrorCategory]::NotSpecified,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $Result = ConvertTo-ActiveDurationTooShortError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
                $Result | Should -Be $false
            }
        }

        It 'does not call Write-CmdletError' {
            InModuleScope Omnicit.PIM {
                $FakeException = [System.Exception]::new('Some unrelated error')
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    $FakeException,
                    'UnrelatedError',
                    [System.Management.Automation.ErrorCategory]::NotSpecified,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $null = ConvertTo-ActiveDurationTooShortError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
            }
            Should -Invoke Write-CmdletError -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }

    Context 'ResourceType defaults to role' {

        BeforeAll {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}
        }

        It 'uses role in the message when -ResourceType is omitted' {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}
            InModuleScope Omnicit.PIM {
                $FakeException = [System.Exception]::new('Something')
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    $FakeException,
                    'ActiveDurationTooShort',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $null = ConvertTo-ActiveDurationTooShortError -CaughtError $FakeRecord -Cmdlet $FakeCmdlet
            }
            Should -Invoke Write-CmdletError -ModuleName Omnicit.PIM -Times 1 -Scope It `
                -ParameterFilter { $Message.Message -match 'role' }
        }
    }
}
