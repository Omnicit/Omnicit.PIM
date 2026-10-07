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
        Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth { }
        # The instance query answers at once; each context mocks the status query itself.
        Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
            @{ value = @(@{ startDateTime = [datetime]::UtcNow.ToString('o') }) }
        } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }

        # Created a day ago, not a minute: the timeout subtracts [datetime]createdDateTime, which is
        # LOCAL time, from UtcNow (OPIM-16). East of UTC a request created a minute ago reads as
        # negative elapsed time and -Timeout 0 never fires. A day stays positive in every time zone.
        function New-WaitTestRequest {
            param([string]$Id, [string]$Name = 'Global Administrator', [string]$EndDateTime)
            $Expiration = if ($EndDateTime) { @{ endDateTime = $EndDateTime } } else { @{ } }
            $Request = [PSCustomObject]@{
                id               = $Id
                roleDefinition   = [PSCustomObject]@{ displayName = $Name }
                createdDateTime  = [DateTime]::UtcNow.AddDays(-1).ToString('o')
                targetScheduleId = "schedule-$Id"
                scheduleInfo     = @{ expiration = $Expiration }
            }
            $Request.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')
            $Request
        }
    }

    Context 'When the role request end date has already expired' {
        BeforeAll {
            # No request reaches the poll here, so the expiry is the only Write-CmdletError call
            # and a plain mock counts it. The polling contexts below run the real Write-CmdletError:
            # in Pester 6 a call no -ParameterFilter matches throws instead of reaching the command,
            # so a filtered mock cannot let the terminating timeout through.
            Mock -ModuleName Omnicit.PIM Write-CmdletError { }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ value = @(@{ status = 'PendingProvisioning' }) }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleRequests*' }
            $expiredRole = New-WaitTestRequest -Id 'req-expired' -EndDateTime ([DateTime]::UtcNow.AddHours(-1).ToString('o'))
        }

        It 'calls Write-CmdletError once with the expiry details' {
            InModuleScope Omnicit.PIM -ArgumentList $expiredRole {
                param($role)
                $role | Wait-OPIMDirectoryRole -NoSummary
            }
            Should -Invoke -ModuleName Omnicit.PIM Write-CmdletError -Times 1 -Exactly -Scope It -ParameterFilter {
                $Message.Message -like '*role end date already expired*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It
        }
    }

    Context 'When the role request has no expiration date set' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ value = @(@{ status = 'PendingProvisioning' }) }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleRequests*' }
            $noExpiryRole = New-WaitTestRequest -Id 'req-001'
        }

        It 'writes no expiry error and times out on the poll' {
            $Thrown = $null
            try {
                $noExpiryRole | Wait-OPIMDirectoryRole -NoSummary -Timeout 0 -ErrorVariable Errs -ErrorAction SilentlyContinue
            } catch {
                $Thrown = $PSItem
            }
            $Thrown | Should -Not -BeNullOrEmpty -Because 'the timeout is a terminating error'
            $Thrown.Exception.Message | Should -Be 'Global Administrator: Exceeded timeout of 0 seconds waiting for role request to complete'
            $Thrown.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::OperationTimeout)
            @($Errs | Where-Object { "$_" -like '*already expired*' }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It
        }

        It 'throws the timeout with no error id of its own' {
            # Write-CmdletError is called with no -ErrorId, so the id is the command name alone.
            $Thrown = $null
            try { $noExpiryRole | Wait-OPIMDirectoryRole -NoSummary -Timeout 0 } catch { $Thrown = $PSItem }
            $Thrown.FullyQualifiedErrorId | Should -Be 'Wait-OPIMDirectoryRole'
            $Thrown.TargetObject | Should -Be 'req-001'
        }
    }

    Context 'When the role request has a future end date' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ value = @(@{ status = 'PendingProvisioning' }) }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleRequests*' }
            $futureRole = New-WaitTestRequest -Id 'req-future' -EndDateTime ([DateTime]::UtcNow.AddHours(1).ToString('o'))
        }

        It 'writes no expiry error and times out on the poll' {
            $Thrown = $null
            try {
                $futureRole | Wait-OPIMDirectoryRole -NoSummary -Timeout 0 -ErrorVariable Errs -ErrorAction SilentlyContinue
            } catch {
                $Thrown = $PSItem
            }
            $Thrown.Exception.Message | Should -BeLike '*Exceeded timeout of 0 seconds*'
            @($Errs | Where-Object { "$_" -like '*already expired*' }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It
        }
    }

    Context 'When multiple role requests are piped and one is expired' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ value = @(@{ status = 'PendingProvisioning' }) }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleRequests*' }
            $expiredRole = New-WaitTestRequest -Id 'req-expired' -EndDateTime ([DateTime]::UtcNow.AddHours(-1).ToString('o'))
            $validRole = New-WaitTestRequest -Id 'req-valid' -Name 'Security Administrator' -EndDateTime ([DateTime]::UtcNow.AddHours(1).ToString('o'))
        }

        It 'writes the expiry error once, for the expired role only, and polls the other' {
            $Thrown = $null
            try {
                $expiredRole, $validRole | Wait-OPIMDirectoryRole -NoSummary -Timeout 0 -ErrorVariable Errs -ErrorAction SilentlyContinue
            } catch {
                $Thrown = $PSItem
            }
            @($Errs | Where-Object { "$_" -like '*already expired*' }).Count | Should -Be 1
            $Thrown.Exception.Message | Should -BeLike 'Security Administrator: Exceeded timeout*'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like "*id eq 'req-valid'*"
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It
        }
    }

    Context 'When the request reaches Provisioned' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ value = @(@{ status = 'Provisioned' }) }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleRequests*' }
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole {
                foreach ($ScheduleId in 'schedule-req-prov', 'schedule-unrelated') {
                    $Instance = [PSCustomObject]@{ id = "instance-$ScheduleId"; roleAssignmentScheduleId = $ScheduleId }
                    $Instance.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')
                    $Instance
                }
            } -ParameterFilter { $Activated }
            $provisionedRole = New-WaitTestRequest -Id 'req-prov'
        }

        It 'returns after the instance appears' {
            { $provisionedRole | Wait-OPIMDirectoryRole -NoSummary } | Should -Not -Throw
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleRequests*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like "*roleAssignmentScheduleInstances*roleAssignmentScheduleId eq 'schedule-req-prov'*"
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 0 -Scope It
        }

        It 'accepts -ThrottleLimit and says it has no effect' {
            $Verbose = @($provisionedRole | Wait-OPIMDirectoryRole -NoSummary -ThrottleLimit 3 -Verbose 4>&1 |
                    Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
            @($Verbose | Where-Object { $_.Message -eq '[Wait-OPIMDirectoryRole] -ThrottleLimit 3 has no effect: the requests are polled in sequence.' }).Count |
                Should -Be 1
        }

        It 'calls Get-OPIMDirectoryRole -Activated to return activated role instances' {
            $Result = @($provisionedRole | Wait-OPIMDirectoryRole -NoSummary -PassThru)
            $Result.Count | Should -Be 1 -Because 'only the instance of the awaited request is returned'
            $Result[0].roleAssignmentScheduleId | Should -Be 'schedule-req-prov'
            $Result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleInstance'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 1 -Exactly -Scope It -ParameterFilter { $Activated }
        }
    }

    Context 'When two requests are polled in turn' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ value = @(@{ status = 'Provisioned' }) }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleRequests*' }
            $firstRole = New-WaitTestRequest -Id 'req-a'
            $secondRole = New-WaitTestRequest -Id 'req-b' -Name 'Security Administrator'
        }

        It 'polls each request once and waits for each instance' {
            { $firstRole, $secondRole | Wait-OPIMDirectoryRole -NoSummary } | Should -Not -Throw
            foreach ($Id in 'req-a', 'req-b') {
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Uri -like "*roleAssignmentScheduleRequests*id eq '$Id'*"
                }
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Uri -like "*roleAssignmentScheduleId eq 'schedule-$Id'*"
                }
            }
        }
    }

    Context 'When the request fails' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ value = @(@{ status = 'Failed' }) }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleRequests*' }
            $failedRole = New-WaitTestRequest -Id 'req-failed'
        }

        It 'writes a non-terminating error and stops polling that request' {
            $Thrown = $null
            try {
                $failedRole | Wait-OPIMDirectoryRole -NoSummary -ErrorVariable Errs -ErrorAction SilentlyContinue
            } catch {
                $Thrown = $PSItem
            }
            $Thrown | Should -BeNullOrEmpty -Because 'a failed request is a non-terminating error, and the timeout must not follow it'
            $Errs.Count | Should -BeGreaterOrEqual 1
            "$($Errs[0])" | Should -Be 'Global Administrator: Request failed with status Failed'
            $Errs[0].TargetObject | Should -Be 'req-failed'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleRequests*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleInstances*'
            }
        }

        It 'writes the failure with no error id of its own' {
            $failedRole | Wait-OPIMDirectoryRole -NoSummary -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[0].FullyQualifiedErrorId | Should -Be 'Wait-OPIMDirectoryRole'
            $Errs[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
        }
    }

    Context 'When Graph refuses the poll' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('denied'),
                        'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied,
                        $null
                    )
                )
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleRequests*' }
            $refusedRole = New-WaitTestRequest -Id 'req-refused'
        }

        It 'writes the error as itself' {
            $refusedRole | Wait-OPIMDirectoryRole -NoSummary -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -BeGreaterOrEqual 1
            # -ErrorVariable also collects what the nested mock frames raised on the way out (the
            # engine fills it from every frame's error stream), so the record Wait-OPIMDirectoryRole
            # wrote itself is the LAST entry, not the first.
            $Errs[-1] | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'Forbidden,Wait-OPIMDirectoryRole'
            $Errs[-1].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::PermissionDenied)
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleRequests*'
            }
        }
    }
}
