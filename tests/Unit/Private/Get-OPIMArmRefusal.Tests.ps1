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
    BeforeAll {
        # Two tenants. Letter-repeat placeholders: neither is a version-4 id.
        $TenantA = 'aaaaaaaa-0000-0000-0000-00000000000a'
        $TenantB = 'bbbbbbbb-0000-0000-0000-00000000000b'
    }
    BeforeEach {
        InModuleScope Omnicit.PIM {
            $script:_OPIMSignInLatch = $null
            $script:_OPIMAuthState = $null
        }
    }
    AfterAll {
        InModuleScope Omnicit.PIM {
            $script:_OPIMSignInLatch = $null
            $script:_OPIMAuthState = $null
        }
    }

    Context 'When the module holds no sign-in latch' {
        It 'returns nothing and calls nothing' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMSignInRefusal { 'Get-OPIMAzureRole' }
                Mock New-OPIMSignInRefusedError {}
                Mock Get-AzContext {}
                @(Get-OPIMArmRefusal).Count | Should -Be 0
                Should -Invoke Get-OPIMSignInRefusal -Times 0 -Scope It
                Should -Invoke New-OPIMSignInRefusedError -Times 0 -Scope It
                Should -Invoke Get-AzContext -Times 0 -Scope It
            }
        }
    }

    Context 'When the module holds a sign-in (OPIM-08)' {
        # Azure must be signed in to the tenant of the Graph session's token. The check runs whenever
        # the auth state records that tenant, whether or not a latch table exists yet.
        It 'returns nothing and reads no Az context without a module sign-in (<Name>)' -ForEach @(
            @{ Name = 'no auth state'; State = $null }
            @{ Name = 'a state that holds only the device code mode'; State = @{ DeviceCode = $true } }
            @{ Name = 'a state without the token tenant'; State = @{ TenantId = 'contoso.onmicrosoft.com' } }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ State = $State } {
                param($State)
                $script:_OPIMAuthState = $State
                Mock Get-AzContext {}
                @(Get-OPIMArmRefusal).Count | Should -Be 0
                Should -Invoke Get-AzContext -Times 0 -Scope It
            }
        }

        It 'returns nothing when the Az context is for the session tenant' {
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; TokenTenantId = $TenantA }
                Mock Get-AzContext { [pscustomobject]@{ Tenant = [pscustomobject]@{ Id = 'aaaaaaaa-0000-0000-0000-00000000000a' } } }
                @(Get-OPIMArmRefusal).Count | Should -Be 0
                Should -Invoke Get-AzContext -Times 1 -Exactly -Scope It
            }
        }

        It 'compares the tenant without regard to case' {
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMAuthState = @{ TenantId = $TenantA; TokenTenantId = $TenantA }
                Mock Get-AzContext { [pscustomobject]@{ Tenant = [pscustomobject]@{ Id = 'AAAAAAAA-0000-0000-0000-00000000000A' } } }
                @(Get-OPIMArmRefusal).Count | Should -Be 0
            }
        }

        It 'returns TenantMismatch when the Az context is for another tenant' {
            # Acceptance (OPIM-08): an Az context for another tenant is refused before any ARM call.
            # No latch table exists here, so the tenant check does not hang on the latch check.
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA; TenantB = $TenantB } {
                param($TenantA, $TenantB)
                $script:_OPIMAuthState = @{ TenantId = $TenantA; TokenTenantId = $TenantA }
                Mock Get-AzContext { [pscustomobject]@{ Tenant = [pscustomobject]@{ Id = 'bbbbbbbb-0000-0000-0000-00000000000b' } } }
                $Record = Get-OPIMArmRefusal
                $Record | Should -BeOfType ([System.Management.Automation.ErrorRecord])
                $Record.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch'
                $Record.TargetObject | Should -BeExactly $TenantA
                $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
                $Record.Exception.Message | Should -BeLike "Azure is signed in to another tenant than '$TenantA'*"
                $Record.Exception.Message | Should -Not -BeLike "*$TenantB*"
            }
        }

        It 'returns TenantMismatch naming the token tenant for a session pinned by domain' {
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; TokenTenantId = $TenantA }
                Mock Get-AzContext { [pscustomobject]@{ Tenant = [pscustomobject]@{ Id = 'contoso.onmicrosoft.com' } } }
                $Record = Get-OPIMArmRefusal
                $Record.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch'
                $Record.TargetObject | Should -BeExactly $TenantA
            }
        }

        It 'returns TenantMismatch when there is no Az context' {
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMAuthState = @{ TenantId = $TenantA; TokenTenantId = $TenantA }
                Mock Get-AzContext {}
                $Record = Get-OPIMArmRefusal
                $Record.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch'
                $Record.TargetObject | Should -BeExactly $TenantA
            }
        }

        It 'checks the latch first' {
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMSignInLatch = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
                $script:_OPIMAuthState = @{ TenantId = $TenantA; TokenTenantId = $TenantA }
                Mock Get-OPIMSignInRefusal { 'Get-OPIMAzureRole' }
                Mock Get-AzContext { [pscustomobject]@{ Tenant = [pscustomobject]@{ Id = 'bbbbbbbb-0000-0000-0000-00000000000b' } } }
                $Record = Get-OPIMArmRefusal
                $Record.FullyQualifiedErrorId | Should -BeExactly 'SignInRefused'
                Should -Invoke Get-AzContext -Times 0 -Scope It
            }
        }

        It 'checks the tenant when a latch table exists and no command is latched' {
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $script:_OPIMSignInLatch = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
                $script:_OPIMAuthState = @{ TenantId = $TenantA; TokenTenantId = $TenantA }
                Mock Get-OPIMSignInRefusal {}
                Mock Get-AzContext { [pscustomobject]@{ Tenant = [pscustomobject]@{ Id = 'bbbbbbbb-0000-0000-0000-00000000000b' } } }
                (Get-OPIMArmRefusal).FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch'
                Should -Invoke Get-OPIMSignInRefusal -Times 1 -Exactly -Scope It
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
