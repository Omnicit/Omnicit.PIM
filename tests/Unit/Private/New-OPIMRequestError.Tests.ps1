BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'New-OPIMRequestError' {
    Context 'When the request failed (ActivationRequestFailed)' {
        BeforeAll {
            $Request = [PSCustomObject]@{ id = 'req-1'; status = 'Failed' }
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Request = $Request } {
                param($Request)
                New-OPIMRequestError -ErrorId ActivationRequestFailed -Name 'Usage Summary Reports Reader' -Status 'Failed' -Request $Request
            }
        }

        It 'returns an ErrorRecord with the id ActivationRequestFailed' {
            $Record | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $Record.FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed'
        }

        It 'uses the category InvalidResult' {
            $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidResult)
        }

        It 'words the message with the name and the status' {
            $Record.Exception.Message | Should -BeExactly "Usage Summary Reports Reader: the activation request ended with status 'Failed' and did not take effect."
        }

        It 'targets the request object itself' {
            [object]::ReferenceEquals($Record.TargetObject, $Request) | Should -BeTrue
        }

        It 'says deactivation with -Deactivate' {
            $Deactivated = InModuleScope Omnicit.PIM {
                New-OPIMRequestError -ErrorId ActivationRequestFailed -Name 'Role X' -Status 'Failed' -Deactivate
            }
            $Deactivated.Exception.Message | Should -BeExactly "Role X: the deactivation request ended with status 'Failed' and did not take effect."
            $Deactivated.FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed'
        }

        It 'says no status when the status is empty' {
            $Empty = InModuleScope Omnicit.PIM {
                New-OPIMRequestError -ErrorId ActivationRequestFailed -Name 'Role X' -Status ''
            }
            $Empty.Exception.Message | Should -BeExactly 'Role X: the activation request ended with no status and did not take effect.'
        }

        It 'says no status when no status is given' {
            $Missing = InModuleScope Omnicit.PIM {
                New-OPIMRequestError -ErrorId ActivationRequestFailed -Name 'Role X'
            }
            $Missing.Exception.Message | Should -BeExactly 'Role X: the activation request ended with no status and did not take effect.'
        }

        It 'accepts an empty name' {
            $NoName = InModuleScope Omnicit.PIM {
                New-OPIMRequestError -ErrorId ActivationRequestFailed -Name '' -Status 'Denied'
            }
            $NoName.Exception.Message | Should -BeExactly ": the activation request ended with status 'Denied' and did not take effect."
        }

        It 'targets nothing when no request is given' {
            $NoRequest = InModuleScope Omnicit.PIM {
                New-OPIMRequestError -ErrorId ActivationRequestFailed -Name 'Role X' -Status 'Denied'
            }
            $NoRequest.TargetObject | Should -BeNullOrEmpty
        }
    }

    Context 'When the wait timed out (ActivationWaitTimedOut)' {
        BeforeAll {
            $Request = [PSCustomObject]@{ id = 'req-2'; status = 'PendingProvisioning' }
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Request = $Request } {
                param($Request)
                New-OPIMRequestError -ErrorId ActivationWaitTimedOut -Name 'opim-s1-grp - member' -Status 'PendingProvisioning' -TimeoutSeconds 300 -Request $Request
            }
        }

        It 'returns an ErrorRecord with the id ActivationWaitTimedOut' {
            $Record | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $Record.FullyQualifiedErrorId | Should -BeExactly 'ActivationWaitTimedOut'
        }

        It 'uses the category OperationTimeout' {
            $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::OperationTimeout)
        }

        It 'words the message with the name, the limit and the last status' {
            $Record.Exception.Message | Should -BeExactly "opim-s1-grp - member: the activation request has not completed within 300 seconds (last status: PendingProvisioning). The wait has ended; the request stays submitted and may still complete."
        }

        It 'targets the request object itself' {
            [object]::ReferenceEquals($Record.TargetObject, $Request) | Should -BeTrue
        }

        It 'says deactivation with -Deactivate' {
            $Deactivated = InModuleScope Omnicit.PIM {
                New-OPIMRequestError -ErrorId ActivationWaitTimedOut -Name 'Role X' -Status 'PendingRevocation' -TimeoutSeconds 60 -Deactivate
            }
            $Deactivated.Exception.Message | Should -BeLike 'Role X: the deactivation request has not completed within 60 seconds (last status: PendingRevocation).*'
        }
    }

    Context 'When the arguments are wrong' {
        It 'refuses an ErrorId it does not own' {
            { InModuleScope Omnicit.PIM { New-OPIMRequestError -ErrorId SomethingElse -Name 'Role X' } } | Should -Throw
        }
    }

    Context 'When it is called' {
        It 'writes nothing to any stream' {
            $Out = InModuleScope Omnicit.PIM {
                New-OPIMRequestError -ErrorId ActivationRequestFailed -Name 'Role X' -Status 'Denied' -Verbose *>&1
            }
            @($Out).Count | Should -Be 1
            @($Out)[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
        }
    }
}
