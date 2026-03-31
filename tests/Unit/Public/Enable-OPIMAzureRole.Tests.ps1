Describe 'Enable-OPIMAzureRole' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When called with -RoleName (happy path)' {
        BeforeAll {
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

        It 'passes a PT1H ISO 8601 duration when -Hours defaults to 1' {
            Enable-OPIMAzureRole -RoleName 'Contributor (elig-001)'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $ExpirationDuration -eq 'PT1H'
            }
        }
    }

    Context 'When called with multiple role names' {
        BeforeAll {
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
}
