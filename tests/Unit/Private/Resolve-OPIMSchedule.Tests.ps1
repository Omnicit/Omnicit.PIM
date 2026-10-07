BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Resolve-OPIMSchedule' {
    BeforeAll {
        # Typed fakes, one list per pillar and state. Group fakes carry accessId and memberType, the
        # properties their self-referencing ScriptProperties read. Every fake carries a Status, as
        # the -All listing tags it ('Eligible' or 'Active').
        $Sets = InModuleScope Omnicit.PIM {
            function New-DirectoryPost {
                param([string]$Id, [string]$Role, [string]$ScopeId = '/', [string]$ScopeName, [string]$Status = 'Eligible')
                $Post = [PSCustomObject]@{
                    id               = $Id
                    roleDefinition   = [PSCustomObject]@{ displayName = $Role }
                    directoryScopeId = $ScopeId
                    directoryScope   = if ($ScopeName) { [PSCustomObject]@{ displayName = $ScopeName } } else { $null }
                    scheduleInfo     = $null
                    Status           = $Status
                }
                $TypeName = if ($Status -eq 'Active') { 'Omnicit.PIM.DirectoryAssignmentScheduleInstance' } else { 'Omnicit.PIM.DirectoryEligibilitySchedule' }
                $Post.PSObject.TypeNames.Insert(0, $TypeName)
                $Post
            }
            function New-GroupPost {
                param([string]$Id, [string]$GroupId, [string]$Name, [string]$AccessId, [string]$Status = 'Eligible')
                $Post = [PSCustomObject]@{
                    id             = $Id
                    groupId        = $GroupId
                    accessId       = $AccessId
                    memberType     = 'direct'
                    assignmentType = 'activated'
                    endDateTime    = $null
                    group          = [PSCustomObject]@{ displayName = $Name }
                    scheduleInfo   = $null
                    Status         = $Status
                }
                $TypeName = if ($Status -eq 'Active') { 'Omnicit.PIM.GroupAssignmentScheduleInstance' } else { 'Omnicit.PIM.GroupEligibilitySchedule' }
                $Post.PSObject.TypeNames.Insert(0, $TypeName)
                $Post
            }
            function New-AzurePost {
                param([string]$Name, [string]$Role, [string]$ScopeId, [string]$ScopeName, [string]$Status = 'Eligible')
                $Post = [PSCustomObject]@{
                    Name                      = $Name
                    RoleDefinitionDisplayName = $Role
                    ScopeId                   = $ScopeId
                    ScopeDisplayName          = $ScopeName
                    Status                    = $Status
                }
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
                $Post
            }

            $DirectoryEligible = @(
                New-DirectoryPost -Id 'elig-001' -Role 'Usage Summary Reports Reader'
                New-DirectoryPost -Id 'elig-002' -Role 'Usage Summary Reports Reader' -ScopeId '/administrativeUnits/au-001' -ScopeName 'Sales AU'
                New-DirectoryPost -Id 'elig-003' -Role 'Message Center Privacy Reader'
                New-DirectoryPost -Id 'elig-011' -Role 'Ops (Tier 1)'
                New-DirectoryPost -Id 'elig-012' -Role "O'Brien Reader"
            )
            $DirectoryActive = @(New-DirectoryPost -Id 'act-003' -Role 'Message Center Privacy Reader' -Status Active)
            $DirectoryActiveTwin = New-DirectoryPost -Id 'act-103' -Role 'Message Center Privacy Reader' -Status Active

            $GroupEligible = @(
                New-GroupPost -Id 'grp-elig-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'member'
                New-GroupPost -Id 'grp-elig-002' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'owner'
                New-GroupPost -Id 'grp-elig-003' -GroupId 'g-2' -Name 'Twin' -AccessId 'member'
                New-GroupPost -Id 'grp-elig-004' -GroupId 'g-3' -Name 'Twin' -AccessId 'member'
                New-GroupPost -Id 'grp-elig-005' -GroupId 'g-4' -Name 'unique-grp' -AccessId 'member'
                New-GroupPost -Id 'grp-elig-006' -GroupId 'g-5' -Name 'owner-only-grp' -AccessId 'owner'
                New-GroupPost -Id 'grp-elig-011' -GroupId 'g-6' -Name 'Ops (Tier 1)' -AccessId 'member'
                New-GroupPost -Id 'grp-elig-012' -GroupId 'g-7' -Name "O'Brien Team" -AccessId 'member'
            )
            $GroupActive = @(New-GroupPost -Id 'grp-act-005' -GroupId 'g-4' -Name 'unique-grp' -AccessId 'member' -Status Active)
            $GroupActiveTwin = New-GroupPost -Id 'grp-act-105' -GroupId 'g-4' -Name 'unique-grp' -AccessId 'member' -Status Active

            $AzureEligible = @(
                New-AzurePost -Name 'azure-001' -Role 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one'
                New-AzurePost -Name 'azure-002' -Role 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-two' -ScopeName 'rg-two'
                New-AzurePost -Name 'azure-003' -Role 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001'
                New-AzurePost -Name 'azure-011' -Role 'Ops (Tier 1)' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001'
                New-AzurePost -Name 'azure-012' -Role "O'Brien Reader" -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001'
            )
            $AzureActive = @(New-AzurePost -Name 'azure-act-003' -Role 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001' -Status Active)
            $AzureActiveTwin = New-AzurePost -Name 'azure-act-103' -Role 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'sub-001' -Status Active

            @{
                Directory = @{
                    Eligible      = $DirectoryEligible
                    Active        = $DirectoryActive
                    Both          = @($DirectoryEligible) + $DirectoryActive
                    BothTwoActive = @($DirectoryEligible) + $DirectoryActive + @($DirectoryActiveTwin)
                }
                Group     = @{
                    Eligible      = $GroupEligible
                    Active        = $GroupActive
                    Both          = @($GroupEligible) + $GroupActive
                    BothTwoActive = @($GroupEligible) + $GroupActive + @($GroupActiveTwin)
                }
                Azure     = @{
                    Eligible      = $AzureEligible
                    Active        = $AzureActive
                    Both          = @($AzureEligible) + $AzureActive
                    BothTwoActive = @($AzureEligible) + $AzureActive + @($AzureActiveTwin)
                }
            }
        }

        # Runs the resolver in module scope. $Resolve returns what it returns; $Capture returns the
        # error record it throws, or nothing when it does not throw.
        $Resolve = {
            param([hashtable]$Params)
            InModuleScope Omnicit.PIM -Parameters @{ Params = $Params } {
                param($Params)
                Resolve-OPIMSchedule @Params
            }
        }
        $Capture = {
            param([hashtable]$Params)
            InModuleScope Omnicit.PIM -Parameters @{ Params = $Params } {
                param($Params)
                try { Resolve-OPIMSchedule @Params } catch { $PSItem }
            }
        }
    }

    Context 'When the pillar lists posts' -ForEach @(
        @{
            Pillar = 'Directory'; Lister = 'Get-OPIMDirectoryRole'; KeyProp = 'id'; FilterParameter = 'Scope'
            Unique = 'Message Center Privacy Reader'; UniqueKey = 'elig-003'; ActiveKey = 'act-003'
            Ambiguous = 'Usage Summary Reports Reader'; AmbiguousKeys = @('elig-001', 'elig-002')
            Narrow = @{ Scope = '/administrativeUnits/au-001' }; NarrowName = 'Usage Summary Reports Reader'; NarrowKey = 'elig-002'
            OldForm = 'Usage Summary Reports Reader -> Sales AU (elig-002)'; OldKey = 'elig-002'
            ParenForm = 'Ops (Tier 1) (elig-011)'; ParenKey = 'elig-011'
            Apostrophe = "o'brien reader"; ApostropheKey = 'elig-012'
            Missing = 'Nobody Carries This'
        }
        @{
            Pillar = 'Group'; Lister = 'Get-OPIMEntraIDGroup'; KeyProp = 'id'; FilterParameter = 'AccessType'
            Unique = 'unique-grp'; UniqueKey = 'grp-elig-005'; ActiveKey = 'grp-act-005'
            Ambiguous = 'Twin'; AmbiguousKeys = @('grp-elig-003', 'grp-elig-004')
            Narrow = @{ AccessType = 'owner' }; NarrowName = 'opim-grp'; NarrowKey = 'grp-elig-002'
            OldForm = 'opim-grp - owner (grp-elig-002)'; OldKey = 'grp-elig-002'
            ParenForm = 'Ops (Tier 1) - member (grp-elig-011)'; ParenKey = 'grp-elig-011'
            Apostrophe = "o'brien team"; ApostropheKey = 'grp-elig-012'
            Missing = 'Nobody Carries This'
        }
        @{
            Pillar = 'Azure'; Lister = 'Get-OPIMAzureRole'; KeyProp = 'Name'; FilterParameter = 'Scope'
            Unique = 'Contributor'; UniqueKey = 'azure-003'; ActiveKey = 'azure-act-003'
            Ambiguous = 'Reader'; AmbiguousKeys = @('azure-001', 'azure-002')
            Narrow = @{ Scope = '/subscriptions/sub-001/resourceGroups/rg-one' }; NarrowName = 'Reader'; NarrowKey = 'azure-001'
            OldForm = 'Reader -> rg-two (azure-002)'; OldKey = 'azure-002'
            ParenForm = 'Ops (Tier 1) -> sub-001 (azure-011)'; ParenKey = 'azure-011'
            Apostrophe = "o'brien reader"; ApostropheKey = 'azure-012'
            Missing = 'Nobody Carries This'
        }
    ) {
        It 'returns the one post for a unique display name (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            $Found = & $Resolve @{ Pillar = $Pillar; Name = $Unique }
            @($Found).Count | Should -Be 1
            @($Found)[0].$KeyProp | Should -Be $UniqueKey
        }

        It 'calls the listing once with -ErrorAction Stop (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            $null = & $Resolve @{ Pillar = $Pillar; Name = $Unique }
            Should -Invoke -CommandName $Lister -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It -ParameterFilter { $ErrorAction -eq 'Stop' }
            Should -Invoke -CommandName $Lister -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It
        }

        It 'passes neither -Activated nor -All for -Status Eligible (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            $null = & $Resolve @{ Pillar = $Pillar; Name = $Unique; Status = 'Eligible' }
            Should -Invoke -CommandName $Lister -ModuleName Omnicit.PIM -Times 0 -Scope It -ParameterFilter { $Activated -or $All }
        }

        It 'matches a display name in another case (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            $Found = & $Resolve @{ Pillar = $Pillar; Name = $Unique.ToUpperInvariant() }
            @($Found)[0].$KeyProp | Should -Be $UniqueKey
        }

        It 'throws AmbiguousName for an ambiguous name and names both candidates (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            { & $Resolve @{ Pillar = $Pillar; Name = $Ambiguous } } | Should -Throw -ErrorId 'AmbiguousName,Resolve-OPIMSchedule'
            $Record = & $Capture @{ Pillar = $Pillar; Name = $Ambiguous }
            $Record | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidArgument)
            foreach ($Key in $AmbiguousKeys) {
                $Record.Exception.Message | Should -BeLike "*($Key)*"
            }
        }

        It 'suggests the filter the caller offers when told which it offers (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            $WithFilter = & $Capture @{ Pillar = $Pillar; Name = $Ambiguous; FilterParameter = @($FilterParameter) }
            $Without = & $Capture @{ Pillar = $Pillar; Name = $Ambiguous }
            if ($Pillar -eq 'Group') {
                # Two groups with one name and one access type: only the tab-completed form tells them apart.
                $WithFilter.Exception.Message | Should -BeLike '*tab-completed form*'
                $WithFilter.Exception.Message | Should -Not -BeLike '*-AccessType*'
            } else {
                $WithFilter.Exception.Message | Should -BeLike '*add -Scope*'
            }
            $Without.Exception.Message | Should -Not -BeLike '*-Scope*'
            $Without.Exception.Message | Should -Not -BeLike '*-AccessType*'
        }

        It 'returns exactly the filtered post when the filter resolves the ambiguity (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            $Found = & $Resolve (@{ Pillar = $Pillar; Name = $NarrowName } + $Narrow)
            @($Found).Count | Should -Be 1
            @($Found)[0].$KeyProp | Should -Be $NarrowKey
        }

        It 'throws EligibleRoleNotFound for a name nobody carries (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            { & $Resolve @{ Pillar = $Pillar; Name = $Missing } } | Should -Throw -ErrorId 'EligibleRoleNotFound,Resolve-OPIMSchedule'
            $Record = & $Capture @{ Pillar = $Pillar; Name = $Missing }
            $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
            $Record.Exception.Message | Should -BeLike "*'$Missing'*"
            $Record.TargetObject | Should -Be $Missing
        }

        It 'throws ActiveRoleNotFound with -Status Active and passes -Activated (<Pillar>)' {
            $Posts = $Sets[$Pillar].Active
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            { & $Resolve @{ Pillar = $Pillar; Name = $Missing; Status = 'Active' } } | Should -Throw -ErrorId 'ActiveRoleNotFound,Resolve-OPIMSchedule'
            Should -Invoke -CommandName $Lister -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It -ParameterFilter { $Activated -eq $true -and -not $All }
        }

        It 'returns the active post with -Status Active (<Pillar>)' {
            $Posts = $Sets[$Pillar].Active
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            $Found = & $Resolve @{ Pillar = $Pillar; Name = $Unique; Status = 'Active' }
            @($Found).Count | Should -Be 1
            @($Found)[0].$KeyProp | Should -Be $ActiveKey
        }

        It 'passes -All with -Status Both and returns one Eligible and one Active post (<Pillar>)' {
            $Posts = $Sets[$Pillar].Both
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            $Found = @(& $Resolve @{ Pillar = $Pillar; Name = $Unique; Status = 'Both' })
            Should -Invoke -CommandName $Lister -ModuleName Omnicit.PIM -Times 1 -Exactly -Scope It -ParameterFilter { $All -eq $true -and -not $Activated }
            $Found.Count | Should -Be 2
            ($Found | ForEach-Object { $PSItem.Status } | Sort-Object) -join ',' | Should -Be 'Active,Eligible'
            ($Found | ForEach-Object { $PSItem.$KeyProp } | Sort-Object) -join ',' | Should -Be ((@($UniqueKey, $ActiveKey) | Sort-Object) -join ',')
        }

        It 'throws AmbiguousName with -Status Both when two Eligible posts match (<Pillar>)' {
            $Posts = $Sets[$Pillar].Both
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            { & $Resolve @{ Pillar = $Pillar; Name = $Ambiguous; Status = 'Both' } } | Should -Throw -ErrorId 'AmbiguousName,Resolve-OPIMSchedule'
            $Record = & $Capture @{ Pillar = $Pillar; Name = $Ambiguous; Status = 'Both' }
            $Record.Exception.Message | Should -BeLike '*matches 2 eligible or active*'
        }

        It 'throws AmbiguousName with -Status Both when two Active posts match (<Pillar>)' {
            $Posts = $Sets[$Pillar].BothTwoActive
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            { & $Resolve @{ Pillar = $Pillar; Name = $Unique; Status = 'Both' } } | Should -Throw -ErrorId 'AmbiguousName,Resolve-OPIMSchedule'
        }

        It 'returns the post for the old form (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            $Found = & $Resolve @{ Pillar = $Pillar; Name = $OldForm }
            @($Found).Count | Should -Be 1
            @($Found)[0].$KeyProp | Should -Be $OldKey
        }

        It 'returns the post for the old form of a name with parentheses (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            $Found = & $Resolve @{ Pillar = $Pillar; Name = $ParenForm }
            @($Found).Count | Should -Be 1
            @($Found)[0].$KeyProp | Should -Be $ParenKey
        }

        It 'returns the post whose display name holds an apostrophe (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            $Found = & $Resolve @{ Pillar = $Pillar; Name = $Apostrophe }
            @($Found).Count | Should -Be 1
            @($Found)[0].$KeyProp | Should -Be $ApostropheKey
        }

        It "throws the listing's own error as itself and never reports it as not found (<Pillar>)" {
            # OPIM-12: the mock writes the record a listing writes for a failed read. It takes its
            # preference from an explicit -ErrorAction, as a listing does.
            Mock -ModuleName Omnicit.PIM $Lister {
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            { & $Resolve @{ Pillar = $Pillar; Name = $Unique } } | Should -Throw -ErrorId 'Forbidden*'
            $Record = & $Capture @{ Pillar = $Pillar; Name = $Unique }
            $Record | Should -BeOfType [System.Management.Automation.ErrorRecord] -Because 'a listing that cannot be read must stop the resolution'
            $Record.Exception.Message | Should -Be 'Forbidden: denied'
            $Record.FullyQualifiedErrorId | Should -Not -BeLike '*NotFound*'
        }

        It "throws the listing's own error for -Status Active and Both too (<Pillar>)" {
            Mock -ModuleName Omnicit.PIM $Lister {
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            { & $Resolve @{ Pillar = $Pillar; Name = $Unique; Status = 'Active' } } | Should -Throw -ErrorId 'Forbidden*'
            { & $Resolve @{ Pillar = $Pillar; Name = $Unique; Status = 'Both' } } | Should -Throw -ErrorId 'Forbidden*'
        }

        It 'refuses a scope with a trailing slash at binding and lists nothing (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            { & $Resolve @{ Pillar = $Pillar; Name = $Unique; Scope = '/subscriptions/sub-001/' } } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            Should -Invoke -CommandName $Lister -ModuleName Omnicit.PIM -Times 0 -Scope It
        }

        It 'refuses an empty scope at binding (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            { & $Resolve @{ Pillar = $Pillar; Name = $Unique; Scope = '' } } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError*'
        }

        It 'says in the binding error which scope ends with a slash (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            { & $Resolve @{ Pillar = $Pillar; Name = $Unique; Scope = '/subscriptions/sub-001/' } } |
                Should -Throw -ExpectedMessage "*The scope '/subscriptions/sub-001/' ends with '/'*"
        }
    }

    Context 'When the pillar has scopes' -ForEach @(
        @{
            Pillar = 'Directory'; Lister = 'Get-OPIMDirectoryRole'; KeyProp = 'id'
            Name = 'Message Center Privacy Reader'; Elsewhere = '/administrativeUnits/au-001'; ElsewhereKey = 'elig-003'
        }
        @{
            Pillar = 'Azure'; Lister = 'Get-OPIMAzureRole'; KeyProp = 'Name'
            Name = 'Contributor'; Elsewhere = '/subscriptions/sub-001/resourceGroups/rg-one'; ElsewhereKey = 'azure-003'
        }
    ) {
        It 'throws EligibleRoleNotFound that lists the other scope when -Scope matches nothing (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            $Record = & $Capture @{ Pillar = $Pillar; Name = $Name; Scope = $Elsewhere }
            $Record.FullyQualifiedErrorId | Should -Be 'EligibleRoleNotFound,Resolve-OPIMSchedule'
            $Record.Exception.Message | Should -BeLike "*It matches at another scope:*($ElsewhereKey)*"
        }

        It 'does not list another scope when the name matches nowhere (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            $Record = & $Capture @{ Pillar = $Pillar; Name = 'Nobody Carries This'; Scope = $Elsewhere }
            $Record.FullyQualifiedErrorId | Should -Be 'EligibleRoleNotFound,Resolve-OPIMSchedule'
            $Record.Exception.Message | Should -Not -BeLike '*another scope*'
            $Record.Exception.Message | Should -BeLike '*use tab completion*'
        }

        It 'does not list another scope when no -Scope was given (<Pillar>)' {
            $Posts = $Sets[$Pillar].Eligible
            Mock -ModuleName Omnicit.PIM $Lister { $Posts }
            $Record = & $Capture @{ Pillar = $Pillar; Name = 'Nobody Carries This' }
            $Record.FullyQualifiedErrorId | Should -Be 'EligibleRoleNotFound,Resolve-OPIMSchedule'
            $Record.Exception.Message | Should -Not -BeLike '*another scope*'
        }
    }

    Context 'When the pillar is Directory and the scope is the root' {
        It 'accepts -Scope / and returns the root post' {
            $Posts = $Sets.Directory.Eligible
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { $Posts }
            $Found = & $Resolve @{ Pillar = 'Directory'; Name = 'Usage Summary Reports Reader'; Scope = '/' }
            @($Found).Count | Should -Be 1
            @($Found)[0].id | Should -Be 'elig-001'
        }

        It 'accepts an administrative unit display name as scope' {
            $Posts = $Sets.Directory.Eligible
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { $Posts }
            $Found = & $Resolve @{ Pillar = 'Directory'; Name = 'Usage Summary Reports Reader'; Scope = 'Sales AU' }
            @($Found)[0].id | Should -Be 'elig-002'
        }
    }

    Context 'When the pillar is Group' {
        It 'throws EligibleRoleNotFound that names -AccessType Owner when the user holds the group only as owner' {
            $Posts = $Sets.Group.Eligible
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $Posts }
            { & $Resolve @{ Pillar = 'Group'; Name = 'owner-only-grp' } } | Should -Throw -ErrorId 'EligibleRoleNotFound,Resolve-OPIMSchedule'
            $Record = & $Capture @{ Pillar = 'Group'; Name = 'owner-only-grp' }
            $Record.Exception.Message | Should -BeLike '*It matches as owner: add -AccessType Owner.*'
        }

        It 'returns the ownership when -AccessType owner is given' {
            $Posts = $Sets.Group.Eligible
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $Posts }
            $Found = & $Resolve @{ Pillar = 'Group'; Name = 'owner-only-grp'; AccessType = 'owner' }
            @($Found).Count | Should -Be 1
            @($Found)[0].id | Should -Be 'grp-elig-006'
        }

        It 'returns the membership for a name held as member and owner' {
            $Posts = $Sets.Group.Eligible
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $Posts }
            $Found = & $Resolve @{ Pillar = 'Group'; Name = 'opim-grp' }
            @($Found).Count | Should -Be 1
            @($Found)[0].id | Should -Be 'grp-elig-001'
        }

        It 'throws EligibleRoleNotFound that names -AccessType Member when -AccessType owner matches nothing' {
            $Posts = $Sets.Group.Eligible
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $Posts }
            $Record = & $Capture @{ Pillar = 'Group'; Name = 'unique-grp'; AccessType = 'owner' }
            $Record.FullyQualifiedErrorId | Should -Be 'EligibleRoleNotFound,Resolve-OPIMSchedule'
            $Record.Exception.Message | Should -BeLike '*It matches as member: add -AccessType Member.*'
        }

        It 'throws EligibleRoleNotFound without an access type hint when the name matches no access type' {
            $Posts = $Sets.Group.Eligible
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $Posts }
            $Record = & $Capture @{ Pillar = 'Group'; Name = 'Nobody Carries This' }
            $Record.Exception.Message | Should -Not -BeLike '*-AccessType*'
            $Record.Exception.Message | Should -BeLike '*use tab completion*'
        }

        It 'throws ActiveRoleNotFound for a group held only as owner with -Status Active' {
            $Posts = @($Sets.Group.Active)
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { $Posts }
            $Record = & $Capture @{ Pillar = 'Group'; Name = 'owner-only-grp'; Status = 'Active' }
            $Record.FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound,Resolve-OPIMSchedule'
        }
    }
}
