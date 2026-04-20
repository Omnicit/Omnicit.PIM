Describe 'Write-CmdletError' {
    BeforeAll {
        Import-Module Omnicit.PIM -Force
        InModuleScope Omnicit.PIM {
            $script:fakeCmdlet = [PSCustomObject]@{
                CapturedErrorRecord    = $null
                TerminatingErrorRecord = $null
            }
            $script:fakeCmdlet | Add-Member -MemberType ScriptMethod -Name WriteError -Value {
                param($errorRecord)
                $this.CapturedErrorRecord = $errorRecord
            }
            $script:fakeCmdlet | Add-Member -MemberType ScriptMethod -Name ThrowTerminatingError -Value {
                param($errorRecord)
                $this.TerminatingErrorRecord = $errorRecord
                throw $errorRecord.Exception
            }
        }
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    BeforeEach {
        InModuleScope Omnicit.PIM {
            $script:fakeCmdlet.CapturedErrorRecord    = $null
            $script:fakeCmdlet.TerminatingErrorRecord = $null
        }
    }

    Context 'When called without -Terminating (non-terminating error)' {
        It 'calls WriteError on the provided cmdlet' {
            InModuleScope Omnicit.PIM {
                $Exception = [System.Exception]::new('Test error message')
                Write-CmdletError -Message $Exception -ErrorId 'TestError' -Cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord | Should -Not -BeNullOrEmpty
            }
        }

        It 'creates an ErrorRecord with the provided exception message' {
            InModuleScope Omnicit.PIM {
                $Exception = [System.Exception]::new('Test error message')
                Write-CmdletError -Message $Exception -ErrorId 'TestError' -Cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.Exception.Message | Should -Be 'Test error message'
            }
        }

        It 'creates an ErrorRecord with the provided ErrorId' {
            InModuleScope Omnicit.PIM {
                $Exception = [System.Exception]::new('Test error')
                Write-CmdletError -Message $Exception -ErrorId 'MyErrorId' -Cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.FullyQualifiedErrorId | Should -BeLike '*MyErrorId*'
            }
        }

        It 'uses InvalidOperation as the default category' {
            InModuleScope Omnicit.PIM {
                $Exception = [System.Exception]::new('Test error')
                Write-CmdletError -Message $Exception -Cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
            }
        }

        It 'does not call ThrowTerminatingError' {
            InModuleScope Omnicit.PIM {
                $Exception = [System.Exception]::new('Test error')
                Write-CmdletError -Message $Exception -Cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.TerminatingErrorRecord | Should -BeNullOrEmpty
            }
        }

        It 'accepts -cmdlet alias for backward compatibility' {
            InModuleScope Omnicit.PIM {
                $Exception = [System.Exception]::new('Test error alias')
                Write-CmdletError -Message $Exception -ErrorId 'AliasTest' -cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.Exception.Message | Should -Be 'Test error alias'
            }
        }
    }

    Context 'When called with a custom Category' {
        It 'creates an ErrorRecord with the specified category' {
            InModuleScope Omnicit.PIM {
                $Exception = [System.Exception]::new('Test error')
                Write-CmdletError -Message $Exception -Category 'AuthenticationError' -Cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
            }
        }
    }

    Context 'When called with a TargetObject' {
        It 'sets the TargetObject on the ErrorRecord' {
            InModuleScope Omnicit.PIM {
                $Exception = [System.Exception]::new('Test error')
                $Target = [PSCustomObject]@{ Name = 'TargetResource' }
                Write-CmdletError -Message $Exception -TargetObject $Target -Cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.TargetObject | Should -Be $Target
            }
        }
    }

    Context 'When called with -InnerException' {
        It 'chains the inner exception into the ErrorRecord' {
            InModuleScope Omnicit.PIM {
                $InnerEx  = [System.Exception]::new('Original inner cause')
                $OuterMsg = [System.Exception]::new('Friendly outer message')
                Write-CmdletError -Message $OuterMsg -InnerException $InnerEx -ErrorId 'Chained' -Cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.Exception.Message           | Should -Be 'Friendly outer message'
                $script:fakeCmdlet.CapturedErrorRecord.Exception.InnerException.Message | Should -Be 'Original inner cause'
            }
        }
    }

    Context 'When called with -ErrorRecord (pass-through set)' {
        It 'emits the pre-built ErrorRecord unchanged' {
            InModuleScope Omnicit.PIM {
                $PreBuilt = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Pre-built error'),
                    'PreBuiltId',
                    [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                    $null
                )
                Write-CmdletError -ErrorRecord $PreBuilt -Cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord | Should -Be $PreBuilt
            }
        }

        It 'emits a pre-built ErrorRecord as terminating when -Terminating is specified' {
            InModuleScope Omnicit.PIM {
                $PreBuilt = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Fatal pre-built'),
                    'FatalPreBuilt',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null
                )
                { Write-CmdletError -ErrorRecord $PreBuilt -Terminating -Cmdlet $script:fakeCmdlet } | Should -Throw '*Fatal pre-built*'
                $script:fakeCmdlet.TerminatingErrorRecord | Should -Be $PreBuilt
            }
        }
    }

    Context 'When called with -Terminating' {
        It 'throws an exception' {
            InModuleScope Omnicit.PIM {
                $Exception = [System.Exception]::new('Fatal error')
                { Write-CmdletError -Message $Exception -ErrorId 'FatalError' -Terminating -Cmdlet $script:fakeCmdlet } | Should -Throw
            }
        }

        It 'calls ThrowTerminatingError on the provided cmdlet' {
            InModuleScope Omnicit.PIM {
                $Exception = [System.Exception]::new('Fatal error')
                { Write-CmdletError -Message $Exception -ErrorId 'FatalError' -Terminating -Cmdlet $script:fakeCmdlet } | Should -Throw
                $script:fakeCmdlet.TerminatingErrorRecord | Should -Not -BeNullOrEmpty
            }
        }

        It 'throws with the provided exception message' {
            InModuleScope Omnicit.PIM {
                $Exception = [System.Exception]::new('Fatal error message')
                { Write-CmdletError -Message $Exception -Terminating -Cmdlet $script:fakeCmdlet } | Should -Throw '*Fatal error message*'
            }
        }

        It 'does not call WriteError' {
            InModuleScope Omnicit.PIM {
                $Exception = [System.Exception]::new('Fatal error')
                { Write-CmdletError -Message $Exception -Terminating -Cmdlet $script:fakeCmdlet } | Should -Throw
                $script:fakeCmdlet.CapturedErrorRecord | Should -BeNullOrEmpty
            }
        }
    }
}
