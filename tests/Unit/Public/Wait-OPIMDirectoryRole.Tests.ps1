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
    # OPIM-14 / OPIM-16 (Scope 2): every request is waited for on its own, up to -TimeoutSeconds
    # counted in UTC from its createdDateTime (or from the start of the wait when it has none), with
    # its final status written back. Time is driven by the clock mock: the command reads it with
    # Get-Date -AsUTC, and every read moves it by Clock.Step seconds. The command reads the clock once
    # per request with an end date (the expiry check), once when the wait starts, and once per round
    # for every request still waiting after its poll.
    BeforeAll {
        Mock -ModuleName Omnicit.PIM Write-Progress { }
        Mock -ModuleName Omnicit.PIM Start-Sleep { }
        Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth { }
        $Clock = @{ Now = [datetime]::new(2026, 10, 8, 12, 0, 0, [DateTimeKind]::Utc); Step = 1 }
        Mock -ModuleName Omnicit.PIM Get-Date { $Clock.Now = $Clock.Now.AddSeconds($Clock.Step); $Clock.Now }

        # Plan.Poll: per request id, the statuses its status query answers in turn, the last one
        # repeating; 'Throw' fails the query as Graph does. Plan.EmptyReads: per request id, how many
        # instance queries answer empty before the instance appears (-1: it never appears).
        $Plan = @{ Poll = @{}; Count = @{}; EmptyReads = @{}; InstanceCount = @{} }
        Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
            $Id = [regex]::Match($Uri, "id eq '([^']+)'").Groups[1].Value
            $Seen = [int]$Plan.Count[$Id]
            $Plan.Count[$Id] = $Seen + 1
            # Runaway guard: after 50 polls answer a status no wait goes on for (an unknown one is a
            # failure), so a wait that would never end fails its test instead of hanging the run.
            if ($Seen -ge 50) { return @{ value = @(@{ status = 'RunawayStop' }) } }
            $List = @($Plan.Poll[$Id])
            $Next = $List[[math]::Min($Seen, $List.Count - 1)]
            if ($Next -eq 'Throw') {
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            @{ value = @(@{ status = $Next }) }
        } -ParameterFilter { $Uri -like '*roleAssignmentScheduleRequests*' }
        Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
            $Id = [regex]::Match($Uri, "roleAssignmentScheduleId eq 'schedule-([^']+)'").Groups[1].Value
            $Seen = [int]$Plan.InstanceCount[$Id]
            $Plan.InstanceCount[$Id] = $Seen + 1
            $Empty = if ($Plan.EmptyReads.ContainsKey($Id)) { $Plan.EmptyReads[$Id] } else { 0 }
            # Runaway guard: the instance appears after 50 reads at the latest, so a wait that would
            # never end fails its test instead of hanging the run.
            if ($Seen -lt 50 -and ($Empty -lt 0 -or $Seen -lt $Empty)) { return @{ value = @() } }
            @{ value = @(@{ startDateTime = '2026-10-08T12:00:00Z' }) }
        } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
        Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole {
            foreach ($ScheduleId in 'schedule-req-a', 'schedule-req-b', 'schedule-unrelated') {
                $Instance = [PSCustomObject]@{
                    id                       = "instance-$ScheduleId"
                    roleAssignmentScheduleId = $ScheduleId
                    memberType               = 'Direct'
                    endDateTime              = $null
                }
                $Instance.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')
                $Instance
            }
        } -ParameterFilter { $Activated }

        # A request as Enable-OPIMDirectoryRole returns it. -Created is the createdDateTime as the
        # test gives it (any form); without it the request carries none. -Status adds a status; without
        # it the request has no status property, as a hand-made one may not.
        function New-WaitTestRequest {
            param([string]$Id, [string]$Name = 'Global Administrator', $Created, $EndDateTime, [string]$Status)
            $Expiration = if ($null -ne $EndDateTime) { @{ endDateTime = $EndDateTime } } else { @{ } }
            $Request = [PSCustomObject]@{
                id               = $Id
                roleDefinition   = [PSCustomObject]@{ displayName = $Name }
                directoryScopeId = '/'
                targetScheduleId = "schedule-$Id"
                scheduleInfo     = @{ expiration = $Expiration }
            }
            if ($PSBoundParameters.ContainsKey('Created')) {
                $Request | Add-Member -NotePropertyName createdDateTime -NotePropertyValue $Created
            }
            if ($Status) { $Request | Add-Member -NotePropertyName status -NotePropertyValue $Status }
            $Request.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')
            $Request
        }

        $T0 = [datetime]::new(2026, 10, 8, 12, 0, 0, [DateTimeKind]::Utc)
    }
    BeforeEach {
        # Step 1 by default, so a wait that never ends on its own still reaches its deadline.
        $Clock.Now = $T0
        $Clock.Step = 1
        $Plan.Poll.Clear(); $Plan.Count.Clear(); $Plan.EmptyReads.Clear(); $Plan.InstanceCount.Clear()
        $Plan.Poll['req-a'] = @('Provisioned')
        $Plan.Poll['req-b'] = @('Provisioned')
    }

    Context 'When the role request end date has already expired' {
        It 'writes the expiry error once and polls nothing' {
            $Expired = New-WaitTestRequest -Id 'req-a' -EndDateTime $T0.AddHours(-1).ToString('o')
            $Result = $Expired | Wait-OPIMDirectoryRole -NoSummary -PassThru -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs | Where-Object { "$_" -like '*role end date already expired*' }).Count | Should -Be 1
            @($Result).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It
        }

        It 'reads an end date of Kind Local as the instant it is' {
            # An hour ago, as a local DateTime: expired in every time zone.
            $Expired = New-WaitTestRequest -Id 'req-a' -EndDateTime $T0.AddHours(-1).ToLocalTime()
            $Expired | Wait-OPIMDirectoryRole -NoSummary -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs | Where-Object { "$_" -like '*role end date already expired*' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It
        }
    }

    Context 'When the role request has a future end date or none' {
        It 'writes no expiry error and waits for the request (<Case>)' -ForEach @(
            @{ Case = 'a future end date'; Hours = 1 }
            @{ Case = 'no end date'; Hours = $null }
        ) {
            $EndDateTime = if ($null -ne $Hours) { $T0.AddHours($Hours).ToString('o') } else { $null }
            $Request = New-WaitTestRequest -Id 'req-a' -EndDateTime $EndDateTime
            $Request | Wait-OPIMDirectoryRole -NoSummary -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like "*roleAssignmentScheduleRequests*id eq 'req-a'*"
            }
        }
    }

    Context 'When multiple role requests are piped and one is expired' {
        It 'writes the expiry error once, for the expired role only, and waits for the other' {
            $Expired = New-WaitTestRequest -Id 'req-a' -EndDateTime $T0.AddHours(-1).ToString('o')
            $Valid = New-WaitTestRequest -Id 'req-b' -Name 'Security Administrator' -EndDateTime $T0.AddHours(1).ToString('o')
            $Expired, $Valid | Wait-OPIMDirectoryRole -NoSummary -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs | Where-Object { "$_" -like '*already expired*' }).Count | Should -Be 1
            @($Errs).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like "*roleAssignmentScheduleRequests*id eq 'req-b'*"
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter {
                $Uri -like "*id eq 'req-a'*"
            }
        }
    }

    Context 'When a request stays in progress' {
        It 'stops at -TimeoutSeconds from the start of the wait and returns nothing for it' {
            # No createdDateTime: the deadline counts from the start of the wait. Start read 12:00:30,
            # deadline 12:01:30. Round 1 poll, check 12:01:00; round 2 poll, check 12:01:30: stop.
            $Clock.Step = 30
            $Plan.Poll['req-a'] = @('PendingProvisioning')
            $Request = New-WaitTestRequest -Id 'req-a'
            $Result = $Request | Wait-OPIMDirectoryRole -NoSummary -PassThru -TimeoutSeconds 60 `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationWaitTimedOut,Wait-OPIMDirectoryRole'
            $Errs[-1].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::OperationTimeout)
            $Errs[-1].Exception.Message | Should -BeExactly 'Global Administrator: the activation request has not completed within 60 seconds (last status: PendingProvisioning). The wait has ended; the request stays submitted and may still complete.'
            [object]::ReferenceEquals($Errs[-1].TargetObject, $Request) | Should -BeTrue
            @($Errs).Count | Should -Be 1
            @($Warns).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleRequests*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleInstances*'
            }
        }

        It 'stops at -TimeoutSeconds from the createdDateTime of the request' {
            # Created 12:00:00, deadline 12:01:00. Start read 12:00:30; round 1 poll, check 12:01:00: stop.
            $Clock.Step = 30
            $Plan.Poll['req-a'] = @('PendingProvisioning')
            $Request = New-WaitTestRequest -Id 'req-a' -Created '2026-10-08T12:00:00Z'
            $Request | Wait-OPIMDirectoryRole -NoSummary -TimeoutSeconds 60 -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationWaitTimedOut,Wait-OPIMDirectoryRole'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleRequests*'
            }
        }

        It 'writes the polled status back onto the request it times out, which had none' {
            $Clock.Step = 30
            $Plan.Poll['req-a'] = @('PendingScheduleCreation')
            $Request = New-WaitTestRequest -Id 'req-a'
            $Request.PSObject.Properties['status'] | Should -BeNullOrEmpty
            $Request | Wait-OPIMDirectoryRole -NoSummary -TimeoutSeconds 60 -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].Exception.Message | Should -BeLike '*(last status: PendingScheduleCreation)*'
            $Request.status | Should -BeExactly 'PendingScheduleCreation'
        }

        It 'waits 300 seconds when -TimeoutSeconds is not given' {
            # Start read 12:00:30, deadline 12:05:30: the check after poll 10 reads 12:05:30.
            $Clock.Step = 30
            $Plan.Poll['req-a'] = @('PendingProvisioning')
            New-WaitTestRequest -Id 'req-a' | Wait-OPIMDirectoryRole -NoSummary -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].Exception.Message | Should -BeLike '*within 300 seconds*'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 10 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleRequests*'
            }
        }

        It 'takes the old -Timeout as -TimeoutSeconds' {
            $Clock.Step = 30
            $Plan.Poll['req-a'] = @('PendingProvisioning')
            (Get-Command Wait-OPIMDirectoryRole).Parameters['TimeoutSeconds'].Aliases | Should -Contain 'Timeout'
            New-WaitTestRequest -Id 'req-a' | Wait-OPIMDirectoryRole -NoSummary -Timeout 60 -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].Exception.Message | Should -BeLike '*within 60 seconds*'
        }

        It 'refuses <Parameter> <Value> when the command is bound' -ForEach @(
            @{ Parameter = 'TimeoutSeconds'; Value = 0 }
            @{ Parameter = 'TimeoutSeconds'; Value = 86401 }
            @{ Parameter = 'Timeout'; Value = 0 }
        ) {
            $Request = New-WaitTestRequest -Id 'req-a'
            $Bound = @{ $Parameter = $Value }
            { $Request | Wait-OPIMDirectoryRole -NoSummary @Bound } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError,Wait-OPIMDirectoryRole'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It
        }

        It 'sleeps -Interval seconds between rounds' {
            $Plan.Poll['req-a'] = @('PendingProvisioning', 'PendingProvisioning', 'Provisioned')
            New-WaitTestRequest -Id 'req-a' | Wait-OPIMDirectoryRole -NoSummary -Interval 3 -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 3 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleRequests*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Start-Sleep -Times 2 -Exactly -Scope It -ParameterFilter { $Seconds -eq 3 }
            Should -Invoke -ModuleName Omnicit.PIM Start-Sleep -Times 2 -Exactly -Scope It
        }
    }

    Context 'When the deadline counts from the createdDateTime' {
        # The request was created Seconds before the clock, -TimeoutSeconds 60. Its status query
        # answers PendingProvisioning, then Provisioned. Created 20 seconds before: the deadline is 40
        # seconds ahead and the wait ends normally. Created 90 seconds before: the deadline passed 30
        # seconds ago, so the first round times out. The forms are the ones the JSON reader or a
        # caller can hand over; each must count from the same UTC instant.
        It 'counts from a createdDateTime given as <Form>, <Seconds> seconds before the clock' -ForEach @(
            @{ Form = 'Local DateTime'; Seconds = 20; TimesOut = $false }
            @{ Form = 'Local DateTime'; Seconds = 90; TimesOut = $true }
            @{ Form = 'Unspecified DateTime'; Seconds = 20; TimesOut = $false }
            @{ Form = 'Unspecified DateTime'; Seconds = 90; TimesOut = $true }
            @{ Form = '+00:00 string'; Seconds = 20; TimesOut = $false }
            @{ Form = '+00:00 string'; Seconds = 90; TimesOut = $true }
            @{ Form = '+05:00 string'; Seconds = 20; TimesOut = $false }
            @{ Form = '+05:00 string'; Seconds = 90; TimesOut = $true }
            @{ Form = 'DateTimeOffset'; Seconds = 20; TimesOut = $false }
            @{ Form = 'DateTimeOffset'; Seconds = 90; TimesOut = $true }
        ) {
            $Invariant = [System.Globalization.CultureInfo]::InvariantCulture
            $Instant = $Clock.Now.AddSeconds(-$Seconds)
            $Created = if ($Form -eq 'Local DateTime') {
                $Instant.ToLocalTime()
            } elseif ($Form -eq 'Unspecified DateTime') {
                [datetime]::SpecifyKind($Instant, [DateTimeKind]::Unspecified)
            } elseif ($Form -eq '+00:00 string') {
                $Instant.ToString('yyyy-MM-ddTHH:mm:ss', $Invariant) + '+00:00'
            } elseif ($Form -eq '+05:00 string') {
                $Instant.AddHours(5).ToString('yyyy-MM-ddTHH:mm:ss', $Invariant) + '+05:00'
            } else {
                [DateTimeOffset]::new($Instant).ToOffset([TimeSpan]::FromHours(5))
            }
            $Plan.Poll['req-a'] = @('PendingProvisioning', 'Provisioned')
            $Request = New-WaitTestRequest -Id 'req-a' -Created $Created
            $Request | Wait-OPIMDirectoryRole -NoSummary -TimeoutSeconds 60 -ErrorVariable Errs -ErrorAction SilentlyContinue
            if ($TimesOut) {
                $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationWaitTimedOut,Wait-OPIMDirectoryRole'
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Uri -like '*roleAssignmentScheduleRequests*'
                }
                $Request.status | Should -BeExactly 'PendingProvisioning'
            } else {
                @($Errs).Count | Should -Be 0
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Exactly -Scope It -ParameterFilter {
                    $Uri -like '*roleAssignmentScheduleRequests*'
                }
                $Request.status | Should -BeExactly 'Provisioned'
            }
        }

        It 'counts from the start of the wait when the createdDateTime is <Case>' -ForEach @(
            @{ Case = 'missing'; Missing = $true; Value = $null }
            @{ Case = 'null'; Missing = $false; Value = $null }
            @{ Case = 'empty'; Missing = $false; Value = '' }
            @{ Case = 'unreadable'; Missing = $false; Value = 'not a time' }
        ) {
            # Start read 12:00:30, deadline 12:01:30. Round 1 poll, check 12:01:00: go on. Round 2
            # Provisioned and the instance is there: no timeout on the first round.
            $Clock.Step = 30
            $Plan.Poll['req-a'] = @('PendingProvisioning', 'Provisioned')
            $Request = if ($Missing) { New-WaitTestRequest -Id 'req-a' } else { New-WaitTestRequest -Id 'req-a' -Created $Value }
            $Request | Wait-OPIMDirectoryRole -NoSummary -TimeoutSeconds 60 -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs).Count | Should -Be 0
            $Request.status | Should -BeExactly 'Provisioned'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleRequests*'
            }
        }
    }

    Context 'When the request reaches Provisioned' {
        It 'waits for the instance and writes Provisioned back onto the request' {
            $Request = New-WaitTestRequest -Id 'req-a' -Status 'PendingProvisioning'
            $Result = $Request | Wait-OPIMDirectoryRole -NoSummary -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            @($Errs).Count | Should -Be 0
            $Request.status | Should -BeExactly 'Provisioned'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleRequests*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like "*roleAssignmentScheduleInstances*roleAssignmentScheduleId eq 'schedule-req-a'*"
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 0 -Scope It
        }

        It 'reads the instance again, not the status, until the instance appears' {
            $Plan.EmptyReads['req-a'] = 2
            New-WaitTestRequest -Id 'req-a' | Wait-OPIMDirectoryRole -NoSummary -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleRequests*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 3 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleInstances*'
            }
        }

        It 'times out with the last status Provisioned when the instance never appears' {
            # Start read 12:00:30, deadline 12:01:30: two instance reads, then the timeout.
            $Clock.Step = 30
            $Plan.EmptyReads['req-a'] = -1
            $Request = New-WaitTestRequest -Id 'req-a'
            $Result = $Request | Wait-OPIMDirectoryRole -NoSummary -PassThru -TimeoutSeconds 60 -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationWaitTimedOut,Wait-OPIMDirectoryRole'
            $Errs[-1].Exception.Message | Should -BeLike '*(last status: Provisioned)*'
            $Request.status | Should -BeExactly 'Provisioned'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleInstances*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 0 -Scope It
        }

        It 'accepts -ThrottleLimit and says it has no effect' {
            $Request = New-WaitTestRequest -Id 'req-a'
            $Verbose = @($Request | Wait-OPIMDirectoryRole -NoSummary -ThrottleLimit 3 -Verbose 4>&1 |
                    Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
            @($Verbose | Where-Object { $_.Message -eq '[Wait-OPIMDirectoryRole] -ThrottleLimit 3 has no effect: the requests are polled in sequence.' }).Count |
                Should -Be 1
        }
    }

    Context 'When a request ends without an instance' {
        It 'ends the wait at once for a request that waits for a decision, with one warning' {
            $Plan.Poll['req-a'] = @('PendingApproval', 'Provisioned')
            $Request = New-WaitTestRequest -Id 'req-a'
            $Result = $Request | Wait-OPIMDirectoryRole -NoSummary -PassThru `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            [object]::ReferenceEquals($Result[0], $Request) | Should -BeTrue
            $Request.status | Should -BeExactly 'PendingApproval'
            @($Warns).Count | Should -Be 1
            "$($Warns[0])" | Should -BeExactly 'Global Administrator: the activation request is PendingApproval. It waits for a decision and has not taken effect yet.'
            @($Errs).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleRequests*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleInstances*'
            }
        }

        It 'writes ActivationRequestFailed and returns nothing for a request the poll finds Denied' {
            $Plan.Poll['req-a'] = @('Denied')
            $Request = New-WaitTestRequest -Id 'req-a'
            $Result = $Request | Wait-OPIMDirectoryRole -NoSummary -PassThru `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Wait-OPIMDirectoryRole'
            $Errs[-1].Exception.Message | Should -BeExactly "Global Administrator: the activation request ended with status 'Denied' and did not take effect."
            @($Errs).Count | Should -Be 1
            @($Warns).Count | Should -Be 0
            $Request.status | Should -BeExactly 'Denied'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleRequests*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleInstances*'
            }
        }

        It 'ends the wait for <Status> without waiting for an instance' -ForEach @(
            @{ Status = 'Granted' }
            @{ Status = 'ScheduleCreated' }
        ) {
            $Plan.Poll['req-a'] = @($Status)
            $Request = New-WaitTestRequest -Id 'req-a'
            $Result = $Request | Wait-OPIMDirectoryRole -NoSummary -PassThru `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            [object]::ReferenceEquals($Result[0], $Request) | Should -BeTrue
            $Request.status | Should -BeExactly $Status
            @($Warns).Count | Should -Be 0
            @($Errs).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleInstances*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 0 -Scope It
        }
    }

    Context 'When -PassThru is given' {
        It 'returns the instance of a provisioned request, then the request that ended without one' {
            $Plan.Poll['req-b'] = @('ScheduleCreated')
            $RequestA = New-WaitTestRequest -Id 'req-a'
            $RequestB = New-WaitTestRequest -Id 'req-b' -Name 'Security Administrator'
            $Result = @($RequestA, $RequestB | Wait-OPIMDirectoryRole -NoSummary -PassThru -ErrorVariable Errs -ErrorAction SilentlyContinue)
            @($Errs).Count | Should -Be 0
            $Result.Count | Should -Be 2
            $Result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleInstance'
            $Result[0].roleAssignmentScheduleId | Should -BeExactly 'schedule-req-a'
            [object]::ReferenceEquals($Result[1], $RequestB) | Should -BeTrue
            $Result[1].status | Should -BeExactly 'ScheduleCreated'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 1 -Exactly -Scope It -ParameterFilter { $Activated }
        }

        It 'returns nothing without -PassThru' {
            $Plan.Poll['req-b'] = @('PendingApproval')
            $RequestA = New-WaitTestRequest -Id 'req-a'
            $RequestB = New-WaitTestRequest -Id 'req-b' -Name 'Security Administrator'
            $Result = $RequestA, $RequestB | Wait-OPIMDirectoryRole -NoSummary -WarningVariable Warns -WarningAction SilentlyContinue
            @($Result).Count | Should -Be 0
            @($Warns).Count | Should -Be 1
            $RequestB.status | Should -BeExactly 'PendingApproval'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 0 -Scope It
        }
    }

    Context 'When one of several requests fails, times out or cannot be polled' {
        It 'writes a failed poll as itself and still waits for the other request' {
            $Plan.Poll['req-a'] = @('Throw')
            $Plan.Poll['req-b'] = @('PendingProvisioning', 'Provisioned')
            $RequestA = New-WaitTestRequest -Id 'req-a'
            $RequestB = New-WaitTestRequest -Id 'req-b' -Name 'Security Administrator'
            $Result = @($RequestA, $RequestB | Wait-OPIMDirectoryRole -NoSummary -PassThru -ErrorVariable Errs -ErrorAction SilentlyContinue)
            # -ErrorVariable also collects what the nested mock frames raised on the way out, so the
            # record Wait-OPIMDirectoryRole wrote itself is counted by its id.
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Wait-OPIMDirectoryRole' }).Count | Should -Be 1
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'Activation*' }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like "*roleAssignmentScheduleRequests*id eq 'req-a'*"
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Exactly -Scope It -ParameterFilter {
                $Uri -like "*roleAssignmentScheduleRequests*id eq 'req-b'*"
            }
            $RequestB.status | Should -BeExactly 'Provisioned'
            $Result.Count | Should -Be 1
            $Result[0].roleAssignmentScheduleId | Should -BeExactly 'schedule-req-b'
        }

        It 'writes a failed instance read as itself and still waits for the other request' {
            $Plan.Poll['req-b'] = @('PendingProvisioning', 'Provisioned')
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            } -ParameterFilter { $Uri -like "*roleAssignmentScheduleInstances*schedule-req-a*" }
            $RequestA = New-WaitTestRequest -Id 'req-a'
            $RequestB = New-WaitTestRequest -Id 'req-b' -Name 'Security Administrator'
            $Result = @($RequestA, $RequestB | Wait-OPIMDirectoryRole -NoSummary -PassThru -ErrorVariable Errs -ErrorAction SilentlyContinue)
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Wait-OPIMDirectoryRole' }).Count | Should -Be 1
            $Result.Count | Should -Be 1
            $Result[0].roleAssignmentScheduleId | Should -BeExactly 'schedule-req-b'
        }

        It 'times out one request and still waits for the other (Ruling P3)' {
            # req-a was created an hour ago and is past its deadline after its first poll; req-b counts
            # from the start of the wait and is provisioned on its second poll.
            $Plan.Poll['req-a'] = @('PendingProvisioning')
            $Plan.Poll['req-b'] = @('PendingProvisioning', 'Provisioned')
            $RequestA = New-WaitTestRequest -Id 'req-a' -Created $T0.AddHours(-1).ToString('o')
            $RequestB = New-WaitTestRequest -Id 'req-b' -Name 'Security Administrator'
            $Thrown = $null
            try {
                $Result = @($RequestA, $RequestB | Wait-OPIMDirectoryRole -NoSummary -PassThru -TimeoutSeconds 60 -ErrorVariable Errs -ErrorAction SilentlyContinue)
            } catch {
                $Thrown = $PSItem
            }
            $Thrown | Should -BeNullOrEmpty
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'ActivationWaitTimedOut,Wait-OPIMDirectoryRole' }).Count | Should -Be 1
            $Errs[-1].Exception.Message | Should -BeLike 'Global Administrator: *'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like "*roleAssignmentScheduleRequests*id eq 'req-a'*"
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Exactly -Scope It -ParameterFilter {
                $Uri -like "*roleAssignmentScheduleRequests*id eq 'req-b'*"
            }
            $Result.Count | Should -Be 1
            $Result[0].roleAssignmentScheduleId | Should -BeExactly 'schedule-req-b'
        }

        It 'ends the command with the timeout under -ErrorAction Stop' {
            $Plan.Poll['req-a'] = @('PendingProvisioning')
            $RequestA = New-WaitTestRequest -Id 'req-a' -Created $T0.AddHours(-1).ToString('o')
            $Thrown = $null
            try {
                $RequestA | Wait-OPIMDirectoryRole -NoSummary -TimeoutSeconds 60 -ErrorAction Stop
            } catch {
                $Thrown = $PSItem
            }
            $Thrown.FullyQualifiedErrorId | Should -BeExactly 'ActivationWaitTimedOut,Wait-OPIMDirectoryRole'
        }

        It 'reports a failed request and still waits for the other' {
            $Plan.Poll['req-a'] = @('Failed')
            $Plan.Poll['req-b'] = @('PendingProvisioning', 'Provisioned')
            $RequestA = New-WaitTestRequest -Id 'req-a'
            $RequestB = New-WaitTestRequest -Id 'req-b' -Name 'Security Administrator'
            $Result = @($RequestA, $RequestB | Wait-OPIMDirectoryRole -NoSummary -PassThru -ErrorVariable Errs -ErrorAction SilentlyContinue)
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'ActivationRequestFailed,Wait-OPIMDirectoryRole' }).Count | Should -Be 1
            $Result.Count | Should -Be 1
            $Result[0].roleAssignmentScheduleId | Should -BeExactly 'schedule-req-b'
        }
    }
}
