BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Lock-OPIMSignIn' {
    # Initialize-OPIMAuth is the only caller in source/. These tests call Lock-OPIMSignIn through a
    # stand-in function in its place, so the frame Lock-OPIMSignIn skips is the stand-in's, and the
    # frame it latches is the command that called the stand-in.
    BeforeEach {
        InModuleScope Omnicit.PIM { $script:_OPIMSignInLatch = $null }
    }
    AfterAll {
        InModuleScope Omnicit.PIM { $script:_OPIMSignInLatch = $null }
    }

    Context 'When a command signs in' {
        It 'returns the invocation of the command that called the stand-in for Initialize-OPIMAuth' {
            $R = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { Lock-OPIMSignIn }
                function Invoke-SignInCaller {
                    [CmdletBinding()]
                    param()
                    $Returned = Initialize-StandIn
                    @{
                        Same = [object]::ReferenceEquals($Returned, $MyInvocation)
                        Type = if ($null -ne $Returned) { $Returned.GetType().FullName } else { '' }
                        Name = if ($null -ne $Returned) { [string]$Returned.MyCommand.Name } else { '' }
                    }
                }
                Invoke-SignInCaller
            }
            $R.Type | Should -BeExactly 'System.Management.Automation.InvocationInfo'
            # Neither the stand-in's own frame nor the frame above the caller.
            $R.Name | Should -BeExactly 'Invoke-SignInCaller'
            $R.Same | Should -BeTrue -Because 'the latch key must be the very invocation object a transport finds on the call stack'
        }

        It 'latches the caller''s invocation with the boolean $true and nothing else' {
            $R = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { $null = Lock-OPIMSignIn }
                function Invoke-SignInCaller {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                    $Value = $null
                    $Held = $script:_OPIMSignInLatch.TryGetValue($MyInvocation, [ref]$Value)
                    @{ Held = $Held; Value = $Value }
                }
                Invoke-SignInCaller
            }
            $R.Held | Should -BeTrue
            $R.Value | Should -BeOfType ([bool])
            $R.Value | Should -BeTrue
        }

        It 'creates the latch table on first use when there is none' {
            $R = InModuleScope Omnicit.PIM {
                Remove-Variable -Scope Script -Name _OPIMSignInLatch -ErrorAction Ignore
                function Initialize-StandIn { $null = Lock-OPIMSignIn }
                function Invoke-SignInCaller {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                }
                Invoke-SignInCaller
                if ($null -ne $script:_OPIMSignInLatch) { $script:_OPIMSignInLatch.GetType().FullName } else { '' }
            }
            $R | Should -BeExactly ([System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]).FullName
        }

        It 'latches the caller while a function named Get-PSCallStack that returns nothing is defined' {
            # Lock-OPIMSignIn calls Microsoft.PowerShell.Utility\Get-PSCallStack. An unqualified call
            # would resolve to this global function, which outranks the cmdlet for module code, and
            # find no caller to latch.
            function global:Get-PSCallStack { }
            try {
                $R = InModuleScope Omnicit.PIM {
                    function Initialize-StandIn { $null = Lock-OPIMSignIn }
                    function Invoke-SignInCaller {
                        [CmdletBinding()]
                        param()
                        Initialize-StandIn
                        $Value = $null
                        $script:_OPIMSignInLatch.TryGetValue($MyInvocation, [ref]$Value)
                    }
                    Invoke-SignInCaller
                }
            } finally {
                # Unqualified on purpose: a scope-qualified function: path removes nothing (see
                # OPIMTransportTripwire.ps1), and from here the nearest definition is the global one.
                Remove-Item -Path 'function:Get-PSCallStack' -ErrorAction SilentlyContinue
            }
            Get-Command -Name Get-PSCallStack -CommandType Function -ErrorAction Ignore | Should -BeNullOrEmpty
            $R | Should -BeTrue
        }

        It 'keeps the table and the latch of an outer command when a nested command latches its own' {
            # The nested and pipeline cases A19 rests on: a second sign-in must never replace the
            # table, or every command latched before it would be released.
            $R = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { $null = Lock-OPIMSignIn }
                function Invoke-NestedCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                }
                function Invoke-OuterCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                    $TableBefore = $script:_OPIMSignInLatch
                    Invoke-NestedCommand
                    $Value = $null
                    @{
                        SameTable = [object]::ReferenceEquals($TableBefore, $script:_OPIMSignInLatch)
                        OuterHeld = $script:_OPIMSignInLatch.TryGetValue($MyInvocation, [ref]$Value)
                    }
                }
                Invoke-OuterCommand
            }
            $R.SameTable | Should -BeTrue
            $R.OuterHeld | Should -BeTrue
        }
    }

    Context 'When the module is read as it loaded' {
        BeforeAll {
            # Every function the module defines, private ones included, as the module loaded them.
            $script:Functions = @(InModuleScope Omnicit.PIM { Get-Command -Module Omnicit.PIM -CommandType Function })
        }

        It 'is called by Initialize-OPIMAuth only, once, and Unlock-OPIMSignIn twice' {
            # The latch rule: only Initialize-OPIMAuth latches and releases, at entry and at its two
            # success ends (the cached return and the end of a new sign-in).
            $script:Functions.Count | Should -BeGreaterThan 20 -Because 'the walk must read the module'
            $Calls = foreach ($Function in $script:Functions) {
                $Ast = $Function.ScriptBlock.Ast
                foreach ($Command in @($Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true))) {
                    $Name = $Command.GetCommandName()
                    if ($Name -eq 'Lock-OPIMSignIn' -or $Name -eq 'Unlock-OPIMSignIn') {
                        [pscustomobject]@{ Caller = $Function.Name; Command = $Name }
                    }
                }
            }
            @($Calls | Where-Object Caller -NE 'Initialize-OPIMAuth') | Should -BeNullOrEmpty
            @($Calls | Where-Object Command -EQ 'Lock-OPIMSignIn').Count | Should -Be 1
            @($Calls | Where-Object Command -EQ 'Unlock-OPIMSignIn').Count | Should -Be 2
        }

        It 'is reached through Initialize-OPIMAuth called directly in each caller''s own body' {
            # Lock-OPIMSignIn latches the frame that called Initialize-OPIMAuth. A call from a nested
            # function or a script block would latch a frame that ends at once and leave the command
            # itself unlatched, so every call site must sit in the calling function's own body. The one
            # exception is the transport's own retries: Invoke-OPIMGraphRequest makes every request in
            # its nested Invoke-OPIMGraphSingle (OPIM-13, one call per page), whose frame a refused retry
            # sign-in latches, and whose own latch gate, before the retry is sent, then refuses it --
            # Invoke-OPIMGraphRequest.Tests.ps1 holds that gate and those sends in the nested function.
            $Sites = foreach ($Function in $script:Functions) {
                # A function's ScriptBlock.Ast is its FunctionDefinitionAst; its own body is .Body.
                $Ast = $Function.ScriptBlock.Ast
                $Body = if ($Ast -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $Ast.Body } else { $Ast }
                foreach ($Command in @($Body.FindAll({
                                param($Node)
                                $Node -is [System.Management.Automation.Language.CommandAst] -and
                                $Node.GetCommandName() -eq 'Initialize-OPIMAuth'
                            }, $true))) {
                    $Node = $Command.Parent
                    while ($Node -and $Node -isnot [System.Management.Automation.Language.ScriptBlockAst]) { $Node = $Node.Parent }
                    # The body of a function defined in the wrapper's own body: ScriptBlockAst ->
                    # FunctionDefinitionAst -> the wrapper's named block -> the wrapper's body.
                    $Nested = $Node.Parent
                    [bool]$InTransportRetry = $Function.Name -eq 'Invoke-OPIMGraphRequest' -and
                        $Nested -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                        $Nested.Name -eq 'Invoke-OPIMGraphSingle' -and
                        [object]::ReferenceEquals($Nested.Parent.Parent, $Body)
                    [pscustomobject]@{
                        Caller           = $Function.Name
                        Line             = $Command.Extent.StartLineNumber
                        Direct           = [object]::ReferenceEquals($Node, $Body)
                        InTransportRetry = $InTransportRetry
                    }
                }
            }
            @($Sites).Count | Should -BeGreaterOrEqual 12 -Because 'the walk must reach the pillar cmdlets, Connect-OPIM, Wait-OPIMDirectoryRole and the wrapper retries'
            @($Sites | Where-Object { -not $_.Direct -and -not $_.InTransportRetry } | ForEach-Object { '{0}:{1}' -f $_.Caller, $_.Line }) | Should -BeNullOrEmpty
            @($Sites | Where-Object InTransportRetry).Count | Should -Be 2 -Because 'the claims step-up and the token-rejected retry are the only sign-ins the transport makes'
        }
    }
}
