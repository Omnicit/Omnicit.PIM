BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMEntraIDGroup' {
    Context 'When called with default parameters (eligible schedules)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    value = @(
                        @{
                            id          = 'elig-001'
                            accessId    = 'member'
                            groupId     = 'group-001'
                            principalId = 'principal-001'
                            group       = @{ displayName = 'PIM Admins' }
                            principal   = @{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }
        }

        It 'calls Invoke-OPIMGraphRequest targeting eligibilitySchedules' {
            Get-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*eligibilitySchedules*'
            }
        }

        It 'calls Invoke-OPIMGraphRequest with filterByCurrentUser' {
            Get-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like "*filterByCurrentUser*"
            }
        }

        It 'returns one object' {
            $Result = Get-OPIMEntraIDGroup
            $Result | Should -HaveCount 1
        }

        It 'returns an object tagged with Omnicit.PIM.GroupEligibilitySchedule' {
            $Result = Get-OPIMEntraIDGroup
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupEligibilitySchedule'
        }
    }

    Context 'When -Activated is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    value = @(
                        @{
                            id          = 'active-001'
                            accessId    = 'member'
                            groupId     = 'group-001'
                            principalId = 'principal-001'
                            group       = @{ displayName = 'PIM Admins' }
                            principal   = @{ displayName = 'Jane Doe' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*assignmentScheduleInstances*' }
        }

        It 'calls Invoke-OPIMGraphRequest targeting assignmentScheduleInstances' {
            Get-OPIMEntraIDGroup -Activated
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*assignmentScheduleInstances*'
            }
        }

        It 'returns an object tagged with Omnicit.PIM.GroupAssignmentScheduleInstance' {
            $Result = Get-OPIMEntraIDGroup -Activated
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleInstance'
        }

        It 'does not call eligibilitySchedules' {
            Get-OPIMEntraIDGroup -Activated
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter {
                $Uri -like '*eligibilitySchedules*'
            }
        }
    }

    Context 'When -All is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*assignmentScheduleInstances*' }
        }

        It 'calls Invoke-OPIMGraphRequest for eligibilitySchedules with filterByCurrentUser' {
            Get-OPIMEntraIDGroup -All
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*eligibilitySchedules*' -and $Uri -like '*filterByCurrentUser*'
            }
        }

        It 'calls Invoke-OPIMGraphRequest for assignmentScheduleInstances with filterByCurrentUser' {
            Get-OPIMEntraIDGroup -All
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*assignmentScheduleInstances*' -and $Uri -like '*filterByCurrentUser*'
            }
        }
    }

    Context 'When -All and -Activated are both specified' {
        It 'throws a parameter binding error because they are mutually exclusive' {
            { Get-OPIMEntraIDGroup -All -Activated } | Should -Throw
        }
    }

    Context 'When -Identity is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*assignmentScheduleInstances*' }
        }

        It 'queries both eligible and active endpoints with the id filter (dual-search)' {
            Get-OPIMEntraIDGroup -Identity 'elig-001'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Scope It -ParameterFilter {
                $Uri -like "*id eq 'elig-001'*"
            }
        }
    }

    Context 'When -Filter is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*assignmentScheduleInstances*' }
        }

        It 'queries both eligible and active endpoints with the OData filter (dual-search)' {
            Get-OPIMEntraIDGroup -Filter "groupId eq 'group-001'"
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Scope It -ParameterFilter {
                $Uri -like "*groupId eq 'group-001'*"
            }
        }
    }

    Context 'When -AccessType is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }
        }

        It 'appends an accessId eq filter for member' {
            Get-OPIMEntraIDGroup -AccessType member
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like "*accessId eq 'member'*"
            }
        }

        It 'appends an accessId eq filter for owner' {
            Get-OPIMEntraIDGroup -AccessType owner
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like "*accessId eq 'owner'*"
            }
        }
    }

    Context 'When -Identity, -AccessType, and -Filter are all specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*assignmentScheduleInstances*' }
        }

        It 'combines all filter parts and queries both endpoints (dual-search)' {
            Get-OPIMEntraIDGroup -Identity 'elig-001' -AccessType member -Filter "principalId eq 'principal-001'"
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Scope It -ParameterFilter {
                $Uri -like "*id eq 'elig-001'*" -and
                $Uri -like "*accessId eq 'member'*" -and
                $Uri -like "*principalId eq 'principal-001'*"
            }
        }
    }

    Context 'When the result set is empty' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }
        }

        It 'returns nothing without throwing' {
            { Get-OPIMEntraIDGroup } | Should -Not -Throw
        }

        It 'returns no objects' {
            $Result = Get-OPIMEntraIDGroup
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'When the Graph API returns an error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new(
                    '{"error":{"code":"InsufficientPermissions","message":"Access denied"}}'
                )
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Convert-GraphHttpException {
                $Ex = [System.Exception]::new('Access denied')
                return [System.Management.Automation.ErrorRecord]::new(
                    $Ex, 'InsufficientPermissions', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null
                )
            }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Get-OPIMEntraIDGroup -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When -All returns both eligible and active results' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    value = @(
                        @{
                            id          = 'elig-001'
                            accessId    = 'member'
                            groupId     = 'group-001'
                            principalId = 'principal-001'
                            group       = @{ displayName = 'PIM Admins' }
                            principal   = @{ displayName = 'Jane Doe' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    value = @(
                        @{
                            id          = 'active-001'
                            accessId    = 'member'
                            groupId     = 'group-001'
                            principalId = 'principal-001'
                            group       = @{ displayName = 'PIM Admins' }
                            principal   = @{ displayName = 'Jane Doe' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*assignmentScheduleInstances*' }
        }

        It 'tags all results with Omnicit.PIM.GroupCombinedSchedule' {
            $Result = Get-OPIMEntraIDGroup -All
            $Result | ForEach-Object {
                $_.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupCombinedSchedule'
            }
        }

        It 'sets Status to Eligible on eligible items and Active on active items' {
            $Result = Get-OPIMEntraIDGroup -All
            ($Result | Where-Object Status -EQ 'Eligible').Count | Should -Be 1
            ($Result | Where-Object Status -EQ 'Active').Count | Should -Be 1
        }
    }

    Context 'When -All -AccessType owner is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*assignmentScheduleInstances*' }
        }

        It 'includes accessId eq owner filter in both endpoint calls' {
            Get-OPIMEntraIDGroup -All -AccessType owner
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Scope It -ParameterFilter {
                $Uri -like "*accessId eq 'owner'*"
            }
        }
    }

    Context 'When -GroupName is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    value = @(
                        @{
                            id          = 'elig-001'
                            accessId    = 'member'
                            groupId     = 'group-001'
                            principalId = 'principal-001'
                            group       = @{ displayName = 'PIM Admins' }
                            principal   = @{ displayName = 'Jane Doe' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*assignmentScheduleInstances*' }
        }

        It 'extracts the schedule ID from trailing parentheses and performs dual-search' {
            Get-OPIMEntraIDGroup -GroupName 'PIM Admins - member (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Scope It -ParameterFilter {
                $Uri -like "*id eq 'elig-001'*"
            }
        }

        It 'returns an object tagged with Omnicit.PIM.GroupCombinedSchedule' {
            $Result = Get-OPIMEntraIDGroup -GroupName 'PIM Admins - member (elig-001)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupCombinedSchedule'
        }
    }

    Context 'When a list has more than one page' {
        # OPIM-13. Under -All the transport reads every page and hands back one value holding the
        # items of all of them; without it, it hands back the first page only, next link and all.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{
                    value = @(
                        @{ id = 'elig-001'; accessId = 'member'; groupId = 'group-001'; group = @{ displayName = 'PIM Admins' } }
                        @{ id = 'elig-002'; accessId = 'owner'; groupId = 'group-002'; group = @{ displayName = 'Finance Team' } }
                    )
                }
            } -ParameterFilter { $All }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{
                    value             = @(@{ id = 'elig-001'; accessId = 'member'; groupId = 'group-001'; group = @{ displayName = 'PIM Admins' } })
                    '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/eligibilitySchedules?$skiptoken=2'
                }
            } -ParameterFilter { -not $All }
        }

        It 'passes -All to the transport for the eligible list' {
            $null = Get-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $All -and $Uri -like '*eligibilitySchedules*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { -not $All }
        }

        It 'passes -All to the transport for the active list' {
            $null = Get-OPIMEntraIDGroup -Activated
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $All -and $Uri -like '*assignmentScheduleInstances*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { -not $All }
        }

        It 'passes -All to the transport for both lists in dual mode' {
            $null = Get-OPIMEntraIDGroup -All
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $All -and $Uri -like '*eligibilitySchedules*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $All -and $Uri -like '*assignmentScheduleInstances*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { -not $All }
        }

        It 'returns the items of every page' {
            $Result = @(Get-OPIMEntraIDGroup)
            ($Result | ForEach-Object { $_.id }) -join ',' | Should -BeExactly 'elig-001,elig-002'
            $Result | ForEach-Object { $_.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupEligibilitySchedule' }
        }
    }

    Context 'When a later page of the list fails' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            # As the transport throws a failed page under -All: the page's own record, with the items
            # read before it attached to its Exception.
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $Exception = [System.Exception]::new('generalException: An unexpected error occurred.')
                $Read = @(
                    @{ id = 'elig-001'; accessId = 'member'; groupId = 'group-001' }
                    @{ id = 'elig-002'; accessId = 'owner'; groupId = 'group-002' }
                )
                $Exception | Add-Member -NotePropertyName PartialValue -NotePropertyValue $Read
                $Exception | Add-Member -NotePropertyName NextLink -NotePropertyValue 'https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/eligibilitySchedules?$skiptoken=3'
                $Exception | Add-Member -NotePropertyName PageNumber -NotePropertyValue 3
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        $Exception, 'generalException', [System.Management.Automation.ErrorCategory]::OperationStopped, $null))
            } -ParameterFilter { $All }
            # Without -All the transport would hand back the first page as if it were the whole list.
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ value = @(@{ id = 'elig-001'; accessId = 'member'; groupId = 'group-001' }) }
            } -ParameterFilter { -not $All }
        }

        It 'writes the error with the partial result when a later page fails' {
            # The error stream is read through 2>&1, so the record counted is the one the cmdlet
            # writes; -ErrorVariable also holds the record the cmdlet's own try caught.
            $Output = @(Get-OPIMEntraIDGroup -ErrorVariable Errs -ErrorAction Continue 2>&1)
            $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count |
                Should -Be 0 -Because 'a list whose page failed is never written as a shorter list'
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'generalException*'
            $Written[0].Exception.PartialValue.Count | Should -Be 2
            $Written[0].Exception.PageNumber | Should -Be 3
            $Errs[0].Exception.PartialValue.Count | Should -Be 2
        }
    }
}
