BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Disable-OPIMAzureRole' {
    # The cmdlet sends its deactivation request through the module's own ARM transport,
    # Invoke-OPIMArmRequest, which every context mocks at the module boundary: the PUT mock records the
    # path and the body the cmdlet built and answers like ARM, with the Microsoft Learn api-version
    # 2020-10-01 example of tests/Unit/TestHelpers/ArmResponse (redacted to digit-repeat ids) carrying
    # the status the context wants; the converter that turns the answer into the module's request
    # object runs for real. Every answer is a FRESH object, since the cmdlet writes the status back
    # onto what it gets. New-Guid is mocked, so the request name is a known id.
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

        # The ARM request an answer carries: the name, the scope, the status and the request type a
        # context sets on a fresh copy of the fixture. The mock bodies call it with &.
        $script:NewArmRequest = {
            param($Name, $Scope, $Status, $RequestType)
            $Item = $script:RequestJson | ConvertFrom-Json
            $Item.name = $Name
            $Item.properties.scope = $Scope
            $Item.properties.expandedProperties.scope.id = $Scope
            $Item.properties.status = $Status
            $Item.properties.requestType = $RequestType
            $Item.properties.linkedRoleEligibilityScheduleId = $null
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

        # What the PUT mock recorded: the path and the body of every request sent.
        # $Answer.Status is the status the PUT mock answers with.
        $Sent = @{ Puts = [System.Collections.Generic.List[object]]::new() }
        $Answer = @{ Status = 'Revoked' }

        Mock -ModuleName Omnicit.PIM New-Guid { [guid]'66666666-6666-6666-6666-666666666666' }
        # The safety net: a call that no context answers fails instead of reaching the real transport.
        Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { throw "No mock answers the ARM call $Method $Path" }
        Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
            $Sent.Puts.Add([pscustomobject]@{ Path = $Path; Body = $Body })
            $Where = & $script:ParseRequestPath $Path
            & $script:NewArmRequest $Where.Name $Where.Scope $Answer.Status 'SelfDeactivate'
        } -ParameterFilter { $Method -eq 'PUT' }
        # No gate of its own is called: the transport gates every request.
        Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal { $null }
    }
    BeforeEach {
        $Sent.Puts.Clear()
        $Answer.Status = 'Revoked'
    }

    Context 'When called with -RoleName (happy path)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeRole = [PSCustomObject]@{
                Name                      = 'active-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeRole }
        }

        It 'calls Resolve-OPIMSchedule for the supplied role name' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It
        }

        It 'sends one PUT through the transport and nothing else' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Method -eq 'PUT' }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
        }

        It 'calls no ARM gate of its own' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMArmRefusal -Times 0 -Scope It
        }

        It 'sends the SelfDeactivate request type' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            $Sent.Puts[0].Body.properties.requestType | Should -BeExactly 'SelfDeactivate'
        }

        It 'puts the request at the role scope under the new request name, with the pinned api-version' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            $Sent.Puts[0].Path | Should -BeExactly ('/subscriptions/sub-001' + $script:RequestSuffix)
        }

        It 'sends exactly the deactivation body, with no eligibility link and no schedule' {
            # OPIM-24: ARM documents the field for an activation only. The exact key set proves the body
            # was sent, so the negative half cannot pass on a request that never went out.
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            $Sent.Puts.Count | Should -Be 1
            $SentBody = $Sent.Puts[0].Body
            Get-KeyList $SentBody | Should -BeExactly 'properties'
            $Props = $SentBody.properties
            Get-KeyList $Props | Should -BeExactly 'principalId,requestType,roleDefinitionId'
            $Props.principalId | Should -BeExactly 'principal-001'
            $Props.roleDefinitionId | Should -BeExactly '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
            $Props.requestType | Should -BeExactly 'SelfDeactivate'
            $Props.Contains('linkedRoleEligibilityScheduleId') | Should -BeFalse
            $Props.Contains('scheduleInfo') | Should -BeFalse
        }

        It 'returns the request ARM answered, as the request object with the A4 properties' {
            $Result = Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            $Result | Should -Not -BeNullOrEmpty
            $Result.RequestType | Should -BeExactly 'SelfDeactivate'
            $Result.Status | Should -BeExactly 'Revoked'
            $Result.Name | Should -BeExactly '66666666-6666-6666-6666-666666666666'
            (@($Result.PSObject.Properties.Name) | Sort-Object) -join ',' | Should -BeExactly (($script:A4Request | Sort-Object) -join ',')
            @($Result.PSObject.Properties).Count | Should -Be 35
            $Result.ScheduleInfoStartDateTime | Should -BeOfType [datetime]
            $Result.ScheduleInfoStartDateTime.Kind | Should -Be ([System.DateTimeKind]::Utc)
        }

        It 'tags the response with Omnicit.PIM.AzureAssignmentScheduleRequest type name' {
            $Result = Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleRequest'
        }
    }

    Context 'When called with pipeline input (-Role parameter set)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeRole = [PSCustomObject]@{
                Name                      = 'active-002'
                ScopeId                   = '/subscriptions/sub-002'
                ScopeDisplayName          = 'Dev Subscription'
                PrincipalId               = 'principal-002'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-002'
                RoleDefinitionDisplayName = 'Owner'
            }
            $FakeRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
        }

        It 'sends the request at the piped role scope for the piped principal' {
            $FakeRole | Disable-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'PUT' -and $Path -ceq ('/subscriptions/sub-002' + $script:RequestSuffix) -and
                $Body.properties.principalId -ceq 'principal-002'
            }
        }

        It 'sends no eligibility link for a piped role either' {
            $FakeRole | Disable-OPIMAzureRole
            $Sent.Puts.Count | Should -Be 1
            $Props = $Sent.Puts[0].Body.properties
            Get-KeyList $Props | Should -BeExactly 'principalId,requestType,roleDefinitionId'
            $Props.requestType | Should -BeExactly 'SelfDeactivate'
            $Props.principalId | Should -BeExactly 'principal-002'
            $Props.roleDefinitionId | Should -BeExactly '/providers/Microsoft.Authorization/roleDefinitions/role-def-002'
            $Props.Contains('linkedRoleEligibilityScheduleId') | Should -BeFalse
        }
    }

    Context 'When the role is at the root scope' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $RootPost = New-AzurePost -Name 'active-root' -DefinitionId 'role-def-owner' -RoleName 'Owner' -ScopeId '/' -ScopeName 'Tenant Root' -Active
        }

        It 'puts the request under /providers, never under a double slash' {
            $RootPost | Disable-OPIMAzureRole
            $Sent.Puts.Count | Should -Be 1
            $Sent.Puts[0].Path | Should -BeExactly $script:RequestSuffix
            $Sent.Puts[0].Path | Should -Not -BeLike '//*'
        }
    }

    Context 'When -WhatIf is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeRole = [PSCustomObject]@{
                Name                      = 'active-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeRole }
        }

        It 'sends no request through the transport when -WhatIf is specified' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
        }
    }

    Context 'When the API returns a general error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeRole = [PSCustomObject]@{
                Name                      = 'active-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeRole }
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
            { Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'writes the transport error as itself and returns nothing' {
            $Result = Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'UnexpectedApiError,Disable-OPIMAzureRole'
            $Errs[-1].Exception.Message | Should -BeExactly 'Unexpected API error'
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'When the transport cannot read the answer to an accepted request' {
        # A 2xx PUT whose body cannot be read is ArmTransportError although ARM accepted the request,
        # so the cmdlet writes the transport's record as itself and adds no wording of its own.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeRole = [PSCustomObject]@{
                Name                      = 'active-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeRole }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('The response of the Azure Resource Manager request could not be read.'),
                        'ArmTransportError',
                        [System.Management.Automation.ErrorCategory]::InvalidResult,
                        $null
                    )
                )
            } -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'writes ArmTransportError as itself, with the transport message unchanged' {
            $Result = Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'ArmTransportError,Disable-OPIMAzureRole' }).Count | Should -Be 1
            $Errs[-1].Exception.Message | Should -BeExactly 'The response of the Azure Resource Manager request could not be read.'
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'When the API returns an ActiveDurationTooShort error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeRole = [PSCustomObject]@{
                Name                      = 'active-001'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
            }
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { return $FakeRole }
            # The record the transport throws for ARM's 400: the ARM error code as the id.
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('The role was not active long enough to be deactivated.'),
                        'ActiveDurationTooShort',
                        [System.Management.Automation.ErrorCategory]::InvalidOperation,
                        $null
                    )
                )
            } -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'includes the 5-minute cooldown message in the error details' {
            $Errors = @()
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].Exception.Message | Should -Match '5 minutes'
            $Errors[-1].FullyQualifiedErrorId | Should -BeExactly 'ActiveDurationTooShort,Disable-OPIMAzureRole'
        }
    }

    Context 'When -Identity is specified and the role is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeActive = [PSCustomObject]@{
                Name                      = 'active-002'
                AssignmentType            = 'Activated'
                ScopeId                   = '/subscriptions/sub-002'
                ScopeDisplayName          = 'Dev Subscription'
                PrincipalId               = 'principal-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-002'
                RoleDefinitionDisplayName = 'Reader'
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return $FakeActive }
        }

        It 'looks up the role via Get-OPIMAzureRole -Activated and filters by Name' {
            Disable-OPIMAzureRole -Identity 'active-002'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter { $Activated }
        }

        It 'submits the SelfDeactivate request through the transport, at the scope of the active role' {
            Disable-OPIMAzureRole -Identity 'active-002'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'PUT' -and $Path -ceq ('/subscriptions/sub-002' + $script:RequestSuffix) -and
                $Body.properties.requestType -ceq 'SelfDeactivate' -and
                $Body.properties.roleDefinitionId -ceq '/providers/Microsoft.Authorization/roleDefinitions/role-def-002'
            }
        }
    }

    Context 'When -Identity is specified but no active role is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return $null }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMAzureRole -Identity 'nonexistent-999' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'writes IdentityNotFound to its own error stream' {
            $Out = Disable-OPIMAzureRole -Identity 'nonexistent-999' -ErrorAction Continue 2>&1
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
            }
        }

        It "writes the listing's error as itself" {
            # The command's own error stream, not -ErrorVariable: -ErrorVariable also collects the
            # record the listing raised and the command caught.
            $Out = Disable-OPIMAzureRole -Identity 'active-403' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
        }

        It 'does not write IdentityNotFound' {
            $Out = Disable-OPIMAzureRole -Identity 'active-403' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            @($Written | Where-Object { $_.FullyQualifiedErrorId -like 'IdentityNotFound*' }).Count | Should -Be 0
        }

        It 'sends no deactivation' {
            Disable-OPIMAzureRole -Identity 'active-403' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
        }
    }

    Context 'When the listing for -RoleName fails' {
        # OPIM-12: the listing that cannot be read is written as itself, never as "not found", and
        # nothing is deactivated.
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
            }
        }

        It "writes the listing's error as itself and sends no deactivation" {
            # The command's own error stream, not -ErrorVariable: -ErrorVariable also collects the
            # record the listing raised and the command caught.
            $Out = Disable-OPIMAzureRole -RoleName 'Reader -> Sub A (active-a)' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
            @($Written | Where-Object { $_.FullyQualifiedErrorId -like '*NotFound*' }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
        }
    }

    Context 'When an AzureEligibilitySchedule is piped from Get-OPIMAzureRole -All' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
        }

        It 'skips the eligible-only schedule and sends no request through the transport' {
            $EligibleOnly = [PSCustomObject]@{
                Name                      = 'elig-001'
                RoleDefinitionDisplayName = 'Contributor'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
            }
            $EligibleOnly.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
            $EligibleOnly | Disable-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
        }
    }

    Context 'When a role names no Azure scope' {
        # SECURITY 4: a deactivation is made at the active assignment's own ARM scope, so a role object
        # whose ScopeId is empty or lacks its leading slash names none, and nothing is sent for it: one
        # error with no error id (category InvalidArgument, no target object). The next object still
        # runs.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $GoodPost = New-AzurePost -Name 'active-003' -DefinitionId 'role-def-contributor' -RoleName 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001' -Active
            function New-ScopelessPost {
                param($ScopeId)
                $Post = New-AzurePost -Name 'active-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/placeholder' -ScopeName 'rg-one' -Active
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
            $Result = $Bad | Disable-OPIMAzureRole -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
            @($Errs).Count | Should -Be 1
            $Errs[0].Exception.Message | Should -BeExactly $NoScopeMessage
            $Errs[0].FullyQualifiedErrorId | Should -BeExactly 'Disable-OPIMAzureRole'
            $Errs[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidArgument)
            $Errs[0].TargetObject | Should -BeNullOrEmpty
            @($Warns).Count | Should -Be 0
            $Result | Should -BeNullOrEmpty
        }

        It 'deactivates the next piped role after one that names no scope' {
            $Result = @((New-ScopelessPost -ScopeId ''), $GoodPost) | Disable-OPIMAzureRole -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'PUT' -and $Path -ceq ('/subscriptions/sub-001' + $script:RequestSuffix) -and
                $Body.properties.roleDefinitionId -ceq 'role-def-contributor'
            }
            @($Errs | Where-Object { $_.Exception.Message -eq $NoScopeMessage }).Count | Should -Be 1
            @($Result).Count | Should -Be 1
        }
    }

    Context 'When the transport refuses the request' {
        # The transport gates every request itself (SignInRefused, TenantMismatch, AccountMismatch),
        # before anything is sent, and throws the refusal. The cmdlet's catch writes it as itself, in
        # the try that holds the request, and sends nothing more.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeRole = [PSCustomObject]@{
                Name                      = 'active-001'
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
        }

        It 'writes <Id> as itself, once, and returns nothing' -ForEach @(
            @{ Id = 'SignInRefused' }
            @{ Id = 'TenantMismatch' }
            @{ Id = 'AccountMismatch' }
        ) {
            # ConvertTo-ActiveDurationTooShortError does not claim it, so the catch writes it unchanged.
            $Refusal.Id = $Id
            $Result = Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs | Where-Object FullyQualifiedErrorId -EQ "$Id,Disable-OPIMAzureRole").Count | Should -Be 1
            @($Errs | Where-Object FullyQualifiedErrorId -Like 'ActiveDurationTooShort*').Count | Should -Be 0
            $Result | Should -BeNullOrEmpty
        }

        It 'sends nothing more than the one refused request' {
            $Refusal.Id = 'SignInRefused'
            $null = Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
        }

        It 'calls no ARM gate of its own' {
            $Refusal.Id = 'SignInRefused'
            $null = Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMArmRefusal -Times 0 -Scope It
        }
    }

    Context 'When the display name matches the active role at more than one scope' {
        # The real resolver runs; only the listing and the transport are mocked. The listing answers
        # with the active posts only when it is asked for them (-Activated), so a name that is only
        # eligible must not be found.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Eligible = @(
                New-AzurePost -Name 'azure-003' -DefinitionId 'role-def-owner' -RoleName 'Owner' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001'
            )
            $Active = @(
                New-AzurePost -Name 'active-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one' -Active
                New-AzurePost -Name 'active-002' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-two' -ScopeName 'rg-two' -Active
                New-AzurePost -Name 'active-004' -DefinitionId 'role-def-contributor' -RoleName 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001' -Active
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { $Eligible }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { $Active } -ParameterFilter { $Activated }
        }

        It 'writes AmbiguousName and sends no deactivation' {
            $Errs = @()
            Disable-OPIMAzureRole -RoleName 'Reader' -ErrorVariable Errs -ErrorAction SilentlyContinue
            # The active list was read, so the resolver and the catch that writes its record were reached.
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter { $Activated }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Disable-OPIMAzureRole'
        }

        It 'tells the user that -Scope separates the candidates' {
            $Errs = @()
            Disable-OPIMAzureRole -RoleName 'Reader' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].Exception.Message | Should -BeLike '*-Scope*'
        }

        It 'deactivates the one role that -Scope names' {
            Disable-OPIMAzureRole -RoleName 'Reader' -Scope '/subscriptions/sub-001/resourceGroups/rg-two' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Method -eq 'PUT' -and $Body.properties.requestType -ceq 'SelfDeactivate' -and
                $Path -ceq ('/subscriptions/sub-001/resourceGroups/rg-two' + $script:RequestSuffix) -and
                -not $Body.properties.Contains('linkedRoleEligibilityScheduleId') -and
                $Body.properties.roleDefinitionId -ceq 'role-def-reader'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
        }

        It 'deactivates a unique display name with its own ids' {
            Disable-OPIMAzureRole -RoleName 'contributor' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq ('/subscriptions/sub-001' + $script:RequestSuffix) -and
                -not $Body.properties.Contains('linkedRoleEligibilityScheduleId') -and
                $Body.properties.roleDefinitionId -ceq 'role-def-contributor' -and $Body.properties.principalId -ceq 'principal-001'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
        }

        It 'writes ActiveRoleNotFound for a role that is eligible but not active' {
            $Errs = @()
            Disable-OPIMAzureRole -RoleName 'Owner' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound,Disable-OPIMAzureRole'
        }

        It 'accepts the root scope / at binding and finds no role there' {
            $Errs = @()
            Disable-OPIMAzureRole -RoleName 'Reader' -Scope '/' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound,Disable-OPIMAzureRole'
        }

        It 'deactivates nothing when the old form names a role that -Scope excludes' {
            $Errs = @()
            Disable-OPIMAzureRole -RoleName 'Reader -> rg-one (active-001)' -Scope '/subscriptions/sub-001/resourceGroups/rg-two' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound,Disable-OPIMAzureRole'
        }
    }

    Context 'When -Identity matches more than one listed post' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Listing = @(
                New-AzurePost -Name 'dup-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one' -Active
                New-AzurePost -Name 'dup-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-two' -ScopeName 'rg-two' -Active
                New-AzurePost -Name 'active-004' -DefinitionId 'role-def-contributor' -RoleName 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001' -Active
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { $Listing }
        }

        It 'writes AmbiguousName, not IdentityNotFound, and sends no deactivation' {
            $Errs = @()
            Disable-OPIMAzureRole -Identity 'dup-001' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Disable-OPIMAzureRole'
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'IdentityNotFound*' }).Count | Should -Be 0
        }

        It 'deactivates the one post when the identity names only one' {
            Disable-OPIMAzureRole -Identity 'active-004' -ErrorAction SilentlyContinue
            # The instance is identified by its scope and role definition now: the linked id is gone.
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq ('/subscriptions/sub-001' + $script:RequestSuffix) -and
                $Body.properties.roleDefinitionId -ceq 'role-def-contributor' -and
                -not $Body.properties.Contains('linkedRoleEligibilityScheduleId')
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
        }
    }

    Context 'When -Scope is given where it does not belong' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { }
        }

        It 'fails to bind -Scope together with -Identity' {
            { Disable-OPIMAzureRole -Identity 'active-001' -Scope '/subscriptions/sub-001' } | Should -Throw -ErrorId 'AmbiguousParameterSet*'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }

        It 'puts -Scope in the RoleName parameter set only' {
            # A piped object binds -Role in another set, so -Scope with it selects the RoleName set, whose
            # mandatory name is then missing. Read the sets from the command metadata instead of
            # binding: an interactive host would prompt for the name.
            (Get-Command Disable-OPIMAzureRole).Parameters['Scope'].ParameterSets.Keys | Should -Be 'RoleName'
        }

        It 'refuses a -Scope that ends with a slash' {
            { Disable-OPIMAzureRole -RoleName 'Reader' -Scope '/subscriptions/sub-001/' } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }

        It 'refuses an empty -Scope' {
            { Disable-OPIMAzureRole -RoleName 'Reader' -Scope '' } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
        }
    }

    Context 'When the role is already deactivated (OPIM-40, G8)' {
        # The real resolver runs; only the listing and the transport are mocked. The first call finds
        # the role active and deactivates it, and that request ends the activation in the mock, so the
        # second call finds the role eligible and no longer active.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Held = @{ IsActive = $true }
            $ActivePost = New-AzurePost -Name 'active-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one' -Active
            $EligiblePost = New-AzurePost -Name 'azure-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one'
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { if ($Held.IsActive) { $ActivePost } } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { $EligiblePost }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                $Held.IsActive = $false
                $Where = & $script:ParseRequestPath $Path
                & $script:NewArmRequest $Where.Name $Where.Scope 'Revoked' 'SelfDeactivate'
            } -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'deactivates once and writes one non-terminating ActiveRoleNotFound that says it is already deactivated' {
            $Held.IsActive = $true
            $Out = & {
                Disable-OPIMAzureRole -RoleName 'Reader' -ErrorAction Continue
                Disable-OPIMAzureRole -RoleName 'Reader' -ErrorAction Continue
                'reached'
            } 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Results = @($Out | Where-Object { $_ -is [PSCustomObject] -and $_.PSObject.TypeNames -contains 'Omnicit.PIM.AzureAssignmentScheduleRequest' })
            # The statement after the second call ran, so the error did not end the script block.
            ($Out -contains 'reached') | Should -BeTrue
            $Results.Count | Should -Be 1
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound,Disable-OPIMAzureRole'
            $Written[0].Exception.Message | Should -BeLike '*already deactivated*'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            # Both lists were read on the second call: the active list, then the eligible one for the hint.
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 2 -Exactly -Scope It -ParameterFilter { $Activated }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter { -not $Activated }
        }

        It 'names the active form, and deactivates nothing, for the eligibility key of a role that is active' {
            # What the 0.5.1 completers offered: the role's own key. The role is active as active-001, so
            # the message must not call it deactivated, and the name is not the active assignment's.
            $Held.IsActive = $true
            $Out = & {
                Disable-OPIMAzureRole -RoleName 'Reader -> rg-one (azure-001)' -ErrorAction Continue
                'reached'
            } 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            ($Out -contains 'reached') | Should -BeTrue
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound,Disable-OPIMAzureRole'
            $Written[0].Exception.Message | Should -Not -BeLike '*already deactivated*'
            $Written[0].Exception.Message | Should -BeLike "*It is active as 'Reader -> rg-one (active-001)'*"
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
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

        It 'writes the error as its own and deactivates nothing' {
            $Out = Disable-OPIMAzureRole -RoleName 'Role A' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            @($Written | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Disable-OPIMAzureRole' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
        }
    }

    Context 'When Azure answers the deactivation with a status' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $Active = New-AzurePost -Name 'active-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one' -Active
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { $Active }
        }

        It 'returns the request and writes neither a warning nor an error for <Status>' -ForEach @(
            @{ Status = 'Revoked' }
            @{ Status = 'revoked' }
        ) {
            $Answer.Status = $Status
            $Result = Disable-OPIMAzureRole -RoleName 'Reader' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleRequest'
            $Result.Status | Should -BeExactly $Status
            @($Warns).Count | Should -Be 0
            @($Errs).Count | Should -Be 0
        }

        It 'returns the request with one warning that names <Status>' -ForEach @(
            @{ Status = 'PendingRevocation'; Message = 'Reader -> rg-one: the deactivation request is PendingRevocation and has not taken effect yet.' }
            @{ Status = 'PendingApproval'; Message = 'Reader -> rg-one: the deactivation request is PendingApproval. It waits for a decision and has not taken effect yet.' }
        ) {
            $Answer.Status = $Status
            $Result = Disable-OPIMAzureRole -RoleName 'Reader' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 1
            $Result.Status | Should -BeExactly $Status
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
            $Result = Disable-OPIMAzureRole -RoleName 'Reader' `
                -WarningVariable Warns -WarningAction SilentlyContinue -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Disable-OPIMAzureRole'
            $Errs[-1].Exception.Message | Should -BeExactly "Reader -> rg-one: the deactivation request ended with status '$Status' and did not take effect."
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'ActivationRequestFailed*' }).Count | Should -Be 1
            @($Warns).Count | Should -Be 0
        }

        It 'writes ActivationRequestFailed for an answer that carries no status' {
            $Answer.Status = $null
            $Result = Disable-OPIMAzureRole -RoleName 'Reader' -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Result).Count | Should -Be 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Disable-OPIMAzureRole'
            $Errs[-1].Exception.Message | Should -BeLike '*ended with no status*'
        }

        It 'throws the failed status once under -ErrorAction Stop and never reaches the catch around the request' {
            # The catch around the request calls ConvertTo-ActiveDurationTooShortError for every record
            # it takes. Measured on PowerShell 7.6.6: an error that $PSCmdlet.WriteError raises under the
            # Stop preference is not caught by a try in the same function, so this holds the contract
            # (one record thrown, the converter unused) and the next test holds the placement itself.
            Mock -ModuleName Omnicit.PIM ConvertTo-ActiveDurationTooShortError { $false }
            $Answer.Status = 'Failed'
            $Caught = [System.Collections.Generic.List[object]]::new()
            try {
                Disable-OPIMAzureRole -RoleName 'Reader' -ErrorAction Stop
                $Caught.Add('returned')
            } catch {
                $Caught.Add($PSItem)
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM ConvertTo-ActiveDurationTooShortError -Times 0 -Exactly -Scope It
            $Caught.Count | Should -Be 1
            $Caught[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $Caught[0].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Disable-OPIMAzureRole'
            $Caught[0].Exception.Message | Should -BeLike "*ended with status 'Failed'*"
        }

        It 'reports the status outside the catch around the request' {
            # What the report itself throws is not a failure of the request. Inside that try the catch
            # would take it, call the converter for it and write it as an error of the request.
            Mock -ModuleName Omnicit.PIM Write-OPIMRequestOutcome { throw [System.InvalidOperationException]::new('report failed') }
            Mock -ModuleName Omnicit.PIM ConvertTo-ActiveDurationTooShortError { $false }
            $Answer.Status = 'Revoked'
            $Caught = $null
            try {
                $null = Disable-OPIMAzureRole -RoleName 'Reader' -ErrorAction SilentlyContinue
            } catch {
                $Caught = $PSItem
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Write-OPIMRequestOutcome -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM ConvertTo-ActiveDurationTooShortError -Times 0 -Exactly -Scope It
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -BeExactly 'report failed'
        }

        It 'gives a request that Azure refuses to the catch around it all the same' {
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Active duration too short'),
                        'ActiveDurationTooShort',
                        [System.Management.Automation.ErrorCategory]::InvalidOperation,
                        $null
                    )
                )
            } -ParameterFilter { $Method -eq 'PUT' }
            Mock -ModuleName Omnicit.PIM ConvertTo-ActiveDurationTooShortError { $false }
            $null = Disable-OPIMAzureRole -RoleName 'Reader' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM ConvertTo-ActiveDurationTooShortError -Times 1 -Exactly -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -BeLike 'ActiveDurationTooShort*'
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'ActivationRequestFailed*' }).Count | Should -Be 0
        }

        It 'writes exactly one ActivationRequestFailed under -ErrorAction SilentlyContinue' {
            $Answer.Status = 'Failed'
            $null = Disable-OPIMAzureRole -RoleName 'Reader' -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'ActivationRequestFailed*' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
        }
    }
}
