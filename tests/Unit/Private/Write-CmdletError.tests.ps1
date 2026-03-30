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
                $exception = [System.Exception]::new('Test error message')
                Write-CmdletError -Message $exception -ErrorId 'TestError' -cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord | Should -Not -BeNullOrEmpty
            }
        }

        It 'creates an ErrorRecord with the provided exception message' {
            InModuleScope Omnicit.PIM {
                $exception = [System.Exception]::new('Test error message')
                Write-CmdletError -Message $exception -ErrorId 'TestError' -cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.Exception.Message | Should -Be 'Test error message'
            }
        }

        It 'creates an ErrorRecord with the provided ErrorId' {
            InModuleScope Omnicit.PIM {
                $exception = [System.Exception]::new('Test error')
                Write-CmdletError -Message $exception -ErrorId 'MyErrorId' -cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.FullyQualifiedErrorId | Should -BeLike '*MyErrorId*'
            }
        }

        It 'uses InvalidOperation as the default category' {
            InModuleScope Omnicit.PIM {
                $exception = [System.Exception]::new('Test error')
                Write-CmdletError -Message $exception -cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
            }
        }

        It 'does not call ThrowTerminatingError' {
            InModuleScope Omnicit.PIM {
                $exception = [System.Exception]::new('Test error')
                Write-CmdletError -Message $exception -cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.TerminatingErrorRecord | Should -BeNullOrEmpty
            }
        }
    }

    Context 'When called with a custom Category' {
        It 'creates an ErrorRecord with the specified category' {
            InModuleScope Omnicit.PIM {
                $exception = [System.Exception]::new('Test error')
                Write-CmdletError -Message $exception -Category 'AuthenticationError' -cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
            }
        }
    }

    Context 'When called with a TargetObject' {
        It 'sets the TargetObject on the ErrorRecord' {
            InModuleScope Omnicit.PIM {
                $exception = [System.Exception]::new('Test error')
                $target = [PSCustomObject]@{ Name = 'TargetResource' }
                Write-CmdletError -Message $exception -TargetObject $target -cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.TargetObject | Should -Be $target
            }
        }
    }

    Context 'When called with -Terminating' {
        It 'throws an exception' {
            InModuleScope Omnicit.PIM {
                $exception = [System.Exception]::new('Fatal error')
                { Write-CmdletError -Message $exception -ErrorId 'FatalError' -Terminating -cmdlet $script:fakeCmdlet } | Should -Throw
            }
        }

        It 'calls ThrowTerminatingError on the provided cmdlet' {
            InModuleScope Omnicit.PIM {
                $exception = [System.Exception]::new('Fatal error')
                { Write-CmdletError -Message $exception -ErrorId 'FatalError' -Terminating -cmdlet $script:fakeCmdlet } | Should -Throw
                $script:fakeCmdlet.TerminatingErrorRecord | Should -Not -BeNullOrEmpty
            }
        }

        It 'throws with the provided exception message' {
            InModuleScope Omnicit.PIM {
                $exception = [System.Exception]::new('Fatal error message')
                { Write-CmdletError -Message $exception -Terminating -cmdlet $script:fakeCmdlet } | Should -Throw '*Fatal error message*'
            }
        }

        It 'does not call WriteError' {
            InModuleScope Omnicit.PIM {
                $exception = [System.Exception]::new('Fatal error')
                { Write-CmdletError -Message $exception -Terminating -cmdlet $script:fakeCmdlet } | Should -Throw
                $script:fakeCmdlet.CapturedErrorRecord | Should -BeNullOrEmpty
            }
        }
    }
}
