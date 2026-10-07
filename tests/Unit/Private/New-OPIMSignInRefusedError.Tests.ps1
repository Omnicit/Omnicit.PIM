BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'New-OPIMSignInRefusedError' {
    Context 'When it builds the record for a refused command' {
        BeforeAll {
            $script:Record = InModuleScope Omnicit.PIM { New-OPIMSignInRefusedError -Command 'Get-OPIMDirectoryRole' }
        }

        It 'returns an ErrorRecord' {
            $script:Record | Should -BeOfType ([System.Management.Automation.ErrorRecord])
        }

        It 'carries the id SignInRefused' {
            $script:Record.FullyQualifiedErrorId | Should -BeExactly 'SignInRefused'
        }

        It 'carries the category AuthenticationError' {
            $script:Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
        }

        It 'targets the refused command' {
            $script:Record.TargetObject | Should -BeOfType ([string])
            $script:Record.TargetObject | Should -BeExactly 'Get-OPIMDirectoryRole'
        }

        It 'carries the exact message' {
            $script:Record.Exception | Should -BeOfType ([System.Exception])
            $script:Record.Exception.Message | Should -BeExactly (
                "The module's sign-in for this command was refused, so Omnicit.PIM sends nothing for this command: " +
                'this request was not sent. Run Connect-OPIM, or run a new command whose sign-in succeeds, to send requests again.')
        }

        It 'keeps the same message whatever command it targets' {
            $Other = InModuleScope Omnicit.PIM { New-OPIMSignInRefusedError -Command 'a script block' }
            $Other.TargetObject | Should -BeExactly 'a script block'
            $Other.Exception.Message | Should -BeExactly $script:Record.Exception.Message
        }
    }

    Context 'When it is read as a command' {
        It 'requires the command it targets' {
            $Parameter = InModuleScope Omnicit.PIM { (Get-Command New-OPIMSignInRefusedError).Parameters['Command'] }
            $Parameter.ParameterType | Should -Be ([string])
            @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count |
                Should -Be 1
        }

        It 'takes no other parameter of its own' {
            # The EntraRBAC model's -SessionUncertain variant (A10) is not ported.
            $Own = InModuleScope Omnicit.PIM {
                $Common = [System.Management.Automation.Cmdlet]::CommonParameters + [System.Management.Automation.Cmdlet]::OptionalCommonParameters
                @((Get-Command New-OPIMSignInRefusedError).Parameters.Keys | Where-Object { $Common -notcontains $_ })
            }
            ($Own -join ', ') | Should -BeExactly 'Command'
        }
    }
}
