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
    BeforeAll {
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
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                return [PSCustomObject]@{
                    Name        = [System.Guid]::NewGuid().ToString()
                    Scope       = '/subscriptions/sub-001'
                    RequestType = 'SelfDeactivate'
                    Status      = 'Revoked'
                }
            }
        }

        It 'calls Resolve-OPIMSchedule for the supplied role name' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It
        }

        It 'calls New-AzRoleAssignmentScheduleRequest with SelfDeactivate RequestType' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $RequestType -eq 'SelfDeactivate'
            }
        }

        It 'calls New-AzRoleAssignmentScheduleRequest with the role scope' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $Scope -eq '/subscriptions/sub-001'
            }
        }

        It 'uses the active assignment Name as LinkedRoleEligibilityScheduleId' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $LinkedRoleEligibilityScheduleId -eq 'active-001'
            }
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
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                return [PSCustomObject]@{
                    Name        = [System.Guid]::NewGuid().ToString()
                    Scope       = '/subscriptions/sub-002'
                    RequestType = 'SelfDeactivate'
                    Status      = 'Revoked'
                }
            }
        }

        It 'calls New-AzRoleAssignmentScheduleRequest with the piped role scope and principal' {
            $FakeRole | Disable-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $Scope -eq '/subscriptions/sub-002' -and $PrincipalId -eq 'principal-002'
            }
        }

        It 'uses the piped role Name as LinkedRoleEligibilityScheduleId' {
            $FakeRole | Disable-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It -ParameterFilter {
                $LinkedRoleEligibilityScheduleId -eq 'active-002'
            }
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
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest { }
        }

        It 'does not call New-AzRoleAssignmentScheduleRequest when -WhatIf is specified' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
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
            { Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
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
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                throw [System.Exception]::new('ActiveDurationTooShort: Role was not activated long enough.')
            }
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
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                return [PSCustomObject]@{
                    Name        = [System.Guid]::NewGuid().ToString()
                    Scope       = '/subscriptions/sub-002'
                    RequestType = 'SelfDeactivate'
                    Status      = 'Revoked'
                }
            }
        }

        It 'looks up the role via Get-OPIMAzureRole -Activated and filters by Name' {
            Disable-OPIMAzureRole -Identity 'active-002'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Scope It
        }

        It 'submits the SelfDeactivate request via New-AzRoleAssignmentScheduleRequest' {
            Disable-OPIMAzureRole -Identity 'active-002'
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Scope It
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
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {}
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
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
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
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {}
        }

        It "writes the listing's error as itself and sends no deactivation" {
            # The command's own error stream, not -ErrorVariable: -ErrorVariable also collects the
            # record the listing raised and the command caught.
            $Out = Disable-OPIMAzureRole -RoleName 'Reader -> Sub A (active-a)' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
            @($Written | Where-Object { $_.FullyQualifiedErrorId -like '*NotFound*' }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
        }
    }

    Context 'When an AzureEligibilitySchedule is piped from Get-OPIMAzureRole -All' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest { }
        }

        It 'skips the eligible-only schedule and does not call New-AzRoleAssignmentScheduleRequest' {
            $EligibleOnly = [PSCustomObject]@{
                Name                      = 'elig-001'
                RoleDefinitionDisplayName = 'Contributor'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
            }
            $EligibleOnly.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
            $EligibleOnly | Disable-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
        }
    }

    Context 'When the ARM gate refuses' {
        # SEC (EntraRBAC A19): the gate stands inside the try that holds the deactivation request,
        # directly before it, so the cmdlet's own catch reports the refusal as itself.
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
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                [PSCustomObject]@{ Name = 'request-001'; Scope = '/subscriptions/sub-001'; RequestType = 'SelfDeactivate'; Status = 'Revoked' }
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal {
                [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('refused'), 'SignInRefused', 'AuthenticationError', 'x')
            }
        }

        It 'sends no ARM request' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
        }

        It 'writes the refusal as itself' {
            # ConvertTo-ActiveDurationTooShortError does not claim it, so the catch writes it unchanged.
            $Errs = @()
            $Result = Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[0].FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
            @($Errs | Where-Object FullyQualifiedErrorId -EQ 'SignInRefused,Disable-OPIMAzureRole').Count | Should -Be 1
            @($Errs | Where-Object FullyQualifiedErrorId -Like 'ActiveDurationTooShort*').Count | Should -Be 0
            $Result | Should -BeNullOrEmpty
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMArmRefusal -Times 1 -Exactly -Scope It
        }
    }

    Context 'When Azure is signed in to another tenant than the Graph session' {
        # Acceptance (OPIM-08): the real ARM gate, an auth state a Graph sign-in for one tenant wrote,
        # and an Az context for another tenant: TenantMismatch before the deactivation request.
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

        It 'sends no deactivation request and writes TenantMismatch' {
            $Errs = @()
            $Result = Disable-OPIMAzureRole -RoleName 'Contributor (active-001)' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
            @($Errs | Where-Object FullyQualifiedErrorId -Like 'TenantMismatch*').Count | Should -BeGreaterThan 0
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'When the display name matches the active role at more than one scope' {
        # The real resolver runs; only the listing, the ARM gate and the ARM call are mocked. The
        # listing answers with the active posts only when it is asked for them (-Activated), so a name
        # that is only eligible must not be found.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal { $null }
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
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                [PSCustomObject]@{ Name = 'request-001'; Scope = $Scope; RequestType = 'SelfDeactivate'; Status = 'Revoked' }
            }
        }

        It 'writes AmbiguousName and sends no deactivation' {
            $Errs = @()
            Disable-OPIMAzureRole -RoleName 'Reader' -ErrorVariable Errs -ErrorAction SilentlyContinue
            # The active list was read, so the resolver and the catch that writes its record were reached.
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter { $Activated }
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Disable-OPIMAzureRole'
        }

        It 'tells the user that -Scope separates the candidates' {
            $Errs = @()
            Disable-OPIMAzureRole -RoleName 'Reader' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].Exception.Message | Should -BeLike '*-Scope*'
        }

        It 'deactivates the one role that -Scope names' {
            Disable-OPIMAzureRole -RoleName 'Reader' -Scope '/subscriptions/sub-001/resourceGroups/rg-two' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $RequestType -eq 'SelfDeactivate' -and $Scope -eq '/subscriptions/sub-001/resourceGroups/rg-two' -and
                $LinkedRoleEligibilityScheduleId -eq 'active-002' -and $RoleDefinitionId -eq 'role-def-reader'
            }
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Exactly -Scope It
        }

        It 'deactivates a unique display name with its own ids' {
            Disable-OPIMAzureRole -RoleName 'contributor' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Scope -eq '/subscriptions/sub-001' -and $LinkedRoleEligibilityScheduleId -eq 'active-004' -and
                $RoleDefinitionId -eq 'role-def-contributor' -and $PrincipalId -eq 'principal-001'
            }
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Exactly -Scope It
        }

        It 'writes ActiveRoleNotFound for a role that is eligible but not active' {
            $Errs = @()
            Disable-OPIMAzureRole -RoleName 'Owner' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound,Disable-OPIMAzureRole'
        }

        It 'accepts the root scope / at binding and finds no role there' {
            $Errs = @()
            Disable-OPIMAzureRole -RoleName 'Reader' -Scope '/' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound,Disable-OPIMAzureRole'
        }

        It 'deactivates nothing when the old form names a role that -Scope excludes' {
            $Errs = @()
            Disable-OPIMAzureRole -RoleName 'Reader -> rg-one (active-001)' -Scope '/subscriptions/sub-001/resourceGroups/rg-two' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound,Disable-OPIMAzureRole'
        }
    }

    Context 'When -Identity matches more than one listed post' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal { $null }
            $Listing = @(
                New-AzurePost -Name 'dup-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one' -Active
                New-AzurePost -Name 'dup-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-two' -ScopeName 'rg-two' -Active
                New-AzurePost -Name 'active-004' -DefinitionId 'role-def-contributor' -RoleName 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001' -Active
            )
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { $Listing }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                [PSCustomObject]@{ Name = 'request-001'; Scope = $Scope; RequestType = 'SelfDeactivate'; Status = 'Revoked' }
            }
        }

        It 'writes AmbiguousName, not IdentityNotFound, and sends no deactivation' {
            $Errs = @()
            Disable-OPIMAzureRole -Identity 'dup-001' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
            $Errs[-1].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Disable-OPIMAzureRole'
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'IdentityNotFound*' }).Count | Should -Be 0
        }

        It 'deactivates the one post when the identity names only one' {
            Disable-OPIMAzureRole -Identity 'active-004' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $LinkedRoleEligibilityScheduleId -eq 'active-004'
            }
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Exactly -Scope It
        }
    }

    Context 'When -Scope is given where it does not belong' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal { $null }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest { }
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
        # The real resolver runs; only the listing, the ARM gate and the ARM call are mocked. The
        # first call finds the role active and deactivates it, and that request ends the activation
        # in the mock, so the second call finds the role eligible and no longer active.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal { $null }
            $Held = @{ IsActive = $true }
            $ActivePost = New-AzurePost -Name 'active-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one' -Active
            $EligiblePost = New-AzurePost -Name 'azure-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one'
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { if ($Held.IsActive) { $ActivePost } } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { $EligiblePost }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                $Held.IsActive = $false
                [PSCustomObject]@{ Name = 'request-001'; Scope = $Scope; RequestType = 'SelfDeactivate'; Status = 'Revoked' }
            }
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
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Exactly -Scope It
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
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
        }
    }

    Context 'When the resolver writes an error instead of throwing it' {
        # The cmdlet calls the resolver with -ErrorAction Stop, so an error the resolver only writes
        # ends that name inside the cmdlet's own try and is written as the cmdlet's own error. The
        # mock takes its preference from an explicit -ErrorAction and is Continue otherwise, as the
        # resolver is under the default preference.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal { $null }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {}
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
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 0 -Scope It
        }
    }

    Context 'When Azure answers the deactivation with a status' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal { $null }
            $Active = New-AzurePost -Name 'active-001' -DefinitionId 'role-def-reader' -RoleName 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one' -Active
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule { $Active }
            # The answer is read when the request is made, so each test sets the status it wants.
            $Answer = @{ Status = 'Revoked' }
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                $Response = [PSCustomObject]@{ Name = 'request-001'; Scope = $Scope; RequestType = 'SelfDeactivate' }
                if ($null -ne $Answer.Status) { $Response | Add-Member -NotePropertyName Status -NotePropertyValue $Answer.Status }
                $Response
            }
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
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Exactly -Scope It
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
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Write-OPIMRequestOutcome -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM ConvertTo-ActiveDurationTooShortError -Times 0 -Exactly -Scope It
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -BeExactly 'report failed'
        }

        It 'still gives a request that Azure refuses to the catch around it' {
            Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Active duration too short'),
                        'ActiveDurationTooShort',
                        [System.Management.Automation.ErrorCategory]::InvalidOperation,
                        $null
                    )
                )
            }
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
            Should -Invoke -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest -Times 1 -Exactly -Scope It
        }
    }
}
