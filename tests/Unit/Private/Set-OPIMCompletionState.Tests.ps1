BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Set-OPIMCompletionState' {
    # Scope 5b: the module flag both transports read at their decision to wait out throttling. The
    # six completers set it before their listing and clear it in a finally block.
    BeforeEach {
        InModuleScope Omnicit.PIM { $script:_OPIMCompletionInProgress = $null }
    }
    AfterAll {
        InModuleScope Omnicit.PIM { $script:_OPIMCompletionInProgress = $null }
    }

    Context 'When a completion starts and ends' {
        It 'sets the flag to $true for -InProgress $true' {
            InModuleScope Omnicit.PIM {
                Set-OPIMCompletionState -InProgress $true
                $script:_OPIMCompletionInProgress -is [bool] | Should -BeTrue
                $script:_OPIMCompletionInProgress | Should -BeTrue
            }
        }

        It 'clears the flag to $false for -InProgress $false' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMCompletionInProgress = $true
                Set-OPIMCompletionState -InProgress $false
                $script:_OPIMCompletionInProgress -is [bool] | Should -BeTrue -Because 'the flag is cleared to $false, not left unset'
                $script:_OPIMCompletionInProgress | Should -BeFalse
            }
        }

        It 'emits nothing for -InProgress <InProgress>' -ForEach @(
            @{ InProgress = $true }
            @{ InProgress = $false }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ InProgress = $InProgress } {
                param($InProgress)
                @(Set-OPIMCompletionState -InProgress $InProgress).Count | Should -Be 0
            }
        }
    }

    Context 'When the command is read' {
        It 'takes -InProgress as a mandatory [bool]' {
            InModuleScope Omnicit.PIM {
                $Parameter = (Get-Command Set-OPIMCompletionState).Parameters['InProgress']
                $Parameter.ParameterType | Should -Be ([bool])
                @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count | Should -Be 1
            }
        }
    }
}
