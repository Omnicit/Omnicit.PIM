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
}
