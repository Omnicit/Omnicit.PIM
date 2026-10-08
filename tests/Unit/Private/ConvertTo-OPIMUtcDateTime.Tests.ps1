BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'ConvertTo-OPIMUtcDateTime' {
    # The round-trip format ends in Z for Kind Utc only (an offset for Local, nothing for
    # Unspecified), so one string comparison checks the instant and the Kind together: two DateTime
    # values compare equal on their ticks alone, whatever their Kind.
    Context 'When the value is missing or unreadable' {
        It 'returns nothing for <Case>' -ForEach @(
            @{ Case = 'a null';               Value = $null }
            @{ Case = 'an empty string';      Value = '' }
            @{ Case = 'a white-space string'; Value = '   ' }
            @{ Case = 'an unreadable string'; Value = 'not a time' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Value = $Value } {
                param($Value)
                @(ConvertTo-OPIMUtcDateTime -Value $Value).Count | Should -Be 0
            }
        }
    }

    Context 'When the value is a string' {
        It 'returns 10:00 UTC for <Text>' -ForEach @(
            @{ Text = '2026-10-08T10:00:00Z' }
            @{ Text = '2026-10-08T15:00:00+05:00' }
            @{ Text = '2026-10-08T05:00:00-05:00' }
            @{ Text = '2026-10-08T10:00:00' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Text = $Text } {
                param($Text)
                $Result = ConvertTo-OPIMUtcDateTime -Value $Text
                $Result | Should -BeOfType ([datetime])
                $Result.ToString('o') | Should -BeExactly '2026-10-08T10:00:00.0000000Z'
            }
        }

        It 'reads a string from the pipeline' {
            InModuleScope Omnicit.PIM {
                $Result = '2026-10-08T15:00:00+05:00' | ConvertTo-OPIMUtcDateTime
                $Result.ToString('o') | Should -BeExactly '2026-10-08T10:00:00.0000000Z'
            }
        }
    }

    Context 'When the value is a DateTime' {
        It 'converts a DateTime of Kind Local to the same instant in UTC' {
            InModuleScope Omnicit.PIM {
                $Local = [datetime]::new(2026, 10, 8, 10, 0, 0, [DateTimeKind]::Utc).ToLocalTime()
                $Local.Kind | Should -Be ([DateTimeKind]::Local)
                $Result = ConvertTo-OPIMUtcDateTime -Value $Local
                $Result.ToString('o') | Should -BeExactly '2026-10-08T10:00:00.0000000Z'
            }
        }

        It 'returns a DateTime of Kind Utc as it is' {
            InModuleScope Omnicit.PIM {
                $Utc = [datetime]::new(2026, 10, 8, 10, 0, 0, [DateTimeKind]::Utc)
                $Result = ConvertTo-OPIMUtcDateTime -Value $Utc
                $Result.ToString('o') | Should -BeExactly '2026-10-08T10:00:00.0000000Z'
            }
        }

        It 'takes a DateTime of Kind Unspecified as UTC' {
            InModuleScope Omnicit.PIM {
                $Unspecified = [datetime]::new(2026, 10, 8, 10, 0, 0, [DateTimeKind]::Unspecified)
                $Result = ConvertTo-OPIMUtcDateTime -Value $Unspecified
                $Result.ToString('o') | Should -BeExactly '2026-10-08T10:00:00.0000000Z'
            }
        }
    }

    Context 'When the value is a DateTimeOffset' {
        It 'returns its UTC instant' {
            InModuleScope Omnicit.PIM {
                $Offset = [DateTimeOffset]::new(2026, 10, 8, 15, 0, 0, [TimeSpan]::FromHours(5))
                $Result = ConvertTo-OPIMUtcDateTime -Value $Offset
                $Result | Should -BeOfType ([datetime])
                $Result.ToString('o') | Should -BeExactly '2026-10-08T10:00:00.0000000Z'
            }
        }
    }
}
