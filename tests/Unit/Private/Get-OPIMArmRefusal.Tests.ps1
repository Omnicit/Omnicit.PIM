BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMArmRefusal' {
    BeforeEach {
        InModuleScope Omnicit.PIM { $script:_OPIMSignInLatch = $null }
    }
    AfterAll {
        InModuleScope Omnicit.PIM { $script:_OPIMSignInLatch = $null }
    }

    Context 'When the module holds no sign-in latch' {
        It 'returns nothing and calls nothing' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMSignInRefusal { 'Get-OPIMAzureRole' }
                Mock New-OPIMSignInRefusedError {}
                @(Get-OPIMArmRefusal).Count | Should -Be 0
                Should -Invoke Get-OPIMSignInRefusal -Times 0 -Scope It
                Should -Invoke New-OPIMSignInRefusedError -Times 0 -Scope It
            }
        }
    }

    Context 'When the module holds a sign-in latch' {
        BeforeEach {
            InModuleScope Omnicit.PIM {
                $script:_OPIMSignInLatch = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
            }
        }

        It 'returns nothing when no command is latched' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMSignInRefusal {}
                @(Get-OPIMArmRefusal).Count | Should -Be 0
                Should -Invoke Get-OPIMSignInRefusal -Times 1 -Exactly -Scope It
            }
        }

        It 'returns SignInRefused naming the latched command' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMSignInRefusal { 'Get-OPIMAzureRole' }
                $Record = Get-OPIMArmRefusal
                $Record | Should -BeOfType ([System.Management.Automation.ErrorRecord])
                $Record.FullyQualifiedErrorId | Should -BeExactly 'SignInRefused'
                $Record.TargetObject | Should -BeExactly 'Get-OPIMAzureRole'
                $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
            }
        }

        It 'returns SignInRefused for a command the real latch holds' {
            $R = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { $null = Lock-OPIMSignIn }
                function Invoke-RefusedCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                    Get-OPIMArmRefusal
                }
                Invoke-RefusedCommand
            }
            $R.FullyQualifiedErrorId | Should -BeExactly 'SignInRefused'
            $R.TargetObject | Should -BeExactly 'Invoke-RefusedCommand'
        }
    }

    Context 'When the module is read as it loaded' {
        It 'stands before every Az.Resources call in the module' {
            # Static check on every function as the module loaded it: each call to an Az.Resources
            # schedule command has the gate -- $ArmRefusal = Get-OPIMArmRefusal, then an if on it --
            # among the statements before it in a block that encloses it, within the same function.
            $Az = @('Get-AzRoleEligibilitySchedule', 'Get-AzRoleAssignmentScheduleInstance',
                'New-AzRoleAssignmentScheduleRequest', 'Get-AzRoleAssignmentScheduleRequest')
            $Functions = @(InModuleScope Omnicit.PIM { Get-Command -Module Omnicit.PIM -CommandType Function })
            $IsGate = {
                param($Statement)
                $Statement -is [System.Management.Automation.Language.IfStatementAst] -and
                $Statement.Clauses[0].Item1.Extent.Text -match '\$null\s+-ne\s+\$ArmRefusal'
            }
            $IsGateRead = {
                param($Statement)
                $Statement -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $Statement.Left.Extent.Text -eq '$ArmRefusal' -and
                $Statement.Right.Extent.Text -match '^Get-OPIMArmRefusal$'
            }
            $Calls = foreach ($Function in $Functions) {
                $Ast = $Function.ScriptBlock.Ast
                foreach ($Command in @($Ast.FindAll({
                                param($Node)
                                $Node -is [System.Management.Automation.Language.CommandAst] -and $Az -contains $Node.GetCommandName()
                            }, $true))) {
                    $Gated = $false
                    $Child = $Command
                    $Node = $Command.Parent
                    while ($Node -and -not $Gated -and -not [object]::ReferenceEquals($Node, $Ast)) {
                        if ($Node -is [System.Management.Automation.Language.StatementBlockAst] -or
                            $Node -is [System.Management.Automation.Language.NamedBlockAst]) {
                            $Index = $Node.Statements.IndexOf($Child)
                            for ($I = $Index - 1; $I -ge 1; $I--) {
                                if ((& $IsGate $Node.Statements[$I]) -and (& $IsGateRead $Node.Statements[$I - 1])) { $Gated = $true; break }
                            }
                        }
                        $Child = $Node
                        $Node = $Node.Parent
                    }
                    [pscustomobject]@{ Site = '{0}:{1} {2}' -f $Function.Name, $Command.Extent.StartLineNumber, $Command.GetCommandName(); Gated = $Gated }
                }
            }
            @($Calls).Count | Should -Be 7 -Because 'the walk must reach the four reads in Get-OPIMAzureRole, the two activation and deactivation requests and the -Wait poll'
            @($Calls | Where-Object { -not $_.Gated } | ForEach-Object Site) | Should -BeNullOrEmpty
        }
    }
}
