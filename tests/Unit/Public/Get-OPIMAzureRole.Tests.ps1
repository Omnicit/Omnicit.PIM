BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMAzureRole' {
    Context 'When called with default parameters (eligible roles)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeEligible = [PSCustomObject]@{
                Name                      = 'elig-001'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule { return $FakeEligible } -ParameterFilter { $Filter -eq 'asTarget()' }
        }

        It 'calls Get-AzRoleEligibilitySchedule with the asTarget() filter' {
            Get-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 1 -Scope It -ParameterFilter { $Filter -eq 'asTarget()' }
        }

        It 'returns objects tagged with Omnicit.PIM.AzureEligibilitySchedule' {
            $Result = Get-OPIMAzureRole
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureEligibilitySchedule'
        }
    }

    Context 'When -Activated is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeActive = [PSCustomObject]@{
                Name                      = 'active-001'
                AssignmentType            = 'Activated'
                RoleDefinitionId          = '/providers/Microsoft.Authorization/roleDefinitions/role-def-001'
                RoleDefinitionDisplayName = 'Contributor'
                ScopeId                   = '/subscriptions/sub-001'
                ScopeDisplayName          = 'My Subscription'
                PrincipalId               = 'principal-001'
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance { return $FakeActive } -ParameterFilter { $Filter -eq 'asTarget()' }
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule { }
        }

        It 'calls Get-AzRoleAssignmentScheduleInstance with the asTarget() filter' {
            Get-OPIMAzureRole -Activated
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 1 -Scope It -ParameterFilter { $Filter -eq 'asTarget()' }
        }

        It 'does not call Get-AzRoleEligibilitySchedule' {
            Get-OPIMAzureRole -Activated
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 0 -Scope It
        }

        It 'returns objects tagged with Omnicit.PIM.AzureAssignmentScheduleInstance' {
            $Result = Get-OPIMAzureRole -Activated
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleInstance'
        }
    }

    Context 'When -Activated returns mixed assignment types' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeActive = [PSCustomObject]@{
                Name           = 'active-001'
                AssignmentType = 'Activated'
                PrincipalId    = 'principal-001'
            }
            $FakeInherited = [PSCustomObject]@{
                Name           = 'inherited-001'
                AssignmentType = 'Assigned'
                PrincipalId    = 'principal-001'
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance { return @($FakeInherited, $FakeActive) }
        }

        It 'filters out non-Activated assignment types and returns only Activated entries' {
            $Result = Get-OPIMAzureRole -Activated
            $Result | Should -HaveCount 1
            $Result[0].AssignmentType | Should -Be 'Activated'
        }
    }

    Context 'When -All is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule { return @() } -ParameterFilter { $Filter -eq 'asTarget()' }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance { return @() } -ParameterFilter { $Filter -eq 'asTarget()' }
        }

        It 'calls Get-AzRoleEligibilitySchedule with the asTarget() filter' {
            Get-OPIMAzureRole -All
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 1 -Scope It -ParameterFilter { $Filter -eq 'asTarget()' }
        }

        It 'calls Get-AzRoleAssignmentScheduleInstance with the asTarget() filter' {
            Get-OPIMAzureRole -All
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 1 -Scope It -ParameterFilter { $Filter -eq 'asTarget()' }
        }
    }

    Context 'When -All returns both eligible and active results' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeEligible = [PSCustomObject]@{
                Name                      = 'elig-001'
                RoleDefinitionDisplayName = 'Contributor'
                ScopeDisplayName          = 'My Subscription'
                ScopeId                   = '/subscriptions/sub-001'
                PrincipalId               = 'principal-001'
            }
            $FakeActive = [PSCustomObject]@{
                Name                      = 'active-001'
                AssignmentType            = 'Activated'
                RoleDefinitionDisplayName = 'Contributor'
                ScopeDisplayName          = 'My Subscription'
                ScopeId                   = '/subscriptions/sub-001'
                PrincipalId               = 'principal-001'
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule { return $FakeEligible } -ParameterFilter { $Filter -eq 'asTarget()' }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance { return $FakeActive } -ParameterFilter { $Filter -eq 'asTarget()' }
        }

        It 'tags all results with Omnicit.PIM.AzureCombinedSchedule' {
            $Result = Get-OPIMAzureRole -All
            $Result | ForEach-Object {
                $_.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureCombinedSchedule'
            }
        }

        It 'sets Status to Eligible on eligible items and Active on active items' {
            $Result = Get-OPIMAzureRole -All
            ($Result | Where-Object Status -EQ 'Eligible').Count | Should -Be 1
            ($Result | Where-Object Status -EQ 'Active').Count | Should -Be 1
        }
    }

    Context 'When -Identity is specified' {
        # OPIM-23: a normal user is refused a GET of one schedule by Name at the root scope
        # (InsufficientPermissions), while the asTarget() listing is allowed. A Name is therefore found
        # among the posts that listing returns and is never handed to Az.Resources. The mocks answer
        # a listing with every post whatever it is asked for, so a call that sent -Name would still get
        # them all: what separates the post is the cmdlet's own filter, and the arguments of each call
        # are asserted on their own. The fakes are built inside the mocks, so each call gets objects
        # that no earlier call has decorated.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal { $null }
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {
                [PSCustomObject]@{
                    Name = 'azure-001'; RoleDefinitionDisplayName = 'Reader'
                    ScopeId = '/subscriptions/sub-001/resourceGroups/rg-one'; ScopeDisplayName = 'rg-one'; PrincipalId = 'principal-001'
                }
                [PSCustomObject]@{
                    Name = 'azure-002'; RoleDefinitionDisplayName = 'Reader'
                    ScopeId = '/subscriptions/sub-001/resourceGroups/rg-two'; ScopeDisplayName = 'rg-two'; PrincipalId = 'principal-001'
                }
                [PSCustomObject]@{
                    Name = 'azure-003'; RoleDefinitionDisplayName = 'Contributor'
                    ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'Subscription One'; PrincipalId = 'principal-001'
                }
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance {
                [PSCustomObject]@{
                    Name = 'azure-act-001'; AssignmentType = 'Activated'; RoleDefinitionDisplayName = 'Reader'
                    ScopeId = '/subscriptions/sub-001/resourceGroups/rg-one'; ScopeDisplayName = 'rg-one'; PrincipalId = 'principal-001'
                }
                [PSCustomObject]@{
                    Name = 'azure-act-002'; AssignmentType = 'Activated'; RoleDefinitionDisplayName = 'Reader'
                    ScopeId = '/subscriptions/sub-001/resourceGroups/rg-two'; ScopeDisplayName = 'rg-two'; PrincipalId = 'principal-001'
                }
                [PSCustomObject]@{
                    Name = 'azure-act-003'; AssignmentType = 'Activated'; RoleDefinitionDisplayName = 'Contributor'
                    ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'Subscription One'; PrincipalId = 'principal-001'
                }
            }
        }

        Context 'in the default dual search' {
            It 'returns only the eligible post that carries the Name' {
                $Result = @(Get-OPIMAzureRole -Identity 'azure-002')
                $Result | Should -HaveCount 1
                $Result[0].Name | Should -BeExactly 'azure-002'
                $Result[0].Status | Should -BeExactly 'Eligible'
                $Result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureCombinedSchedule'
                $Result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureEligibilitySchedule'
            }

            It 'returns only the active post that carries the Name' {
                $Result = @(Get-OPIMAzureRole -Identity 'azure-act-002')
                $Result | Should -HaveCount 1
                $Result[0].Name | Should -BeExactly 'azure-act-002'
                $Result[0].Status | Should -BeExactly 'Active'
                $Result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureCombinedSchedule'
                $Result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleInstance'
            }

            It 'returns nothing, and writes no error, for a Name that no post carries' {
                $Output = @(Get-OPIMAzureRole -Identity 'azure-999' -ErrorAction Continue 2>&1)
                $Output | Should -HaveCount 0
            }

            It 'lists both states with the asTarget() filter at the root scope' {
                $null = Get-OPIMAzureRole -Identity 'azure-002'
                Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Filter -eq 'asTarget()' -and $Scope -eq '/'
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Filter -eq 'asTarget()' -and $Scope -eq '/'
                }
            }

            It 'hands no Name to Az.Resources' {
                $null = Get-OPIMAzureRole -Identity 'azure-002'
                Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 0 -Scope It -ParameterFilter { $Name }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 0 -Scope It -ParameterFilter { $Name }
            }
        }

        Context 'with -Activated' {
            It 'returns only the active instance that carries the Name' {
                $Result = @(Get-OPIMAzureRole -Activated -Identity 'azure-act-002')
                $Result | Should -HaveCount 1
                $Result[0].Name | Should -BeExactly 'azure-act-002'
                $Result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleInstance'
            }

            It 'returns nothing for the Name of an eligible post' {
                $Output = @(Get-OPIMAzureRole -Activated -Identity 'azure-002' -ErrorAction Continue 2>&1)
                $Output | Should -HaveCount 0
            }

            It 'lists the active posts with the asTarget() filter at the root scope, passes no Name and reads no eligible list' {
                $null = Get-OPIMAzureRole -Activated -Identity 'azure-act-002'
                Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Filter -eq 'asTarget()' -and $Scope -eq '/' -and -not $Name
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 0 -Scope It
            }

            It 'lists the active posts at the scope that -Scope names, and keeps the instance there' {
                $Result = @(Get-OPIMAzureRole -Activated -Identity 'azure-act-002' -Scope '/subscriptions/sub-001/resourceGroups/rg-two')
                $Result | Should -HaveCount 1
                $Result[0].Name | Should -BeExactly 'azure-act-002'
                Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Scope -eq '/subscriptions/sub-001/resourceGroups/rg-two' -and $Filter -eq 'asTarget()'
                }
            }

            It 'returns nothing when -Scope names another scope than the instance is at' {
                $Result = @(Get-OPIMAzureRole -Activated -Identity 'azure-act-002' -Scope '/subscriptions/sub-001/resourceGroups/rg-one')
                $Result | Should -HaveCount 0
            }

            It 'compares the scope without regard to case' {
                $Result = @(Get-OPIMAzureRole -Activated -Identity 'azure-act-002' -Scope '/SUBSCRIPTIONS/SUB-001/RESOURCEGROUPS/RG-TWO')
                $Result | Should -HaveCount 1
                $Result[0].Name | Should -BeExactly 'azure-act-002'
            }
        }

        Context 'with -Scope' {
            It 'returns nothing when -Scope names another scope than the eligible post is at' {
                $Result = @(Get-OPIMAzureRole -Identity 'azure-001' -Scope '/subscriptions/sub-001/resourceGroups/rg-two')
                $Result | Should -HaveCount 0
            }

            It 'returns nothing when -Scope names another scope than the active post is at' {
                $Result = @(Get-OPIMAzureRole -Identity 'azure-act-001' -Scope '/subscriptions/sub-001/resourceGroups/rg-two')
                $Result | Should -HaveCount 0
            }

            It 'returns the eligible post when -Scope names its scope' {
                $Result = @(Get-OPIMAzureRole -Identity 'azure-001' -Scope '/subscriptions/sub-001/resourceGroups/rg-one')
                $Result | Should -HaveCount 1
                $Result[0].Name | Should -BeExactly 'azure-001'
            }

            It 'compares the scope of an eligible post without regard to case' {
                $Result = @(Get-OPIMAzureRole -Identity 'azure-001' -Scope '/SUBSCRIPTIONS/SUB-001/RESOURCEGROUPS/RG-ONE')
                $Result | Should -HaveCount 1
                $Result[0].Name | Should -BeExactly 'azure-001'
            }

            It 'compares the scope of an active post without regard to case' {
                $Result = @(Get-OPIMAzureRole -Identity 'azure-act-001' -Scope '/SUBSCRIPTIONS/SUB-001/RESOURCEGROUPS/RG-ONE')
                $Result | Should -HaveCount 1
                $Result[0].Name | Should -BeExactly 'azure-act-001'
            }

            It 'matches the scope exactly, not as a prefix' {
                $Result = @(Get-OPIMAzureRole -Identity 'azure-001' -Scope '/subscriptions/sub-001')
                $Result | Should -HaveCount 0
            }

            It 'lists at the root scope all the same, whatever scope -Scope names' {
                $null = Get-OPIMAzureRole -Identity 'azure-001' -Scope '/subscriptions/sub-001/resourceGroups/rg-one'
                Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Filter -eq 'asTarget()' -and $Scope -eq '/'
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Filter -eq 'asTarget()' -and $Scope -eq '/'
                }
            }

            It 'reads -Scope ''/'' as every scope, like the default' {
                $Result = @(Get-OPIMAzureRole -Identity 'azure-002' -Scope '/')
                $Result | Should -HaveCount 1
                $Result[0].Name | Should -BeExactly 'azure-002'
            }

            It 'filters the -All listing to the scope as well' {
                $Everything = @(Get-OPIMAzureRole -All)
                $Everything | Should -HaveCount 6
                $Result = @(Get-OPIMAzureRole -All -Scope '/subscriptions/sub-001/resourceGroups/rg-two')
                ($Result | Sort-Object Name | ForEach-Object { "$($_.Status):$($_.Name)" }) -join ',' |
                    Should -BeExactly 'Eligible:azure-002,Active:azure-act-002'
            }
        }

        Context 'with a scope that arrives from the pipeline' {
            It 'looks the Name up at that scope' {
                $Result = @('/subscriptions/sub-001/resourceGroups/rg-two' | Get-OPIMAzureRole -Identity 'azure-002')
                $Result | Should -HaveCount 1
                $Result[0].Name | Should -BeExactly 'azure-002'
            }

            It 'returns nothing for a Name at another scope' {
                $Result = @('/subscriptions/sub-001/resourceGroups/rg-two' | Get-OPIMAzureRole -Identity 'azure-001')
                $Result | Should -HaveCount 0
            }
        }
    }

    Context 'When -Scope ends in a slash' {
        # Only the root scope is written '/'; any other trailing slash is refused when the parameter
        # binds, like the -Scope of Enable and Disable, so nothing runs: no sign-in and no ARM call.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal { $null }
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {}
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance {}
        }

        It 'refuses the scope before anything runs (<Name>)' -ForEach @(
            @{ Name = 'eligible'; Parameters = @{} }
            @{ Name = '-Activated'; Parameters = @{ Activated = $true } }
            @{ Name = '-All'; Parameters = @{ All = $true } }
            @{ Name = '-Identity'; Parameters = @{ Identity = 'azure-001' } }
        ) {
            { Get-OPIMAzureRole @Parameters -Scope '/subscriptions/sub-001/' } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*' -ExpectedMessage '*ends with*'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 0 -Scope It
        }

        It 'refuses a piped scope before anything runs' {
            $Output = @('/subscriptions/sub-001/' | Get-OPIMAzureRole -Identity 'azure-001' -ErrorAction Continue 2>&1)
            $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written | Should -HaveCount 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationError*'
            @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 0 -Scope It
        }

        It 'binds the root scope ''/''' {
            { Get-OPIMAzureRole -Scope '/' -ErrorAction Stop } | Should -Not -Throw
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 1 -Exactly -Scope It
        }

        It 'binds a scope without a trailing slash' {
            { Get-OPIMAzureRole -Scope '/subscriptions/sub-001' -ErrorAction Stop } | Should -Not -Throw
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $Scope -eq '/subscriptions/sub-001'
            }
        }
    }

    Context 'When -RoleName is specified' {
        # A name resolves through Resolve-OPIMSchedule, as on Enable and Disable. The resolver lists by
        # calling this cmdlet without a name, so the Az.Resources mocks below answer the nested listing
        # and the whole path runs for real. The fakes are built inside the mocks, so each call gets
        # fresh objects that no earlier call has decorated.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal { $null }
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {
                [PSCustomObject]@{
                    Name = 'azure-001'; RoleDefinitionDisplayName = 'Reader'
                    ScopeId = '/subscriptions/sub-001/resourceGroups/rg-one'; ScopeDisplayName = 'rg-one'; PrincipalId = 'principal-001'
                }
                [PSCustomObject]@{
                    Name = 'azure-002'; RoleDefinitionDisplayName = 'Reader'
                    ScopeId = '/subscriptions/sub-001/resourceGroups/rg-two'; ScopeDisplayName = 'rg-two'; PrincipalId = 'principal-001'
                }
                [PSCustomObject]@{
                    Name = 'azure-003'; RoleDefinitionDisplayName = 'Contributor'
                    ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'Subscription One'; PrincipalId = 'principal-001'
                }
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance {
                [PSCustomObject]@{
                    Name = 'azure-act-003'; AssignmentType = 'Activated'; RoleDefinitionDisplayName = 'Contributor'
                    ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'Subscription One'; PrincipalId = 'principal-001'
                }
            }
        }

        Context 'a display name that names one role' {
            It 'returns the post in each state it is in' {
                $Result = @(Get-OPIMAzureRole -RoleName 'Contributor')
                $Result | Should -HaveCount 2
                ($Result | Sort-Object Status | ForEach-Object { "$($_.Status):$($_.Name)" }) -join ',' |
                    Should -BeExactly 'Active:azure-act-003,Eligible:azure-003'
                foreach ($Post in $Result) {
                    $Post.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureCombinedSchedule'
                }
            }

            It 'takes the name as the first positional argument and ignores its case' {
                $Result = @(Get-OPIMAzureRole 'contributor')
                $Result | Should -HaveCount 2
            }

            It 'reads the listing at the root scope with the asTarget() filter and passes no Name' {
                $null = Get-OPIMAzureRole -RoleName 'Contributor'
                Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Scope -eq '/' -and $Filter -eq 'asTarget()' -and -not $Name
                }
                Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Scope -eq '/' -and $Filter -eq 'asTarget()' -and -not $Name
                }
            }
        }

        Context 'with -Activated' {
            It 'returns only the active instance' {
                $Result = @(Get-OPIMAzureRole -Activated -RoleName 'Contributor')
                $Result | Should -HaveCount 1
                $Result[0].Name | Should -BeExactly 'azure-act-003'
                $Result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleInstance'
            }

            It 'does not read the eligible list when the active instance is found' {
                $null = Get-OPIMAzureRole -Activated -RoleName 'Contributor'
                Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 0 -Scope It
            }

            It 'keeps the instance when -Scope names its scope' {
                $Result = @(Get-OPIMAzureRole -Activated -RoleName 'Contributor' -Scope '/subscriptions/sub-001')
                $Result | Should -HaveCount 1
                $Result[0].Name | Should -BeExactly 'azure-act-003'
            }

            It 'writes ActiveRoleNotFound for a role that is not active' {
                $Output = @(Get-OPIMAzureRole -Activated -RoleName 'Reader' -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].FullyQualifiedErrorId | Should -BeExactly 'ActiveRoleNotFound,Get-OPIMAzureRole'
                @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            }
        }

        Context 'a display name that two scopes carry' {
            It 'writes AmbiguousName with the candidates and offers -Scope' {
                $Output = @(Get-OPIMAzureRole -RoleName 'Reader' -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].FullyQualifiedErrorId | Should -BeExactly 'AmbiguousName,Get-OPIMAzureRole'
                $Written[0].Exception.Message | Should -Match 'azure-001'
                $Written[0].Exception.Message | Should -Match 'azure-002'
                $Written[0].Exception.Message | Should -Match 'add -Scope'
                @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            }

            It 'returns only the post at the scope that -Scope names' {
                $Result = @(Get-OPIMAzureRole -RoleName 'Reader' -Scope '/subscriptions/sub-001/resourceGroups/rg-one')
                $Result | Should -HaveCount 1
                $Result[0].Name | Should -BeExactly 'azure-001'
                $Result[0].Status | Should -BeExactly 'Eligible'
            }

            It 'reads -Scope ''/'' as every scope, like the default, and so stays ambiguous' {
                $Output = @(Get-OPIMAzureRole -RoleName 'Reader' -Scope '/' -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].FullyQualifiedErrorId | Should -BeExactly 'AmbiguousName,Get-OPIMAzureRole'
                @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            }

            It 'stays ambiguous when -Scope is left out' {
                $Output = @(Get-OPIMAzureRole -RoleName 'Reader' -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].FullyQualifiedErrorId | Should -BeExactly 'AmbiguousName,Get-OPIMAzureRole'
            }

            It 'writes EligibleRoleNotFound when -Scope names a scope the role is not at' {
                $Output = @(Get-OPIMAzureRole -RoleName 'Reader' -Scope '/subscriptions/sub-001' -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].FullyQualifiedErrorId | Should -BeExactly 'EligibleRoleNotFound,Get-OPIMAzureRole'
                @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            }

            It 'refuses a -Scope that ends in a slash when it binds, before anything is listed' {
                { Get-OPIMAzureRole -RoleName 'Reader' -Scope '/subscriptions/sub-001/resourceGroups/rg-one/' } |
                    Should -Throw -ErrorId 'ParameterArgumentValidationError*' -ExpectedMessage '*ends with*'
                Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 0 -Scope It
                Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 0 -Scope It
            }
        }

        Context 'a name that no role carries' {
            It 'writes EligibleRoleNotFound and returns nothing' {
                $Output = @(Get-OPIMAzureRole -RoleName 'No Such Role' -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].FullyQualifiedErrorId | Should -BeExactly 'EligibleRoleNotFound,Get-OPIMAzureRole'
                @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            }

            It 'writes it as a non-terminating error' {
                { Get-OPIMAzureRole -RoleName 'No Such Role' -ErrorAction SilentlyContinue } | Should -Not -Throw
            }
        }

        Context 'the old tab-completed form' {
            It 'returns the post whose Name ends the string' {
                $Result = @(Get-OPIMAzureRole -RoleName 'Reader -> rg-two (azure-002)')
                $Result | Should -HaveCount 1
                $Result[0].Name | Should -BeExactly 'azure-002'
                $Result[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureCombinedSchedule'
            }

            It 'finds nothing when -Scope excludes the post the Name names' {
                $Output = @(Get-OPIMAzureRole -RoleName 'Reader -> rg-two (azure-002)' -Scope '/subscriptions/sub-001/resourceGroups/rg-one' -ErrorAction Continue 2>&1)
                $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
                $Written | Should -HaveCount 1
                $Written[0].FullyQualifiedErrorId | Should -BeExactly 'EligibleRoleNotFound,Get-OPIMAzureRole'
                @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            }
        }

        Context 'a scope that arrives from the pipeline' {
            It 'resolves the name at that scope' {
                $Result = @('/subscriptions/sub-001/resourceGroups/rg-two' | Get-OPIMAzureRole -RoleName 'Reader')
                $Result | Should -HaveCount 1
                $Result[0].Name | Should -BeExactly 'azure-002'
            }
        }
    }

    Context 'When -RoleName is specified and the listing fails' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal { $null }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance { }
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {
                Write-Error -Message 'Service unavailable' `
                    -ErrorId 'ServiceUnavailable' `
                    -Category ResourceUnavailable `
                    -ErrorAction Stop
            }
        }

        It 'writes the listing''s own error and never EligibleRoleNotFound' {
            $Output = @(Get-OPIMAzureRole -RoleName 'Contributor' -ErrorAction Continue 2>&1)
            $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written | Should -HaveCount 1
            $Written[0].FullyQualifiedErrorId | Should -BeExactly 'ServiceUnavailable,Get-OPIMAzureRole'
            @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
        }

        It 'writes the listing''s own error under -ErrorAction SilentlyContinue too' {
            $Errs = $null
            $Output = @(Get-OPIMAzureRole -RoleName 'Contributor' -ErrorVariable Errs -ErrorAction SilentlyContinue)
            $Output | Should -HaveCount 0
            # -ErrorVariable collects every nested frame's copy as well; the cmdlet's own record is the last.
            $Errs[-1].FullyQualifiedErrorId | Should -BeExactly 'ServiceUnavailable,Get-OPIMAzureRole'
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'EligibleRoleNotFound*' }) | Should -HaveCount 0
        }
    }

    Context 'When -RoleName is specified and the resolver is mocked' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal { $null }
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {}
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance {}
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule {
                [PSCustomObject]@{ Name = 'resolved-001'; Status = 'Eligible' }
            }
        }

        It 'hands the resolver the Azure pillar, both states and the name, offers -Scope and gives no scope' {
            $Result = @(Get-OPIMAzureRole -RoleName 'Contributor')
            $Result | Should -HaveCount 1
            $Result[0].Name | Should -BeExactly 'resolved-001'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $Pillar -eq 'Azure' -and $Status -eq 'Both' -and $Name -ceq 'Contributor' -and
                @($FilterParameter) -ceq 'Scope' -and -not $Scope
            }
        }

        It 'gives the resolver no scope for -Scope ''/'', which has always meant every scope' {
            $null = Get-OPIMAzureRole -RoleName 'Contributor' -Scope '/'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                -not $Scope
            }
        }

        It 'hands the resolver the scope it was given, as given' {
            $null = Get-OPIMAzureRole -RoleName 'Contributor' -Scope '/subscriptions/sub-001'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $Scope -ceq '/subscriptions/sub-001'
            }
        }

        It 'hands the resolver the scope that arrives from the pipeline' {
            $null = '/subscriptions/sub-002' | Get-OPIMAzureRole -RoleName 'Contributor'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $Scope -ceq '/subscriptions/sub-002'
            }
        }

        It 'hands the resolver both states with -All' {
            $null = Get-OPIMAzureRole -All -RoleName 'Contributor'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $Status -eq 'Both'
            }
        }

        It 'hands the resolver the active state with -Activated' {
            $null = Get-OPIMAzureRole -Activated -RoleName 'Contributor'
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It -ParameterFilter {
                $Pillar -eq 'Azure' -and $Status -eq 'Active'
            }
        }

        It 'lists nothing itself, since the resolver lists' {
            $null = Get-OPIMAzureRole -RoleName 'Contributor'
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 0 -Scope It
        }

        It 'does not call the resolver without a name' {
            $null = Get-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 0 -Scope It
        }
    }

    Context 'When the resolver writes an error instead of throwing' {
        # The cmdlet calls the resolver with -ErrorAction Stop, so an error the resolver only writes
        # ends that name inside the cmdlet's own try and is written as the cmdlet's own error. The
        # mock takes its preference from an explicit -ErrorAction and is Continue otherwise, as the
        # resolver is under the default preference.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Resolve-OPIMSchedule {
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
        }

        It 'writes the error as its own, once' {
            $Out = Get-OPIMAzureRole -RoleName 'Contributor' -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            @($Written | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Get-OPIMAzureRole' }).Count | Should -Be 1
            Should -Invoke -ModuleName Omnicit.PIM Resolve-OPIMSchedule -Times 1 -Exactly -Scope It
        }
    }

    Context 'When -All and -Activated are both specified' {
        It 'throws a parameter binding error because they are mutually exclusive' {
            { Get-OPIMAzureRole -All -Activated } | Should -Throw
        }
    }

    Context 'When -Activated -Scope filters to a specific scope' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $FakeActiveOnScope = [PSCustomObject]@{
                Name           = 'active-sub-001'
                AssignmentType = 'Activated'
                ScopeId        = '/subscriptions/sub-001'
            }
            $FakeActiveOnParent = [PSCustomObject]@{
                Name           = 'active-parent-001'
                AssignmentType = 'Activated'
                ScopeId        = '/'
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance {
                return @($FakeActiveOnScope, $FakeActiveOnParent)
            } -ParameterFilter { $Filter -eq 'asTarget()' }
        }

        It 'returns only instances matching the exact scope' {
            $Result = Get-OPIMAzureRole -Activated -Scope '/subscriptions/sub-001'
            $Result | Should -HaveCount 1
            $Result[0].ScopeId | Should -Be '/subscriptions/sub-001'
        }
    }

    Context 'When -Scope is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule { return @() }
        }

        It 'passes the scope to Get-AzRoleEligibilitySchedule' {
            Get-OPIMAzureRole -Scope '/subscriptions/sub-001'
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 1 -Scope It -ParameterFilter {
                $Scope -eq '/subscriptions/sub-001'
            }
        }
    }

    Context 'When the result set is empty' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule { return @() }
        }

        It 'returns nothing without throwing' {
            { Get-OPIMAzureRole } | Should -Not -Throw
        }

        It 'returns no objects' {
            $Result = Get-OPIMAzureRole
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'When the API returns an InsufficientPermissions error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {
                Write-Error -Message 'Insufficient permissions' `
                    -ErrorId 'InsufficientPermissions' `
                    -Category PermissionDenied `
                    -ErrorAction Stop
            }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Get-OPIMAzureRole -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'includes guidance to use -All in the error message' {
            $Errors = @()
            Get-OPIMAzureRole -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[-1].ErrorDetails.Message | Should -Match '\-All'
        }
    }

    Context 'When -All is specified and the API returns an InsufficientPermissions error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient permissions'),
                        'InsufficientPermissions',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied,
                        $null
                    )
                )
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance { return @() }
            Mock -ModuleName Omnicit.PIM Write-CmdletError { } -Verifiable
        }

        It 'writes a non-terminating error with Owner or UserAccessAdministrator guidance' {
            $Errors = @()
            Get-OPIMAzureRole -All -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When the InsufficientPermissions rewrap is written' {
        # OPIM-11: the rewrapped record keeps no reference to the raw Az record, which can carry the
        # request it failed on -- no inner exception, and the scope as its target object. Each read
        # throws a record whose target object is a request message, as a failed ARM call's can be.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $RawFailure = {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient permissions'),
                        'InsufficientPermissions',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied,
                        [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, 'https://management.azure.com/providers/Microsoft.Authorization/roleEligibilitySchedules')))
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule $RawFailure
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance $RawFailure
        }

        It 'writes the rewrap for the <Name> read with the scope as its target and no inner exception' -ForEach @(
            @{ Name = 'eligible'; Activated = $false }
            @{ Name = 'activated'; Activated = $true }
        ) {
            $Errs = $null
            Get-OPIMAzureRole -Scope '/subscriptions/sub-001' -Activated:$Activated -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Rewrap = @($Errs | Where-Object { $_.Exception.Message -like 'Insufficient permissions to list roles at scope*' })
            $Rewrap.Count | Should -Be 1
            $Rewrap[0].FullyQualifiedErrorId.Split(',')[0] | Should -BeExactly 'InsufficientPermissions'
            $Rewrap[0].Exception.InnerException | Should -BeNullOrEmpty
            $Rewrap[0].TargetObject | Should -Not -BeOfType ([System.Management.Automation.ErrorRecord])
            $Rewrap[0].TargetObject | Should -BeOfType ([string])
            $Rewrap[0].TargetObject | Should -BeExactly '/subscriptions/sub-001'
        }

        It 'writes both -All rewraps with the root scope as their target and no inner exception' {
            $Errs = $null
            Get-OPIMAzureRole -All -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Rewrap = @($Errs | Where-Object { $_.Exception.Message -like 'You do not have sufficient rights to view*' })
            $Rewrap.Count | Should -Be 2
            foreach ($Record in $Rewrap) {
                $Record.FullyQualifiedErrorId.Split(',')[0] | Should -BeExactly 'InsufficientPermissions'
                $Record.Exception.InnerException | Should -BeNullOrEmpty
                $Record.TargetObject | Should -Not -BeOfType ([System.Management.Automation.ErrorRecord])
                $Record.TargetObject | Should -BeOfType ([string])
                $Record.TargetObject | Should -BeExactly '/'
            }
        }
    }

    Context 'When the API returns a non-permissions error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {
                Write-Error -Message 'Service unavailable' `
                    -ErrorId 'ServiceUnavailable' `
                    -Category ResourceUnavailable `
                    -ErrorAction Stop
            }
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Get-OPIMAzureRole -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When scope is provided via pipeline' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule { return @() }
        }

        It 'calls Get-AzRoleEligibilitySchedule once per piped scope' {
            '/subscriptions/sub-001', '/subscriptions/sub-002' | Get-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 2 -Scope It
        }
    }

    Context 'When the ARM gate refuses' {
        # SEC (EntraRBAC A19): the gate stands inside the try that holds each Az.Resources call,
        # directly before it, so the cmdlet's own catch reports the refusal as itself.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal {
                [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('refused'), 'SignInRefused', 'AuthenticationError', 'x')
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {}
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance {}
        }

        It 'sends no ARM request (<Name>)' -ForEach @(
            @{ Name = 'eligible'; Parameters = @{} }
            @{ Name = '-Activated'; Parameters = @{ Activated = $true } }
            @{ Name = '-All'; Parameters = @{ All = $true } }
            @{ Name = '-Identity'; Parameters = @{ Identity = 'azure-001' } }
        ) {
            Get-OPIMAzureRole @Parameters -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 0 -Scope It
        }

        It 'writes the refusal as itself (<Name>)' -ForEach @(
            @{ Name = 'eligible'; Parameters = @{}; Expected = 1 }
            @{ Name = '-Activated'; Parameters = @{ Activated = $true }; Expected = 1 }
            @{ Name = '-All'; Parameters = @{ All = $true }; Expected = 2 }
            @{ Name = '-Identity'; Parameters = @{ Identity = 'azure-001' }; Expected = 2 }
        ) {
            $Errs = @()
            Get-OPIMAzureRole @Parameters -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs[0].FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
            # One written record per try that holds an Az.Resources call (-All has two), each the
            # refusal itself and not the InsufficientPermissions rewrap.
            @($Errs | Where-Object FullyQualifiedErrorId -EQ 'SignInRefused,Get-OPIMAzureRole').Count | Should -Be $Expected
            @($Errs | Where-Object FullyQualifiedErrorId -Like 'InsufficientPermissions*').Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMArmRefusal -Times $Expected -Exactly -Scope It
        }
    }

    Context 'When Azure is signed in to another tenant than the Graph session' {
        # Acceptance (OPIM-08): the real ARM gate, an auth state a Graph sign-in for one tenant wrote,
        # and an Az context for another tenant: TenantMismatch before any ARM call.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Get-AzContext {
                [PSCustomObject]@{ Tenant = [PSCustomObject]@{ Id = 'bbbbbbbb-0000-0000-0000-00000000000b' } }
            }
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {}
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance {}
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

        It 'sends no ARM request and writes TenantMismatch (<Name>)' -ForEach @(
            @{ Name = 'eligible'; Parameters = @{} }
            @{ Name = '-Activated'; Parameters = @{ Activated = $true } }
        ) {
            $Errs = @()
            Get-OPIMAzureRole @Parameters -ErrorVariable Errs -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 0 -Scope It
            @($Errs | Where-Object FullyQualifiedErrorId -Like 'TenantMismatch*').Count | Should -BeGreaterThan 0
        }
    }
}
