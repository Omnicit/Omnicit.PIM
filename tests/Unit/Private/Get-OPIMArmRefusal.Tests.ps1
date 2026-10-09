BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OPIMTestToken.ps1"
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMArmRefusal' {
    BeforeAll {
        # Two tenants and two accounts. Digit- and letter-repeat placeholders: none is a version-4 id.
        $TenantA = '22222222-2222-2222-2222-222222222222'
        $TenantB = '33333333-3333-3333-3333-333333333333'
        $AccountA = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        $AccountB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'

        # An ARM token as Initialize-OPIMAuth keeps it: a SecureString of a NOT-A-REAL-TOKEN fixture.
        function New-ArmTestToken {
            param(
                [string]$TenantId = $TenantA,
                [string]$ObjectId = $AccountA,
                [switch]$NoTenant,
                [switch]$NoObjectId
            )
            $Token = New-OPIMTestAccessToken -TenantId $TenantId -ObjectId $ObjectId -NoTenant:$NoTenant -NoObjectId:$NoObjectId
            [System.Net.NetworkCredential]::new('', $Token).SecurePassword
        }

        # The auth state of a module sign-in to TenantA as AccountA that holds the given ARM token.
        function New-ArmTestState {
            param([AllowNull()]$ArmToken)
            @{
                TenantId         = 'contoso.onmicrosoft.com'
                TokenTenantId    = $TenantA
                ObjectId         = $AccountA
                ArmToken         = $ArmToken
                ArmTokenExpiry   = [DateTime]::UtcNow.AddHours(1)
                ArmTokenTenantId = $TenantA
                ArmTokenObjectId = $AccountA
                ArmResourceUrl   = 'https://management.azure.com'
            }
        }

        function Set-ArmTestState {
            param([AllowNull()]$State)
            & (Get-Module Omnicit.PIM) { param($S) $script:_OPIMAuthState = $S } $State
        }
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
                Mock Get-OPIMTokenTenantId {}
                Mock Get-AzContext {}
                @(Get-OPIMArmRefusal).Count | Should -Be 0
                Should -Invoke Get-OPIMSignInRefusal -Times 0 -Scope It
                Should -Invoke New-OPIMSignInRefusedError -Times 0 -Scope It
                Should -Invoke Get-OPIMTokenTenantId -Times 0 -Scope It
                Should -Invoke Get-AzContext -Times 0 -Scope It
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

        It 'checks the latch first and reads no token for a latched command' {
            Set-ArmTestState -State (New-ArmTestState -ArmToken (New-ArmTestToken -TenantId $TenantB -ObjectId $AccountB))
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMSignInRefusal { 'Get-OPIMAzureRole' }
                Mock Get-OPIMTokenTenantId {}
                Mock Get-OPIMTokenObjectId {}
                $Record = Get-OPIMArmRefusal
                $Record.FullyQualifiedErrorId | Should -BeExactly 'SignInRefused'
                Should -Invoke Get-OPIMTokenTenantId -Times 0 -Scope It
                Should -Invoke Get-OPIMTokenObjectId -Times 0 -Scope It
            }
        }

        It 'checks the token when a latch table exists and no command is latched' {
            Set-ArmTestState -State (New-ArmTestState -ArmToken (New-ArmTestToken -TenantId $TenantB))
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMSignInRefusal {}
                (Get-OPIMArmRefusal).FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch'
                Should -Invoke Get-OPIMSignInRefusal -Times 1 -Exactly -Scope It
            }
        }
    }

    Context 'When the module holds a sign-in and an ARM token (OPIM-08, A3)' {
        # The ARM token's own tid and oid are read before every ARM request and compared with the
        # module's Graph session: the tenant of its token (TokenTenantId) and the account it signed in
        # with (ObjectId). No Az context is read.
        It 'returns nothing when the token is for the session''s tenant and account' {
            Set-ArmTestState -State (New-ArmTestState -ArmToken (New-ArmTestToken))
            InModuleScope Omnicit.PIM {
                @(Get-OPIMArmRefusal).Count | Should -Be 0
            }
        }

        It 'reads the token''s own claims and no Az context' {
            Set-ArmTestState -State (New-ArmTestState -ArmToken (New-ArmTestToken))
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMTokenTenantId { '22222222-2222-2222-2222-222222222222' }
                Mock Get-AzContext { [pscustomobject]@{ Tenant = [pscustomobject]@{ Id = '33333333-3333-3333-3333-333333333333' } } }
                @(Get-OPIMArmRefusal).Count | Should -Be 0
                Should -Invoke Get-OPIMTokenTenantId -Times 1 -Exactly -Scope It -ParameterFilter {
                    $AccessToken -is [System.Security.SecureString] -and $AccessToken.Length -gt 0
                }
                Should -Invoke Get-AzContext -Times 0 -Scope It
            }
        }

        It 'compares the tenant and the account without regard to case' {
            $State = New-ArmTestState -ArmToken (New-ArmTestToken)
            $State.TokenTenantId = $TenantA.ToUpperInvariant()
            $State.ObjectId = $AccountA.ToUpperInvariant()
            Set-ArmTestState -State $State
            InModuleScope Omnicit.PIM {
                @(Get-OPIMArmRefusal).Count | Should -Be 0
            }
        }

        It 'returns TenantMismatch for a token issued for another tenant' {
            Set-ArmTestState -State (New-ArmTestState -ArmToken (New-ArmTestToken -TenantId $TenantB))
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA; TenantB = $TenantB } {
                param($TenantA, $TenantB)
                $Record = Get-OPIMArmRefusal
                $Record | Should -BeOfType ([System.Management.Automation.ErrorRecord])
                $Record.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch'
                $Record.TargetObject | Should -BeExactly $TenantA
                $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
                $Record.Exception.Message | Should -BeLike "Azure is signed in to another tenant than '$TenantA'*"
                $Record.Exception.Message | Should -Not -BeLike "*$TenantB*"
            }
        }

        It 'returns TenantMismatch, unreadable, for a token whose tenant cannot be read' {
            Set-ArmTestState -State (New-ArmTestState -ArmToken (New-ArmTestToken -NoTenant))
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $Record = Get-OPIMArmRefusal
                $Record.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch'
                $Record.TargetObject | Should -BeExactly $TenantA
                $Record.Exception.Message | Should -BeLike 'The tenant of the Azure Resource Manager token could not be read*'
            }
        }

        It 'checks the tenant before the account' {
            Set-ArmTestState -State (New-ArmTestState -ArmToken (New-ArmTestToken -TenantId $TenantB -ObjectId $AccountB))
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMTokenObjectId {}
                (Get-OPIMArmRefusal).FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch'
                Should -Invoke Get-OPIMTokenObjectId -Times 0 -Scope It
            }
        }

        It 'returns AccountMismatch for a token issued to another account' {
            Set-ArmTestState -State (New-ArmTestState -ArmToken (New-ArmTestToken -ObjectId $AccountB))
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA; AccountA = $AccountA; AccountB = $AccountB } {
                param($TenantA, $AccountA, $AccountB)
                $Record = Get-OPIMArmRefusal
                $Record | Should -BeOfType ([System.Management.Automation.ErrorRecord])
                $Record.FullyQualifiedErrorId | Should -BeExactly 'AccountMismatch'
                $Record.TargetObject | Should -BeExactly $TenantA
                $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
                $Record.Exception.Message | Should -BeLike 'The Azure Resource Manager token was issued to another account*'
                $Record.Exception.Message | Should -Not -BeLike "*$AccountA*"
                $Record.Exception.Message | Should -Not -BeLike "*$AccountB*"
            }
        }

        It 'returns AccountMismatch, unreadable, for <Name>' -ForEach @(
            @{ Name = 'a token whose account cannot be read'; NoObjectId = $true; SessionObjectId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; RemoveKey = $false }
            @{ Name = 'a state whose account is null'; NoObjectId = $false; SessionObjectId = $null; RemoveKey = $false }
            @{ Name = 'a state whose account is empty'; NoObjectId = $false; SessionObjectId = ''; RemoveKey = $false }
            @{ Name = 'a state without an account'; NoObjectId = $false; SessionObjectId = $null; RemoveKey = $true }
        ) {
            $State = New-ArmTestState -ArmToken (New-ArmTestToken -NoObjectId:$NoObjectId)
            $State.ObjectId = $SessionObjectId
            if ($RemoveKey) { $State.Remove('ObjectId') }
            Set-ArmTestState -State $State
            InModuleScope Omnicit.PIM -Parameters @{ TenantA = $TenantA } {
                param($TenantA)
                $Record = Get-OPIMArmRefusal
                $Record.FullyQualifiedErrorId | Should -BeExactly 'AccountMismatch'
                $Record.TargetObject | Should -BeExactly $TenantA
                $Record.Exception.Message | Should -BeLike 'The account of the Azure Resource Manager token could not be read*'
            }
        }

        It 'returns nothing and reads no token for <Name>' -ForEach @(
            @{ Name = 'no auth state'; Shape = 'NoState' }
            @{ Name = 'a state that is not a dictionary'; Shape = 'NotDictionary' }
            @{ Name = 'a state that holds only the device code mode'; Shape = 'DeviceCodeOnly' }
            @{ Name = 'a state without the token tenant'; Shape = 'NoTokenTenant' }
            @{ Name = 'a state without an ARM token'; Shape = 'NoArmToken' }
            @{ Name = 'a state whose ARM token is null'; Shape = 'NullArmToken' }
            @{ Name = 'a state whose ARM token is not a SecureString'; Shape = 'StringArmToken' }
            @{ Name = 'a state whose ARM token is empty'; Shape = 'EmptyArmToken' }
        ) {
            # Each shape holds a token for another tenant and account where it holds one at all, so a
            # token that was read would be refused: an empty answer proves none was read.
            $Other = New-ArmTestToken -TenantId $TenantB -ObjectId $AccountB
            $State = switch ($Shape) {
                'NoState' { $null }
                'NotDictionary' { [pscustomobject](New-ArmTestState -ArmToken $Other) }
                'DeviceCodeOnly' { @{ DeviceCode = $true } }
                'NoTokenTenant' { $S = New-ArmTestState -ArmToken $Other; $S.Remove('TokenTenantId'); $S }
                'NoArmToken' { $S = New-ArmTestState -ArmToken $null; $S.Remove('ArmToken'); $S }
                'NullArmToken' { New-ArmTestState -ArmToken $null }
                'StringArmToken' { New-ArmTestState -ArmToken (New-OPIMTestAccessToken -TenantId $TenantB -ObjectId $AccountB) }
                'EmptyArmToken' { New-ArmTestState -ArmToken ([securestring]::new()) }
            }
            Set-ArmTestState -State $State
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMTokenTenantId { '33333333-3333-3333-3333-333333333333' }
                Mock Get-OPIMTokenObjectId { 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' }
                Mock Get-AzContext {}
                @(Get-OPIMArmRefusal).Count | Should -Be 0
                Should -Invoke Get-OPIMTokenTenantId -Times 0 -Scope It
                Should -Invoke Get-OPIMTokenObjectId -Times 0 -Scope It
                Should -Invoke Get-AzContext -Times 0 -Scope It
            }
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
