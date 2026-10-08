BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Disable-OPIMEntraIDGroup' {
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
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id          = 'deact-req-001'
                    action      = 'selfDeactivate'
                    accessId    = 'member'
                    groupId     = 'group-001'
                    principalId = 'principal-001'
                    status      = 'Revoked'
                    group       = @{ displayName = 'Finance Team' }
                }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'calls Resolve-OPIMSchedule for the supplied group name' {
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It
        }

        It 'calls Invoke-OPIMGraphRequest with POST to the group assignmentScheduleRequests endpoint' {
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*privilegedAccess/group/assignmentScheduleRequests*'
            }
        }

        It 'sends selfDeactivate as the action in the request body' {
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.action -eq 'selfDeactivate'
            }
        }

        It 'sends the accessId from the resolved group in the request body' {
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.accessId -eq 'member'
            }
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.GroupAssignmentScheduleRequest' {
            $Result = Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
        }
    }

    Context 'When called with pipeline input (-Group parameter set)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-002'
                accessId    = 'owner'
                groupId     = 'group-002'
                principalId = 'principal-002'
                group       = [PSCustomObject]@{ displayName = 'DevOps Team' }
            }
            $FakeGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleInstance')
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id          = 'deact-req-002'
                    action      = 'selfDeactivate'
                    accessId    = 'owner'
                    groupId     = 'group-002'
                    principalId = 'principal-002'
                    status      = 'Revoked'
                    group       = @{ displayName = 'DevOps Team' }
                }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'calls Invoke-OPIMGraphRequest with the groupId and principalId from the piped group' {
            $FakeGroup | Disable-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and
                $Body.groupId -eq 'group-002' -and
                $Body.principalId -eq 'principal-002'
            }
        }

        It 'calls Invoke-OPIMGraphRequest with the accessId from the piped group' {
            $FakeGroup | Disable-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.accessId -eq 'owner'
            }
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.GroupAssignmentScheduleRequest' {
            $Result = $FakeGroup | Disable-OPIMEntraIDGroup
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
        }
    }

    Context 'When -WhatIf is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest { } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not call Invoke-OPIMGraphRequest when -WhatIf is specified' {
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)' -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It
        }
    }

    Context 'When the Graph API returns a general error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"GeneralError","message":"An unexpected error occurred."}}'
                )
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'does not throw a terminating error' {
            { Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When the API returns an ActiveDurationTooShort error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Finance Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"ActiveDurationTooShort","message":"Group was not activated long enough to meet the minimum wait period."}}'
                )
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'includes the 5-minute cooldown message in the error details' {
            $Errors = @()
            Disable-OPIMEntraIDGroup -GroupName 'Finance Team (instance-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].Exception.Message | Should -Match '5 minutes'
        }
    }

    Context 'When the API response does not include a group property' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeGroup = [PSCustomObject]@{
                id          = 'instance-004'
                accessId    = 'member'
                groupId     = 'group-004'
                principalId = 'principal-004'
                group       = [PSCustomObject]@{ displayName = 'Engineering Team' }
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeGroup }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id          = 'deact-req-004'
                    action      = 'selfDeactivate'
                    accessId    = 'member'
                    groupId     = 'group-004'
                    principalId = 'principal-004'
                    status      = 'Revoked'
                    # 'group' key intentionally omitted to exercise the restore branch
                }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'restores the group property from the resolved schedule object' {
            $Result = Disable-OPIMEntraIDGroup -GroupName 'Engineering Team (instance-004)'
            $Result.group.displayName | Should -Be 'Engineering Team'
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.GroupAssignmentScheduleRequest' {
            $Result = Disable-OPIMEntraIDGroup -GroupName 'Engineering Team (instance-004)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
        }
    }

    Context 'When -Identity is specified and the group is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeActive = [PSCustomObject]@{
                id          = 'instance-005'
                accessId    = 'member'
                groupId     = 'group-002'
                principalId = 'principal-001'
                group       = [PSCustomObject]@{ displayName = 'Security Team' }
            }
            $FakeActive.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleInstance')
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return $FakeActive }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    id          = 'deact-req-005'
                    action      = 'selfDeactivate'
                    accessId    = 'member'
                    groupId     = 'group-002'
                    principalId = 'principal-001'
                    status      = 'Revoked'
                    group       = @{ displayName = 'Security Team' }
                }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'looks up the group via Get-OPIMEntraIDGroup -Activated -Identity' {
            Disable-OPIMEntraIDGroup -Identity 'instance-005'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 1 -Scope It
        }

        It 'submits the selfDeactivate request' {
            Disable-OPIMEntraIDGroup -Identity 'instance-005'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'returns a PSCustomObject tagged with Omnicit.PIM.GroupAssignmentScheduleRequest' {
            $Result = Disable-OPIMEntraIDGroup -Identity 'instance-005'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
        }
    }

    Context 'When -Identity is specified but no active group is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return $null }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMEntraIDGroup -Identity 'nonexistent-999' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'writes IdentityNotFound to its own error stream' {
            $Out = Disable-OPIMEntraIDGroup -Identity 'nonexistent-999' -ErrorAction Continue 2>&1
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
            $Out = Disable-OPIMEntraIDGroup -Identity 'active-403' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
        }

        It 'does not write IdentityNotFound' {
            $Out = Disable-OPIMEntraIDGroup -Identity 'active-403' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            @($Written | Where-Object { $_.FullyQualifiedErrorId -like 'IdentityNotFound*' }).Count | Should -Be 0
        }

        It 'sends no deactivation' {
            Disable-OPIMEntraIDGroup -Identity 'active-403' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When the listing for -GroupName fails' {
        # OPIM-12: the listing that cannot be read is written as itself, never as "not found", and
        # nothing is deactivated.
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

        It "writes the listing's error as itself and sends no deactivation" {
            # The command's own error stream, not -ErrorVariable: -ErrorVariable also collects the
            # record the listing raised and the command caught.
            $Out = Disable-OPIMEntraIDGroup -GroupName 'Group A - member (active-a)' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
            @($Written | Where-Object { $_.FullyQualifiedErrorId -like '*NotFound*' }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When a GroupEligibilitySchedule is piped from Get-OPIMEntraIDGroup -All' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest { } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'skips the eligible-only schedule and does not POST to the Graph API' {
            $EligibleOnly = [PSCustomObject]@{
                id          = 'elig-001'
                accessId    = 'member'
                groupId     = 'group-001'
                principalId = 'principal-001'
                group       = @{ displayName = 'PIM Admins' }
            }
            $EligibleOnly.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
            $EligibleOnly | Disable-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When two active groups carry the same display name' {
        # The real resolver runs; only the listing and the transport are mocked. The listing answers
        # with the active posts only when it is asked for them (-Activated), so a name that is only
        # eligible must not be found.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Eligible = @(
                New-GroupPost -Id 'grp-elig-007' -GroupId 'g-7' -Name 'eligible-only-grp' -AccessId 'member'
            )
            $Active = @(
                New-GroupPost -Id 'grp-act-003' -GroupId 'g-2' -Name 'Twin' -AccessId 'member' -Active
                New-GroupPost -Id 'grp-act-004' -GroupId 'g-3' -Name 'Twin' -AccessId 'member' -Active
                New-GroupPost -Id 'grp-act-005' -GroupId 'g-4' -Name 'unique-grp' -AccessId 'member' -Active
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $Eligible }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $Active } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'deact-req-001'; action = 'selfDeactivate'; status = 'Revoked' }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes AmbiguousName and sends no deactivation' {
            $Errs = @()
            Disable-OPIMEntraIDGroup -GroupName 'Twin' -ErrorVariable Errs -ErrorAction SilentlyContinue
            # The active list was read, so the resolver and the catch that writes its record were reached.
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 1 -Exactly -Scope It -ParameterFilter { $Activated }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Disable-OPIMEntraIDGroup'
        }

        It 'points at the tab-completed form, since -AccessType cannot tell the groups apart' {
            $Errs = @()
            Disable-OPIMEntraIDGroup -GroupName 'Twin' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].Exception.Message | Should -BeLike '*tab-completed form*'
        }

        It 'deactivates a unique display name with its own ids' {
            Disable-OPIMEntraIDGroup -GroupName 'UNIQUE-GRP' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.action -eq 'selfDeactivate' -and $Body.groupId -eq 'g-4' -and
                $Body.accessId -eq 'member' -and $Body.principalId -eq 'principal-001'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes ActiveRoleNotFound for a group that is eligible but not active' {
            $Errs = @()
            Disable-OPIMEntraIDGroup -GroupName 'eligible-only-grp' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound,Disable-OPIMEntraIDGroup'
        }
    }

    Context 'When the name is active as a member and as an owner' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Active = @(
                New-GroupPost -Id 'grp-act-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'member' -Active
                New-GroupPost -Id 'grp-act-002' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'owner' -Active
                New-GroupPost -Id 'grp-act-006' -GroupId 'g-5' -Name 'owner-only-grp' -AccessId 'owner' -Active
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $Active }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'deact-req-001'; action = 'selfDeactivate'; status = 'Revoked' }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'deactivates the membership when no -AccessType is given' {
            Disable-OPIMEntraIDGroup -GroupName 'opim-grp' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.accessId -eq 'member' -and $Body.groupId -eq 'g-1'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }

        It 'deactivates the ownership when -AccessType is <Given>' -ForEach @(
            @{ Given = 'Owner' }
            @{ Given = 'owner' }
        ) {
            Disable-OPIMEntraIDGroup -GroupName 'opim-grp' -AccessType $Given -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.accessId -eq 'owner' -and $Body.groupId -eq 'g-1'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }

        It 'refuses an owner-only group without -AccessType Owner and says so' {
            $Errs = @()
            Disable-OPIMEntraIDGroup -GroupName 'owner-only-grp' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound,Disable-OPIMEntraIDGroup'
            $Errs[-1].Exception.Message | Should -BeLike '*-AccessType Owner*'
        }

        It 'deactivates the owner-only group when -AccessType Owner is given' {
            Disable-OPIMEntraIDGroup -GroupName 'owner-only-grp' -AccessType Owner -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.accessId -eq 'owner' -and $Body.groupId -eq 'g-5'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When -Identity matches more than one listed post' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-GroupPost -Id 'dup-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'member' -Active
                New-GroupPost -Id 'dup-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'owner' -Active
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $Listing }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'deact-req-001'; action = 'selfDeactivate'; status = 'Revoked' }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes AmbiguousName, not IdentityNotFound, and sends no deactivation' {
            $Errs = @()
            Disable-OPIMEntraIDGroup -Identity 'dup-001' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Disable-OPIMEntraIDGroup'
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
            { Disable-OPIMEntraIDGroup -Identity 'grp-act-001' -AccessType Owner } | Should -Throw -ErrorId 'AmbiguousParameterSet*'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }

        It 'puts -AccessType in the GroupName parameter set only' {
            # A piped object binds -Group in another set, so -AccessType with it selects the GroupName set, whose
            # mandatory name is then missing. Read the sets from the command metadata instead of
            # binding: an interactive host would prompt for the name.
            (Get-Command Disable-OPIMEntraIDGroup).Parameters['AccessType'].ParameterSets.Keys | Should -Be 'GroupName'
        }

        It 'refuses an -AccessType other than Member or Owner' {
            { Disable-OPIMEntraIDGroup -GroupName 'opim-grp' -AccessType Admin } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }
    }

    Context 'When the group is already deactivated (OPIM-40, G8)' {
        # The real resolver runs; only the listing and the transport are mocked. The first call finds
        # the membership active and deactivates it, and that request ends the activation in the mock,
        # so the second call finds the group eligible and no longer active.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Held = @{ IsActive = $true }
            $ActivePost = New-GroupPost -Id 'grp-act-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'member' -Active
            $EligiblePost = New-GroupPost -Id 'grp-elig-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'member'
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { if ($Held.IsActive) { $ActivePost } } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $EligiblePost }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $Held.IsActive = $false
                @{ id = 'deact-req-001'; action = 'selfDeactivate'; status = 'Revoked' }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'deactivates once and writes one non-terminating ActiveRoleNotFound that says it is already deactivated' {
            $Held.IsActive = $true
            $Out = & {
                Disable-OPIMEntraIDGroup -GroupName 'opim-grp' -ErrorAction Continue
                Disable-OPIMEntraIDGroup -GroupName 'opim-grp' -ErrorAction Continue
                'reached'
            } 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Results = @($Out | Where-Object { $_ -is [PSCustomObject] -and $_.PSObject.TypeNames -contains 'Omnicit.PIM.GroupAssignmentScheduleRequest' })
            # The statement after the second call ran, so the error did not end the script block.
            ($Out -contains 'reached') | Should -BeTrue
            $Results.Count | Should -Be 1
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound,Disable-OPIMEntraIDGroup'
            $Written[0].Exception.Message | Should -BeLike '*already deactivated*'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
            # Both lists were read on the second call: the active list, then the eligible one for the hint.
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 2 -Exactly -Scope It -ParameterFilter { $Activated }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 1 -Exactly -Scope It -ParameterFilter { -not $Activated }
        }

        It 'names the active form, and deactivates nothing, for the eligibility key of a group that is active' {
            # What the 0.5.1 completers offered: the assignment's own key. The group is active as
            # grp-act-001, so the message must not call it deactivated.
            $Held.IsActive = $true
            $Out = & {
                Disable-OPIMEntraIDGroup -GroupName 'opim-grp - member (grp-elig-001)' -ErrorAction Continue
                'reached'
            } 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            ($Out -contains 'reached') | Should -BeTrue
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound,Disable-OPIMEntraIDGroup'
            $Written[0].Exception.Message | Should -Not -BeLike '*already deactivated*'
            $Written[0].Exception.Message | Should -BeLike "*It is active as 'opim-grp - member (grp-act-001)'*"
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
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

        It 'writes the error as its own and deactivates nothing' {
            $Out = Disable-OPIMEntraIDGroup -GroupName 'Group A' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            @($Written | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Disable-OPIMEntraIDGroup' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }
    Context 'When the old form matches an active member and an owner post that share an id' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-GroupPost -Id 'dup-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'member' -Active
                New-GroupPost -Id 'dup-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'owner' -Active
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $Listing }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'deact-req-001'; action = 'selfDeactivate'; status = 'Revoked' }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'writes AmbiguousName that names -AccessType as the way to tell them apart' {
            $Errs = @()
            Disable-OPIMEntraIDGroup -GroupName 'opim-grp - member (dup-001)' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { $Method -eq 'POST' }
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Disable-OPIMEntraIDGroup'
            $Errs[-1].Exception.Message | Should -BeLike '*-AccessType Member*'
        }

        It 'deactivates the ownership once -AccessType Owner is given' {
            Disable-OPIMEntraIDGroup -GroupName 'opim-grp - member (dup-001)' -AccessType Owner -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'POST' -and $Body.accessId -eq 'owner' -and $Body.groupId -eq 'g-1'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'When the resolver is mocked and -AccessType is given' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Resolved = New-GroupPost -Id 'grp-act-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'owner' -Active
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { $Resolved }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'deact-req-001'; action = 'selfDeactivate'; status = 'Revoked' }
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'hands the resolver the group pillar, the active status and the access type in the lower case it declares' {
            Disable-OPIMEntraIDGroup -GroupName 'opim-grp' -AccessType Owner -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $Pillar -eq 'Group' -and $Status -eq 'Active' -and $AccessType -ceq 'owner' -and $Name -eq 'opim-grp'
            }
        }

        It 'hands the resolver no access type when none is given' {
            Disable-OPIMEntraIDGroup -GroupName 'opim-grp' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $Pillar -eq 'Group' -and -not $AccessType
            }
        }
    }

    Context 'When Graph answers the deactivation with a status' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Active = New-GroupPost -Id 'grp-act-001' -GroupId 'g-1' -Name 'opim-s1-grp' -AccessId 'member' -Active
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { $Active }
            # The answer is read when the POST is made, so each test sets the status it wants.
            $Answer = @{ Status = 'Revoked' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $Response = @{ id = 'deact-req-001'; action = 'selfDeactivate'; accessId = 'member'; groupId = 'g-1'; principalId = 'principal-001' }
                if ($null -ne $Answer.Status) { $Response.status = $Answer.Status }
                $Response
            } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'returns the request and writes neither a warning nor an error for <Status>' -ForEach @(
            @{ Status = 'Revoked' }
            @{ Status = 'revoked' }
        ) {
            $Answer.Status = $Status
            $Result = Disable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleRequest'
            $Result.status | Should -BeExactly $Status
            @($Warns).Count | Should -Be 0
            @($Errs).Count | Should -Be 0
        }

        It 'returns the request with one warning that names <Status>' -ForEach @(
            @{ Status = 'PendingRevocation'; Message = 'opim-s1-grp - member: the deactivation request is PendingRevocation and has not taken effect yet.' }
            @{ Status = 'PendingApproval'; Message = 'opim-s1-grp - member: the deactivation request is PendingApproval. It waits for a decision and has not taken effect yet.' }
        ) {
            $Answer.Status = $Status
            $Result = Disable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.status | Should -BeExactly $Status
            @($Warns).Count | Should -Be 1
            "$($Warns[0])" | Should -BeExactly $Message
            @($Errs).Count | Should -Be 0
        }

        It 'writes ActivationRequestFailed and returns nothing for <Status>' -ForEach @(
            @{ Status = 'Failed' }
            @{ Status = 'Provisioned' }
            @{ Status = 'Granted' }
            @{ Status = 'ScheduleCreated' }
            @{ Status = 'Denied' }
            @{ Status = 'Canceled' }
            @{ Status = 'SomethingNew' }
        ) {
            $Answer.Status = $Status
            $Result = Disable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Disable-OPIMEntraIDGroup'
            $Errs[-1].Exception.Message | Should -BeExactly "opim-s1-grp - member: the deactivation request ended with status '$Status' and did not take effect."
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'ActivationRequestFailed*' }).Count | Should -Be 1
            @($Warns).Count | Should -Be 0
        }

        It 'writes ActivationRequestFailed for an answer that carries no status' {
            $Answer.Status = $null
            $Result = Disable-OPIMEntraIDGroup -GroupName 'opim-s1-grp' -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Disable-OPIMEntraIDGroup'
            $Errs[-1].Exception.Message | Should -BeLike '*ended with no status*'
        }
    }

    Context 'When the help is read (OPIM-37)' {
        It 'describes in .OUTPUTS a PSCustomObject and no Hashtable' {
            $Outputs = @((Get-Help Disable-OPIMEntraIDGroup -Full).returnValues.returnValue.type.name) -join "`n"
            $Outputs | Should -Match 'PSCustomObject'
            $Outputs | Should -Match 'Omnicit\.PIM\.GroupAssignmentScheduleRequest'
            $Outputs | Should -Not -Match 'Hashtable'
        }
    }

    Context 'When the help of -AccessType is read (OPIM-49)' {
        BeforeAll {
            $AccessTypeHelp = (@((Get-Help Disable-OPIMEntraIDGroup -Parameter AccessType).Description.Text) -join ' ') -replace '\s+', ' '
        }

        It 'names the Graph error that refuses to deactivate an ownership held as the only owner' {
            $AccessTypeHelp | Should -Match 'CannotDeleteLastAdminAssignment'
            $AccessTypeHelp | Should -Match 'only owner'
        }

        It 'says the ownership does not end at its end time and what to do instead' {
            $AccessTypeHelp | Should -Match 'does not end at its end time'
            $AccessTypeHelp | Should -Match 'Activate an ownership only of a group that has another owner'
        }

        It 'says only what was seen about a service principal as an owner and promises no remedy' {
            $AccessTypeHelp | Should -Match 'Adding a service principal as a direct owner of the group did not change this in testing'
            $AccessTypeHelp | Should -Not -Match 'until another owner exists'
            $AccessTypeHelp | Should -Not -Match 'does not count'
        }
    }
}
