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
        # A name resolves through Resolve-OPIMSchedule, as on Enable and Disable. The resolver lists by
        # calling this cmdlet without a name, so the transport mocks below answer the nested listing
        # and the whole path runs for real.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            # Typed fakes carry every property a self-referencing ScriptProperty of their type reads:
            # accessId and memberType on an eligibility, accessId, assignmentType and endDateTime on
            # an instance.
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{
                    value = @(
                        @{ id = 'elig-g1'; accessId = 'member'; memberType = 'Direct'; groupId = 'group-001'; principalId = 'principal-001'; group = @{ displayName = 'opim-grp' }; principal = @{ displayName = 'Jane Doe' } }
                        @{ id = 'elig-g2'; accessId = 'owner'; memberType = 'Direct'; groupId = 'group-001'; principalId = 'principal-001'; group = @{ displayName = 'opim-grp' }; principal = @{ displayName = 'Jane Doe' } }
                        @{ id = 'elig-g3'; accessId = 'owner'; memberType = 'Direct'; groupId = 'group-004'; principalId = 'principal-001'; group = @{ displayName = 'Owner Only Group' }; principal = @{ displayName = 'Jane Doe' } }
                        @{ id = 'elig-g4'; accessId = 'member'; memberType = 'Direct'; groupId = 'group-002'; principalId = 'principal-001'; group = @{ displayName = 'Twin Group' }; principal = @{ displayName = 'Jane Doe' } }
                        @{ id = 'elig-g5'; accessId = 'member'; memberType = 'Direct'; groupId = 'group-003'; principalId = 'principal-001'; group = @{ displayName = 'Twin Group' }; principal = @{ displayName = 'Jane Doe' } }
                    )
                }
            } -ParameterFilter { $Uri -like '*eligibilitySchedules*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{
                    value = @(
                        @{ id = 'active-g1'; accessId = 'member'; assignmentType = 'Activated'; endDateTime = '2026-10-08T12:00:00Z'; groupId = 'group-001'; principalId = 'principal-001'; group = @{ displayName = 'opim-grp' }; principal = @{ displayName = 'Jane Doe' } }
                    )
                }
            } -ParameterFilter { $Uri -like '*assignmentScheduleInstances*' }
        }

        Context 'a display name' {
            It 'returns the membership, in each state it is in, and not the ownership' {
                $Result = @(Get-OPIMEntraIDGroup -GroupName 'opim-grp')
                $Result | Should -HaveCount 2
                ($Result | Sort-Object Status | ForEach-Object { "$($_.Status):$($_.id):$($_.accessId)" }) -join ',' |
                    Should -BeExactly 'Active:active-g1:member,Eligible:elig-g1:member'
                foreach ($Post in $Result) {
                    $Post.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupCombinedSchedule'
                }
            }

            It 'takes the name as the first positional argument and ignores its case' {
                $Result = @(Get-OPIMEntraIDGroup 'OPIM-GRP')
                $Result | Should -HaveCount 2
            }

            It 'sends no id and no accessId filter, since the name is matched on the listing' {
                $null = Get-OPIMEntraIDGroup -GroupName 'opim-grp'
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter {
                    $Uri -like '*id eq*' -or $Uri -like '*accessId eq*'
                }
            }
        }

        Context 'with -AccessType' {
            It 'returns the ownership for owner' {
                $Result = @(Get-OPIMEntraIDGroup -GroupName 'opim-grp' -AccessType owner)
                $Result | Should -HaveCount 1
                $Result[0].id | Should -BeExactly 'elig-g2'
                $Result[0].accessId | Should -BeExactly 'owner'
                $Result[0].Status | Should -BeExactly 'Eligible'
            }

            It 'accepts the access type in any case' {
                $Result = @(Get-OPIMEntraIDGroup -GroupName 'opim-grp' -AccessType Owner)
                $Result | Should -HaveCount 1
                $Result[0].id | Should -BeExactly 'elig-g2'
            }

            It 'returns the ownership of a group the user holds only as owner' {
                $Result = @(Get-OPIMEntraIDGroup -GroupName 'Owner Only Group' -AccessType owner)
                $Result | Should -HaveCount 1
                $Result[0].id | Should -BeExactly 'elig-g3'
            }
        }

        Context 'with -Activated' {
            It 'returns only the active instance' {
                $Result = @(Get-OPIMEntraIDGroup -Activated -GroupName 'opim-grp')
                $Result | Should -HaveCount 1
                $Result[0].id | Should -BeExactly 'active-g1'
                $Result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupAssignmentScheduleInstance'
            }

            It 'does not read the eligible list when the active instance is found' {
                $null = Get-OPIMEntraIDGroup -Activated -GroupName 'opim-grp'
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter {
                    $Uri -like '*eligibilitySchedules*'
                }
            }

            It 'writes ActiveRoleNotFound for a group that is not active' {
                $Output = @(Get-OPIMEntraIDGroup -Activated -GroupName 'Twin Group' -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].FullyQualifiedErrorId | Should -BeExactly 'ActiveRoleNotFound,Get-OPIMEntraIDGroup'
                @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            }
        }

        Context 'a display name that two groups carry' {
            It 'writes AmbiguousName with the candidates and returns nothing' {
                $Output = @(Get-OPIMEntraIDGroup -GroupName 'Twin Group' -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].FullyQualifiedErrorId | Should -BeExactly 'AmbiguousName,Get-OPIMEntraIDGroup'
                $Written[0].Exception.Message | Should -Match 'elig-g4'
                $Written[0].Exception.Message | Should -Match 'elig-g5'
                @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            }

            It 'points at the tab-completed form, since -AccessType does not separate them' {
                $Output = @(Get-OPIMEntraIDGroup -GroupName 'Twin Group' -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].Exception.Message | Should -Match 'tab-completed'
                $Written[0].Exception.Message | Should -Not -Match 'add -AccessType'
            }
        }

        Context 'a group the user holds only as owner' {
            It 'writes EligibleRoleNotFound that names -AccessType Owner, and never guesses' {
                $Output = @(Get-OPIMEntraIDGroup -GroupName 'Owner Only Group' -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].FullyQualifiedErrorId | Should -BeExactly 'EligibleRoleNotFound,Get-OPIMEntraIDGroup'
                $Written[0].Exception.Message | Should -Match '-AccessType Owner'
                @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            }
        }

        Context 'a name that no group carries' {
            It 'writes EligibleRoleNotFound and returns nothing' {
                $Output = @(Get-OPIMEntraIDGroup -GroupName 'No Such Group' -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].FullyQualifiedErrorId | Should -BeExactly 'EligibleRoleNotFound,Get-OPIMEntraIDGroup'
                @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            }

            It 'writes it as a non-terminating error' {
                { Get-OPIMEntraIDGroup -GroupName 'No Such Group' -ErrorAction SilentlyContinue } | Should -Not -Throw
            }
        }

        Context 'the old tab-completed form' {
            It 'returns the post whose id ends the string, whatever its access type' {
                $Result = @(Get-OPIMEntraIDGroup -GroupName 'opim-grp - owner (elig-g2)')
                $Result | Should -HaveCount 1
                $Result[0].id | Should -BeExactly 'elig-g2'
                $Result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.GroupCombinedSchedule'
            }

            It 'returns the membership post for the member form' {
                $Result = @(Get-OPIMEntraIDGroup -GroupName 'opim-grp - member (elig-g1)')
                $Result | Should -HaveCount 1
                $Result[0].id | Should -BeExactly 'elig-g1'
            }

            It 'finds nothing when -AccessType excludes the post the id names' {
                $Output = @(Get-OPIMEntraIDGroup -GroupName 'opim-grp - owner (elig-g2)' -AccessType member -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].FullyQualifiedErrorId | Should -BeExactly 'EligibleRoleNotFound,Get-OPIMEntraIDGroup'
                @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            }

            It 'sends no id filter, since the key is matched on the listing' {
                $null = Get-OPIMEntraIDGroup -GroupName 'opim-grp - member (elig-g1)'
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter {
                    $Uri -like '*id eq*'
                }
            }
        }
    }

    Context 'When -GroupName is specified and the listing fails' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: access denied'),
                        'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied,
                        $null
                    )
                )
            }
        }

        It 'writes the listing''s own error and never EligibleRoleNotFound' {
            $Output = @(Get-OPIMEntraIDGroup -GroupName 'opim-grp' -ErrorAction Continue 2>&1)
            $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written | Should -HaveCount 1
            $Written[0].FullyQualifiedErrorId | Should -BeExactly 'Forbidden,Get-OPIMEntraIDGroup'
            @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
        }

        It 'writes the listing''s own error under -ErrorAction SilentlyContinue too' {
            $Errs = $null
            $Output = @(Get-OPIMEntraIDGroup -GroupName 'opim-grp' -ErrorVariable Errs -ErrorAction SilentlyContinue)
            $Output | Should -HaveCount 0
            # -ErrorVariable collects every nested frame's copy as well; the cmdlet's own record is the last.
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'Forbidden,Get-OPIMEntraIDGroup'
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'EligibleRoleNotFound*' }) | Should -HaveCount 0
        }
    }

    Context 'When -GroupName is specified and the resolver is mocked' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {}
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule {
                [PSCustomObject]@{ id = 'resolved-001'; accessId = 'member'; memberType = 'Direct'; Status = 'Eligible' }
            }
        }

        It 'hands the resolver the group pillar, both states and the name, offers -AccessType and gives no access type' {
            $Result = @(Get-OPIMEntraIDGroup -GroupName 'opim-grp')
            $Result | Should -HaveCount 1
            $Result[0].id | Should -BeExactly 'resolved-001'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $Pillar -eq 'Group' -and $Status -eq 'Both' -and $Name -ceq 'opim-grp' -and
                @($FilterParameter) -ceq 'AccessType' -and -not $AccessType
            }
        }

        It 'hands the resolver the access type in the lower case it declares' {
            $null = Get-OPIMEntraIDGroup -GroupName 'opim-grp' -AccessType Owner
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $AccessType -ceq 'owner'
            }
        }

        It 'hands the resolver both states with -All' {
            $null = Get-OPIMEntraIDGroup -All -GroupName 'opim-grp'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $Status -eq 'Both'
            }
        }

        It 'hands the resolver the active state with -Activated' {
            $null = Get-OPIMEntraIDGroup -Activated -GroupName 'opim-grp'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $Pillar -eq 'Group' -and $Status -eq 'Active'
            }
        }

        It 'lists nothing itself, since the resolver lists' {
            $null = Get-OPIMEntraIDGroup -GroupName 'opim-grp'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It
        }

        It 'does not call the resolver without a name' {
            $null = Get-OPIMEntraIDGroup
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 0 -Scope It
        }
    }

    Context 'When the resolver writes an error instead of throwing' {
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

        It 'writes the error as its own, once' {
            $Out = Get-OPIMEntraIDGroup -GroupName 'opim-grp' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            @($Written | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Get-OPIMEntraIDGroup' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It
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
