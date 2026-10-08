BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMSignInRefusal' {
    # Lock-OPIMSignIn is reached through a stand-in for Initialize-OPIMAuth, its only caller in source/.
    BeforeEach {
        InModuleScope Omnicit.PIM { $script:_OPIMSignInLatch = $null }
    }
    AfterAll {
        InModuleScope Omnicit.PIM { $script:_OPIMSignInLatch = $null }
    }

    Context 'When the latch table was never created' {
        It 'returns nothing at once, without reading the call stack' {
            Mock -ModuleName Omnicit.PIM Get-PSCallStack { }
            $R = InModuleScope Omnicit.PIM {
                Remove-Variable -Scope Script -Name _OPIMSignInLatch -ErrorAction Ignore
                @(Get-OPIMSignInRefusal)
            }
            $R.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Get-PSCallStack -Times 0

            # Not vacuous: the function calls Microsoft.PowerShell.Utility\Get-PSCallStack, and the same
            # mock does see that module-qualified call once a table exists. Without this the zero above
            # would also pass if the mock could not intercept the call at all.
            $null = InModuleScope Omnicit.PIM {
                $script:_OPIMSignInLatch = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
                @(Get-OPIMSignInRefusal)
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-PSCallStack -Times 1 -Exactly
        }
    }

    Context 'When a command on the call stack is latched' {
        It 'finds the held frame even while a function named Get-PSCallStack that returns nothing is defined' {
            # Both latch helpers call Microsoft.PowerShell.Utility\Get-PSCallStack. An unqualified call
            # would resolve to this global function, which outranks the cmdlet for module code: the latch
            # would then hold nothing, or this function would walk an empty stack and find nothing.
            function global:Get-PSCallStack { }
            try {
                $R = InModuleScope Omnicit.PIM {
                    function Initialize-StandIn { $null = Lock-OPIMSignIn }
                    function Invoke-RefusedCommand {
                        [CmdletBinding()]
                        param()
                        Initialize-StandIn
                        Get-OPIMSignInRefusal
                    }
                    Invoke-RefusedCommand
                }
            } finally {
                # Unqualified on purpose: a scope-qualified function: path removes nothing (see
                # OPIMTransportTripwire.ps1), and from here the nearest definition is the global one.
                Remove-Item -Path 'function:Get-PSCallStack' -ErrorAction SilentlyContinue
            }
            Get-Command -Name Get-PSCallStack -CommandType Function -ErrorAction Ignore | Should -BeNullOrEmpty
            $R | Should -BeExactly 'Invoke-RefusedCommand'
        }

        It 'returns the name of the refused command when that command is the caller' {
            $R = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { $null = Lock-OPIMSignIn }
                function Invoke-RefusedCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                    Get-OPIMSignInRefusal
                }
                Invoke-RefusedCommand
            }
            $R | Should -BeOfType ([string])
            $R | Should -BeExactly 'Invoke-RefusedCommand'
        }

        It 'finds a held frame two levels up the call stack' {
            $R = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { $null = Lock-OPIMSignIn }
                function Invoke-Deeper { Get-OPIMSignInRefusal }
                function Invoke-Nested { Invoke-Deeper }
                function Invoke-RefusedCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                    Invoke-Nested
                }
                Invoke-RefusedCommand
            }
            $R | Should -BeExactly 'Invoke-RefusedCommand'
        }

        It 'names the innermost held command when more than one frame is held' {
            $R = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { $null = Lock-OPIMSignIn }
                function Invoke-InnerRefusedCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                    Get-OPIMSignInRefusal
                }
                function Invoke-OuterRefusedCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                    Invoke-InnerRefusedCommand
                }
                Invoke-OuterRefusedCommand
            }
            $R | Should -BeExactly 'Invoke-InnerRefusedCommand'
        }

        It 'names a held script block that carries no command name ''a script block''' {
            $R = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { $null = Lock-OPIMSignIn }
                & {
                    Initialize-StandIn
                    Get-OPIMSignInRefusal
                }
            }
            $R | Should -BeExactly 'a script block'
        }

        It 'returns nothing after Unlock-OPIMSignIn released the frame' {
            $R = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { Lock-OPIMSignIn }
                function Invoke-RefusedCommand {
                    [CmdletBinding()]
                    param()
                    $Caller = Initialize-StandIn
                    $Before = Get-OPIMSignInRefusal
                    Unlock-OPIMSignIn -Invocation $Caller
                    @{ Before = $Before; After = @(Get-OPIMSignInRefusal) }
                }
                Invoke-RefusedCommand
            }
            # Not vacuous: the same frame was held before the release.
            $R.Before | Should -BeExactly 'Invoke-RefusedCommand'
            $R.After.Count | Should -Be 0
        }

        It 'returns nothing from a later command once the refused one has finished' {
            $First = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { $null = Lock-OPIMSignIn }
                function Invoke-RefusedCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                    Get-OPIMSignInRefusal
                }
                Invoke-RefusedCommand
            }
            $Later = InModuleScope Omnicit.PIM {
                @{ TableExists = $null -ne $script:_OPIMSignInLatch; Refusal = @(Get-OPIMSignInRefusal) }
            }
            $First | Should -BeExactly 'Invoke-RefusedCommand'
            # The table is there, so the later read walked the stack and found no held frame.
            $Later.TableExists | Should -BeTrue
            $Later.Refusal.Count | Should -Be 0
        }
    }

    Context 'When Initialize-OPIMAuth asks with -OutsideCaller (BL-74)' {
        # Initialize-RefusalStandIn stands in for Initialize-OPIMAuth's BL-74 check: frame 0 is
        # Get-OPIMSignInRefusal, frame 1 the stand-in, and frame 2 the command that called it.
        It 'skips the caller''s own latched frame' {
            $R = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { $null = Lock-OPIMSignIn }
                function Initialize-RefusalStandIn { Get-OPIMSignInRefusal -OutsideCaller }
                function Invoke-RefusedCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                    @{ Outside = @(Initialize-RefusalStandIn); Inside = Get-OPIMSignInRefusal }
                }
                Invoke-RefusedCommand
            }
            $R.Outside.Count | Should -Be 0
            # Not vacuous: the caller's frame is held, and a walk from the innermost frame finds it.
            $R.Inside | Should -BeExactly 'Invoke-RefusedCommand'
        }

        It 'finds a latched command outside the caller' {
            $R = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { $null = Lock-OPIMSignIn }
                function Initialize-RefusalStandIn { Get-OPIMSignInRefusal -OutsideCaller }
                function Invoke-NestedCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-RefusalStandIn
                }
                function Invoke-RefusedCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                    Invoke-NestedCommand
                }
                Invoke-RefusedCommand
            }
            $R | Should -BeExactly 'Invoke-RefusedCommand'
        }

        It 'returns nothing when no command outside the caller is latched' {
            $R = InModuleScope Omnicit.PIM {
                function Initialize-RefusalStandIn { Get-OPIMSignInRefusal -OutsideCaller }
                function Invoke-SignInCaller {
                    [CmdletBinding()]
                    param()
                    Initialize-RefusalStandIn
                }
                $script:_OPIMSignInLatch = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
                @(Invoke-SignInCaller)
            }
            $R.Count | Should -Be 0
        }
    }
}
