Describe 'Install-OPIMConfiguration' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
        Mock -ModuleName Omnicit.PIM Write-Host { }
        Mock -ModuleName Omnicit.PIM Set-Content { }
        Mock -ModuleName Omnicit.PIM New-Item { }
        Mock -ModuleName Omnicit.PIM Get-OPIMCurrentTenantInfo {
            return [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000001'; DisplayName = 'Mock Tenant' }
        }
        $PSDefaultParameterValues['Install-OPIMConfiguration:Confirm'] = $false
    }
    AfterAll {
        $null = $PSDefaultParameterValues.Remove('Install-OPIMConfiguration:Confirm')
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
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
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 1 -Scope It
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

        It 'writes the roleDefinitionId into the DirectoryRoles list' {
            $script:dirRole | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match 'role-def-001'
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

    Context 'When an unrecognised InputObject type is piped' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }  -ParameterFilter { $Path -notlike '*.psd1' }
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
        }

        It 'silently ignores the unknown object and still calls Set-Content' {
            [PSCustomObject]@{ SomeProperty = 'value' } | Install-OPIMConfiguration -TenantAlias 'contoso' -TenantId '00000000-0000-0000-0000-000000000001' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 1 -Scope It
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
            Should -Invoke New-Item -ModuleName Omnicit.PIM -Times 1 -Scope It -ParameterFilter { $ItemType -eq 'Directory' }
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

    Context 'When TenantId is not provided but an active Graph session exists' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMCurrentTenantInfo {
                return [PSCustomObject]@{ TenantId = 'cccccccc-0000-0000-0000-000000000003'; DisplayName = 'Auto Tenant' }
            }
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }  -ParameterFilter { $Path -notlike '*.psd1' }
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Set-Content { $script:writtenContent = $Value }
        }
        BeforeEach {
            $script:writtenContent = $null
        }

        It 'resolves the TenantId from the Graph session and writes it into the PSD1' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            $script:writtenContent | Should -Match 'cccccccc-0000-0000-0000-000000000003'
        }

        It 'does not write an error when TenantId is omitted but a session exists' {
            $Errors = @()
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -Be 0
        }
    }

    Context 'When TenantId is not provided and there is no active Graph session' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMCurrentTenantInfo {
                return [PSCustomObject]@{ TenantId = $null; DisplayName = $null }
            }
            Mock -ModuleName Omnicit.PIM Test-Path { return $true }  -ParameterFilter { $Path -notlike '*.psd1' }
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
        }

        It 'writes a non-terminating error with error id TenantIdNotResolvable' {
            $Errors = @()
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
            $Errors[0].FullyQualifiedErrorId | Should -Match 'TenantIdNotResolvable'
        }

        It 'does not call Set-Content when TenantId cannot be resolved' {
            Install-OPIMConfiguration -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
            Should -Invoke Set-Content -ModuleName Omnicit.PIM -Times 0 -Scope It
        }
    }
}