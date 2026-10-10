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
}
