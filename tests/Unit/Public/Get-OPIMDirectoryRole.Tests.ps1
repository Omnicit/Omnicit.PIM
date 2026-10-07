BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*roleEligibilitySchedules*'
            }
        }

        It 'calls Invoke-OPIMGraphRequest with filterByCurrentUser' {
            Get-OPIMDirectoryRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*directory/administrativeUnits*'
            }
        }

        It 'sets the directoryScope property from the second API response' {
            $Result = Get-OPIMDirectoryRole
            $Result.directoryScope.displayName | Should -Be 'Admin Unit 1'
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*roleAssignmentScheduleInstances*'
            }
        }

        It 'returns an object tagged with Omnicit.PIM.DirectoryAssignmentScheduleInstance' {
            $Result = Get-OPIMDirectoryRole -Activated
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleInstance'
        }
    }

    Context 'When -Activated returns mixed assignment types' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
                return @{
                    value = @(
                        @{
                            id               = 'active-001'
                            assignmentType   = 'Activated'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'Global Administrator' }
                            principal        = @{ displayName = 'Jane Doe' }
                        },
                        @{
                            id               = 'inherited-001'
                            assignmentType   = 'Assigned'
                            directoryScopeId = '/'
                            roleDefinition   = @{ displayName = 'Reader' }
                            principal        = @{ displayName = 'Jane Doe' }
                        }
                    )
                }
            } -ParameterFilter { $Uri -like '*roleAssignmentScheduleInstances*' }
        }

        It 'returns all items from roleAssignmentScheduleInstances without post-filtering by assignmentType' {
            $Result = Get-OPIMDirectoryRole -Activated
            $Result | Should -HaveCount 2
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
                $Uri -like '*roleEligibilitySchedules*' -and $Uri -like '*filterByCurrentUser*'
            }
        }

        It 'calls Invoke-OPIMGraphRequest for roleAssignmentScheduleInstances with filterByCurrentUser' {
            Get-OPIMDirectoryRole -All
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Scope It -ParameterFilter {
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Scope It -ParameterFilter {
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Scope It -ParameterFilter {
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

            # A failed Graph read as the SDK leaves it. The token is built at runtime in the shape a
            # real one has, and says it is not one, so no token-shaped literal sits in this file.
            function New-ScrubFixture {
                param([int]$Status)
                $Token = 'Bearer ' + 'eyJ' + ('A' * 20) + '.' + 'NOT-A-REAL-TOKEN'
                $Request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilitySchedules')
                $null = $Request.Headers.TryAddWithoutValidation('Authorization', $Token)
                $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Status)
                $Response.RequestMessage = $Request
                $Response.Content = [System.Net.Http.StringContent]::new('{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges."}}')
                $Exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Response status code does not indicate success.', $Response)
                [pscustomobject]@{
                    Request = $Request
                    Record  = [System.Management.Automation.ErrorRecord]::new($Exception, 'HttpFail', 'InvalidOperation', $Request)
                }
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
                $script:ScrubFixture = New-ScrubFixture -Status $Status
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

        It 'extracts the schedule ID from trailing parentheses and performs dual-search' {
            Get-OPIMDirectoryRole -RoleName 'Global Administrator -> Directory (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 2 -Scope It -ParameterFilter {
                $Uri -like "*id eq 'elig-001'*"
            }
        }

        It 'returns an object tagged with Omnicit.PIM.DirectoryCombinedSchedule' {
            $Result = Get-OPIMDirectoryRole -RoleName 'Global Administrator -> Directory (elig-001)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryCombinedSchedule'
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
        # Fix round 1 end to end: page 2 answers nothing. The wrapper raises a failed read with no
        # error id; this context measures what a caller receives from the listing.
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
