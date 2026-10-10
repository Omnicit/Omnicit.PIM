BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OPIMScrubFixture.ps1"
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMDirectoryRole' {
    Context 'When called with default parameters (eligible roles, root scope)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    value = @(
                        @{
                            id               = 'elig-001'
                            roleDefinitionId = 'role-def-001'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'Global Administrator' }
                            principal        = @{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }
        }

        It 'calls Invoke-OPIMGraphRequest targeting roleEligibilitySchedules' {
            Get-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleEligibilitySchedules*'
            }
        }

        It 'calls Invoke-OPIMGraphRequest with filterByCurrentUser' {
            Get-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like "*filterByCurrentUser*"
            }
        }

        It 'returns one object' {
            $Result = Get-OPIMDirectoryRole
            $Result | Should -HaveCount 1
        }

        It 'returns an object tagged with Omnicit.PIM.DirectoryEligibilitySchedule' {
            $Result = Get-OPIMDirectoryRole
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryEligibilitySchedule'
        }

        It 'sets the directoryScope property to the root scope shortcut without a second API call' {
            $Result = Get-OPIMDirectoryRole
            $Result.directoryScope.id | Should -Be '/'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It
        }
    }

    Context 'When an item has a non-root directoryScopeId' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    value = @(
                        @{
                            id               = 'elig-002'
                            roleDefinitionId = 'role-def-001'
                            directoryScopeId = '/administrativeUnits/au-001'
                            roleDefinition   = @{ displayName = 'User Administrator' }
                            principal        = @{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ id = '/administrativeUnits/au-001'; displayName = 'Admin Unit 1' }
            } -ParameterFilter { $Uri -like '*directory/administrativeUnits*' }
        }

        It 'calls Invoke-OPIMGraphRequest a second time to rehydrate the directoryScope' {
            Get-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*directory/administrativeUnits*'
            }
        }

        It 'sets the directoryScope property from the second API response' {
            $Result = Get-OPIMDirectoryRole
            $Result.directoryScope.displayName | Should -Be 'Admin Unit 1'
        }
    }

    Context 'When the scope of a post cannot be read (OPIM-19), <Mode>' -ForEach @(
        @{ Mode = 'by default'; Params = @{} }
        @{ Mode = 'with -All'; Params = @{ All = $true } }
    ) {
        # Graph refuses the lookup of one administrative unit the user may not read. That post is
        # listed with its scope id as the scope's name and a warning, and the next post is still
        # looked up. The failure is reported as itself in the warning, never as "not found" and never
        # as an error that would end a caller running under -ErrorAction Stop, such as pim.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            # A spy: the scrub itself is covered by the bearer scrub contexts below; here it is only
            # counted, and asked what record it was given.
            Mock -ModuleName Omnicit.PIM Remove-OPIMErrorRecord {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{
                    value = @(
                        @{ id = 'elig-au-001'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/administrativeUnits/au-001'; roleDefinition = @{ displayName = 'User Administrator' }; principal = @{ displayName = 'Jane Doe' } }
                        @{ id = 'elig-au-002'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/administrativeUnits/au-002'; roleDefinition = @{ displayName = 'User Administrator' }; principal = @{ displayName = 'Jane Doe' } }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied,
                        $null
                    )
                )
            } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/au-001' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = 'au-002'; displayName = 'Sales AU' }
            } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/au-002' }
        }

        It 'returns every post, the unreadable one with its scope id as the scope''s name' {
            $Out = @(Get-OPIMDirectoryRole @Params -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            $Out.Count | Should -Be 2
            $Failed =@($Out | Where-Object directoryScopeId -EQ '/administrativeUnits/au-001')
            $Failed.Count | Should -Be 1
            $Failed[0].id | Should -BeExactly 'elig-au-001'
            $Failed[0].roleDefinition.displayName | Should -BeExactly 'User Administrator'
            $Failed[0].directoryScope.id | Should -BeExactly '/administrativeUnits/au-001'
            $Failed[0].directoryScope.displayName | Should -BeExactly '/administrativeUnits/au-001'
            $Read = @($Out | Where-Object directoryScopeId -EQ '/administrativeUnits/au-002')
            $Read.Count | Should -Be 1
            $Read[0].directoryScope.displayName | Should -BeExactly 'Sales AU'
        }

        It 'looks up the next scope after the one that failed' {
            $null = Get-OPIMDirectoryRole @Params -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -eq 'v1.0/directory/administrativeUnits/au-001'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -eq 'v1.0/directory/administrativeUnits/au-002'
            }
        }

        It 'writes one warning that names the scope and the error as itself, and no error' {
            # The error stream is read through 2>&1, so only a record the cmdlet writes is counted;
            # -ErrorVariable would also hold every nested frame's copy of the record the mock threw.
            $Output = @(Get-OPIMDirectoryRole @Params -WarningVariable Warns -WarningAction SilentlyContinue -ErrorAction Continue 2>&1)
            @($Warns).Count | Should -Be 1
            $Warns[0].Message | Should -BeLike "*'/administrativeUnits/au-001'*"
            $Warns[0].Message | Should -BeLike "*'User Administrator'*"
            $Warns[0].Message | Should -BeLike '*Authorization_RequestDenied*'
            $Warns[0].Message | Should -BeLike '*Insufficient privileges to complete the operation.*'
            $Warns[0].Message | Should -BeLike '*(error id Authorization_RequestDenied*' -Because 'the id is reported beside the message'
            $Warns[0].Message | Should -Not -BeLike '*au-002*'
            @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
            @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count | Should -Be 2 -Because 'both posts are listed'
        }

        It 'lists under -ErrorAction Stop as well, as pim calls it' {
            { $script:Out = @(Get-OPIMDirectoryRole @Params -ErrorAction Stop -WarningAction SilentlyContinue) } | Should -Not -Throw
            $script:Out.Count | Should -Be 2
            # The catch point was reached: the failed lookup was scrubbed once, and then warned about.
            Should -Invoke -ModuleName Omnicit.PIM Remove-OPIMErrorRecord -Times 1 -Exactly -Scope It
        }

        It 'scrubs the caught record first' {
            $null = Get-OPIMDirectoryRole @Params -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Remove-OPIMErrorRecord -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Remove-OPIMErrorRecord -Times 1 -Exactly -Scope It -ParameterFilter {
                $Record.FullyQualifiedErrorId -like 'Authorization_RequestDenied*'
            }
        }
    }

    Context 'When the scope of an activation cannot be read (OPIM-19), <Mode>' -ForEach @(
        @{ Mode = 'with -Activated'; Params = @{ Activated = $true }; Status = $null }
        @{ Mode = 'in the Active rows of -All'; Params = @{ All = $true }; Status = 'Active' }
    ) {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Remove-OPIMErrorRecord {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }
            # A typed fake carries memberType and endDateTime, which the ScriptProperties of an
            # assignment instance read from the object itself.
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{
                    value = @(
                        @{ id = 'active-au-001'; assignmentType = 'Activated'; memberType = 'Direct'; endDateTime = '2026-10-08T12:00:00Z'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/administrativeUnits/au-001'; roleDefinition = @{ displayName = 'User Administrator' }; principal = @{ displayName = 'Jane Doe' } }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied,
                        $null
                    )
                )
            } -ParameterFilter { $Uri -eq 'v1.0/directory/administrativeUnits/au-001' }
        }

        It 'returns the activation with its scope id as the scope''s name and one warning' {
            $Output = @(Get-OPIMDirectoryRole @Params -WarningVariable Warns -WarningAction SilentlyContinue -ErrorAction Continue 2>&1)
            @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
            $Out = @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
            $Out.Count | Should -Be 1
            $Out[0].id | Should -BeExactly 'active-au-001'
            $Out[0].directoryScope.displayName | Should -BeExactly '/administrativeUnits/au-001'
            if ($Status) { $Out[0].Status | Should -BeExactly $Status }
            @($Warns).Count | Should -Be 1
            $Warns[0].Message | Should -BeLike '*Authorization_RequestDenied*'
            Should -Invoke -ModuleName Omnicit.PIM Remove-OPIMErrorRecord -Times 1 -Exactly -Scope It
        }
    }

    Context 'When -Activated is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    value = @(
                        @{
                            id               = 'active-001'
                            assignmentType   = 'Activated'
                            roleDefinitionId = 'role-def-001'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'Global Administrator' }
                            principal        = @{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
        }

        It 'calls Invoke-OPIMGraphRequest targeting roleAssignmentScheduleInstances' {
            Get-OPIMDirectoryRole -Activated
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleInstances*'
            }
        }

        It 'returns an object tagged with Omnicit.PIM.DirectoryAssignmentScheduleInstance' {
            $Result = Get-OPIMDirectoryRole -Activated
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleInstance'
        }
    }

    Context 'When the instances hold a permanent assignment beside an activation (OPIM-17)' {
        # roleAssignmentScheduleInstances lists a time-bound activation (assignmentType Activated) and a
        # permanent assignment (Assigned) alike. Only the activation is the user's to deactivate, so
        # only it is listed, and a permanent assignment costs no scope lookup. Graph's own spelling is
        # kept in the fakes; the comparison ignores letter case.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    value = @(
                        @{
                            id               = 'active-001'
                            assignmentType   = 'Activated'
                            memberType       = 'Direct'
                            endDateTime      = '2026-10-08T12:00:00Z'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'Global Administrator' }
                            principal        = @{ displayName = 'Jane Doe' }
                        },
                        @{
                            id               = 'permanent-001'
                            assignmentType   = 'Assigned'
                            memberType       = 'Direct'
                            endDateTime      = $null
                            directoryScopeId = '/administrativeUnits/au-perm'
                            roleDefinition   = @{ displayName = 'Reader' }
                            principal        = @{ displayName = 'Jane Doe' }
                        },
                        @{
                            id               = 'active-lower-001'
                            assignmentType   = 'activated'
                            memberType       = 'Direct'
                            endDateTime      = '2026-10-08T12:00:00Z'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'User Administrator' }
                            principal        = @{ displayName = 'Jane Doe' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ id = '/administrativeUnits/au-perm'; displayName = 'Permanent AU' }
            } -ParameterFilter { $Uri -like '*directory/administrativeUnits/au-perm*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    value = @(
                        @{
                            id               = 'elig-001'
                            roleDefinitionId = 'role-def-001'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'Global Administrator' }
                            principal        = @{ displayName = 'Jane Doe' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }
        }

        It 'returns only the activations with -Activated, the lower case spelling included' {
            $Result = @(Get-OPIMDirectoryRole -Activated)
            ($Result | ForEach-Object { $_.id }) -join ',' | Should -BeExactly 'active-001,active-lower-001'
        }

        It 'makes no scope lookup for the permanent assignment' {
            $null = Get-OPIMDirectoryRole -Activated
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*v1.0/directory/administrativeUnits*'
            }
        }

        It 'lists only the activations in the Active rows of -All' {
            $Result = @(Get-OPIMDirectoryRole -All)
            ($Result | Where-Object Status -EQ 'Active' | ForEach-Object { $_.id }) -join ',' | Should -BeExactly 'active-001,active-lower-001'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*v1.0/directory/administrativeUnits*'
            }
        }

        It 'leaves the Eligible rows of -All as they are' {
            $Result = @(Get-OPIMDirectoryRole -All)
            ($Result | Where-Object Status -EQ 'Eligible' | ForEach-Object { $_.id }) -join ',' | Should -BeExactly 'elig-001'
        }

        It 'lists only the activations in the Active rows of -Identity' {
            $Result = @(Get-OPIMDirectoryRole -Identity 'active-001')
            ($Result | Where-Object Status -EQ 'Active' | ForEach-Object { $_.id }) -join ',' | Should -BeExactly 'active-001,active-lower-001'
            ($Result | Where-Object Status -EQ 'Eligible' | ForEach-Object { $_.id }) -join ',' | Should -BeExactly 'elig-001'
        }

        It 'lists only the activations in the Active rows of -Filter' {
            $Result = @(Get-OPIMDirectoryRole -Filter "roleDefinitionId eq 'role-def-001'")
            ($Result | Where-Object Status -EQ 'Active' | ForEach-Object { $_.id }) -join ',' | Should -BeExactly 'active-001,active-lower-001'
            ($Result | Where-Object Status -EQ 'Eligible' | ForEach-Object { $_.id }) -join ',' | Should -BeExactly 'elig-001'
        }

        It 'lists only the activations with -Activated -Identity' {
            $Result = @(Get-OPIMDirectoryRole -Activated -Identity 'active-001')
            ($Result | ForEach-Object { $_.id }) -join ',' | Should -BeExactly 'active-001,active-lower-001'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleEligibilitySchedules*'
            }
        }

        It 'lists only the activations with -Activated -Filter' {
            $Result = @(Get-OPIMDirectoryRole -Activated -Filter "roleDefinitionId eq 'role-def-001'")
            ($Result | ForEach-Object { $_.id }) -join ',' | Should -BeExactly 'active-001,active-lower-001'
        }

        It 'returns nothing when the only instance is a permanent assignment' {
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    value = @(
                        @{
                            id               = 'permanent-002'
                            assignmentType   = 'Assigned'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'Reader' }
                            principal        = @{ displayName = 'Jane Doe' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
            @(Get-OPIMDirectoryRole -Activated).Count | Should -Be 0
        }
    }

    Context 'When -All is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
        }

        It 'calls Invoke-OPIMGraphRequest for roleEligibilitySchedules with filterByCurrentUser' {
            Get-OPIMDirectoryRole -All
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleEligibilitySchedules*' -and $Uri -like '*filterByCurrentUser*'
            }
        }

        It 'calls Invoke-OPIMGraphRequest for roleAssignmentScheduleInstances with filterByCurrentUser' {
            Get-OPIMDirectoryRole -All
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleInstances*' -and $Uri -like '*filterByCurrentUser*'
            }
        }
    }

    Context 'When -All and -Activated are both specified' {
        It 'throws a parameter binding error because they are mutually exclusive' {
            { Get-OPIMDirectoryRole -All -Activated } | Should -Throw
        }
    }

    Context 'When -Identity is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    value = @(
                        @{
                            id               = 'elig-001'
                            roleDefinitionId = 'role-def-001'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'Global Administrator' }
                            principal        = @{ displayName = 'Jane Doe' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
        }

        It 'queries both eligible and active endpoints with the id filter (dual-search)' {
            Get-OPIMDirectoryRole -Identity 'elig-001'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Exactly -Scope It -ParameterFilter {
                $Uri -like "*id eq 'elig-001'*"
            }
        }

        It 'returns an object tagged with Omnicit.PIM.DirectoryCombinedSchedule' {
            $Result = Get-OPIMDirectoryRole -Identity 'elig-001'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryCombinedSchedule'
        }

        It 'returns an object with Status set to Eligible for eligible items' {
            $Result = Get-OPIMDirectoryRole -Identity 'elig-001'
            $Result.Status | Should -Be 'Eligible'
        }
    }

    Context 'When -Filter is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
        }

        It 'queries both eligible and active endpoints with the OData filter (dual-search)' {
            Get-OPIMDirectoryRole -Filter "roleDefinitionId eq 'role-def-001'"
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Exactly -Scope It -ParameterFilter {
                $Uri -like "*roleDefinitionId eq 'role-def-001'*"
            }
        }
    }

    Context 'When the result set is empty' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{ value = @() }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }
        }

        It 'returns nothing without throwing' {
            { Get-OPIMDirectoryRole } | Should -Not -Throw
        }

        It 'returns no objects' {
            $Result = Get-OPIMDirectoryRole
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
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Convert-GraphHttpException {
                $Ex = [System.Exception]::new('Access denied')
                return [System.Management.Automation.ErrorRecord]::new(
                    $Ex, 'InsufficientPermissions', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null
                )
            }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Get-OPIMDirectoryRole -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When Graph answers 403 and 500 to the listing' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            # The raw SDK call is mocked here, below the wrapper, so the wrapper's own catch and
            # Convert-GraphHttpException run for real on a record that points at a request message
            # carrying an Authorization header.
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                param($Method, $Uri, $Body, $OutputType)
                $PSCmdlet.ThrowTerminatingError($script:ScrubFixture.Record)
            }

            # Walks every record, exception, target and request reachable from the given roots and
            # returns what each renders as, plus every HttpRequestMessage it passed through.
            function Get-RenderedErrorText {
                param($Records)
                $Seen = [System.Collections.Generic.HashSet[object]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance)
                $Text = [System.Text.StringBuilder]::new()
                $Requests = [System.Collections.Generic.List[object]]::new()
                $Queue = [System.Collections.Generic.Queue[object]]::new()
                foreach ($R in @($Records)) { $Queue.Enqueue($R) }
                while ($Queue.Count -gt 0) {
                    $Item = $Queue.Dequeue()
                    if ($null -eq $Item -or -not $Seen.Add($Item)) { continue }
                    $null = $Text.AppendLine(($Item | Out-String))
                    if ($Item -is [System.Net.Http.HttpRequestMessage]) {
                        $Requests.Add($Item)
                        $null = $Text.AppendLine($Item.Headers.ToString())
                    }
                    foreach ($Name in 'Exception', 'InnerException', 'TargetObject', 'Response', 'RequestMessage', 'ErrorRecord') {
                        try { $P = $Item.PSObject.Properties[$Name]; if ($P) { $Queue.Enqueue($P.Value) } } catch { $null = $PSItem }
                    }
                    try { if ($Item.PSObject.Properties['InnerExceptions']) { foreach ($I in $Item.InnerExceptions) { $Queue.Enqueue($I) } } } catch { $null = $PSItem }
                }
                [pscustomobject]@{ Text = $Text.ToString(); Requests = $Requests }
            }

            # Runs the listing against a fixture and returns the error variable plus every entry the
            # run added to $global:Error. Earlier tests in the same process can leave unrelated
            # strings in $global:Error (an ACRS challenge quotes 'Bearer realm=' and a base64 claim),
            # so only what this run added is read.
            function Invoke-ScrubbedListing {
                param([int]$Status)
                # The token is built in the shape a real one has (Jwt), since the render test below looks for eyJ.
                $script:ScrubFixture = New-ScrubFixture -Status $Status -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilitySchedules' -TokenShape Jwt
                $HadHeader = $script:ScrubFixture.Request.Headers.Contains('Authorization')
                $Before = [System.Collections.Generic.HashSet[object]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance)
                foreach ($Entry in @($global:Error)) { $null = $Before.Add($Entry) }
                Get-OPIMDirectoryRole -ErrorVariable Errs -ErrorAction SilentlyContinue
                $Added = @($global:Error | Where-Object { -not $Before.Contains($_) })
                [pscustomobject]@{ Fixture = $script:ScrubFixture; HadHeader = $HadHeader; Errs = @($Errs); Added = $Added }
            }
        }

        It 'leaves no Authorization header and no token in the error variable, the global error list or any inner exception after a 403' {
            $Run = Invoke-ScrubbedListing -Status 403
            $Run.Errs.Count | Should -BeGreaterThan 0 -Because 'the listing must have failed into its catch, or nothing was scrubbed'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Exactly -Scope It

            $Walk = Get-RenderedErrorText (@($Run.Errs) + @($Run.Added))
            # The raw record is caught inside the wrapper and never reaches the caller, so the walk
            # may find no request at all; the fixture's own request is what proves the scrub ran.
            $Run.HadHeader | Should -BeTrue -Because 'the request must carry the header before the call, or its absence after proves nothing'
            foreach ($Request in $Walk.Requests) { $Request.Headers.Contains('Authorization') | Should -BeFalse }
            $Run.Fixture.Request.Headers.Contains('Authorization') | Should -BeFalse
            $Walk.Text | Should -Not -Match 'Bearer\s+\S'
            $Walk.Text | Should -Not -Match 'eyJ'
            @($Run.Errs | Where-Object { $_.FullyQualifiedErrorId -like 'Authorization_RequestDenied*' }).Count |
                Should -BeGreaterThan 0 -Because 'the converted Graph error is what the caller receives'
        }

        It 'leaves no Authorization header and no token in the error variable, the global error list or any inner exception after a 500' {
            $Run = Invoke-ScrubbedListing -Status 500
            $Run.Errs.Count | Should -BeGreaterThan 0 -Because 'the listing must have failed into its catch, or nothing was scrubbed'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 1 -Exactly -Scope It

            $Walk = Get-RenderedErrorText (@($Run.Errs) + @($Run.Added))
            # The raw record is caught inside the wrapper and never reaches the caller, so the walk
            # may find no request at all; the fixture's own request is what proves the scrub ran.
            $Run.HadHeader | Should -BeTrue -Because 'the request must carry the header before the call, or its absence after proves nothing'
            foreach ($Request in $Walk.Requests) { $Request.Headers.Contains('Authorization') | Should -BeFalse }
            $Run.Fixture.Request.Headers.Contains('Authorization') | Should -BeFalse
            $Walk.Text | Should -Not -Match 'Bearer\s+\S'
            $Walk.Text | Should -Not -Match 'eyJ'
        }
    }

    Context 'When -All returns both eligible and active results' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    value = @(
                        @{
                            id               = 'elig-001'
                            roleDefinitionId = 'role-def-001'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'Global Administrator' }
                            principal        = @{ displayName = 'Jane Doe' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }

            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    value = @(
                        @{
                            id               = 'active-001'
                            assignmentType   = 'Activated'
                            memberType       = 'Direct'
                            endDateTime      = '2026-10-08T12:00:00Z'
                            roleDefinitionId = 'role-def-001'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'Global Administrator' }
                            principal        = @{ displayName = 'Jane Doe' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
        }

        It 'tags all results with Omnicit.PIM.DirectoryCombinedSchedule' {
            $Result = Get-OPIMDirectoryRole -All
            $Result | ForEach-Object {
                $_.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryCombinedSchedule'
            }
        }

        It 'sets Status to Eligible on eligible items and Active on active items' {
            $Result = Get-OPIMDirectoryRole -All
            ($Result | Where-Object Status -EQ 'Eligible').Count | Should -Be 1
            ($Result | Where-Object Status -EQ 'Active').Count | Should -Be 1
        }

        It 'retains the original TypeName for pipeline binding on eligible items' {
            $Result = Get-OPIMDirectoryRole -All
            ($Result | Where-Object Status -EQ 'Eligible').PSObject.TypeNames |
                Should -Contain 'Omnicit.PIM.DirectoryEligibilitySchedule'
        }

        It 'retains the original TypeName for pipeline binding on active items' {
            $Result = Get-OPIMDirectoryRole -All
            ($Result | Where-Object Status -EQ 'Active').PSObject.TypeNames |
                Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleInstance'
        }
    }

    Context 'When -RoleName is specified' {
        # A name resolves through Resolve-OPIMSchedule, as on Enable and Disable. The resolver lists by
        # calling this cmdlet without a name, so the transport mocks below answer the nested listing
        # and the whole path runs for real.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            # Typed fakes carry the notes Graph returns: memberType and endDateTime on an assignment
            # instance.
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{
                    value = @(
                        @{ id = 'elig-001'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/'; roleDefinition = @{ displayName = 'Global Administrator' }; principal = @{ displayName = 'Jane Doe' } }
                        @{ id = 'elig-002'; roleDefinitionId = 'role-def-002'; directoryScopeId = '/administrativeUnits/au-001'; roleDefinition = @{ displayName = 'User Administrator' }; principal = @{ displayName = 'Jane Doe' } }
                        @{ id = 'elig-003'; roleDefinitionId = 'role-def-003'; directoryScopeId = '/'; roleDefinition = @{ displayName = 'Helpdesk Administrator' }; principal = @{ displayName = 'Jane Doe' } }
                        @{ id = 'elig-004'; roleDefinitionId = 'role-def-003'; directoryScopeId = '/administrativeUnits/au-001'; roleDefinition = @{ displayName = 'Helpdesk Administrator' }; principal = @{ displayName = 'Jane Doe' } }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{
                    value = @(
                        @{ id = 'active-001'; assignmentType = 'Activated'; memberType = 'Direct'; endDateTime = '2026-10-08T12:00:00Z'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/'; roleDefinition = @{ displayName = 'Global Administrator' }; principal = @{ displayName = 'Jane Doe' } }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ id = '/administrativeUnits/au-001'; displayName = 'Admin Unit 1' }
            } -ParameterFilter { $Uri -like '*directory/administrativeUnits/au-001*' }
        }

        Context 'a display name that names one role' {
            It 'returns the eligible post tagged as a combined schedule' {
                $Result = @(Get-OPIMDirectoryRole -RoleName 'User Administrator')
                $Result | Should -HaveCount 1
                $Result[0].id | Should -BeExactly 'elig-002'
                $Result[0].Status | Should -BeExactly 'Eligible'
                $Result[0].directoryScope.displayName | Should -BeExactly 'Admin Unit 1'
                $Result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryCombinedSchedule'
                $Result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryEligibilitySchedule'
            }

            It 'takes the name as the first positional argument and ignores its case' {
                $Result = @(Get-OPIMDirectoryRole 'user administrator')
                $Result | Should -HaveCount 1
                $Result[0].id | Should -BeExactly 'elig-002'
            }

            It 'sends no id filter, since the name is matched on the listing' {
                $null = Get-OPIMDirectoryRole -RoleName 'User Administrator'
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter {
                    $Uri -like '*id eq*'
                }
            }
        }

        Context 'a display name whose role is both eligible and active' {
            It 'returns one post per state' {
                $Result = @(Get-OPIMDirectoryRole -RoleName 'Global Administrator')
                $Result | Should -HaveCount 2
                ($Result | Sort-Object Status | ForEach-Object { "$($_.Status):$($_.id)" }) -join ',' |
                    Should -BeExactly 'Active:active-001,Eligible:elig-001'
                foreach ($Post in $Result) {
                    $Post.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryCombinedSchedule'
                }
            }

            It 'reads both lists' {
                $null = Get-OPIMDirectoryRole -RoleName 'Global Administrator'
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Uri -like '*roleEligibilitySchedules*'
                }
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Uri -like '*roleAssignmentScheduleInstances*'
                }
            }
        }

        Context 'with -Activated' {
            It 'returns only the active instance' {
                $Result = @(Get-OPIMDirectoryRole -Activated -RoleName 'Global Administrator')
                $Result | Should -HaveCount 1
                $Result[0].id | Should -BeExactly 'active-001'
                $Result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleInstance'
            }

            It 'does not read the eligible list when the active instance is found' {
                $null = Get-OPIMDirectoryRole -Activated -RoleName 'Global Administrator'
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter {
                    $Uri -like '*roleEligibilitySchedules*'
                }
            }

            It 'writes ActiveRoleNotFound for a role that is not active' {
                $Output = @(Get-OPIMDirectoryRole -Activated -RoleName 'User Administrator' -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].FullyQualifiedErrorId | Should -BeExactly 'ActiveRoleNotFound,Get-OPIMDirectoryRole'
                @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            }
        }

        Context 'a display name that names several roles' {
            It 'writes AmbiguousName with the candidates and returns nothing' {
                $Output = @(Get-OPIMDirectoryRole -RoleName 'Helpdesk Administrator' -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].FullyQualifiedErrorId | Should -BeExactly 'AmbiguousName,Get-OPIMDirectoryRole'
                $Written[0].Exception.Message | Should -Match 'elig-003'
                $Written[0].Exception.Message | Should -Match 'elig-004'
                @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            }

            It 'does not offer -Scope, since the cmdlet has none' {
                $Output = @(Get-OPIMDirectoryRole -RoleName 'Helpdesk Administrator' -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].Exception.Message | Should -Not -Match '-Scope'
                $Written[0].Exception.Message | Should -Match 'tab-completed'
            }
        }

        Context 'a name that no role carries' {
            It 'writes EligibleRoleNotFound and returns nothing' {
                $Output = @(Get-OPIMDirectoryRole -RoleName 'No Such Role' -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].FullyQualifiedErrorId | Should -BeExactly 'EligibleRoleNotFound,Get-OPIMDirectoryRole'
                @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            }

            It 'writes it as a non-terminating error' {
                { Get-OPIMDirectoryRole -RoleName 'No Such Role' -ErrorAction SilentlyContinue } | Should -Not -Throw
            }
        }

        Context 'the old tab-completed form' {
            It 'returns the post whose id ends the string, for a role at an administrative unit' {
                $Result = @(Get-OPIMDirectoryRole -RoleName 'User Administrator -> Admin Unit 1 (elig-002)')
                $Result | Should -HaveCount 1
                $Result[0].id | Should -BeExactly 'elig-002'
            }

            It 'returns the post whose id ends the string, for the root scope form' {
                $Result = @(Get-OPIMDirectoryRole -RoleName 'Global Administrator -> Directory (elig-001)')
                $Result | Should -HaveCount 1
                $Result[0].id | Should -BeExactly 'elig-001'
                $Result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryCombinedSchedule'
            }

            It 'sends no id filter, since the key is matched on the listing' {
                $null = Get-OPIMDirectoryRole -RoleName 'Global Administrator -> Directory (elig-001)'
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter {
                    $Uri -like '*id eq*'
                }
            }
        }
    }

    Context 'When -RoleName is specified and the listing fails' {
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

        It 'writes the listing''s own error and no EligibleRoleNotFound' {
            $Output = @(Get-OPIMDirectoryRole -RoleName 'Global Administrator' -ErrorAction Continue 2>&1)
            $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written | Should -HaveCount 1
            $Written[0].FullyQualifiedErrorId | Should -BeExactly 'Forbidden,Get-OPIMDirectoryRole'
            @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
        }

        It 'writes the listing''s own error under -ErrorAction SilentlyContinue too' {
            $Errs = $null
            $Output = @(Get-OPIMDirectoryRole -RoleName 'Global Administrator' -ErrorVariable Errs -ErrorAction SilentlyContinue)
            $Output | Should -HaveCount 0
            # -ErrorVariable collects every nested frame's copy as well; the cmdlet's own record is the last.
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'Forbidden,Get-OPIMDirectoryRole'
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'EligibleRoleNotFound*' }) | Should -HaveCount 0
        }
    }

    Context 'When -RoleName is specified and the resolver is mocked' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {}
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule {
                [PSCustomObject]@{ id = 'resolved-001'; Status = 'Eligible' }
            }
        }

        It 'hands the resolver the directory pillar, both states and the name, and no filter' {
            $Result = @(Get-OPIMDirectoryRole -RoleName 'Global Administrator')
            $Result | Should -HaveCount 1
            $Result[0].id | Should -BeExactly 'resolved-001'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $Pillar -eq 'Directory' -and $Status -eq 'Both' -and $Name -ceq 'Global Administrator' -and
                -not $FilterParameter -and -not $Scope -and -not $AccessType
            }
        }

        It 'hands the resolver both states with -All' {
            $null = Get-OPIMDirectoryRole -All -RoleName 'Global Administrator'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $Status -eq 'Both'
            }
        }

        It 'hands the resolver the active state with -Activated' {
            $null = Get-OPIMDirectoryRole -Activated -RoleName 'Global Administrator'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $Pillar -eq 'Directory' -and $Status -eq 'Active'
            }
        }

        It 'lists nothing itself, since the resolver lists' {
            $null = Get-OPIMDirectoryRole -RoleName 'Global Administrator'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It
        }

        It 'does not call the resolver without a name' {
            $null = Get-OPIMDirectoryRole
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
            $Out = Get-OPIMDirectoryRole -RoleName 'Global Administrator' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            @($Written | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Get-OPIMDirectoryRole' }).Count | Should -Be 1
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
                        @{ id = 'elig-001'; directoryScopeId = '/'; roleDefinition = @{ displayName = 'Global Administrator' } }
                        @{ id = 'elig-002'; directoryScopeId = '/'; roleDefinition = @{ displayName = 'User Administrator' } }
                    )
                }
            } -ParameterFilter { $All }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{
                    value             = @(@{ id = 'elig-001'; directoryScopeId = '/'; roleDefinition = @{ displayName = 'Global Administrator' } })
                    '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilitySchedules?$skiptoken=2'
                }
            } -ParameterFilter { -not $All }
        }

        It 'passes -All to the transport for the eligible list' {
            $null = Get-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $All -and $Uri -like '*roleEligibilitySchedules*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { -not $All }
        }

        It 'passes -All to the transport for the active list' {
            $null = Get-OPIMDirectoryRole -Activated
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $All -and $Uri -like '*roleAssignmentScheduleInstances*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { -not $All }
        }

        It 'passes -All to the transport for both lists in dual mode' {
            $null = Get-OPIMDirectoryRole -All
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $All -and $Uri -like '*roleEligibilitySchedules*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $All -and $Uri -like '*roleAssignmentScheduleInstances*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It -ParameterFilter { -not $All }
        }

        It 'returns the items of every page' {
            $Result = @(Get-OPIMDirectoryRole)
            ($Result | ForEach-Object { $_.id }) -join ',' | Should -BeExactly 'elig-001,elig-002'
            $Result | ForEach-Object { $_.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryEligibilitySchedule' }
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
                    @{ id = 'elig-001'; directoryScopeId = '/' }
                    @{ id = 'elig-002'; directoryScopeId = '/' }
                )
                $Exception | Add-Member -NotePropertyName PartialValue -NotePropertyValue $Read
                $Exception | Add-Member -NotePropertyName NextLink -NotePropertyValue 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilitySchedules?$skiptoken=3'
                $Exception | Add-Member -NotePropertyName PageNumber -NotePropertyValue 3
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        $Exception, 'generalException', [System.Management.Automation.ErrorCategory]::OperationStopped, $null))
            } -ParameterFilter { $All }
            # Without -All the transport would hand back the first page as if it were the whole list.
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                @{ value = @(@{ id = 'elig-001'; directoryScopeId = '/' }) }
            } -ParameterFilter { -not $All }
        }

        It 'writes the error with the partial result when a later page fails' {
            # The error stream is read through 2>&1, so the record counted is the one the cmdlet
            # writes; -ErrorVariable also holds the record the cmdlet's own try caught.
            $Output = @(Get-OPIMDirectoryRole -ErrorVariable Errs -ErrorAction Continue 2>&1)
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

    Context 'When a later page fails in the transport' {
        # Ruling R-T7b end to end: the raw SDK call is mocked below the wrapper, so the wrapper's paging
        # catch, its scrub and Convert-GraphHttpException run for real, and the caller reads the
        # partial result off the record the cmdlet wrote.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                param($Method, $Uri, $Body, $OutputType)
                if ($Uri -notlike '*skiptoken*') {
                    return @{
                        value             = @(
                            @{ id = 'elig-001'; directoryScopeId = '/' }
                            @{ id = 'elig-002'; directoryScopeId = '/' }
                        )
                        '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilitySchedules?$skiptoken=2'
                    }
                }
                $PSCmdlet.ThrowTerminatingError($script:PageFailure.Record)
            }
        }
        BeforeEach {
            $Token = 'Bearer ' + 'eyJ' + ('A' * 20) + '.' + 'NOT-A-REAL-TOKEN'
            $Request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilitySchedules?$skiptoken=2')
            $null = $Request.Headers.TryAddWithoutValidation('Authorization', $Token)
            $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]500)
            $Response.RequestMessage = $Request
            $Response.Content = [System.Net.Http.StringContent]::new('{"error":{"code":"generalException","message":"An unexpected error occurred."}}')
            $Exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Response status code does not indicate success.', $Response)
            $script:PageFailure = [pscustomobject]@{
                Request = $Request
                Record  = [System.Management.Automation.ErrorRecord]::new($Exception, 'HttpFail', 'InvalidOperation', $Request)
            }
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'carries the partial result from the transport to the caller''s error record' {
            $Output = @(Get-OPIMDirectoryRole -ErrorVariable Errs -ErrorAction Continue 2>&1)
            $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count |
                Should -Be 0 -Because 'page 1 alone is never written as the list'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'generalException,*'
            ($Written[0].Exception.PartialValue | ForEach-Object { $_.id }) -join ',' | Should -BeExactly 'elig-001,elig-002'
            $Written[0].Exception.NextLink | Should -BeExactly 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilitySchedules?$skiptoken=2'
            $Written[0].Exception.PageNumber | Should -Be 2
            $Errs[0].Exception.PartialValue.Count | Should -Be 2
            $script:PageFailure.Request.Headers.Contains('Authorization') | Should -BeFalse
        }
    }

    Context 'When a later page comes back with no body in the transport' {
        # A later page with no body, end to end: page 2 answers nothing. The wrapper raises a failed
        # read with no error id; this context measures what a caller receives from the listing.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-MgGraphRequest {
                param($Method, $Uri, $Body, $OutputType)
                if ($Uri -notlike '*skiptoken*') {
                    return @{
                        value             = @(
                            @{ id = 'elig-001'; directoryScopeId = '/' }
                            @{ id = 'elig-002'; directoryScopeId = '/' }
                        )
                        '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilitySchedules?$skiptoken=2'
                    }
                }
                return $null
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'writes the incomplete list as a failed read with the partial result' {
            $Output = @(Get-OPIMDirectoryRole -ErrorVariable Errs -ErrorAction Continue 2>&1)
            $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count |
                Should -Be 0 -Because 'page 1 alone is never written as the list'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-MgGraphRequest -Times 2 -Exactly -Scope It
            $Written.Count | Should -Be 1
            # No error id: once the listing writes the record its id is only the listing's name
            # (measured 2026-10-07; inside the wrapper it is 'Invoke-OPIMGraphRequest').
            $Written[0].FullyQualifiedErrorId | Should -BeExactly 'Get-OPIMDirectoryRole'
            $Written[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidResult)
            $Written[0].Exception.Message | Should -Match 'no body for this page of the list, so the list is incomplete'
            ($Written[0].Exception.PartialValue | ForEach-Object { $_.id }) -join ',' | Should -BeExactly 'elig-001,elig-002'
            $Written[0].Exception.PageNumber | Should -Be 2
        }
    }
}
