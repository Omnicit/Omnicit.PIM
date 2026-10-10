BeforeDiscovery {
    # The seven ScriptProperties of Omnicit.PIM.Types.ps1xml that echo a note of their own name
    # (OPIM-48). Without the note they return $null; EndDateTime returns 'Never'.
    $script:NoNoteCases = @(
        @{ TypeName = 'Omnicit.PIM.DirectoryAssignmentScheduleInstance'; Property = 'MemberType'; Expected = $null }
        @{ TypeName = 'Omnicit.PIM.DirectoryAssignmentScheduleInstance'; Property = 'EndDateTime'; Expected = 'Never' }
        @{ TypeName = 'Omnicit.PIM.GroupEligibilitySchedule'; Property = 'AccessId'; Expected = $null }
        @{ TypeName = 'Omnicit.PIM.GroupEligibilitySchedule'; Property = 'MemberType'; Expected = $null }
        @{ TypeName = 'Omnicit.PIM.GroupAssignmentScheduleInstance'; Property = 'AccessId'; Expected = $null }
        @{ TypeName = 'Omnicit.PIM.GroupAssignmentScheduleInstance'; Property = 'AssignmentType'; Expected = $null }
        @{ TypeName = 'Omnicit.PIM.GroupAssignmentScheduleInstance'; Property = 'EndDateTime'; Expected = 'Never' }
    )
    $script:TypeCases = @(
        @{ TypeName = 'Omnicit.PIM.DirectoryAssignmentScheduleInstance' }
        @{ TypeName = 'Omnicit.PIM.GroupEligibilitySchedule' }
        @{ TypeName = 'Omnicit.PIM.GroupAssignmentScheduleInstance' }
    )
    $script:NoteCases = @(
        @{
            TypeName = 'Omnicit.PIM.DirectoryAssignmentScheduleInstance'
            Notes    = @{ id = 'inst-001'; memberType = 'Direct'; endDateTime = '2026-10-10T12:00:00Z' }
            Property = 'MemberType'
            Expected = 'Direct'
        }
        @{
            TypeName = 'Omnicit.PIM.DirectoryAssignmentScheduleInstance'
            Notes    = @{ id = 'inst-001'; memberType = 'Direct'; endDateTime = '2026-10-10T12:00:00Z' }
            Property = 'EndDateTime'
            Expected = '2026-10-10T12:00:00Z'
        }
        @{
            TypeName = 'Omnicit.PIM.GroupEligibilitySchedule'
            Notes    = @{ id = 'elig-001'; accessId = 'member'; memberType = 'Direct' }
            Property = 'AccessId'
            Expected = 'member'
        }
        @{
            TypeName = 'Omnicit.PIM.GroupEligibilitySchedule'
            Notes    = @{ id = 'elig-001'; accessId = 'member'; memberType = 'Direct' }
            Property = 'MemberType'
            Expected = 'Direct'
        }
        @{
            TypeName = 'Omnicit.PIM.GroupAssignmentScheduleInstance'
            Notes    = @{ id = 'inst-002'; accessId = 'owner'; assignmentType = 'Activated'; endDateTime = '2026-10-10T12:00:00Z' }
            Property = 'AccessId'
            Expected = 'owner'
        }
        @{
            TypeName = 'Omnicit.PIM.GroupAssignmentScheduleInstance'
            Notes    = @{ id = 'inst-002'; accessId = 'owner'; assignmentType = 'Activated'; endDateTime = '2026-10-10T12:00:00Z' }
            Property = 'AssignmentType'
            Expected = 'Activated'
        }
        @{
            TypeName = 'Omnicit.PIM.GroupAssignmentScheduleInstance'
            Notes    = @{ id = 'inst-002'; accessId = 'owner'; assignmentType = 'Activated'; endDateTime = '2026-10-10T12:00:00Z' }
            Property = 'EndDateTime'
            Expected = '2026-10-10T12:00:00Z'
        }
    )
    $script:NullEndCases = @(
        @{
            TypeName = 'Omnicit.PIM.DirectoryAssignmentScheduleInstance'
            Notes    = @{ id = 'inst-003'; memberType = 'Direct'; endDateTime = $null }
        }
        @{
            TypeName = 'Omnicit.PIM.GroupAssignmentScheduleInstance'
            Notes    = @{ id = 'inst-004'; accessId = 'member'; assignmentType = 'Assigned'; endDateTime = $null }
        }
    )
}

BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Omnicit.PIM.Types.ps1xml' {
    BeforeAll {
        # A typed fake: a PSCustomObject that carries the given notes and the module's type name.
        function New-TypedFake {
            param(
                [string]$TypeName,
                [hashtable]$Notes
            )
            $Fake = [PSCustomObject]$Notes
            $Fake.PSObject.TypeNames.Insert(0, $TypeName)
            $Fake
        }
    }

    # The type data is read from the module's own load (suffix.ps1), so these tests also prove that
    # the Types file still loads: without it the 'Never' of EndDateTime would not be there.
    Context 'When an object lacks the notes its ScriptProperties echo' {
        # An object's own note of the same name shadows a ScriptProperty of that name, so these
        # ScriptProperties run only on an object without the note (a hand-built object, a test
        # fake). A property that read $this.<its own name> there would call itself until the stack
        # overflowed and the process died.
        It 'returns <Expected> from <Property> of a <TypeName> without the note' -ForEach $script:NoNoteCases {
            $Fake = New-TypedFake -TypeName $TypeName -Notes @{ id = 'fake-001' }
            $Value = $Fake.$Property
            if ($null -eq $Expected) {
                $null -eq $Value | Should -BeTrue -Because 'without the note the echo returns $null, not an empty string'
            } else {
                $Value | Should -BeExactly $Expected
            }
        }

        It 'formats a <TypeName> without the notes as a table' -ForEach $script:TypeCases {
            $Fake = New-TypedFake -TypeName $TypeName -Notes @{ id = 'fake-001' }
            $Text = $Fake | Format-Table | Out-String -Width 200
            $Text | Should -Not -BeNullOrEmpty
            $Text | Should -Match 'PrincipalDisplayName'
        }

        It 'formats a <TypeName> without the notes as a list' -ForEach $script:TypeCases {
            $Fake = New-TypedFake -TypeName $TypeName -Notes @{ id = 'fake-001' }
            $Text = $Fake | Format-List | Out-String -Width 200
            $Text | Should -Not -BeNullOrEmpty
            $Text | Should -Match 'EndDateTime'
        }
    }

    Context 'When an object carries the notes its ScriptProperties echo' {
        # The note shadows the ScriptProperty, so the value is the note's own, as for every object
        # the module returns.
        It 'returns <Expected> from <Property> of a <TypeName> with the note' -ForEach $script:NoteCases {
            $Fake = New-TypedFake -TypeName $TypeName -Notes $Notes
            $Fake.$Property | Should -BeExactly $Expected
        }

        It 'returns null from EndDateTime of a <TypeName> whose endDateTime note is null' -ForEach $script:NullEndCases {
            $Fake = New-TypedFake -TypeName $TypeName -Notes $Notes
            $null -eq $Fake.EndDateTime | Should -BeTrue -Because 'the null note shadows the ScriptProperty, so the value is $null, not an empty string'
        }

        It 'formats a <TypeName> with the notes as a table' -ForEach $script:NoteCases.Where({ $_.Property -eq 'EndDateTime' }) {
            $Fake = New-TypedFake -TypeName $TypeName -Notes $Notes
            $Text = $Fake | Format-Table | Out-String -Width 200
            $Text | Should -Not -BeNullOrEmpty
            $Text | Should -Match 'PrincipalDisplayName'
        }
    }
}
