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
    # The cmdlet reads through the module's own ARM transport, Invoke-OPIMArmRequest, which every
    # context mocks at the module boundary: the mock answers the path of the list it is asked for
    # with a response shaped like ARM's, { value = [...] }, and the converter that turns an ARM item
    # into the module's object runs for real. The ARM items are the Microsoft Learn api-version
    # 2020-10-01 examples of tests/Unit/TestHelpers/ArmResponse, redacted to digit-repeat ids, with the
    # names, roles and scopes a context needs set on a fresh copy.
    BeforeAll {
        $FixtureDirectory = "$PSScriptRoot/../TestHelpers/ArmResponse"
        $script:EligJson = Get-Content -Raw -LiteralPath "$FixtureDirectory/roleEligibilitySchedules.json"
        $script:InstJson = Get-Content -Raw -LiteralPath "$FixtureDirectory/roleAssignmentScheduleInstances.json"

        # One ARM item, from item 1 of the fixture of its kind. ScopeId lives at
        # properties.expandedProperties.scope.id, as it does in ARM's answer.
        function New-ArmItem {
            param(
                [Parameter(Mandatory)][ValidateSet('Eligibility', 'Instance')][string]$Kind,
                [Parameter(Mandatory)][string]$Name,
                [string]$Role = 'Reader',
                [string]$ScopeId = '/subscriptions/sub-001',
                [string]$ScopeName = 'Subscription One',
                [string]$AssignmentType = 'Activated'
            )
            $Json = if ($Kind -eq 'Eligibility') { $script:EligJson } else { $script:InstJson }
            $Item = ($Json | ConvertFrom-Json).value[0]
            $Item.name = $Name
            $Item.properties.scope = $ScopeId
            $Item.properties.expandedProperties.scope.id = $ScopeId
            $Item.properties.expandedProperties.scope.displayName = $ScopeName
            $Item.properties.expandedProperties.roleDefinition.displayName = $Role
            if ($Kind -eq 'Instance') { $Item.properties.assignmentType = $AssignmentType }
            $Item
        }

        function New-ArmResponse {
            param($Item)
            [pscustomobject]@{ value = @($Item) }
        }

        # The safety net: a path that no context answers fails the call instead of reaching the
        # real transport.
        Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { throw "No mock answers the ARM path $Path" }
    }

    Context 'When called with default parameters (eligible roles)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $EligResponse = New-ArmResponse (New-ArmItem Eligibility -Name 'elig-001' -Role 'Contributor' -ScopeName 'My Subscription')
            $InstResponse = New-ArmResponse @()
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EligResponse } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $InstResponse } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
        }

        It 'reads the eligibility schedules through the transport with the asTarget() filter' {
            $null = Get-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -like '*/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01'
            }
        }

        It 'reads the eligible list at the root without a double slash, across every page' {
            $null = Get-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq '/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01' -and $All.IsPresent
            }
        }

        It 'reads nothing else' {
            $null = Get-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
        }

        It 'returns objects tagged with Omnicit.PIM.AzureEligibilitySchedule' {
            $Result = Get-OPIMAzureRole
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureEligibilitySchedule'
        }

        It 'returns the post ARM listed' {
            $Result = @(Get-OPIMAzureRole)
            $Result | Should -HaveCount 1
            $Result[0].Name | Should -BeExactly 'elig-001'
            $Result[0].RoleDefinitionDisplayName | Should -BeExactly 'Contributor'
            $Result[0].ScopeDisplayName | Should -BeExactly 'My Subscription'
        }
    }

    Context 'When -Activated is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $EligResponse = New-ArmResponse @()
            $InstResponse = New-ArmResponse (New-ArmItem Instance -Name 'active-001' -Role 'Contributor' -ScopeName 'My Subscription')
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EligResponse } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $InstResponse } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
        }

        It 'reads the role assignment schedule instances through the transport with the asTarget() filter' {
            $null = Get-OPIMAzureRole -Activated
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq '/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?$filter=asTarget()&api-version=2020-10-01' -and $All.IsPresent
            }
        }

        It 'does not read the eligibility schedules' {
            $null = Get-OPIMAzureRole -Activated
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
        }

        It 'returns objects tagged with Omnicit.PIM.AzureAssignmentScheduleInstance' {
            $Result = Get-OPIMAzureRole -Activated
            $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.AzureAssignmentScheduleInstance'
        }
    }

    Context 'When -Activated returns mixed assignment types' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $InstResponse = [pscustomobject]@{
                value = @(
                    (New-ArmItem Instance -Name 'inherited-001' -AssignmentType 'Assigned')
                    (New-ArmItem Instance -Name 'active-001' -AssignmentType 'Activated')
                )
            }
            $InstFixture = $script:InstJson | ConvertFrom-Json
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $InstResponse } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
        }

        It 'filters out non-Activated assignment types and returns only Activated entries' {
            $Result = Get-OPIMAzureRole -Activated
            $Result | Should -HaveCount 1
            $Result[0].AssignmentType | Should -Be 'Activated'
        }

        It 'keeps only the Activated instance of the fixture and drops the Assigned one' {
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $InstFixture } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
            $Result = @(Get-OPIMAzureRole -Activated)
            $Result | Should -HaveCount 1
            $Result[0].Name | Should -BeExactly '55555555-5555-5555-5555-555555555557'
            $Result[0].AssignmentType | Should -BeExactly 'Activated'
        }
    }

    Context 'When -Activated reads the listing recorded live' {
        # The answer ARM gave to the roleAssignmentScheduleInstances listing in the live run of
        # docs/live-verification/feat-arm-transport-checklist.md, redacted: an Activated row, and the
        # Assigned row ARM lists for a few minutes after an activation is revoked.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $RecordedDirectory = "$PSScriptRoot/../TestHelpers/ArmResponse"
            $RecordedListing = Get-Content -Raw -LiteralPath "$RecordedDirectory/recorded-roleAssignmentScheduleInstances.json" | ConvertFrom-Json
            $RecordedResponse = [pscustomobject]@{ value = $RecordedListing.value }
            $RecordedActivated = @($RecordedListing.value | Where-Object { $_.properties.assignmentType -ceq 'Activated' })
            $RecordedAssigned = @($RecordedListing.value | Where-Object { $_.properties.assignmentType -ceq 'Assigned' })
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $RecordedResponse } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
        }

        It 'keeps only the Activated instance of the recorded listing' {
            @($RecordedListing.value) | Should -HaveCount 2 -Because 'the recorded listing must carry both rows for the filter to have something to drop'
            $RecordedActivated | Should -HaveCount 1
            $RecordedAssigned | Should -HaveCount 1

            $Result = @(Get-OPIMAzureRole -Activated)

            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq '/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?$filter=asTarget()&api-version=2020-10-01'
            }
            $Result | Should -HaveCount 1
            $Result[0].Name | Should -BeExactly $RecordedActivated[0].name
            $Result[0].Id | Should -BeExactly $RecordedActivated[0].id
            $Result[0].AssignmentType | Should -BeExactly 'Activated'
            $Result[0].PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.PIM.AzureAssignmentScheduleInstance'
            @($Result | Where-Object Name -EQ $RecordedAssigned[0].name) | Should -HaveCount 0
        }
    }

    Context 'When -All is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $EligResponse = New-ArmResponse @()
            $InstResponse = New-ArmResponse @()
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EligResponse } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $InstResponse } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
        }

        It 'reads the eligibility schedules at the root with the asTarget() filter, across every page' {
            $null = Get-OPIMAzureRole -All
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq '/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01' -and $All.IsPresent
            }
        }

        It 'reads the role assignment schedule instances at the root with the asTarget() filter, across every page' {
            $null = Get-OPIMAzureRole -All
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq '/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?$filter=asTarget()&api-version=2020-10-01' -and $All.IsPresent
            }
        }
    }

    Context 'When -All returns both eligible and active results' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $EligResponse = New-ArmResponse (New-ArmItem Eligibility -Name 'elig-001' -Role 'Contributor' -ScopeName 'My Subscription')
            $InstResponse = New-ArmResponse (New-ArmItem Instance -Name 'active-001' -Role 'Contributor' -ScopeName 'My Subscription')
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EligResponse } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $InstResponse } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
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

        It 'tags each row with the type of its state as well' {
            $Result = @(Get-OPIMAzureRole -All)
            $Result[0].PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.PIM.AzureCombinedSchedule'
            $Result[0].PSObject.TypeNames[1] | Should -BeExactly 'Omnicit.PIM.AzureEligibilitySchedule'
            $Result[1].PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.PIM.AzureCombinedSchedule'
            $Result[1].PSObject.TypeNames[1] | Should -BeExactly 'Omnicit.PIM.AzureAssignmentScheduleInstance'
        }
    }

    Context 'When the rows are returned' {
        # The A4 contract: the objects carry exactly the properties and the value types the
        # Az.Resources objects had, so a row is what the converter makes of the same ARM item.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $EligFixture = $script:EligJson | ConvertFrom-Json
            $InstFixture = $script:InstJson | ConvertFrom-Json
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EligFixture } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $InstFixture } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }

            function Assert-SameProperty {
                param($Actual, $Expected, [string[]]$Except = @())
                ($Actual.PSObject.Properties.Name | Sort-Object) -join ',' | Should -BeExactly (($Expected.PSObject.Properties.Name | Sort-Object) -join ',')
                foreach ($Name in $Expected.PSObject.Properties.Name | Where-Object { $_ -notin $Except }) {
                    if ($null -eq $Expected.$Name) {
                        $null -eq $Actual.$Name | Should -BeTrue -Because "$Name is null in ARM's item"
                    } else {
                        $Actual.$Name | Should -BeExactly $Expected.$Name -Because "$Name is the converter's"
                    }
                }
            }
        }

        It 'returns the A4 properties of an eligible row, property by property' {
            $Expected = InModuleScope Omnicit.PIM -Parameters @{ Item = $EligFixture.value[0] } {
                param($Item)
                ConvertFrom-OPIMArmSchedule -InputObject $Item -Kind EligibilitySchedule
            }
            $Result = @(Get-OPIMAzureRole)
            $Result | Should -HaveCount 2
            Assert-SameProperty -Actual $Result[0] -Expected $Expected
            $Result[0].EndDateTime.Kind | Should -Be 'Utc'
            $Result[0].Status | Should -BeExactly 'Provisioned'
            $Result[0].ResourceGroupName | Should -BeExactly 'opim-fixture-rg'
        }

        It 'returns the A4 properties of an active row, property by property' {
            $Expected = InModuleScope Omnicit.PIM -Parameters @{ Item = $InstFixture.value[0] } {
                param($Item)
                ConvertFrom-OPIMArmSchedule -InputObject $Item -Kind AssignmentScheduleInstance
            }
            $Result = @(Get-OPIMAzureRole -Activated)
            $Result | Should -HaveCount 1
            Assert-SameProperty -Actual $Result[0] -Expected $Expected
            $Result[0].EndDateTime.Kind | Should -Be 'Utc'
            $Result[0].AssignmentType | Should -BeExactly 'Activated'
        }

        It 'returns the A4 properties of the -All rows, with Status as the state' {
            $EligExpected = InModuleScope Omnicit.PIM -Parameters @{ Item = $EligFixture.value[1] } {
                param($Item)
                ConvertFrom-OPIMArmSchedule -InputObject $Item -Kind EligibilitySchedule
            }
            $InstExpected = InModuleScope Omnicit.PIM -Parameters @{ Item = $InstFixture.value[0] } {
                param($Item)
                ConvertFrom-OPIMArmSchedule -InputObject $Item -Kind AssignmentScheduleInstance
            }
            $Result = @(Get-OPIMAzureRole -All)
            $Result | Should -HaveCount 3
            Assert-SameProperty -Actual ($Result | Where-Object Status -EQ 'Active') -Expected $InstExpected -Except Status
            $Eligible = @($Result | Where-Object Status -EQ 'Eligible')
            $Eligible | Should -HaveCount 2
            Assert-SameProperty -Actual ($Eligible | Where-Object Name -EQ $EligExpected.Name) -Expected $EligExpected -Except Status
        }

        It 'drops the Assigned instance with -All' {
            # The fixture lists two instances: one Activated (...557) and one Assigned (...558), a
            # permanent assignment the user cannot self-deactivate.
            @($InstFixture.value | Where-Object { $_.properties.assignmentType -eq 'Assigned' }).name |
                Should -BeExactly '55555555-5555-5555-5555-555555555558' -Because 'the fixture must carry the Assigned instance the cmdlet drops'
            $Active = @(Get-OPIMAzureRole -All | Where-Object Status -EQ 'Active')
            $Active | Should -HaveCount 1
            $Active[0].Name | Should -BeExactly '55555555-5555-5555-5555-555555555557'
            $Active[0].AssignmentType | Should -BeExactly 'Activated'
        }
    }

    Context 'When -Identity is specified' {
        # OPIM-23: a normal user is refused a GET of one schedule by Name at the root scope
        # (InsufficientPermissions), while the asTarget() listing is allowed. A Name is therefore found
        # among the posts that listing returns and is never put in an ARM path. The mocks answer
        # a listing with every post whatever it is asked for, so a call that sent the Name would still
        # get them all: what separates the post is the cmdlet's own filter, and the path of each call
        # is asserted on its own. The converter makes a new object of every item it reads, so each call
        # gets objects that no earlier call has decorated.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $EligResponse = [pscustomobject]@{
                value = @(
                    (New-ArmItem Eligibility -Name 'azure-001' -Role 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one')
                    (New-ArmItem Eligibility -Name 'azure-002' -Role 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-two' -ScopeName 'rg-two')
                    (New-ArmItem Eligibility -Name 'azure-003' -Role 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'Subscription One')
                )
            }
            $InstResponse = [pscustomobject]@{
                value = @(
                    (New-ArmItem Instance -Name 'azure-act-001' -Role 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one')
                    (New-ArmItem Instance -Name 'azure-act-002' -Role 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-two' -ScopeName 'rg-two')
                    (New-ArmItem Instance -Name 'azure-act-003' -Role 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'Subscription One')
                )
            }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EligResponse } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $InstResponse } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
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
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Path -ceq '/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01' -and $All.IsPresent
                }
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Path -ceq '/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?$filter=asTarget()&api-version=2020-10-01' -and $All.IsPresent
                }
            }

            It 'hands no Name to the transport' {
                $null = Get-OPIMAzureRole -Identity 'azure-002'
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It -ParameterFilter { $Path -like '*azure-002*' }
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It -ParameterFilter { $PesterBoundParameters.ContainsKey('Body') }
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
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Path -ceq '/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?$filter=asTarget()&api-version=2020-10-01' -and $All.IsPresent
                }
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It -ParameterFilter { $Path -like '*azure-act-002*' }
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
            }

            It 'lists the active posts at the scope that -Scope names, and keeps the instance there' {
                $Result = @(Get-OPIMAzureRole -Activated -Identity 'azure-act-002' -Scope '/subscriptions/sub-001/resourceGroups/rg-two')
                $Result | Should -HaveCount 1
                $Result[0].Name | Should -BeExactly 'azure-act-002'
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Path -ceq '/subscriptions/sub-001/resourceGroups/rg-two/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?$filter=asTarget()&api-version=2020-10-01'
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
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Path -ceq '/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01'
                }
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Path -ceq '/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?$filter=asTarget()&api-version=2020-10-01'
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

            It 'reads the -All listing at the root as well, whatever scope -Scope names' {
                $null = Get-OPIMAzureRole -All -Scope '/subscriptions/sub-001/resourceGroups/rg-two'
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Path -ceq '/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01'
                }
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Path -ceq '/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?$filter=asTarget()&api-version=2020-10-01'
                }
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
            $EmptyResponse = New-ArmResponse @()
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EmptyResponse } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EmptyResponse } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
        }

        It 'refuses a piped scope before anything runs' {
            $Output = @('/subscriptions/sub-001/' | Get-OPIMAzureRole -Identity 'azure-001' -ErrorAction Continue 2>&1)
            $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written | Should -HaveCount 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationError*'
            @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
        }

        It 'binds the root scope ''/''' {
            { Get-OPIMAzureRole -Scope '/' -ErrorAction Stop } | Should -Not -Throw
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -like '*/roleEligibilitySchedules?*'
            }
        }

        It 'binds a scope without a trailing slash' {
            { Get-OPIMAzureRole -Scope '/subscriptions/sub-001' -ErrorAction Stop } | Should -Not -Throw
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq '/subscriptions/sub-001/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01'
            }
        }
    }

    Context 'When -Scope is typed without its leading slash' {
        # The ARM path prefix of a scope is the scope with exactly one leading slash, so a scope typed
        # without it is read at that scope, and its path stays on the ARM host instead of extending
        # the host name. Only the request path changes.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $EmptyResponse = New-ArmResponse @()
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EmptyResponse } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EmptyResponse } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
        }

        It 'reads the <List> at that scope (<Name>)' -ForEach @(
            @{ Name = 'eligible'; Parameters = @{}; List = 'roleEligibilitySchedules' }
            @{ Name = '-Activated'; Parameters = @{ Activated = $true }; List = 'roleAssignmentScheduleInstances' }
        ) {
            $null = Get-OPIMAzureRole @Parameters -Scope 'subscriptions/22222222-2222-2222-2222-222222222222' -ErrorAction Stop
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $All.IsPresent -and
                $Path -ceq ('/subscriptions/22222222-2222-2222-2222-222222222222/providers/Microsoft.Authorization/{0}?$filter=asTarget()&api-version=2020-10-01' -f $List)
            }
        }
    }

    Context 'When -RoleName is specified' {
        # A name resolves through Resolve-OPIMSchedule, as on Enable and Disable. The resolver lists by
        # calling this cmdlet without a name, so the transport mocks below answer the nested listing
        # and the whole path runs for real.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $EligResponse = [pscustomobject]@{
                value = @(
                    (New-ArmItem Eligibility -Name 'azure-001' -Role 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one')
                    (New-ArmItem Eligibility -Name 'azure-002' -Role 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-two' -ScopeName 'rg-two')
                    (New-ArmItem Eligibility -Name 'azure-003' -Role 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'Subscription One')
                )
            }
            $InstResponse = New-ArmResponse (New-ArmItem Instance -Name 'azure-act-003' -Role 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'Subscription One')
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EligResponse } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $InstResponse } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
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
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Path -ceq '/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01' -and $All.IsPresent
                }
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Path -ceq '/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?$filter=asTarget()&api-version=2020-10-01' -and $All.IsPresent
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
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
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
                Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
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
            $InstResponse = New-ArmResponse @()
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $InstResponse } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Service unavailable'),
                        'ServiceUnavailable',
                        [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                        $null
                    )
                )
            } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
        }

        It 'writes the listing''s own error and never EligibleRoleNotFound' {
            $Output = @(Get-OPIMAzureRole -RoleName 'Contributor' -ErrorAction Continue 2>&1)
            $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written | Should -HaveCount 1
            $Written[0].FullyQualifiedErrorId.Split(',')[0] | Should -BeExactly 'ServiceUnavailable'
            @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
        }

        It 'writes the listing''s own error under -ErrorAction SilentlyContinue too' {
            $Errs = $null
            $Output = @(Get-OPIMAzureRole -RoleName 'Contributor' -ErrorVariable Errs -ErrorAction SilentlyContinue)
            $Output | Should -HaveCount 0
            # -ErrorVariable collects every nested frame's copy as well; the cmdlet's own record is the last.
            $Errs[-1].FullyQualifiedErrorId.Split(',')[0] | Should -BeExactly 'ServiceUnavailable'
            @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'EligibleRoleNotFound*' }) | Should -HaveCount 0
        }
    }

    Context 'When -RoleName is specified and the resolver is mocked' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $EmptyResponse = New-ArmResponse @()
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EmptyResponse } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EmptyResponse } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
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
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 0 -Scope It
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
            $InstResponse = [pscustomobject]@{
                value = @(
                    (New-ArmItem Instance -Name 'active-sub-001' -ScopeId '/subscriptions/sub-001')
                    (New-ArmItem Instance -Name 'active-parent-001' -ScopeId '/')
                )
            }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $InstResponse } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
        }

        It 'returns only instances matching the exact scope' {
            $Result = Get-OPIMAzureRole -Activated -Scope '/subscriptions/sub-001'
            $Result | Should -HaveCount 1
            $Result[0].ScopeId | Should -Be '/subscriptions/sub-001'
        }

        It 'reads the instances at that scope' {
            $null = Get-OPIMAzureRole -Activated -Scope '/subscriptions/sub-001'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq '/subscriptions/sub-001/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?$filter=asTarget()&api-version=2020-10-01'
            }
        }
    }

    Context 'When -Scope is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $EmptyResponse = New-ArmResponse @()
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EmptyResponse } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
        }

        It 'reads the eligible list at that scope, which starts the path' {
            $null = Get-OPIMAzureRole -Scope '/subscriptions/sub-001'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq '/subscriptions/sub-001/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01' -and $All.IsPresent
            }
        }

        It 'reads a resource group scope as it is' {
            $null = Get-OPIMAzureRole -Scope '/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/opim-fixture-rg'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq '/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/opim-fixture-rg/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01'
            }
        }
    }

    Context 'When the result set is empty' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $EmptyResponse = New-ArmResponse @()
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EmptyResponse } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
        }

        It 'returns nothing without throwing' {
            { Get-OPIMAzureRole } | Should -Not -Throw
        }

        It 'returns no objects' {
            $Result = Get-OPIMAzureRole
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'When the response carries no value' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $NoValue = [pscustomobject]@{ value = $null }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $NoValue } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
        }

        It 'returns no objects, not an empty one' {
            $Result = @(Get-OPIMAzureRole)
            $Result | Should -HaveCount 0
        }
    }

    Context 'When the API returns an InsufficientPermissions error' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient permissions'),
                        'InsufficientPermissions',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied,
                        $null
                    )
                )
            } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
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
            $InstResponse = New-ArmResponse @()
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient permissions'),
                        'InsufficientPermissions',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied,
                        $null
                    )
                )
            } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $InstResponse } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
        }

        It 'writes a non-terminating error with Owner or UserAccessAdministrator guidance' {
            $Errs = $null
            Get-OPIMAzureRole -All -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Rewrap = @($Errs | Where-Object { $_.Exception.Message -like 'You do not have sufficient rights to view*' })
            $Rewrap | Should -HaveCount 1
            $Rewrap[0].Exception.Message | Should -Match 'Owner or UserAccessAdministrator'
        }
    }

    Context 'When the InsufficientPermissions rewrap is written' {
        # OPIM-11: the rewrapped record keeps no reference to the raw record, which can carry the
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
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest $RawFailure -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest $RawFailure -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
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
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Service unavailable'),
                        'ServiceUnavailable',
                        [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                        $null
                    )
                )
            } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
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
            $EmptyResponse = New-ArmResponse @()
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EmptyResponse } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
        }

        It 'reads the eligible list once per piped scope' {
            '/subscriptions/sub-001', '/subscriptions/sub-002' | Get-OPIMAzureRole
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 2 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq '/subscriptions/sub-001/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01'
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -ceq '/subscriptions/sub-002/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01'
            }
        }
    }

    Context 'When the transport throws a record' {
        # The transport gates every request itself (the sign-in latch, the tenant and the account of
        # the ARM token) and converts every failure, so the cmdlet only writes what it is given: the
        # record as itself, once per read, and nothing is returned. -All and a Name make two reads,
        # each with its own try, and the second is still made.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
        }

        It 'writes <Id> as itself for each read and returns nothing (<ModeName>)' -ForEach @(
            foreach ($Id in 'ArmTransportError', 'ArmTokenAcquisitionFailed', 'SignInRefused', 'TenantMismatch', 'AccountMismatch') {
                foreach ($Mode in @(
                        @{ Name = 'eligible'; Parameters = @{}; Expected = 1 }
                        @{ Name = '-Activated'; Parameters = @{ Activated = $true }; Expected = 1 }
                        @{ Name = '-All'; Parameters = @{ All = $true }; Expected = 2 }
                        @{ Name = '-Identity'; Parameters = @{ Identity = 'azure-001' }; Expected = 2 }
                    )) {
                    @{ Id = $Id; ModeName = $Mode.Name; Parameters = $Mode.Parameters; Expected = $Mode.Expected }
                }
            }
        ) {
            $Thrown = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("$Id raised by the transport"), $Id,
                [System.Management.Automation.ErrorCategory]::NotSpecified, '/providers/Microsoft.Authorization')
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $PSCmdlet.ThrowTerminatingError($Thrown) }

            $Output = @(Get-OPIMAzureRole @Parameters -ErrorAction Continue 2>&1)

            $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written | Should -HaveCount $Expected
            foreach ($Record in $Written) {
                $Record.FullyQualifiedErrorId.Split(',')[0] | Should -BeExactly $Id
                $Record.Exception.Message | Should -BeExactly "$Id raised by the transport"
            }
            @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times $Expected -Exactly -Scope It
        }

        It 'writes ArmTransportError once for the eligible read, with its id kept, and returns nothing' {
            $Thrown = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('The ARM request failed.'), 'ArmTransportError',
                [System.Management.Automation.ErrorCategory]::ConnectionError, '/providers/Microsoft.Authorization/roleEligibilitySchedules')
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $PSCmdlet.ThrowTerminatingError($Thrown) } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
            $Output = @(Get-OPIMAzureRole -ErrorAction Continue 2>&1)
            $Written = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written | Should -HaveCount 1
            $Written[0].FullyQualifiedErrorId | Should -BeExactly 'ArmTransportError,Get-OPIMAzureRole'
            $Written[0].Exception.Message | Should -BeExactly 'The ARM request failed.'
            @($Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Should -HaveCount 0
        }
    }

    Context 'When any mode reads' {
        # G15: after the move to the module's own transport no Az command is called.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            $EligResponse = New-ArmResponse (New-ArmItem Eligibility -Name 'azure-001' -Role 'Reader')
            $InstResponse = New-ArmResponse (New-ArmItem Instance -Name 'azure-act-001' -Role 'Reader')
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $EligResponse } -ParameterFilter { $Path -like '*/roleEligibilitySchedules?*' }
            Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { $InstResponse } -ParameterFilter { $Path -like '*/roleAssignmentScheduleInstances?*' }
            Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {}
            Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance {}
        }

        It 'calls no Az command and reads through the transport (<Name>)' -ForEach @(
            @{ Name = 'eligible'; Parameters = @{}; Reads = 1 }
            @{ Name = '-Activated'; Parameters = @{ Activated = $true }; Reads = 1 }
            @{ Name = '-All'; Parameters = @{ All = $true }; Reads = 2 }
            @{ Name = '-Identity'; Parameters = @{ Identity = 'azure-001' }; Reads = 2 }
            @{ Name = '-RoleName'; Parameters = @{ RoleName = 'Reader' }; Reads = 2 }
            @{ Name = '-Scope'; Parameters = @{ Scope = '/subscriptions/sub-001' }; Reads = 1 }
        ) {
            $null = Get-OPIMAzureRole @Parameters -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMArmRequest -Times $Reads -Exactly -Scope It
        }

        It 'runs no ARM gate of its own, since the transport gates every request' {
            Mock -ModuleName Omnicit.PIM Get-OPIMArmRefusal {}
            $null = Get-OPIMAzureRole -All
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMArmRefusal -Times 0 -Scope It
        }
    }
}
