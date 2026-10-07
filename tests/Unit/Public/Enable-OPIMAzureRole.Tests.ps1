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
            $fakeResponse = [PSCustomObject]@{
                Name        = [System.Guid]::NewGuid().ToString()
                Scope       = '/subscriptions/sub-001'
                RequestType = 'SelfActivate'
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest { return $fakeResponse }
        }

        It 'calls Resolve-RoleByName for the supplied role name' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-RoleByName -Times 1 -Scope It
        }

        It 'calls New-AzRoleAssignmentScheduleRequest with SelfActivate RequestType' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $RequestType -eq 'SelfActivate'
            }
        }

        It 'calls New-AzRoleAssignmentScheduleRequest with AfterDuration expiration by default' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $ExpirationType -eq 'AfterDuration'
            }
        }

        It 'returns the response object from New-AzRoleAssignmentScheduleRequest' {
            $Result = Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            $Result | Should -Not -BeNullOrEmpty
            $Result.RequestType | Should -Be 'SelfActivate'
        }

        It 'tags the response with Omnicit.PIM.AzureAssignmentScheduleRequest type name' {
            $Result = Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleRequest'
        }

        It 'passes a PT1H ISO 8601 duration when -Hours defaults to 1' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $ExpirationDuration -eq 'PT1H'
            }
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
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName {
                if ($RoleName -like '*elig-001*') { return $fakeRoleA }
                else { return $fakeRoleB }
            }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                return [PSCustomObject]@{ Name = [System.Guid]::NewGuid().ToString(); Scope = $Scope; RequestType = 'SelfActivate' }
            }
        }

        It 'calls New-AzRoleAssignmentScheduleRequest once per role name supplied' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)', 'Owner (elig-002)'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 2 -Scope It
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
            $fakeResponse = [PSCustomObject]@{
                Name        = [System.Guid]::NewGuid().ToString()
                Scope       = '/subscriptions/sub-002'
                RequestType = 'SelfActivate'
            }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest { return $fakeResponse }
        }

        It 'calls New-AzRoleAssignmentScheduleRequest with the piped role scope and principal' {
            $fakeRole | Enable-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $Scope -eq '/subscriptions/sub-002' -and $PrincipalId -eq 'principal-002'
            }
        }

        It 'uses the piped role Name as LinkedRoleEligibilityScheduleId' {
            $fakeRole | Enable-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $LinkedRoleEligibilityScheduleId -eq 'elig-002'
            }
        }

        It 'returns the response for the piped role' {
            $Result = $fakeRole | Enable-OPIMAzureRole
            $Result | Should -Not -BeNullOrEmpty
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
            $fakeResponse = [PSCustomObject]@{
                Name        = [System.Guid]::NewGuid().ToString()
                Scope       = '/subscriptions/sub-001'
                RequestType = 'SelfActivate'
            }
            $script:UntilDateTime = [DateTime]::Now.AddHours(3)
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest { return $fakeResponse }
        }

        It 'uses AfterDateTime expiration type when -Until is provided' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Until $script:UntilDateTime
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $ExpirationType -eq 'AfterDateTime'
            }
        }

        It 'passes the -Until value as ExpirationEndDateTime' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Until $script:UntilDateTime
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $ExpirationEndDateTime -eq $script:UntilDateTime
            }
        }

        It 'does not set ExpirationDuration when -Until is specified' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Until $script:UntilDateTime
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                -not $ExpirationDuration
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
            $fakeResponse = [PSCustomObject]@{
                Name        = [System.Guid]::NewGuid().ToString()
                Scope       = '/subscriptions/sub-001'
                RequestType = 'SelfActivate'
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest { return $fakeResponse }
        }

        It 'passes PT4H ISO 8601 duration when -Hours 4 is specified' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Hours 4
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $ExpirationDuration -eq 'PT4H'
            }
        }

        It 'passes PT8H ISO 8601 duration when -Hours 8 is specified' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Hours 8
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $ExpirationDuration -eq 'PT8H'
            }
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
            $fakeResponse = [PSCustomObject]@{
                Name        = [System.Guid]::NewGuid().ToString()
                Scope       = '/subscriptions/sub-001'
                RequestType = 'SelfActivate'
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest { return $fakeResponse }
        }

        It 'passes TicketNumber and TicketSystem to the API request' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -TicketNumber 'INC-123' -TicketSystem 'ServiceNow'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $TicketNumber -eq 'INC-123' -and $TicketSystem -eq 'ServiceNow'
            }
        }

        It 'does not include TicketNumber or TicketSystem when not provided' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                -not $TicketNumber -and -not $TicketSystem
            }
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
            $fakeResponse = [PSCustomObject]@{
                Name        = [System.Guid]::NewGuid().ToString()
                Scope       = '/subscriptions/sub-001'
                RequestType = 'SelfActivate'
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest { return $fakeResponse }
        }

        It 'passes the justification text to the API request' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Justification 'Deploying hotfix'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $Justification -eq 'Deploying hotfix'
            }
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
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest { }
        }

        It 'does not call New-AzRoleAssignmentScheduleRequest when -WhatIf is specified' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
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
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Unexpected API error'),
                        'UnexpectedApiError',
                        [System.Management.Automation.ErrorCategory]::InvalidOperation,
                        $null
                    )
                )
            }
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
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                throw [System.Exception]::new('Policy validation failed: JustificationRule requires a justification.')
            }
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
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                throw [System.Exception]::new('Policy validation failed: ExpirationRule requires a shorter duration.')
            }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'sets error details with a hint to use the -NotAfter parameter' {
            $Errors = @()
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].Exception.Message | Should -BeLike '*-NotAfter*'
        }
    }

    Context 'When -Wait is specified' {
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
            $script:fakeResponseName = [System.Guid]::NewGuid().ToString()
            $fakeResponse = [PSCustomObject]@{
                Name        = $script:fakeResponseName
                Scope       = '/subscriptions/sub-001'
                RequestType = 'SelfActivate'
            }
            $fakeActivation = [PSCustomObject]@{
                Name        = $script:fakeResponseName
                Status      = 'Provisioned'
                RequestType = 'SelfActivate'
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest { return $fakeResponse }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleRequest { return $fakeActivation }
        }

        It 'calls Get-AzRoleAssignmentScheduleRequest to poll for provisioning' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Wait
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleRequest -Times 1 -Scope It
        }

        It 'does not call Get-AzRoleAssignmentScheduleRequest when -Wait is not specified' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
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
            $fakeResponse = [PSCustomObject]@{
                Name        = [System.Guid]::NewGuid().ToString()
                Scope       = '/subscriptions/sub-001'
                RequestType = 'SelfActivate'
            }
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest { return $fakeResponse }
            # The poll fails as an ARM call does: its record points at the request message, whose
            # Authorization header carries the token. The token is built at runtime and says what it is.
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleRequest {
                $PSCmdlet.ThrowTerminatingError($script:PollFixture.Record)
            }

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

        It 'scrubs the request of the failed poll and still ends the command' {
            $script:PollFixture = New-PollFixture
            $script:PollFixture.Request.Headers.Contains('Authorization') | Should -BeTrue -Because 'the request must carry the header before the call, or its absence after proves nothing'
            $Thrown = $null
            try {
                Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Wait
            } catch {
                $Thrown = $PSItem
            }
            $Thrown | Should -Not -BeNullOrEmpty -Because 'a failed poll ends the command, as it did before the scrub'
            $Thrown.FullyQualifiedErrorId | Should -BeLike 'AuthorizationFailed*'
            $script:PollFixture.Request.Headers.Contains('Authorization') | Should -BeFalse
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleRequest -Times 1 -Exactly -Scope It
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
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                $InnerEx = [System.Exception]::new('Inner network error')
                throw [System.Exception]::new('Outer API error', $InnerEx)
            }
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
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return $FakeElig }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                return [PSCustomObject]@{
                    Name        = [System.Guid]::NewGuid().ToString()
                    Scope       = '/subscriptions/sub-001'
                    RequestType = 'SelfActivate'
                }
            }
        }

        It 'looks up the role via Get-OPIMAzureRole filtered by Name' {
            Enable-OPIMAzureRole -Identity 'elig-010'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Scope It
        }

        It 'submits the SelfActivate request via New-AzRoleAssignmentScheduleRequest' {
            Enable-OPIMAzureRole -Identity 'elig-010'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It
        }
    }

    Context 'When -Identity is specified but no eligible role is found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return $null }
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
            }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {}
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
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
        }
    }

    Context 'When the listing for -RoleName fails' {
        # OPIM-12: Resolve-RoleByName throws the listing's error as itself, so the command stops at
        # the first name, as it does for a name it cannot resolve; it never goes on to the next name.
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
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {}
        }

        It "stops with the listing's error and resolves no further name" {
            { Enable-OPIMAzureRole -RoleName 'Reader -> Sub A (elig-a)', 'Reader -> Sub B (elig-b)' -ErrorAction Continue } |
                Should -Throw -ErrorId 'Forbidden*'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
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
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeElig }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                return [PSCustomObject]@{
                    Name        = [System.Guid]::NewGuid().ToString()
                    Scope       = '/subscriptions/sub-001'
                    RequestType = 'SelfActivate'
                }
            }
        }

        It 'accepts RoleName as position 0, Justification as position 1, Hours as position 2' {
            Enable-OPIMAzureRole 'Contributor (elig-pos-001)' 'Incident response' 4
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $Justification -eq 'Incident response' -and
                $ExpirationDuration -eq 'PT4H'
            }
        }
    }

    Context 'When an AzureAssignmentScheduleInstance is piped from Get-OPIMAzureRole -All' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest { }
        }

        It 'skips the already-active instance and does not call New-AzRoleAssignmentScheduleRequest' {
            $AlreadyActive = [PSCustomObject]@{
                Name                      = 'active-001'
                AssignmentType            = 'Activated'
                RoleDefinitionDisplayName = 'Contributor'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
            }
            $AlreadyActive.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
            $AlreadyActive | Enable-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
        }
    }

    Context 'When the ARM gate refuses' {
        # SEC (EntraRBAC A19): the gate stands inside the try that holds the activation request,
        # directly before it, and first in every round of the -Wait poll.
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
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                [PSCustomObject]@{ Name = 'request-001'; Scope = '/subscriptions/sub-001'; RequestType = 'SelfActivate' }
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleRequest {
                [PSCustomObject]@{ Name = 'request-001'; Status = 'Provisioned' }
            }
        }
        BeforeEach {
            # Every call refuses unless a test lets the first ones through. The mock body runs in this
            # test file's scope, so the counters live there.
            $script:ArmGateCalls = 0
            $script:ArmGatePasses = 0
            Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal {
                $script:ArmGateCalls++
                if ($script:ArmGateCalls -gt $script:ArmGatePasses) {
                    [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('refused'), 'SignInRefused', 'AuthenticationError', 'x')
                }
            }
        }

        It 'sends no ARM request' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Wait -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
        }

        It 'writes the refusal as itself' {
            # ConvertTo-PolicyValidationError does not claim it, so the catch writes it unchanged.
            $Errs = @()
            $Result = Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[0].FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
            @($Errs | Where-Object FullyQualifiedErrorId -EQ 'SignInRefused,Enable-OPIMAzureRole').Count | Should -Be 1
            @($Errs | Where-Object FullyQualifiedErrorId -Like 'RoleAssignmentRequestPolicyValidationFailed*').Count | Should -Be 0
            $Result | Should -BeNullOrEmpty
        }

        It 'stops the -Wait poll before its first request when the gate refuses there' {
            $script:ArmGatePasses = 1
            $Errs = @()
            $Result = Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -Wait -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMArmRefusal -Times 2 -Exactly -Scope It
            @($Errs | Where-Object FullyQualifiedErrorId -EQ 'SignInRefused,Enable-OPIMAzureRole').Count | Should -Be 1
            # The activation request was sent before the refusal, so its response is still returned.
            $Result.Name | Should -Be 'request-001'
        }
    }

    Context 'When Azure is signed in to another tenant than the Graph session' {
        # Acceptance (OPIM-08): the real ARM gate, an auth state a Graph sign-in for one tenant wrote,
        # and an Az context for another tenant: TenantMismatch before the activation request.
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
            Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $FakeRole }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {}
            Mock -ModuleName Omnicit.PIM Get-AzContext {
                [PSCustomObject]@{ Tenant = [PSCustomObject]@{ Id = 'bbbbbbbb-0000-0000-0000-00000000000b' } }
            }
            InModuleScope Omnicit.PIM {
                $script:_OPIMSignInLatch = $null
                $script:_OPIMAuthState = @{
                    TenantId      = 'aaaaaaaa-0000-0000-0000-00000000000a'
                    TokenTenantId = 'aaaaaaaa-0000-0000-0000-00000000000a'
                }
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'sends no activation request and writes TenantMismatch' {
            $Errs = @()
            $Result = Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
            @($Errs | Where-Object FullyQualifiedErrorId -Like 'TenantMismatch*').Count | Should -BeGreaterThan 0
            $Result | Should -BeNullOrEmpty
        }
    }
}
