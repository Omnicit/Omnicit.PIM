BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Install-OPIMConfiguration' {
    BeforeAll {
        Mock -ModuleName Omnicit.PIM Write-Host { }
        Mock -ModuleName Omnicit.PIM Set-Content { }
        Mock -ModuleName Omnicit.PIM New-Item { }
        Mock -ModuleName Omnicit.PIM Get-OPIMCurrentTenantInfo {
            return [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000001'; DisplayName = 'Mock Tenant' }
        }
        $PSDefaultParameterValues['Install-OPIMConfiguration:Confirm'] = $false

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
        $null = $PSDefaultParameterValues.Remove('Install-OPIMConfiguration:Confirm')
    }

    Context 'When creating a new tenant alias with no existing TenantMap file' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }  -ParameterFilter { $Path -notlike '*.psd1' }
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'calls Set-Content once to write the PSD1' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It
        }

        It 'does not call New-Item when the directory already exists' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke New-Item -ModuleName Omnicit.PIM -Times 0 -Scope It
        }

        It 'writes the TenantId into the PSD1 content' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match '00000000-0000-0000-0000-000000000001'
        }

        It 'writes the tenant alias key into the PSD1 content' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match "'contoso'"
        }
    }

    Context 'When a directory role object is piped' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }  -ParameterFilter { $Path -notlike '*.psd1' }
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }

            $script:dirRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
            }
            $script:dirRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'writes roleDefinitionId|directoryScopeId into the DirectoryRoles list' {
            $script:dirRole | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match ([regex]::Escape("'role-def-001|/'"))
        }

        It 'writes the administrative unit of a post at an administrative unit' {
            $AuRole = [PSCustomObject]@{ id = 'elig-002'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/administrativeUnits/au-001' }
            $AuRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            $AuRole | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match ([regex]::Escape("'role-def-001|/administrativeUnits/au-001'"))
            $script:writtenContent | Should -Not -Match ([regex]::Escape("'role-def-001|/'"))
        }

        It 'stores a key once when the same post is piped twice' {
            # Get-OPIMDirectoryRole -All returns the eligible and the active post of one role at one scope.
            $ActiveRole = [PSCustomObject]@{ id = 'active-001'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/' }
            $ActiveRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleInstance')
            $script:dirRole, $ActiveRole | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Not -BeNullOrEmpty
            [regex]::Matches($script:writtenContent, [regex]::Escape("'role-def-001|/'")).Count | Should -Be 1
        }

        It 'stores a key once when two posts differ only in letter case, and keeps the first' {
            $Lower = [PSCustomObject]@{ id = 'elig-003'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/administrativeUnits/au-001' }
            $Upper = [PSCustomObject]@{ id = 'elig-004'; roleDefinitionId = 'ROLE-DEF-001'; directoryScopeId = '/administrativeUnits/AU-001' }
            $Other = [PSCustomObject]@{ id = 'elig-005'; roleDefinitionId = 'role-def-002'; directoryScopeId = '/' }
            foreach ($Post in @($Lower, $Upper, $Other)) { $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule') }
            $Lower, $Upper, $Other | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match ([regex]::Escape("DirectoryRoles = @('role-def-001|/administrativeUnits/au-001', 'role-def-002|/')"))
        }
    }

    Context 'When a group object is piped' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }  -ParameterFilter { $Path -notlike '*.psd1' }
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }

            $script:groupObj = [PSCustomObject]@{
                id       = 'elig-grp-001'
                groupId  = 'group-001'
                accessId = 'member'
            }
            $script:groupObj.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'writes the groupId_accessId key into the EntraIDGroups list' {
            $script:groupObj | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match 'group-001_member'
        }

        It 'stores a group key once when the eligible and the active post of one group are piped' {
            $ActiveGroup = [PSCustomObject]@{ id = 'active-grp-001'; groupId = 'group-001'; accessId = 'member' }
            $ActiveGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleInstance')
            $script:groupObj, $ActiveGroup | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Not -BeNullOrEmpty
            [regex]::Matches($script:writtenContent, [regex]::Escape("'group-001_member'")).Count | Should -Be 1
        }
    }

    Context 'When an Azure role object is piped' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }  -ParameterFilter { $Path -notlike '*.psd1' }
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }

            $script:azRole = [PSCustomObject]@{
                Name             = 'azure-elig-001'
                RoleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/role-def-az-001'
                ScopeId          = '/subscriptions/sub-001'
            }
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'writes the Azure role Name into the AzureRoles list' {
            $script:azRole | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match 'azure-elig-001'
        }
    }

    Context 'When an active Azure role is piped (OPIM-22)' {
        # An active instance from Get-OPIMAzureRole -Activated (or an active row of -All) is stored by
        # the eligibility schedule it was activated from and its own scope, '<Name>|<ScopeId>', which pim
        # matches only with that eligibility at that scope -- or refused when its link names no
        # eligibility, or names one at another scope.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }  -ParameterFilter { $Path -notlike '*.psd1' }
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
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
            $script:azActive | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $script:writtenContent | Should -Match ("AzureRoles\s+=\s+@\(" + [regex]::Escape("'elig-az-001|/subscriptions/sub-001'") + "\)")
            $script:writtenContent | Should -Not -Match 'az-active-001'
        }

        It 'stores an active role whose link is <Label> as its eligibility and its own scope' -ForEach @(
            @{ Label = 'a bare name'; Fixture = 'azBare'; Expected = 'elig-az-005|/subscriptions/sub-001' }
            @{ Label = 'the provider-only form'; Fixture = 'azProviderOnly'; Expected = 'elig-az-006|/subscriptions/sub-002' }
        ) {
            $Fixtures = @{ azBare = $script:azBare; azProviderOnly = $script:azProviderOnly }
            $Fixtures[$Fixture] | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $script:writtenContent | Should -Match ("AzureRoles\s+=\s+@\(" + [regex]::Escape("'$Expected'") + "\)")
        }

        It 'stores the key once when the eligible role and its active instance are piped' {
            $script:azEligible, $script:azActive | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $script:writtenContent | Should -Match "AzureRoles\s+=\s+@\('elig-az-001'\)"
            $script:writtenContent | Should -Not -Match 'az-active-001'
        }

        It 'stores the key once, in the form first piped, when the active instance comes before its eligible role' {
            $script:azActive, $script:azEligible | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $script:writtenContent | Should -Match ("AzureRoles\s+=\s+@\(" + [regex]::Escape("'elig-az-001|/subscriptions/sub-001'") + "\)")
        }

        It 'writes LinkedEligibilityNotFound for an active role that names no eligibility, and stores the other piped objects' {
            $script:azUnlinked, $script:azOther, $script:grpForAz | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
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
            $Out = $script:azOther, $script:azUnlinked | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'LinkedEligibilityNotFound*'
            $script:writtenContent | Should -Match "AzureRoles\s+=\s+@\('elig-az-003'\)"
        }

        It 'writes LinkedEligibilityNotFound for an active role at a narrower scope than its eligibility, and stores neither' {
            $script:azNarrow, $script:azOther | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[-1].FullyQualifiedErrorId | Should -BeLike 'LinkedEligibilityNotFound*'
            $Errs[-1].Exception.Message | Should -BeLike "The active Azure role 'Contributor' at scope 'rg-001' cannot be shown to be active at the scope of the eligibility*"
            $script:writtenContent | Should -Match "AzureRoles\s+=\s+@\('elig-az-003'\)"
            $script:writtenContent | Should -Not -Match 'elig-az-004'
            $script:writtenContent | Should -Not -Match 'az-active-004'
        }
    }

    Context 'When an unrecognised InputObject type is piped' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }  -ParameterFilter { $Path -notlike '*.psd1' }
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
        }

        It 'silently ignores the unknown object and still calls Set-Content' {
            [PSCustomObject]@{ SomeProperty = 'value' } | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It
        }
    }

    Context 'When the tenant alias already exists' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    contoso = @{ TenantId = '00000000-0000-0000-0000-000000000099' }
                }
            }
        }

        It 'writes a non-terminating error mentioning the alias name' {
            $Errors = @()
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
            $Errors[0].Exception.Message | Should -Match 'contoso'
        }

        It 'does not call Set-Content' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }

        It 'suggests using Set-OPIMConfiguration in the error message' {
            $Errors = @()
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[0].Exception.Message | Should -Match 'Set-OPIMConfiguration'
        }
    }

    Context 'When the TenantMap directory does not exist' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -notlike '*.psd1' }
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
        }

        It 'calls New-Item to create the directory' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\NewDir\TenantMap.psd1'
            Should -Invoke New-Item -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It -ParameterFilter { $ItemType -eq 'Directory' }
        }
    }

    Context 'When -WhatIf is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }  -ParameterFilter { $Path -notlike '*.psd1' }
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
        }

        It 'does not call Set-Content' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }

    Context 'When TenantId is not provided and the module holds a sign-in (OPIM-45)' {
        # Get-OPIMCurrentTenantInfo returns the tenant of the module's own sign-in (the Describe mock:
        # ...001, 'Mock Tenant'); its own tests prove it never takes a foreign Graph context.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }  -ParameterFilter { $Path -notlike '*.psd1' }
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'writes the tenant of the module sign-in and no error' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -WarningVariable Warns -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $Errors.Count | Should -Be 0
            $Warns.Count | Should -Be 0
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It
            $script:writtenContent | Should -Match "TenantId\s+=\s+'00000000-0000-0000-0000-000000000001'"
        }

        It 'shows the display name of that tenant in the confirmation' {
            $Text = Get-WhatIfText { Install-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf }
            $Text | Should -Match ([regex]::Escape("Add alias 'contoso' for tenant 'Mock Tenant' (00000000-0000-0000-0000-000000000001)"))
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }

    Context 'When TenantId is not provided and the module holds no sign-in (OPIM-45)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMCurrentTenantInfo {
                return [PSCustomObject]@{ TenantId = $null; DisplayName = '' }
            }
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }  -ParameterFilter { $Path -notlike '*.psd1' }
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
        }

        It 'writes one TenantIdNotResolvable error that names the missing module sign-in' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -Be 1
            $Errors[0].FullyQualifiedErrorId | Should -BeLike 'TenantIdNotResolvable*'
            $Errors[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
            $Errors[0].Exception.Message | Should -Match 'Omnicit\.PIM holds no sign-in'
            $Errors[0].Exception.Message | Should -Match 'give -TenantId'
            $Errors[0].Exception.Message | Should -Match 'Connect-OPIM'
            $Errors[0].Exception.Message | Should -Match 'Connect-MgGraph outside the module is not used'
            $Errors[0].ErrorDetails.Message | Should -BeExactly $Errors[0].Exception.Message
        }

        It 'writes nothing when the tenant cannot be resolved' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
            Should -Invoke New-Item -ModuleName Omnicit.PIM -Times 0 -Scope It
            Should -Invoke Get-OPIMCurrentTenantInfo -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It
        }

        It 'writes the given -TenantId without a session' {
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }
            $script:writtenContent = $null
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -WarningVariable Warns -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $Errors.Count | Should -Be 0
            $Warns.Count | Should -Be 0
            $script:writtenContent | Should -Match "TenantId\s+=\s+'00000000-0000-0000-0000-000000000099'"
        }
    }

    Context 'When -TenantId differs from the tenant of the module sign-in (OPIM-45)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }  -ParameterFilter { $Path -notlike '*.psd1' }
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'writes a warning that names both tenants, and the given tenant' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WarningVariable Warns -WarningAction SilentlyContinue
            $Warns.Count | Should -Be 1
            $Warns[0].Message | Should -Match '00000000-0000-0000-0000-000000000099'
            $Warns[0].Message | Should -Match '00000000-0000-0000-0000-000000000001'
            $script:writtenContent | Should -Match "TenantId\s+=\s+'00000000-0000-0000-0000-000000000099'"
        }

        It 'shows N/A instead of the display name of the session tenant in the confirmation' {
            $Text = Get-WhatIfText { Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf -WarningAction SilentlyContinue }
            $Text | Should -Match ([regex]::Escape("Add alias 'contoso' for tenant 'N/A' (00000000-0000-0000-0000-000000000099)"))
            $Text | Should -Not -Match 'Mock Tenant'
        }

        It 'shows the display name and writes no warning when -TenantId is the session tenant in another letter case' {
            Mock -ModuleName Omnicit.PIM Get-OPIMCurrentTenantInfo {
                return [PSCustomObject]@{ TenantId = 'aaaaaaaa-0000-0000-0000-00000000000a'; DisplayName = 'Mock Tenant' }
            }
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId 'AAAAAAAA-0000-0000-0000-00000000000A' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WarningVariable Warns -WarningAction SilentlyContinue
            $Warns.Count | Should -Be 0
            $script:writtenContent | Should -Match "TenantId\s+=\s+'AAAAAAAA-0000-0000-0000-00000000000A'"
            $Text = Get-WhatIfText { Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId 'AAAAAAAA-0000-0000-0000-00000000000A' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf -WarningAction SilentlyContinue }
            $Text | Should -Match ([regex]::Escape("for tenant 'Mock Tenant' (AAAAAAAA-0000-0000-0000-00000000000A)"))
        }
    }

    Context 'When -Environment is given (A12)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }  -ParameterFilter { $Path -notlike '*.psd1' }
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'stores Environment for -Environment USGov' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -Environment USGov -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It
            $script:writtenContent | Should -Match "TenantId\s+=\s+'00000000-0000-0000-0000-000000000001'\r?\n\s+Environment\s+=\s+'USGov'"
        }

        It 'stores the canonical name of the cloud for -Environment <Typed>' -ForEach @(
            @{ Typed = 'usgovdod'; Canonical = 'USGovDoD' }
            @{ Typed = 'CHINA'; Canonical = 'China' }
            @{ Typed = 'USGov'; Canonical = 'USGov' }
        ) {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -Environment $Typed -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            # Case-sensitive: the file holds the canonical name, whatever case was typed.
            $script:writtenContent | Should -MatchExactly ("Environment\s+=\s+'" + $Canonical + "'")
        }

        It 'stores no Environment for -Environment Global' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -Environment Global -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It
            $script:writtenContent | Should -Not -BeNullOrEmpty
            $script:writtenContent | Should -Not -Match 'Environment'
            $script:writtenContent | Should -Match "TenantId\s+=\s+'00000000-0000-0000-0000-000000000001'"
        }

        It 'stores no Environment without -Environment and without a sign-in cloud' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $script:writtenContent | Should -Not -BeNullOrEmpty
            $script:writtenContent | Should -Not -Match 'Environment'
        }

        It 'stores the cloud with the roles that are piped' {
            $Role = [PSCustomObject]@{ id = 'elig-001'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/' }
            $Role.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            $Role | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -Environment China
            $script:writtenContent | Should -Match "Environment\s+=\s+'China'\r?\n\s+DirectoryRoles\s+=\s+@\('role-def-001\|/'\)"
        }

        It 'names the cloud in a verbose line' {
            $Verbose = Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -Environment USGov -Verbose 4>&1 |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message }
            # The cloud line itself; the ShouldProcess line of -Verbose names the cloud too.
            @($Verbose | Where-Object { $_ -like "Cloud for tenant alias*USGov*" }).Count | Should -Be 1
        }

        It 'names Global in the verbose line when no cloud is stored' {
            $Verbose = Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -Verbose 4>&1 |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message }
            @($Verbose | Where-Object { $_ -like "Cloud for tenant alias*Global*" }).Count | Should -Be 1
        }

        It 'names the cloud the alias will store in the confirmation' {
            $Text = Get-WhatIfText { Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -Environment USGov -WhatIf }
            $Line = 'What if: Performing the operation "' +
                "Add alias 'contoso' for tenant 'Mock Tenant' (00000000-0000-0000-0000-000000000001) in cloud 'USGov'" +
                '" on target "TestDrive:\TenantMap.psd1".'
            $Text | Should -Match ([regex]::Escape($Line))
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }

        It 'names Global in the confirmation when the alias will store no cloud' {
            $Text = Get-WhatIfText { Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf }
            $Line = 'What if: Performing the operation "' +
                "Add alias 'contoso' for tenant 'Mock Tenant' (00000000-0000-0000-0000-000000000001) in cloud 'Global'" +
                '" on target "TestDrive:\TenantMap.psd1".'
            $Text | Should -Match ([regex]::Escape($Line))
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }

        It 'refuses an unknown -Environment at binding' {
            $Caught = $null
            try {
                Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -Environment Germany
            } catch {
                $Caught = $PSItem
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'ParameterArgumentValidationError,Install-OPIMConfiguration'
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
            Should -Invoke Get-OPIMCurrentTenantInfo -ModuleName Omnicit.PIM -Times 0 -Scope It
        }

        It 'keeps -Environment the last parameter, after -InputObject, so no position moves' {
            $Names = @((Get-Command Install-OPIMConfiguration).ScriptBlock.Ast.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            $Names[-1] | Should -BeExactly 'Environment'
            $Names[-2] | Should -BeExactly 'InputObject'
        }
    }

    Context 'When the module is signed in to a sovereign cloud (A12, review focus 5)' {
        # The cloud is a property of the tenant: without -Environment, a new alias takes the cloud of the
        # module's sign-in only when it also takes that sign-in's tenant. Any other tenant is Global.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }  -ParameterFilter { $Path -notlike '*.psd1' }
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }
            Mock -ModuleName Omnicit.PIM Get-OPIMCurrentTenantInfo {
                return [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000001'; DisplayName = 'Mock Tenant'; Environment = 'USGov' }
            }
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'takes the cloud of the module''s sign-in with its tenant' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $script:writtenContent | Should -Match "TenantId\s+=\s+'00000000-0000-0000-0000-000000000001'\r?\n\s+Environment\s+=\s+'USGov'"
        }

        It 'takes the cloud of the sign-in for a -TenantId equal to the sign-in''s tenant' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -WarningVariable Warns -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $Warns.Count | Should -Be 0
            $script:writtenContent | Should -Match "Environment\s+=\s+'USGov'"
        }

        It 'takes the cloud of the sign-in for a -TenantId equal to the sign-in''s tenant in another letter case' {
            Mock -ModuleName Omnicit.PIM Get-OPIMCurrentTenantInfo {
                return [PSCustomObject]@{ TenantId = 'aaaaaaaa-0000-0000-0000-00000000000a'; DisplayName = 'Mock Tenant'; Environment = 'China' }
            }
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId 'AAAAAAAA-0000-0000-0000-00000000000A' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $script:writtenContent | Should -Match "Environment\s+=\s+'China'"
        }

        It 'names the cloud of the sign-in in the confirmation when the alias takes it' {
            $Text = Get-WhatIfText { Install-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WhatIf }
            $Text | Should -Match ([regex]::Escape("Add alias 'contoso' for tenant 'Mock Tenant' (00000000-0000-0000-0000-000000000001) in cloud 'USGov'"))
        }

        It 'stores no cloud for another tenant than the sign-in''s' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $script:writtenContent | Should -Match "TenantId\s+=\s+'00000000-0000-0000-0000-000000000099'"
            $script:writtenContent | Should -Not -Match 'Environment'
        }

        It 'stores the cloud that -Environment names, whatever the sign-in''s cloud, also for another tenant' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000099' -TenantMapPath 'TestDrive:\TenantMap.psd1' -Environment China -WarningAction SilentlyContinue
            $script:writtenContent | Should -Match "Environment\s+=\s+'China'"
            $script:writtenContent | Should -Not -Match "Environment\s+=\s+'USGov'"
        }

        It 'stores no cloud for -Environment Global, whatever the sign-in''s cloud, for its own tenant' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -Environment Global
            $script:writtenContent | Should -Not -BeNullOrEmpty
            $script:writtenContent | Should -Not -Match 'Environment'
        }

        It 'stores no cloud when the sign-in is in the Global cloud' {
            Mock -ModuleName Omnicit.PIM Get-OPIMCurrentTenantInfo {
                return [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000001'; DisplayName = 'Mock Tenant'; Environment = 'Global' }
            }
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Not -BeNullOrEmpty
            $script:writtenContent | Should -Not -Match 'Environment'
        }

        It 'stores no cloud when the sign-in records none' {
            Mock -ModuleName Omnicit.PIM Get-OPIMCurrentTenantInfo {
                return [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000001'; DisplayName = 'Mock Tenant' }
            }
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Not -BeNullOrEmpty
            $script:writtenContent | Should -Not -Match 'Environment'
        }

        It 'stores no cloud when the module holds no sign-in and a -TenantId is given' {
            Mock -ModuleName Omnicit.PIM Get-OPIMCurrentTenantInfo {
                return [PSCustomObject]@{ TenantId = $null; DisplayName = ''; Environment = $null }
            }
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Not -BeNullOrEmpty
            $script:writtenContent | Should -Not -Match 'Environment'
        }
    }

    Context 'The default -TenantMapPath (OPIM-21)' {
        BeforeAll {
            $Param = (Get-Command Install-OPIMConfiguration).ScriptBlock.Ast.Body.ParamBlock.Parameters |
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
            # -WhatIf, so the missing directory and file are not created; the Describe mocks New-Item and
            # Set-Content as well, and the last two assertions prove nothing reached either.
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -WhatIf -ErrorAction SilentlyContinue
            $script:SeenPaths | Should -Contain $ExpectedPath
            $script:SeenPaths | Should -Contain (Split-Path $ExpectedPath -Parent)
            Should -Invoke New-Item -ModuleName Omnicit.PIM -Times 0 -Scope It
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }
}