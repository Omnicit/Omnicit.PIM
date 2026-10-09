BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'New-OPIMTenantMismatchError' {
    Context 'When the Graph token is for another tenant' {
        BeforeAll {
            $Record = InModuleScope Omnicit.PIM {
                New-OPIMTenantMismatchError -RequestedTenant 'aaaaaaaa-0000-0000-0000-00000000000a'
            }
        }

        It 'returns a record with the id TenantMismatch' {
            $Record | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $Record.FullyQualifiedErrorId | Should -Be 'TenantMismatch'
        }

        It 'uses the category AuthenticationError' {
            $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
        }

        It 'targets the requested tenant' {
            $Record.TargetObject | Should -Be 'aaaaaaaa-0000-0000-0000-00000000000a'
        }

        It 'names the requested tenant in the message' {
            $Record.Exception.Message | Should -BeLike "*'aaaaaaaa-0000-0000-0000-00000000000a'*"
            $Record.Exception.Message | Should -BeLike '*Microsoft Graph token was issued for another tenant*'
            $Record.Exception.Message | Should -BeLike '*did not use the token and sent nothing*'
        }

        It 'writes nothing to any stream' {
            $Out = InModuleScope Omnicit.PIM {
                New-OPIMTenantMismatchError -RequestedTenant 'contoso.onmicrosoft.com' -Verbose *>&1
            }
            @($Out).Count | Should -Be 1
            @($Out)[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
        }
    }

    Context 'When Azure is signed in to another tenant' {
        It 'names Azure in the Azure message' {
            $Record = InModuleScope Omnicit.PIM {
                New-OPIMTenantMismatchError -RequestedTenant 'contoso.onmicrosoft.com' -Source Azure
            }
            $Record.FullyQualifiedErrorId | Should -Be 'TenantMismatch'
            $Record.Exception.Message | Should -BeLike "Azure is signed in to another tenant than 'contoso.onmicrosoft.com'*"
            $Record.Exception.Message | Should -BeLike '*sends no Azure request*'
        }

        It 'targets the requested tenant and uses the category AuthenticationError' {
            $Record = InModuleScope Omnicit.PIM {
                New-OPIMTenantMismatchError -RequestedTenant 'contoso.onmicrosoft.com' -Source Azure
            }
            $Record.TargetObject | Should -BeExactly 'contoso.onmicrosoft.com'
            $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
        }
    }

    Context 'When the tenant of the Graph token cannot be read' {
        It 'says the tenant could not be read with -Unreadable' {
            $Record = InModuleScope Omnicit.PIM {
                New-OPIMTenantMismatchError -RequestedTenant 'organizations' -Unreadable
            }
            $Record.FullyQualifiedErrorId | Should -Be 'TenantMismatch'
            $Record.Exception.Message | Should -BeLike '*could not be read*'
            $Record.Exception.Message | Should -BeLike "*'organizations'*"
            $Record.Exception.Message | Should -BeLike '*The token was not used and nothing was sent.'
        }

        It 'differs from the message for a Graph token of another tenant' {
            $Records = InModuleScope Omnicit.PIM {
                @(
                    New-OPIMTenantMismatchError -RequestedTenant 'contoso.onmicrosoft.com' -Unreadable
                    New-OPIMTenantMismatchError -RequestedTenant 'contoso.onmicrosoft.com'
                )
            }
            $Records[0].Exception.Message | Should -Not -Be $Records[1].Exception.Message
        }
    }

    Context 'When the tenant of the Azure Resource Manager token cannot be read' {
        BeforeAll {
            $Unreadable = InModuleScope Omnicit.PIM {
                New-OPIMTenantMismatchError -RequestedTenant 'aaaaaaaa-0000-0000-0000-00000000000a' -Source Azure -Unreadable
            }
            $Mismatch = InModuleScope Omnicit.PIM {
                New-OPIMTenantMismatchError -RequestedTenant 'aaaaaaaa-0000-0000-0000-00000000000a' -Source Azure
            }
            $GraphUnreadable = InModuleScope Omnicit.PIM {
                New-OPIMTenantMismatchError -RequestedTenant 'aaaaaaaa-0000-0000-0000-00000000000a' -Unreadable
            }
        }

        It 'keeps the id, the category and the target' {
            $Unreadable.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch'
            $Unreadable.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
            $Unreadable.TargetObject | Should -BeExactly 'aaaaaaaa-0000-0000-0000-00000000000a'
        }

        It 'says the tenant of the Azure Resource Manager token could not be read and names the requested tenant' {
            $Unreadable.Exception.Message | Should -BeLike 'The tenant of the Azure Resource Manager token could not be read*'
            $Unreadable.Exception.Message | Should -BeLike "*'aaaaaaaa-0000-0000-0000-00000000000a', the tenant of this session's Microsoft Graph sign-in*"
            $Unreadable.Exception.Message | Should -BeLike '*The token was not used and nothing was sent to Azure.'
        }

        It 'differs from the Azure message for another tenant and from the Graph message' {
            $Unreadable.Exception.Message | Should -Not -Be $Mismatch.Exception.Message
            $Unreadable.Exception.Message | Should -Not -Be $GraphUnreadable.Exception.Message
        }
    }
}
