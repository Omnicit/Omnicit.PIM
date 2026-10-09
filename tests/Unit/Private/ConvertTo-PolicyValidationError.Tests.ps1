BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
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

    # The record is the one Convert-OPIMArmHttpException (Azure) or Convert-GraphHttpException (Graph)
    # built: its id is the service's error.code and its message carries error.message, with no inner
    # exception. Az.Resources used to hide the rule name in an inner exception; the converter no longer
    # reads one, so a rule named only there is not a policy violation.
    Context 'reads no inner exception' {

        BeforeAll {
            Mock -ModuleName Omnicit.PIM Write-CmdletError {}
        }

        It 'returns $false and writes nothing when only the inner exception names <Rule>' -ForEach @(
            @{ Rule = 'JustificationRule' }
            @{ Rule = 'ExpirationRule' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Rule = $Rule } {
                param($Rule)
                $InnerEx = [System.Exception]::new("$Rule is not satisfied")
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

        It 'writes the <Rule> error once and returns $true' -ForEach @(
            @{
                Rule     = 'JustificationRule'
                File     = 'error-PolicyValidationFailed.json'
                Expected = 'Your PIM policy requires a justification for this role. Use the -Justification parameter.'
            }
            @{
                Rule     = 'ExpirationRule'
                File     = 'error-PolicyValidationFailed-ExpirationRule.json'
                Expected = 'Your PIM policy requires a shorter expiration. Use -Hours, or -Until on the Enable-OPIM* cmdlets, to ask for a shorter activation.'
            }
        ) {
            $Body = Get-Content -Raw -LiteralPath "$FixtureDirectory/$File"
            InModuleScope Omnicit.PIM -Parameters @{ Body = $Body; Expected = $Expected } {
                param($Body, $Expected)
                $Record = Convert-OPIMArmHttpException -Response ([PSCustomObject]@{ StatusCode = 400; Content = $Body }) -Path '/providers/x'
                $Record.FullyQualifiedErrorId | Should -BeExactly 'RoleAssignmentRequestPolicyValidationFailed'
                $Cmdlet = [PSCustomObject]@{ Written = [System.Collections.Generic.List[object]]::new() }
                Add-Member -InputObject $Cmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) $this.Written.Add($E) }

                $Result = ConvertTo-PolicyValidationError -CaughtError $Record -ResourceType 'role' -Cmdlet $Cmdlet

                $Result | Should -Be $true
                $Cmdlet.Written.Count | Should -Be 1
                $Cmdlet.Written[0].FullyQualifiedErrorId | Should -BeExactly 'RoleAssignmentRequestPolicyValidationFailed'
                $Cmdlet.Written[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::OperationStopped)
                $Cmdlet.Written[0].Exception.Message | Should -BeExactly $Expected
            }
        }

        It 'names the resource type of the caller in the message' {
            $Body = Get-Content -Raw -LiteralPath "$FixtureDirectory/error-PolicyValidationFailed.json"
            InModuleScope Omnicit.PIM -Parameters @{ Body = $Body } {
                param($Body)
                $Record = Convert-OPIMArmHttpException -Response ([PSCustomObject]@{ StatusCode = 400; Content = $Body }) -Path '/providers/x'
                $Cmdlet = [PSCustomObject]@{ Written = [System.Collections.Generic.List[object]]::new() }
                Add-Member -InputObject $Cmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) $this.Written.Add($E) }

                $Result = ConvertTo-PolicyValidationError -CaughtError $Record -ResourceType 'group' -Cmdlet $Cmdlet

                $Result | Should -Be $true
                $Cmdlet.Written[0].Exception.Message | Should -BeExactly 'Your PIM policy requires a justification for this group. Use the -Justification parameter.'
            }
        }

        It 'reads a rule that the body names only under error.details' {
            $Body = '{"error":{"code":"RoleAssignmentRequestPolicyValidationFailed","message":"The request failed policy validation.","details":[{"code":"JustificationRule","message":"A justification is required."}]}}'
            InModuleScope Omnicit.PIM -Parameters @{ Body = $Body } {
                param($Body)
                $Record = Convert-OPIMArmHttpException -Response ([PSCustomObject]@{ StatusCode = 400; Content = $Body }) -Path '/providers/x'
                $Cmdlet = [PSCustomObject]@{ Written = [System.Collections.Generic.List[object]]::new() }
                Add-Member -InputObject $Cmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) $this.Written.Add($E) }

                $Result = ConvertTo-PolicyValidationError -CaughtError $Record -ResourceType 'role' -Cmdlet $Cmdlet

                $Result | Should -Be $true
                $Cmdlet.Written.Count | Should -Be 1
                $Cmdlet.Written[0].Exception.Message | Should -BeExactly 'Your PIM policy requires a justification for this role. Use the -Justification parameter.'
            }
        }

        It 'returns $false and writes nothing for the <Name> body' -ForEach @(
            @{ Name = 'InsufficientPermissions'; Body = $null; File = 'error-InsufficientPermissions.json' }
            @{ Name = 'ActiveDurationTooShort'; Body = $null; File = 'error-ActiveDurationTooShort.json' }
            @{
                Name = 'policy failure of another rule'
                Body = '{"error":{"code":"RoleAssignmentRequestPolicyValidationFailed","message":"The following policy rules failed: [\"MaximumDurationRule\"]."}}'
                File = $null
            }
            @{ Name = 'body without an ARM error'; Body = '{"value":[]}'; File = $null }
        ) {
            $Content = if ($File) { Get-Content -Raw -LiteralPath "$FixtureDirectory/$File" } else { $Body }
            InModuleScope Omnicit.PIM -Parameters @{ Content = $Content } {
                param($Content)
                $Record = Convert-OPIMArmHttpException -Response ([PSCustomObject]@{ StatusCode = 400; Content = $Content }) -Path '/providers/x'
                $Cmdlet = [PSCustomObject]@{ Written = [System.Collections.Generic.List[object]]::new() }
                Add-Member -InputObject $Cmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) $this.Written.Add($E) }

                $Result = ConvertTo-PolicyValidationError -CaughtError $Record -ResourceType 'role' -Cmdlet $Cmdlet

                $Result | Should -Be $false
                $Cmdlet.Written.Count | Should -Be 0
            }
        }
    }

    # The same converter serves the Graph cmdlets, whose record Convert-GraphHttpException builds the
    # same way: the Graph error.code as the id, "<code>: <message>" as the message.
    Context 'Graph error body' {

        It 'writes the <Rule> error once and returns $true' -ForEach @(
            @{
                Rule     = 'JustificationRule'
                Body     = '{"error":{"code":"RoleAssignmentRequestPolicyValidationFailed","message":"Policy validation failed: JustificationRule requires a justification."}}'
                Expected = 'Your PIM policy requires a justification for this group. Use the -Justification parameter.'
            }
            @{
                Rule     = 'ExpirationRule'
                Body     = '{"error":{"code":"RoleAssignmentRequestPolicyValidationFailed","message":"Policy validation failed: ExpirationRule duration exceeded."}}'
                Expected = 'Your PIM policy requires a shorter expiration. Use -Hours, or -Until on the Enable-OPIM* cmdlets, to ask for a shorter activation.'
            }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Body = $Body; Expected = $Expected } {
                param($Body, $Expected)
                $Ex = [System.Net.Http.HttpRequestException]::new($Body)
                $Raw = [System.Management.Automation.ErrorRecord]::new($Ex, 'HttpError', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
                $Record = Convert-GraphHttpException -InputRecord $Raw
                $Record.FullyQualifiedErrorId | Should -BeExactly 'RoleAssignmentRequestPolicyValidationFailed'
                $Cmdlet = [PSCustomObject]@{ Written = [System.Collections.Generic.List[object]]::new() }
                Add-Member -InputObject $Cmdlet -MemberType ScriptMethod -Name WriteError -Value { param($E) $this.Written.Add($E) }

                $Result = ConvertTo-PolicyValidationError -CaughtError $Record -ResourceType 'group' -Cmdlet $Cmdlet

                $Result | Should -Be $true
                $Cmdlet.Written.Count | Should -Be 1
                $Cmdlet.Written[0].FullyQualifiedErrorId | Should -BeExactly 'RoleAssignmentRequestPolicyValidationFailed'
                $Cmdlet.Written[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::OperationStopped)
                $Cmdlet.Written[0].Exception.Message | Should -BeExactly $Expected
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

        It 'points to -Hours, and to -Until on the Enable-OPIM* cmdlets, instead of -NotAfter, which pim lacks' {
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
            Should -Invoke Write-CmdletError -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It `
                -ParameterFilter {
                    $Message.Message -ceq ('Your PIM policy requires a shorter expiration. ' +
                        'Use -Hours, or -Until on the Enable-OPIM* cmdlets, to ask for a shorter activation.')
                }
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
