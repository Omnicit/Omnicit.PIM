BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Enable-OPIMEntraIDGroup' {
    BeforeAll {
        # A post as Get-OPIMEntraIDGroup lists it, typed as it types it. Each carries the properties
        # the self-referencing ScriptProperties of its type read (Omnicit.PIM.Types.ps1xml): the
        # eligibility type reads accessId and memberType, the instance type accessId, assignmentType
        # and endDateTime, and a typed fake without them overflows the stack when a failing assertion
        # formats it.
        function New-GroupPost {
            param([string]$Id, [string]$GroupId, [string]$Name, [string]$AccessId, [switch]$Active)
            $Post = [PSCustomObject]@{
                id           = $Id
                groupId      = $GroupId
                principalId  = 'principal-001'
                accessId     = $AccessId
                memberType   = 'direct'
                group        = [PSCustomObject]@{ displayName = $Name }
                principal    = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
                scheduleInfo = $null
            }
            if ($Active) {
                $Post | Add-Member -NotePropertyName assignmentType -NotePropertyValue 'activated'
                $Post | Add-Member -NotePropertyName endDateTime -NotePropertyValue $null
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleInstance')
            } else {
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
            }
            $Post
        }
    }

    Context 'When called with -GroupName (happy path)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id          = 'req-001'
                    action      = 'selfActivate'
                    accessId    = 'member'
                    groupId     = 'group-001'
                    principalId = 'principal-001'
                    status      = 'Provisioned'
                    group       = @{ displayName = 'Finance Team' }
                }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'calls Resolve-OPIMSchedule for the supplied group name' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It
        }

        It 'calls Invoke-OPIMGraphRequest with POST to the group assignmentScheduleRequests endpoint' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*privilegedAccess/group/assignmentScheduleRequests*'
            }
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.GroupAssignmentScheduleRequest' {
            $Result = Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
        }

        It 'sends selfActivate as the action in the request body' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.action -eq 'selfActivate'
            }
        }

        It 'sends the accessId from the resolved group in the request body' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.accessId -eq 'member'
            }
        }

        It 'uses AfterDuration expiration type by default' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.type -eq 'AfterDuration'
            }
        }

        It 'passes a PT1H ISO 8601 duration when -Hours defaults to 1' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.duration -eq 'PT1H'
            }
        }
    }

    Context 'When called with multiple group names' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeGroupA = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            $fakeGroupB = [PSCustomObject]@{
                id          = 'elig-002'
                accessId    = 'owner'
                groupId     = 'group-002'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'DevOps Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule {
                if ($Name -like '*elig-001*') { return $fakeGroupA } else { return $fakeGroupB }
            }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id     = [System.Guid]::NewGuid().ToString()
                    action = 'selfActivate'
                    status = 'Provisioned'
                    group  = @{ displayName = 'Team' }
                }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'calls Invoke-OPIMGraphRequest once per group name supplied' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)', 'DevOps Team (elig-002)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When called with pipeline input (-Group parameter set)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-002'
                accessId    = 'owner'
                groupId     = 'group-002'
                principalId = 'principal-002'
                group       = [PSCustomObject]@{ displayName = 'DevOps Team' }
            }
            $fakeGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id          = 'req-002'
                    action      = 'selfActivate'
                    accessId    = 'owner'
                    groupId     = 'group-002'
                    principalId = 'principal-002'
                    status      = 'Provisioned'
                    group       = @{ displayName = 'DevOps Team' }
                }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'calls Invoke-OPIMGraphRequest with the groupId and principalId from the piped group' {
            $fakeGroup | Enable-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and
                $Body.groupId -eq 'group-002' -and
                $Body.principalId -eq 'principal-002'
            }
        }

        It 'calls Invoke-OPIMGraphRequest with the accessId from the piped group' {
            $fakeGroup | Enable-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.accessId -eq 'owner'
            }
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.GroupAssignmentScheduleRequest' {
            $Result = $fakeGroup | Enable-OPIMEntraIDGroup
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
        }
    }

    Context 'When -Until is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            $script:UntilDateTime = [DateTime]::Now.AddHours(3)
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id     = 'req-001'
                    action = 'selfActivate'
                    status = 'Provisioned'
                    group  = @{ displayName = 'Finance Team' }
                }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'uses AfterDateTime expiration type when -Until is provided' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -Until $script:UntilDateTime
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.type -eq 'AfterDateTime'
            }
        }

        It 'does not include a duration in the request body when -Until is specified' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -Until $script:UntilDateTime
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and -not $Body.scheduleInfo.expiration.duration
            }
        }
    }

    Context 'When -Hours overrides the default duration' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id     = 'req-001'
                    action = 'selfActivate'
                    status = 'Provisioned'
                    group  = @{ displayName = 'Finance Team' }
                }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'passes PT4H ISO 8601 duration when -Hours 4 is specified' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -Hours 4
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.duration -eq 'PT4H'
            }
        }

        It 'passes PT8H ISO 8601 duration when -Hours 8 is specified' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -Hours 8
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.duration -eq 'PT8H'
            }
        }
    }

    Context 'When ticket information is provided' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id     = 'req-001'
                    action = 'selfActivate'
                    status = 'Provisioned'
                    group  = @{ displayName = 'Finance Team' }
                }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'passes TicketNumber and TicketSystem in the ticketInfo request body' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -TicketNumber 'INC-456' -TicketSystem 'Jira'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and
                $Body.ticketInfo.ticketNumber -eq 'INC-456' -and
                $Body.ticketInfo.ticketSystem -eq 'Jira'
            }
        }
    }

    Context 'When -Justification is provided' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id     = 'req-001'
                    action = 'selfActivate'
                    status = 'Provisioned'
                    group  = @{ displayName = 'Finance Team' }
                }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'passes the justification text in the request body' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -Justification 'Year-end reporting'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.justification -eq 'Year-end reporting'
            }
        }
    }

    Context 'When -WhatIf is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest { } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not call Invoke-OPIMGraphRequest when -WhatIf is specified' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It
        }
    }

    Context 'When the Graph API returns a general error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"GeneralError","message":"An unexpected error occurred."}}'
                )
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not throw a terminating error' {
            { Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When the API returns a JustificationRule policy violation' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"RoleAssignmentRequestPolicyValidationFailed","message":"Policy validation failed: JustificationRule requires a justification."}}'
                )
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'sets error details with a hint to use the -Justification parameter' {
            $Errors = @()
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].Exception.Message | Should -BeLike '*-Justification*'
        }
    }

    Context 'When the API returns an ExpirationRule policy violation' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"RoleAssignmentRequestPolicyValidationFailed","message":"Policy validation failed: ExpirationRule duration exceeded."}}'
                )
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'sets error details with a hint to use the -NotAfter parameter' {
            $Errors = @()
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].Exception.Message | Should -BeLike '*-NotAfter*'
        }
    }

    Context 'When -Wait is specified' {
        # OPIM-14 (Scope 2): the wait polls only while the request is in progress, sleeps before each
        # poll, stops at -TimeoutSeconds counted in UTC, writes the final status back, and reports each
        # group on its own. Time is driven by the clock mock: every Get-Date read moves it by Step.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $PostA = New-GroupPost -Id 'grp-elig-001' -GroupId 'g-1' -Name 'opim-s1-grp' -AccessId 'member'
            $PostB = New-GroupPost -Id 'grp-elig-002' -GroupId 'g-2' -Name 'opim-s1-other' -AccessId 'member'
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule {
                if ($Name -eq 'opim-s1-grp') { $PostA } else { $PostB }
            }
            # Plan.Post is the status the POST answers per groupId; Plan.Poll the statuses the polls of
            # that request answer in turn, the last one repeating; 'Throw' fails the poll as Graph does.
            $Plan = @{ Post = @{}; Poll = @{}; Count = @{} }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = "req-$($Body.groupId)"; action = 'selfActivate'; accessId = 'member'; groupId = $Body.groupId; principalId = 'principal-001'; status = $Plan.Post[$Body.groupId] }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $GroupId = ($Uri -split '/req-')[-1]
                $Seen = [int]$Plan.Count[$GroupId]
                $Plan.Count[$GroupId] = $Seen + 1
                # Runaway guard: after 50 polls answer a status no wait goes on for (an unknown one is
                # a failure), so a wait that would never end fails its test instead of hanging the run.
                if ($Seen -ge 50) { return @{ id = "req-$GroupId"; groupId = $GroupId; status = 'RunawayStop' } }
                $List = @($Plan.Poll[$GroupId])
                $Next = $List[[math]::Min($Seen, $List.Count - 1)]
                if ($Next -eq 'Throw') {
                    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('denied'), 'Forbidden',
                            [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
                }
                @{ id = "req-$GroupId"; groupId = $GroupId; status = $Next }
            } -ParameterFilter { $Uri -like '*/assignmentScheduleRequests/req-*' }
            $Clock = @{ Now = [datetime]::new(2026, 10, 8, 12, 0, 0, [DateTimeKind]::Utc); Step = 1 }
            Mock -ModuleName Omnicit.PIM Get-Date { $Clock.Now = $Clock.Now.AddSeconds($Clock.Step); $Clock.Now }
            Mock -ModuleName Omnicit.PIM Start-Sleep { }
        }
        BeforeEach {
            # Step 1 by default, so a wait that never ends on its own still reaches its deadline.
            $Clock.Now = [datetime]::new(2026, 10, 8, 12, 0, 0, [DateTimeKind]::Utc)
            $Clock.Step = 1
            $Plan.Post.Clear(); $Plan.Poll.Clear(); $Plan.Count.Clear()
            $Plan.Post['g-1'] = 'PendingProvisioning'; $Plan.Post['g-2'] = 'PendingProvisioning'
            $Plan.Poll['g-1'] = @('Provisioned'); $Plan.Poll['g-2'] = @('Provisioned')
        }

        It 'stops at -TimeoutSeconds, writes ActivationWaitTimedOut and returns nothing' {
            # Deadline = first read (12:00:30) + 60 = 12:01:30. Check 12:01:00: poll once. Check
            # 12:01:30: at the deadline, stop. One poll, never more.
            $Clock.Step = 30
            $Plan.Poll['g-1'] = @('PendingProvisioning')
            $Result = Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' -Wait -TimeoutSeconds 60 `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationWaitTimedOut,Enable-OPIMEntraIDGroup'
            $Errs[-1].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::OperationTimeout)
            $Errs[-1].Exception.Message | Should -BeExactly 'opim-s1-grp - member: the activation request has not completed within 60 seconds (last status: PendingProvisioning). The wait has ended; the request stays submitted and may still complete.'
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'ActivationWaitTimedOut*' }).Count | Should -Be 1
            @($Warns).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*/assignmentScheduleRequests/req-*'
            }
        }

        It 'writes the last polled status back onto the request it times out' {
            $Clock.Step = 30
            $Plan.Poll['g-1'] = @('PendingScheduleCreation')
            $null = Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' -Wait -TimeoutSeconds 60 -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationWaitTimedOut,Enable-OPIMEntraIDGroup'
            $Errs[-1].Exception.Message | Should -BeLike '*(last status: PendingScheduleCreation)*'
            $Errs[-1].TargetObject.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
            $Errs[-1].TargetObject.status | Should -BeExactly 'PendingScheduleCreation'
        }

        It 'waits 300 seconds when -TimeoutSeconds is not given' {
            # Deadline = 12:00:30 + 300 = 12:05:30; checks at 12:01:00 ... 12:05:00 poll (9 polls).
            $Clock.Step = 30
            $Plan.Poll['g-1'] = @('PendingProvisioning')
            $null = Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' -Wait -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].Exception.Message | Should -BeLike '*within 300 seconds*'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 9 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*/assignmentScheduleRequests/req-*'
            }
        }

        It 'returns the request with the polled status written back' {
            $Result = Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' -Wait `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
            $Result.status | Should -BeExactly 'Provisioned'
            @($Warns).Count | Should -Be 0
            @($Errs).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*/assignmentScheduleRequests/req-g-1'
            }
        }

        It 'sleeps 2 seconds before each poll' {
            $Plan.Poll['g-1'] = @('PendingProvisioning', 'PendingProvisioning', 'Provisioned')
            $Result = Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' -Wait -ErrorAction SilentlyContinue
            $Result.status | Should -BeExactly 'Provisioned'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 3 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*/assignmentScheduleRequests/req-*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Start-Sleep -Times 3 -Exactly -Scope It -ParameterFilter { $Seconds -eq 2 }
            Should -Invoke -ModuleName Omnicit.PIM Start-Sleep -Times 3 -Exactly -Scope It
        }

        It 'ends the wait at once for a request that waits for a decision, with one warning' {
            $Plan.Poll['g-1'] = @('PendingApproval', 'Provisioned')
            $Result = Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' -Wait `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.status | Should -BeExactly 'PendingApproval'
            @($Warns).Count | Should -Be 1
            "$($Warns[0])" | Should -BeExactly 'opim-s1-grp - member: the activation request is PendingApproval. It waits for a decision and has not taken effect yet.'
            @($Errs).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*/assignmentScheduleRequests/req-*'
            }
        }

        It 'writes ActivationRequestFailed and returns nothing for a request the poll finds Denied' {
            $Plan.Poll['g-1'] = @('Denied')
            $Result = Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' -Wait `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Enable-OPIMEntraIDGroup'
            $Errs[-1].Exception.Message | Should -BeExactly "opim-s1-grp - member: the activation request ended with status 'Denied' and did not take effect."
            @($Warns).Count | Should -Be 0
        }

        It 'writes a failed poll as itself and still requests, polls and returns the next group' {
            $Plan.Poll['g-1'] = @('Throw')
            $Result = Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp', 'opim-s1-other' -Wait `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Enable-OPIMEntraIDGroup' }).Count | Should -Be 1
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'Activation*' }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*/assignmentScheduleRequests/req-g-1'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*/assignmentScheduleRequests/req-g-2'
            }
            @($Result).Count | Should -Be 1
            $Result.groupId | Should -BeExactly 'g-2'
            $Result.status | Should -BeExactly 'Provisioned'
            @($Warns).Count | Should -Be 0
        }

        It 'still waits for the next group after one times out' {
            $Clock.Step = 30
            $Plan.Poll['g-1'] = @('PendingProvisioning')
            $Result = Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp', 'opim-s1-other' -Wait -TimeoutSeconds 60 `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'ActivationWaitTimedOut,Enable-OPIMEntraIDGroup' }).Count | Should -Be 1
            @($Result).Count | Should -Be 1
            $Result.groupId | Should -BeExactly 'g-2'
            $Result.status | Should -BeExactly 'Provisioned'
            @($Warns).Count | Should -Be 0
        }

        It 'does not poll a request whose POST answered <Status>' -ForEach @(
            @{ Status = 'Provisioned'; Warnings = 0 }
            @{ Status = 'PendingApproval'; Warnings = 1 }
        ) {
            # Ruling P4: a final status, or one that waits for a person, needs no poll.
            $Plan.Post['g-1'] = $Status
            $Result = Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' -Wait `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.status | Should -BeExactly $Status
            @($Warns).Count | Should -Be $Warnings
            @($Errs).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter {
                $Uri -like '*/assignmentScheduleRequests/req-*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Start-Sleep -Times 0 -Scope It
        }

        It 'does not poll when -Wait is not specified' {
            $Result = Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' -WarningAction SilentlyContinue
            $Result.status | Should -BeExactly 'PendingProvisioning'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter {
                $Uri -like '*/assignmentScheduleRequests/req-*'
            }
        }

        It 'refuses -TimeoutSeconds <Value> before anything is sent' -ForEach @(
            @{ Value = 0 }
            @{ Value = 86401 }
        ) {
            { Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' -Wait -TimeoutSeconds $Value } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError,Enable-OPIMEntraIDGroup'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It
        }
    }

    Context 'When API returns RoleAssignmentRequestPolicyValidationFailed with an unrecognized rule' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"RoleAssignmentRequestPolicyValidationFailed","message":"Policy validation failed: UnknownRuleViolation."}}'
                )
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not throw a terminating error' {
            { Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When the API returns RoleAssignmentRequestAcrsValidationFailed (throws from Invoke-OPIMGraphRequest)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('RoleAssignmentRequestAcrsValidationFailed: ACRS validation failed'),
                        'RoleAssignmentRequestAcrsValidationFailed',
                        [System.Management.Automation.ErrorCategory]::AuthenticationError,
                        $null
                    )
                )
            }
        }

        It 'does not throw a terminating error' {
            { Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'calls Invoke-OPIMGraphRequest once only (ACRS retry is handled inside Invoke-OPIMGraphRequest)' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It
        }
    }

    Context 'When -Identity is specified and the group is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeElig = [PSCustomObject]@{
                id          = 'elig-010'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
                principal   = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return $FakeElig }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id          = 'req-010'
                    action      = 'selfActivate'
                    accessId    = 'member'
                    groupId     = 'group-001'
                    principalId = 'principal-001'
                    status      = 'Provisioned'
                }
            }
        }

        It 'looks up the group via Get-OPIMEntraIDGroup -Identity' {
            Enable-OPIMEntraIDGroup -Identity 'elig-010'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 1 -Scope It
        }

        It 'submits the selfActivate request' {
            Enable-OPIMEntraIDGroup -Identity 'elig-010'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.GroupAssignmentScheduleRequest' {
            $Result = Enable-OPIMEntraIDGroup -Identity 'elig-010'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
        }
    }

    Context 'When -Identity is specified but no eligible group is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return $null }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMEntraIDGroup -Identity 'nonexistent-999' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'writes IdentityNotFound to its own error stream' {
            $Out = Enable-OPIMEntraIDGroup -Identity 'nonexistent-999' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'IdentityNotFound*'
        }
    }

    Context 'When the listing for -Identity fails' {
        # OPIM-12: a listing that cannot be read is reported as itself and stops for that identity;
        # it is never reported as IdentityNotFound. The mock writes the record a listing writes for
        # a failed read (a Graph 403).
        # The mock takes its preference from an explicit -ErrorAction and is Continue otherwise, as a
        # listing is under the default preference: a module-scoped mock body reads the test scope's
        # preference (Stop under the build), never the caller's.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup {
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {}
        }

        It "writes the listing's error as itself" {
            # The command's own error stream, not -ErrorVariable: -ErrorVariable also collects the
            # record the listing raised and the command caught.
            $Out = Enable-OPIMEntraIDGroup -Identity 'elig-403' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
        }

        It 'does not write IdentityNotFound' {
            $Out = Enable-OPIMEntraIDGroup -Identity 'elig-403' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            @($Written | Where-Object { $_.FullyQualifiedErrorId -like 'IdentityNotFound*' }).Count | Should -Be 0
        }

        It 'sends no activation' {
            Enable-OPIMEntraIDGroup -Identity 'elig-403' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When the listing for -GroupName fails' {
        # OPIM-12: each name resolves on its own. A listing that cannot be read is written as itself
        # for that name, never as "not found", and the next name still runs.
        # The mock takes its preference from an explicit -ErrorAction and is Continue otherwise, as a
        # listing is under the default preference: a module-scoped mock body reads the test scope's
        # preference (Stop under the build), never the caller's.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup {
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {}
        }

        It "writes the listing's error as itself for each name and activates nothing" {
            # The command's own error stream, not -ErrorVariable: -ErrorVariable also collects the
            # record the listing raised and the command caught.
            $Out = Enable-OPIMEntraIDGroup -GroupName 'Group A - member (elig-a)', 'Group B - member (elig-b)' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 2
            @($Written | Where-Object { $_.FullyQualifiedErrorId -like 'Forbidden*' }).Count | Should -Be 2
            @($Written | Where-Object { $_.FullyQualifiedErrorId -like '*NotFound*' }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 2 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When positional parameters are used' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeElig = [PSCustomObject]@{
                id          = 'elig-pos-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
                principal   = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeElig }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id          = 'req-pos-001'
                    action      = 'selfActivate'
                    accessId    = 'member'
                    groupId     = 'group-001'
                    principalId = 'principal-001'
                    status      = 'Provisioned'
                }
            }
        }

        It 'accepts GroupName as position 0, Justification as position 1, Hours as position 2' {
            Enable-OPIMEntraIDGroup 'Finance Team (elig-pos-001)' 'Project work' 2
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Body.justification -eq 'Project work' -and
                $Body.scheduleInfo.expiration.duration -eq 'PT2H'
            }
        }
    }

    Context 'When a GroupAssignmentScheduleInstance is piped from Get-OPIMEntraIDGroup -All' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest { }
        }

        It 'skips the already-active instance and does not POST to the Graph API' {
            $AlreadyActive = [PSCustomObject]@{
                id          = 'active-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = @{ displayName = 'PIM Admins' }
            }
            $AlreadyActive.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleInstance')
            $AlreadyActive | Enable-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It
        }
    }

    Context 'When two groups carry the same display name' {
        # The real resolver runs; only the listing and the transport are mocked.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-GroupPost -Id 'grp-elig-003' -GroupId 'g-2' -Name 'Twin' -AccessId 'member'
                New-GroupPost -Id 'grp-elig-004' -GroupId 'g-3' -Name 'Twin' -AccessId 'member'
                New-GroupPost -Id 'grp-elig-005' -GroupId 'g-4' -Name 'unique-grp' -AccessId 'member'
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $Listing }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'req-001'; action = 'selfActivate'; status = 'Provisioned' }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes AmbiguousName and sends no activation' {
            $Errs = @()
            Enable-OPIMEntraIDGroup -GroupName 'Twin' -ErrorVariable Errs -ErrorAction SilentlyContinue
            # The listing was read, so the resolver and the catch that writes its record were reached.
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Enable-OPIMEntraIDGroup'
        }

        It 'points at the tab-completed form, since -AccessType cannot tell the groups apart' {
            $Errs = @()
            Enable-OPIMEntraIDGroup -GroupName 'Twin' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].Exception.Message | Should -BeLike '*tab-completed form*'
        }

        It 'activates a unique display name with its own ids' {
            Enable-OPIMEntraIDGroup -GroupName 'UNIQUE-GRP' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.groupId -eq 'g-4' -and $Body.accessId -eq 'member' -and $Body.principalId -eq 'principal-001'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When the name is held as a member and as an owner' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-GroupPost -Id 'grp-elig-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'member'
                New-GroupPost -Id 'grp-elig-002' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'owner'
                New-GroupPost -Id 'grp-elig-006' -GroupId 'g-5' -Name 'owner-only-grp' -AccessId 'owner'
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $Listing }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'req-001'; action = 'selfActivate'; status = 'Provisioned' }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'activates the membership when no -AccessType is given' {
            Enable-OPIMEntraIDGroup -GroupName 'opim-grp' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.accessId -eq 'member' -and $Body.groupId -eq 'g-1'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }

        It 'activates the ownership when -AccessType is <Given>' -ForEach @(
            @{ Given = 'Owner' }
            @{ Given = 'owner' }
        ) {
            Enable-OPIMEntraIDGroup -GroupName 'opim-grp' -AccessType $Given -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.accessId -eq 'owner' -and $Body.groupId -eq 'g-1'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }

        It 'activates the membership when -AccessType Member is given' {
            Enable-OPIMEntraIDGroup -GroupName 'opim-grp' -AccessType Member -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.accessId -eq 'member' -and $Body.groupId -eq 'g-1'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }

        It 'refuses an owner-only group without -AccessType Owner and says so' {
            $Errs = @()
            Enable-OPIMEntraIDGroup -GroupName 'owner-only-grp' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'EligibleRoleNotFound,Enable-OPIMEntraIDGroup'
            $Errs[-1].Exception.Message | Should -BeLike '*-AccessType Owner*'
        }

        It 'activates the owner-only group when -AccessType Owner is given' {
            Enable-OPIMEntraIDGroup -GroupName 'owner-only-grp' -AccessType Owner -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.accessId -eq 'owner' -and $Body.groupId -eq 'g-5'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When several names are given and one of them is unknown' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-GroupPost -Id 'grp-elig-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'member'
                New-GroupPost -Id 'grp-elig-005' -GroupId 'g-4' -Name 'unique-grp' -AccessId 'member'
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $Listing }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'req-001'; action = 'selfActivate'; status = 'Provisioned' }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes EligibleRoleNotFound for the unknown name and still activates the other (<Names>)' -ForEach @(
            @{ Names = 'unknown first'; List = @('Unknown Group', 'unique-grp') }
            @{ Names = 'unknown last'; List = @('unique-grp', 'Unknown Group') }
        ) {
            $Errs = @()
            Enable-OPIMEntraIDGroup -GroupName $List -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'EligibleRoleNotFound,Enable-OPIMEntraIDGroup'
            # -ErrorVariable also collects the record the resolver threw, so count the one the cmdlet wrote.
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'EligibleRoleNotFound,Enable-OPIMEntraIDGroup' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.groupId -eq 'g-4'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When -Identity matches more than one listed post' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-GroupPost -Id 'dup-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'member'
                New-GroupPost -Id 'dup-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'owner'
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $Listing }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'req-001'; action = 'selfActivate'; status = 'Provisioned' }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes AmbiguousName, not IdentityNotFound, and sends no activation' {
            $Errs = @()
            Enable-OPIMEntraIDGroup -Identity 'dup-001' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Enable-OPIMEntraIDGroup'
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'IdentityNotFound*' }).Count | Should -Be 0
        }
    }

    Context 'When -AccessType is given where it does not belong' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest { } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'fails to bind -AccessType together with -Identity' {
            { Enable-OPIMEntraIDGroup -Identity 'grp-elig-001' -AccessType Owner } | Should -Throw -ErrorId 'AmbiguousParameterSet*'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }

        It 'puts -AccessType in the GroupName parameter set only' {
            # A piped object binds -Group in another set, so -AccessType with it selects the GroupName set, whose
            # mandatory name is then missing. Read the sets from the command metadata instead of
            # binding: an interactive host would prompt for the name.
            (Get-Command Enable-OPIMEntraIDGroup).Parameters['AccessType'].ParameterSets.Keys | Should -Be 'GroupName'
        }

        It 'refuses an -AccessType other than Member or Owner' {
            { Enable-OPIMEntraIDGroup -GroupName 'opim-grp' -AccessType Admin } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }
    }
    Context 'When the resolver writes an error instead of throwing it' {
        # The cmdlet calls the resolver with -ErrorAction Stop, so an error the resolver only writes
        # ends that name inside the cmdlet's own try and is written as the cmdlet's own error. The
        # mock takes its preference from an explicit -ErrorAction and is Continue otherwise, as the
        # resolver is under the default preference.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {}
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule {
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
        }

        It 'writes the error as its own for each name and activates nothing' {
            $Out = Enable-OPIMEntraIDGroup -GroupName 'Group A', 'Group B' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 2
            @($Written | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Enable-OPIMEntraIDGroup' }).Count | Should -Be 2
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 2 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }
    Context 'When the old form matches a member and an owner post that share an id' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-GroupPost -Id 'dup-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'member'
                New-GroupPost -Id 'dup-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'owner'
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $Listing }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'req-001'; action = 'selfActivate'; status = 'Provisioned' }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes AmbiguousName that names -AccessType as the way to tell them apart' {
            $Errs = @()
            Enable-OPIMEntraIDGroup -GroupName 'opim-grp - member (dup-001)' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Enable-OPIMEntraIDGroup'
            $Errs[-1].Exception.Message | Should -BeLike '*-AccessType Member*'
        }

        It 'activates the ownership once -AccessType Owner is given' {
            Enable-OPIMEntraIDGroup -GroupName 'opim-grp - member (dup-001)' -AccessType Owner -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.accessId -eq 'owner' -and $Body.groupId -eq 'g-1'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When the resolver is mocked and -AccessType is given' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Resolved = New-GroupPost -Id 'grp-elig-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'owner'
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { $Resolved }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'req-001'; action = 'selfActivate'; status = 'Provisioned' }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'hands the resolver the group pillar and the access type in the lower case it declares' {
            Enable-OPIMEntraIDGroup -GroupName 'opim-grp' -AccessType Owner -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $Pillar -eq 'Group' -and $AccessType -ceq 'owner' -and $Name -eq 'opim-grp'
            }
        }

        It 'hands the resolver no access type when none is given' {
            Enable-OPIMEntraIDGroup -GroupName 'opim-grp' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $Pillar -eq 'Group' -and -not $AccessType
            }
        }
    }

    Context 'When Graph answers the request with a status' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Post = New-GroupPost -Id 'grp-elig-001' -GroupId 'g-1' -Name 'opim-s1-grp' -AccessId 'member'
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { $Post }
            # The answer is read when the POST is made, so each test sets the status it wants.
            $Answer = @{ Status = 'Provisioned' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $Response = @{ id = 'req-001'; action = 'selfActivate'; accessId = 'member'; groupId = 'g-1'; principalId = 'principal-001' }
                if ($null -ne $Answer.Status) { $Response.status = $Answer.Status }
                $Response
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'returns the request and writes neither a warning nor an error for <Status>' -ForEach @(
            @{ Status = 'Provisioned' }
            @{ Status = 'Granted' }
            @{ Status = 'ScheduleCreated' }
            @{ Status = 'provisioned' }
        ) {
            $Answer.Status = $Status
            $Result = Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
            $Result.status | Should -BeExactly $Status
            @($Warns).Count | Should -Be 0
            @($Errs).Count | Should -Be 0
        }

        It 'returns the request with one warning that names <Status>' -ForEach @(
            @{ Status = 'PendingApproval'; Message = 'opim-s1-grp - member: the activation request is PendingApproval. It waits for a decision and has not taken effect yet.' }
            @{ Status = 'PendingAdminDecision'; Message = 'opim-s1-grp - member: the activation request is PendingAdminDecision. It waits for a decision and has not taken effect yet.' }
            @{ Status = 'PendingProvisioning'; Message = 'opim-s1-grp - member: the activation request is PendingProvisioning and has not taken effect yet.' }
        ) {
            $Answer.Status = $Status
            $Result = Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.status | Should -BeExactly $Status
            @($Warns).Count | Should -Be 1
            "$($Warns[0])" | Should -BeExactly $Message
            @($Errs).Count | Should -Be 0
        }

        It 'writes ActivationRequestFailed and returns nothing for <Status>' -ForEach @(
            @{ Status = 'Failed' }
            @{ Status = 'Denied' }
            @{ Status = 'Canceled' }
            @{ Status = 'Revoked' }
            @{ Status = 'AdminDenied' }
            @{ Status = 'SomethingNew' }
        ) {
            $Answer.Status = $Status
            $Result = Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Enable-OPIMEntraIDGroup'
            $Errs[-1].Exception.Message | Should -BeExactly "opim-s1-grp - member: the activation request ended with status '$Status' and did not take effect."
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'ActivationRequestFailed*' }).Count | Should -Be 1
            @($Warns).Count | Should -Be 0
        }

        It 'writes ActivationRequestFailed for an answer that carries no status' {
            $Answer.Status = $null
            $Result = Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Enable-OPIMEntraIDGroup'
            $Errs[-1].Exception.Message | Should -BeLike '*ended with no status*'
        }
    }

    Context 'When the first of two requests comes back Failed' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $PostA = New-GroupPost -Id 'grp-elig-001' -GroupId 'g-1' -Name 'opim-s1-grp' -AccessId 'member'
            $PostB = New-GroupPost -Id 'grp-elig-002' -GroupId 'g-2' -Name 'opim-s1-other' -AccessId 'member'
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule {
                if ($Name -like '*grp') { $PostA } else { $PostB }
            }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $State = if ($Body.groupId -eq 'g-1') { 'Failed' } else { 'Provisioned' }
                @{ id = "req-$($Body.groupId)"; action = 'selfActivate'; accessId = 'member'; groupId = $Body.groupId; status = $State }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes one error and still requests and returns the second group' {
            $Result = Enable-OPIMEntraIDGroup -GroupName 'opim-s1-grp', 'opim-s1-other' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'ActivationRequestFailed,Enable-OPIMEntraIDGroup' }).Count | Should -Be 1
            $Errs[-1].Exception.Message | Should -BeLike 'opim-s1-grp - member: *'
            @($Result).Count | Should -Be 1
            $Result.groupId | Should -BeExactly 'g-2'
            $Result.status | Should -BeExactly 'Provisioned'
        }
    }

    Context 'When the help is read (OPIM-37)' {
        It 'describes in .OUTPUTS a PSCustomObject and no Hashtable' {
            $Outputs = @((Get-Help Enable-OPIMEntraIDGroup -Full).returnValues.returnValue.type.name) -join "`n"
            $Outputs | Should -Match 'PSCustomObject'
            $Outputs | Should -Match 'Omnicit\.PIM\.GroupAssignmentScheduleRequest'
            $Outputs | Should -Not -Match 'Hashtable'
        }
    }
}
