BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Find-OPIMScheduleMatch' {
    Context 'When the pillar is Directory' {
        BeforeAll {
            # Typed fakes carry the module type name and only the properties the matcher reads.
            $Sets = InModuleScope Omnicit.PIM {
                function New-DirectoryPost {
                    param([string]$Id, [string]$Role, [string]$ScopeId = '/', [string]$ScopeName, [switch]$NoScopeObject)
                    $Post = [PSCustomObject]@{
                        id               = $Id
                        roleDefinition   = [PSCustomObject]@{ displayName = $Role }
                        directoryScopeId = $ScopeId
                        directoryScope   = if ($NoScopeObject -or -not $ScopeName) { $null } else { [PSCustomObject]@{ displayName = $ScopeName } }
                        scheduleInfo     = $null
                    }
                    $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
                    $Post
                }
                $Base = @(
                    New-DirectoryPost -Id 'elig-001' -Role 'Usage Summary Reports Reader'
                    New-DirectoryPost -Id 'elig-002' -Role 'Usage Summary Reports Reader' -ScopeId '/administrativeUnits/au-001' -ScopeName 'Sales AU'
                    New-DirectoryPost -Id 'elig-003' -Role 'Message Center Privacy Reader'
                )
                @{
                    Base      = $Base
                    EuOps     = @(New-DirectoryPost -Id 'elig-010' -Role 'Contoso Ops (EU)')
                    Tier      = @(New-DirectoryPost -Id 'elig-011' -Role 'Ops (Tier 1)')
                    Brien     = @(New-DirectoryPost -Id 'elig-012' -Role "O'Brien Reader")
                    Wildcard  = @(
                        New-DirectoryPost -Id 'elig-013' -Role 'Reader [Preview]'
                        New-DirectoryPost -Id 'elig-014' -Role 'Reader X'
                    )
                    Single    = @($Base[0])
                    NullScope = @(New-DirectoryPost -Id 'elig-020' -Role 'Usage Summary Reports Reader' -ScopeId '/administrativeUnits/au-009' -NoScopeObject)
                }
            }
        }

        It 'returns <Expected> for <Title>' -ForEach @(
            @{ Title = 'a unique display name'; Set = 'Base'; Name = 'Message Center Privacy Reader'; Filter = @{}; Expected = 'elig-003' }
            @{ Title = 'a display name in another case (both scopes are reported)'; Set = 'Base'; Name = 'usage summary reports reader'; Filter = @{}; Expected = 'elig-001,elig-002' }
            @{ Title = 'the root scope filter'; Set = 'Base'; Name = 'Usage Summary Reports Reader'; Filter = @{ Scope = '/' }; Expected = 'elig-001' }
            @{ Title = 'an administrative unit display name as scope'; Set = 'Base'; Name = 'Usage Summary Reports Reader'; Filter = @{ Scope = 'sales au' }; Expected = 'elig-002' }
            @{ Title = 'a directoryScopeId in another case'; Set = 'Base'; Name = 'Usage Summary Reports Reader'; Filter = @{ Scope = '/ADMINISTRATIVEUNITS/AU-001' }; Expected = 'elig-002' }
            @{ Title = 'the old form with an administrative unit'; Set = 'Base'; Name = 'Usage Summary Reports Reader -> Sales AU (elig-002)'; Filter = @{}; Expected = 'elig-002' }
            @{ Title = 'a key that wins over the text before it'; Set = 'Base'; Name = 'Anything (elig-001)'; Filter = @{}; Expected = 'elig-001' }
            @{ Title = 'a key in another case'; Set = 'Base'; Name = 'Anything (ELIG-003)'; Filter = @{}; Expected = 'elig-003' }
            @{ Title = 'an old-form key that the scope filter excludes'; Set = 'Base'; Name = 'Usage Summary Reports Reader (elig-001)'; Filter = @{ Scope = '/administrativeUnits/au-001' }; Expected = '' }
            @{ Title = 'a display name that ends in parentheses'; Set = 'EuOps'; Name = 'Contoso Ops (EU)'; Filter = @{}; Expected = 'elig-010' }
            @{ Title = 'the old form of a name with parentheses'; Set = 'Tier'; Name = 'Ops (Tier 1) (elig-011)'; Filter = @{}; Expected = 'elig-011' }
            @{ Title = 'a display name with an apostrophe'; Set = 'Brien'; Name = "o'brien reader"; Filter = @{}; Expected = 'elig-012' }
            @{ Title = 'a display name with brackets, which are no wildcard'; Set = 'Wildcard'; Name = 'Reader [Preview]'; Filter = @{}; Expected = 'elig-013' }
            @{ Title = 'a name with a wildcard asterisk'; Set = 'Wildcard'; Name = 'Reader*'; Filter = @{}; Expected = '' }
            @{ Title = 'a name with a leading space'; Set = 'Single'; Name = ' Usage Summary Reports Reader'; Filter = @{}; Expected = '' }
            @{ Title = 'a name with a trailing space'; Set = 'Single'; Name = 'Usage Summary Reports Reader '; Filter = @{}; Expected = '' }
            @{ Title = 'a scope name on a post whose directoryScope is null'; Set = 'NullScope'; Name = 'Usage Summary Reports Reader'; Filter = @{ Scope = 'Sales AU' }; Expected = '' }
            @{ Title = 'the synthetic root label as a scope name'; Set = 'Base'; Name = 'Message Center Privacy Reader'; Filter = @{ Scope = 'Directory' }; Expected = '' }
            @{ Title = 'a key that no listed post carries'; Set = 'Base'; Name = 'Message Center Privacy Reader (elig-999)'; Filter = @{}; Expected = '' }
            @{ Title = 'an empty name'; Set = 'Base'; Name = ''; Filter = @{}; Expected = '' }
            @{ Title = 'a name of only white space'; Set = 'Base'; Name = '   '; Filter = @{}; Expected = '' }
        ) {
            $Keys = InModuleScope Omnicit.PIM -Parameters @{ Posts = $Sets[$Set]; Name = $Name; Filter = $Filter } {
                param($Posts, $Name, $Filter)
                $Params = @{ Pillar = 'Directory'; Name = $Name; InputObject = $Posts }
                (Find-OPIMScheduleMatch @Params @Filter).id
            }
            (@($Keys) -join ',') | Should -Be $Expected
        }

        It 'returns the original objects, not copies' {
            $Same = InModuleScope Omnicit.PIM -Parameters @{ Posts = $Sets.Base } {
                param($Posts)
                $Found = @(Find-OPIMScheduleMatch -Pillar Directory -Name 'Message Center Privacy Reader' -InputObject $Posts)
                [object]::ReferenceEquals($Found[0], $Posts[2])
            }
            $Same | Should -BeTrue
        }

        It 'ignores a null entry in the list' {
            $Keys = InModuleScope Omnicit.PIM -Parameters @{ Posts = $Sets.Base } {
                param($Posts)
                (Find-OPIMScheduleMatch -Pillar Directory -Name 'Message Center Privacy Reader' -InputObject @($null, $Posts[2], $null)).id
            }
            (@($Keys) -join ',') | Should -Be 'elig-003'
        }

        It 'ignores -AccessType outside groups' {
            $Keys = InModuleScope Omnicit.PIM -Parameters @{ Posts = $Sets.Base } {
                param($Posts)
                (Find-OPIMScheduleMatch -Pillar Directory -Name 'Message Center Privacy Reader' -InputObject $Posts -AccessType owner).id
            }
            (@($Keys) -join ',') | Should -Be 'elig-003'
        }

        It 'returns nothing for an empty or null list' {
            InModuleScope Omnicit.PIM {
                @(Find-OPIMScheduleMatch -Pillar Directory -Name 'Reader' -InputObject @()).Count | Should -Be 0
                @(Find-OPIMScheduleMatch -Pillar Directory -Name 'Reader' -InputObject $null).Count | Should -Be 0
            }
        }
    }

    Context 'When the pillar is Group' {
        BeforeAll {
            # Every fake carries accessId (the matcher reads it) and memberType, as Graph returns
            # them for Omnicit.PIM.GroupEligibilitySchedule, the type these fakes carry.
            $Sets = InModuleScope Omnicit.PIM {
                function New-GroupPost {
                    param([string]$Id, [string]$GroupId, [string]$Name, [string]$AccessId)
                    $Post = [PSCustomObject]@{
                        id           = $Id
                        groupId      = $GroupId
                        accessId     = $AccessId
                        memberType   = 'direct'
                        group        = [PSCustomObject]@{ displayName = $Name }
                        scheduleInfo = $null
                    }
                    $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
                    $Post
                }
                $Both = @(
                    New-GroupPost -Id 'grp-elig-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'member'
                    New-GroupPost -Id 'grp-elig-002' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'owner'
                )
                @{
                    Both      = $Both
                    OwnerOnly = @($Both[1])
                    Twin      = @(
                        New-GroupPost -Id 'grp-elig-003' -GroupId 'g-1' -Name 'Twin' -AccessId 'member'
                        New-GroupPost -Id 'grp-elig-004' -GroupId 'g-2' -Name 'Twin' -AccessId 'member'
                    )
                }
            }
        }

        It 'returns <Expected> for <Title>' -ForEach @(
            @{ Title = 'a group name, which means the membership'; Set = 'Both'; Name = 'opim-grp'; Filter = @{}; Expected = 'grp-elig-001' }
            @{ Title = 'a group name with -AccessType owner'; Set = 'Both'; Name = 'opim-grp'; Filter = @{ AccessType = 'owner' }; Expected = 'grp-elig-002' }
            @{ Title = 'a group name with -AccessType member'; Set = 'Both'; Name = 'opim-grp'; Filter = @{ AccessType = 'member' }; Expected = 'grp-elig-001' }
            @{ Title = 'the old form of the ownership, which ignores the membership default'; Set = 'Both'; Name = 'opim-grp - owner (grp-elig-002)'; Filter = @{}; Expected = 'grp-elig-002' }
            @{ Title = 'the old form that the access type filter excludes'; Set = 'Both'; Name = 'opim-grp - owner (grp-elig-002)'; Filter = @{ AccessType = 'member' }; Expected = '' }
            @{ Title = 'a group the user holds only as owner'; Set = 'OwnerOnly'; Name = 'opim-grp'; Filter = @{}; Expected = '' }
            @{ Title = 'a group name in another case'; Set = 'Both'; Name = 'OPIM-GRP'; Filter = @{}; Expected = 'grp-elig-001' }
            @{ Title = 'two groups with the same display name (the matcher reports both)'; Set = 'Twin'; Name = 'Twin'; Filter = @{}; Expected = 'grp-elig-003,grp-elig-004' }
            @{ Title = 'two groups with the same display name and an access type filter'; Set = 'Twin'; Name = 'Twin'; Filter = @{ AccessType = 'member' }; Expected = 'grp-elig-003,grp-elig-004' }
            @{ Title = 'a scope filter, which groups ignore'; Set = 'Both'; Name = 'opim-grp'; Filter = @{ Scope = '/subscriptions/sub-001' }; Expected = 'grp-elig-001' }
        ) {
            $Keys = InModuleScope Omnicit.PIM -Parameters @{ Posts = $Sets[$Set]; Name = $Name; Filter = $Filter } {
                param($Posts, $Name, $Filter)
                $Params = @{ Pillar = 'Group'; Name = $Name; InputObject = $Posts }
                (Find-OPIMScheduleMatch @Params @Filter).id
            }
            (@($Keys) -join ',') | Should -Be $Expected
        }
    }

    Context 'When the pillar is Azure' {
        BeforeAll {
            $Sets = InModuleScope Omnicit.PIM {
                function New-AzurePost {
                    param([string]$Name, [string]$Role, [string]$ScopeId, [string]$ScopeName)
                    $Post = [PSCustomObject]@{
                        Name                      = $Name
                        RoleDefinitionDisplayName = $Role
                        ScopeId                   = $ScopeId
                        ScopeDisplayName          = $ScopeName
                    }
                    $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
                    $Post
                }
                @{
                    Base = @(
                        New-AzurePost -Name 'azure-001' -Role 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one'
                        New-AzurePost -Name 'azure-002' -Role 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-two' -ScopeName 'rg-two'
                    )
                }
            }
        }

        It 'returns <Expected> for <Title>' -ForEach @(
            @{ Title = 'a role name held at two scopes (the matcher reports both)'; Name = 'Reader'; Filter = @{}; Expected = 'azure-001,azure-002' }
            @{ Title = 'a scope in another case'; Name = 'Reader'; Filter = @{ Scope = '/subscriptions/SUB-001/resourcegroups/RG-ONE' }; Expected = 'azure-001' }
            @{ Title = 'a scope display name, which Azure does not accept'; Name = 'Reader'; Filter = @{ Scope = 'rg-one' }; Expected = '' }
            @{ Title = 'the old form'; Name = 'Reader -> rg-two (azure-002)'; Filter = @{}; Expected = 'azure-002' }
            @{ Title = 'the old form that the scope filter excludes'; Name = 'Reader -> rg-one (azure-001)'; Filter = @{ Scope = '/subscriptions/sub-001/resourceGroups/rg-two' }; Expected = '' }
        ) {
            $Keys = InModuleScope Omnicit.PIM -Parameters @{ Posts = $Sets.Base; Name = $Name; Filter = $Filter } {
                param($Posts, $Name, $Filter)
                $Params = @{ Pillar = 'Azure'; Name = $Name; InputObject = $Posts }
                (Find-OPIMScheduleMatch @Params @Filter).Name
            }
            (@($Keys) -join ',') | Should -Be $Expected
        }
    }

    Context 'When the name is unusual' {
        # The post below carries a display name equal to the blank name, so only the blank-name
        # guard keeps the matcher from returning it.
        It 'matches nothing for a blank name of <Length> characters (<Pillar>)' -ForEach @(
            @{ Pillar = 'Directory'; Blank = ''; Length = 0 }
            @{ Pillar = 'Directory'; Blank = '   '; Length = 3 }
            @{ Pillar = 'Group'; Blank = ''; Length = 0 }
            @{ Pillar = 'Group'; Blank = '   '; Length = 3 }
            @{ Pillar = 'Azure'; Blank = ''; Length = 0 }
            @{ Pillar = 'Azure'; Blank = '   '; Length = 3 }
        ) {
            $Count = InModuleScope Omnicit.PIM -Parameters @{ Pillar = $Pillar; Blank = $Blank } {
                param($Pillar, $Blank)
                $Post = [PSCustomObject]@{
                    id                        = 'elig-001'
                    Name                      = 'azure-001'
                    accessId                  = 'member'
                    roleDefinition            = [PSCustomObject]@{ displayName = $Blank }
                    directoryScopeId          = '/'
                    group                     = [PSCustomObject]@{ displayName = $Blank }
                    RoleDefinitionDisplayName = $Blank
                    ScopeId                   = '/'
                    ScopeDisplayName          = 'root'
                }
                @(Find-OPIMScheduleMatch -Pillar $Pillar -Name $Blank -InputObject @($Post)).Count
            }
            $Count | Should -Be 0
        }
    }

    # OPIM-51: -NameList answers many names from one index of the posts. Every name gets what -Name
    # returns for it, the same objects in the same order; the known answers pin the rules both sets
    # share, so a rule broken in the shared code cannot hide behind the agreement of the two sets.
    Context 'When many names are resolved at once' {
        BeforeAll {
            # Tag names each fake, so an answer can be read as the posts it holds.
            $Sets = InModuleScope Omnicit.PIM {
                function New-BatchPost {
                    param([string]$Pillar, [string]$Tag, [string]$Key, [string]$Name, [string]$ScopeId = '/', [string]$ScopeName, [string]$AccessId = 'member')
                    $Post = switch ($Pillar) {
                        'Directory' {
                            [PSCustomObject]@{
                                Tag = $Tag; id = $Key; roleDefinition = [PSCustomObject]@{ displayName = $Name }; directoryScopeId = $ScopeId
                                directoryScope = if ($ScopeName) { [PSCustomObject]@{ displayName = $ScopeName } } else { $null }; scheduleInfo = $null
                            }
                        }
                        'Group' {
                            [PSCustomObject]@{
                                Tag = $Tag; id = $Key; groupId = "g-$Name"; accessId = $AccessId; memberType = 'direct'
                                group = [PSCustomObject]@{ displayName = $Name }; scheduleInfo = $null
                            }
                        }
                        'Azure' {
                            [PSCustomObject]@{ Tag = $Tag; Name = $Key; RoleDefinitionDisplayName = $Name; ScopeId = $ScopeId; ScopeDisplayName = $ScopeName }
                        }
                    }
                    $TypeName = @{ Directory = 'DirectoryEligibilitySchedule'; Group = 'GroupEligibilitySchedule'; Azure = 'AzureEligibilitySchedule' }[$Pillar]
                    $Post.PSObject.TypeNames.Insert(0, "Omnicit.PIM.$TypeName")
                    $Post
                }
                $D1 = New-BatchPost -Pillar Directory -Tag D1 -Key 'elig-001' -Name 'Usage Summary Reports Reader'
                $D2 = New-BatchPost -Pillar Directory -Tag D2 -Key 'elig-002' -Name 'Usage Summary Reports Reader' -ScopeId '/administrativeUnits/au-001' -ScopeName 'Sales AU'
                $D3 = New-BatchPost -Pillar Directory -Tag D3 -Key 'elig-003' -Name 'Message Center Privacy Reader'
                # D4 ends in the key of D3 and sits alone at its unit; D5 shares that key at another scope.
                $D4 = New-BatchPost -Pillar Directory -Tag D4 -Key 'elig-004' -Name 'Contoso Ops (elig-003)' -ScopeId '/administrativeUnits/au-002' -ScopeName 'Ops AU'
                $D5 = New-BatchPost -Pillar Directory -Tag D5 -Key 'elig-003' -Name 'Message Center Privacy Reader' -ScopeId '/administrativeUnits/au-001' -ScopeName 'Sales AU'
                $D6 = New-BatchPost -Pillar Directory -Tag D6 -Key 'elig-006' -Name 'Contoso Ops (EU)'
                $G1 = New-BatchPost -Pillar Group -Tag G1 -Key 'grp-elig-001' -Name 'opim-grp' -AccessId 'member'
                $G2 = New-BatchPost -Pillar Group -Tag G2 -Key 'grp-elig-002' -Name 'opim-grp' -AccessId 'owner'
                $G3 = New-BatchPost -Pillar Group -Tag G3 -Key 'grp-elig-003' -Name 'owner-only' -AccessId 'owner'
                $G4 = New-BatchPost -Pillar Group -Tag G4 -Key 'grp-elig-004' -Name 'Twin' -AccessId 'member'
                $G5 = New-BatchPost -Pillar Group -Tag G5 -Key 'grp-elig-005' -Name 'Twin' -AccessId 'member'
                $A1 = New-BatchPost -Pillar Azure -Tag A1 -Key 'azure-001' -Name 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one'
                $A2 = New-BatchPost -Pillar Azure -Tag A2 -Key 'azure-002' -Name 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-two' -ScopeName 'rg-two'
                $A3 = New-BatchPost -Pillar Azure -Tag A3 -Key 'azure-003' -Name 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'Subscription One'
                $A4 = New-BatchPost -Pillar Azure -Tag A4 -Key 'azure-001' -Name 'Reader' -ScopeId '/subscriptions/sub-001' -ScopeName 'Subscription One'
                # The last post of each list is listed a second time, as the same object.
                @{
                    Directory = @($D1, $D2, $D3, $D4, $D5, $D6, $D1)
                    Group     = @($G1, $G2, $G3, $G4, $G5, $G2)
                    Azure     = @($A1, $A2, $A3, $A4, $A2)
                }
            }
        }

        It 'answers every name as -Name does, with the same objects in the same order (<Pillar>, <Title>)' -ForEach @(
            @{ Pillar = 'Directory'; Title = 'no filter'; Filter = @{}; Extra = @('', '   ', 'usage summary reports reader', 'Anything (ELIG-003)', 'No Such Role (elig-999)', 'Contoso Ops (EU)') }
            @{ Pillar = 'Directory'; Title = 'the root scope'; Filter = @{ Scope = '/' }; Extra = @('Anything (elig-002)', 'Contoso Ops (elig-003)') }
            @{ Pillar = 'Directory'; Title = 'an administrative unit by its display name'; Filter = @{ Scope = 'sales au' }; Extra = @('Contoso Ops (elig-003)', 'Usage Summary Reports Reader (elig-001)') }
            @{ Pillar = 'Directory'; Title = 'a unit without the key a name ends in'; Filter = @{ Scope = '/administrativeUnits/au-002' }; Extra = @('Contoso Ops (elig-003)', 'Message Center Privacy Reader') }
            @{ Pillar = 'Group'; Title = 'the membership default'; Filter = @{}; Extra = @('OPIM-GRP', 'owner-only', 'anything (grp-elig-002)', '   ') }
            @{ Pillar = 'Group'; Title = '-AccessType owner'; Filter = @{ AccessType = 'owner' }; Extra = @('opim-grp', 'Twin', 'anything (grp-elig-001)') }
            @{ Pillar = 'Azure'; Title = 'no filter'; Filter = @{}; Extra = @('READER', 'anything (azure-001)', '') }
            @{ Pillar = 'Azure'; Title = 'one subscription'; Filter = @{ Scope = '/subscriptions/sub-001' }; Extra = @('Reader', 'Reader -> rg-one (azure-001)') }
        ) {
            $Report = InModuleScope Omnicit.PIM -Parameters @{ Pillar = $Pillar; Posts = $Sets[$Pillar]; Filter = $Filter; Extra = $Extra } {
                param($Pillar, $Posts, $Filter, $Extra)
                $NameList = @(foreach ($Post in $Posts) {
                    $Known = Get-OPIMScheduleName -Pillar $Pillar -InputObject $Post
                    $Known.DisplayName
                    $Known.OldForm
                }) + @($Extra)
                $Answers = Find-OPIMScheduleMatch -Pillar $Pillar -NameList $NameList -InputObject $Posts @Filter
                $Matched = 0
                $Wrong = @(foreach ($Each in $NameList) {
                    $One = @(Find-OPIMScheduleMatch -Pillar $Pillar -Name $Each -InputObject $Posts @Filter)
                    $Many = @($Answers[$Each])
                    $Matched += $One.Count
                    $Same = $One.Count -eq $Many.Count
                    for ($I = 0; $Same -and $I -lt $One.Count; $I++) { $Same = [object]::ReferenceEquals($One[$I], $Many[$I]) }
                    if (-not $Same) { "'$Each': -Name $(@($One.Tag) -join ','), -NameList $(@($Many.Tag) -join ',')" }
                })
                [PSCustomObject]@{
                    Wrong    = $Wrong
                    Matched  = $Matched
                    Keys     = $Answers.Count
                    Distinct = [System.Collections.Generic.HashSet[string]]::new([string[]]$NameList, [System.StringComparer]::Ordinal).Count
                }
            }
            $Report.Wrong | Should -BeNullOrEmpty
            $Report.Matched | Should -BeGreaterThan 0
            $Report.Keys | Should -Be $Report.Distinct
        }

        It 'answers <Name> with <Expected> (<Pillar>, <Title>)' -ForEach @(
            @{ Pillar = 'Group'; Title = 'a group name means the membership'; Name = 'opim-grp'; Filter = @{}; Expected = 'G1' }
            @{ Pillar = 'Group'; Title = 'the ownership, listed twice'; Name = 'opim-grp'; Filter = @{ AccessType = 'owner' }; Expected = 'G2,G2' }
            @{ Pillar = 'Group'; Title = 'a group held only as owner'; Name = 'owner-only'; Filter = @{}; Expected = '' }
            @{ Pillar = 'Group'; Title = 'two groups with one name'; Name = 'Twin'; Filter = @{}; Expected = 'G4,G5' }
            @{ Pillar = 'Group'; Title = 'the old form, which ignores the membership default'; Name = 'opim-grp - owner (grp-elig-002)'; Filter = @{}; Expected = 'G2,G2' }
            @{ Pillar = 'Directory'; Title = 'a key in parentheses, which wins over the display name'; Name = 'Contoso Ops (elig-003)'; Filter = @{}; Expected = 'D3,D5' }
            @{ Pillar = 'Directory'; Title = 'a key under a scope filter'; Name = 'Contoso Ops (elig-003)'; Filter = @{ Scope = '/administrativeUnits/au-001' }; Expected = 'D5' }
            @{ Pillar = 'Directory'; Title = 'the display name when the scope filter excludes the key'; Name = 'Contoso Ops (elig-003)'; Filter = @{ Scope = '/administrativeUnits/au-002' }; Expected = 'D4' }
            @{ Pillar = 'Directory'; Title = 'a display name in another case, a post listed twice'; Name = 'usage summary reports reader'; Filter = @{}; Expected = 'D1,D2,D1' }
            @{ Pillar = 'Directory'; Title = 'a display name in parentheses that is no key'; Name = 'Contoso Ops (EU)'; Filter = @{}; Expected = 'D6' }
            @{ Pillar = 'Azure'; Title = 'a role name under one scope'; Name = 'Reader'; Filter = @{ Scope = '/subscriptions/sub-001' }; Expected = 'A4' }
        ) {
            $Tags = InModuleScope Omnicit.PIM -Parameters @{ Pillar = $Pillar; Posts = $Sets[$Pillar]; Name = $Name; Filter = $Filter } {
                param($Pillar, $Posts, $Name, $Filter)
                $Answers = Find-OPIMScheduleMatch -Pillar $Pillar -NameList @($Name) -InputObject $Posts @Filter
                @($Answers[$Name].Tag) -join ','
            }
            $Tags | Should -BeExactly $Expected
        }

        It 'maps a name of only white space to an empty array' {
            $Report = InModuleScope Omnicit.PIM -Parameters @{ Posts = $Sets.Directory } {
                param($Posts)
                $Answers = Find-OPIMScheduleMatch -Pillar Directory -NameList @('', '   ', 'Message Center Privacy Reader') -InputObject $Posts
                [PSCustomObject]@{
                    Empty  = '{0}:{1}' -f $Answers[''].GetType().Name, $Answers[''].Count
                    Spaces = '{0}:{1}' -f $Answers['   '].GetType().Name, $Answers['   '].Count
                    Named  = @($Answers['Message Center Privacy Reader'].Tag) -join ','
                }
            }
            $Report.Empty | Should -BeExactly 'Object[]:0'
            $Report.Spaces | Should -BeExactly 'Object[]:0'
            $Report.Named | Should -BeExactly 'D3,D5'
        }

        It 'returns one dictionary with an ordinal comparer for <Title>' -ForEach @(
            @{ Title = 'one name'; NoPosts = $false }
            @{ Title = 'an empty list of posts'; NoPosts = $true }
        ) {
            $Report = InModuleScope Omnicit.PIM -Parameters @{ Posts = $Sets.Directory; NoPosts = $NoPosts } {
                param($Posts, $NoPosts)
                $Listed = if ($NoPosts) { @() } else { $Posts }
                $One = @(Find-OPIMScheduleMatch -Pillar Directory -NameList @('x') -InputObject $Listed)
                $Cased = Find-OPIMScheduleMatch -Pillar Directory -NameList @('Message Center Privacy Reader', 'MESSAGE CENTER PRIVACY READER') -InputObject $Listed
                [PSCustomObject]@{
                    Count = $One.Count
                    Type  = $One[0].GetType().FullName
                    Keys  = @($One[0].Keys) -join '|'
                    Value = '{0}:{1}' -f $One[0]['x'].GetType().Name, $One[0]['x'].Count
                    Cased = $Cased.Count
                }
            }
            $Report.Count | Should -Be 1
            $Report.Type | Should -BeExactly ([System.Collections.Generic.Dictionary[string, object[]]]).FullName
            $Report.Keys | Should -BeExactly 'x'
            $Report.Value | Should -BeExactly 'Object[]:0'
            $Report.Cased | Should -Be 2 -Because 'an ordinal comparer keeps two names that differ only in case apart'
        }
    }
}
