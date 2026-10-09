BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
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

    # The record is the one Convert-OPIMArmHttpException (Azure) or Convert-GraphHttpException (Graph)
    # built: its id is the service's error.code and its message carries error.message, with no inner
    # exception. The converter reads the id and the message of the record itself, never an inner
    # exception, so a keyword held only there is not a cooldown error.
    Context 'reads no inner exception' {

        BeforeAll {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}
        }

        It 'returns $false and writes nothing when only the inner exception names ActiveDurationTooShort' {
            InModuleScope Omnicit.PIM {
                $InnerEx = [System.Exception]::new('ActiveDurationTooShort: must wait')
                $OuterEx = [System.Exception]::new('The request failed.', $InnerEx)
                $FakeRecord = [System.Management.Automation.ErrorRecord]::new(
                    $OuterEx,
                    'SomeOtherErrorId',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                $FakeCmdlet = [PSCustomObject]@{}
                Add-Member -InputObject $FakeCmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) }
                $Result = ConvertTo-ActiveDurationTooShortError -CaughtError $FakeRecord -ResourceType 'role' -Cmdlet $FakeCmdlet
                $Result | Should -Be $false
            }
            Should -Invoke Write-CmdletError -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }

    # The ARM bodies (tests/Unit/TestHelpers/ArmResponse/error-*.json) are shaped as ARM's CloudError;
    # replaced by the bodies recorded live where they differ. Each record is built by
    # Convert-OPIMArmHttpException, as Invoke-OPIMArmRequest throws it, and the real Write-CmdletError
    # runs against a cmdlet stand-in that keeps what is written.
    Context 'ARM error body' {

        BeforeAll {
            $FixtureDirectory = "$PSScriptRoot/../TestHelpers/ArmResponse"
        }

        It 'writes the cooldown error once and returns $true' {
            $Body = Get-Content -Raw -LiteralPath "$FixtureDirectory/error-ActiveDurationTooShort.json"
            InModuleScope Omnicit.PIM -Parameters @{ Body = $Body } {
                param($Body)
                $Record = Convert-OPIMArmHttpException -Response ([PSCustomObject]@{ StatusCode = 400; Content = $Body }) -Path '/providers/x'
                $Record.FullyQualifiedErrorId | Should -BeExactly 'ActiveDurationTooShort'
                $Cmdlet = [PSCustomObject]@{ Written = [System.Collections.Generic.List[object]]::new() }
                Add-Member -InputObject $Cmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) $this.Written.Add($E) }

                $Result = ConvertTo-ActiveDurationTooShortError -CaughtError $Record -ResourceType 'role' -Cmdlet $Cmdlet

                $Result | Should -Be $true
                $Cmdlet.Written.Count | Should -Be 1
                $Cmdlet.Written[0].FullyQualifiedErrorId | Should -BeExactly 'ActiveDurationTooShort'
                $Cmdlet.Written[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ResourceUnavailable)
                $Cmdlet.Written[0].Exception.Message | Should -BeExactly 'You must wait at least 5 minutes after activating a role before you can deactivate it.'
            }
        }

        It 'names the resource type of the caller in the message' {
            $Body = Get-Content -Raw -LiteralPath "$FixtureDirectory/error-ActiveDurationTooShort.json"
            InModuleScope Omnicit.PIM -Parameters @{ Body = $Body } {
                param($Body)
                $Record = Convert-OPIMArmHttpException -Response ([PSCustomObject]@{ StatusCode = 400; Content = $Body }) -Path '/providers/x'
                $Cmdlet = [PSCustomObject]@{ Written = [System.Collections.Generic.List[object]]::new() }
                Add-Member -InputObject $Cmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) $this.Written.Add($E) }

                $Result = ConvertTo-ActiveDurationTooShortError -CaughtError $Record -ResourceType 'group' -Cmdlet $Cmdlet

                $Result | Should -Be $true
                $Cmdlet.Written[0].Exception.Message | Should -BeExactly 'You must wait at least 5 minutes after activating a group before you can deactivate it.'
            }
        }

        It 'returns $false and writes nothing for the <Name> body' -ForEach @(
            @{ Name = 'InsufficientPermissions'; Body = $null; File = 'error-InsufficientPermissions.json' }
            @{ Name = 'policy validation'; Body = $null; File = 'error-PolicyValidationFailed.json' }
            @{ Name = 'body without an ARM error'; Body = '{"value":[]}'; File = $null }
        ) {
            $Content = if ($File) { Get-Content -Raw -LiteralPath "$FixtureDirectory/$File" } else { $Body }
            InModuleScope Omnicit.PIM -Parameters @{ Content = $Content } {
                param($Content)
                $Record = Convert-OPIMArmHttpException -Response ([PSCustomObject]@{ StatusCode = 400; Content = $Content }) -Path '/providers/x'
                $Cmdlet = [PSCustomObject]@{ Written = [System.Collections.Generic.List[object]]::new() }
                Add-Member -InputObject $Cmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) $this.Written.Add($E) }

                $Result = ConvertTo-ActiveDurationTooShortError -CaughtError $Record -ResourceType 'role' -Cmdlet $Cmdlet

                $Result | Should -Be $false
                $Cmdlet.Written.Count | Should -Be 0
            }
        }
    }

    # The same converter serves the Graph cmdlets, whose record Convert-GraphHttpException builds the
    # same way: the Graph error.code as the id, "<code>: <message>" as the message.
    Context 'Graph error body' {

        It 'writes the cooldown error once and returns $true' {
            InModuleScope Omnicit.PIM {
                $Ex = [System.Net.Http.HttpRequestException]::new('{"error":{"code":"ActiveDurationTooShort","message":"The role was activated less than 5 minutes ago."}}')
                $Raw = [System.Management.Automation.ErrorRecord]::new($Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
                $Record = Convert-GraphHttpException -InputRecord $Raw
                $Record.FullyQualifiedErrorId | Should -BeExactly 'ActiveDurationTooShort'
                $Cmdlet = [PSCustomObject]@{ Written = [System.Collections.Generic.List[object]]::new() }
                Add-Member -InputObject $Cmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) $this.Written.Add($E) }

                $Result = ConvertTo-ActiveDurationTooShortError -CaughtError $Record -ResourceType 'group' -Cmdlet $Cmdlet

                $Result | Should -Be $true
                $Cmdlet.Written.Count | Should -Be 1
                $Cmdlet.Written[0].FullyQualifiedErrorId | Should -BeExactly 'ActiveDurationTooShort'
                $Cmdlet.Written[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ResourceUnavailable)
                $Cmdlet.Written[0].Exception.Message | Should -BeExactly 'You must wait at least 5 minutes after activating a group before you can deactivate it.'
            }
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
