BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Set-OPIMConfiguration' {
    BeforeAll {
        Mock -ModuleName Omnicit.PIM Set-Content { }
        Mock -ModuleName Omnicit.PIM Get-OPIMCurrentTenantInfo {
            return [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000001'; DisplayName = 'Mock Tenant' }
        }
        $PSDefaultParameterValues['Set-OPIMConfiguration:Confirm'] = $false

        # The "What if:" text of ShouldProcess goes to the host, not to a stream, so it is read back from
        # a transcript of the call.
        function Get-WhatIfText {
            param([scriptblock]$Command)
            $Path = Join-Path $TestDrive 'whatif-transcript.txt'
            $null = Start-Transcript -LiteralPath $Path -Force
            try { $null = & $Command } finally { $null = Stop-Transcript }
            [System.IO.File]::ReadAllText($Path)
        }
    }
    AfterAll {
        $null = $PSDefaultParameterValues.Remove('Set-OPIMConfiguration:Confirm')
    }

    Context 'When the TenantMap file does not exist' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $false }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'does not call Set-Content' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }

    Context 'When the alias does not exist in the file' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    fabrikam = @{ TenantId = '00000000-0000-0000-0000-000000000002' }
                }
            }
        }

        It 'writes a non-terminating error mentioning the alias' {
            $Errors = @()
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
            $Errors[0].Exception.Message | Should -Match 'contoso'
        }

        It 'does not call Set-Content' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }

    Context 'When updating the TenantId for an existing alias' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{ TenantId = '00000000-0000-0000-0000-000000000001' }
                }
            }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'calls Set-Content once' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It
        }

        It 'writes the new TenantId into the PSD1 content' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match '00000000-0000-0000-0000-000000000099'
        }
    }

    Context 'When a directory role object is piped' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{
                        TenantId       = '00000000-0000-0000-0000-000000000001'
                        DirectoryRoles = @('old-role-def-001')
                    }
                }
            }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }

            $script:dirRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'new-role-def-001'
                directoryScopeId = '/'
            }
            $script:dirRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'writes roleDefinitionId|directoryScopeId into the DirectoryRoles list' {
            $script:dirRole | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match ([regex]::Escape("'new-role-def-001|/'"))
        }

        It 'removes the old roleDefinitionId from the content' {
            $script:dirRole | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Not -Match 'old-role-def-001'
        }

        It 'writes the administrative unit of a post at an administrative unit' {
            $AuRole = [PSCustomObject]@{ id = 'elig-002'; roleDefinitionId = 'new-role-def-001'; directoryScopeId = '/administrativeUnits/au-001' }
            $AuRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            $AuRole | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match ([regex]::Escape("'new-role-def-001|/administrativeUnits/au-001'"))
            $script:writtenContent | Should -Not -Match ([regex]::Escape("'new-role-def-001|/'"))
        }

        It 'stores a key once when the same post is piped twice' {
            # Get-OPIMDirectoryRole -All returns the eligible and the active post of one role at one scope.
            $ActiveRole = [PSCustomObject]@{ id = 'active-001'; roleDefinitionId = 'new-role-def-001'; directoryScopeId = '/' }
            $ActiveRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')
            $script:dirRole, $ActiveRole | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Not -BeNullOrEmpty
            [regex]::Matches($script:writtenContent, [regex]::Escape("'new-role-def-001|/'")).Count | Should -Be 1
        }

        It 'stores a key once when two posts differ only in letter case, and keeps the first' {
            $Lower = [PSCustomObject]@{ id = 'elig-003'; roleDefinitionId = 'new-role-def-001'; directoryScopeId = '/administrativeUnits/au-001' }
            $Upper = [PSCustomObject]@{ id = 'elig-004'; roleDefinitionId = 'NEW-ROLE-DEF-001'; directoryScopeId = '/administrativeUnits/AU-001' }
            $Other = [PSCustomObject]@{ id = 'elig-005'; roleDefinitionId = 'new-role-def-002'; directoryScopeId = '/' }
            foreach ($Post in @($Lower, $Upper, $Other)) { $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule') }
            $Lower, $Upper, $Other | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match ([regex]::Escape("DirectoryRoles = @('new-role-def-001|/administrativeUnits/au-001', 'new-role-def-002|/')"))
        }
    }

    Context 'When a group object is piped' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{
                        TenantId      = '00000000-0000-0000-0000-000000000001'
                        EntraIDGroups = @('old-group-001_member')
                    }
                }
            }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }

            $script:groupObj = [PSCustomObject]@{
                id       = 'assign-001'
                groupId  = 'new-group-001'
                accessId = 'member'
            }
            $script:groupObj.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'replaces the EntraIDGroups list with the piped groupId_accessId' {
            $script:groupObj | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match 'new-group-001_member'
        }
    }

    Context 'When an Azure role object is piped' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{
                        TenantId   = '00000000-0000-0000-0000-000000000001'
                        AzureRoles = @('old-azure-elig-001')
                    }
                }
            }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }

            $script:azRole = [PSCustomObject]@{
                Name             = 'new-azure-elig-001'
                RoleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/abc'
                ScopeId          = '/subscriptions/sub-001'
            }
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'replaces the AzureRoles list with the piped schedule Name' {
            $script:azRole | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match 'new-azure-elig-001'
        }
    }

    Context 'When an active Azure role is piped (OPIM-22)' {
        # An active instance from Get-OPIMAzureRole -Activated (or an active row of -All) is stored by
        # the eligibility schedule it was activated from and its own scope, '<Name>|<ScopeId>', which pim
        # matches only with that eligibility at that scope -- or refused when its link names no
        # eligibility, or names one at another scope.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{
                        TenantId      = '00000000-0000-0000-0000-000000000001'
                        EntraIDGroups = @('old-group-001_member')
                        AzureRoles    = @('old-azure-elig-001')
                    }
                }
            }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }

            $script:azEligible = [PSCustomObject]@{
                Name             = 'elig-az-001'
                RoleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/role-def-az-001'
                ScopeId          = '/subscriptions/sub-001'
            }
            $script:azEligible.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
            $script:azActive = [PSCustomObject]@{
                Name                            = 'az-active-001'
                LinkedRoleEligibilityScheduleId = '/subscriptions/sub-001/providers/Microsoft.Authorization/roleEligibilitySchedules/elig-az-001'
                RoleDefinitionId                = '/providers/Microsoft.Authorization/roleDefinitions/role-def-az-001'
                RoleDefinitionDisplayName       = 'Contributor'
                ScopeId                         = '/subscriptions/sub-001'
                ScopeDisplayName                = 'ProdSub'
            }
            $script:azActive.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
            $script:azUnlinked = [PSCustomObject]@{
                Name                            = 'az-active-002'
                LinkedRoleEligibilityScheduleId = $null
                RoleDefinitionId                = '/providers/Microsoft.Authorization/roleDefinitions/role-def-az-002'
                RoleDefinitionDisplayName       = 'Reader'
                ScopeId                         = '/subscriptions/sub-001'
                ScopeDisplayName                = 'ProdSub'
            }
            $script:azUnlinked.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
            $script:azOther = [PSCustomObject]@{
                Name             = 'elig-az-003'
                RoleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/role-def-az-003'
                ScopeId          = '/subscriptions/sub-001'
            }
            $script:azOther.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
            $script:grpForAz = [PSCustomObject]@{ id = 'elig-grp-az-001'; groupId = 'group-001'; accessId = 'member' }
            $script:grpForAz.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
            # Activated at one resource group from a subscription eligibility (the portal's Scope tab).
            $script:azNarrow = [PSCustomObject]@{
                Name                            = 'az-active-004'
                LinkedRoleEligibilityScheduleId = '/subscriptions/sub-001/providers/Microsoft.Authorization/roleEligibilitySchedules/elig-az-004'
                RoleDefinitionId                = '/providers/Microsoft.Authorization/roleDefinitions/role-def-az-004'
                RoleDefinitionDisplayName       = 'Contributor'
                ScopeId                         = '/subscriptions/sub-001/resourceGroups/rg-001'
                ScopeDisplayName                = 'rg-001'
            }
            $script:azNarrow.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
            # The link as ARM returns it and as Enable-OPIMAzureRole sends it: the bare Name.
            $script:azBare = [PSCustomObject]@{
                Name                            = 'az-active-005'
                LinkedRoleEligibilityScheduleId = 'elig-az-005'
                RoleDefinitionId                = '/providers/Microsoft.Authorization/roleDefinitions/role-def-az-005'
                ScopeId                         = '/subscriptions/sub-001'
            }
            $script:azBare.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
            $script:azProviderOnly = [PSCustomObject]@{
                Name                            = 'az-active-006'
                LinkedRoleEligibilityScheduleId = '/providers/Microsoft.Authorization/roleEligibilitySchedules/elig-az-006'
                RoleDefinitionId                = '/providers/Microsoft.Authorization/roleDefinitions/role-def-az-006'
                ScopeId                         = '/subscriptions/sub-002'
            }
            $script:azProviderOnly.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleInstance')
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'stores the eligibility the active role was activated from with its own scope, not the instance Name' {
            $script:azActive | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $script:writtenContent | Should -Match ("AzureRoles\s+=\s+@\(" + [regex]::Escape("'elig-az-001|/subscriptions/sub-001'") + "\)")
            $script:writtenContent | Should -Not -Match 'az-active-001'
        }

        It 'stores an active role whose link is <Label> as its eligibility and its own scope' -ForEach @(
            @{ Label = 'a bare name'; Fixture = 'azBare'; Expected = 'elig-az-005|/subscriptions/sub-001' }
            @{ Label = 'the provider-only form'; Fixture = 'azProviderOnly'; Expected = 'elig-az-006|/subscriptions/sub-002' }
        ) {
            $Fixtures = @{ azBare = $script:azBare; azProviderOnly = $script:azProviderOnly }
            $Fixtures[$Fixture] | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $script:writtenContent | Should -Match ("AzureRoles\s+=\s+@\(" + [regex]::Escape("'$Expected'") + "\)")
        }

        It 'stores the key once when the eligible role and its active instance are piped' {
            $script:azEligible, $script:azActive | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $script:writtenContent | Should -Match "AzureRoles\s+=\s+@\('elig-az-001'\)"
            $script:writtenContent | Should -Not -Match 'az-active-001'
        }

        It 'stores the key once, in the form first piped, when the active instance comes before its eligible role' {
            $script:azActive, $script:azEligible | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $script:writtenContent | Should -Match ("AzureRoles\s+=\s+@\(" + [regex]::Escape("'elig-az-001|/subscriptions/sub-001'") + "\)")
        }

        It 'writes LinkedEligibilityNotFound for an active role that names no eligibility, and stores the other piped objects' {
            $script:azUnlinked, $script:azOther, $script:grpForAz | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'LinkedEligibilityNotFound*' }).Count | Should -BeGreaterThan 0
            $Errs[-1].FullyQualifiedErrorId | Should -BeLike 'LinkedEligibilityNotFound*'
            $Errs[-1].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
            $Errs[-1].Exception.Message | Should -BeLike "The active Azure role 'Reader' at scope 'ProdSub' names no eligibility*"
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It
            $script:writtenContent | Should -Match "AzureRoles\s+=\s+@\('elig-az-003'\)"
            $script:writtenContent | Should -Match "EntraIDGroups\s+=\s+@\('group-001_member'\)"
            $script:writtenContent | Should -Not -Match 'az-active-002'
        }

        It 'writes the refusal once to the error stream' {
            $Out = $script:azOther, $script:azUnlinked | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'LinkedEligibilityNotFound*'
            $script:writtenContent | Should -Match "AzureRoles\s+=\s+@\('elig-az-003'\)"
        }

        It 'writes LinkedEligibilityNotFound for an active role at a narrower scope than its eligibility, and stores neither' {
            $script:azNarrow, $script:azOther | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].FullyQualifiedErrorId | Should -BeLike 'LinkedEligibilityNotFound*'
            $Errs[-1].Exception.Message | Should -BeLike "The active Azure role 'Contributor' at scope 'rg-001' cannot be shown to be active at the scope of the eligibility*"
            $script:writtenContent | Should -Match "AzureRoles\s+=\s+@\('elig-az-003'\)"
            $script:writtenContent | Should -Not -Match 'elig-az-004'
            $script:writtenContent | Should -Not -Match 'az-active-004'
        }

        It 'keeps the stored AzureRoles when the only piped Azure role is refused' {
            $script:azUnlinked | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].FullyQualifiedErrorId | Should -BeLike 'LinkedEligibilityNotFound*'
            $script:writtenContent | Should -Match "AzureRoles\s+=\s+@\('old-azure-elig-001'\)"
        }
    }

    Context 'When no pipeline input is provided and only TenantId is changed' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{
                        TenantId       = '00000000-0000-0000-0000-000000000001'
                        DirectoryRoles = @('preserved-role-def-001')
                        EntraIDGroups  = @('preserved-group_member')
                        AzureRoles     = @('preserved-azure-001')
                    }
                }
            }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'preserves the existing DirectoryRoles' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match 'preserved-role-def-001'
        }

        It 'preserves the existing EntraIDGroups' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match 'preserved-group_member'
        }

        It 'preserves the existing AzureRoles' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match 'preserved-azure-001'
        }
    }

    Context 'When the alias is in the string form (OPIM-20)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            # The 0.4-era form: the alias maps straight to the tenant id, not to a hashtable.
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ contoso = '00000000-0000-0000-0000-000000000001' }
            }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }

            $script:stringFormRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
            }
            $script:stringFormRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'keeps the TenantId of the string form when -TenantId is not given' {
            $script:stringFormRole | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match "TenantId\s+=\s+'00000000-0000-0000-0000-000000000001'"
            $script:writtenContent | Should -Match ([regex]::Escape("'role-def-001|/'"))
        }

        It 'writes the given TenantId over the string form' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match "TenantId\s+=\s+'00000000-0000-0000-0000-000000000099'"
            $script:writtenContent | Should -Not -Match '00000000-0000-0000-0000-000000000001'
        }

        It 'keeps the TenantId when nothing is piped and no -TenantId is given' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It
            $script:writtenContent | Should -Match "TenantId\s+=\s+'00000000-0000-0000-0000-000000000001'"
        }
    }

    Context 'When the alias entry is an ordered dictionary' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = [ordered]@{
                        TenantId   = '00000000-0000-0000-0000-000000000001'
                        AzureRoles = @('kept-azure-001')
                    }
                }
            }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'keeps the TenantId and the stored lists of the entry' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match "TenantId\s+=\s+'00000000-0000-0000-0000-000000000001'"
            $script:writtenContent | Should -Match 'kept-azure-001'
        }
    }

    Context 'The display name in the confirmation (OPIM-45)' {
        # The Describe mock of Get-OPIMCurrentTenantInfo returns the tenant of the module's sign-in,
        # ...001, with the display name 'Mock Tenant'. Set shows that name only for the tenant it writes.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso  = @{ TenantId = '00000000-0000-0000-0000-000000000001' }
                    fabrikam = @{ TenantId = '00000000-0000-0000-0000-000000000002' }
                }
            }
        }

        It 'shows the display name when the alias keeps the tenant of the module sign-in' {
            $Text = Get-WhatIfText { Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf }
            $Text | Should -Match ([regex]::Escape("Update alias 'contoso' -> tenant 'Mock Tenant' (00000000-0000-0000-0000-000000000001)"))
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }

        It 'shows N/A when -TenantId names another tenant than the module sign-in' {
            $Text = Get-WhatIfText { Set-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf }
            $Text | Should -Match ([regex]::Escape("Update alias 'contoso' -> tenant 'N/A' (00000000-0000-0000-0000-000000000099)"))
            $Text | Should -Not -Match 'Mock Tenant'
        }

        It 'shows N/A when the alias keeps another tenant than the module sign-in' {
            $Text = Get-WhatIfText { Set-OPIMConfiguration -TenantAlias 'fabrikam' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf }
            $Text | Should -Match ([regex]::Escape("Update alias 'fabrikam' -> tenant 'N/A' (00000000-0000-0000-0000-000000000002)"))
            $Text | Should -Not -Match 'Mock Tenant'
        }
    }

    Context 'When the cloud of an alias is set (A12)' {
        # Set changes no cloud it is not asked to: -Environment sets the cloud, -Environment Global removes
        # it, and without -Environment whatever is stored stays, an unknown cloud included, except a
        # stored Global in any letter case, which is dropped since Global is never written. Connect-OPIM,
        # pim and unpim are the commands that refuse a cloud the module does not know. Set writes the
        # whole map, so each It reads the written text back as data and looks at its own alias.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    plain    = @{ TenantId = '00000000-0000-0000-0000-000000000001' }
                    gov      = @{
                        TenantId       = '00000000-0000-0000-0000-000000000002'
                        Environment    = 'USGov'
                        DirectoryRoles = @('kept-role-def-001|/')
                        EntraIDGroups  = @('kept-group-001_member')
                        AzureRoles     = @('kept-azure-001')
                    }
                    lower    = @{ TenantId = '00000000-0000-0000-0000-000000000003'; Environment = 'usgovdod' }
                    unknown  = @{ TenantId = '00000000-0000-0000-0000-000000000003'; Environment = 'Germany' }
                    globalc  = @{ TenantId = '00000000-0000-0000-0000-000000000003'; Environment = 'Global' }
                    globall  = @{ TenantId = '00000000-0000-0000-0000-000000000003'; Environment = 'global' }
                    globalu  = @{ TenantId = '00000000-0000-0000-0000-000000000003'; Environment = 'GLOBAL' }
                    blank    = @{ TenantId = '00000000-0000-0000-0000-000000000003'; Environment = '  ' }
                    oldstyle = '00000000-0000-0000-0000-000000000001'
                }
            }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }

            # The map Set wrote, read back as data (the module's Import-PowerShellDataFile mock is scoped
            # to the module, so this call is the real one).
            function Get-WrittenMap {
                $Path = Join-Path $TestDrive 'written-map.psd1'
                [System.IO.File]::WriteAllText($Path, [string]$script:writtenContent)
                Import-PowerShellDataFile -LiteralPath $Path
            }
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'stores the cloud given' {
            Set-OPIMConfiguration -TenantAlias 'plain' -Environment USGov -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It
            $Map = Get-WrittenMap
            $Map.plain.Environment | Should -BeExactly 'USGov'
            $Map.plain.TenantId | Should -BeExactly '00000000-0000-0000-0000-000000000001'
            # The cloud is written straight after the tenant.
            $script:writtenContent | Should -Match "'plain' = @\{\r?\n\s+TenantId\s+=\s+'00000000-0000-0000-0000-000000000001'\r?\n\s+Environment\s+=\s+'USGov'"
        }

        It 'stores the canonical name of the cloud for -Environment <Typed>' -ForEach @(
            @{ Typed = 'usgovdod'; Canonical = 'USGovDoD' }
            @{ Typed = 'CHINA'; Canonical = 'China' }
        ) {
            Set-OPIMConfiguration -TenantAlias 'plain' -Environment $Typed -TenantMapPath 'TestDrive:\TenantMap.psd1'
            (Get-WrittenMap).plain.Environment | Should -BeExactly $Canonical
        }

        It 'changes the stored cloud' {
            Set-OPIMConfiguration -TenantAlias 'gov' -Environment China -TenantMapPath 'TestDrive:\TenantMap.psd1'
            (Get-WrittenMap).gov.Environment | Should -BeExactly 'China'
        }

        It 'removes the stored cloud for -Environment Global' {
            Set-OPIMConfiguration -TenantAlias 'gov' -Environment Global -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It
            $Map = Get-WrittenMap
            $Map.gov.ContainsKey('Environment') | Should -BeFalse
            $Map.gov.TenantId | Should -BeExactly '00000000-0000-0000-0000-000000000002'
            $Map.gov.AzureRoles | Should -BeExactly 'kept-azure-001'
        }

        It 'keeps the stored cloud without -Environment' {
            Set-OPIMConfiguration -TenantAlias 'gov' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $Map = Get-WrittenMap
            $Map.gov.Environment | Should -BeExactly 'USGov'
            $Map.gov.TenantId | Should -BeExactly '00000000-0000-0000-0000-000000000002'
        }

        It 'keeps the stored cloud when only the tenant is changed' {
            Set-OPIMConfiguration -TenantAlias 'gov' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $Map = Get-WrittenMap
            $Map.gov.TenantId | Should -BeExactly '00000000-0000-0000-0000-000000000099'
            $Map.gov.Environment | Should -BeExactly 'USGov'
        }

        It 'keeps the stored cloud when roles are piped' {
            $Role = [PSCustomObject]@{ id = 'elig-001'; roleDefinitionId = 'new-role-def-001'; directoryScopeId = '/' }
            $Role.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            $Role | Set-OPIMConfiguration -TenantAlias 'gov' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $Map = Get-WrittenMap
            $Map.gov.Environment | Should -BeExactly 'USGov'
            $Map.gov.DirectoryRoles | Should -BeExactly 'new-role-def-001|/'
        }

        It 'keeps the stored tenant and lists when only -Environment is given' {
            Set-OPIMConfiguration -TenantAlias 'gov' -Environment China -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $Map = Get-WrittenMap
            $Map.gov.TenantId | Should -BeExactly '00000000-0000-0000-0000-000000000002'
            $Map.gov.DirectoryRoles | Should -BeExactly 'kept-role-def-001|/'
            $Map.gov.EntraIDGroups | Should -BeExactly 'kept-group-001_member'
            $Map.gov.AzureRoles | Should -BeExactly 'kept-azure-001'
        }

        It 'keeps a stored unknown cloud without -Environment' {
            Set-OPIMConfiguration -TenantAlias 'unknown' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            (Get-WrittenMap).unknown.Environment | Should -BeExactly 'Germany'
        }

        It 'replaces a stored unknown cloud with -Environment' {
            Set-OPIMConfiguration -TenantAlias 'unknown' -Environment USGov -TenantMapPath 'TestDrive:\TenantMap.psd1'
            (Get-WrittenMap).unknown.Environment | Should -BeExactly 'USGov'
        }

        It 'keeps a stored cloud in another letter case as it is written' {
            Set-OPIMConfiguration -TenantAlias 'lower' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            (Get-WrittenMap).lower.Environment | Should -BeExactly 'usgovdod'
        }

        It 'writes no Environment for a stored Global or a stored white space' {
            Set-OPIMConfiguration -TenantAlias 'globalc' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            (Get-WrittenMap).globalc.ContainsKey('Environment') | Should -BeFalse
            $script:writtenContent = $null
            Set-OPIMConfiguration -TenantAlias 'blank' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            (Get-WrittenMap).blank.ContainsKey('Environment') | Should -BeFalse
        }

        It 'drops a stored Global in any letter case when -Environment is omitted' {
            # Global is never written, so a stored Global (written by hand, in any letter case) means the
            # same as none, and Set writes the entry back without the key. The documented exception to
            # "the stored cloud is kept as it is written".
            foreach ($Alias in 'globall', 'globalu') {
                $script:writtenContent = $null
                Set-OPIMConfiguration -TenantAlias $Alias -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
                $Errs.Count | Should -Be 0
                $Map = Get-WrittenMap
                $Map.$Alias.ContainsKey('Environment') | Should -BeFalse -Because "$Alias stores Global, which is never written"
                $Map.$Alias.TenantId | Should -BeExactly '00000000-0000-0000-0000-000000000003'
            }
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 2 -Exactly -Scope It
        }

        It 'writes no Environment without -Environment for an alias that stores none' {
            Set-OPIMConfiguration -TenantAlias 'plain' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            (Get-WrittenMap).plain.ContainsKey('Environment') | Should -BeFalse
        }

        It 'leaves the other aliases as they are' {
            Set-OPIMConfiguration -TenantAlias 'plain' -Environment China -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $Map = Get-WrittenMap
            $Map.gov.Environment | Should -BeExactly 'USGov'
            $Map.lower.Environment | Should -BeExactly 'usgovdod'
            $Map.unknown.Environment | Should -BeExactly 'Germany'
        }

        It 'writes the string form in the table form with the cloud given' {
            Set-OPIMConfiguration -TenantAlias 'oldstyle' -Environment USGov -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $Map = Get-WrittenMap
            $Map.oldstyle.TenantId | Should -BeExactly '00000000-0000-0000-0000-000000000001'
            $Map.oldstyle.Environment | Should -BeExactly 'USGov'
        }

        It 'writes nothing under -WhatIf' {
            Set-OPIMConfiguration -TenantAlias 'plain' -Environment USGov -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }

        It 'names the cloud the alias will store in the confirmation' {
            # The cloud -Environment names, and the stored cloud Set keeps without it.
            $Text = Get-WhatIfText { Set-OPIMConfiguration -TenantAlias 'plain' -Environment USGov -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf }
            $Line = 'What if: Performing the operation "' +
                "Update alias 'plain' -> tenant 'Mock Tenant' (00000000-0000-0000-0000-000000000001) in cloud 'USGov'" +
                '" on target "TestDrive:\TenantMap.psd1".'
            $Text | Should -Match ([regex]::Escape($Line))
            $Text = Get-WhatIfText { Set-OPIMConfiguration -TenantAlias 'gov' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf }
            $Text | Should -Match ([regex]::Escape("Update alias 'gov' -> tenant 'N/A' (00000000-0000-0000-0000-000000000002) in cloud 'USGov'" + '"'))
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }

        It 'names Global in the confirmation when the alias will store no cloud' {
            # An alias that stores none, and one whose stored Global (in another letter case) is dropped.
            $Text = Get-WhatIfText { Set-OPIMConfiguration -TenantAlias 'plain' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf }
            $Line = 'What if: Performing the operation "' +
                "Update alias 'plain' -> tenant 'Mock Tenant' (00000000-0000-0000-0000-000000000001) in cloud 'Global'" +
                '" on target "TestDrive:\TenantMap.psd1".'
            $Text | Should -Match ([regex]::Escape($Line))
            $Text = Get-WhatIfText { Set-OPIMConfiguration -TenantAlias 'globall' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf }
            $Text | Should -Match ([regex]::Escape("Update alias 'globall' -> tenant 'N/A' (00000000-0000-0000-0000-000000000003) in cloud 'Global'" + '"'))
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }

        It 'refuses an unknown -Environment at binding' {
            $Caught = $null
            try {
                Set-OPIMConfiguration -TenantAlias 'plain' -Environment Germany -TenantMapPath 'TestDrive:\TenantMap.psd1'
            } catch {
                $Caught = $PSItem
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'ParameterArgumentValidationError,Set-OPIMConfiguration'
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }

        It 'keeps -Environment the last parameter, after -InputObject, so no position moves' {
            $Names = @((Get-Command Set-OPIMConfiguration).ScriptBlock.Ast.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $Names[-1] | Should -BeExactly 'Environment'
            $Names[-2] | Should -BeExactly 'InputObject'
        }
    }

    Context 'When the module holds no sign-in (OPIM-45)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMCurrentTenantInfo {
                return [PSCustomObject]@{ TenantId = $null; DisplayName = '' }
            }
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{
                        TenantId       = '00000000-0000-0000-0000-000000000001'
                        DirectoryRoles = @('old-role-def-001|/')
                    }
                }
            }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }

            $script:noSessionRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
            }
            $script:noSessionRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'writes the piped objects and keeps the stored tenant' {
            $script:noSessionRole | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -WarningVariable Warns -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $Errors.Count | Should -Be 0
            $Warns.Count | Should -Be 0
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It
            $script:writtenContent | Should -Match "TenantId\s+=\s+'00000000-0000-0000-0000-000000000001'"
            $script:writtenContent | Should -Match ([regex]::Escape("DirectoryRoles = @('role-def-001|/')"))
        }

        It 'shows N/A in the confirmation' {
            $Text = Get-WhatIfText { $script:noSessionRole | Set-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf }
            $Text | Should -Match ([regex]::Escape("Update alias 'contoso' -> tenant 'N/A' (00000000-0000-0000-0000-000000000001)"))
        }
    }

    Context 'When -WhatIf is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{ TenantId = '00000000-0000-0000-0000-000000000001' }
                }
            }
        }

        It 'does not call Set-Content' {
            Set-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }

    Context 'The default -TenantMapPath (OPIM-21)' {
        BeforeAll {
            $Param = (Get-Command Set-OPIMConfiguration).ScriptBlock.Ast.Body.ParamBlock.Parameters |
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
            Set-OPIMConfiguration -TenantAlias 'contoso' -WhatIf -ErrorVariable Errs -ErrorAction SilentlyContinue
            $script:SeenPaths | Should -Contain $ExpectedPath
            $Errs[-1].FullyQualifiedErrorId | Should -BeLike 'TenantMapNotFound*'
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }
}
