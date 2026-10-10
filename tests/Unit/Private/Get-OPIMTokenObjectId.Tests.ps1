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

Describe 'Get-OPIMTokenObjectId' {
    Context 'When the token carries an oid claim' {
        It 'returns the oid claim of the token' {
            $Token = ConvertTo-TestSecureString (New-OPIMTestAccessToken -ObjectId '22222222-2222-2222-2222-222222222222')
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenObjectId -AccessToken $Token
            }
            $Result | Should -Be '22222222-2222-2222-2222-222222222222'
            $Result | Should -BeOfType [string]
        }

        It 'returns the oid in lower case' {
            $Token = ConvertTo-TestSecureString (New-OPIMTestAccessToken -ObjectId 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA')
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenObjectId -AccessToken $Token
            }
            $Result | Should -BeExactly 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        }

        It 'reads the oid claim and not the tid claim' {
            $Token = ConvertTo-TestSecureString (New-OPIMTestAccessToken -TenantId '33333333-3333-3333-3333-333333333333' -ObjectId '22222222-2222-2222-2222-222222222222')
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenObjectId -AccessToken $Token
            }
            $Result | Should -BeExactly '22222222-2222-2222-2222-222222222222'
        }

        It 'writes nothing to any stream' {
            $Token = ConvertTo-TestSecureString (New-OPIMTestAccessToken)
            $Out = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenObjectId -AccessToken $Token -Verbose *>&1
            }
            @($Out).Count | Should -Be 1
            $Out | Should -BeExactly '00000000-0000-0000-0000-000000000000'
        }
    }

    Context 'When the object id cannot be read from the value' {
        It 'returns null for a token without an oid claim' {
            $Token = ConvertTo-TestSecureString (New-OPIMTestAccessToken -NoObjectId)
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenObjectId -AccessToken $Token
            }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null for a value that is not a JWT' {
            $Token = ConvertTo-TestSecureString 'not-a-token'
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenObjectId -AccessToken $Token
            }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null for an empty string' {
            $Token = ConvertTo-TestSecureString ''
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenObjectId -AccessToken $Token
            }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null for no token' {
            $Result = InModuleScope Omnicit.PIM { Get-OPIMTokenObjectId -AccessToken $null }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null when the payload is not JSON' {
            # bm90IGpzb24 is the base64url of the text 'not json'.
            $Token = ConvertTo-TestSecureString ('a.' + 'bm90IGpzb24' + '.c')
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenObjectId -AccessToken $Token -ErrorAction Stop
            }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null when the payload is a JSON value other than an object' {
            # WzEsMl0 is the base64url of the JSON array [1,2].
            $Token = ConvertTo-TestSecureString ('a.' + 'WzEsMl0' + '.c')
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenObjectId -AccessToken $Token -ErrorAction Stop
            }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null when the payload is not base64url' {
            $Token = ConvertTo-TestSecureString 'a.%%%%.c'
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenObjectId -AccessToken $Token -ErrorAction Stop
            }
            $Result | Should -BeNullOrEmpty
        }

        It 'returns null for an oid that is not a GUID' {
            $Token = ConvertTo-TestSecureString (New-OPIMTestAccessToken -ObjectId 'user@contoso.com')
            $Result = InModuleScope Omnicit.PIM -Parameters @{ Token = $Token } {
                param($Token)
                Get-OPIMTokenObjectId -AccessToken $Token
            }
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'When the token is handed to the helper' {
        # SECURITY rule 5: PowerShell module logging (LogPipelineExecutionDetails, event 4103) records
        # the value of every parameter bound to a command, so neither the plaintext token nor its
        # payload may ever be bound to one.
        It 'accepts the token only as a SecureString' {
            $Type = InModuleScope Omnicit.PIM { (Get-Command Get-OPIMTokenObjectId).Parameters['AccessToken'].ParameterType }
            $Type | Should -Be ([System.Security.SecureString])
        }

        It 'binds no plaintext token to a command' {
            # Static check on the function as the module loaded it. The helper calls no command at
            # all and has no throw statement: it works on the plaintext through .NET method calls
            # only, so no cmdlet or function can receive the token, the payload or a claim value.
            $Ast = InModuleScope Omnicit.PIM { (Get-Command Get-OPIMTokenObjectId).ScriptBlock.Ast }
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
