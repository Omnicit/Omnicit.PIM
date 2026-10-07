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
                }
            }
        }

        It 'calls Resolve-OPIMSchedule for the supplied role name' {
            Disable-OPIMAzureRole -RoleName 'Contributor (active-001)'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Scope It
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
                [PSCustomObject]@{ Name = 'request-001'; Scope = '/subscriptions/sub-001'; RequestType = 'SelfDeactivate' }
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
                [PSCustomObject]@{ Name = 'request-001'; Scope = $Scope; RequestType = 'SelfDeactivate' }
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
                [PSCustomObject]@{ Name = 'request-001'; Scope = $Scope; RequestType = 'SelfDeactivate' }
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
    }
}
