BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Wait-OPIMDirectoryRole' {
    BeforeAll {
        Mock -ModuleName Omnicit.PIM Write-Progress { }
        Mock -ModuleName Omnicit.PIM Start-Sleep { }
        Mock -ModuleName Omnicit.PIM Write-CmdletError { }
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
            # Created a day ago, not a minute: the -Parallel poll's Get-Timestamp subtracts
            # [datetime]createdDateTime, which is LOCAL time, from UtcNow
            # (source/Public/Wait-OPIMDirectoryRole.ps1:72, :75). East of UTC a request created a
            # minute ago reads as negative elapsed time, -Timeout 0 never fires, and the stand-in's
            # PendingProvisioning keeps the poll looping. A day stays positive in every time zone.
            $noExpiryRole = [PSCustomObject]@{
                id               = 'req-001'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                createdDateTime  = [DateTime]::UtcNow.AddDays(-1).ToString('o')
                targetScheduleId = 'schedule-001'
                scheduleInfo     = @{ expiration = @{ } }
            }
            $noExpiryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')
        }

        It 'does not call Write-CmdletError' {
            # A Pester mock cannot cross the -Parallel runspace; the registered stand-in is the mock
            # there. With -Timeout 0 the poll still ends in the block's timeout throw.
            Register-OPIMParallelTransportStandIn -Name 'Invoke-MgGraphRequest' -Response @{ value = @(@{ status = 'PendingProvisioning' }) }
            try {
                { $noExpiryRole | Wait-OPIMDirectoryRole -NoSummary -Timeout 0 2>$null } | Should -Throw
                Should -Invoke -ModuleName Omnicit.PIM Write-CmdletError -Times 0 -Scope It
                $Calls = @(Get-OPIMParallelTransportStandInCall)
                $Calls.Count | Should -Be 1 -Because 'the one request has not expired, so its -Parallel poll must reach Graph once'
                foreach ($Call in $Calls) { $Call.Command | Should -Be 'Invoke-MgGraphRequest' }
            } finally {
                Unregister-OPIMParallelTransportStandIn
            }
        }
    }

    Context 'When the role request has a future end date' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            # Created a day ago: see the note in the context above.
            $futureRole = [PSCustomObject]@{
                id               = 'req-future'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                createdDateTime  = [DateTime]::UtcNow.AddDays(-1).ToString('o')
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
            Register-OPIMParallelTransportStandIn -Name 'Invoke-MgGraphRequest' -Response @{ value = @(@{ status = 'PendingProvisioning' }) }
            try {
                { $futureRole | Wait-OPIMDirectoryRole -NoSummary -Timeout 0 2>$null } | Should -Throw
                Should -Invoke -ModuleName Omnicit.PIM Write-CmdletError -Times 0 -Scope It
                $Calls = @(Get-OPIMParallelTransportStandInCall)
                $Calls.Count | Should -Be 1 -Because 'the one request has not expired, so its -Parallel poll must reach Graph once'
                foreach ($Call in $Calls) { $Call.Command | Should -Be 'Invoke-MgGraphRequest' }
            } finally {
                Unregister-OPIMParallelTransportStandIn
            }
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

            # Created a day ago: see the note in the first -Parallel context above.
            $validRole = [PSCustomObject]@{
                id               = 'req-valid'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Security Administrator' }
                createdDateTime  = [DateTime]::UtcNow.AddDays(-1).ToString('o')
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
            Register-OPIMParallelTransportStandIn -Name 'Invoke-MgGraphRequest' -Response @{ value = @(@{ status = 'PendingProvisioning' }) }
            try {
                InModuleScope Omnicit.PIM -ArgumentList $expiredRole, $validRole {
                    param($expired, $valid)
                    try {
                        $expired, $valid | Wait-OPIMDirectoryRole -NoSummary -Timeout 0 2>$null
                    } catch { }
                }
                Should -Invoke -ModuleName Omnicit.PIM Write-CmdletError -Times 1 -Scope It
                $Calls = @(Get-OPIMParallelTransportStandInCall)
                $Calls.Count | Should -Be 1 -Because 'only the request that has not expired reaches the -Parallel poll'
                foreach ($Call in $Calls) { $Call.Command | Should -Be 'Invoke-MgGraphRequest' }
            } finally {
                Unregister-OPIMParallelTransportStandIn
            }
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
