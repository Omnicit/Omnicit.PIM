BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Enable-OPIMAzureRole' {
    # The cmdlet sends its activation request, and polls it under -Wait, through the module's own ARM
    # transport, Invoke-OPIMArmRequest, which every context mocks at the module boundary: the PUT mock
    # records the path and the body the cmdlet built and answers like ARM, with the Microsoft Learn
    # api-version 2020-10-01 example of tests/Unit/TestHelpers/ArmResponse (redacted to digit-repeat
    # ids) carrying the status the context wants; the converter that turns the answer into the
    # module's request object runs for real. Every answer is a FRESH object, since the cmdlet writes
    # the status back onto what it gets. New-Guid is mocked, so the request name is a known id.
    BeforeAll {
        $script:RequestJson = Get-Content -Raw -LiteralPath "$PSScriptRoot/../TestHelpers/ArmResponse/roleAssignmentScheduleRequest.json"

        # The path suffix of the request that the New-Guid mock names, after the scope.
        $script:RequestSuffix = '/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/66666666-6666-6666-6666-666666666666?api-version=2020-10-01'

        # The 35 properties of an Az request (A4), which the converter reproduces.
        $script:A4Request = @(
            'ApprovalId', 'Condition', 'ConditionVersion', 'CreatedOn', 'ExpandedPropertiesPrincipalId',
            'ExpandedPropertiesPrincipalType', 'ExpandedPropertiesRoleDefinitionId', 'ExpirationDuration',
            'ExpirationEndDateTime', 'ExpirationType', 'Id', 'Justification', 'LinkedRoleEligibilityScheduleId',
            'Name', 'PrincipalDisplayName', 'PrincipalEmail', 'PrincipalId', 'PrincipalType', 'RequestType',
            'RequestorId', 'ResourceGroupName', 'RoleDefinitionDisplayName', 'RoleDefinitionId',
            'RoleDefinitionType', 'ScheduleInfoStartDateTime', 'Scope', 'ScopeDisplayName', 'ScopeId',
            'ScopeType', 'Status', 'TargetRoleAssignmentScheduleId', 'TargetRoleAssignmentScheduleInstanceId',
            'TicketInfoTicketNumber', 'TicketInfoTicketSystem', 'Type'
        )

        # The ARM request an answer carries: the name, the scope, the status and the eligibility link
        # a context sets on a fresh copy of the fixture. The mock bodies call it with &.
        $script:NewArmRequest = {
            param($Name, $Scope, $Status, $Link, $ApprovalId)
            $Item = $script:RequestJson | ConvertFrom-Json
            $Item.name = $Name
            $Item.properties.scope = $Scope
            $Item.properties.expandedProperties.scope.id = $Scope
            $Item.properties.status = $Status
            $Item.properties.linkedRoleEligibilityScheduleId = $Link
            $Item.properties.approvalId = $ApprovalId
            $Item
        }

        # The request name and the scope that a PUT path names ('' as a prefix means the root scope).
        $script:ParseRequestPath = {
            param($Path)
            $Marker = '/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/'
            $Target = ($Path -split '\?', 2)[0]
            $At = $Target.IndexOf($Marker)
            $Scope = $Target.Substring(0, $At)
            [pscustomobject]@{ Name = $Target.Substring($At + $Marker.Length); Scope = $(if ($Scope) { $Scope } else { '/' }) }
        }

        # A post as Get-OPIMAzureRole lists it, typed as it types it. The Azure type names carry no
        # self-referencing ScriptProperty (Omnicit.PIM.Types.ps1xml), so no extra property is needed.
        function New-AzurePost {
            param([string]$Name, [string]$DefinitionId, [string]$RoleName, [string]$ScopeId, [string]$ScopeName, [switch]$Active)
            $Post = [PSCustomObject]@{
                Name                      = $Name
                ScopeId                   = $ScopeId
                ScopeDisplayName          = $ScopeName
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = $DefinitionId
                RoleDefinitionDisplayName = $RoleName
            }
            $TypeName = if ($Active) { 'Omnicit.PIM.AzureAssignmentScheduleInstance' } else { 'Omnicit.PIM.AzureEligibilitySchedule' }
            $Post.PSObject.TypeNames.Insert(0, $TypeName)
            $Post
        }

        # The keys of a request dictionary, in one order, so a test pins the exact key set.
        function Get-KeyList {
            param($Dictionary)
            (@($Dictionary.Keys) | Sort-Object) -join ','
        }

        # What the PUT mock recorded: the path and the body of every request sent, and the path and the
        # -All switch of every poll. $Answer.Status is the status the PUT mock answers with.
        $Sent = @{
            Puts  = [System.Collections.Generic.List[object]]::new()
            Polls = [System.Collections.Generic.List[object]]::new()
        }
        $Answer = @{ Status = 'Provisioned' }

        # OPIM-39: every role that reaches the request reads the active list first. Nothing is active
        # unless a context answers -Activated itself, and every listing mock that answers the resolver
        # or -Identity is filtered on -not $Activated, so an eligible list is never read as the active one.
        Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { } -ParameterFilter { $Activated }
        Mock -ModuleName Omnicit.PIM New-Guid { [guid]'66666666-6666-6666-6666-666666666666' }
        # The safety net: a call that no context answers fails instead of reaching the real transport.
        Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { throw "No mock answers the ARM call $Method $Path" }
        Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
            $Sent.Puts.Add([pscustomobject]@{ Path = $Path; Body = $Body })
            $Where = & $script:ParseRequestPath $Path
            & $script:NewArmRequest $Where.Name $Where.Scope $Answer.Status $Body.properties.linkedRoleEligibilityScheduleId $null
        } -ParameterFilter { $Method -eq 'PUT' }
        # No Az command and no gate of its own is called any more: the transport gates every request.
        Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest { }
        Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleRequest { }
        Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal { $null }
    }
    BeforeEach {
        $Sent.Puts.Clear()
        $Sent.Polls.Clear()
        $Answer.Status = 'Provisioned'
    }

    Context 'When called with -RoleName (happy path)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                Name                      = 'elig-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
        }

        It 'calls Resolve-OPIMSchedule for the supplied role name' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It
        }

        It 'sends one PUT through the transport and nothing else' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'PUT' }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
        }

        It 'calls no Az command and no ARM gate of its own' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Wait
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMArmRefusal -Times 0 -Scope It
        }

        It 'sends the SelfActivate request type' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            $Sent.Puts[0].Body.properties.requestType | Should -BeExactly 'SelfActivate'
        }

        It 'sends AfterDuration expiration by default' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            $Sent.Puts[0].Body.properties.scheduleInfo.expiration.type | Should -BeExactly 'AfterDuration'
        }

        It 'sends a PT1H ISO 8601 duration when -Hours defaults to 1' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            $Sent.Puts[0].Body.properties.scheduleInfo.expiration.duration | Should -BeExactly 'PT1H'
        }

        It 'sends exactly the activation body of the eligibility and nothing more' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            $Sent.Puts.Count | Should -Be 1
            $SentBody = $Sent.Puts[0].Body
            Get-KeyList $SentBody | Should -BeExactly 'properties'
            $Props = $SentBody.properties
            Get-KeyList $Props | Should -BeExactly 'linkedRoleEligibilityScheduleId,principalId,requestType,roleDefinitionId,scheduleInfo'
            $Props.principalId | Should -BeExactly 'principal-001'
            $Props.roleDefinitionId | Should -BeExactly '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
            $Props.requestType | Should -BeExactly 'SelfActivate'
            $Props.linkedRoleEligibilityScheduleId | Should -BeExactly 'elig-001'
            Get-KeyList $Props.scheduleInfo | Should -BeExactly 'expiration'
            Get-KeyList $Props.scheduleInfo.expiration | Should -BeExactly 'duration,type'
            $Props.scheduleInfo.expiration.type | Should -BeExactly 'AfterDuration'
            $Props.scheduleInfo.expiration.duration | Should -BeExactly 'PT1H'
        }

        It 'puts the request at the scope of the role under the new request name, with the pinned api-version' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            $Sent.Puts[0].Path | Should -BeExactly ('/subscriptions/sub-001' + $script:RequestSuffix)
        }

        It 'returns the request ARM answered, as the request object with the A4 properties' {
            $Result = Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            $Result | Should -Not -BeNullOrEmpty
            $Result.RequestType | Should -Be 'SelfActivate'
            $Result.Status | Should -BeExactly 'Provisioned'
            $Result.Name | Should -BeExactly '66666666-6666-6666-6666-666666666666'
            $Result.LinkedRoleEligibilityScheduleId | Should -BeExactly 'elig-001'
            (@($Result.PSObject.Properties.Name) | Sort-Object) -join ',' | Should -BeExactly (($script:A4Request | Sort-Object) -join ',')
            @($Result.PSObject.Properties).Count | Should -Be 35
            $Result.ScheduleInfoStartDateTime | Should -BeOfType [datetime]
            $Result.ScheduleInfoStartDateTime.Kind | Should -Be ([System.DateTimeKind]::Utc)
        }

        It 'tags the response with Omnicit.PIM.AzureAssignmentScheduleRequest type name' {
            $Result = Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleRequest'
        }
    }

    Context 'When called with multiple role names' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRoleA = [PSCustomObject]@{
                Name                      = 'elig-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            $fakeRoleB = [PSCustomObject]@{
                Name                      = 'elig-002'
                ScopeId                   = '/subscriptions/sub-002'
                ScopeDisplayName          = 'Dev Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-002'
                RoleDefinitionDisplayName = 'Owner'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule {
                if ($Name -like '*elig-001*') { return $fakeRoleA }
                else { return $fakeRoleB }
            }
        }

        It 'sends one request per role name supplied, each for its own eligibility and scope' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)', 'Owner (elig-002)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 2 -Exactly -Scope It -ParameterFilter { $Method -eq 'PUT' }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq ('/subscriptions/sub-001' + $script:RequestSuffix) -and $Body.properties.linkedRoleEligibilityScheduleId -ceq 'elig-001'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq ('/subscriptions/sub-002' + $script:RequestSuffix) -and $Body.properties.linkedRoleEligibilityScheduleId -ceq 'elig-002'
            }
        }
    }

    Context 'When called with pipeline input (-Role parameter set)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                Name                      = 'elig-002'
                ScopeId                   = '/subscriptions/sub-002'
                ScopeDisplayName          = 'Dev Subscription'
                PrincipalId               = 'principal-002'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-002'
                RoleDefinitionDisplayName = 'Owner'
            }
            $fakeRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
        }

        It 'sends the request at the piped role scope for the piped principal' {
            $fakeRole | Enable-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'PUT' -and $Path -ceq ('/subscriptions/sub-002' + $script:RequestSuffix) -and
                $Body.properties.principalId -ceq 'principal-002' -and
                $Body.properties.roleDefinitionId -ceq '/providers/Microsoft.Authorization/roleDefinitions/role-def-002'
            }
        }

        It 'uses the piped role Name as linkedRoleEligibilityScheduleId' {
            $fakeRole | Enable-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'PUT' -and $Body.properties.linkedRoleEligibilityScheduleId -ceq 'elig-002'
            }
        }

        It 'returns the response for the piped role' {
            $Result = $fakeRole | Enable-OPIMAzureRole
            $Result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When the role is at the root scope' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $RootPost = New-AzurePost -Name 'azure-root' -DefinitionId 'role-def-owner' -RoleName 'Owner' -ScopeId '/' -ScopeName 'Tenant Root'
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { $RootPost }
        }

        It 'puts the request under /providers, never under a double slash' {
            Enable-OPIMAzureRole -RoleName 'Owner'
            $Sent.Puts.Count | Should -Be 1
            $Sent.Puts[0].Path | Should -BeExactly $script:RequestSuffix
            $Sent.Puts[0].Path | Should -Not -BeLike '//*'
        }

        It 'sends the root-scope eligibility and role' {
            Enable-OPIMAzureRole -RoleName 'Owner'
            $Sent.Puts[0].Body.properties.linkedRoleEligibilityScheduleId | Should -BeExactly 'azure-root'
            $Sent.Puts[0].Body.properties.roleDefinitionId | Should -BeExactly 'role-def-owner'
        }
    }

    Context 'When -Until is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                Name                      = 'elig-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            $script:UntilDateTime = [DateTime]::Now.AddHours(3)
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
        }

        It 'uses AfterDateTime expiration type when -Until is provided' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Until $script:UntilDateTime
            $Sent.Puts[0].Body.properties.scheduleInfo.expiration.type | Should -BeExactly 'AfterDateTime'
        }

        It 'sends the -Until value as endDateTime, in UTC, in the round-trip format' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Until $script:UntilDateTime
            $End = $Sent.Puts[0].Body.properties.scheduleInfo.expiration.endDateTime
            $End | Should -BeOfType [string]
            $End | Should -BeExactly $script:UntilDateTime.ToUniversalTime().ToString('o')
            $End | Should -BeLike '*Z'
        }

        It 'does not set the duration when -Until is specified' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Until $script:UntilDateTime
            Get-KeyList $Sent.Puts[0].Body.properties.scheduleInfo.expiration | Should -BeExactly 'endDateTime,type'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
        }
    }

    Context 'When -NotBefore and -Until are given (OPIM-15)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Post = New-AzurePost -Name 'azure-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one'
            # A second name resolves to a post of its own: the same post twice is requested once (OPIM-39).
            $PostB = New-AzurePost -Name 'azure-003' -DefinitionId 'role-def-contributor' -RoleName 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001'
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { if ($Name -eq 'Contributor') { $PostB } else { $Post } }
            # A time typed without an offset (such as '4pm') has Kind Unspecified and means local time.
            $script:StartUnspecified = [datetime]::new(2026, 10, 9, 16, 0, 0, [System.DateTimeKind]::Unspecified)
            $script:StartUtc = [datetime]::new(2026, 10, 9, 14, 0, 0, [System.DateTimeKind]::Utc)
            $script:UntilUnspecified = [datetime]::new(2026, 10, 9, 18, 0, 0, [System.DateTimeKind]::Unspecified)
            $script:StartAsLocal = [datetime]::SpecifyKind($script:StartUnspecified, [System.DateTimeKind]::Local).ToUniversalTime()
        }

        It 'sends a -NotBefore without an offset as startDateTime, as local time in UTC' {
            Enable-OPIMAzureRole -RoleName 'Reader' -NotBefore $script:StartUnspecified
            $Start = $Sent.Puts[0].Body.properties.scheduleInfo.startDateTime
            $Start | Should -BeOfType [string]
            $Start | Should -BeExactly $script:StartAsLocal.ToString('o')
            $Start | Should -BeLike '*Z'
        }

        It 'sends a -NotBefore that is already UTC unchanged' {
            Enable-OPIMAzureRole -RoleName 'Reader' -NotBefore $script:StartUtc
            $Sent.Puts[0].Body.properties.scheduleInfo.startDateTime | Should -BeExactly '2026-10-09T14:00:00.0000000Z'
        }

        It 'sends a -NotBefore of Kind Local in UTC' {
            $StartLocal = [datetime]::SpecifyKind($script:StartUnspecified, [System.DateTimeKind]::Local)
            Enable-OPIMAzureRole -RoleName 'Reader' -NotBefore $StartLocal
            $Sent.Puts[0].Body.properties.scheduleInfo.startDateTime | Should -BeExactly $script:StartAsLocal.ToString('o')
        }

        It 'does not send startDateTime when -NotBefore is not given' {
            Enable-OPIMAzureRole -RoleName 'Reader'
            $Sent.Puts.Count | Should -Be 1
            $Sent.Puts[0].Body.properties.scheduleInfo.Contains('startDateTime') | Should -BeFalse
            Get-KeyList $Sent.Puts[0].Body.properties.scheduleInfo | Should -BeExactly 'expiration'
        }

        It 'sends an -Until without an offset as endDateTime, as local time in UTC' {
            Enable-OPIMAzureRole -RoleName 'Reader' -Until $script:UntilUnspecified
            $ExpectedEnd = [datetime]::SpecifyKind($script:UntilUnspecified, [System.DateTimeKind]::Local).ToUniversalTime()
            $Expiration = $Sent.Puts[0].Body.properties.scheduleInfo.expiration
            $Expiration.type | Should -BeExactly 'AfterDateTime'
            $Expiration.endDateTime | Should -BeExactly $ExpectedEnd.ToString('o')
            $Expiration.endDateTime | Should -BeLike '*Z'
        }

        It 'sends both times, in UTC, when -NotBefore and -Until are given together' {
            Enable-OPIMAzureRole -RoleName 'Reader' -NotBefore $script:StartUnspecified -Until $script:UntilUnspecified
            $ExpectedEnd = [datetime]::SpecifyKind($script:UntilUnspecified, [System.DateTimeKind]::Local).ToUniversalTime()
            $Info = $Sent.Puts[0].Body.properties.scheduleInfo
            Get-KeyList $Info | Should -BeExactly 'expiration,startDateTime'
            $Info.startDateTime | Should -BeExactly $script:StartAsLocal.ToString('o')
            $Info.expiration.endDateTime | Should -BeExactly $ExpectedEnd.ToString('o')
        }

        It 'keeps the duration and sends the start when -NotBefore and -Hours are given' {
            Enable-OPIMAzureRole -RoleName 'Reader' -NotBefore $script:StartUtc -Hours 2
            $Info = $Sent.Puts[0].Body.properties.scheduleInfo
            Get-KeyList $Info | Should -BeExactly 'expiration,startDateTime'
            Get-KeyList $Info.expiration | Should -BeExactly 'duration,type'
            $Info.expiration.type | Should -BeExactly 'AfterDuration'
            $Info.expiration.duration | Should -BeExactly 'PT2H'
            $Info.startDateTime | Should -BeExactly '2026-10-09T14:00:00.0000000Z'
        }

        It 'reports a scheduled activation (ScheduleCreated) as a success' {
            $Answer.Status = 'ScheduleCreated'
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' -NotBefore ([datetime]::UtcNow.AddHours(2)) `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.Status | Should -BeExactly 'ScheduleCreated'
            @($Warns).Count | Should -Be 0
            @($Errs).Count | Should -Be 0
        }

        It 'sends the same start with every request when several names are given' {
            Enable-OPIMAzureRole -RoleName 'Reader', 'Contributor' -NotBefore $script:StartUtc
            $Sent.Puts.Count | Should -Be 2
            foreach ($Put in $Sent.Puts) {
                $Put.Body.properties.scheduleInfo.startDateTime | Should -BeExactly '2026-10-09T14:00:00.0000000Z'
            }
        }
    }

    Context 'When -Hours overrides the default duration' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                Name                      = 'elig-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
        }

        It 'sends the PT3H ISO 8601 duration, as AfterDuration with no endDateTime, when -Hours 3 is specified' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Hours 3
            $Expiration = $Sent.Puts[0].Body.properties.scheduleInfo.expiration
            Get-KeyList $Expiration | Should -BeExactly 'duration,type'
            $Expiration.type | Should -BeExactly 'AfterDuration'
            $Expiration.duration | Should -BeExactly 'PT3H'
        }

        It 'sends PT4H ISO 8601 duration when -Hours 4 is specified' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Hours 4
            $Sent.Puts[0].Body.properties.scheduleInfo.expiration.duration | Should -BeExactly 'PT4H'
        }

        It 'sends PT8H ISO 8601 duration when -Hours 8 is specified' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Hours 8
            $Sent.Puts[0].Body.properties.scheduleInfo.expiration.duration | Should -BeExactly 'PT8H'
        }

        It 'sends PT1H when -Hours 1, the lower edge, is given' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Hours 1
            $Sent.Puts.Count | Should -Be 1
            $Sent.Puts[0].Body.properties.scheduleInfo.expiration.duration | Should -BeExactly 'PT1H'
        }

        # XmlConvert.ToString writes 24 hours as P1D, which is the same ISO 8601 duration as PT24H, so
        # the assertion reads the duration back instead of pinning one spelling of it.
        It 'sends a duration of exactly 24 hours when -Hours 24, the upper edge, is given' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Hours 24
            $Sent.Puts.Count | Should -Be 1
            [System.Xml.XmlConvert]::ToTimeSpan($Sent.Puts[0].Body.properties.scheduleInfo.expiration.duration) | Should -Be ([TimeSpan]::FromHours(24))
        }
    }

    Context 'When -Hours is outside 1 to 24' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                Name                      = 'elig-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
        }

        It 'refuses -Hours <_> at binding with ParameterArgumentValidationError' -ForEach 0, -1, 25 {
            $Hours = $_
            { Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Hours $Hours -ErrorAction Stop } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError,Enable-OPIMAzureRole'
        }

        It 'signs in, resolves and sends nothing for -Hours <_>' -ForEach 0, -1, 25 {
            $Hours = $_
            { Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Hours $Hours -ErrorAction Stop } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError,Enable-OPIMAzureRole'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
        }
    }

    Context 'When ticket information is provided' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                Name                      = 'elig-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
        }

        It 'sends ticketNumber and ticketSystem as ticketInfo in the request body' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -TicketNumber 'INC-123' -TicketSystem 'ServiceNow'
            $Props = $Sent.Puts[0].Body.properties
            Get-KeyList $Props | Should -BeExactly 'linkedRoleEligibilityScheduleId,principalId,requestType,roleDefinitionId,scheduleInfo,ticketInfo'
            Get-KeyList $Props.ticketInfo | Should -BeExactly 'ticketNumber,ticketSystem'
            $Props.ticketInfo.ticketNumber | Should -BeExactly 'INC-123'
            $Props.ticketInfo.ticketSystem | Should -BeExactly 'ServiceNow'
        }

        It 'sends only the ticketNumber when no ticket system is given' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -TicketNumber 'INC-123'
            Get-KeyList $Sent.Puts[0].Body.properties.ticketInfo | Should -BeExactly 'ticketNumber'
            $Sent.Puts[0].Body.properties.ticketInfo.ticketNumber | Should -BeExactly 'INC-123'
        }

        It 'sends only the ticketSystem when no ticket number is given' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -TicketSystem 'ServiceNow'
            Get-KeyList $Sent.Puts[0].Body.properties.ticketInfo | Should -BeExactly 'ticketSystem'
            $Sent.Puts[0].Body.properties.ticketInfo.ticketSystem | Should -BeExactly 'ServiceNow'
        }

        It 'does not include ticketInfo when no ticket field is provided' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            $Sent.Puts.Count | Should -Be 1
            $Sent.Puts[0].Body.properties.Contains('ticketInfo') | Should -BeFalse
        }
    }

    Context 'When -Justification is provided' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                Name                      = 'elig-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
        }

        It 'sends the justification text in the request body' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Justification 'Deploying hotfix'
            $Props = $Sent.Puts[0].Body.properties
            Get-KeyList $Props | Should -BeExactly 'justification,linkedRoleEligibilityScheduleId,principalId,requestType,roleDefinitionId,scheduleInfo'
            $Props.justification | Should -BeExactly 'Deploying hotfix'
        }

        It 'does not include justification when none is provided' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            $Sent.Puts.Count | Should -Be 1
            $Sent.Puts[0].Body.properties.Contains('justification') | Should -BeFalse
        }
    }

    Context 'When -WhatIf is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                Name                      = 'elig-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
        }

        It 'sends no request through the transport when -WhatIf is specified' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
        }
    }

    Context 'When the API returns a general error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                Name                      = 'elig-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Unexpected API error'),
                        'UnexpectedApiError',
                        [System.Management.Automation.ErrorCategory]::InvalidOperation,
                        $null
                    )
                )
            } -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'does not throw a terminating error' {
            { Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'writes the transport error as itself and returns nothing' {
            $Result = Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'UnexpectedApiError,Enable-OPIMAzureRole'
            $Errs[-1].Exception.Message | Should -BeExactly 'Unexpected API error'
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'When the transport cannot read the answer to an accepted request' {
        # A 2xx PUT answered with no body, or with a body that cannot be read, is ArmTransportError
        # although ARM may have accepted the request, so the cmdlet writes the transport's record as
        # itself, adds no wording of its own, and still requests the next role. The mock throws the
        # record the transport throws for a write answered with no body, for the Reader eligibility
        # only, and answers the Contributor one as ARM does.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $PostA = New-AzurePost -Name 'azure-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one'
            $PostB = New-AzurePost -Name 'azure-003' -DefinitionId 'role-def-contributor' -RoleName 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001'
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule {
                if ($Name -eq 'Reader') { $PostA } else { $PostB }
            }
            $NoBodyMessage = 'Azure Resource Manager returned no body for the request, so its answer could not be read; the request may have been accepted.'
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                if ($Body.properties.linkedRoleEligibilityScheduleId -eq 'azure-001') {
                    $PSCmdlet.ThrowTerminatingError(
                        [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new($NoBodyMessage),
                            'ArmTransportError',
                            [System.Management.Automation.ErrorCategory]::InvalidResult,
                            $Path
                        )
                    )
                }
                $Where = & $script:ParseRequestPath $Path
                & $script:NewArmRequest $Where.Name $Where.Scope 'Provisioned' $Body.properties.linkedRoleEligibilityScheduleId $null
            } -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'writes ArmTransportError as itself, with the transport message unchanged' {
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'ArmTransportError,Enable-OPIMAzureRole' }).Count | Should -Be 1
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ArmTransportError,Enable-OPIMAzureRole'
            $Errs[-1].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidResult)
            $Errs[-1].Exception.Message | Should -BeExactly $NoBodyMessage
            $Result | Should -BeNullOrEmpty
        }

        It 'writes it for the role it belongs to and still requests and returns the next role' {
            $Result = Enable-OPIMAzureRole -RoleName 'Reader', 'Contributor' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 2 -Exactly -Scope It -ParameterFilter { $Method -eq 'PUT' }
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'ArmTransportError,Enable-OPIMAzureRole' }).Count | Should -Be 1
            @($Result).Count | Should -Be 1
            $Result.LinkedRoleEligibilityScheduleId | Should -BeExactly 'azure-003'
            $Result.Status | Should -BeExactly 'Provisioned'
            @($Warns).Count | Should -Be 0
        }
    }

    Context 'When a role names no Azure scope' {
        # SECURITY 4: a request is made at the role's own ARM scope, so a role object whose ScopeId is
        # empty or lacks its leading slash names none, and nothing is sent for it: one error with no
        # error id (category InvalidArgument, no target object), no active list read for it, and no
        # entry among the posts the command has requested. The next role still runs.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $GoodPost = New-AzurePost -Name 'azure-003' -DefinitionId 'role-def-contributor' -RoleName 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001'
            function New-ScopelessPost {
                param($ScopeId)
                $Post = New-AzurePost -Name 'azure-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/placeholder' -ScopeName 'rg-one'
                $Post.ScopeId = $ScopeId
                $Post
            }
            $NoScopeMessage = 'Reader -> rg-one: the role names no Azure scope, so no request was sent.'
        }

        It 'sends nothing for a ScopeId that is <Name>, and writes one error' -ForEach @(
            @{ Name = 'null'; ScopeId = $null }
            @{ Name = 'empty'; ScopeId = '' }
            @{ Name = 'without its leading slash'; ScopeId = 'subscriptions/sub-001/resourceGroups/rg-one' }
        ) {
            $Bad = New-ScopelessPost -ScopeId $ScopeId
            $Result = $Bad | Enable-OPIMAzureRole -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 0 -Scope It -ParameterFilter { $Activated }
            @($Errs).Count | Should -Be 1
            $Errs[0].Exception.Message | Should -BeExactly $NoScopeMessage
            $Errs[0].FullyQualifiedErrorId | Should -BeExactly 'Enable-OPIMAzureRole'
            $Errs[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidArgument)
            $Errs[0].TargetObject | Should -BeNullOrEmpty
            @($Warns).Count | Should -Be 0
            $Result | Should -BeNullOrEmpty
        }

        It 'still requests the next role after one that names no scope' {
            $Result = Enable-OPIMAzureRole -Role @((New-ScopelessPost -ScopeId ''), $GoodPost) -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'PUT' -and $Path -ceq ('/subscriptions/sub-001' + $script:RequestSuffix) -and
                $Body.properties.linkedRoleEligibilityScheduleId -ceq 'azure-003'
            }
            @($Errs | Where-Object { $_.Exception.Message -eq $NoScopeMessage }).Count | Should -Be 1
            @($Result).Count | Should -Be 1
            $Result.LinkedRoleEligibilityScheduleId | Should -BeExactly 'azure-003'
        }

        It 'never counts a role that names no scope as requested' {
            # Two such objects with the same role definition: each is refused for its scope, and the
            # second never reads as already requested by this command.
            $null = Enable-OPIMAzureRole -Role @((New-ScopelessPost -ScopeId ''), (New-ScopelessPost -ScopeId '')) `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
            @($Errs | Where-Object { $_.Exception.Message -eq $NoScopeMessage }).Count | Should -Be 2
            @($Warns).Count | Should -Be 0
        }
    }

    Context 'When the API returns a JustificationRule policy violation' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                Name                      = 'elig-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
            # The record the transport throws for ARM's 400: the ARM error code as the id.
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('The following policy rules failed: ["JustificationRule"]'),
                        'RoleAssignmentRequestPolicyValidationFailed',
                        [System.Management.Automation.ErrorCategory]::InvalidOperation,
                        $null
                    )
                )
            } -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'sets error details with a hint to use the -Justification parameter' {
            $Errors = @()
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].Exception.Message | Should -BeLike '*-Justification*'
            $Errors[-1].FullyQualifiedErrorId | Should -BeExactly 'RoleAssignmentRequestPolicyValidationFailed,Enable-OPIMAzureRole'
        }
    }

    Context 'When the API returns an ExpirationRule policy violation' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                Name                      = 'elig-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('The following policy rules failed: ["ExpirationRule"]'),
                        'RoleAssignmentRequestPolicyValidationFailed',
                        [System.Management.Automation.ErrorCategory]::InvalidOperation,
                        $null
                    )
                )
            } -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'sets error details with a hint to use -Hours or -Until' {
            $Errors = @()
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].Exception.Message | Should -BeLike '*Use -Hours, or -Until on the Enable-OPIM`* cmdlets, to ask for a shorter activation.'
            $Errors[-1].Exception.Message | Should -Not -BeLike '*-NotAfter*'
        }
    }

    Context 'When -Wait is specified' {
        # OPIM-14 (Scope 2): the wait polls only while the request is in progress, sleeps before each
        # poll, stops at -TimeoutSeconds counted in UTC, reports the last polled request, and reports
        # each role on its own. Time is driven by the clock mock: every Get-Date read moves it by Step.
        # A poll is the GET of the requests made for the signed-in user, at the scope of the request,
        # across every page; the transport mock answers it from $Plan.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $PostA = New-AzurePost -Name 'azure-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one'
            $PostB = New-AzurePost -Name 'azure-003' -DefinitionId 'role-def-contributor' -RoleName 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001'
            $PostRoot = New-AzurePost -Name 'azure-004' -DefinitionId 'role-def-owner' -RoleName 'Owner' -ScopeId '/' -ScopeName 'Tenant Root'
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule {
                if ($Name -eq 'Reader') { $PostA } elseif ($Name -eq 'Owner') { $PostRoot } else { $PostB }
            }
            # Every request gets a name of its own (6666..., 7777..., ...), so a poll can tell them apart.
            $GuidState = @{ N = 0 }
            Mock -ModuleName Omnicit.PIM New-Guid {
                $GuidState.N++
                $D = [string](5 + $GuidState.N)
                [guid]"$($D * 8)-$($D * 4)-$($D * 4)-$($D * 4)-$($D * 12)"
            }
            # Plan.Post is the status the request answers per eligibility; Plan.Poll the statuses the
            # polls of that request answer in turn, the last one repeating. 'Missing' lists no request
            # of that name yet, and 'Throw:<Id>' fails the poll with that id, as the transport does.
            # Plan.Names is the request name each eligibility was sent under.
            $Plan = @{ Post = @{}; Poll = @{}; Count = @{}; Names = @{} }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                $Sent.Puts.Add([pscustomobject]@{ Path = $Path; Body = $Body })
                $Where = & $script:ParseRequestPath $Path
                $Eligibility = $Body.properties.linkedRoleEligibilityScheduleId
                $Plan.Names[$Eligibility] = $Where.Name
                & $script:NewArmRequest $Where.Name $Where.Scope $Plan.Post[$Eligibility] $Eligibility $null
            } -ParameterFilter { $Method -eq 'PUT' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                # MethodBound: a poll is a GET by the transport's default, so it binds no -Method.
                $Sent.Polls.Add([pscustomobject]@{ Path = $Path; All = $All.IsPresent; MethodBound = $PesterBoundParameters.ContainsKey('Method') })
                $PollScope = ($Path -split '/providers/', 2)[0]
                if (-not $PollScope) { $PollScope = '/' }
                $Eligibility = if ($PollScope -eq '/subscriptions/sub-001') { 'azure-003' } elseif ($PollScope -eq '/') { 'azure-004' } else { 'azure-001' }
                $Seen = [int]$Plan.Count[$Eligibility]
                $Plan.Count[$Eligibility] = $Seen + 1
                $List = @($Plan.Poll[$Eligibility])
                $Next = $List[[math]::Min($Seen, $List.Count - 1)]
                # Runaway guard: after 50 polls answer a status no wait goes on for (an unknown one is
                # a failure), so a wait that would never end fails its test instead of hanging the run.
                if ($Seen -ge 50) { $Next = 'RunawayStop' }
                if ($Next -like 'Throw:*') {
                    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('denied'), $Next.Substring(6),
                            [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
                }
                # Another request of the same user at the same scope comes first; the poll must not
                # take it for this one.
                $Items = @(& $script:NewArmRequest 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $PollScope 'Denied' $null 'unrelated')
                if ($Next -ne 'Missing') {
                    $Items += & $script:NewArmRequest $Plan.Names[$Eligibility] $PollScope $Next $Eligibility 'polled'
                }
                [pscustomobject]@{ value = $Items }
            } -ParameterFilter { $Path -like '*/roleAssignmentScheduleRequests?$filter=asTarget()*' }
            $Clock = @{ Now = [datetime]::new(2026, 10, 8, 12, 0, 0, [DateTimeKind]::Utc); Step = 1 }
            Mock -ModuleName Omnicit.PIM Get-Date { $Clock.Now = $Clock.Now.AddSeconds($Clock.Step); $Clock.Now }
            Mock -ModuleName Omnicit.PIM Start-Sleep { }
        }
        BeforeEach {
            # Step 1 by default, so a wait that never ends on its own still reaches its deadline.
            $Clock.Now = [datetime]::new(2026, 10, 8, 12, 0, 0, [DateTimeKind]::Utc)
            $Clock.Step = 1
            $GuidState.N = 0
            $Plan.Post.Clear(); $Plan.Poll.Clear(); $Plan.Count.Clear(); $Plan.Names.Clear()
            $Plan.Post['azure-001'] = 'PendingProvisioning'; $Plan.Post['azure-003'] = 'PendingProvisioning'; $Plan.Post['azure-004'] = 'PendingProvisioning'
            $Plan.Poll['azure-001'] = @('Provisioned'); $Plan.Poll['azure-003'] = @('Provisioned'); $Plan.Poll['azure-004'] = @('Provisioned')
        }

        It 'stops at -TimeoutSeconds, writes ActivationWaitTimedOut and returns nothing' {
            # Deadline = first read (12:00:30) + 60 = 12:01:30. Check 12:01:00: poll once. Check
            # 12:01:30: at the deadline, stop. One poll, never more.
            $Clock.Step = 30
            $Plan.Poll['azure-001'] = @('PendingProvisioning')
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' -Wait -TimeoutSeconds 60 `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationWaitTimedOut,Enable-OPIMAzureRole'
            $Errs[-1].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::OperationTimeout)
            $Errs[-1].Exception.Message | Should -BeExactly 'Reader -> rg-one: the activation request has not completed within 60 seconds (last status: PendingProvisioning). The wait has ended; the request stays submitted and may still complete.'
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'ActivationWaitTimedOut*' }).Count | Should -Be 1
            # The record targets the last polled request, tagged as the module tags a request.
            $Errs[-1].TargetObject.ApprovalId | Should -BeExactly 'polled'
            $Errs[-1].TargetObject.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleRequest'
            @($Warns).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter { $All.IsPresent }
        }

        It 'waits 300 seconds when -TimeoutSeconds is not given' {
            # Deadline = 12:00:30 + 300 = 12:05:30; checks at 12:01:00 ... 12:05:00 poll (9 polls).
            $Clock.Step = 30
            $Plan.Poll['azure-001'] = @('PendingProvisioning')
            $null = Enable-OPIMAzureRole -RoleName 'Reader' -Wait -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].Exception.Message | Should -BeLike '*within 300 seconds*'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 9 -Exactly -Scope It -ParameterFilter { $All.IsPresent }
        }

        It 'times out with the request it sent when the poll never lists it' {
            $Clock.Step = 30
            $Plan.Poll['azure-001'] = @('Missing')
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' -Wait -TimeoutSeconds 60 -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationWaitTimedOut,Enable-OPIMAzureRole'
            $Errs[-1].Exception.Message | Should -BeLike '*(last status: PendingProvisioning)*'
            $Errs[-1].TargetObject.ApprovalId | Should -BeNullOrEmpty
            $Errs[-1].TargetObject.Name | Should -BeExactly '66666666-6666-6666-6666-666666666666'
            $Errs[-1].TargetObject.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleRequest'
        }

        It 'returns the polled request, which carries the final status' {
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' -Wait `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.ApprovalId | Should -BeExactly 'polled'
            $Result.Name | Should -BeExactly '66666666-6666-6666-6666-666666666666'
            $Result.Status | Should -BeExactly 'Provisioned'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleRequest'
            @($Result.PSObject.Properties).Count | Should -Be 35
            @($Warns).Count | Should -Be 0
            @($Errs).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter { $All.IsPresent }
        }

        It 'polls the requests made for the signed-in user with asTarget() at the scope of the request, across every page' {
            $null = Enable-OPIMAzureRole -RoleName 'Reader' -Wait -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $All.IsPresent -and
                $Path -ceq '/subscriptions/sub-001/resourceGroups/rg-one/providers/Microsoft.Authorization/roleAssignmentScheduleRequests?$filter=asTarget()&api-version=2020-10-01'
            }
            $Sent.Polls.Count | Should -Be 1
            $Sent.Polls[0].All | Should -BeTrue
            # A GET by the transport's default: a poll sent with any -Method would be a write.
            $Sent.Polls[0].MethodBound | Should -BeFalse
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMArmRefusal -Times 0 -Scope It
        }

        It 'polls a request at the root scope without a double slash' {
            $null = Enable-OPIMAzureRole -RoleName 'Owner' -Wait -ErrorAction SilentlyContinue
            $Sent.Puts[0].Path | Should -BeExactly '/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/66666666-6666-6666-6666-666666666666?api-version=2020-10-01'
            $Sent.Polls.Count | Should -Be 1
            $Sent.Polls[0].Path | Should -BeExactly '/providers/Microsoft.Authorization/roleAssignmentScheduleRequests?$filter=asTarget()&api-version=2020-10-01'
            $Sent.Polls[0].All | Should -BeTrue
        }

        It 'does not poll with asRequestor(), which ARM refuses to a user without a role at the scope' {
            # Measured live 2026-10-08: asRequestor() at a scope where the user holds no active role
            # is InsufficientPermissions; asTarget() lists the user's own requests there.
            $Plan.Poll['azure-001'] = @('PendingProvisioning', 'Provisioned')
            $Plan.Poll['azure-003'] = @('PendingProvisioning', 'Provisioned')
            $null = Enable-OPIMAzureRole -RoleName 'Reader', 'Contributor' -Wait -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 4 -Exactly -Scope It -ParameterFilter {
                $Path -like '*$filter=asTarget()*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It -ParameterFilter {
                $Path -like '*asRequestor()*'
            }
        }

        It 'keeps polling a request the poll does not list yet' {
            $Plan.Poll['azure-001'] = @('Missing', 'Provisioned')
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' -Wait -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Result.ApprovalId | Should -BeExactly 'polled'
            $Result.Status | Should -BeExactly 'Provisioned'
            @($Errs).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 2 -Exactly -Scope It -ParameterFilter { $All.IsPresent }
        }

        It 'sleeps 5 seconds before each poll' {
            $Plan.Poll['azure-001'] = @('PendingProvisioning', 'Accepted', 'Provisioned')
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' -Wait -ErrorAction SilentlyContinue
            $Result.Status | Should -BeExactly 'Provisioned'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 3 -Exactly -Scope It -ParameterFilter { $All.IsPresent }
            Should -Invoke -ModuleName Omnicit.PIM Start-Sleep -Times 3 -Exactly -Scope It -ParameterFilter { $Seconds -eq 5 }
            Should -Invoke -ModuleName Omnicit.PIM Start-Sleep -Times 3 -Exactly -Scope It
        }

        It 'ends the wait at once for a request that waits for a decision, with one warning' {
            $Plan.Poll['azure-001'] = @('PendingApproval', 'Provisioned')
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' -Wait `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.Status | Should -BeExactly 'PendingApproval'
            @($Warns).Count | Should -Be 1
            "$($Warns[0])" | Should -BeExactly 'Reader -> rg-one: the activation request is PendingApproval. It waits for a decision and has not taken effect yet.'
            @($Errs).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter { $All.IsPresent }
        }

        It 'writes ActivationRequestFailed and returns nothing for a request the poll finds Denied' {
            $Plan.Poll['azure-001'] = @('Denied')
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' -Wait `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Enable-OPIMAzureRole'
            $Errs[-1].Exception.Message | Should -BeExactly "Reader -> rg-one: the activation request ended with status 'Denied' and did not take effect."
            @($Warns).Count | Should -Be 0
        }

        It 'takes only the polled item whose name is the request name, never another request of the user' {
            # The unrelated request comes first in every answer and is Denied; taking it would fail
            # the activation.
            $Plan.Poll['azure-001'] = @('Provisioned')
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' -Wait -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs).Count | Should -Be 0
            @($Result).Count | Should -Be 1
            $Result.Status | Should -BeExactly 'Provisioned'
            $Result.Name | Should -BeExactly '66666666-6666-6666-6666-666666666666'
        }

        It 'writes a failed poll as itself and still requests, polls and returns the next role' {
            $Plan.Poll['azure-001'] = @('Throw:Forbidden')
            $Result = Enable-OPIMAzureRole -RoleName 'Reader', 'Contributor' -Wait `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Enable-OPIMAzureRole' }).Count | Should -Be 1
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'Activation*' }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 2 -Exactly -Scope It -ParameterFilter { $Method -eq 'PUT' }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $All.IsPresent -and $Path -like '/subscriptions/sub-001/resourceGroups/rg-one/providers/*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $All.IsPresent -and $Path -like '/subscriptions/sub-001/providers/*'
            }
            @($Result).Count | Should -Be 1
            $Result.LinkedRoleEligibilityScheduleId | Should -BeExactly 'azure-003'
            $Result.Name | Should -BeExactly '77777777-7777-7777-7777-777777777777'
            $Result.Status | Should -BeExactly 'Provisioned'
            @($Warns).Count | Should -Be 0
        }

        It 'goes on to wait for the next role after one times out' {
            $Clock.Step = 30
            $Plan.Poll['azure-001'] = @('PendingProvisioning')
            $Result = Enable-OPIMAzureRole -RoleName 'Reader', 'Contributor' -Wait -TimeoutSeconds 60 `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'ActivationWaitTimedOut,Enable-OPIMAzureRole' }).Count | Should -Be 1
            @($Result).Count | Should -Be 1
            $Result.LinkedRoleEligibilityScheduleId | Should -BeExactly 'azure-003'
            $Result.Name | Should -BeExactly '77777777-7777-7777-7777-777777777777'
            $Result.Status | Should -BeExactly 'Provisioned'
            @($Warns).Count | Should -Be 0
        }

        It 'writes a refusal the transport throws in the poll as itself and still runs the next role' {
            # The transport gates every request itself. A TenantMismatch on the first poll is written
            # once, ends the wait for that role only (the request was sent and stays submitted), and the
            # next role is requested, polled and returned.
            $Plan.Poll['azure-001'] = @('Throw:TenantMismatch')
            $Result = Enable-OPIMAzureRole -RoleName 'Reader', 'Contributor' -Wait `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'TenantMismatch,Enable-OPIMAzureRole' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 2 -Exactly -Scope It -ParameterFilter { $Method -eq 'PUT' }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $All.IsPresent -and $Path -like '/subscriptions/sub-001/resourceGroups/rg-one/providers/*'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $All.IsPresent -and $Path -like '/subscriptions/sub-001/providers/*'
            }
            @($Result).Count | Should -Be 1
            $Result.LinkedRoleEligibilityScheduleId | Should -BeExactly 'azure-003'
            @($Warns).Count | Should -Be 0
        }

        It 'does not poll a request that answered <Status>' -ForEach @(
            @{ Status = 'Provisioned'; Warnings = 0 }
            @{ Status = 'PendingApproval'; Warnings = 1 }
        ) {
            # Ruling P4: a final status, or one that waits for a person, needs no poll.
            $Plan.Post['azure-001'] = $Status
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' -Wait `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.Status | Should -BeExactly $Status
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleRequest'
            @($Warns).Count | Should -Be $Warnings
            @($Errs).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It -ParameterFilter { $All.IsPresent }
            Should -Invoke -ModuleName Omnicit.PIM Start-Sleep -Times 0 -Scope It
        }

        It 'sends no poll when -Wait is not specified' {
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' -WarningAction SilentlyContinue
            $Result.Status | Should -BeExactly 'PendingProvisioning'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It -ParameterFilter { $All.IsPresent }
        }

        It 'refuses -TimeoutSeconds <Value> before anything is sent' -ForEach @(
            @{ Value = 0 }
            @{ Value = 86401 }
        ) {
            { Enable-OPIMAzureRole -RoleName 'Reader' -Wait -TimeoutSeconds $Value } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError,Enable-OPIMAzureRole'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
        }
    }

    Context 'When the -Wait poll fails with a record that points at a request carrying a token' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $fakeRole = [PSCustomObject]@{
                Name                      = 'elig-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $fakeRole }
            Mock -ModuleName Omnicit.PIM Start-Sleep { }
            # The clock moves a second per read, so a wait that never ended would still stop.
            $Clock = @{ Now = [datetime]::new(2026, 10, 8, 12, 0, 0, [DateTimeKind]::Utc); Step = 1 }
            Mock -ModuleName Omnicit.PIM Get-Date { $Clock.Now = $Clock.Now.AddSeconds($Clock.Step); $Clock.Now }
            # The poll fails as an ARM call does: its record points at the request message, whose
            # Authorization header carries the token. The token is built at runtime and says what it is.
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                $PSCmdlet.ThrowTerminatingError($script:PollFixture.Record)
            } -ParameterFilter { $Path -like '*/roleAssignmentScheduleRequests?$filter=asTarget()*' }

            function New-PollFixture {
                $Token = 'Bearer ' + ('x' * 40) + 'NOT-A-REAL-TOKEN'
                $Request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, 'https://management.azure.com/subscriptions/sub-001/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/x')
                $null = $Request.Headers.TryAddWithoutValidation('Authorization', $Token)
                $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Forbidden)
                $Response.RequestMessage = $Request
                $Exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Operation returned an invalid status code ''Forbidden''', $Response)
                [pscustomobject]@{
                    Request = $Request
                    Record  = [System.Management.Automation.ErrorRecord]::new($Exception, 'AuthorizationFailed', 'PermissionDenied', $Request)
                }
            }
        }

        It 'scrubs the request of the failed poll and writes the failure as itself' {
            # Scope 2: a failed poll no longer ends the command; it is written for this role only.
            # In progress, so -Wait polls it.
            $Answer.Status = 'PendingProvisioning'
            $script:PollFixture = New-PollFixture
            $script:PollFixture.Request.Headers.Contains('Authorization') | Should -BeTrue -Because 'the request must carry the header before the call, or its absence after proves nothing'
            $Result = Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Wait -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'AuthorizationFailed,Enable-OPIMAzureRole' }).Count | Should -Be 1
            $script:PollFixture.Request.Headers.Contains('Authorization') | Should -BeFalse
            $Result | Should -BeNullOrEmpty
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter { $All.IsPresent }
        }
    }

    Context 'When the API throws an exception that has an InnerException' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeRole = [PSCustomObject]@{
                Name                      = 'elig-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                $InnerEx = [System.Exception]::new('Inner network error')
                throw [System.Exception]::new('Outer API error', $InnerEx)
            } -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'does not throw a terminating error' {
            { Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When -Identity is specified and the role is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeElig = [PSCustomObject]@{
                Name                            = 'elig-010'
                RoleDefinitionId                = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName       = 'Storage Blob Reader'
                ScopeId                         = '/subscriptions/sub-001'
                ScopeDisplayName                = 'My Subscription'
                PrincipalId                     = 'principal-001'
                LinkedRoleEligibilityScheduleId = 'schedule-010'
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return $FakeElig } -ParameterFilter { -not $Activated }
        }

        It 'looks up the role via Get-OPIMAzureRole filtered by Name' {
            Enable-OPIMAzureRole -Identity 'elig-010'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter { -not $Activated }
        }

        It 'submits the SelfActivate request through the transport, linked to the eligibility named by the identity' {
            Enable-OPIMAzureRole -Identity 'elig-010'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'PUT' -and $Body.properties.requestType -ceq 'SelfActivate' -and
                $Body.properties.linkedRoleEligibilityScheduleId -ceq 'elig-010'
            }
        }
    }

    Context 'When -Identity is specified but no eligible role is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return $null } -ParameterFilter { -not $Activated }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMAzureRole -Identity 'nonexistent-999' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'writes IdentityNotFound to its own error stream' {
            $Out = Enable-OPIMAzureRole -Identity 'nonexistent-999' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'IdentityNotFound*'
        }
    }

    Context 'When the listing for -Identity fails' {
        # OPIM-12: a listing that cannot be read is reported as itself and stops for that identity;
        # it is never reported as IdentityNotFound. The mock writes the record a listing writes for
        # a failed read (an ARM 403).
        # The mock takes its preference from an explicit -ErrorAction and is Continue otherwise, as a
        # listing is under the default preference: a module-scoped mock body reads the test scope's
        # preference (Stop under the build), never the caller's.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole {
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            } -ParameterFilter { -not $Activated }
        }

        It "writes the listing's error as itself" {
            # The command's own error stream, not -ErrorVariable: -ErrorVariable also collects the
            # record the listing raised and the command caught.
            $Out = Enable-OPIMAzureRole -Identity 'elig-403' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
        }

        It 'does not write IdentityNotFound' {
            $Out = Enable-OPIMAzureRole -Identity 'elig-403' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            @($Written | Where-Object { $_.FullyQualifiedErrorId -like 'IdentityNotFound*' }).Count | Should -Be 0
        }

        It 'sends no activation' {
            Enable-OPIMAzureRole -Identity 'elig-403' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
        }
    }

    Context 'When the listing for -RoleName fails' {
        # OPIM-12: each name resolves on its own. A listing that cannot be read is written as itself
        # for that name, never as "not found", and the next name still runs.
        # The mock takes its preference from an explicit -ErrorAction and is Continue otherwise, as a
        # listing is under the default preference: a module-scoped mock body reads the test scope's
        # preference (Stop under the build), never the caller's.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole {
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            } -ParameterFilter { -not $Activated }
        }

        It "writes the listing's error as itself for each name and activates nothing" {
            # The command's own error stream, not -ErrorVariable: -ErrorVariable also collects the
            # record the listing raised and the command caught.
            $Out = Enable-OPIMAzureRole -RoleName 'Reader -> Sub A (elig-a)', 'Reader -> Sub B (elig-b)' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 2
            @($Written | Where-Object { $_.FullyQualifiedErrorId -like 'Forbidden*' }).Count | Should -Be 2
            @($Written | Where-Object { $_.FullyQualifiedErrorId -like '*NotFound*' }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 2 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
        }
    }

    Context 'When positional parameters are used' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeElig = [PSCustomObject]@{
                Name                            = 'elig-pos-001'
                RoleDefinitionId                = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName       = 'Contributor'
                ScopeId                         = '/subscriptions/sub-001'
                ScopeDisplayName                = 'My Subscription'
                PrincipalId                     = 'principal-001'
                LinkedRoleEligibilityScheduleId = 'elig-pos-001'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeElig }
        }

        It 'accepts RoleName as position 0, Justification as position 1, Hours as position 2' {
            Enable-OPIMAzureRole 'Contributor (elig-pos-001)' 'Incident response' 4
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'PUT' -and
                $Body.properties.justification -ceq 'Incident response' -and
                $Body.properties.scheduleInfo.expiration.duration -ceq 'PT4H'
            }
        }
    }

    Context 'When an AzureAssignmentScheduleInstance is piped from Get-OPIMAzureRole -All' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
        }

        It 'skips the already-active instance and sends no request through the transport' {
            $AlreadyActive = [PSCustomObject]@{
                Name                      = 'active-001'
                AssignmentType            = 'Activated'
                RoleDefinitionDisplayName = 'Contributor'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
            }
            $AlreadyActive.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
            $AlreadyActive | Enable-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
        }
    }

    Context 'When the transport refuses the request' {
        # The transport gates every request itself (SignInRefused, TenantMismatch, AccountMismatch),
        # before anything is sent, and throws the refusal. The cmdlet's catch writes it as itself, in
        # the try that holds the request, and sends nothing more: no poll, no second request.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeRole = [PSCustomObject]@{
                Name                      = 'elig-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeRole }
            $Refusal = @{ Id = 'SignInRefused' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('refused'), $Refusal.Id,
                        [System.Management.Automation.ErrorCategory]::AuthenticationError, 'x'))
            } -ParameterFilter { $Method -eq 'PUT' }
            Mock -ModuleName Omnicit.PIM Start-Sleep { }
        }

        It 'writes <Id> as itself, once, and returns nothing' -ForEach @(
            @{ Id = 'SignInRefused' }
            @{ Id = 'TenantMismatch' }
            @{ Id = 'AccountMismatch' }
        ) {
            $Refusal.Id = $Id
            $Result = Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs | Where-Object FullyQualifiedErrorId -EQ "$Id,Enable-OPIMAzureRole").Count | Should -Be 1
            @($Errs | Where-Object FullyQualifiedErrorId -Like 'RoleAssignmentRequestPolicyValidationFailed*').Count | Should -Be 0
            $Result | Should -BeNullOrEmpty
        }

        It 'sends nothing more than the one refused request, and never polls it' {
            $Refusal.Id = 'SignInRefused'
            $null = Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Wait -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Start-Sleep -Times 0 -Scope It
        }

        It 'calls no Az command and no ARM gate of its own' {
            $Refusal.Id = 'SignInRefused'
            $null = Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMArmRefusal -Times 0 -Scope It
        }
    }

    Context 'When the display name matches the role at more than one scope' {
        # The real resolver runs; only the listing and the transport are mocked.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-AzurePost -Name 'azure-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one'
                New-AzurePost -Name 'azure-002' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-two' -ScopeName 'rg-two'
                New-AzurePost -Name 'azure-003' -DefinitionId 'role-def-contributor' -RoleName 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001'
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { $Listing } -ParameterFilter { -not $Activated }
        }

        It 'writes AmbiguousName and sends no activation' {
            $Errs = @()
            Enable-OPIMAzureRole -RoleName 'Reader' -ErrorVariable Errs -ErrorAction SilentlyContinue
            # The listing was read, so the resolver and the catch that writes its record were reached.
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Enable-OPIMAzureRole'
        }

        It 'tells the user that -Scope separates the candidates' {
            $Errs = @()
            Enable-OPIMAzureRole -RoleName 'Reader' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].Exception.Message | Should -BeLike '*-Scope*'
        }

        It 'activates the one role that -Scope names' {
            Enable-OPIMAzureRole -RoleName 'Reader' -Scope '/subscriptions/sub-001/resourceGroups/rg-two' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'PUT' -and
                $Path -ceq ('/subscriptions/sub-001/resourceGroups/rg-two' + $script:RequestSuffix) -and
                $Body.properties.linkedRoleEligibilityScheduleId -ceq 'azure-002' -and
                $Body.properties.roleDefinitionId -ceq 'role-def-reader'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
        }

        It 'compares -Scope without regard to letter case' {
            Enable-OPIMAzureRole -RoleName 'Reader' -Scope '/SUBSCRIPTIONS/sub-001/resourcegroups/RG-TWO' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Body.properties.linkedRoleEligibilityScheduleId -ceq 'azure-002'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
        }

        It 'writes EligibleRoleNotFound when no role is at the -Scope given' {
            $Errs = @()
            Enable-OPIMAzureRole -RoleName 'Reader' -Scope '/subscriptions/sub-001/resourceGroups/rg-three' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'EligibleRoleNotFound,Enable-OPIMAzureRole'
        }

        It 'accepts the root scope / at binding and finds no role there' {
            $Errs = @()
            Enable-OPIMAzureRole -RoleName 'Reader' -Scope '/' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'EligibleRoleNotFound,Enable-OPIMAzureRole'
        }

        It 'activates nothing when the old form names a role that -Scope excludes' {
            $Errs = @()
            Enable-OPIMAzureRole -RoleName 'Reader -> rg-one (azure-001)' -Scope '/subscriptions/sub-001/resourceGroups/rg-two' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'EligibleRoleNotFound,Enable-OPIMAzureRole'
        }
    }

    Context 'When the display name is unique' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-AzurePost -Name 'azure-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one'
                New-AzurePost -Name 'azure-003' -DefinitionId 'role-def-contributor' -RoleName 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001'
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { $Listing } -ParameterFilter { -not $Activated }
        }

        It 'activates that role with its own ids' {
            Enable-OPIMAzureRole -RoleName 'contributor' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'PUT' -and
                $Path -ceq ('/subscriptions/sub-001' + $script:RequestSuffix) -and
                $Body.properties.linkedRoleEligibilityScheduleId -ceq 'azure-003' -and
                $Body.properties.roleDefinitionId -ceq 'role-def-contributor' -and
                $Body.properties.principalId -ceq 'principal-001'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
        }
    }

    Context 'When several names are given and one of them is unknown' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-AzurePost -Name 'azure-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one'
                New-AzurePost -Name 'azure-003' -DefinitionId 'role-def-contributor' -RoleName 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001'
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { $Listing } -ParameterFilter { -not $Activated }
        }

        It 'writes EligibleRoleNotFound for the unknown name and still activates the other (<Names>)' -ForEach @(
            @{ Names = 'unknown first'; List = @('Unknown Role', 'Contributor') }
            @{ Names = 'unknown last'; List = @('Contributor', 'Unknown Role') }
        ) {
            $Errs = @()
            Enable-OPIMAzureRole -RoleName $List -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'EligibleRoleNotFound,Enable-OPIMAzureRole'
            # -ErrorVariable also collects the record the resolver threw, so count the one the cmdlet wrote.
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'EligibleRoleNotFound,Enable-OPIMAzureRole' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Body.properties.linkedRoleEligibilityScheduleId -ceq 'azure-003'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
        }
    }

    Context 'When -Identity matches more than one listed post' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-AzurePost -Name 'dup-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one'
                New-AzurePost -Name 'dup-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-two' -ScopeName 'rg-two'
                New-AzurePost -Name 'azure-003' -DefinitionId 'role-def-contributor' -RoleName 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001'
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { $Listing } -ParameterFilter { -not $Activated }
        }

        It 'writes AmbiguousName, not IdentityNotFound, and sends no activation' {
            $Errs = @()
            Enable-OPIMAzureRole -Identity 'dup-001' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Enable-OPIMAzureRole'
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'IdentityNotFound*' }).Count | Should -Be 0
        }

        It 'activates the one post when the identity names only one' {
            Enable-OPIMAzureRole -Identity 'azure-003' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Body.properties.linkedRoleEligibilityScheduleId -ceq 'azure-003'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
        }
    }

    Context 'When -Scope is given where it does not belong' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { } -ParameterFilter { -not $Activated }
        }

        It 'fails to bind -Scope together with -Identity' {
            { Enable-OPIMAzureRole -Identity 'azure-001' -Scope '/subscriptions/sub-001' } | Should -Throw -ErrorId 'AmbiguousParameterSet*'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }

        It 'puts -Scope in the RoleName parameter set only' {
            # A piped object binds -Role in another set, so -Scope with it selects the RoleName set, whose
            # mandatory name is then missing. Read the sets from the command metadata instead of
            # binding: an interactive host would prompt for the name.
            (Get-Command Enable-OPIMAzureRole).Parameters['Scope'].ParameterSets.Keys | Should -Be 'RoleName'
        }

        It 'refuses a -Scope that ends with a slash' {
            { Enable-OPIMAzureRole -RoleName 'Reader' -Scope '/subscriptions/sub-001/' } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }

        It 'refuses an empty -Scope' {
            { Enable-OPIMAzureRole -RoleName 'Reader' -Scope '' } |
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
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule {
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
        }

        It 'writes the error as its own for each name and activates nothing' {
            $Out = Enable-OPIMAzureRole -RoleName 'Role A', 'Role B' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 2
            @($Written | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Enable-OPIMAzureRole' }).Count | Should -Be 2
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 2 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
        }
    }

    Context 'When Azure answers the request with a status' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Post = New-AzurePost -Name 'azure-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one'
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { $Post }
        }

        It 'returns the request and writes neither a warning nor an error for <Status>' -ForEach @(
            @{ Status = 'Provisioned' }
            @{ Status = 'Granted' }
            @{ Status = 'ScheduleCreated' }
            @{ Status = 'provisioned' }
        ) {
            $Answer.Status = $Status
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleRequest'
            $Result.Status | Should -BeExactly $Status
            @($Warns).Count | Should -Be 0
            @($Errs).Count | Should -Be 0
        }

        It 'returns the request with one warning that names <Status>' -ForEach @(
            @{ Status = 'PendingApproval'; Message = 'Reader -> rg-one: the activation request is PendingApproval. It waits for a decision and has not taken effect yet.' }
            @{ Status = 'PendingAdminDecision'; Message = 'Reader -> rg-one: the activation request is PendingAdminDecision. It waits for a decision and has not taken effect yet.' }
            @{ Status = 'PendingProvisioning'; Message = 'Reader -> rg-one: the activation request is PendingProvisioning and has not taken effect yet.' }
            @{ Status = 'Accepted'; Message = 'Reader -> rg-one: the activation request is Accepted and has not taken effect yet.' }
        ) {
            $Answer.Status = $Status
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.Status | Should -BeExactly $Status
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
            @{ Status = 'TimedOut' }
            @{ Status = 'SomethingNew' }
        ) {
            $Answer.Status = $Status
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Enable-OPIMAzureRole'
            $Errs[-1].Exception.Message | Should -BeExactly "Reader -> rg-one: the activation request ended with status '$Status' and did not take effect."
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'ActivationRequestFailed*' }).Count | Should -Be 1
            @($Warns).Count | Should -Be 0
        }

        It 'writes ActivationRequestFailed for an answer that carries no status' {
            $Answer.Status = $null
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Enable-OPIMAzureRole'
            $Errs[-1].Exception.Message | Should -BeLike '*ended with no status*'
        }
    }

    Context 'When the first of two requests comes back Failed' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $PostA = New-AzurePost -Name 'azure-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one'
            $PostB = New-AzurePost -Name 'azure-003' -DefinitionId 'role-def-contributor' -RoleName 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001'
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule {
                if ($Name -eq 'Reader') { $PostA } else { $PostB }
            }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                $Where = & $script:ParseRequestPath $Path
                $Link = $Body.properties.linkedRoleEligibilityScheduleId
                $State = if ($Link -eq 'azure-001') { 'Failed' } else { 'Provisioned' }
                & $script:NewArmRequest $Where.Name $Where.Scope $State $Link $null
            } -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'writes one error and still requests and returns the second role' {
            $Result = Enable-OPIMAzureRole -RoleName 'Reader', 'Contributor' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 2 -Exactly -Scope It
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'ActivationRequestFailed,Enable-OPIMAzureRole' }).Count | Should -Be 1
            $Errs[-1].Exception.Message | Should -BeLike 'Reader -> rg-one: *'
            @($Result).Count | Should -Be 1
            $Result.LinkedRoleEligibilityScheduleId | Should -BeExactly 'azure-003'
            $Result.Scope | Should -BeExactly '/subscriptions/sub-001'
            $Result.Status | Should -BeExactly 'Provisioned'
        }
    }

    Context 'When the role is already active (OPIM-39)' {
        # A second request for an active post can end it, so the active list is read before anything
        # is sent. The real resolver runs; the eligible listing, the active listing and the transport
        # are mocked. $Active.List is what Get-OPIMAzureRole -Activated answers; with FailFirst the
        # first read writes an ARM 403, as a listing does, and later reads answer the list.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-AzurePost -Name 'azure-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one'
                New-AzurePost -Name 'azure-003' -DefinitionId 'role-def-contributor' -RoleName 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001'
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { $Listing } -ParameterFilter { -not $Activated }
            $Active = @{ List = @(); FailFirst = $false; Reads = 0 }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole {
                $Active.Reads++
                if ($Active.FailFirst -and $Active.Reads -eq 1) {
                    $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                            [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
                    return
                }
                $Active.List
            } -ParameterFilter { $Activated }
            # With PostThrows every request fails as ARM refuses one.
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                if ($Active.PostThrows) {
                    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('BadRequest: refused'), 'BadRequest',
                            [System.Management.Automation.ErrorCategory]::InvalidOperation, $null))
                }
                $Where = & $script:ParseRequestPath $Path
                & $script:NewArmRequest $Where.Name $Where.Scope 'Provisioned' $Body.properties.linkedRoleEligibilityScheduleId $null
            } -ParameterFilter { $Method -eq 'PUT' }
            $Message = 'Reader -> rg-one is already active, so no new request was sent and the active assignment is left as it is.'
            $Twice = 'Reader -> rg-one was already requested by this command, so no second request was sent.'
        }
        BeforeEach {
            $Active.List = @()
            $Active.FailFirst = $false
            $Active.Reads = 0
            $Active.PostThrows = $false
        }

        It 'sends no request, writes one warning and returns nothing' {
            $Active.List = @(New-AzurePost -Name 'azure-inst-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one' -Active)
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            # The active list was read, so the guard was reached.
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter { $Activated }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
            @($Warns).Count | Should -Be 1
            "$($Warns[0])" | Should -BeExactly $Message
            @($Result).Count | Should -Be 0
            @($Errs).Count | Should -Be 0
        }

        It 'compares the <Key> of the active role without regard to letter case' -ForEach @(
            @{ Key = 'scope'; DefinitionId = 'role-def-reader'; ScopeId = '/SUBSCRIPTIONS/sub-001/resourcegroups/RG-ONE' }
            @{ Key = 'role definition'; DefinitionId = 'ROLE-DEF-READER'; ScopeId = '/subscriptions/sub-001/resourceGroups/rg-one' }
        ) {
            $Active.List = @(New-AzurePost -Name 'azure-inst-001' -DefinitionId $DefinitionId -RoleName 'Reader' -ScopeId $ScopeId -ScopeName 'rg-one' -Active)
            $null = Enable-OPIMAzureRole -RoleName 'Reader' -WarningVariable Warns -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
            @($Warns).Count | Should -Be 1
            "$($Warns[0])" | Should -BeExactly $Message
        }

        It 'sends the request when the role is active only at another scope' {
            $Active.List = @(New-AzurePost -Name 'azure-inst-002' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-two' -ScopeName 'rg-two' -Active)
            $Result = Enable-OPIMAzureRole -RoleName 'Reader' -WarningVariable Warns -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Body.properties.linkedRoleEligibilityScheduleId -ceq 'azure-001' -and
                $Path -ceq ('/subscriptions/sub-001/resourceGroups/rg-one' + $script:RequestSuffix)
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            @($Warns).Count | Should -Be 0
            @($Result).Count | Should -Be 1
        }

        It 'sends the request when another role is active at the same scope' {
            $Active.List = @(New-AzurePost -Name 'azure-inst-004' -DefinitionId 'role-def-contributor' -RoleName 'Contributor' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one' -Active)
            $null = Enable-OPIMAzureRole -RoleName 'Reader' -WarningVariable Warns -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Body.properties.linkedRoleEligibilityScheduleId -ceq 'azure-001'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            @($Warns).Count | Should -Be 0
        }

        It 'warns for the active role and still requests the next one' {
            $Active.List = @(New-AzurePost -Name 'azure-inst-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one' -Active)
            $Result = Enable-OPIMAzureRole -RoleName 'Reader', 'Contributor' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Body.properties.linkedRoleEligibilityScheduleId -ceq 'azure-003'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            @($Warns).Count | Should -Be 1
            "$($Warns[0])" | Should -BeExactly $Message
            @($Result).Count | Should -Be 1
            $Result.LinkedRoleEligibilityScheduleId | Should -BeExactly 'azure-003'
        }

        It 'reads the active list once for several names' {
            $null = Enable-OPIMAzureRole -RoleName 'Reader', 'Contributor' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter { $Activated }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 2 -Exactly -Scope It
        }

        It 'reads the active list once for two objects passed to -Role at once' {
            $null = Enable-OPIMAzureRole -Role @($Listing[0], $Listing[1]) -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter { $Activated }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 2 -Exactly -Scope It
        }

        It 'checks every object piped in and reads the active list once for the whole pipeline' {
            # Each piped object is a process call of its own; the list is read once per command.
            $Active.List = @(New-AzurePost -Name 'azure-inst-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one' -Active)
            $Result = $Listing | Enable-OPIMAzureRole -WarningVariable Warns -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter { $Activated }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Body.properties.linkedRoleEligibilityScheduleId -ceq 'azure-003'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            @($Warns).Count | Should -Be 1
            "$($Warns[0])" | Should -BeExactly $Message
            @($Result).Count | Should -Be 1
        }

        It 'reads no active list when no name resolves' {
            $null = Enable-OPIMAzureRole -RoleName 'Unknown Role' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'EligibleRoleNotFound,Enable-OPIMAzureRole'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 0 -Scope It -ParameterFilter { $Activated }
        }

        It 'writes a failed read of the active list as itself and sends nothing more' {
            # The read fails once and would succeed after: no second read, and no name is sent.
            $Active.FailFirst = $true
            $Result = Enable-OPIMAzureRole -RoleName 'Reader', 'Contributor' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'Forbidden,Enable-OPIMAzureRole'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter { $Activated }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
            @($Result).Count | Should -Be 0
            @($Warns).Count | Should -Be 0
        }

        It 'writes the failed read to its own error stream once' {
            $Active.FailFirst = $true
            $Out = Enable-OPIMAzureRole -RoleName 'Reader', 'Contributor' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeExactly 'Forbidden,Enable-OPIMAzureRole'
        }

        It 'writes a failed read once for several piped roles and sends nothing' {
            # The read fails once and would succeed after: a later piped role reads no list again.
            $Active.FailFirst = $true
            $Out = $Listing | Enable-OPIMAzureRole -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeExactly 'Forbidden,Enable-OPIMAzureRole'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter { $Activated }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
        }

        It 'sends one request for the same role named twice, by its name and its old form' {
            $Result = Enable-OPIMAzureRole -RoleName 'Reader', 'Reader -> rg-one (azure-001)' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            @($Warns).Count | Should -Be 1
            "$($Warns[0])" | Should -BeExactly $Twice
            @($Result).Count | Should -Be 1
            @($Errs).Count | Should -Be 0
        }

        It 'sends one request for the same role piped twice' {
            $Result = @($Listing[0], $Listing[0]) | Enable-OPIMAzureRole -WarningVariable Warns -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            @($Warns).Count | Should -Be 1
            "$($Warns[0])" | Should -BeExactly $Twice
            @($Result).Count | Should -Be 1
        }

        It 'sends one request for the same role passed twice to -Role' {
            $null = Enable-OPIMAzureRole -Role @($Listing[0], $Listing[0]) -WarningVariable Warns -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            @($Warns).Count | Should -Be 1
            "$($Warns[0])" | Should -BeExactly $Twice
        }

        It 'sends both posts of one role that differ only in scope, with nothing active' {
            # The same Reader RoleDefinitionId at two resource groups, in ONE call and against an
            # empty active list: only the second part of the requested-post key, the scope, tells the
            # two apart, so a key on the role definition alone would withhold the second post.
            $RgTwoPost = New-AzurePost -Name 'azure-004' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-two' -ScopeName 'rg-two'
            $Result = Enable-OPIMAzureRole -Role @($Listing[0], $RgTwoPost) `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            # The active list was read and was empty, so only the requested-post key stood in the way.
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter { $Activated }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq ('/subscriptions/sub-001/resourceGroups/rg-one' + $script:RequestSuffix) -and
                $Body.properties.roleDefinitionId -ceq 'role-def-reader' -and $Body.properties.linkedRoleEligibilityScheduleId -ceq 'azure-001'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq ('/subscriptions/sub-001/resourceGroups/rg-two' + $script:RequestSuffix) -and
                $Body.properties.roleDefinitionId -ceq 'role-def-reader' -and $Body.properties.linkedRoleEligibilityScheduleId -ceq 'azure-004'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 2 -Exactly -Scope It
            @($Warns | Where-Object { "$_" -like '*was already requested by this command*' }).Count | Should -Be 0
            @($Warns).Count | Should -Be 0
            @($Errs).Count | Should -Be 0
            @($Result).Count | Should -Be 2
        }

        It 'does not send the role again after its first request failed' {
            # The post counts as requested before the request is sent, so a failed one is not repeated.
            $Active.PostThrows = $true
            $null = Enable-OPIMAzureRole -RoleName 'Reader', 'Reader -> rg-one (azure-001)' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'BadRequest,Enable-OPIMAzureRole'
            @($Warns).Count | Should -Be 1
            "$($Warns[0])" | Should -BeExactly $Twice
        }
    }
}
