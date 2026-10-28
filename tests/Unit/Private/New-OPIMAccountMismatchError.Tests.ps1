BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'New-OPIMAccountMismatchError' {
    Context 'When the Azure Resource Manager token is for another account' {
        BeforeAll {
            $Record = InModuleScope Omnicit.PIM {
                New-OPIMAccountMismatchError -RequestedTenant 'aaaaaaaa-0000-0000-0000-00000000000a'
            }
        }

        It 'returns a record with the id AccountMismatch' {
            $Record | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $Record.FullyQualifiedErrorId | Should -BeExactly 'AccountMismatch'
        }

        It 'uses the category AuthenticationError' {
            $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
        }

        It 'targets the requested tenant' {
            $Record.TargetObject | Should -BeExactly 'aaaaaaaa-0000-0000-0000-00000000000a'
        }

        It 'names the requested tenant in the message and says what to do' {
            $Record.Exception.Message | Should -BeLike "*'aaaaaaaa-0000-0000-0000-00000000000a'*"
            $Record.Exception.Message | Should -BeLike 'The Azure Resource Manager token was issued to another account than *'
            $Record.Exception.Message | Should -BeLike '*did not use the token and sent nothing to Azure*'
            $Record.Exception.Message | Should -BeLike '*Run Disconnect-OPIM*'
        }

        It 'carries no inner exception' {
            $Record.Exception.InnerException | Should -BeNullOrEmpty
        }

        It 'writes nothing to any stream' {
            $Out = InModuleScope Omnicit.PIM {
                New-OPIMAccountMismatchError -RequestedTenant 'contoso.onmicrosoft.com' -Verbose *>&1
            }
            @($Out).Count | Should -Be 1
            @($Out)[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
        }
    }

    Context 'When the account of the Azure Resource Manager token cannot be read' {
        BeforeAll {
            $Unreadable = InModuleScope Omnicit.PIM {
                New-OPIMAccountMismatchError -RequestedTenant 'aaaaaaaa-0000-0000-0000-00000000000a' -Unreadable
            }
            $Mismatch = InModuleScope Omnicit.PIM {
                New-OPIMAccountMismatchError -RequestedTenant 'aaaaaaaa-0000-0000-0000-00000000000a'
            }
        }

        It 'keeps the id, the category and the target' {
            $Unreadable.FullyQualifiedErrorId | Should -BeExactly 'AccountMismatch'
            $Unreadable.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
            $Unreadable.TargetObject | Should -BeExactly 'aaaaaaaa-0000-0000-0000-00000000000a'
        }

        It 'says the account could not be read and names the requested tenant' {
            $Unreadable.Exception.Message | Should -BeLike 'The account of the Azure Resource Manager token could not be read*'
            $Unreadable.Exception.Message | Should -BeLike "*'aaaaaaaa-0000-0000-0000-00000000000a'*"
            $Unreadable.Exception.Message | Should -BeLike '*The token was not used and nothing was sent to Azure.'
        }

        It 'differs from the message for another account' {
            $Unreadable.Exception.Message | Should -Not -Be $Mismatch.Exception.Message
        }
    }

    Context 'When a Microsoft Graph sign-in that continues the session is answered by another account (-Source Graph)' {
        # EntraRBAC BL-119: Initialize-OPIMAuth refuses a new Microsoft Graph token for the session's
        # tenant and cloud that another account answered.
        BeforeAll {
            $Graph = InModuleScope Omnicit.PIM {
                New-OPIMAccountMismatchError -RequestedTenant 'contoso.onmicrosoft.com' -Source Graph
            }
        }

        It 'returns a record with the id AccountMismatch, the category AuthenticationError and the requested tenant as its target' {
            $Graph | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $Graph.FullyQualifiedErrorId | Should -BeExactly 'AccountMismatch'
            $Graph.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
            $Graph.TargetObject | Should -BeExactly 'contoso.onmicrosoft.com'
            $Graph.Exception.InnerException | Should -BeNullOrEmpty
        }

        It 'says the sign-in was answered by another account, that nothing was used, and to run Disconnect-OPIM' {
            $Graph.Exception.Message | Should -BeExactly ("The new Microsoft Graph sign-in in 'contoso.onmicrosoft.com' was answered by another account than " +
                "the one this session signed in with. Omnicit.PIM did not use the token and sent nothing, and the session stays " +
                "signed in as it was. Sign in with the session's account, or run Disconnect-OPIM and then sign in again to use " +
                'another account.')
        }

        It 'names the requested tenant and nothing that identifies an account' {
            $Message = $Graph.Exception.Message
            $Message | Should -BeLike "*'contoso.onmicrosoft.com'*"
            $Message | Should -Not -Match '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
            $Message | Should -Not -BeLike '*@*'
            $Message | Should -Not -BeLike '*Azure Resource Manager*'
        }

        It 'gives the same message with -Unreadable, which belongs to the Azure source only' {
            $GraphUnreadable = InModuleScope Omnicit.PIM {
                New-OPIMAccountMismatchError -RequestedTenant 'contoso.onmicrosoft.com' -Source Graph -Unreadable
            }
            $GraphUnreadable.Exception.Message | Should -BeExactly $Graph.Exception.Message
        }

        It 'differs from both Azure messages for the same tenant' {
            $Azure = InModuleScope Omnicit.PIM {
                @(
                    New-OPIMAccountMismatchError -RequestedTenant 'contoso.onmicrosoft.com'
                    New-OPIMAccountMismatchError -RequestedTenant 'contoso.onmicrosoft.com' -Unreadable
                )
            }
            foreach ($Record in $Azure) {
                $Record.Exception.Message | Should -Not -Be $Graph.Exception.Message
            }
        }
    }

    Context 'When -Source is not given or names another source' {
        It 'gives the Azure messages by default, for <Name>' -ForEach @(
            @{ Name = 'another account'; Unreadable = $false }
            @{ Name = 'an account that cannot be read'; Unreadable = $true }
        ) {
            $Records = InModuleScope Omnicit.PIM -Parameters @{ Unreadable = $Unreadable } {
                param($Unreadable)
                @{
                    Default = New-OPIMAccountMismatchError -RequestedTenant 'contoso.onmicrosoft.com' -Unreadable:$Unreadable
                    Azure   = New-OPIMAccountMismatchError -RequestedTenant 'contoso.onmicrosoft.com' -Unreadable:$Unreadable -Source Azure
                }
            }
            $Records.Default.Exception.Message | Should -BeExactly $Records.Azure.Exception.Message
            $Records.Default.Exception.Message | Should -BeLike '*Azure Resource Manager token*'
        }

        It 'reads the source in any letter case' {
            $Graph = InModuleScope Omnicit.PIM {
                New-OPIMAccountMismatchError -RequestedTenant 'contoso.onmicrosoft.com' -Source graph
            }
            $Graph.Exception.Message | Should -BeLike 'The new Microsoft Graph sign-in in *'
        }

        It 'refuses a source other than Azure or Graph at binding' {
            $Caught = InModuleScope Omnicit.PIM {
                try {
                    New-OPIMAccountMismatchError -RequestedTenant 'contoso.onmicrosoft.com' -Source 'Arm'
                    $null
                } catch {
                    $PSItem
                }
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationError*'
        }
    }
}
