BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OPIMTestToken.ps1"

    # The helper takes the token only as a SecureString; each fixture string is converted at runtime.
    function ConvertTo-TestSecureString {
        param([string]$Text)
        [System.Net.NetworkCredential]::new('', $Text).SecurePassword
    }
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMTokenTenantId' {
    Context 'When the token carries a tid claim' {
        It 'returns the tid claim of the token' {
            $Token = ConvertTo-TestSecureString (New-OPIMTestAccessToken -TenantId 'aaaaaaaa-0000-0000-0000-00000000000a')
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenTenantId -AccessToken $Token
            }
            $Result | Should -Be 'aaaaaaaa-0000-0000-0000-00000000000a'
            $Result | Should -BeOfType [string]
        }

        It 'returns the tid in lower case' {
            $Token = ConvertTo-TestSecureString (New-OPIMTestAccessToken -TenantId 'AAAAAAAA-0000-0000-0000-00000000000A')
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenTenantId -AccessToken $Token
            }
            $Result | Should -BeExactly 'aaaaaaaa-0000-0000-0000-00000000000a'
        }

        It 'writes nothing to any stream' {
            $Token = ConvertTo-TestSecureString (New-OPIMTestAccessToken)
            $Out = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenTenantId -AccessToken $Token -Verbose *>&1
            }
            @($Out).Count | Should -Be 1
            $Out | Should -BeExactly '11111111-1111-1111-1111-111111111111'
        }
    }

    Context 'When the tenant cannot be read from the value' {
        It 'returns null for a token without a tid claim' {
            $Token = ConvertTo-TestSecureString (New-OPIMTestAccessToken -NoTenant)
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenTenantId -AccessToken $Token
            }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null for a value that is not a JWT' {
            $Token = ConvertTo-TestSecureString 'not-a-token'
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenTenantId -AccessToken $Token
            }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null for an empty string' {
            $Token = ConvertTo-TestSecureString ''
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenTenantId -AccessToken $Token
            }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null for no token' {
            $Result = InModuleScope Omnicit.PIM { Get-OPIMTokenTenantId -AccessToken $null }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null when the payload is not JSON' {
            # bm90IGpzb24 is the base64url of the text 'not json'.
            $Token = ConvertTo-TestSecureString ('a.' + 'bm90IGpzb24' + '.c')
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenTenantId -AccessToken $Token -ErrorAction Stop
            }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null when the payload is a JSON value other than an object' {
            # WzEsMl0 is the base64url of the JSON array [1,2].
            $Token = ConvertTo-TestSecureString ('a.' + 'WzEsMl0' + '.c')
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenTenantId -AccessToken $Token -ErrorAction Stop
            }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null when the payload is not base64url' {
            $Token = ConvertTo-TestSecureString 'a.%%%%.c'
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenTenantId -AccessToken $Token -ErrorAction Stop
            }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null for a tid that is not a GUID' {
            $Token = ConvertTo-TestSecureString (New-OPIMTestAccessToken -TenantId 'contoso.onmicrosoft.com')
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenTenantId -AccessToken $Token
            }
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'When the token is handed to the helper' {
        # SECURITY rule 5: PowerShell module logging (LogPipelineExecutionDetails, event 4103) records
        # the value of every parameter bound to a command, so neither the plaintext token nor its
        # payload may ever be bound to one.
        It 'accepts the token only as a SecureString' {
            $Type = InModuleScope Omnicit.PIM { (Get-Command Get-OPIMTokenTenantId).Parameters['AccessToken'].ParameterType }
            $Type | Should -Be ([System.Security.SecureString])
        }

        It 'binds no plaintext token to a command' {
            # Static check on the function as the module loaded it. The helper calls no command at
            # all and has no throw statement: it works on the plaintext through .NET method calls
            # only, so no cmdlet or function can receive the token, the payload or a claim value.
            $Ast = InModuleScope Omnicit.PIM { (Get-Command Get-OPIMTokenTenantId).ScriptBlock.Ast }
            $Ast | Should -Not -BeNullOrEmpty
            $Members = @($Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true) |
                    ForEach-Object { $_.Member.Extent.Text })
            $Members | Should -Contain 'FromBase64String' -Because 'the walk must read the decoding body; a walk that reads nothing would pass vacuously'
            $Commands = @($Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) |
                    ForEach-Object { $_.GetCommandName() })
            $Commands | Should -BeNullOrEmpty -Because 'a command bound to the plaintext token or its payload records it in the module log'
            @($Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ThrowStatementAst] }, $true)).Count |
                Should -Be 0 -Because 'the helper never throws, so no error text can carry the payload'
        }
    }
}
