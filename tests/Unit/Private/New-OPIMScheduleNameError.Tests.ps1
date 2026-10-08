BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'New-OPIMScheduleNameError' {
    BeforeAll {
        # Fakes carry every property a self-referencing ScriptProperty reads (accessId, memberType).
        $Fakes = InModuleScope Omnicit.PIM {
            $DirectoryRoot = [PSCustomObject]@{
                id = 'elig-001'; directoryScopeId = '/'; directoryScope = $null
                roleDefinition = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }
            }
            $DirectoryAu = [PSCustomObject]@{
                id = 'elig-002'; directoryScopeId = '/administrativeUnits/au-001'
                directoryScope = [PSCustomObject]@{ displayName = 'Sales AU' }
                roleDefinition = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }
            }
            $DirectoryAuAgain = [PSCustomObject]@{
                id = 'elig-004'; directoryScopeId = '/administrativeUnits/au-001'
                directoryScope = [PSCustomObject]@{ displayName = 'Sales AU' }
                roleDefinition = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }
            }
            $GroupMember = [PSCustomObject]@{
                id = 'grp-elig-001'; accessId = 'member'; memberType = 'direct'
                group = [PSCustomObject]@{ displayName = 'opim-grp' }
            }
            $GroupOwner = [PSCustomObject]@{
                id = 'grp-elig-002'; accessId = 'owner'; memberType = 'direct'
                group = [PSCustomObject]@{ displayName = 'opim-grp' }
            }
            $TwinOne = [PSCustomObject]@{
                id = 'grp-elig-003'; accessId = 'member'; memberType = 'direct'
                group = [PSCustomObject]@{ displayName = 'Twin' }
            }
            $TwinTwo = [PSCustomObject]@{
                id = 'grp-elig-004'; accessId = 'member'; memberType = 'direct'
                group = [PSCustomObject]@{ displayName = 'Twin' }
            }
            $AzureOne = [PSCustomObject]@{
                Name = 'azure-001'; RoleDefinitionDisplayName = 'Reader'
                ScopeId = '/subscriptions/sub-001/resourceGroups/rg-one'; ScopeDisplayName = 'rg-one'
            }
            $AzureTwo = [PSCustomObject]@{
                Name = 'azure-002'; RoleDefinitionDisplayName = 'Reader'
                ScopeId = '/subscriptions/sub-001/resourceGroups/rg-two'; ScopeDisplayName = 'rg-two'
            }
            # The ACTIVE posts of the same names under their instance keys, for the old form
            # 'Role (instance key)' (ActiveForm). Group instances carry the accessId and memberType
            # the group types read.
            $DirectoryActive = [PSCustomObject]@{
                id = 'inst-001'; directoryScopeId = '/'; directoryScope = $null
                roleDefinition = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }
            }
            $DirectoryActiveAu = [PSCustomObject]@{
                id = 'inst-002'; directoryScopeId = '/administrativeUnits/au-001'
                directoryScope = [PSCustomObject]@{ displayName = 'Sales AU' }
                roleDefinition = [PSCustomObject]@{ displayName = 'Usage Summary Reports Reader' }
            }
            $GroupOwnerActive = [PSCustomObject]@{
                id = 'grp-inst-002'; accessId = 'owner'; memberType = 'direct'
                group = [PSCustomObject]@{ displayName = 'opim-grp' }
            }
            $GroupMemberActive = [PSCustomObject]@{
                id = 'grp-inst-001'; accessId = 'member'; memberType = 'direct'
                group = [PSCustomObject]@{ displayName = 'opim-grp' }
            }
            $AzureActive = [PSCustomObject]@{
                Name = 'azure-inst-001'; RoleDefinitionDisplayName = 'Reader'
                ScopeId = '/subscriptions/sub-001/resourceGroups/rg-one'; ScopeDisplayName = 'rg-one'
            }
            # Candidates of a -Status Both listing carry the Status the -All listing tags them with.
            $WithStatus = {
                param($Post, $Status)
                $Copy = $Post.PSObject.Copy()
                $Copy | Add-Member -NotePropertyName Status -NotePropertyValue $Status
                $Copy
            }
            @{
                DirectoryRoot = $DirectoryRoot; DirectoryAu = $DirectoryAu; DirectoryAuAgain = $DirectoryAuAgain
                GroupMember = $GroupMember; GroupOwner = $GroupOwner; TwinOne = $TwinOne; TwinTwo = $TwinTwo
                AzureOne = $AzureOne; AzureTwo = $AzureTwo
                DirectoryActive = $DirectoryActive; DirectoryActiveAu = $DirectoryActiveAu
                GroupOwnerActive = $GroupOwnerActive; GroupMemberActive = $GroupMemberActive; AzureActive = $AzureActive
                AzureOneEligible = (& $WithStatus $AzureOne 'Eligible'); AzureTwoEligible = (& $WithStatus $AzureTwo 'Eligible')
                AzureOneActive = (& $WithStatus $AzureActive 'Active')
                AzureOneEligibleAgain = (& $WithStatus ([PSCustomObject]@{
                            Name = 'azure-004'; RoleDefinitionDisplayName = 'Reader'
                            ScopeId = '/subscriptions/sub-001/resourceGroups/rg-one'; ScopeDisplayName = 'rg-one'
                        }) 'Eligible')
                GroupMemberEligible = (& $WithStatus $GroupMember 'Eligible'); GroupOwnerEligible = (& $WithStatus $GroupOwner 'Eligible')
                GroupMemberActiveTagged = (& $WithStatus $GroupMemberActive 'Active')
                GroupMemberEligibleAgain = (& $WithStatus ([PSCustomObject]@{
                            id = 'grp-elig-009'; accessId = 'member'; memberType = 'direct'
                            group = [PSCustomObject]@{ displayName = 'opim-grp' }
                        }) 'Eligible')
            }
        }
    }

    Context 'When the name is ambiguous' {
        BeforeAll {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Directory -Name 'Usage Summary Reports Reader' `
                    -Candidate @($Fakes.DirectoryRoot, $Fakes.DirectoryAu) -FilterParameter Scope
            }
        }

        It 'returns an ErrorRecord with the id AmbiguousName' {
            $Record | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $Record.FullyQualifiedErrorId | Should -Be 'AmbiguousName'
        }

        It 'uses the category InvalidArgument' {
            $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidArgument)
        }

        It 'targets the name as given' {
            $Record.TargetObject | Should -Be 'Usage Summary Reports Reader'
        }

        It 'names every candidate in its old form with its scope' {
            $Record.Exception.Message | Should -BeLike "*'Usage Summary Reports Reader (elig-001)' at scope '/'*"
            $Record.Exception.Message | Should -BeLike "*'Usage Summary Reports Reader -> Sales AU (elig-002)' at scope '/administrativeUnits/au-001'*"
        }

        It 'counts the candidates and names the state and the noun' {
            $Record.Exception.Message | Should -BeLike "The name 'Usage Summary Reports Reader' matches 2 eligible directory roles, so it names none of them:*"
        }

        It 'suggests -Scope when the candidates differ in scope and the caller offers it' {
            $Record.Exception.Message | Should -BeLike '*They differ in scope: add -Scope*'
        }

        It 'names no candidate as the answer' {
            $Record.Exception.Message | Should -BeLike '*matches 2*'
            $Record.Exception.Message | Should -Not -BeLike '*Did you mean*'
            $Record.Exception.Message | Should -Not -BeLike '*use elig-00*'
        }

        It 'writes nothing to any stream' {
            $Out = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Azure -Name 'Reader' `
                    -Candidate @($Fakes.AzureOne, $Fakes.AzureTwo) -FilterParameter Scope -Verbose *>&1
            }
            @($Out).Count | Should -Be 1
            @($Out)[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
        }
    }

    Context 'When the caller offers no filter' {
        It 'suggests no -Scope for a directory name when -FilterParameter is empty' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Directory -Name 'Usage Summary Reports Reader' `
                    -Candidate @($Fakes.DirectoryRoot, $Fakes.DirectoryAu)
            }
            $Record.Exception.Message | Should -Not -BeLike '*-Scope*'
            $Record.Exception.Message | Should -BeLike '*Give the tab-completed form of the one you mean, as listed.'
        }

        It 'suggests no -AccessType for a group name when -FilterParameter is empty' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Group -Name 'opim-grp' `
                    -Candidate @($Fakes.GroupMember, $Fakes.GroupOwner)
            }
            $Record.Exception.Message | Should -Not -BeLike '*-AccessType*'
            $Record.Exception.Message | Should -BeLike '*tab-completed form*'
        }

        It 'suggests only the filter the caller offers (<Pillar>, <Offered>)' -ForEach @(
            @{ Pillar = 'Directory'; Offered = 'AccessType'; Candidate = @('DirectoryRoot', 'DirectoryAu'); Absent = '*-Scope*' }
            @{ Pillar = 'Azure'; Offered = 'AccessType'; Candidate = @('AzureOne', 'AzureTwo'); Absent = '*-Scope*' }
            @{ Pillar = 'Group'; Offered = 'Scope'; Candidate = @('GroupMember', 'GroupOwner'); Absent = '*-AccessType*' }
        ) {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes; Pillar = $Pillar; Offered = $Offered; Candidate = $Candidate } {
                param($Fakes, $Pillar, $Offered, $Candidate)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar $Pillar -Name 'Name' `
                    -Candidate @($Candidate | ForEach-Object { $Fakes[$PSItem] }) -FilterParameter $Offered
            }
            $Record.Exception.Message | Should -BeLike '*Give the tab-completed form of the one you mean, as listed.'
            $Record.Exception.Message | Should -Not -BeLike $Absent
        }
    }

    Context 'When groups share a name' {
        It 'does not suggest -Scope for a group, since a group has no scope' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Group -Name 'opim-grp' `
                    -Candidate @($Fakes.GroupMember) -FilterParameter Scope
            }
            $Record.Exception.Message | Should -BeLike "*'opim-grp - member (grp-elig-001)'*"
            $Record.Exception.Message | Should -Not -BeLike '*-Scope*'
        }

        It 'suggests -AccessType for two groups that differ in access type' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Group -Name 'opim-grp' `
                    -Candidate @($Fakes.GroupMember, $Fakes.GroupOwner) -FilterParameter AccessType
            }
            $Record.Exception.Message | Should -BeLike '*They differ in access type: add -AccessType Member or -AccessType Owner*'
            $Record.Exception.Message | Should -BeLike "*'opim-grp - member (grp-elig-001)'*"
            $Record.Exception.Message | Should -BeLike "*'opim-grp - owner (grp-elig-002)'*"
        }

        It 'points at the tab-completed form for two groups with the same access type' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Group -Name 'Twin' `
                    -Candidate @($Fakes.TwinOne, $Fakes.TwinTwo) -FilterParameter AccessType
            }
            $Record.Exception.Message | Should -BeLike '*tab-completed form*'
            $Record.Exception.Message | Should -Not -BeLike '*-AccessType*'
            $Record.Exception.Message | Should -BeLike "*'Twin - member (grp-elig-003)'*"
            $Record.Exception.Message | Should -BeLike "*'Twin - member (grp-elig-004)'*"
            $Record.Exception.Message | Should -Not -BeLike '*at scope*'
        }
    }

    Context 'When scopes do not tell the candidates apart' {
        It 'points at the tab-completed form when two candidates share a scope' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Directory -Name 'Usage Summary Reports Reader' `
                    -Candidate @($Fakes.DirectoryRoot, $Fakes.DirectoryAu, $Fakes.DirectoryAuAgain) -FilterParameter Scope
            }
            $Record.Exception.Message | Should -Not -BeLike '*-Scope*'
            $Record.Exception.Message | Should -BeLike '*tab-completed form*'
            $Record.Exception.Message | Should -BeLike '*matches 3 eligible directory roles*'
        }
    }

    Context 'When the pillar is Azure' {
        It 'lists both scopes and suggests -Scope' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Azure -Name 'Reader' `
                    -Candidate @($Fakes.AzureOne, $Fakes.AzureTwo) -FilterParameter Scope
            }
            $Record.Exception.Message | Should -BeLike "*'Reader -> rg-one (azure-001)' at scope '/subscriptions/sub-001/resourceGroups/rg-one'*"
            $Record.Exception.Message | Should -BeLike "*'Reader -> rg-two (azure-002)' at scope '/subscriptions/sub-001/resourceGroups/rg-two'*"
            $Record.Exception.Message | Should -BeLike '*matches 2 eligible Azure roles*'
            $Record.Exception.Message | Should -BeLike '*add -Scope*'
        }
    }

    Context 'When the state or the identity differs' {
        It 'says active for -Status Active' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Group -Name 'Twin' -Status Active `
                    -Candidate @($Fakes.TwinOne, $Fakes.TwinTwo)
            }
            $Record.Exception.Message | Should -BeLike '*matches 2 active group assignments*'
        }

        It 'says eligible or active for -Status Both' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId EligibleRoleNotFound -Pillar Directory -Name 'Nobody' -Status Both
            }
            $Record.Exception.Message | Should -BeLike 'No eligible or active directory role matches the name ''Nobody''.*'
        }

        It 'says identity for -Identity' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Azure -Name 'azure-001' -Identity `
                    -Candidate @($Fakes.AzureOne, $Fakes.AzureTwo)
            }
            $Record.Exception.Message | Should -BeLike "The identity 'azure-001' matches 2*"
            $Record.Exception.Message | Should -Not -BeLike 'The name*'
        }
    }

    Context 'When no post matches' {
        It 'returns <ErrorId> with the category ObjectNotFound and the name as target' -ForEach @(
            @{ ErrorId = 'EligibleRoleNotFound'; Status = 'Eligible' }
            @{ ErrorId = 'ActiveRoleNotFound'; Status = 'Active' }
        ) {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ ErrorId = $ErrorId; Status = $Status } {
                param($ErrorId, $Status)
                New-OPIMScheduleNameError -ErrorId $ErrorId -Pillar Directory -Name 'Nobody' -Status $Status
            }
            $Record | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $Record.FullyQualifiedErrorId | Should -Be $ErrorId
            $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
            $Record.TargetObject | Should -Be 'Nobody'
        }

        It 'says no eligible role matches the name' {
            $Record = InModuleScope Omnicit.PIM {
                New-OPIMScheduleNameError -ErrorId EligibleRoleNotFound -Pillar Azure -Name 'Nobody'
            }
            $Record.Exception.Message | Should -BeLike "No eligible Azure role matches the name 'Nobody'.*"
        }

        It 'names the listing with -Activated for -Status Active' {
            $Record = InModuleScope Omnicit.PIM {
                New-OPIMScheduleNameError -ErrorId ActiveRoleNotFound -Pillar Azure -Name 'Nobody' -Status Active
            }
            $Record.Exception.Message | Should -BeLike '*Get-OPIMAzureRole -Activated*'
            $Record.Exception.Message | Should -BeLike "No active Azure role matches the name 'Nobody'.*"
        }

        It 'names the listing without -Activated for -Status Eligible (<Pillar>)' -ForEach @(
            @{ Pillar = 'Directory'; Listing = 'Get-OPIMDirectoryRole' }
            @{ Pillar = 'Group'; Listing = 'Get-OPIMEntraIDGroup' }
            @{ Pillar = 'Azure'; Listing = 'Get-OPIMAzureRole' }
        ) {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Pillar = $Pillar } {
                param($Pillar)
                New-OPIMScheduleNameError -ErrorId EligibleRoleNotFound -Pillar $Pillar -Name 'Nobody'
            }
            $Record.Exception.Message | Should -BeLike "*as $Listing shows it, or use tab completion."
            $Record.Exception.Message | Should -Not -BeLike '*-Activated*'
        }

        It 'says the identity is not found with -Identity' {
            $Record = InModuleScope Omnicit.PIM {
                New-OPIMScheduleNameError -ErrorId EligibleRoleNotFound -Pillar Group -Name 'grp-elig-999' -Identity
            }
            $Record.Exception.Message | Should -BeLike "No eligible group assignment matches the identity 'grp-elig-999'.*"
        }

        It 'names -AccessType Owner when the name matches as owner' {
            $Record = InModuleScope Omnicit.PIM {
                New-OPIMScheduleNameError -ErrorId EligibleRoleNotFound -Pillar Group -Name 'opim-grp' -OtherAccessType owner
            }
            $Record.Exception.Message | Should -BeLike '*It matches as owner: add -AccessType Owner.*'
            $Record.Exception.Message | Should -Not -BeLike '*or use tab completion*'
        }

        It 'names -AccessType Member when the name matches as member' {
            $Record = InModuleScope Omnicit.PIM {
                New-OPIMScheduleNameError -ErrorId EligibleRoleNotFound -Pillar Group -Name 'opim-grp' -OtherAccessType member
            }
            $Record.Exception.Message | Should -BeLike '*It matches as member: add -AccessType Member.*'
        }

        It 'says the post is already deactivated with -AlreadyInactive' {
            $Record = InModuleScope Omnicit.PIM {
                New-OPIMScheduleNameError -ErrorId ActiveRoleNotFound -Pillar Directory -Name 'Usage Summary Reports Reader' `
                    -Status Active -AlreadyInactive
            }
            $Record.Exception.Message | Should -BeLike '*already deactivated*'
            $Record.Exception.Message | Should -Not -BeLike '*or use tab completion*'
        }

        It 'says an activation that has not finished yet may be the reason, with -AlreadyInactive (I1)' {
            # An activation pending approval or still provisioning is no active instance yet, so
            # "already deactivated" alone would be false for it.
            $Record = InModuleScope Omnicit.PIM {
                New-OPIMScheduleNameError -ErrorId ActiveRoleNotFound -Pillar Directory -Name 'Usage Summary Reports Reader' `
                    -Status Active -AlreadyInactive
            }
            $Record.Exception.Message | Should -BeLike '*It is eligible but not active: it is already deactivated, or its activation has not finished yet.*'
        }

        It 'says nothing of the sort without -AlreadyInactive' {
            $Record = InModuleScope Omnicit.PIM {
                New-OPIMScheduleNameError -ErrorId ActiveRoleNotFound -Pillar Directory -Name 'Nobody' -Status Active
            }
            $Record.Exception.Message | Should -Not -BeLike '*already deactivated*'
            $Record.Exception.Message | Should -Not -BeLike '*activation has not finished*'
        }

        It 'lists the other scope with -OtherScope' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId EligibleRoleNotFound -Pillar Azure -Name 'Reader' `
                    -OtherScope @($Fakes.AzureOne, $Fakes.AzureTwo)
            }
            $Record.Exception.Message | Should -BeLike "*It matches at another scope: 'Reader -> rg-one (azure-001)' at scope '/subscriptions/sub-001/resourceGroups/rg-one'; 'Reader -> rg-two (azure-002)' at scope '/subscriptions/sub-001/resourceGroups/rg-two'.*"
            $Record.Exception.Message | Should -Not -BeLike '*or use tab completion*'
        }

        It 'lists the other scope of a directory role with its administrative unit' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId EligibleRoleNotFound -Pillar Directory -Name 'Usage Summary Reports Reader' `
                    -OtherScope @($Fakes.DirectoryAu)
            }
            $Record.Exception.Message | Should -BeLike "*'Usage Summary Reports Reader -> Sales AU (elig-002)' at scope '/administrativeUnits/au-001'*"
        }

        It 'lists a group that matches elsewhere without a scope' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId EligibleRoleNotFound -Pillar Group -Name 'opim-grp' `
                    -OtherScope @($Fakes.GroupOwner)
            }
            $Record.Exception.Message | Should -BeLike "*'opim-grp - owner (grp-elig-002)'*"
            $Record.Exception.Message | Should -Not -BeLike '*at scope*'
        }

        It 'keeps the not-found parts together in one message' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId EligibleRoleNotFound -Pillar Group -Name 'opim-grp' `
                    -OtherAccessType owner -OtherScope @($Fakes.GroupOwner)
            }
            $Record.Exception.Message | Should -BeLike "No eligible group assignment matches the name 'opim-grp'. It matches as owner: add -AccessType Owner. It matches at another scope:*"
        }
    }

    Context 'When the name is active under another key (OPIM-40 guard)' {
        It 'names the active form of the post (<Pillar>, <Post>)' -ForEach @(
            @{ Pillar = 'Directory'; Post = 'DirectoryActive'; Form = 'Usage Summary Reports Reader (inst-001)' }
            @{ Pillar = 'Directory'; Post = 'DirectoryActiveAu'; Form = 'Usage Summary Reports Reader -> Sales AU (inst-002)' }
            @{ Pillar = 'Group'; Post = 'GroupMemberActive'; Form = 'opim-grp - member (grp-inst-001)' }
            @{ Pillar = 'Azure'; Post = 'AzureActive'; Form = 'Reader -> rg-one (azure-inst-001)' }
        ) {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes; Pillar = $Pillar; Post = $Post } {
                param($Fakes, $Pillar, $Post)
                New-OPIMScheduleNameError -ErrorId ActiveRoleNotFound -Pillar $Pillar -Name 'Name (elig-001)' `
                    -Status Active -ActiveForm @($Fakes[$Post])
            }
            $Record.FullyQualifiedErrorId | Should -Be 'ActiveRoleNotFound'
            $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ObjectNotFound)
            $Record.Exception.Message | Should -BeLike "*It is active as '$Form'; use that name or its display name.*"
            $Record.Exception.Message | Should -Not -BeLike '*already deactivated*'
            $Record.Exception.Message | Should -Not -BeLike '*or use tab completion*'
        }

        It 'lists every active form when several posts are active under that label' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId ActiveRoleNotFound -Pillar Directory -Name 'Usage Summary Reports Reader (elig-001)' `
                    -Status Active -ActiveForm @($Fakes.DirectoryActive, $Fakes.DirectoryActiveAu)
            }
            $Record.Exception.Message | Should -BeLike "*It is active as 'Usage Summary Reports Reader (inst-001)', 'Usage Summary Reports Reader -> Sales AU (inst-002)'; use one of those names.*"
        }

        It 'says the display name needs -AccessType Owner for a group held as owner' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId ActiveRoleNotFound -Pillar Group -Name 'opim-grp - owner (grp-elig-002)' `
                    -Status Active -ActiveForm @($Fakes.GroupOwnerActive)
            }
            $Record.Exception.Message | Should -BeLike "*It is active as 'opim-grp - owner (grp-inst-002)'; use that name or its display name with -AccessType Owner.*"
        }

        It 'does not say -AccessType Owner for a group held as member' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId ActiveRoleNotFound -Pillar Group -Name 'opim-grp - member (grp-elig-001)' `
                    -Status Active -ActiveForm @($Fakes.GroupMemberActive)
            }
            $Record.Exception.Message | Should -Not -BeLike '*-AccessType*'
        }

        It 'does not also say the post is already deactivated when it is given the active form' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId ActiveRoleNotFound -Pillar Directory -Name 'Usage Summary Reports Reader (elig-001)' `
                    -Status Active -AlreadyInactive -ActiveForm @($Fakes.DirectoryActive)
            }
            $Record.Exception.Message | Should -BeLike "*It is active as 'Usage Summary Reports Reader (inst-001)'*"
            $Record.Exception.Message | Should -Not -BeLike '*already deactivated*'
            $Record.Exception.Message | Should -Not -BeLike '*eligible but not active*'
        }

        It 'keeps the already-deactivated sentence when the active form is empty' {
            $Record = InModuleScope Omnicit.PIM {
                New-OPIMScheduleNameError -ErrorId ActiveRoleNotFound -Pillar Directory -Name 'Usage Summary Reports Reader' `
                    -Status Active -AlreadyInactive -ActiveForm @()
            }
            $Record.Exception.Message | Should -BeLike '*already deactivated*'
            $Record.Exception.Message | Should -Not -BeLike '*It is active as*'
        }

        It 'adds no active-form sentence without -ActiveForm' {
            $Record = InModuleScope Omnicit.PIM {
                New-OPIMScheduleNameError -ErrorId ActiveRoleNotFound -Pillar Directory -Name 'Nobody' -Status Active
            }
            $Record.Exception.Message | Should -Not -BeLike '*It is active as*'
        }
    }

    Context 'When -Status Both lists an eligible and an active post (M5)' {
        It 'suggests -Scope when the scopes differ within each state, though an eligible and an active post share one' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Azure -Name 'Reader' -Status Both `
                    -Candidate @($Fakes.AzureOneEligible, $Fakes.AzureTwoEligible, $Fakes.AzureOneActive) -FilterParameter Scope
            }
            $Record.Exception.Message | Should -BeLike '*matches 3 eligible or active Azure roles*'
            $Record.Exception.Message | Should -BeLike '*They differ in scope: add -Scope*'
        }

        It 'points at the tab-completed form when two eligible posts share a scope' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Azure -Name 'Reader' -Status Both `
                    -Candidate @($Fakes.AzureOneEligible, $Fakes.AzureOneEligibleAgain, $Fakes.AzureOneActive) -FilterParameter Scope
            }
            $Record.Exception.Message | Should -Not -BeLike '*-Scope*'
            $Record.Exception.Message | Should -BeLike '*tab-completed form*'
        }

        It 'suggests -AccessType when the access types differ within each state' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Group -Name 'opim-grp' -Status Both `
                    -Candidate @($Fakes.GroupMemberEligible, $Fakes.GroupOwnerEligible, $Fakes.GroupMemberActiveTagged) -FilterParameter AccessType
            }
            $Record.Exception.Message | Should -BeLike '*They differ in access type: add -AccessType Member or -AccessType Owner*'
        }

        It 'points at the tab-completed form when two eligible groups share an access type' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Group -Name 'opim-grp' -Status Both `
                    -Candidate @($Fakes.GroupMemberEligible, $Fakes.GroupMemberEligibleAgain, $Fakes.GroupMemberActiveTagged) -FilterParameter AccessType
            }
            $Record.Exception.Message | Should -Not -BeLike '*-AccessType*'
            $Record.Exception.Message | Should -BeLike '*tab-completed form*'
        }
    }

    Context 'When the value is a configured entry of a tenant alias (OPIM-17)' {
        # Disable-OPIMMyRole reads its entries from TenantMap.psd1 and matches each against every active
        # post: an entry that matches several is refused. The record says "configured entry", and the
        # hint names the Disable- cmdlet of the pillar, since an entry offers neither -Scope nor -AccessType.
        It 'says configured entry instead of name and counts the active candidates (<Pillar>)' -ForEach @(
            @{ Pillar = 'Directory'; Noun = 'directory roles'; Candidate = @('DirectoryActive', 'DirectoryActiveAu') }
            @{ Pillar = 'Group'; Noun = 'group assignments'; Candidate = @('GroupMemberActive', 'GroupOwnerActive') }
            @{ Pillar = 'Azure'; Noun = 'Azure roles'; Candidate = @('AzureOne', 'AzureTwo') }
        ) {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes; Pillar = $Pillar; Candidate = $Candidate } {
                param($Fakes, $Pillar, $Candidate)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar $Pillar -Name 'entry-001' -Status Active `
                    -Candidate @($Candidate | ForEach-Object { $Fakes[$PSItem] }) -Configuration
            }
            $Record.Exception.Message | Should -BeLike "The configured entry 'entry-001' matches 2 active $Noun, so it names none of them:*"
            $Record.Exception.Message | Should -Not -BeLike 'The name*'
            $Record.FullyQualifiedErrorId | Should -Be 'AmbiguousName'
            $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidArgument)
            $Record.TargetObject | Should -Be 'entry-001'
        }

        It 'names the Disable- cmdlet of the pillar and its tab-completed form in the hint (<Pillar>)' -ForEach @(
            @{ Pillar = 'Directory'; Noun = 'DirectoryRole'; Candidate = @('DirectoryActive', 'DirectoryActiveAu') }
            @{ Pillar = 'Group'; Noun = 'EntraIDGroup'; Candidate = @('GroupMemberActive', 'GroupOwnerActive') }
            @{ Pillar = 'Azure'; Noun = 'AzureRole'; Candidate = @('AzureOne', 'AzureTwo') }
        ) {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes; Pillar = $Pillar; Candidate = $Candidate } {
                param($Fakes, $Pillar, $Candidate)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar $Pillar -Name 'entry-001' -Status Active `
                    -Candidate @($Candidate | ForEach-Object { $Fakes[$PSItem] }) -Configuration
            }
            $Record.Exception.Message | Should -BeLike "*. Deactivate the one you mean with Disable-OPIM$Noun and its tab-completed form, as listed."
        }

        It 'lists every candidate in its old form with its scope' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Directory -Name 'role-def-001' -Status Active `
                    -Candidate @($Fakes.DirectoryActive, $Fakes.DirectoryActiveAu) -Configuration
            }
            $Record.Exception.Message | Should -BeLike "*'Usage Summary Reports Reader (inst-001)' at scope '/'*"
            $Record.Exception.Message | Should -BeLike "*'Usage Summary Reports Reader -> Sales AU (inst-002)' at scope '/administrativeUnits/au-001'*"
        }

        It 'suggests no filter parameter, though the caller offers one and the candidates differ in it (<Pillar>)' -ForEach @(
            @{ Pillar = 'Directory'; Offered = 'Scope'; Candidate = @('DirectoryActive', 'DirectoryActiveAu') }
            @{ Pillar = 'Azure'; Offered = 'Scope'; Candidate = @('AzureOne', 'AzureTwo') }
            @{ Pillar = 'Group'; Offered = 'AccessType'; Candidate = @('GroupMemberActive', 'GroupOwnerActive') }
        ) {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes; Pillar = $Pillar; Offered = $Offered; Candidate = $Candidate } {
                param($Fakes, $Pillar, $Offered, $Candidate)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar $Pillar -Name 'entry-001' -Status Active `
                    -Candidate @($Candidate | ForEach-Object { $Fakes[$PSItem] }) -FilterParameter $Offered -Configuration
            }
            $Record.Exception.Message | Should -Not -BeLike '*They differ in*'
            $Record.Exception.Message | Should -Not -BeLike '*add -Scope*'
            $Record.Exception.Message | Should -Not -BeLike '*add -AccessType*'
        }

        It 'leaves the message of a plain name unchanged without -Configuration' {
            $Record = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Directory -Name 'role-def-001' -Status Active `
                    -Candidate @($Fakes.DirectoryActive, $Fakes.DirectoryActiveAu)
            }
            $Record.Exception.Message | Should -BeLike "The name 'role-def-001' matches 2 active directory roles, so it names none of them:*"
            $Record.Exception.Message | Should -Not -BeLike '*configured entry*'
            $Record.Exception.Message | Should -Not -BeLike '*Deactivate the one you mean*'
        }

        It 'changes nothing in the records that find nothing' {
            $Plain = InModuleScope Omnicit.PIM {
                New-OPIMScheduleNameError -ErrorId ActiveRoleNotFound -Pillar Directory -Name 'role-def-009' -Status Active
            }
            $Configured = InModuleScope Omnicit.PIM {
                New-OPIMScheduleNameError -ErrorId ActiveRoleNotFound -Pillar Directory -Name 'role-def-009' -Status Active -Configuration
            }
            $Configured.Exception.Message | Should -BeExactly $Plain.Exception.Message
            $Configured.Exception.Message | Should -BeLike "No active directory role matches the name 'role-def-009'.*"
        }

        It 'writes nothing to any stream' {
            $Out = InModuleScope Omnicit.PIM -Parameters @{ Fakes = $Fakes } {
                param($Fakes)
                New-OPIMScheduleNameError -ErrorId AmbiguousName -Pillar Directory -Name 'role-def-001' -Status Active `
                    -Candidate @($Fakes.DirectoryActive, $Fakes.DirectoryActiveAu) -Configuration -Verbose *>&1
            }
            @($Out).Count | Should -Be 1
            @($Out)[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
        }
    }
}
