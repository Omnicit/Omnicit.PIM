#Requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'Get-OPIMDirectoryRole' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../../../Source/Omnicit.PIM.psd1" -Force
    }

    Context 'Happy path — eligible role schedules returned' {
        BeforeAll {
            Mock -ModuleName 'Omnicit.PIM' Get-MyId { 'user-id-123' }
            Mock -ModuleName 'Omnicit.PIM' Restore-GraphProperty { param($InputObject) $InputObject }
            Mock -ModuleName 'Omnicit.PIM' Invoke-MgGraphRequest {
                [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{
                            id               = 'elig-id-1'
                            roleDefinitionId = 'rdef-1'
                            directoryScopeId = '/'
                            principalId      = 'user-id-123'
                            roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator'; id = 'rdef-1' }
                        }
                    )
                }
            }
            $script:result = Get-OPIMDirectoryRole
        }

        It 'Returns at least one role object' {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It 'Tags each output object as Omnicit.PIM.DirectoryRole' {
            $script:result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryRole'
        }

        It 'Calls the Graph API' {
            Should -Invoke -CommandName 'Invoke-MgGraphRequest' -ModuleName 'Omnicit.PIM' -Times 1 -Exactly
        }
    }

    Context 'Empty result set — no eligible roles exist' {
        BeforeAll {
            Mock -ModuleName 'Omnicit.PIM' Get-MyId { 'user-id-123' }
            Mock -ModuleName 'Omnicit.PIM' Invoke-MgGraphRequest { [PSCustomObject]@{ value = @() } }
        }

        It 'Returns nothing without throwing' {
            { $script:empty = Get-OPIMDirectoryRole } | Should -Not -Throw
        }

        It 'Produces no pipeline output' {
            $script:empty = Get-OPIMDirectoryRole
            $script:empty | Should -BeNullOrEmpty
        }
    }

    Context 'API error path — Graph throws' {
        BeforeAll {
            Mock -ModuleName 'Omnicit.PIM' Get-MyId { 'user-id-123' }
            Mock -ModuleName 'Omnicit.PIM' Invoke-MgGraphRequest {
                throw [System.Net.Http.HttpRequestException]::new('Simulated Graph failure')
            }
            Mock -ModuleName 'Omnicit.PIM' Convert-GraphHttpException {
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Mocked Graph error'),
                    'MockedGraphError',
                    [System.Management.Automation.ErrorCategory]::ConnectionError,
                    $null
                )
            }
            Mock -ModuleName 'Omnicit.PIM' Write-CmdletError { }
        }

        It 'Does not throw a terminating error' {
            { Get-OPIMDirectoryRole -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Invokes the Graph error-handling helper' {
            Get-OPIMDirectoryRole -ErrorAction SilentlyContinue
            Should -Invoke -CommandName 'Convert-GraphHttpException' -ModuleName 'Omnicit.PIM' -Times 1 -Exactly
        }
    }

    Context '-Activated switch — queries active assignments' {
        BeforeAll {
            Mock -ModuleName 'Omnicit.PIM' Get-MyId { 'user-id-123' }
            Mock -ModuleName 'Omnicit.PIM' Restore-GraphProperty { param($InputObject) $InputObject }
            Mock -ModuleName 'Omnicit.PIM' Invoke-MgGraphRequest {
                [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{
                            id               = 'active-id-1'
                            roleDefinitionId = 'rdef-1'
                            directoryScopeId = '/'
                            principalId      = 'user-id-123'
                            roleDefinition   = [PSCustomObject]@{ displayName = 'User Administrator'; id = 'rdef-1' }
                            startDateTime    = '2026-03-26T00:00:00Z'
                            endDateTime      = '2026-03-26T01:00:00Z'
                        }
                    )
                }
            }
            $script:result = Get-OPIMDirectoryRole -Activated
        }

        It 'Returns active role objects' {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It 'Queries the roleAssignmentScheduleInstances endpoint' {
            Should -Invoke -CommandName 'Invoke-MgGraphRequest' -ModuleName 'Omnicit.PIM' -ParameterFilter {
                $Uri -match 'roleAssignmentScheduleInstances'
            } -Times 1 -Exactly
        }
    }

    Context '-All switch — all principals, no principal ID filter' {
        BeforeAll {
            Mock -ModuleName 'Omnicit.PIM' Invoke-MgGraphRequest { [PSCustomObject]@{ value = @() } }
            Get-OPIMDirectoryRole -All
        }

        It 'Does not call Get-MyId when -All is specified' {
            Should -Invoke -CommandName 'Get-MyId' -ModuleName 'Omnicit.PIM' -Times 0 -Exactly
        }
    }

    Context '-Identity parameter — retrieve single schedule by ID' {
        BeforeAll {
            Mock -ModuleName 'Omnicit.PIM' Get-MyId { 'user-id-123' }
            Mock -ModuleName 'Omnicit.PIM' Restore-GraphProperty { param($InputObject) $InputObject }
            Mock -ModuleName 'Omnicit.PIM' Invoke-MgGraphRequest {
                [PSCustomObject]@{
                    id               = 'elig-specific-id'
                    roleDefinitionId = 'rdef-1'
                    directoryScopeId = '/'
                    principalId      = 'user-id-123'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Global Reader'; id = 'rdef-1' }
                }
            }
            $script:result = Get-OPIMDirectoryRole -Identity 'elig-specific-id'
        }

        It 'Returns the matching role object' {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It 'Includes the identity in the API request URI' {
            Should -Invoke -CommandName 'Invoke-MgGraphRequest' -ModuleName 'Omnicit.PIM' -ParameterFilter {
                $Uri -match 'elig-specific-id'
            } -Times 1 -Exactly
        }
    }

    Context '-Filter parameter — OData filter pass-through' {
        BeforeAll {
            Mock -ModuleName 'Omnicit.PIM' Get-MyId { 'user-id-123' }
            Mock -ModuleName 'Omnicit.PIM' Invoke-MgGraphRequest { [PSCustomObject]@{ value = @() } }
        }

        It 'Accepts a filter string without throwing' {
            { Get-OPIMDirectoryRole -Filter "status eq 'Provisioned'" } | Should -Not -Throw
        }

        It 'Calls the Graph API when a filter is supplied' {
            Get-OPIMDirectoryRole -Filter "status eq 'Provisioned'"
            Should -Invoke -CommandName 'Invoke-MgGraphRequest' -ModuleName 'Omnicit.PIM' -Times 1 -Exactly
        }
    }
}