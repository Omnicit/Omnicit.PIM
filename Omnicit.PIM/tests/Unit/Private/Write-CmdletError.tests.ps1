BeforeAll {
    $ModuleName = 'Omnicit.PIM'
    $ModuleManifestName = "$ModuleName.psd1"
    $ModuleManifestPath = "$PSScriptRoot\..\..\..\$ModuleManifestName"
    Import-Module -Name $ModuleManifestPath -Force
}

InModuleScope Omnicit.PIM {
    Describe 'Write-CmdletError' {
        BeforeAll {
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

        BeforeEach {
            $script:fakeCmdlet.CapturedErrorRecord = $null
            $script:fakeCmdlet.TerminatingErrorRecord = $null
        }

        Context 'When called without -Terminating (non-terminating error)' {
            It 'calls WriteError on the provided cmdlet' {
                $exception = [System.Exception]::new('Test error message')
                Write-CmdletError -Message $exception -ErrorId 'TestError' -cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord | Should -Not -BeNullOrEmpty
            }

            It 'creates an ErrorRecord with the provided exception message' {
                $exception = [System.Exception]::new('Test error message')
                Write-CmdletError -Message $exception -ErrorId 'TestError' -cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.Exception.Message | Should -Be 'Test error message'
            }

            It 'creates an ErrorRecord with the provided ErrorId' {
                $exception = [System.Exception]::new('Test error')
                Write-CmdletError -Message $exception -ErrorId 'MyErrorId' -cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.FullyQualifiedErrorId | Should -BeLike '*MyErrorId*'
            }

            It 'uses InvalidOperation as the default category' {
                $exception = [System.Exception]::new('Test error')
                Write-CmdletError -Message $exception -cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
            }

            It 'does not call ThrowTerminatingError' {
                $exception = [System.Exception]::new('Test error')
                Write-CmdletError -Message $exception -cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.TerminatingErrorRecord | Should -BeNullOrEmpty
            }
        }

        Context 'When called with a custom Category' {
            It 'creates an ErrorRecord with the specified category' {
                $exception = [System.Exception]::new('Test error')
                Write-CmdletError -Message $exception -Category 'AuthenticationError' -cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
            }
        }

        Context 'When called with a TargetObject' {
            It 'sets the TargetObject on the ErrorRecord' {
                $exception = [System.Exception]::new('Test error')
                $target = [PSCustomObject]@{ Name = 'TargetResource' }
                Write-CmdletError -Message $exception -TargetObject $target -cmdlet $script:fakeCmdlet
                $script:fakeCmdlet.CapturedErrorRecord.TargetObject | Should -Be $target
            }
        }

        Context 'When called with -Terminating' {
            It 'throws an exception' {
                $exception = [System.Exception]::new('Fatal error')
                { Write-CmdletError -Message $exception -ErrorId 'FatalError' -Terminating -cmdlet $script:fakeCmdlet } | Should -Throw
            }

            It 'calls ThrowTerminatingError on the provided cmdlet' {
                $exception = [System.Exception]::new('Fatal error')
                { Write-CmdletError -Message $exception -ErrorId 'FatalError' -Terminating -cmdlet $script:fakeCmdlet } | Should -Throw
                $script:fakeCmdlet.TerminatingErrorRecord | Should -Not -BeNullOrEmpty
            }

            It 'throws with the provided exception message' {
                $exception = [System.Exception]::new('Fatal error message')
                { Write-CmdletError -Message $exception -Terminating -cmdlet $script:fakeCmdlet } | Should -Throw 'Fatal error message'
            }

            It 'does not call WriteError' {
                $exception = [System.Exception]::new('Fatal error')
                { Write-CmdletError -Message $exception -Terminating -cmdlet $script:fakeCmdlet } | Should -Throw
                $script:fakeCmdlet.CapturedErrorRecord | Should -BeNullOrEmpty
            }
        }
    }
}