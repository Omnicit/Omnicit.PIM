BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'ConvertFrom-OPIMArmSchedule' {
    # Provenance of the fixtures: Microsoft Learn, Azure Authorization REST API, api-version
    # 2020-10-01 examples ("Role Eligibility Schedules - List For Scope", "Role Assignment Schedule
    # Instances - List For Scope", "Role Assignment Schedule Requests - Create"), redacted to
    # digit-repeat ids, with two items per list (a resource group and the subscription) and the
    # request's linkedRoleEligibilityScheduleId, which the schema has and the example leaves out.
    # The expected values are read from the fixture's own text, never typed twice.
    # -ForEach data is built when the file is discovered, so it stands outside BeforeAll.
    $Kinds = @(
        @{ Kind = 'EligibilitySchedule';        Count = 27 }
        @{ Kind = 'AssignmentScheduleInstance'; Count = 30 }
        @{ Kind = 'AssignmentScheduleRequest';  Count = 35 }
    )

    BeforeAll {
        $FixtureDirectory = "$PSScriptRoot/../TestHelpers/ArmResponse"
        $script:Fixture = @{
            EligibilitySchedule        = Get-Content -Raw -LiteralPath "$FixtureDirectory/roleEligibilitySchedules.json"
            AssignmentScheduleInstance = Get-Content -Raw -LiteralPath "$FixtureDirectory/roleAssignmentScheduleInstances.json"
            AssignmentScheduleRequest  = Get-Content -Raw -LiteralPath "$FixtureDirectory/roleAssignmentScheduleRequest.json"
        }

        # The JSON text of one value, as the file spells it: 'value[0].properties.createdOn'. A JSON
        # null, and a value that is not in the file, are $null.
        function Get-FixtureText {
            param([string]$Kind, [int]$Index, [string]$Path)
            $Document = [System.Text.Json.JsonDocument]::Parse($script:Fixture[$Kind])
            try {
                $Element = $Document.RootElement
                if ($Kind -ne 'AssignmentScheduleRequest') { $Element = $Element.GetProperty('value')[$Index] }
                foreach ($Segment in $Path.Split('.')) {
                    $Found = $false
                    foreach ($Property in $Element.EnumerateObject()) {
                        if ($Property.Name -ceq $Segment) {
                            $Element = $Property.Value
                            $Found = $true
                            break
                        }
                    }
                    if (-not $Found) { return $null }
                }
                if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Null) { return $null }
                $Element.GetString()
            } finally {
                $Document.Dispose()
            }
        }

        # A fresh object for one item of a fixture, so a test can change it.
        function Get-FixtureItem {
            param([string]$Kind, [int]$Index)
            $Parsed = $script:Fixture[$Kind] | ConvertFrom-Json
            if ($Kind -eq 'AssignmentScheduleRequest') { $Parsed } else { $Parsed.value[$Index] }
        }

        function Set-ItemValue {
            param($Item, [string]$Path, $Value)
            $Segments = $Path.Split('.')
            foreach ($Segment in $Segments[0..($Segments.Count - 2)]) { $Item = $Item.$Segment }
            $Item.($Segments[-1]) = $Value
        }

        function Invoke-Converter {
            param($InputObject, [string]$Kind)
            InModuleScope Omnicit.PIM -Parameters @{ InputObject = $InputObject; Kind = $Kind } {
                param($InputObject, $Kind)
                ConvertFrom-OPIMArmSchedule -InputObject $InputObject -Kind $Kind
            }
        }

        # Property -> JSON path, from the A4 table, for the string properties every kind shares ...
        $Common = @{
            Condition                          = 'properties.condition'
            ConditionVersion                   = 'properties.conditionVersion'
            ExpandedPropertiesPrincipalId      = 'properties.expandedProperties.principal.id'
            ExpandedPropertiesPrincipalType    = 'properties.expandedProperties.principal.type'
            ExpandedPropertiesRoleDefinitionId = 'properties.expandedProperties.roleDefinition.id'
            Id                                 = 'id'
            Name                               = 'name'
            PrincipalDisplayName               = 'properties.expandedProperties.principal.displayName'
            PrincipalEmail                     = 'properties.expandedProperties.principal.email'
            PrincipalId                        = 'properties.principalId'
            PrincipalType                      = 'properties.principalType'
            RoleDefinitionDisplayName          = 'properties.expandedProperties.roleDefinition.displayName'
            RoleDefinitionId                   = 'properties.roleDefinitionId'
            RoleDefinitionType                 = 'properties.expandedProperties.roleDefinition.type'
            Scope                              = 'properties.scope'
            ScopeDisplayName                   = 'properties.expandedProperties.scope.displayName'
            ScopeId                            = 'properties.expandedProperties.scope.id'
            ScopeType                          = 'properties.expandedProperties.scope.type'
            Status                             = 'properties.status'
            Type                               = 'type'
        }
        $Schedule = @{
            MemberType = 'properties.memberType'
        }
        # ... and the ones of one kind only.
        $StringPath = @{
            EligibilitySchedule        = $Common + $Schedule + @{
                RequestId = 'properties.roleEligibilityScheduleRequestId'
            }
            AssignmentScheduleInstance = $Common + $Schedule + @{
                AssignmentType                          = 'properties.assignmentType'
                LinkedRoleEligibilityScheduleId         = 'properties.linkedRoleEligibilityScheduleId'
                LinkedRoleEligibilityScheduleInstanceId = 'properties.linkedRoleEligibilityScheduleInstanceId'
                OriginRoleAssignmentId                  = 'properties.originRoleAssignmentId'
                RoleAssignmentScheduleId                = 'properties.roleAssignmentScheduleId'
            }
            AssignmentScheduleRequest  = $Common + @{
                ApprovalId                             = 'properties.approvalId'
                ExpirationDuration                     = 'properties.scheduleInfo.expiration.duration'
                ExpirationType                         = 'properties.scheduleInfo.expiration.type'
                Justification                          = 'properties.justification'
                LinkedRoleEligibilityScheduleId        = 'properties.linkedRoleEligibilityScheduleId'
                RequestType                            = 'properties.requestType'
                RequestorId                            = 'properties.requestorId'
                TargetRoleAssignmentScheduleId         = 'properties.targetRoleAssignmentScheduleId'
                TargetRoleAssignmentScheduleInstanceId = 'properties.targetRoleAssignmentScheduleInstanceId'
                TicketInfoTicketNumber                 = 'properties.ticketInfo.ticketNumber'
                TicketInfoTicketSystem                 = 'properties.ticketInfo.ticketSystem'
            }
        }
        $DatePath = @{
            EligibilitySchedule        = @{
                CreatedOn     = 'properties.createdOn'
                EndDateTime   = 'properties.endDateTime'
                StartDateTime = 'properties.startDateTime'
                UpdatedOn     = 'properties.updatedOn'
            }
            AssignmentScheduleInstance = @{
                CreatedOn     = 'properties.createdOn'
                EndDateTime   = 'properties.endDateTime'
                StartDateTime = 'properties.startDateTime'
            }
            AssignmentScheduleRequest  = @{
                CreatedOn                 = 'properties.createdOn'
                ExpirationEndDateTime     = 'properties.scheduleInfo.expiration.endDateTime'
                ScheduleInfoStartDateTime = 'properties.scheduleInfo.startDateTime'
            }
        }
        $script:StringPath = $StringPath
        $script:DatePath = $DatePath

        # The A4 property lists, written out and in alphabetical order.
        $script:A4Names = @{
            EligibilitySchedule        = @(
                'Condition', 'ConditionVersion', 'CreatedOn', 'EndDateTime', 'ExpandedPropertiesPrincipalId',
                'ExpandedPropertiesPrincipalType', 'ExpandedPropertiesRoleDefinitionId', 'Id', 'MemberType', 'Name',
                'PrincipalDisplayName', 'PrincipalEmail', 'PrincipalId', 'PrincipalType', 'RequestId',
                'ResourceGroupName', 'RoleDefinitionDisplayName', 'RoleDefinitionId', 'RoleDefinitionType', 'Scope',
                'ScopeDisplayName', 'ScopeId', 'ScopeType', 'StartDateTime', 'Status', 'Type', 'UpdatedOn'
            )
            AssignmentScheduleInstance = @(
                'AssignmentType', 'Condition', 'ConditionVersion', 'CreatedOn', 'EndDateTime',
                'ExpandedPropertiesPrincipalId', 'ExpandedPropertiesPrincipalType', 'ExpandedPropertiesRoleDefinitionId',
                'Id', 'LinkedRoleEligibilityScheduleId', 'LinkedRoleEligibilityScheduleInstanceId', 'MemberType', 'Name',
                'OriginRoleAssignmentId', 'PrincipalDisplayName', 'PrincipalEmail', 'PrincipalId', 'PrincipalType',
                'ResourceGroupName', 'RoleAssignmentScheduleId', 'RoleDefinitionDisplayName', 'RoleDefinitionId',
                'RoleDefinitionType', 'Scope', 'ScopeDisplayName', 'ScopeId', 'ScopeType', 'StartDateTime', 'Status', 'Type'
            )
            AssignmentScheduleRequest  = @(
                'ApprovalId', 'Condition', 'ConditionVersion', 'CreatedOn', 'ExpandedPropertiesPrincipalId',
                'ExpandedPropertiesPrincipalType', 'ExpandedPropertiesRoleDefinitionId', 'ExpirationDuration',
                'ExpirationEndDateTime', 'ExpirationType', 'Id', 'Justification', 'LinkedRoleEligibilityScheduleId', 'Name',
                'PrincipalDisplayName', 'PrincipalEmail', 'PrincipalId', 'PrincipalType', 'RequestorId', 'RequestType',
                'ResourceGroupName', 'RoleDefinitionDisplayName', 'RoleDefinitionId', 'RoleDefinitionType',
                'ScheduleInfoStartDateTime', 'Scope', 'ScopeDisplayName', 'ScopeId', 'ScopeType', 'Status',
                'TargetRoleAssignmentScheduleId', 'TargetRoleAssignmentScheduleInstanceId', 'TicketInfoTicketNumber',
                'TicketInfoTicketSystem', 'Type'
            )
        }
    }

    Context 'The A4 property list' {
        It 'holds <Count> properties for <Kind>, with no name twice' -ForEach $Kinds {
            @($script:A4Names[$Kind]).Count | Should -Be $Count
            @($script:A4Names[$Kind] | Select-Object -Unique).Count | Should -Be $Count
        }

        It 'is the sorted list the string and date maps cover, plus ResourceGroupName (<Kind>)' -ForEach $Kinds {
            $Covered = @($script:StringPath[$Kind].Keys) + @($script:DatePath[$Kind].Keys) + 'ResourceGroupName'
            ($Covered | Sort-Object) -join ',' | Should -BeExactly (($script:A4Names[$Kind] | Sort-Object) -join ',')
        }
    }

    Context 'When an item of each kind is converted' {
        It 'returns exactly the A4 properties of <Kind>' -ForEach $Kinds {
            $Result = Invoke-Converter -InputObject (Get-FixtureItem -Kind $Kind -Index 0) -Kind $Kind
            ($Result.PSObject.Properties.Name | Sort-Object) -join ',' | Should -BeExactly ($script:A4Names[$Kind] -join ',')
        }

        It 'returns the properties of <Kind> in alphabetical order' -ForEach $Kinds {
            $Result = Invoke-Converter -InputObject (Get-FixtureItem -Kind $Kind -Index 0) -Kind $Kind
            $Result.PSObject.Properties.Name -join ',' | Should -BeExactly ($script:A4Names[$Kind] -join ',')
        }

        It 'returns the <Kind> property list starting with <First>' -ForEach @(
            @{ Kind = 'EligibilitySchedule';        First = 'Condition,ConditionVersion,CreatedOn' }
            @{ Kind = 'AssignmentScheduleInstance'; First = 'AssignmentType,Condition,ConditionVersion' }
            @{ Kind = 'AssignmentScheduleRequest';  First = 'ApprovalId,Condition,ConditionVersion' }
        ) {
            $Result = Invoke-Converter -InputObject (Get-FixtureItem -Kind $Kind -Index 0) -Kind $Kind
            @($Result.PSObject.Properties.Name)[0..2] -join ',' | Should -BeExactly $First
        }

        It 'returns every string property of <Kind> as its JSON source, and $null for a JSON null' -ForEach $Kinds {
            $Result = Invoke-Converter -InputObject (Get-FixtureItem -Kind $Kind -Index 0) -Kind $Kind
            foreach ($Entry in $script:StringPath[$Kind].GetEnumerator()) {
                $Expected = Get-FixtureText -Kind $Kind -Index 0 -Path $Entry.Value
                if ($null -eq $Expected) {
                    $null -eq $Result.($Entry.Key) | Should -BeTrue -Because "$($Entry.Key) is null in the JSON and must stay null"
                } else {
                    $Result.($Entry.Key) | Should -BeOfType ([string]) -Because "$($Entry.Key) is a string"
                    $Result.($Entry.Key) | Should -BeExactly $Expected -Because "$($Entry.Key) is read from $($Entry.Value)"
                }
            }
        }

        It 'returns every date property of <Kind> as a UTC DateTime of the JSON instant, and $null for a JSON null' -ForEach $Kinds {
            $Result = Invoke-Converter -InputObject (Get-FixtureItem -Kind $Kind -Index 0) -Kind $Kind
            foreach ($Entry in $script:DatePath[$Kind].GetEnumerator()) {
                $Text = Get-FixtureText -Kind $Kind -Index 0 -Path $Entry.Value
                if ($null -eq $Text) {
                    $null -eq $Result.($Entry.Key) | Should -BeTrue -Because "$($Entry.Key) is null in the JSON and must stay null"
                } else {
                    $Expected = [DateTimeOffset]::Parse($Text, [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::AssumeUniversal).UtcDateTime
                    $Result.($Entry.Key) | Should -BeOfType ([datetime]) -Because "$($Entry.Key) is a date"
                    # The round-trip format ends in Z for Kind Utc only, so one comparison holds the
                    # instant and the Kind.
                    $Result.($Entry.Key).ToString('o') | Should -BeExactly $Expected.ToString('o') -Because "$($Entry.Key) is read from $($Entry.Value)"
                }
            }
        }

        It 'returns a $null date for a JSON null in the second item of <Kind>' -ForEach @(
            @{ Kind = 'EligibilitySchedule' }
            @{ Kind = 'AssignmentScheduleInstance' }
        ) {
            $Result = Invoke-Converter -InputObject (Get-FixtureItem -Kind $Kind -Index 1) -Kind $Kind
            $null -eq $Result.EndDateTime | Should -BeTrue
            $null -eq $Result.Condition | Should -BeTrue
            $null -eq $Result.ConditionVersion | Should -BeTrue
        }

        It 'inserts no type name on <Kind>' -ForEach $Kinds {
            $Result = Invoke-Converter -InputObject (Get-FixtureItem -Kind $Kind -Index 0) -Kind $Kind
            $Result.PSObject.TypeNames[0] | Should -BeExactly 'System.Management.Automation.PSCustomObject'
        }
    }

    Context 'When the resource group is read from the id' {
        It 'returns opim-fixture-rg for the resource group item and $null for the subscription item of <Kind>' -ForEach @(
            @{ Kind = 'EligibilitySchedule' }
            @{ Kind = 'AssignmentScheduleInstance' }
        ) {
            (Invoke-Converter -InputObject (Get-FixtureItem -Kind $Kind -Index 0) -Kind $Kind).ResourceGroupName | Should -BeExactly 'opim-fixture-rg'
            $null -eq (Invoke-Converter -InputObject (Get-FixtureItem -Kind $Kind -Index 1) -Kind $Kind).ResourceGroupName | Should -BeTrue
        }

        It 'returns the resource group of <Kind> too' -ForEach $Kinds {
            $Item = Get-FixtureItem -Kind $Kind -Index 0
            $Item.id = '/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/opim-fixture-rg/providers/Microsoft.Authorization/X/66666666-6666-6666-6666-666666666666'
            (Invoke-Converter -InputObject $Item -Kind $Kind).ResourceGroupName | Should -BeExactly 'opim-fixture-rg'
        }

        It 'reads <Case> as <Expected>' -ForEach @(
            @{ Case = 'the words of the id in any letter case'; Id = '/SUBSCRIPTIONS/s/RESOURCEGROUPS/Rg-Name/PROVIDERS/Microsoft.Authorization/X/y'; Expected = 'Rg-Name' }
            @{ Case = 'the group of a resource inside it'; Id = '/subscriptions/s/resourceGroups/rg-one/providers/Microsoft.Compute/virtualMachines/vm/providers/Microsoft.Authorization/X/y'; Expected = 'rg-one' }
            @{ Case = 'an id at a management group'; Id = '/providers/Microsoft.Management/managementGroups/mg/providers/Microsoft.Authorization/X/y'; Expected = $null }
            @{ Case = 'an id at a subscription'; Id = '/subscriptions/s/providers/Microsoft.Authorization/X/y'; Expected = $null }
            @{ Case = 'an id that is a resource group without a provider'; Id = '/subscriptions/s/resourceGroups/rg-one'; Expected = $null }
            @{ Case = 'an id that does not start with the subscription'; Id = '/x/subscriptions/s/resourceGroups/rg-one/providers/Microsoft.Authorization/X/y'; Expected = $null }
            @{ Case = 'a missing id'; Id = $null; Expected = $null }
        ) {
            $Item = Get-FixtureItem -Kind EligibilitySchedule -Index 0
            $Item.id = $Id
            $Result = Invoke-Converter -InputObject $Item -Kind EligibilitySchedule
            if ($null -eq $Expected) { $null -eq $Result.ResourceGroupName | Should -BeTrue } else { $Result.ResourceGroupName | Should -BeExactly $Expected }
        }
    }

    Context 'When a date does not arrive as an UTC string' {
        It 'reads a string with an offset of the <Kind> as the UTC instant' -ForEach $Kinds {
            $Item = Get-FixtureItem -Kind $Kind -Index 0
            foreach ($Entry in $script:DatePath[$Kind].GetEnumerator()) {
                Set-ItemValue -Item $Item -Path $Entry.Value -Value '2026-10-08T12:00:00+02:00'
            }
            $Result = Invoke-Converter -InputObject $Item -Kind $Kind
            foreach ($Name in $script:DatePath[$Kind].Keys) {
                $Result.$Name.ToString('o') | Should -BeExactly '2026-10-08T10:00:00.0000000Z' -Because "$Name is converted to UTC"
            }
        }

        It 'reads a DateTime of Kind Local of the <Kind> as the same instant in UTC' -ForEach $Kinds {
            $Local = [datetime]::SpecifyKind([datetime]::new(2026, 10, 8, 12, 0, 0), [System.DateTimeKind]::Local)
            $Item = Get-FixtureItem -Kind $Kind -Index 0
            foreach ($Entry in $script:DatePath[$Kind].GetEnumerator()) {
                Set-ItemValue -Item $Item -Path $Entry.Value -Value $Local
            }
            $Result = Invoke-Converter -InputObject $Item -Kind $Kind
            foreach ($Name in $script:DatePath[$Kind].Keys) {
                $Result.$Name | Should -BeOfType ([datetime]) -Because "$Name is a date"
                $Result.$Name.ToString('o') | Should -BeExactly $Local.ToUniversalTime().ToString('o') -Because "$Name is converted to UTC"
            }
        }

        It 'reads a DateTime of Kind Unspecified of the <Kind> as UTC' -ForEach $Kinds {
            $Item = Get-FixtureItem -Kind $Kind -Index 0
            foreach ($Entry in $script:DatePath[$Kind].GetEnumerator()) {
                Set-ItemValue -Item $Item -Path $Entry.Value -Value ([datetime]::new(2026, 10, 8, 12, 0, 0))
            }
            $Result = Invoke-Converter -InputObject $Item -Kind $Kind
            foreach ($Name in $script:DatePath[$Kind].Keys) {
                $Result.$Name.ToString('o') | Should -BeExactly '2026-10-08T12:00:00.0000000Z' -Because "$Name is converted to UTC"
            }
        }

        It 'returns a $null date, not a missing property, for an empty string' {
            $Item = Get-FixtureItem -Kind EligibilitySchedule -Index 0
            Set-ItemValue -Item $Item -Path 'properties.endDateTime' -Value ''
            $Result = Invoke-Converter -InputObject $Item -Kind EligibilitySchedule
            $Result.PSObject.Properties.Name | Should -Contain 'EndDateTime'
            $null -eq $Result.EndDateTime | Should -BeTrue
        }
    }

    Context 'When the ARM item is incomplete' {
        It 'returns $null display names and ids, and no error, for a <Kind> without expandedProperties' -ForEach $Kinds {
            $Item = Get-FixtureItem -Kind $Kind -Index 0
            $Item.properties.PSObject.Properties.Remove('expandedProperties')
            $Result = Invoke-Converter -InputObject $Item -Kind $Kind
            @($Result) | Should -HaveCount 1
            foreach ($Name in 'ExpandedPropertiesPrincipalId', 'ExpandedPropertiesPrincipalType', 'ExpandedPropertiesRoleDefinitionId',
                'PrincipalDisplayName', 'PrincipalEmail', 'RoleDefinitionDisplayName', 'RoleDefinitionType',
                'ScopeDisplayName', 'ScopeId', 'ScopeType') {
                $null -eq $Result.$Name | Should -BeTrue -Because "$Name is not in the item"
            }
            $Result.Name | Should -BeExactly (Get-FixtureText -Kind $Kind -Index 0 -Path 'name')
            $Result.RoleDefinitionId | Should -BeExactly (Get-FixtureText -Kind $Kind -Index 0 -Path 'properties.roleDefinitionId')
        }

        It 'returns every property of <Kind> as $null for an item that carries nothing' -ForEach $Kinds {
            $Result = Invoke-Converter -InputObject ([pscustomobject]@{}) -Kind $Kind
            @($Result) | Should -HaveCount 1
            $Result.PSObject.Properties.Name -join ',' | Should -BeExactly ($script:A4Names[$Kind] -join ',')
            foreach ($Name in $script:A4Names[$Kind]) {
                $null -eq $Result.$Name | Should -BeTrue -Because "$Name is not in the item"
            }
        }
    }

    Context 'When the input is null or piped' {
        It 'returns nothing for a null InputObject' {
            InModuleScope Omnicit.PIM {
                @(ConvertFrom-OPIMArmSchedule -InputObject $null -Kind EligibilitySchedule).Count | Should -Be 0
            }
        }

        It 'returns nothing for a null from the pipeline' {
            InModuleScope Omnicit.PIM {
                @($null | ConvertFrom-OPIMArmSchedule -Kind EligibilitySchedule).Count | Should -Be 0
            }
        }

        It 'returns nothing for the value of a response without one' {
            InModuleScope Omnicit.PIM {
                $Response = [pscustomobject]@{ value = $null }
                @($Response.value | ConvertFrom-OPIMArmSchedule -Kind EligibilitySchedule).Count | Should -Be 0
            }
        }

        It 'converts every item from the pipeline' {
            $Items = @((Get-FixtureItem -Kind EligibilitySchedule -Index 0), (Get-FixtureItem -Kind EligibilitySchedule -Index 1))
            $Result = @(InModuleScope Omnicit.PIM -Parameters @{ Items = $Items } {
                    param($Items)
                    $Items | ConvertFrom-OPIMArmSchedule -Kind EligibilitySchedule
                })
            $Result | Should -HaveCount 2
            $Result[0].Name | Should -BeExactly (Get-FixtureText -Kind EligibilitySchedule -Index 0 -Path 'name')
            $Result[1].Name | Should -BeExactly (Get-FixtureText -Kind EligibilitySchedule -Index 1 -Path 'name')
            $Result[0].ScopeDisplayName | Should -BeExactly 'opim-fixture-rg'
            $Result[1].ScopeDisplayName | Should -BeExactly 'Fixture Subscription'
        }

        It 'refuses a Kind it does not know' {
            InModuleScope Omnicit.PIM {
                { ConvertFrom-OPIMArmSchedule -InputObject ([pscustomobject]@{}) -Kind 'Group' } |
                    Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            }
        }
    }
}
