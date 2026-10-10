BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMCompletionText' {
    Context 'When the pillar is Directory' {
        BeforeAll {
            # None of the ScriptProperties of Omnicit.PIM.DirectoryEligibilitySchedule reads its own
            # name, so these typed fakes need only the properties the helper reads.
            $Sets = InModuleScope Omnicit.PIM {
                function New-DirectoryPost {
                    param([string]$Id, [string]$Role, [string]$ScopeId = '/', [string]$ScopeName)
                    $Post = [PSCustomObject]@{
                        id               = $Id
                        roleDefinition   = [PSCustomObject]@{ displayName = $Role }
                        directoryScopeId = $ScopeId
                        directoryScope   = if ($ScopeName) { [PSCustomObject]@{ displayName = $ScopeName } } else { $null }
                        scheduleInfo     = $null
                    }
                    $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
                    $Post
                }
                $Usage   = New-DirectoryPost -Id 'elig-001' -Role 'Usage Summary Reports Reader'
                $AuUsage = New-DirectoryPost -Id 'elig-002' -Role 'Usage Summary Reports Reader' -ScopeId '/administrativeUnits/au-001' -ScopeName 'Sales AU'
                $Message = New-DirectoryPost -Id 'elig-003' -Role 'Message Center Privacy Reader'
                @{
                    Unique   = @($Usage, $Message)
                    Base     = @($Usage, $AuUsage, $Message)
                    Single   = @($Usage)
                    Brien    = @(New-DirectoryPost -Id 'elig-012' -Role "O'Brien Reader")
                    Wildcard = @(
                        New-DirectoryPost -Id 'elig-013' -Role 'Reader [Preview]'
                        New-DirectoryPost -Id 'elig-014' -Role 'Reader X'
                    )
                    Twins    = @(
                        New-DirectoryPost -Id 'elig-015' -Role "O'Brien Reader"
                        New-DirectoryPost -Id 'elig-016' -Role "O'Brien Reader" -ScopeId '/administrativeUnits/au-002' -ScopeName "Ops' AU"
                    )
                }
            }
        }

        It 'offers <Title>' -ForEach @(
            @{ Title = 'the bare display names when each is unique'; Set = 'Unique'; Word = ''; Bound = $null; Expected = @("'Usage Summary Reports Reader'", "'Message Center Privacy Reader'") }
            @{ Title = 'the old form of an ambiguous name and the bare name of a unique one'; Set = 'Base'; Word = ''; Bound = $null; Expected = @("'Usage Summary Reports Reader (elig-001)'", "'Usage Summary Reports Reader -> Sales AU (elig-002)'", "'Message Center Privacy Reader'") }
            @{ Title = 'the bare names under the root scope, with the administrative unit post left out'; Set = 'Base'; Word = ''; Bound = @{ Scope = '/' }; Expected = @("'Usage Summary Reports Reader'", "'Message Center Privacy Reader'") }
            @{ Title = 'the bare name of the administrative unit post under its scope id'; Set = 'Base'; Word = ''; Bound = @{ Scope = '/administrativeUnits/au-001' }; Expected = @("'Usage Summary Reports Reader'") }
            @{ Title = 'the bare name of the administrative unit post under its display name'; Set = 'Base'; Word = ''; Bound = @{ Scope = 'sales au' }; Expected = @("'Usage Summary Reports Reader'") }
            @{ Title = 'nothing under a scope no post has'; Set = 'Base'; Word = ''; Bound = @{ Scope = '/administrativeUnits/au-999' }; Expected = @() }
            @{ Title = 'the old forms when -Scope is bound to an empty value'; Set = 'Base'; Word = ''; Bound = @{ Scope = '' }; Expected = @("'Usage Summary Reports Reader (elig-001)'", "'Usage Summary Reports Reader -> Sales AU (elig-002)'", "'Message Center Privacy Reader'") }
            @{ Title = 'a name with an apostrophe doubled'; Set = 'Brien'; Word = ''; Bound = $null; Expected = @("'O''Brien Reader'") }
            @{ Title = 'a name with an apostrophe doubled for a partly typed, quoted word'; Set = 'Brien'; Word = "'O''Br"; Bound = $null; Expected = @("'O''Brien Reader'") }
            @{ Title = 'a name with an apostrophe for a word that ends in the first half of a doubled apostrophe'; Set = 'Brien'; Word = "'O''"; Bound = $null; Expected = @("'O''Brien Reader'") }
            @{ Title = 'an old form with every apostrophe doubled'; Set = 'Twins'; Word = ''; Bound = $null; Expected = @("'O''Brien Reader (elig-015)'", "'O''Brien Reader -> Ops'' AU (elig-016)'") }
            @{ Title = 'the bare name for a partly typed, quoted word'; Set = 'Single'; Word = "'Usage Su"; Bound = $null; Expected = @("'Usage Summary Reports Reader'") }
            @{ Title = 'the bare name for a partly typed word in another case'; Set = 'Single'; Word = 'usage SU'; Bound = $null; Expected = @("'Usage Summary Reports Reader'") }
            @{ Title = 'the bare name for a partly typed, double-quoted word'; Set = 'Single'; Word = '"Usage Su'; Bound = $null; Expected = @("'Usage Summary Reports Reader'") }
            @{ Title = 'the bare name for a word that is the whole name in quotes'; Set = 'Single'; Word = "'Usage Summary Reports Reader'"; Bound = $null; Expected = @("'Usage Summary Reports Reader'") }
            @{ Title = 'nothing for a word no name starts with'; Set = 'Single'; Word = 'Reports'; Bound = $null; Expected = @() }
            @{ Title = 'only the old form that starts with the word'; Set = 'Base'; Word = 'Usage Summary Reports Reader (elig-0'; Bound = $null; Expected = @("'Usage Summary Reports Reader (elig-001)'") }
            @{ Title = 'both old forms for a word that is their common start'; Set = 'Base'; Word = 'usage'; Bound = $null; Expected = @("'Usage Summary Reports Reader (elig-001)'", "'Usage Summary Reports Reader -> Sales AU (elig-002)'") }
            @{ Title = 'only the name that has the brackets of the word, which are no wildcard'; Set = 'Wildcard'; Word = 'Reader ['; Bound = $null; Expected = @("'Reader [Preview]'") }
            @{ Title = 'nothing for a word with an asterisk'; Set = 'Wildcard'; Word = 'Reader*'; Bound = $null; Expected = @() }
            @{ Title = 'nothing for a word of one question mark'; Set = 'Wildcard'; Word = 'Reader ?'; Bound = $null; Expected = @() }
            @{ Title = 'nothing for a word of one asterisk'; Set = 'Wildcard'; Word = '*'; Bound = $null; Expected = @() }
        ) {
            $Got = @(InModuleScope Omnicit.PIM -Parameters @{ Posts = $Sets[$Set]; Word = $Word; Bound = $Bound } {
                param($Posts, $Word, $Bound)
                Get-OPIMCompletionText -Pillar Directory -InputObject $Posts -WordToComplete $Word -FakeBoundParameters $Bound
            })
            $Got.Count | Should -Be $Expected.Count
            ($Got -join '|') | Should -Be ($Expected -join '|')
        }

        It 'ignores -AccessType outside groups' {
            $Got = @(InModuleScope Omnicit.PIM -Parameters @{ Posts = $Sets.Base } {
                param($Posts)
                Get-OPIMCompletionText -Pillar Directory -InputObject $Posts -FakeBoundParameters @{ AccessType = 'Owner' }
            })
            $Got.Count | Should -Be 3
        }

        It 'offers each of its texts as a string' {
            $Types = @(InModuleScope Omnicit.PIM -Parameters @{ Posts = $Sets.Base } {
                param($Posts)
                Get-OPIMCompletionText -Pillar Directory -InputObject $Posts | ForEach-Object { $PSItem.GetType().FullName }
            })
            @($Types | Sort-Object -Unique) | Should -Be 'System.String'
        }
    }

    Context 'When the pillar is Group' {
        BeforeAll {
            # Every fake carries accessId and memberType, as Graph returns them for
            # Omnicit.PIM.GroupEligibilitySchedule.
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
                @{
                    Both      = @(
                        New-GroupPost -Id 'grp-elig-001' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'member'
                        New-GroupPost -Id 'grp-elig-002' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'owner'
                    )
                    OwnerOnly = @(New-GroupPost -Id 'grp-elig-002' -GroupId 'g-1' -Name 'opim-grp' -AccessId 'owner')
                    Twin      = @(
                        New-GroupPost -Id 'grp-elig-003' -GroupId 'g-1' -Name 'Twin' -AccessId 'member'
                        New-GroupPost -Id 'grp-elig-004' -GroupId 'g-2' -Name 'Twin' -AccessId 'member'
                    )
                    Brien     = @(New-GroupPost -Id 'grp-elig-005' -GroupId 'g-3' -Name "O'Brien Team" -AccessId 'member')
                }
            }
        }

        It 'offers <Title>' -ForEach @(
            @{ Title = 'the bare name of the membership and the old form of the ownership'; Set = 'Both'; Word = ''; Bound = $null; Expected = @("'opim-grp'", "'opim-grp - owner (grp-elig-002)'") }
            @{ Title = 'the bare name of the ownership alone under -AccessType Owner'; Set = 'Both'; Word = ''; Bound = @{ AccessType = 'Owner' }; Expected = @("'opim-grp'") }
            @{ Title = 'the bare name of the membership alone under -AccessType member'; Set = 'Both'; Word = ''; Bound = @{ AccessType = 'member' }; Expected = @("'opim-grp'") }
            @{ Title = 'the default for an -AccessType that is no access type'; Set = 'Both'; Word = ''; Bound = @{ AccessType = 'bogus' }; Expected = @("'opim-grp'", "'opim-grp - owner (grp-elig-002)'") }
            @{ Title = 'the default when -AccessType is bound to an empty value'; Set = 'Both'; Word = ''; Bound = @{ AccessType = '' }; Expected = @("'opim-grp'", "'opim-grp - owner (grp-elig-002)'") }
            @{ Title = 'the default for a -Scope, which groups ignore'; Set = 'Both'; Word = ''; Bound = @{ Scope = '/subscriptions/sub-001' }; Expected = @("'opim-grp'", "'opim-grp - owner (grp-elig-002)'") }
            @{ Title = 'the old form of a group the user holds only as owner'; Set = 'OwnerOnly'; Word = ''; Bound = $null; Expected = @("'opim-grp - owner (grp-elig-002)'") }
            @{ Title = 'the bare name of a group the user holds only as owner under -AccessType Owner'; Set = 'OwnerOnly'; Word = ''; Bound = @{ AccessType = 'Owner' }; Expected = @("'opim-grp'") }
            @{ Title = 'nothing for a group the user holds only as owner under -AccessType Member'; Set = 'OwnerOnly'; Word = ''; Bound = @{ AccessType = 'Member' }; Expected = @() }
            @{ Title = 'the old forms of two groups with the same name'; Set = 'Twin'; Word = ''; Bound = $null; Expected = @("'Twin - member (grp-elig-003)'", "'Twin - member (grp-elig-004)'") }
            @{ Title = 'the old forms of two groups with the same name under -AccessType member'; Set = 'Twin'; Word = ''; Bound = @{ AccessType = 'member' }; Expected = @("'Twin - member (grp-elig-003)'", "'Twin - member (grp-elig-004)'") }
            @{ Title = 'the old form of the ownership for a word that starts it'; Set = 'Both'; Word = "'opim-grp - o"; Bound = $null; Expected = @("'opim-grp - owner (grp-elig-002)'") }
            @{ Title = 'a group name with an apostrophe doubled'; Set = 'Brien'; Word = "'O''Br"; Bound = $null; Expected = @("'O''Brien Team'") }
        ) {
            $Got = @(InModuleScope Omnicit.PIM -Parameters @{ Posts = $Sets[$Set]; Word = $Word; Bound = $Bound } {
                param($Posts, $Word, $Bound)
                Get-OPIMCompletionText -Pillar Group -InputObject $Posts -WordToComplete $Word -FakeBoundParameters $Bound
            })
            $Got.Count | Should -Be $Expected.Count
            ($Got -join '|') | Should -Be ($Expected -join '|')
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
                $Reader1 = New-AzurePost -Name 'azure-001' -Role 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-one' -ScopeName 'rg-one'
                $Reader2 = New-AzurePost -Name 'azure-002' -Role 'Reader' -ScopeId '/subscriptions/sub-001/resourceGroups/rg-two' -ScopeName 'rg-two'
                @{
                    Base   = @($Reader1, $Reader2)
                    Mixed  = @(
                        $Reader1, $Reader2
                        New-AzurePost -Name 'azure-003' -Role 'Contributor' -ScopeId '/subscriptions/sub-001' -ScopeName 'Subscription One'
                    )
                    Root   = @(
                        New-AzurePost -Name 'azure-004' -Role 'Reader' -ScopeId '/' -ScopeName 'Tenant Root'
                        $Reader1
                    )
                }
            }
        }

        It 'offers <Title>' -ForEach @(
            @{ Title = 'the old forms of a role held at two scopes'; Set = 'Base'; Bound = $null; Command = ''; Expected = @("'Reader -> rg-one (azure-001)'", "'Reader -> rg-two (azure-002)'") }
            @{ Title = 'the bare name under the scope of one of them'; Set = 'Base'; Bound = @{ Scope = '/subscriptions/sub-001/resourceGroups/rg-one' }; Command = 'Enable-OPIMAzureRole'; Expected = @("'Reader'") }
            @{ Title = 'the bare name under a scope in another case'; Set = 'Base'; Bound = @{ Scope = '/subscriptions/SUB-001/resourcegroups/RG-TWO' }; Command = 'Enable-OPIMAzureRole'; Expected = @("'Reader'") }
            @{ Title = 'the old forms on a Get- command, where the root scope filters nothing'; Set = 'Base'; Bound = @{ Scope = '/' }; Command = 'Get-OPIMAzureRole'; Expected = @("'Reader -> rg-one (azure-001)'", "'Reader -> rg-two (azure-002)'") }
            @{ Title = 'the old forms on a Get- command in another case, where the root scope filters nothing'; Set = 'Base'; Bound = @{ Scope = '/' }; Command = 'get-opimazurerole'; Expected = @("'Reader -> rg-one (azure-001)'", "'Reader -> rg-two (azure-002)'") }
            @{ Title = 'nothing on an Enable- command, where the root scope is a scope of its own'; Set = 'Base'; Bound = @{ Scope = '/' }; Command = 'Enable-OPIMAzureRole'; Expected = @() }
            @{ Title = 'only the post at the root scope on a Disable- command'; Set = 'Root'; Bound = @{ Scope = '/' }; Command = 'Disable-OPIMAzureRole'; Expected = @("'Reader'") }
            @{ Title = 'the bare name of a role held at one scope and the old forms of one held at two'; Set = 'Mixed'; Bound = $null; Command = ''; Expected = @("'Reader -> rg-one (azure-001)'", "'Reader -> rg-two (azure-002)'", "'Contributor'") }
            @{ Title = 'nothing under a scope no post has'; Set = 'Base'; Bound = @{ Scope = '/subscriptions/sub-999' }; Command = 'Enable-OPIMAzureRole'; Expected = @() }
            @{ Title = 'the old forms when no command name is given'; Set = 'Base'; Bound = $null; Command = $null; Expected = @("'Reader -> rg-one (azure-001)'", "'Reader -> rg-two (azure-002)'") }
        ) {
            $Got = @(InModuleScope Omnicit.PIM -Parameters @{ Posts = $Sets[$Set]; Bound = $Bound; Command = $Command } {
                param($Posts, $Bound, $Command)
                Get-OPIMCompletionText -Pillar Azure -InputObject $Posts -FakeBoundParameters $Bound -CommandName $Command
            })
            $Got.Count | Should -Be $Expected.Count
            ($Got -join '|') | Should -Be ($Expected -join '|')
        }

        It 'offers a bare name that the cmdlet resolves to exactly the post it stands for' {
            $Resolved = InModuleScope Omnicit.PIM -Parameters @{ Posts = $Sets.Mixed } {
                param($Posts)
                $Bound = @{ Scope = '/subscriptions/sub-001/resourceGroups/rg-one' }
                foreach ($Text in Get-OPIMCompletionText -Pillar Azure -InputObject $Posts -FakeBoundParameters $Bound -CommandName 'Enable-OPIMAzureRole') {
                    $Name = $Text.Substring(1, $Text.Length - 2).Replace("''", "'")
                    $Found = @(Find-OPIMScheduleMatch -Pillar Azure -Name $Name -InputObject $Posts -Scope $Bound.Scope)
                    "$Name=$(@($Found.Name) -join ',')"
                }
            }
            @($Resolved) | Should -Be @('Reader=azure-001')
        }
    }

    Context 'When the completion text is checked against the matcher' {
        BeforeAll {
            $Sets = InModuleScope Omnicit.PIM {
                function New-DirectoryPost {
                    param([string]$Id, [string]$Role, [string]$ScopeId = '/', [string]$ScopeName)
                    [PSCustomObject]@{
                        id               = $Id
                        roleDefinition   = [PSCustomObject]@{ displayName = $Role }
                        directoryScopeId = $ScopeId
                        directoryScope   = if ($ScopeName) { [PSCustomObject]@{ displayName = $ScopeName } } else { $null }
                    }
                }
                @{
                    Posts = @(
                        New-DirectoryPost -Id 'elig-001' -Role 'Usage Summary Reports Reader'
                        New-DirectoryPost -Id 'elig-002' -Role 'Usage Summary Reports Reader' -ScopeId '/administrativeUnits/au-001' -ScopeName 'Sales AU'
                        New-DirectoryPost -Id 'elig-003' -Role 'Message Center Privacy Reader'
                        New-DirectoryPost -Id 'elig-004' -Role "O'Brien Reader"
                        New-DirectoryPost -Id 'elig-005' -Role 'Reader [Preview]'
                        New-DirectoryPost -Id 'elig-006' -Role 'Contoso Ops (EU)'
                    )
                }
            }
        }

        # A completion text must name exactly the post it stands for: typed back without its quotes
        # and with its apostrophes undoubled, the matcher finds that one post and no other.
        It 'names one post each, for every text offered' {
            $Pairs = InModuleScope Omnicit.PIM -Parameters @{ Posts = $Sets.Posts } {
                param($Posts)
                foreach ($Text in Get-OPIMCompletionText -Pillar Directory -InputObject $Posts) {
                    $Name = $Text.Substring(1, $Text.Length - 2).Replace("''", "'")
                    $Found = @(Find-OPIMScheduleMatch -Pillar Directory -Name $Name -InputObject $Posts)
                    "$Name=$(@($Found.id).Count)"
                }
            }
            @($Pairs).Count | Should -Be 6
            @($Pairs | Where-Object { $PSItem -notmatch '=1$' }) | Should -BeNullOrEmpty
        }
    }

    # PowerShell's tokenizer reads U+2018, U+2019, U+201A and U+201B as single quotes, as it does the
    # straight one, so a display name that holds one must have it doubled too, or the text ends at it.
    # The test file stays ASCII: the quotes are built from their code points.
    Context 'When a display name holds a typographic single quote (I2)' -ForEach @(
        @{ Code = 0x2018; Hex = '2018' }
        @{ Code = 0x2019; Hex = '2019' }
        @{ Code = 0x201A; Hex = '201A' }
        @{ Code = 0x201B; Hex = '201B' }
    ) {
        BeforeAll {
            $Quote = [string][char]$Code
            $DisplayName = "Partner${Quote}s Admins"
            $Posts = @{
                Directory = @([PSCustomObject]@{
                        id = 'elig-017'; directoryScopeId = '/'; directoryScope = $null
                        roleDefinition = [PSCustomObject]@{ displayName = $DisplayName }
                    })
                Group     = @([PSCustomObject]@{
                        id = 'grp-elig-017'; accessId = 'member'; memberType = 'direct'
                        group = [PSCustomObject]@{ displayName = $DisplayName }
                    })
                Azure     = @([PSCustomObject]@{
                        Name = 'azure-017'; RoleDefinitionDisplayName = $DisplayName
                        ScopeId = '/subscriptions/sub-001'; ScopeDisplayName = 'sub-001'
                    })
            }
        }

        It 'doubles the quote and parses back to the display name as one string (U+<Hex>, <Pillar>)' -ForEach @(
            @{ Pillar = 'Directory' }
            @{ Pillar = 'Group' }
            @{ Pillar = 'Azure' }
        ) {
            $Got = @(InModuleScope Omnicit.PIM -Parameters @{ Pillar = $Pillar; Posts = $Posts[$Pillar] } {
                param($Pillar, $Posts)
                Get-OPIMCompletionText -Pillar $Pillar -InputObject $Posts
            })
            $Got.Count | Should -Be 1
            $Got[0] | Should -BeExactly "'Partner${Quote}${Quote}s Admins'"

            $Tokens = $null
            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseInput("Enable-OPIMDirectoryRole $($Got[0])", [ref]$Tokens, [ref]$Errors)
            @($Errors).Count | Should -Be 0
            $Command = $Ast.Find({ param($Node) $Node -is [System.Management.Automation.Language.CommandAst] }, $true)
            $Command.CommandElements.Count | Should -Be 2
            $Command.CommandElements[1] | Should -BeOfType [System.Management.Automation.Language.StringConstantExpressionAst]
            $Command.CommandElements[1].Value | Should -BeExactly $DisplayName
        }

        It 'completes the word the engine hands over, with the quote undoubled (U+<Hex>)' {
            $Got = @(InModuleScope Omnicit.PIM -Parameters @{ Posts = $Posts.Directory; Word = "'Partner${Quote}s Ad" } {
                param($Posts, $Word)
                Get-OPIMCompletionText -Pillar Directory -InputObject $Posts -WordToComplete $Word
            })
            ($Got -join '|') | Should -BeExactly "'Partner${Quote}${Quote}s Admins'"
        }

        It 'completes the word as typed, with the quote doubled (U+<Hex>)' {
            $Got = @(InModuleScope Omnicit.PIM -Parameters @{ Posts = $Posts.Directory; Word = "'Partner${Quote}${Quote}s Ad" } {
                param($Posts, $Word)
                Get-OPIMCompletionText -Pillar Directory -InputObject $Posts -WordToComplete $Word
            })
            ($Got -join '|') | Should -BeExactly "'Partner${Quote}${Quote}s Admins'"
        }

        It 'completes a word that ends in the doubled quote (U+<Hex>)' {
            $Got = @(InModuleScope Omnicit.PIM -Parameters @{ Posts = $Posts.Directory; Word = "'Partner${Quote}${Quote}" } {
                param($Posts, $Word)
                Get-OPIMCompletionText -Pillar Directory -InputObject $Posts -WordToComplete $Word
            })
            ($Got -join '|') | Should -BeExactly "'Partner${Quote}${Quote}s Admins'"
        }

        It 'offers nothing for a word with another quote kind in place of it (U+<Hex>)' {
            $Other = if ($Code -eq 0x2019) { [string][char]0x2018 } else { [string][char]0x2019 }
            $Got = @(InModuleScope Omnicit.PIM -Parameters @{ Posts = $Posts.Directory; Word = "'Partner${Other}s Ad" } {
                param($Posts, $Word)
                Get-OPIMCompletionText -Pillar Directory -InputObject $Posts -WordToComplete $Word
            })
            $Got.Count | Should -Be 0
        }
    }

    Context 'When the input is unusual' {
        It 'offers nothing for an empty list' {
            InModuleScope Omnicit.PIM {
                @(Get-OPIMCompletionText -Pillar Directory -InputObject @()).Count | Should -Be 0
                @(Get-OPIMCompletionText -Pillar Group -InputObject @()).Count | Should -Be 0
                @(Get-OPIMCompletionText -Pillar Azure -InputObject @()).Count | Should -Be 0
            }
        }

        It 'offers nothing for a null list' {
            InModuleScope Omnicit.PIM {
                @(Get-OPIMCompletionText -Pillar Directory -InputObject $null).Count | Should -Be 0
            }
        }

        It 'ignores a null entry in the list' {
            $Got = @(InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{
                    id               = 'elig-001'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }
                    directoryScopeId = '/'
                }
                Get-OPIMCompletionText -Pillar Directory -InputObject @($null, $Post, $null)
            })
            $Got | Should -Be @("'Usage Summary Reports Reader'")
        }

        It 'accepts a null set of bound parameters and an empty word' {
            $Got = @(InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{
                    id               = 'elig-001'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }
                    directoryScopeId = '/'
                }
                Get-OPIMCompletionText -Pillar Directory -InputObject @($Post) -WordToComplete '' -FakeBoundParameters $null -CommandName ''
            })
            $Got | Should -Be @("'Usage Summary Reports Reader'")
        }
    }

    # The matcher ignores a filter that does not apply to the pillar and compares an access type
    # without regard to case, so the results cannot show what the helper hands on. A stand-in matcher
    # that answers nothing records it: the first call of the helper is its check of a post's own
    # old form, which carries the typed filters.
    Context 'When the typed filters are handed to the matcher' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Find-OPIMScheduleMatch {}
        }

        It 'hands -AccessType to the matcher in lower case for a group' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{ id = 'grp-elig-001'; accessId = 'owner'; group = [PSCustomObject]@{ displayName = 'opim-grp' } }
                $null = Get-OPIMCompletionText -Pillar Group -InputObject @($Post) -FakeBoundParameters @{ AccessType = 'Owner' }
            }
            Should -Invoke -ModuleName Omnicit.PIM Find-OPIMScheduleMatch -ParameterFilter { $AccessType -ceq 'owner' } -Times 1 -Exactly -Scope It
        }

        It 'hands no -Scope to the matcher for a group' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{ id = 'grp-elig-001'; accessId = 'owner'; group = [PSCustomObject]@{ displayName = 'opim-grp' } }
                $null = Get-OPIMCompletionText -Pillar Group -InputObject @($Post) -FakeBoundParameters @{ Scope = '/subscriptions/sub-001' }
            }
            Should -Invoke -ModuleName Omnicit.PIM Find-OPIMScheduleMatch -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Find-OPIMScheduleMatch -ParameterFilter { $PesterBoundParameters.ContainsKey('Scope') } -Times 0 -Scope It
        }

        It 'hands no -AccessType to the matcher outside groups' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{ id = 'elig-001'; roleDefinition = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }; directoryScopeId = '/' }
                $null = Get-OPIMCompletionText -Pillar Directory -InputObject @($Post) -FakeBoundParameters @{ AccessType = 'Owner' }
            }
            Should -Invoke -ModuleName Omnicit.PIM Find-OPIMScheduleMatch -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Find-OPIMScheduleMatch -ParameterFilter { $PesterBoundParameters.ContainsKey('AccessType') } -Times 0 -Scope It
        }

        It 'hands no -Scope to the matcher for an empty one' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{ id = 'elig-001'; roleDefinition = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }; directoryScopeId = '/' }
                $null = Get-OPIMCompletionText -Pillar Directory -InputObject @($Post) -FakeBoundParameters @{ Scope = '' }
            }
            Should -Invoke -ModuleName Omnicit.PIM Find-OPIMScheduleMatch -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Find-OPIMScheduleMatch -ParameterFilter { $PesterBoundParameters.ContainsKey('Scope') } -Times 0 -Scope It
        }

        It 'hands the typed -Scope to the matcher for a directory role' {
            InModuleScope Omnicit.PIM {
                $Post = [PSCustomObject]@{ id = 'elig-001'; roleDefinition = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }; directoryScopeId = '/' }
                $null = Get-OPIMCompletionText -Pillar Directory -InputObject @($Post) -FakeBoundParameters @{ Scope = '/administrativeUnits/au-001' }
            }
            Should -Invoke -ModuleName Omnicit.PIM Find-OPIMScheduleMatch -ParameterFilter { $Scope -ceq '/administrativeUnits/au-001' } -Times 1 -Exactly -Scope It
        }
    }

    Context 'When strict mode is on' {
        It 'completes an empty word' {
            $Got = @(InModuleScope Omnicit.PIM {
                Set-StrictMode -Version Latest
                $Post = [PSCustomObject]@{
                    id               = 'elig-001'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }
                    directoryScopeId = '/'
                    directoryScope   = $null
                }
                Get-OPIMCompletionText -Pillar Directory -InputObject @($Post) -WordToComplete ''
            })
            $Got | Should -Be @("'Usage Summary Reports Reader'")
        }

        It 'ignores a null entry in the list' {
            $Got = @(InModuleScope Omnicit.PIM {
                Set-StrictMode -Version Latest
                $Post = [PSCustomObject]@{
                    id               = 'elig-001'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }
                    directoryScopeId = '/'
                    directoryScope   = $null
                }
                Get-OPIMCompletionText -Pillar Directory -InputObject @($null, $Post, $null)
            })
            $Got | Should -Be @("'Usage Summary Reports Reader'")
        }
    }

    Context 'When the helper is called' {
        It 'reaches no command that can reach a tenant or the network' {
            $Calls = InModuleScope Omnicit.PIM {
                $Ast = (Get-Command Get-OPIMCompletionText).ScriptBlock.Ast
                $Found = $Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.CommandAst] }, $true)
                @($Found | ForEach-Object { $PSItem.GetCommandName() } | Where-Object { $PSItem } | Sort-Object -Unique)
            }
            $Allowed = @('Find-OPIMScheduleMatch', 'Get-OPIMScheduleName', 'Where-Object')
            @($Calls | Where-Object { $PSItem -notin $Allowed }) | Should -BeNullOrEmpty
            $Calls | Should -Contain 'Find-OPIMScheduleMatch'
            $Calls | Should -Contain 'Get-OPIMScheduleName'
        }
    }
}
