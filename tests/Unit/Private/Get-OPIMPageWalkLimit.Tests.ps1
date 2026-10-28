BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMPageWalkLimit' {
    # Ported from Omnicit.EntraRBAC (Get-OERPageWalkLimit, #67). The transports' own test files hold
    # what a walk does at the limit, with this function mocked to a small number.
    Context 'When it is called' {
        It 'returns 100000' {
            InModuleScope Omnicit.PIM {
                Get-OPIMPageWalkLimit | Should -Be 100000
            }
        }

        It 'returns exactly one value, typed as an int' {
            InModuleScope Omnicit.PIM {
                $Result = @(Get-OPIMPageWalkLimit)
                $Result.Count | Should -Be 1
                $Result[0] | Should -BeOfType ([int])
            }
        }

        It 'takes no parameters' {
            InModuleScope Omnicit.PIM {
                $Command = Get-Command -Name Get-OPIMPageWalkLimit
                $Own = @($Command.Parameters.Keys | Where-Object {
                        $_ -notin [System.Management.Automation.Cmdlet]::CommonParameters -and
                        $_ -notin [System.Management.Automation.Cmdlet]::OptionalCommonParameters
                    })
                $Own.Count | Should -Be 0
            }
        }

        It 'declares [int] as its output type' {
            InModuleScope Omnicit.PIM {
                @((Get-Command -Name Get-OPIMPageWalkLimit).OutputType.Type) | Should -Be @([int])
            }
        }
    }

    Context 'When the source is read' {
        It 'is called by the two transports and by no other file under source' {
            $SourceRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../../source')).Path
            $Callers = @(Get-ChildItem -Path $SourceRoot -Recurse -File -Filter '*.ps1' |
                    Where-Object { $_.Name -ne 'Get-OPIMPageWalkLimit.ps1' -and
                        (Get-Content -LiteralPath $_.FullName -Raw) -match 'Get-OPIMPageWalkLimit' } |
                    ForEach-Object { $_.Name } | Sort-Object)
            $Callers | Should -Be @('Invoke-OPIMArmRequest.ps1', 'Invoke-OPIMGraphRequest.ps1')
        }
    }
}
