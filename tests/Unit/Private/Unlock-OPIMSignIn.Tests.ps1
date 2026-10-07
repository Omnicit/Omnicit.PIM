BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Unlock-OPIMSignIn' {
    # Lock-OPIMSignIn is reached through a stand-in for Initialize-OPIMAuth, its only caller in source/.
    BeforeEach {
        InModuleScope Omnicit.PIM { $script:_OPIMSignInLatch = $null }
    }
    AfterAll {
        InModuleScope Omnicit.PIM { $script:_OPIMSignInLatch = $null }
    }

    Context 'When a latched command signed in' {
        It 'releases the invocation it is given' {
            $R = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { Lock-OPIMSignIn }
                function Invoke-SignInCaller {
                    [CmdletBinding()]
                    param()
                    $Caller = Initialize-StandIn
                    $Value = $null
                    $HeldBefore = $script:_OPIMSignInLatch.TryGetValue($MyInvocation, [ref]$Value)
                    Unlock-OPIMSignIn -Invocation $Caller
                    @{ HeldBefore = $HeldBefore; HeldAfter = $script:_OPIMSignInLatch.TryGetValue($MyInvocation, [ref]$Value) }
                }
                Invoke-SignInCaller
            }
            $R.HeldBefore | Should -BeTrue
            $R.HeldAfter | Should -BeFalse
        }

        It 'releases only that invocation, keeping an outer command latched' {
            $R = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { Lock-OPIMSignIn }
                function Invoke-NestedCommand {
                    [CmdletBinding()]
                    param()
                    $Caller = Initialize-StandIn
                    Unlock-OPIMSignIn -Invocation $Caller
                }
                function Invoke-OuterCommand {
                    [CmdletBinding()]
                    param()
                    $null = Initialize-StandIn
                    Invoke-NestedCommand
                    $Value = $null
                    $script:_OPIMSignInLatch.TryGetValue($MyInvocation, [ref]$Value)
                }
                Invoke-OuterCommand
            }
            $R | Should -BeTrue
        }

        It 'writes nothing to the pipeline when it releases' {
            $R = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { Lock-OPIMSignIn }
                function Invoke-SignInCaller {
                    [CmdletBinding()]
                    param()
                    $Caller = Initialize-StandIn
                    @(Unlock-OPIMSignIn -Invocation $Caller).Count
                }
                Invoke-SignInCaller
            }
            $R | Should -Be 0
        }
    }

    Context 'When there is nothing to release' {
        It 'does nothing when there is no latch table, and creates none' {
            $R = InModuleScope Omnicit.PIM {
                Remove-Variable -Scope Script -Name _OPIMSignInLatch -ErrorAction Ignore
                $Output = @(Unlock-OPIMSignIn -Invocation $MyInvocation -ErrorAction Stop)
                @{ Count = $Output.Count; TableExists = $null -ne (Get-Variable -Scope Script -Name _OPIMSignInLatch -ErrorAction Ignore) }
            }
            $R.Count | Should -Be 0
            $R.TableExists | Should -BeFalse
        }

        It 'requires the invocation to release' {
            $Parameter = InModuleScope Omnicit.PIM { (Get-Command Unlock-OPIMSignIn).Parameters['Invocation'] }
            $Parameter.ParameterType | Should -Be ([System.Management.Automation.InvocationInfo])
            @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count |
                Should -Be 1
        }
    }
}
