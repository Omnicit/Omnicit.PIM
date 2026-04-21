Describe 'Disable-OPIMMyRole' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
        Mock -ModuleName Omnicit.PIM Connect-OPIM {}
        Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @() }
        Mock -ModuleName Omnicit.PIM Disable-OPIMDirectoryRole { }
        Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @() }
        Mock -ModuleName Omnicit.PIM Disable-OPIMEntraIDGroup { }
        Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @() }
        Mock -ModuleName Omnicit.PIM Disable-OPIMAzureRole { }
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
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
            Disable-OPIMMyRole -AllActivatedDirectoryRoles -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $false
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

        It 'calls Connect-OPIM without -IncludeARM when config has no AzureRoles' {
            Disable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $false
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

            # role-def-002 is NOT active — should trigger a verbose message, not an error
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

            # Eligible schedule — returned by Get-OPIMAzureRole without -Activated
            $FakeEligibleAzureRole = [PSCustomObject]@{
                Name                      = $FakeEligibleScheduleName
                ScopeId                   = '/subscriptions/sub-003'
                ScopeDisplayName          = 'ProdSub'
                RoleDefinitionId          = 'role-az-contrib-001'
                RoleDefinitionDisplayName = 'Contributor'
                PrincipalId               = 'user-003'
            }
            $FakeEligibleAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')

            # Active instance — returned by Get-OPIMAzureRole -Activated; correlated via RoleDefinitionId + ScopeId
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
            # No matching active instance — different RoleDefinitionId
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
}
