BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Disable-OPIMMyRole' {
    BeforeAll {
        Mock -ModuleName Omnicit.PIM Connect-OPIM {}
        Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @() }
        Mock -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole { }
        Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @() }
        Mock -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup { }
        Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @() }
        Mock -ModuleName Omnicit.PIM Disable-OPIMAzureRole { }
    }

    Context 'When called with no target switch and no TenantAlias' {
        It 'writes a non-terminating error' {
            $Errors = @()
            Disable-OPIMMyRole -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'does not call Connect-OPIM' {
            Disable-OPIMMyRole -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 0 -Scope It
        }

        It 'does not call any Disable-OPIM* cmdlet' {
            Disable-OPIMMyRole -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 0 -Scope It
        }
    }

    Context 'When -AllActivated is specified with active roles' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeActiveDirectoryRole = [PSCustomObject]@{
                id                       = 'active-dir-001'
                roleDefinitionId         = 'role-def-001'
                directoryScopeId         = '/'
                principalId              = 'user-001'
                roleAssignmentScheduleId = 'sched-001'
                roleDefinition           = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal                = [PSCustomObject]@{ displayName = 'Jane Doe' }
            }
            $FakeActiveDirectoryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')

            $FakeActiveGroup = [PSCustomObject]@{
                id        = 'active-grp-001'
                groupId   = 'group-id-001'
                accessId  = 'member'
                group     = [PSCustomObject]@{ displayName = 'MyGroup' }
            }
            $FakeActiveGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleInstance')

            $FakeActiveAzureRole = [PSCustomObject]@{
                Name                       = 'az-active-001'
                ScopeId                    = '/subscriptions/sub-001'
                ScopeDisplayName           = 'MySubscription'
                RoleDefinitionDisplayName  = 'Contributor'
                RoleDefinitionId           = 'role-az-001'
                PrincipalId                = 'user-001'
            }
            $FakeActiveAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')

            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($FakeActiveDirectoryRole) } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @($FakeActiveGroup) } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($FakeActiveAzureRole) } -ParameterFilter { $Activated }
        }

        It 'calls Connect-OPIM with -IncludeARM when -AllActivated is specified' {
            Disable-OPIMMyRole -AllActivated -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $true
            }
        }

        It 'deactivates all three categories when -Confirm:$false is specified' {
            Disable-OPIMMyRole -AllActivated -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup -Times 1 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 1 -Scope It
        }

        It 'does not deactivate any category when -WhatIf is specified' {
            Disable-OPIMMyRole -AllActivated -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 0 -Scope It
        }

        It 'calls Get-OPIMDirectoryRole -Activated to retrieve only active directory roles' {
            Disable-OPIMMyRole -AllActivated -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 1 -Scope It -ParameterFilter {
                $Activated -eq $true
            }
        }

        It 'calls Get-OPIMEntraIDGroup -Activated to retrieve only active group assignments' {
            Disable-OPIMMyRole -AllActivated -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 1 -Scope It -ParameterFilter {
                $Activated -eq $true
            }
        }

        It 'calls Get-OPIMAzureRole -Activated to retrieve only active Azure roles' {
            Disable-OPIMMyRole -AllActivated -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Scope It -ParameterFilter {
                $Activated -eq $true
            }
        }

        It 'signs in to Microsoft Graph first, then to Azure as a second sign-in' {
            # OPIM-08: two Connect-OPIM calls for the same tenant, the Graph one without -IncludeARM.
            # The mock body runs in this test file's scope, so the record lives there.
            $script:ConnectCalls = [System.Collections.Generic.List[bool]]::new()
            Mock -ModuleName Omnicit.PIM Connect-OPIM { $script:ConnectCalls.Add([bool]$IncludeARM) }
            Disable-OPIMMyRole -AllActivated -Confirm:$false
            $script:ConnectCalls | Should -Be @($false, $true)
        }

        It 'passes -DeviceCode to both sign-ins when Azure is needed' {
            Disable-OPIMMyRole -AllActivated -DeviceCode -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 2 -Exactly -Scope It -ParameterFilter {
                $DeviceCode
            }
        }

        It 'passes -Environment to both Connect-OPIM calls' {
            # OPIM-29: Graph and then Azure sign in to the same cloud.
            Disable-OPIMMyRole -AllActivated -Environment USGov -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 2 -Exactly -Scope It -ParameterFilter {
                $Environment -eq 'USGov'
            }
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It -ParameterFilter {
                $Environment -eq 'USGov' -and $IncludeARM
            }
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It -ParameterFilter {
                $Environment -eq 'USGov' -and -not $IncludeARM
            }
        }

        It 'passes -Environment Global to both Connect-OPIM calls when it is given' {
            Disable-OPIMMyRole -AllActivated -Environment Global -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 2 -Exactly -Scope It -ParameterFilter {
                $PesterBoundParameters.ContainsKey('Environment') -and $Environment -eq 'Global'
            }
        }

        It 'passes no Environment to Connect-OPIM without -Environment' {
            # OPIM-29: without a cloud the session keeps its own for its tenant.
            Disable-OPIMMyRole -AllActivated -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 2 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 0 -Scope It -ParameterFilter {
                $PesterBoundParameters.ContainsKey('Environment')
            }
        }

        It 'keeps -Environment the last parameter, after -DeviceCode, so no position moves' {
            $Names = @((Get-Command Disable-OPIMMyRole).ScriptBlock.Ast.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $Names[-1] | Should -BeExactly 'Environment'
            $Names[-2] | Should -BeExactly 'DeviceCode'
        }

        It 'refuses an unknown -Environment at binding, before a sign-in' {
            $Caught = $null
            try { Disable-OPIMMyRole -AllActivated -Environment Germany -Confirm:$false } catch { $Caught = $PSItem }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'ParameterArgumentValidationError,Disable-OPIMMyRole'
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 0 -Scope It
        }
    }

    Context 'When the Graph sign-in fails' {
        # OPIM-08: a failed Graph sign-in stops the command. Nothing is listed or deactivated -- not
        # even in the tenant an earlier sign-in pinned -- and Azure is not signed in to. The mock
        # raises the error Connect-OPIM would carry out of Initialize-OPIMAuth; its id is set per It.
        BeforeAll {
            $FakeActiveDirectoryRole = [PSCustomObject]@{ id = 'active-gf-001'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/' }
            $FakeActiveDirectoryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')
            $FakeActiveGroup = [PSCustomObject]@{ id = 'active-grp-gf-001'; groupId = 'group-id-001'; accessId = 'member' }
            $FakeActiveGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleInstance')
            $FakeActiveAzureRole = [PSCustomObject]@{ Name = 'az-active-gf-001'; ScopeId = '/subscriptions/sub-001'; RoleDefinitionId = 'role-az-001' }
            $FakeActiveAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($FakeActiveDirectoryRole) }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @($FakeActiveGroup) }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($FakeActiveAzureRole) }
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ contoso = '00000000-0000-0000-0000-000000000001' }
            }
            Mock -ModuleName Omnicit.PIM Connect-OPIM {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('The sign-in failed.'),
                        $script:SignInErrorId,
                        [System.Management.Automation.ErrorCategory]::AuthenticationError,
                        $null
                    )
                )
            } -ParameterFilter { -not $IncludeARM }
        }

        It 'writes the sign-in error to its own error stream (<ErrorId>)' -ForEach @(
            @{ ErrorId = 'TenantMismatch' }
            @{ ErrorId = 'InteractiveAuthFailed' }
            @{ ErrorId = 'DeviceCodeAuthFailed' }
        ) {
            # Read the command's own error stream, not -ErrorVariable: -ErrorVariable also collects the
            # record the Connect-OPIM mock threw and the command caught, so it holds one even when the
            # command writes nothing. The caught record never reaches the stream (one record, not two).
            $script:SignInErrorId = $ErrorId
            $Out = Disable-OPIMMyRole -AllActivated -Confirm:$false -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike "$ErrorId*"
        }

        It 'lists and deactivates nothing (<ErrorId>)' -ForEach @(
            @{ ErrorId = 'TenantMismatch' }
            @{ ErrorId = 'InteractiveAuthFailed' }
            @{ ErrorId = 'DeviceCodeAuthFailed' }
        ) {
            $script:SignInErrorId = $ErrorId
            Disable-OPIMMyRole -AllActivated -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 0 -Scope It
            # The Azure sign-in is never attempted.
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It
        }

        It 'lists and deactivates nothing for a tenant alias' {
            $script:SignInErrorId = 'TenantMismatch'
            Disable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It
        }
    }

    Context 'When only the Azure sign-in fails' {
        # A failed Azure sign-in skips the Azure pillar only; Graph is signed in.
        BeforeAll {
            $FakeActiveDirectoryRole = [PSCustomObject]@{ id = 'active-af-001'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/' }
            $FakeActiveDirectoryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')
            $FakeActiveGroup = [PSCustomObject]@{ id = 'active-grp-af-001'; groupId = 'group-id-001'; accessId = 'member' }
            $FakeActiveGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleInstance')
            $FakeActiveAzureRole = [PSCustomObject]@{ Name = 'az-active-af-001'; ScopeId = '/subscriptions/sub-001'; RoleDefinitionId = 'role-az-001' }
            $FakeActiveAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($FakeActiveDirectoryRole) }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @($FakeActiveGroup) }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($FakeActiveAzureRole) }
            Mock -ModuleName Omnicit.PIM Connect-OPIM {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Azure connection failed: no account.'),
                        'AzureConnectFailed',
                        [System.Management.Automation.ErrorCategory]::AuthenticationError,
                        $null
                    )
                )
            } -ParameterFilter { $IncludeARM }
        }

        It 'writes the Azure sign-in error to its own error stream' {
            # The command's own error stream, as for the Graph sign-in: the caught record is not in it.
            $Out = Disable-OPIMMyRole -AllActivated -Confirm:$false -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'AzureConnectFailed*'
        }

        It 'goes on to deactivate directory roles and groups' {
            Disable-OPIMMyRole -AllActivated -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup -Times 1 -Exactly -Scope It
        }

        It 'skips the Azure pillar' {
            Disable-OPIMMyRole -AllActivated -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 0 -Scope It
        }
    }

    Context "When a pillar's listing fails (<Failing>, <Mode>)" -ForEach @(
        @{ Mode = 'AllActivated'; Failing = 'Directory'; Deactivator = 'Disable-OPIMDirectoryRole'; Others = @('Disable-OPIMEntraIDGroup', 'Disable-OPIMAzureRole') }
        @{ Mode = 'AllActivated'; Failing = 'Group'; Deactivator = 'Disable-OPIMEntraIDGroup'; Others = @('Disable-OPIMDirectoryRole', 'Disable-OPIMAzureRole') }
        @{ Mode = 'AllActivated'; Failing = 'AzureActive'; Deactivator = 'Disable-OPIMAzureRole'; Others = @('Disable-OPIMDirectoryRole', 'Disable-OPIMEntraIDGroup') }
        @{ Mode = 'StringAlias'; Failing = 'Directory'; Deactivator = 'Disable-OPIMDirectoryRole'; Others = @('Disable-OPIMEntraIDGroup', 'Disable-OPIMAzureRole') }
        @{ Mode = 'StringAlias'; Failing = 'Group'; Deactivator = 'Disable-OPIMEntraIDGroup'; Others = @('Disable-OPIMDirectoryRole', 'Disable-OPIMAzureRole') }
        @{ Mode = 'StringAlias'; Failing = 'AzureActive'; Deactivator = 'Disable-OPIMAzureRole'; Others = @('Disable-OPIMDirectoryRole', 'Disable-OPIMEntraIDGroup') }
        @{ Mode = 'ConfiguredAlias'; Failing = 'Directory'; Deactivator = 'Disable-OPIMDirectoryRole'; Others = @('Disable-OPIMEntraIDGroup', 'Disable-OPIMAzureRole') }
        @{ Mode = 'ConfiguredAlias'; Failing = 'Group'; Deactivator = 'Disable-OPIMEntraIDGroup'; Others = @('Disable-OPIMDirectoryRole', 'Disable-OPIMAzureRole') }
        @{ Mode = 'ConfiguredAlias'; Failing = 'AzureActive'; Deactivator = 'Disable-OPIMAzureRole'; Others = @('Disable-OPIMDirectoryRole', 'Disable-OPIMEntraIDGroup') }
        @{ Mode = 'ConfiguredAlias'; Failing = 'AzureEligible'; Deactivator = 'Disable-OPIMAzureRole'; Others = @('Disable-OPIMDirectoryRole', 'Disable-OPIMEntraIDGroup') }
    ) {
        # OPIM-12: a pillar whose listing cannot be read is reported as that error and ends there:
        # nothing it read is deactivated, and it is never reported as "no active ..." or "not
        # currently activated". The other pillars still run. Every listing returns one item; the
        # failing one writes the record a listing writes for a failed read -- after its item when
        # $script:PartialRead is set, as a read that fails after its first item does. The string form
        # and a configured alias (with the configured-eligible Azure lookup) reach all seven listings.
        # The mock takes its preference from an explicit -ErrorAction and is Continue otherwise, as a
        # listing is under the default preference: a module-scoped mock body reads the test scope's
        # preference (Stop under the build), never the caller's.
        BeforeAll {
            $script:FailingListing = $Failing
            $script:PartialRead = $false
            $MyRoleParams = switch ($Mode) {
                'StringAlias' { @{ TenantAlias = 'contoso'; TenantMapPath = 'TestDrive:\TenantMap.psd1' } }
                'ConfiguredAlias' { @{ TenantAlias = 'fabrikam'; TenantMapPath = 'TestDrive:\TenantMap.psd1' } }
                default { @{ AllActivated = $true; Confirm = $false } }
            }
            # memberType, endDateTime and assignmentType are set as Graph sets them: the types'
            # ScriptProperties of those names read $this.<name>, which resolves to itself on an
            # object without the property.
            $FakeActiveDirectoryRole = [PSCustomObject]@{
                id = 'active-lf-001'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/'
                memberType = 'Direct'; endDateTime = '2026-10-07T18:00:00Z'
            }
            $FakeActiveDirectoryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')
            $FakeActiveGroup = [PSCustomObject]@{
                id = 'active-grp-lf-001'; groupId = 'group-id-001'; accessId = 'member'
                memberType = 'Direct'; assignmentType = 'Activated'; endDateTime = '2026-10-07T18:00:00Z'
            }
            $FakeActiveGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleInstance')
            $FakeActiveAzureRole = [PSCustomObject]@{ Name = 'az-active-lf-001'; ScopeId = '/subscriptions/sub-001'; RoleDefinitionId = 'role-az-001' }
            $FakeActiveAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
            $FakeEligibleAzureRole = [PSCustomObject]@{ Name = 'elig-az-lf-001'; ScopeId = '/subscriptions/sub-001'; RoleDefinitionId = 'role-az-001' }
            $FakeEligibleAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso  = '00000000-0000-0000-0000-000000000001'
                    fabrikam = @{
                        TenantId       = '00000000-0000-0000-0000-000000000002'
                        DirectoryRoles = @('role-def-001')
                        EntraIDGroups  = @('group-id-001_member')
                        AzureRoles     = @('elig-az-lf-001')
                    }
                }
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole {
                if ($script:FailingListing -ne 'Directory') { return $FakeActiveDirectoryRole }
                if ($script:PartialRead) { $FakeActiveDirectoryRole }
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup {
                if ($script:FailingListing -ne 'Group') { return $FakeActiveGroup }
                if ($script:PartialRead) { $FakeActiveGroup }
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole {
                $Listing = if ($Activated) { 'AzureActive' } else { 'AzureEligible' }
                $Item = if ($Activated) { $FakeActiveAzureRole } else { $FakeEligibleAzureRole }
                if ($script:FailingListing -ne $Listing) { return $Item }
                if ($script:PartialRead) { $Item }
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
        }

        It "writes the listing's error" {
            # The command's own error stream, not -ErrorVariable: -ErrorVariable also collects the
            # record the listing raised and the command caught.
            $script:PartialRead = $false
            $Out = Disable-OPIMMyRole @MyRoleParams -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
        }

        It 'deactivates nothing the failed listing read' {
            $script:PartialRead = $true
            Disable-OPIMMyRole @MyRoleParams -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM $Deactivator -Times 0 -Scope It
        }

        It 'does not report the failed listing as no active roles' {
            $script:PartialRead = $false
            $Out = Disable-OPIMMyRole @MyRoleParams -ErrorAction SilentlyContinue -Verbose 4>&1
            $Said = @($Out | Where-Object {
                    $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match 'No active|not currently activated'
                })
            $Said.Count | Should -Be 0
        }

        It 'goes on to list and deactivate the other pillars' {
            $script:PartialRead = $true
            Disable-OPIMMyRole @MyRoleParams -ErrorAction SilentlyContinue
            foreach ($Other in $Others) {
                Should -Invoke -ModuleName Omnicit.PIM $Other -Times 1 -Exactly -Scope It
            }
        }
    }

    Context 'When -AllActivated is specified but no roles are active' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @() } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @() } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @() } -ParameterFilter { $Activated }
        }

        It 'does not call Disable-OPIMDirectoryRole when no directory roles are active' {
            Disable-OPIMMyRole -AllActivated -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 0 -Scope It
        }

        It 'does not call Disable-OPIMEntraIDGroup when no groups are active' {
            Disable-OPIMMyRole -AllActivated -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup -Times 0 -Scope It
        }

        It 'does not call Disable-OPIMAzureRole when no Azure roles are active' {
            Disable-OPIMMyRole -AllActivated -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 0 -Scope It
        }
    }

    Context 'When -AllActivatedDirectoryRoles is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeActiveDirectoryRole = [PSCustomObject]@{
                id                       = 'active-dr-002'
                roleDefinitionId         = 'role-def-002'
                directoryScopeId         = '/'
                principalId              = 'user-001'
                roleAssignmentScheduleId = 'sched-002'
                roleDefinition           = [PSCustomObject]@{ displayName = 'Security Reader' }
                principal                = [PSCustomObject]@{ displayName = 'Jane Doe' }
            }
            $FakeActiveDirectoryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($FakeActiveDirectoryRole) } -ParameterFilter { $Activated }
        }

        It 'deactivates only directory roles' {
            Disable-OPIMMyRole -AllActivatedDirectoryRoles -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 0 -Scope It
        }

        It 'calls Connect-OPIM without -IncludeARM' {
            # Graph only: one sign-in, and none with -IncludeARM.
            Disable-OPIMMyRole -AllActivatedDirectoryRoles -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It -ParameterFilter {
                -not $IncludeARM
            }
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 0 -Scope It -ParameterFilter { $IncludeARM }
        }

        It 'passes -DeviceCode to Connect-OPIM when specified' {
            Disable-OPIMMyRole -AllActivatedDirectoryRoles -DeviceCode -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It -ParameterFilter {
                $DeviceCode -eq $true
            }
        }

        It 'does not ask for device code mode without -DeviceCode' {
            Disable-OPIMMyRole -AllActivatedDirectoryRoles -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It -ParameterFilter {
                -not $DeviceCode
            }
        }
    }

    Context 'When -AllActivatedEntraIDGroups is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeActiveGroup = [PSCustomObject]@{
                id       = 'active-grp-002'
                groupId  = 'group-id-002'
                accessId = 'owner'
                group    = [PSCustomObject]@{ displayName = 'OwnedGroup' }
            }
            $FakeActiveGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleInstance')
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @($FakeActiveGroup) } -ParameterFilter { $Activated }
        }

        It 'deactivates only Entra ID group assignments' {
            Disable-OPIMMyRole -AllActivatedEntraIDGroups -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup -Times 1 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 0 -Scope It
        }
    }

    Context 'When -AllActivatedAzureRoles is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeActiveAzureRole = [PSCustomObject]@{
                Name                      = 'az-active-002'
                ScopeId                   = '/subscriptions/sub-002'
                ScopeDisplayName          = 'ProdSub'
                RoleDefinitionDisplayName = 'Owner'
                RoleDefinitionId          = 'role-az-002'
                PrincipalId               = 'user-001'
            }
            $FakeActiveAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($FakeActiveAzureRole) } -ParameterFilter { $Activated }
        }

        It 'deactivates only Azure RBAC roles' {
            Disable-OPIMMyRole -AllActivatedAzureRoles -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 1 -Scope It
        }

        It 'calls Connect-OPIM with -IncludeARM when -AllActivatedAzureRoles is used' {
            Disable-OPIMMyRole -AllActivatedAzureRoles -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $true
            }
        }
    }

    Context 'When called with -TenantAlias (simple string TenantId in TenantMap)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeTenantId = '00000000-0000-0000-0000-000000000001'
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ contoso = $FakeTenantId }
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @() } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @() } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @() } -ParameterFilter { $Activated }
        }

        It 'calls Connect-OPIM with the resolved TenantId' {
            Disable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $TenantId -eq $FakeTenantId
            }
        }

        It 'calls Connect-OPIM with -IncludeARM for the string form, whose Azure pillar deactivates every active Azure role' {
            Disable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It -ParameterFilter {
                $IncludeARM
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter {
                $Activated
            }
        }
    }

    Context 'When called with -TenantAlias pointing to a hashtable config with DirectoryRoles' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeTenantId = '00000000-0000-0000-0000-000000000002'
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    fabrikam = @{
                        TenantId     = $FakeTenantId
                        DirectoryRoles = @('role-def-001', 'role-def-002')
                    }
                }
            }

            $FakeActiveRole001 = [PSCustomObject]@{
                id                       = 'active-dir-fab-001'
                roleDefinitionId         = 'role-def-001'
                directoryScopeId         = '/'
                principalId              = 'user-fab'
                roleAssignmentScheduleId = 'sched-fab-001'
                roleDefinition           = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal                = [PSCustomObject]@{ displayName = 'Fabrikam User' }
            }
            $FakeActiveRole001.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')

            # role-def-002 is NOT active -- should trigger a verbose message, not an error
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($FakeActiveRole001) } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @() } -ParameterFilter { $Activated }
        }

        It 'deactivates only the configured role that is currently active' {
            Disable-OPIMMyRole -TenantAlias 'fabrikam' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Scope It
        }

        It 'does not write an error when a configured role is not currently active' {
            $Errors = @()
            Disable-OPIMMyRole -TenantAlias 'fabrikam' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -Be 0
        }
    }

    Context 'When called with -TenantAlias pointing to a hashtable config with AzureRoles' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeTenantId = '00000000-0000-0000-0000-000000000003'
            # The config stores eligible schedule .Name values (GUIDs), not display names
            $FakeEligibleScheduleName = 'elig-az-sched-001'
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    azure = @{
                        TenantId   = $FakeTenantId
                        AzureRoles = @($FakeEligibleScheduleName)
                    }
                }
            }

            # Eligible schedule -- returned by Get-OPIMAzureRole without -Activated
            $FakeEligibleAzureRole = [PSCustomObject]@{
                Name                      = $FakeEligibleScheduleName
                ScopeId                   = '/subscriptions/sub-003'
                ScopeDisplayName          = 'ProdSub'
                RoleDefinitionId          = 'role-az-contrib-001'
                RoleDefinitionDisplayName = 'Contributor'
                PrincipalId               = 'user-003'
            }
            $FakeEligibleAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')

            # Active instance -- returned by Get-OPIMAzureRole -Activated; correlated via RoleDefinitionId + ScopeId
            $FakeActiveAzureRole = [PSCustomObject]@{
                Name                      = 'az-active-inst-003'
                ScopeId                   = '/subscriptions/sub-003'
                ScopeDisplayName          = 'ProdSub'
                RoleDefinitionId          = 'role-az-contrib-001'
                RoleDefinitionDisplayName = 'Contributor'
                PrincipalId               = 'user-003'
            }
            $FakeActiveAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')

            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($FakeEligibleAzureRole) } -ParameterFilter { -not $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($FakeActiveAzureRole) } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @() } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @() } -ParameterFilter { $Activated }
        }

        It 'calls Connect-OPIM with -IncludeARM when AzureRoles are configured' {
            Disable-OPIMMyRole -TenantAlias 'azure' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $true
            }
        }

        It 'deactivates the configured Azure role when it is currently active' {
            Disable-OPIMMyRole -TenantAlias 'azure' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 1 -Scope It
        }

        It 'calls Get-OPIMAzureRole without -Activated to retrieve eligible schedules for config matching' {
            Disable-OPIMMyRole -TenantAlias 'azure' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Scope It -ParameterFilter {
                -not $Activated
            }
        }

        It 'calls Get-OPIMAzureRole -Activated to retrieve currently active Azure roles' {
            Disable-OPIMMyRole -TenantAlias 'azure' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Scope It -ParameterFilter {
                $Activated -eq $true
            }
        }
    }

    Context 'When called with -TenantAlias and configured Azure role is not currently active' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeTenantId = '00000000-0000-0000-0000-000000000005'
            $FakeEligibleScheduleName = 'elig-az-sched-inactive-001'
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    azureinactive = @{
                        TenantId   = $FakeTenantId
                        AzureRoles = @($FakeEligibleScheduleName)
                    }
                }
            }

            $FakeEligibleAzureRole = [PSCustomObject]@{
                Name                      = $FakeEligibleScheduleName
                ScopeId                   = '/subscriptions/sub-005'
                ScopeDisplayName          = 'DevSub'
                RoleDefinitionId          = 'role-az-reader-001'
                RoleDefinitionDisplayName = 'Reader'
                PrincipalId               = 'user-005'
            }
            $FakeEligibleAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')

            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($FakeEligibleAzureRole) } -ParameterFilter { -not $Activated }
            # No matching active instance -- different RoleDefinitionId
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @() } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @() } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @() } -ParameterFilter { $Activated }
        }

        It 'does not call Disable-OPIMAzureRole when the configured role is not active' {
            Disable-OPIMMyRole -TenantAlias 'azureinactive' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 0 -Scope It
        }

        It 'does not write an error when the configured Azure role is not active' {
            $Errors = @()
            Disable-OPIMMyRole -TenantAlias 'azureinactive' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -Be 0
        }
    }

    Context 'When a configured entry matches several active posts (OPIM-17)' {
        # Every configured entry is matched against every active post -- no first match. An entry that
        # matches more than one names none of them: it is written as AmbiguousName and deactivates
        # nothing, and the next entry still runs. The listings return what -Activated returns: only
        # activations.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    dirambig = @{ TenantId = '00000000-0000-0000-0000-000000000006'; DirectoryRoles = @('role-def-001|/', 'role-def-002') }
                    dirone   = @{ TenantId = '00000000-0000-0000-0000-000000000006'; DirectoryRoles = @('role-def-002') }
                    grpambig = @{ TenantId = '00000000-0000-0000-0000-000000000006'; EntraIDGroups = @('group-001_member', 'group-002_member') }
                    grpone   = @{ TenantId = '00000000-0000-0000-0000-000000000006'; EntraIDGroups = @('group-002_member') }
                    azambig  = @{ TenantId = '00000000-0000-0000-0000-000000000006'; AzureRoles = @('elig-az-001', 'elig-az-002') }
                    azone    = @{ TenantId = '00000000-0000-0000-0000-000000000006'; AzureRoles = @('elig-az-002') }
                }
            }

            # memberType, assignmentType and endDateTime are set as Graph sets them: the types'
            # ScriptProperties of those names read $this.<name>.
            # Two overlapping activations of role-def-001 at '/': the entry 'role-def-001|/' names the
            # role at that scope, and both posts carry its key (OPIM-10, A13).
            $DirectoryRoot = [PSCustomObject]@{
                id = 'active-dir-a1'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/'
                memberType = 'Direct'; assignmentType = 'Activated'; endDateTime = '2026-10-08T12:00:00Z'
                roleDefinition = [PSCustomObject]@{ displayName = 'Global Administrator' }
            }
            $DirectoryRootSecond = [PSCustomObject]@{
                id = 'active-dir-a2'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/'
                memberType = 'Direct'; assignmentType = 'Activated'; endDateTime = '2026-10-08T14:00:00Z'
                roleDefinition = [PSCustomObject]@{ displayName = 'Global Administrator' }
            }
            $DirectoryOther = [PSCustomObject]@{
                id = 'active-dir-c'; roleDefinitionId = 'role-def-002'; directoryScopeId = '/'
                memberType = 'Direct'; assignmentType = 'Activated'; endDateTime = '2026-10-08T12:00:00Z'
                roleDefinition = [PSCustomObject]@{ displayName = 'User Administrator' }
            }
            foreach ($Post in @($DirectoryRoot, $DirectoryRootSecond, $DirectoryOther)) {
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')
            }
            $GroupFirst = [PSCustomObject]@{
                id = 'active-grp-a1'; groupId = 'group-001'; accessId = 'member'
                memberType = 'Direct'; assignmentType = 'Activated'; endDateTime = '2026-10-08T12:00:00Z'
                group = [PSCustomObject]@{ displayName = 'PIM Admins' }
            }
            $GroupSecond = [PSCustomObject]@{
                id = 'active-grp-a2'; groupId = 'group-001'; accessId = 'member'
                memberType = 'Direct'; assignmentType = 'Activated'; endDateTime = '2026-10-08T14:00:00Z'
                group = [PSCustomObject]@{ displayName = 'PIM Admins' }
            }
            $GroupOther = [PSCustomObject]@{
                id = 'active-grp-c'; groupId = 'group-002'; accessId = 'member'
                memberType = 'Direct'; assignmentType = 'Activated'; endDateTime = '2026-10-08T12:00:00Z'
                group = [PSCustomObject]@{ displayName = 'Ops Group' }
            }
            foreach ($Post in @($GroupFirst, $GroupSecond, $GroupOther)) {
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleInstance')
            }
            $EligibleOne = [PSCustomObject]@{
                Name = 'elig-az-001'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'ProdSub'
                RoleDefinitionId = 'role-az-001'; RoleDefinitionDisplayName = 'Contributor'
            }
            $EligibleTwo = [PSCustomObject]@{
                Name = 'elig-az-002'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'ProdSub'
                RoleDefinitionId = 'role-az-002'; RoleDefinitionDisplayName = 'Reader'
            }
            $AzureFirst = [PSCustomObject]@{
                Name = 'az-active-a1'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'ProdSub'
                RoleDefinitionId = 'role-az-001'; RoleDefinitionDisplayName = 'Contributor'
            }
            $AzureSecond = [PSCustomObject]@{
                Name = 'az-active-a2'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'ProdSub'
                RoleDefinitionId = 'role-az-001'; RoleDefinitionDisplayName = 'Contributor'
            }
            $AzureOther = [PSCustomObject]@{
                Name = 'az-active-c'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'ProdSub'
                RoleDefinitionId = 'role-az-002'; RoleDefinitionDisplayName = 'Reader'
            }
            foreach ($Post in @($EligibleOne, $EligibleTwo)) { $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule') }
            foreach ($Post in @($AzureFirst, $AzureSecond, $AzureOther)) { $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance') }

            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($DirectoryRoot, $DirectoryRootSecond, $DirectoryOther) } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @($GroupFirst, $GroupSecond, $GroupOther) } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($EligibleOne, $EligibleTwo) } -ParameterFilter { -not $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($AzureFirst, $AzureSecond, $AzureOther) } -ParameterFilter { $Activated }
        }

        Context 'a directory role entry' {
            It 'deactivates none of the posts that the entry matches' {
                Disable-OPIMMyRole -TenantAlias 'dirambig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
                Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 0 -Exactly -Scope It -ParameterFilter {
                    $Role.roleDefinitionId -eq 'role-def-001'
                }
            }

            It 'writes one AmbiguousName that names both posts and says configured entry' {
                $Out = Disable-OPIMMyRole -TenantAlias 'dirambig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction Continue 2>&1
                $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written.Count | Should -Be 1
                $Written[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
                $Written[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidArgument)
                $Written[0].Exception.Message | Should -BeExactly (
                    "The configured entry 'role-def-001|/' matches 2 active directory roles, so it names none of them: " +
                    "'Global Administrator (active-dir-a1)' at scope '/'; " +
                    "'Global Administrator (active-dir-a2)' at scope '/'. " +
                    'Deactivate the one you mean with Disable-OPIMDirectoryRole and its tab-completed form, as listed.')
            }

            It 'goes on with the next entry, which matches one post, and deactivates that post' {
                Disable-OPIMMyRole -TenantAlias 'dirambig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
                Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Role.id -eq 'active-dir-c'
                }
            }

            It 'deactivates the one post that an entry matches, and writes no error' {
                $Out = Disable-OPIMMyRole -TenantAlias 'dirone' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction Continue 2>&1
                @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
                Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Role.id -eq 'active-dir-c'
                }
            }
        }

        Context 'a group entry' {
            It 'deactivates none of the posts that the entry matches' {
                Disable-OPIMMyRole -TenantAlias 'grpambig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
                Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup -Times 0 -Exactly -Scope It -ParameterFilter {
                    $Group.groupId -eq 'group-001'
                }
            }

            It 'writes one AmbiguousName that names both posts and says configured entry' {
                $Out = Disable-OPIMMyRole -TenantAlias 'grpambig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction Continue 2>&1
                $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written.Count | Should -Be 1
                $Written[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
                $Written[0].Exception.Message | Should -BeExactly (
                    "The configured entry 'group-001_member' matches 2 active group assignments, so it names none of them: " +
                    "'PIM Admins - member (active-grp-a1)'; 'PIM Admins - member (active-grp-a2)'. " +
                    'Deactivate the one you mean with Disable-OPIMEntraIDGroup and its tab-completed form, as listed.')
            }

            It 'goes on with the next entry, which matches one post, and deactivates that post' {
                Disable-OPIMMyRole -TenantAlias 'grpambig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
                Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Group.id -eq 'active-grp-c'
                }
            }

            It 'deactivates the one post that an entry matches, and writes no error' {
                $Out = Disable-OPIMMyRole -TenantAlias 'grpone' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction Continue 2>&1
                @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
                Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Group.id -eq 'active-grp-c'
                }
            }
        }

        Context 'an Azure role entry' {
            It 'deactivates none of the posts that the entry matches' {
                Disable-OPIMMyRole -TenantAlias 'azambig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
                Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 0 -Exactly -Scope It -ParameterFilter {
                    $Role.RoleDefinitionId -eq 'role-az-001'
                }
            }

            It 'writes one AmbiguousName that names the eligible role and both posts and says configured entry' {
                $Out = Disable-OPIMMyRole -TenantAlias 'azambig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction Continue 2>&1
                $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written.Count | Should -Be 1
                $Written[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
                $Written[0].Exception.Message | Should -BeExactly (
                    "The configured entry 'elig-az-001' matches 2 active Azure roles, so it names none of them: " +
                    "'Contributor -> ProdSub (az-active-a1)' at scope '/subscriptions/sub-001'; " +
                    "'Contributor -> ProdSub (az-active-a2)' at scope '/subscriptions/sub-001'. " +
                    'Deactivate the one you mean with Disable-OPIMAzureRole and its tab-completed form, as listed.')
            }

            It 'goes on with the next entry, which matches one post, and deactivates that post' {
                Disable-OPIMMyRole -TenantAlias 'azambig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
                Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 1 -Exactly -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Role.Name -eq 'az-active-c'
                }
            }

            It 'deactivates the one post that an entry matches, and writes no error' {
                $Out = Disable-OPIMMyRole -TenantAlias 'azone' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction Continue 2>&1
                @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
                Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Role.Name -eq 'az-active-c'
                }
            }
        }

        It 'writes the ambiguity as an error and ends the command under -ErrorAction Stop, before anything is deactivated' {
            { Disable-OPIMMyRole -TenantAlias 'dirambig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage "The configured entry 'role-def-001|/' matches 2*"
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 0 -Exactly -Scope It
        }
    }

    Context 'When a tenant alias lists directory roles (OPIM-10, A13)' {
        # A directory role is deactivated only at the scope its entry names. An entry written before
        # 0.6.0 holds the roleDefinitionId alone and means the role at '/' only.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    oldkey    = @{ TenantId = '00000000-0000-0000-0000-000000000003'; DirectoryRoles = @('role-def-001') }
                    aukey     = @{ TenantId = '00000000-0000-0000-0000-000000000003'; DirectoryRoles = @('role-def-001|/administrativeUnits/au-001') }
                    mixed     = @{ TenantId = '00000000-0000-0000-0000-000000000003'; DirectoryRoles = @('role-def-001', 'role-def-001|/') }
                    upper     = @{ TenantId = '00000000-0000-0000-0000-000000000003'; DirectoryRoles = @('ROLE-DEF-001|/ADMINISTRATIVEUNITS/AU-001') }
                    notactive = @{ TenantId = '00000000-0000-0000-0000-000000000003'; DirectoryRoles = @('role-def-002|/') }
                    twocase   = @{ TenantId = '00000000-0000-0000-0000-000000000003'; DirectoryRoles = @('role-def-001|/administrativeUnits/au-001', 'ROLE-DEF-001|/ADMINISTRATIVEUNITS/AU-001') }
                }
            }

            # memberType and endDateTime are set as Graph sets them: the type's ScriptProperties of
            # those names read $this.<name>.
            $ActiveRoot = [PSCustomObject]@{
                id = 'active-a13-001'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/'
                memberType = 'Direct'; assignmentType = 'Activated'; endDateTime = '2026-10-08T12:00:00Z'
                roleDefinition = [PSCustomObject]@{ displayName = 'Global Administrator' }
            }
            $ActiveAu = [PSCustomObject]@{
                id = 'active-a13-002'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/administrativeUnits/au-001'
                directoryScope = [PSCustomObject]@{ displayName = 'Sales AU' }
                memberType = 'Direct'; assignmentType = 'Activated'; endDateTime = '2026-10-08T12:00:00Z'
                roleDefinition = [PSCustomObject]@{ displayName = 'Global Administrator' }
            }
            foreach ($Post in @($ActiveRoot, $ActiveAu)) {
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($ActiveRoot, $ActiveAu) } -ParameterFilter { $Activated }
        }

        It 'deactivates only the activation at the root for an entry without a scope' {
            Disable-OPIMMyRole -TenantAlias 'oldkey' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Exactly -Scope It -ParameterFilter {
                $Role.id -eq 'active-a13-001'
            }
            $Errs.Count | Should -Be 0
        }

        It 'deactivates exactly the configured scope for a new entry' {
            Disable-OPIMMyRole -TenantAlias 'aukey' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Exactly -Scope It -ParameterFilter {
                $Role.id -eq 'active-a13-002'
            }
            $Errs.Count | Should -Be 0
        }

        It 'deactivates the root activation once for an old and a new entry of the same role' {
            Disable-OPIMMyRole -TenantAlias 'mixed' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Exactly -Scope It -ParameterFilter {
                $Role.id -eq 'active-a13-001'
            }
            $Errs.Count | Should -Be 0
        }

        It 'compares the key without regard to letter case' {
            Disable-OPIMMyRole -TenantAlias 'upper' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Exactly -Scope It -ParameterFilter {
                $Role.id -eq 'active-a13-002'
            }
            $Errs.Count | Should -Be 0
        }

        It 'deactivates the activation once for two entries that differ only in letter case' {
            Disable-OPIMMyRole -TenantAlias 'twocase' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Exactly -Scope It -ParameterFilter {
                $Role.id -eq 'active-a13-002'
            }
            $Errs.Count | Should -Be 0
        }

        It 'writes the entry in the verbose message when the configured scope is not active' {
            $Out = Disable-OPIMMyRole -TenantAlias 'notactive' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue -Verbose 4>&1
            $Verbose = @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } |
                    Where-Object { $_.Message -like "*'role-def-002|/'*" })
            $Verbose.Count | Should -Be 1
            $Verbose[0].Message | Should -BeLike '*not currently activated*'
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 0 -Scope It
            $Errs.Count | Should -Be 0
        }
    }

    Context 'When a tenant alias holds a blank entry or an entry in other letter case' {
        # Every configured entry is read through the tenant map's key helper: a blank entry matches
        # nothing, and an entry is compared without regard to letter case.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    blankdir = @{ TenantId = '00000000-0000-0000-0000-000000000003'; DirectoryRoles = @('', 'role-def-001|/') }
                    blankgrp = @{ TenantId = '00000000-0000-0000-0000-000000000003'; EntraIDGroups = @('', 'group-001_member') }
                    blankaz  = @{ TenantId = '00000000-0000-0000-0000-000000000003'; AzureRoles = @('', 'elig-az-001') }
                    grpcase  = @{ TenantId = '00000000-0000-0000-0000-000000000003'; EntraIDGroups = @('GROUP-001_MEMBER') }
                    azcase   = @{ TenantId = '00000000-0000-0000-0000-000000000003'; AzureRoles = @('ELIG-AZ-001') }
                }
            }

            # memberType, assignmentType and endDateTime are set as Graph sets them: the types'
            # ScriptProperties of those names read $this.<name>.
            $ActiveDir = [PSCustomObject]@{
                id = 'active-blank-dir-001'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/'
                memberType = 'Direct'; assignmentType = 'Activated'; endDateTime = '2026-10-08T12:00:00Z'
                roleDefinition = [PSCustomObject]@{ displayName = 'Global Administrator' }
            }
            $ActiveDir.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')
            $ActiveGroup = [PSCustomObject]@{
                id = 'active-blank-grp-001'; groupId = 'group-001'; accessId = 'member'
                memberType = 'Direct'; assignmentType = 'Activated'; endDateTime = '2026-10-08T12:00:00Z'
                group = [PSCustomObject]@{ displayName = 'PIM Admins' }
            }
            $ActiveGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleInstance')
            $EligibleAzure = [PSCustomObject]@{
                Name = 'elig-az-001'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'ProdSub'
                RoleDefinitionId = 'role-az-001'; RoleDefinitionDisplayName = 'Contributor'
            }
            $EligibleAzure.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
            $ActiveAzure = [PSCustomObject]@{
                Name = 'az-active-blank-001'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'ProdSub'
                RoleDefinitionId = 'role-az-001'; RoleDefinitionDisplayName = 'Contributor'
                LinkedRoleEligibilityScheduleId = '/subscriptions/sub-001/providers/Microsoft.Authorization/roleEligibilitySchedules/elig-az-001'
            }
            $ActiveAzure.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
            # An eligibility whose key is empty, and its activation: a blank entry matches it no more
            # than any other post.
            $EligibleNoName = [PSCustomObject]@{
                Name = ''; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'ProdSub'
                RoleDefinitionId = 'role-az-009'; RoleDefinitionDisplayName = 'Reader'
            }
            $EligibleNoName.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
            $ActiveNoName = [PSCustomObject]@{
                Name = 'az-active-blank-009'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'ProdSub'
                RoleDefinitionId = 'role-az-009'; RoleDefinitionDisplayName = 'Reader'
            }
            $ActiveNoName.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')

            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($ActiveDir) } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @($ActiveGroup) } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($EligibleAzure, $EligibleNoName) } -ParameterFilter { -not $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($ActiveAzure, $ActiveNoName) } -ParameterFilter { $Activated }
        }

        It 'reads a blank directory entry as matching nothing, writes no error and deactivates only the real entry' {
            $Out = Disable-OPIMMyRole -TenantAlias 'blankdir' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue -Verbose 4>&1
            $Errs.Count | Should -Be 0
            @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -like "*''*" }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole -Times 1 -Exactly -Scope It -ParameterFilter {
                $Role.id -eq 'active-blank-dir-001'
            }
        }

        It 'reads a blank group entry as matching nothing, writes no error and deactivates only the real entry' {
            $Out = Disable-OPIMMyRole -TenantAlias 'blankgrp' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue -Verbose 4>&1
            $Errs.Count | Should -Be 0
            @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -like "*''*" }).Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup -Times 1 -Exactly -Scope It -ParameterFilter {
                $Group.id -eq 'active-blank-grp-001'
            }
        }

        It 'reads a blank Azure entry as matching nothing, writes no error and deactivates only the real entry' {
            Disable-OPIMMyRole -TenantAlias 'blankaz' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter {
                $Role.Name -eq 'az-active-blank-001'
            }
        }

        It 'compares a group entry without regard to letter case' {
            Disable-OPIMMyRole -TenantAlias 'grpcase' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup -Times 1 -Exactly -Scope It -ParameterFilter {
                $Group.id -eq 'active-blank-grp-001'
            }
        }

        It 'compares an Azure entry without regard to letter case' {
            Disable-OPIMMyRole -TenantAlias 'azcase' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter {
                $Role.Name -eq 'az-active-blank-001'
            }
        }
    }

    Context 'When a tenant alias lists an Azure role stored from an active role (OPIM-22)' {
        # An active Azure role is stored as '<eligibility Name>|<its own ScopeId>', which selects the
        # eligibility only at that scope; its activation there is then deactivated. An entry from an
        # activation at a narrower scope than its eligibility selects nothing, so nothing is deactivated.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    scoped   = @{ TenantId = '00000000-0000-0000-0000-000000000003'; AzureRoles = @('elig-az-101|/subscriptions/sub-001') }
                    narrowed = @{ TenantId = '00000000-0000-0000-0000-000000000003'; AzureRoles = @('elig-az-101|/subscriptions/sub-001/resourceGroups/rg-001') }
                    upper    = @{ TenantId = '00000000-0000-0000-0000-000000000003'; AzureRoles = @('ELIG-AZ-101|/SUBSCRIPTIONS/SUB-001') }
                    bare     = @{ TenantId = '00000000-0000-0000-0000-000000000003'; AzureRoles = @('elig-az-101') }
                }
            }

            $EligibleSub = [PSCustomObject]@{
                Name = 'elig-az-101'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'ProdSub'
                RoleDefinitionId = 'role-az-101'; RoleDefinitionDisplayName = 'Contributor'
            }
            $EligibleSub.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
            # The eligibility activated at its own scope, and again at one of its resource groups.
            $ActiveSub = [PSCustomObject]@{
                Name = 'az-active-101'; ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'ProdSub'
                RoleDefinitionId = 'role-az-101'; RoleDefinitionDisplayName = 'Contributor'
                LinkedRoleEligibilityScheduleId = 'elig-az-101'
            }
            $ActiveRg = [PSCustomObject]@{
                Name = 'az-active-102'; ScopeId = '/subscriptions/sub-001/resourceGroups/rg-001'; ScopeDisplayName = 'rg-001'
                RoleDefinitionId = 'role-az-101'; RoleDefinitionDisplayName = 'Contributor'
                LinkedRoleEligibilityScheduleId = 'elig-az-101'
            }
            foreach ($Post in @($ActiveSub, $ActiveRg)) {
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @() } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @() } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($EligibleSub) } -ParameterFilter { -not $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($ActiveSub, $ActiveRg) } -ParameterFilter { $Activated }
        }

        It 'deactivates exactly the activation of the eligibility at the scope the entry names' {
            Disable-OPIMMyRole -TenantAlias 'scoped' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter {
                $Role.Name -eq 'az-active-101'
            }
        }

        It 'deactivates nothing for an entry whose scope is not the scope of its eligibility' {
            Disable-OPIMMyRole -TenantAlias 'narrowed' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 0 -Scope It
            # Both listings were read: the entry was compared with the eligible posts.
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter { -not $Activated }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter { $Activated }
        }

        It 'compares a scoped entry without regard to letter case' {
            Disable-OPIMMyRole -TenantAlias 'upper' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter {
                $Role.Name -eq 'az-active-101'
            }
        }

        It 'deactivates the activation for an entry stored from an eligible role, as before' {
            Disable-OPIMMyRole -TenantAlias 'bare' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Disable-OPIMAzureRole -Times 1 -Exactly -Scope It -ParameterFilter {
                $Role.Name -eq 'az-active-101'
            }
        }
    }

    Context 'When called with -TenantAlias pointing to a hashtable config with no category lists' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeTenantId = '00000000-0000-0000-0000-000000000004'
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ noconfig = @{ TenantId = $FakeTenantId } }
            }
        }

        It 'does not call Get-OPIMDirectoryRole when no DirectoryRoles are configured' {
            Disable-OPIMMyRole -TenantAlias 'noconfig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 0 -Scope It
        }

        It 'does not call Get-OPIMEntraIDGroup when no EntraIDGroups are configured' {
            Disable-OPIMMyRole -TenantAlias 'noconfig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 0 -Scope It
        }

        It 'does not call Get-OPIMAzureRole when no AzureRoles are configured' {
            Disable-OPIMMyRole -TenantAlias 'noconfig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 0 -Scope It
        }

        It 'signs in to Graph only when the config lists no AzureRoles' {
            Disable-OPIMMyRole -TenantAlias 'noconfig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 0 -Scope It -ParameterFilter { $IncludeARM }
        }
    }

    Context 'When -TenantMapPath does not exist' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
        }

        It 'writes a non-terminating error when the TenantMap file is missing' {
            $Errors = @()
            Disable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\missing.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'does not call Connect-OPIM when the TenantMap file is missing' {
            Disable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\missing.psd1' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 0 -Scope It
        }
    }

    Context 'When -TenantAlias is not found in TenantMap' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ contoso = '00000000-0000-0000-0000-000000000001' }
            }
        }

        It 'writes a non-terminating error when the alias is absent from the TenantMap' {
            $Errors = @()
            Disable-OPIMMyRole -TenantAlias 'unknown' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Write-Progress -Completed is called when deactivation finishes' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @() } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @() } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @() } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Write-Progress {}
        }

        It 'calls Write-Progress -Completed after all pillars run' {
            Disable-OPIMMyRole -AllActivated -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Write-Progress -Scope It -ParameterFilter { $Completed }
        }
    }

    Context 'Write-Progress PercentComplete stays within bounds for single-pillar modes' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @() } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @() } -ParameterFilter { $Activated }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @() } -ParameterFilter { $Activated }
        }

        It 'does not exceed PercentComplete 100 when only the Directory Roles pillar is active' {
            { Disable-OPIMMyRole -AllActivatedDirectoryRoles -Confirm:$false } | Should -Not -Throw
        }

        It 'does not exceed PercentComplete 100 when only the Entra ID Groups pillar is active' {
            { Disable-OPIMMyRole -AllActivatedEntraIDGroups -Confirm:$false } | Should -Not -Throw
        }

        It 'does not exceed PercentComplete 100 when only the Azure RBAC Roles pillar is active' {
            { Disable-OPIMMyRole -AllActivatedAzureRoles -Confirm:$false } | Should -Not -Throw
        }
    }

    Context 'The default -TenantMapPath (OPIM-21)' {
        BeforeAll {
            $Param = (Get-Command Disable-OPIMMyRole).ScriptBlock.Ast.Body.ParamBlock.Parameters |
                Where-Object { $_.Name.VariablePath.UserPath -eq 'TenantMapPath' }
            $DefaultText = $Param.DefaultValue.Extent.Text
            $ExpectedPath = if ($IsWindows) {
                "$env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1"
            } else {
                "$HOME/.config/Omnicit.PIM/TenantMap.psd1"
            }
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { $script:SeenPaths.Add($Path); $false }
        }
        BeforeEach {
            $script:SeenPaths = [System.Collections.Generic.List[string]]::new()
        }

        It 'builds the default from $HOME' {
            $Param | Should -Not -BeNullOrEmpty
            $DefaultText | Should -BeExactly "(Join-Path `$HOME '.config/Omnicit.PIM/TenantMap.psd1')"
        }

        It 'gives the same path as before on Windows and a path under $HOME elsewhere' {
            $Actual = & ([scriptblock]::Create($DefaultText))
            $Actual | Should -BeExactly $ExpectedPath
        }

        It 'reads that path when -TenantMapPath is not given' {
            Disable-OPIMMyRole -TenantAlias 'contoso' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $script:SeenPaths | Should -Contain $ExpectedPath
            $Errs[-1].FullyQualifiedErrorId | Should -BeLike 'TenantMapNotFound*'
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 0 -Scope It
        }
    }
}
