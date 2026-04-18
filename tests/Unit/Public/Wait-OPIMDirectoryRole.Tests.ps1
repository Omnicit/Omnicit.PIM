Describe 'Wait-OPIMDirectoryRole' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
        Mock -ModuleName Omnicit.PIM Write-Progress { }
        Mock -ModuleName Omnicit.PIM Start-Sleep { }
        Mock -ModuleName Omnicit.PIM Write-CmdletError { }
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When the role request end date has already expired' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $expiredRole = [PSCustomObject]@{
                id               = 'req-expired'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                createdDateTime  = [DateTime]::UtcNow.AddHours(-2).ToString('o')
                targetScheduleId = 'schedule-expired'
                scheduleInfo     = @{
                    expiration = @{
                        endDateTime = [DateTime]::UtcNow.AddHours(-1).ToString('o')
                    }
                }
            }
            $expiredRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')
        }

        It 'calls Write-CmdletError once with the expiry details' {
            InModuleScope Omnicit.PIM -ArgumentList $expiredRole {
                param($role)
                $role | Wait-OPIMDirectoryRole -NoSummary
            }
            Should -Invoke -ModuleName Omnicit.PIM Write-CmdletError -Times 1 -Scope It
        }
    }

    Context 'When the role request has no expiration date set' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $noExpiryRole = [PSCustomObject]@{
                id               = 'req-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                createdDateTime  = [DateTime]::UtcNow.AddMinutes(-1).ToString('o')
                targetScheduleId = 'schedule-001'
                scheduleInfo     = @{ expiration = @{ } }
            }
            $noExpiryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')
        }

        It 'does not call Write-CmdletError' {
            { $noExpiryRole | Wait-OPIMDirectoryRole -NoSummary -Timeout 0 2>$null } | Should -Throw
            Should -Invoke -ModuleName Omnicit.PIM Write-CmdletError -Times 0 -Scope It
        }
    }

    Context 'When the role request has a future end date' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $futureRole = [PSCustomObject]@{
                id               = 'req-future'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                createdDateTime  = [DateTime]::UtcNow.AddMinutes(-1).ToString('o')
                targetScheduleId = 'schedule-future'
                scheduleInfo     = @{
                    expiration = @{
                        endDateTime = [DateTime]::UtcNow.AddHours(1).ToString('o')
                    }
                }
            }
            $futureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')
        }

        It 'does not call Write-CmdletError' {
            { $futureRole | Wait-OPIMDirectoryRole -NoSummary -Timeout 0 2>$null } | Should -Throw
            Should -Invoke -ModuleName Omnicit.PIM Write-CmdletError -Times 0 -Scope It
        }
    }

    Context 'When multiple role requests are piped and one is expired' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $expiredRole = [PSCustomObject]@{
                id               = 'req-expired'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                createdDateTime  = [DateTime]::UtcNow.AddHours(-2).ToString('o')
                targetScheduleId = 'schedule-expired'
                scheduleInfo     = @{
                    expiration = @{
                        endDateTime = [DateTime]::UtcNow.AddHours(-1).ToString('o')
                    }
                }
            }
            $expiredRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')

            $validRole = [PSCustomObject]@{
                id               = 'req-valid'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Security Administrator' }
                createdDateTime  = [DateTime]::UtcNow.AddMinutes(-1).ToString('o')
                targetScheduleId = 'schedule-valid'
                scheduleInfo     = @{
                    expiration = @{
                        endDateTime = [DateTime]::UtcNow.AddHours(1).ToString('o')
                    }
                }
            }
            $validRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')
        }

        It 'calls Write-CmdletError exactly once for the expired role only' {
            InModuleScope Omnicit.PIM -ArgumentList $expiredRole, $validRole {
                param($expired, $valid)
                try {
                    $expired, $valid | Wait-OPIMDirectoryRole -NoSummary -Timeout 0 2>$null
                } catch { }
            }
            Should -Invoke -ModuleName Omnicit.PIM Write-CmdletError -Times 1 -Scope It
        }
    }

    Context 'When -PassThru is specified' {
        It 'calls Get-OPIMDirectoryRole -Activated to return activated role instances' -Skip {
            # Invoke-OPIMGraphRequest mocks do not cross ForEach-Object -Parallel runspace boundaries.
            # Wait-OPIMDirectoryRole must poll Graph until the role reaches Provisioned status before
            # the -PassThru code path is reachable. This scenario is covered by integration tests.
        }
    }
}
