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

        It 'returns the properties of <Kind> in the same order under a culture that sorts ch after h' -ForEach $Kinds {
            # cs-CZ sorts the letter pair ch after h, so a sort by the culture would put Scope before
            # ScheduleInfoStartDateTime. The order is ordinal and case-insensitive under every culture.
            $Thread = [System.Threading.Thread]::CurrentThread
            $Before = $Thread.CurrentCulture
            try {
                $Thread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('cs-CZ')
                $Result = Invoke-Converter -InputObject (Get-FixtureItem -Kind $Kind -Index 0) -Kind $Kind
            } finally {
                $Thread.CurrentCulture = $Before
            }
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

    # The answers ARM gave in the live run of docs/live-verification/feat-arm-transport-checklist.md
    # (tests/Unit/TestHelpers/ArmResponse/recorded-*.json), redacted to non-v4 placeholder ids and
    # to the contoso.com domain. Where the Microsoft Learn fixtures above show the documented
    # shape, these show what the service really returned: dates with none to seven fractional
    # digits and with a Z or a +00:00 suffix, an Assigned row that carries no end date and no link
    # to its eligibility, request answers with an empty ticketInfo (and, for the SelfDeactivate
    # answer, no scheduleInfo), and a principal that carries userPrincipalName where the schema
    # has email.
    # The expected values are read from the recorded text itself, with the same JsonDocument oracle
    # as above, never typed twice.
    # -ForEach data is built when the file is discovered, so it stands outside BeforeAll.
    Context 'recorded ARM answers' {
        $RecordedAnswers = @(
            @{ Name = 'eligibility schedule at the first resource group'; File = 'recorded-roleEligibilitySchedules.json'; Index = 0; Kind = 'EligibilitySchedule' }
            @{ Name = 'eligibility schedule at the second resource group'; File = 'recorded-roleEligibilitySchedules.json'; Index = 1; Kind = 'EligibilitySchedule' }
            @{ Name = 'Activated instance'; File = 'recorded-roleAssignmentScheduleInstances.json'; Index = 0; Kind = 'AssignmentScheduleInstance' }
            @{ Name = 'Assigned instance'; File = 'recorded-roleAssignmentScheduleInstances.json'; Index = 1; Kind = 'AssignmentScheduleInstance' }
            @{ Name = 'SelfActivate request'; File = 'recorded-roleAssignmentScheduleRequest-SelfActivate.json'; Index = -1; Kind = 'AssignmentScheduleRequest' }
            @{ Name = 'SelfDeactivate request'; File = 'recorded-roleAssignmentScheduleRequest-SelfDeactivate.json'; Index = -1; Kind = 'AssignmentScheduleRequest' }
        )

        # What each recorded answer does not carry: the properties that must come out $null, since
        # neither the field nor a value is in the text.
        $RecordedNulls = @(
            @{
                Name = 'eligibility schedule'; File = 'recorded-roleEligibilitySchedules.json'; Index = 0; Kind = 'EligibilitySchedule'
                Missing = @('Condition', 'ConditionVersion', 'PrincipalEmail')
            }
            @{
                Name = 'Activated instance'; File = 'recorded-roleAssignmentScheduleInstances.json'; Index = 0; Kind = 'AssignmentScheduleInstance'
                Missing = @('Condition', 'ConditionVersion', 'PrincipalEmail')
            }
            @{
                Name = 'Assigned instance'; File = 'recorded-roleAssignmentScheduleInstances.json'; Index = 1; Kind = 'AssignmentScheduleInstance'
                Missing = @('Condition', 'ConditionVersion', 'EndDateTime', 'LinkedRoleEligibilityScheduleId', 'LinkedRoleEligibilityScheduleInstanceId', 'PrincipalEmail')
            }
            @{
                Name = 'SelfActivate request'; File = 'recorded-roleAssignmentScheduleRequest-SelfActivate.json'; Index = -1; Kind = 'AssignmentScheduleRequest'
                Missing = @('ApprovalId', 'Condition', 'ConditionVersion', 'ExpirationEndDateTime', 'PrincipalEmail',
                    'TargetRoleAssignmentScheduleInstanceId', 'TicketInfoTicketNumber', 'TicketInfoTicketSystem')
            }
            @{
                Name = 'SelfDeactivate request'; File = 'recorded-roleAssignmentScheduleRequest-SelfDeactivate.json'; Index = -1; Kind = 'AssignmentScheduleRequest'
                Missing = @('ApprovalId', 'Condition', 'ConditionVersion', 'ExpirationDuration', 'ExpirationEndDateTime', 'ExpirationType',
                    'Justification', 'LinkedRoleEligibilityScheduleId', 'PrincipalEmail', 'ScheduleInfoStartDateTime',
                    'TargetRoleAssignmentScheduleId', 'TargetRoleAssignmentScheduleInstanceId', 'TicketInfoTicketNumber', 'TicketInfoTicketSystem')
            }
        )

        BeforeAll {
            $RecordedDirectory = "$PSScriptRoot/../TestHelpers/ArmResponse"
            $script:Recorded = @{}
            foreach ($File in 'recorded-roleEligibilitySchedules.json', 'recorded-roleAssignmentScheduleInstances.json',
                'recorded-roleAssignmentScheduleRequest-SelfActivate.json', 'recorded-roleAssignmentScheduleRequest-SelfDeactivate.json') {
                $script:Recorded[$File] = Get-Content -Raw -LiteralPath "$RecordedDirectory/$File"
            }

            # The JSON text of one value of a recorded answer, as the file spells it. Index is the
            # item of a list answer ('value[Index]') and -1 for an answer that is one object. A JSON
            # null, and a value that is not in the file, are $null.
            function Get-RecordedText {
                param([string]$File, [int]$Index, [string]$Path)
                $Document = [System.Text.Json.JsonDocument]::Parse($script:Recorded[$File])
                try {
                    $Element = $Document.RootElement
                    if ($Index -ge 0) { $Element = $Element.GetProperty('value')[$Index] }
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

            # A fresh object for one item of a recorded answer, read by ConvertFrom-Json, as the transport reads a response.
            function Get-RecordedItem {
                param([string]$File, [int]$Index)
                $Parsed = $script:Recorded[$File] | ConvertFrom-Json
                if ($Index -ge 0) { $Parsed.value[$Index] } else { $Parsed }
            }
        }

        It 'records the states the cases are named after' {
            Get-RecordedText -File 'recorded-roleAssignmentScheduleInstances.json' -Index 0 -Path 'properties.assignmentType' | Should -BeExactly 'Activated'
            Get-RecordedText -File 'recorded-roleAssignmentScheduleInstances.json' -Index 1 -Path 'properties.assignmentType' | Should -BeExactly 'Assigned'
            Get-RecordedText -File 'recorded-roleAssignmentScheduleRequest-SelfActivate.json' -Index -1 -Path 'properties.requestType' | Should -BeExactly 'SelfActivate'
            Get-RecordedText -File 'recorded-roleAssignmentScheduleRequest-SelfDeactivate.json' -Index -1 -Path 'properties.requestType' | Should -BeExactly 'SelfDeactivate'
        }

        It 'returns exactly the A4 properties of <Kind> for the recorded <Name>' -ForEach $RecordedAnswers {
            $Result = Invoke-Converter -InputObject (Get-RecordedItem -File $File -Index $Index) -Kind $Kind
            @($Result) | Should -HaveCount 1
            $Result.PSObject.Properties.Name -join ',' | Should -BeExactly ($script:A4Names[$Kind] -join ',')
        }

        It 'returns every string property of the recorded <Name> as its JSON source, and $null for what the text lacks' -ForEach $RecordedAnswers {
            $Result = Invoke-Converter -InputObject (Get-RecordedItem -File $File -Index $Index) -Kind $Kind
            foreach ($Entry in $script:StringPath[$Kind].GetEnumerator()) {
                $Expected = Get-RecordedText -File $File -Index $Index -Path $Entry.Value
                if ($null -eq $Expected) {
                    $null -eq $Result.($Entry.Key) | Should -BeTrue -Because "$($Entry.Key) is not in the recorded text and must stay null"
                } else {
                    $Result.($Entry.Key) | Should -BeOfType ([string]) -Because "$($Entry.Key) is a string"
                    $Result.($Entry.Key) | Should -BeExactly $Expected -Because "$($Entry.Key) is read from $($Entry.Value)"
                }
            }
        }

        It 'returns every date property of the recorded <Name> as a UTC DateTime of the JSON instant, and $null for what the text lacks' -ForEach $RecordedAnswers {
            $Result = Invoke-Converter -InputObject (Get-RecordedItem -File $File -Index $Index) -Kind $Kind
            foreach ($Entry in $script:DatePath[$Kind].GetEnumerator()) {
                $Text = Get-RecordedText -File $File -Index $Index -Path $Entry.Value
                if ($null -eq $Text) {
                    $null -eq $Result.($Entry.Key) | Should -BeTrue -Because "$($Entry.Key) is not in the recorded text and must stay null"
                } else {
                    $Expected = [DateTimeOffset]::Parse($Text, [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::AssumeUniversal).UtcDateTime
                    $Result.($Entry.Key) | Should -BeOfType ([datetime]) -Because "$($Entry.Key) is a date"
                    $Result.($Entry.Key).Kind | Should -Be ([System.DateTimeKind]::Utc) -Because "$($Entry.Key) is in UTC"
                    $Result.($Entry.Key).ToString('o') | Should -BeExactly $Expected.ToString('o') -Because "$($Entry.Key) is read from $($Entry.Value)"
                }
            }
        }

        It 'returns $null for the properties the recorded <Name> does not carry' -ForEach $RecordedNulls {
            $Result = Invoke-Converter -InputObject (Get-RecordedItem -File $File -Index $Index) -Kind $Kind
            foreach ($Property in $Missing) {
                $Path = if ($script:StringPath[$Kind].ContainsKey($Property)) { $script:StringPath[$Kind][$Property] } else { $script:DatePath[$Kind][$Property] }
                $Path | Should -Not -BeNullOrEmpty -Because "$Property must be a property the A4 maps cover for $Kind"
                $null -eq (Get-RecordedText -File $File -Index $Index -Path $Path) | Should -BeTrue -Because "$Path is not in the recorded text"
                $null -eq $Result.$Property | Should -BeTrue -Because "$Property has no source in the recorded text"
            }
        }

        It 'returns the resource group of the id of the recorded <Name>' -ForEach $RecordedAnswers {
            $Result = Invoke-Converter -InputObject (Get-RecordedItem -File $File -Index $Index) -Kind $Kind
            # The id is /subscriptions/<id>/resourceGroups/<name>/providers/...: the name is its fifth segment.
            $Segments = (Get-RecordedText -File $File -Index $Index -Path 'id').Split('/')
            $Segments[3] | Should -BeExactly 'resourceGroups' -Because 'the recorded id is in a resource group'
            $Expected = $Segments[4]
            $Expected | Should -Not -BeNullOrEmpty
            $Result.ResourceGroupName | Should -BeExactly $Expected
            $Result.ResourceGroupName | Should -BeExactly (Get-RecordedText -File $File -Index $Index -Path 'properties.expandedProperties.scope.displayName') -Because 'the recorded scope is the resource group itself'
        }

        It 'reads the end of the recorded Activated instance, a Z-suffixed date with no fraction, as that second in UTC' {
            $Result = Invoke-Converter -InputObject (Get-RecordedItem -File 'recorded-roleAssignmentScheduleInstances.json' -Index 0) -Kind AssignmentScheduleInstance
            $Result.EndDateTime.ToString('o') | Should -BeExactly ((Get-RecordedText -File 'recorded-roleAssignmentScheduleInstances.json' -Index 0 -Path 'properties.endDateTime') -replace 'Z$', '.0000000Z')
        }

        It 'reads the start of the recorded SelfActivate request, a +00:00 date with seven digits, as that instant in UTC' {
            $Result = Invoke-Converter -InputObject (Get-RecordedItem -File 'recorded-roleAssignmentScheduleRequest-SelfActivate.json' -Index -1) -Kind AssignmentScheduleRequest
            $Text = Get-RecordedText -File 'recorded-roleAssignmentScheduleRequest-SelfActivate.json' -Index -1 -Path 'properties.scheduleInfo.startDateTime'
            $Text | Should -Match '\.\d{7}\+00:00$' -Because 'the recorded start carries seven fractional digits and an offset'
            $Result.ScheduleInfoStartDateTime.ToString('o') | Should -BeExactly ($Text -replace '\+00:00$', 'Z')
        }
    }
}
