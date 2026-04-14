Describe 'Enable-OPIMEntraIDGroup' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When called with -GroupName (happy path)' {
        BeforeAll {
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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

        It 'calls Resolve-RoleByName for the supplied group name' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-RoleByName -Times 1 -Scope It
        }

        It 'calls Invoke-MgGraphRequest with POST to the group assignmentScheduleRequests endpoint' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*privilegedAccess/group/assignmentScheduleRequests*'
            }
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.GroupAssignmentScheduleRequest' {
            $Result = Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
        }

        It 'sends selfActivate as the action in the request body' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.action -eq 'selfActivate'
            }
        }

        It 'sends the accessId from the resolved group in the request body' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.accessId -eq 'member'
            }
        }

        It 'uses AfterDuration expiration type by default' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.type -eq 'AfterDuration'
            }
        }

        It 'passes a PT1H ISO 8601 duration when -Hours defaults to 1' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.duration -eq 'PT1H'
            }
        }
    }

    Context 'When called with multiple group names' {
        BeforeAll {
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
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName {
                if ($RoleName -like '*elig-001*') { return $fakeGroupA } else { return $fakeGroupB }
            }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{
                    id     = [System.Guid]::NewGuid().ToString()
                    action = 'selfActivate'
                    status = 'Provisioned'
                    group  = @{ displayName = 'Team' }
                }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'calls Invoke-MgGraphRequest once per group name supplied' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)', 'DevOps Team (elig-002)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 2 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When called with pipeline input (-Group parameter set)' {
        BeforeAll {
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-002'
                accessId    = 'owner'
                groupId     = 'group-002'
                principalId = 'principal-002'
                group       = [PSCustomObject]@{ displayName = 'DevOps Team' }
            }
            $fakeGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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

        It 'calls Invoke-MgGraphRequest with the groupId and principalId from the piped group' {
            $fakeGroup | Enable-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and
                $Body.groupId -eq 'group-002' -and
                $Body.principalId -eq 'principal-002'
            }
        }

        It 'calls Invoke-MgGraphRequest with the accessId from the piped group' {
            $fakeGroup | Enable-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
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
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            $script:UntilDateTime = [DateTime]::Now.AddHours(3)
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.type -eq 'AfterDateTime'
            }
        }

        It 'does not include a duration in the request body when -Until is specified' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -Until $script:UntilDateTime
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and -not $Body.scheduleInfo.expiration.duration
            }
        }
    }

    Context 'When -Hours overrides the default duration' {
        BeforeAll {
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.duration -eq 'PT4H'
            }
        }

        It 'passes PT8H ISO 8601 duration when -Hours 8 is specified' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -Hours 8
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.scheduleInfo.expiration.duration -eq 'PT8H'
            }
        }
    }

    Context 'When ticket information is provided' {
        BeforeAll {
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and
                $Body.ticketInfo.ticketNumber -eq 'INC-456' -and
                $Body.ticketInfo.ticketSystem -eq 'Jira'
            }
        }
    }

    Context 'When -Justification is provided' {
        BeforeAll {
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.justification -eq 'Year-end reporting'
            }
        }
    }

    Context 'When -WhatIf is specified' {
        BeforeAll {
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest { } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not call Invoke-MgGraphRequest when -WhatIf is specified' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 0 -Scope It
        }
    }

    Context 'When the Graph API returns a general error' {
        BeforeAll {
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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
        BeforeAll {
            $fakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{
                    id     = 'req-poll-001'
                    action = 'selfActivate'
                    status = 'Provisioned'
                    group  = @{ displayName = 'Finance Team' }
                }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                return @{ status = 'Provisioned' }
            } -ParameterFilter { $Uri -like '*assignmentScheduleRequests/req-poll-001*' }
            Mock -ModuleName Omnicit.PIM Start-Sleep { }
        }

        It 'calls Invoke-MgGraphRequest to poll the request status' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -Wait
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*assignmentScheduleRequests/req-poll-001*'
            }
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.GroupAssignmentScheduleRequest' {
            $Result = Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -Wait
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
        }

        It 'does not poll when -Wait is not specified' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 0 -Scope It -ParameterFilter {
                $Uri -like '*assignmentScheduleRequests/req-poll-001*'
            }
        }
    }

    Context 'When API returns RoleAssignmentRequestPolicyValidationFailed with an unrecognized rule' {
        BeforeAll {
            $FakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
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

    Context 'When the API returns RoleAssignmentRequestAcrsValidationFailed' {
        BeforeAll {
            $FakeGroup = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"RoleAssignmentRequestAcrsValidationFailed","message":"&claims=%7B%22access_token%22%3A%7B%22acrs%22%3A%7B%22essential%22%3Atrue%2C%20%22value%22%3A%22c1%22%7D%7D%7D"}}'
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

        It 'sets the FullyQualifiedErrorId to RoleAssignmentRequestAcrsValidationFailed' {
            $Errors = @()
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].FullyQualifiedErrorId | Should -BeLike '*RoleAssignmentRequestAcrsValidationFailed*'
        }

        It 'includes a hint to run Connect-MgGraph in the error message' {
            $Errors = @()
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].Exception.Message | Should -BeLike '*Connect-MgGraph*'
        }

        It 'calls Invoke-MgGraphRequest POST once only (no retry)' {
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not call Disconnect-MgGraph' {
            Mock -ModuleName Omnicit.PIM Disconnect-MgGraph { }
            Enable-OPIMEntraIDGroup -GroupName 'Finance Team (elig-001)' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Disconnect-MgGraph -Times 0 -Scope It
        }
    }
}
