BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'New-OPIMGraphSessionChangedError' {
    AfterEach {
        InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
    }

    Context 'When the module holds an auth state' {
        BeforeEach {
            # A letter-repeat placeholder tenant, not a version-4 id.
            $Record = InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'aaaaaaaa-0000-0000-0000-00000000000a'; DeviceCode = $false }
                New-OPIMGraphSessionChangedError
            }
        }

        It 'returns an ErrorRecord with the id GraphSessionChanged' {
            $Record | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $Record.FullyQualifiedErrorId | Should -BeExactly 'GraphSessionChanged'
        }

        It 'uses the category AuthenticationError' {
            $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
        }

        It 'targets the module''s own tenant and names it in the message' {
            $Record.TargetObject | Should -BeExactly 'aaaaaaaa-0000-0000-0000-00000000000a'
            $Record.Exception.Message | Should -Match ([regex]::Escape("connected it for tenant 'aaaaaaaa-0000-0000-0000-00000000000a'"))
        }

        It 'carries the exact message' {
            $Record.Exception | Should -BeOfType [System.Exception]
            $Record.Exception.Message | Should -BeExactly (
                "The Microsoft Graph PowerShell SDK session in this PowerShell process has changed since Omnicit.PIM " +
                "connected it for tenant 'aaaaaaaa-0000-0000-0000-00000000000a': another Connect-MgGraph has replaced it. " +
                'Omnicit.PIM does not send its Microsoft Graph calls under a session it did not connect, and it does ' +
                "not switch the session back by itself, since that would move the other session's calls to this " +
                "module's tenant. Run Disconnect-OPIM, which also disconnects that session, and sign in again, or " +
                'use a new PowerShell process.')
        }

        It 'tells the user to run Disconnect-OPIM, not to take the session back' {
            $Record.Exception.Message | Should -Match 'Run Disconnect-OPIM'
            $Record.Exception.Message | Should -Match 'new PowerShell process'
            $Record.Exception.Message | Should -Not -Match 'Reclaim'
        }

        It 'names no tenant but the module''s own' {
            $Guids = @([regex]::Matches($Record.Exception.Message, '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}') |
                    ForEach-Object { $_.Value })
            $Guids | Should -Be @('aaaaaaaa-0000-0000-0000-00000000000a')
        }

        It 'writes nothing to any stream' {
            $Out = InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com' }
                New-OPIMGraphSessionChangedError -Verbose *>&1
            }
            @($Out).Count | Should -Be 1
            @($Out)[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
        }
    }

    Context 'When the module holds no auth state' {
        It 'builds the record with the empty string as its target' {
            $NoState = InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                New-OPIMGraphSessionChangedError
            }
            $NoState.FullyQualifiedErrorId | Should -BeExactly 'GraphSessionChanged'
            $NoState.TargetObject | Should -BeOfType [string]
            $NoState.TargetObject | Should -BeExactly ''
        }
    }
}
