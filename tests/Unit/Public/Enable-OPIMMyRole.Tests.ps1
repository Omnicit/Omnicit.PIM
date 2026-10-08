BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Enable-OPIMMyRole' {
    BeforeAll {
        Mock -ModuleName Omnicit.PIM Connect-OPIM {}
        Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @() }
        Mock -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole { }
        Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @() }
        Mock -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup { }
        Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @() }
        Mock -ModuleName Omnicit.PIM Enable-OPIMAzureRole { }
    }

    Context 'When called without -TenantAlias (uses current MgGraph context)' {
        It 'calls Connect-OPIM with -IncludeARM when -AllEligible is specified' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $true
            }
        }

        

        It 'calls Get-OPIMDirectoryRole to retrieve eligible directory roles' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 1 -Scope It
        }

        It 'calls Get-OPIMEntraIDGroup to retrieve eligible group assignments' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 1 -Scope It
        }

        It 'calls Get-OPIMAzureRole to retrieve eligible Azure RBAC roles' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Scope It
        }
    }

    Context 'When eligible roles are returned (no TenantAlias)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $fakeDirectoryRole = [PSCustomObject]@{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe' }
            }
            $fakeDirectoryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')

            $fakeGroup = [PSCustomObject]@{
                id       = 'grp-elig-001'
                groupId  = 'group-id-001'
                accessId = 'member'
            }
            $fakeGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')

            $fakeAzureRole = [PSCustomObject]@{
                Name  = 'az-role-001'
                Scope = '/subscriptions/sub-001'
            }
            $fakeAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')

            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($fakeDirectoryRole) }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @($fakeGroup) }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($fakeAzureRole) }
        }

        It 'calls Enable-OPIMDirectoryRole for each eligible directory role' {
            Enable-OPIMMyRole -AllEligible -Hours 2 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Scope It
        }

        It 'calls Enable-OPIMEntraIDGroup for each eligible group assignment' {
            Enable-OPIMMyRole -AllEligible -Hours 2 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 1 -Scope It
        }

        It 'calls Enable-OPIMAzureRole for each eligible Azure role' {
            Enable-OPIMMyRole -AllEligible -Hours 2 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 1 -Scope It
        }

        It 'passes -Hours to Enable-OPIMDirectoryRole' {
            Enable-OPIMMyRole -AllEligible -Hours 3 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Scope It -ParameterFilter {
                $Hours -eq 3
            }
        }

        It 'passes -Justification when supplied' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false -Justification 'Incident response'
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Scope It -ParameterFilter {
                $Justification -eq 'Incident response'
            }
        }
    }

    Context 'When called with -TenantAlias (simple string TenantId in TenantMap)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $fakeTenantId = '00000000-0000-0000-0000-000000000001'
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ contoso = $fakeTenantId }
            }
        }

        It 'calls Connect-OPIM with the resolved TenantId' {
            Enable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $TenantId -eq $fakeTenantId
            }
        }

        It 'calls Connect-OPIM with -IncludeARM for the string form, whose Azure pillar activates every eligible Azure role' {
            Enable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It -ParameterFilter {
                $IncludeARM
            }
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 1 -Exactly -Scope It
        }
    }

    Context 'When called with -TenantAlias pointing to a hashtable config with AzureRoles' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $fakeTenantId = '00000000-0000-0000-0000-000000000002'
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    fabrikam = @{
                        TenantId   = $fakeTenantId
                        AzureRoles = @('Contributor')
                    }
                }
            }
        }

        It 'calls Connect-OPIM with the resolved TenantId' {
            Enable-OPIMMyRole -TenantAlias 'fabrikam' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $TenantId -eq $fakeTenantId
            }
        }

        It 'calls Connect-OPIM with -IncludeARM when AzureRoles are configured' {
            Enable-OPIMMyRole -TenantAlias 'fabrikam' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $true
            }
        }
    }

    Context 'When -TenantMapPath does not exist' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $false } -ParameterFilter { $Path -like '*.psd1' }
        }

        It 'writes a non-terminating error when the TenantMap file is missing' {
            $Errors = @()
            Enable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\missing.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'does not call Connect-OPIM when the TenantMap file is missing' {
            Enable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\missing.psd1' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 0 -Scope It
        }
    }

    Context 'When -TenantAlias is not found in TenantMap' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ contoso = '00000000-0000-0000-0000-000000000001' }
            }
        }

        It 'writes a non-terminating error when the alias is absent from the TenantMap' {
            $Errors = @()
            Enable-OPIMMyRole -TenantAlias 'unknown' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }
    }

    Context 'When no eligible roles or groups are found' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @() }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @() }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @() }
        }

        It 'does not call Enable-OPIMDirectoryRole when no directory roles are eligible' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 0 -Scope It
        }

        It 'does not call Enable-OPIMEntraIDGroup when no groups are eligible' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 0 -Scope It
        }

        It 'does not call Enable-OPIMAzureRole when no Azure roles are eligible' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 0 -Scope It
        }
    }

    Context 'When -Wait is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $fakeDirectoryRole = [PSCustomObject]@{
                id               = 'elig-w01'
                roleDefinitionId = 'role-def-w01'
                directoryScopeId = '/'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Security Reader' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe' }
            }
            $fakeDirectoryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($fakeDirectoryRole) }
        }

        It 'passes -Wait to Enable-OPIMDirectoryRole' {
            Enable-OPIMMyRole -AllEligible -Wait -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Scope It -ParameterFilter {
                $Wait -eq $true
            }
        }

        It 'passes -TimeoutSeconds with -Wait to Enable-OPIMDirectoryRole' {
            Enable-OPIMMyRole -AllEligible -Wait -TimeoutSeconds 120 -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Exactly -Scope It -ParameterFilter {
                $Wait -and $TimeoutSeconds -eq 120
            }
        }

        It 'passes 300 seconds to Enable-OPIMDirectoryRole when -TimeoutSeconds is not given' {
            Enable-OPIMMyRole -AllEligible -Wait -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Exactly -Scope It -ParameterFilter {
                $TimeoutSeconds -eq 300
            }
        }

        It 'passes -TimeoutSeconds to Enable-OPIMDirectoryRole for a tenant alias' {
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                @{ contoso = @{ TenantId = '00000000-0000-0000-0000-000000000003'; DirectoryRoles = @('role-def-w01') } }
            }
            Enable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -Wait -TimeoutSeconds 120
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Exactly -Scope It -ParameterFilter {
                $Wait -and $TimeoutSeconds -eq 120
            }
        }

        It 'refuses -TimeoutSeconds <Value> before anything is sent' -ForEach @(
            @{ Value = 0 }
            @{ Value = 86401 }
        ) {
            { Enable-OPIMMyRole -AllEligible -Wait -TimeoutSeconds $Value -Confirm:$false } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError,Enable-OPIMMyRole'
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 0 -Scope It
        }
    }

    Context 'When called with no TenantAlias and no AllEligible switch' {
        It 'writes a non-terminating error' {
            $Errors = @()
            Enable-OPIMMyRole -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors.Count | Should -BeGreaterThan 0
        }

        It 'does not call Connect-OPIM' {
            Enable-OPIMMyRole -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 0 -Scope It
        }

        It 'does not call any Enable-OPIM* cmdlet' {
            Enable-OPIMMyRole -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 0 -Scope It
        }
    }

    Context 'When -AllEligible is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeDirectoryRole = [PSCustomObject]@{
                id               = 'elig-all-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe' }
            }
            $FakeDirectoryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            $FakeGroup = [PSCustomObject]@{ id = 'grp-all-001'; groupId = 'group-id-001'; accessId = 'member' }
            $FakeGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
            $FakeAzureRole = [PSCustomObject]@{ Name = 'az-all-001'; Scope = '/subscriptions/sub-001' }
            $FakeAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($FakeDirectoryRole) }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @($FakeGroup) }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($FakeAzureRole) }
        }

        It 'activates all three categories when -Confirm:$false is specified' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 1 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 1 -Scope It
        }

        It 'does not activate any category when -WhatIf is specified' {
            Enable-OPIMMyRole -AllEligible -WhatIf
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 0 -Scope It
        }

        It 'calls Connect-OPIM with -IncludeARM when -AllEligible is used' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $true
            }
        }

        It 'signs in to Microsoft Graph first, then to Azure as a second sign-in' {
            # OPIM-08: two Connect-OPIM calls for the same tenant, the Graph one without -IncludeARM.
            # The mock body runs in this test file's scope, so the record lives there.
            $script:ConnectCalls = [System.Collections.Generic.List[bool]]::new()
            Mock -ModuleName Omnicit.PIM Connect-OPIM { $script:ConnectCalls.Add([bool]$IncludeARM) }
            Enable-OPIMMyRole -AllEligible -Confirm:$false
            $script:ConnectCalls | Should -Be @($false, $true)
        }

        It 'passes -DeviceCode to both sign-ins when Azure is needed' {
            Enable-OPIMMyRole -AllEligible -DeviceCode -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 2 -Exactly -Scope It -ParameterFilter {
                $DeviceCode
            }
        }
    }

    Context 'When the Graph sign-in fails' {
        # OPIM-08: a failed Graph sign-in stops the command. Nothing is listed or activated -- not
        # even in the tenant an earlier sign-in pinned -- and Azure is not signed in to. The mock
        # raises the error Connect-OPIM would carry out of Initialize-OPIMAuth; its id is set per It.
        BeforeAll {
            $FakeDirectoryRole = [PSCustomObject]@{ id = 'elig-gf-001'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/' }
            $FakeDirectoryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            $FakeGroup = [PSCustomObject]@{ id = 'grp-gf-001'; groupId = 'group-id-001'; accessId = 'member' }
            $FakeGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
            $FakeAzureRole = [PSCustomObject]@{ Name = 'az-gf-001'; Scope = '/subscriptions/sub-001' }
            $FakeAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($FakeDirectoryRole) }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @($FakeGroup) }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($FakeAzureRole) }
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ contoso = '00000000-0000-0000-0000-000000000001' }
            }
            Mock -ModuleName Omnicit.PIM Connect-OPIM {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('The sign-in failed.'),
                        $script:SignInErrorId,
                        [System.Management.Automation.ErrorCategory]::AuthenticationError,
                        $null
                    )
                )
            } -ParameterFilter { -not $IncludeARM }
        }

        It 'writes the sign-in error to its own error stream (<ErrorId>)' -ForEach @(
            @{ ErrorId = 'TenantMismatch' }
            @{ ErrorId = 'InteractiveAuthFailed' }
            @{ ErrorId = 'DeviceCodeAuthFailed' }
        ) {
            # Read the command's own error stream, not -ErrorVariable: -ErrorVariable also collects the
            # record the Connect-OPIM mock threw and the command caught, so it holds one even when the
            # command writes nothing. The caught record never reaches the stream (one record, not two).
            $script:SignInErrorId = $ErrorId
            $Out = Enable-OPIMMyRole -AllEligible -Confirm:$false -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike "$ErrorId*"
        }

        It 'lists and activates nothing (<ErrorId>)' -ForEach @(
            @{ ErrorId = 'TenantMismatch' }
            @{ ErrorId = 'InteractiveAuthFailed' }
            @{ ErrorId = 'DeviceCodeAuthFailed' }
        ) {
            $script:SignInErrorId = $ErrorId
            Enable-OPIMMyRole -AllEligible -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 0 -Scope It
            # The Azure sign-in is never attempted.
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It
        }

        It 'lists and activates nothing for a tenant alias' {
            $script:SignInErrorId = 'TenantMismatch'
            Enable-OPIMMyRole -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It
        }
    }

    Context 'When only the Azure sign-in fails' {
        # A failed Azure sign-in skips the Azure pillar only; Graph is signed in.
        BeforeAll {
            $FakeDirectoryRole = [PSCustomObject]@{ id = 'elig-af-001'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/' }
            $FakeDirectoryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            $FakeGroup = [PSCustomObject]@{ id = 'grp-af-001'; groupId = 'group-id-001'; accessId = 'member' }
            $FakeGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
            $FakeAzureRole = [PSCustomObject]@{ Name = 'az-af-001'; Scope = '/subscriptions/sub-001' }
            $FakeAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($FakeDirectoryRole) }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @($FakeGroup) }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($FakeAzureRole) }
            Mock -ModuleName Omnicit.PIM Connect-OPIM {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Azure connection failed: no account.'),
                        'AzureConnectFailed',
                        [System.Management.Automation.ErrorCategory]::AuthenticationError,
                        $null
                    )
                )
            } -ParameterFilter { $IncludeARM }
        }

        It 'writes the Azure sign-in error to its own error stream' {
            # The command's own error stream, as for the Graph sign-in: the caught record is not in it.
            $Out = Enable-OPIMMyRole -AllEligible -Confirm:$false -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'AzureConnectFailed*'
        }

        It 'goes on to activate directory roles and groups' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 1 -Exactly -Scope It
        }

        It 'skips the Azure pillar' {
            Enable-OPIMMyRole -AllEligible -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 0 -Scope It
        }
    }

    Context "When a pillar's listing fails (<Failing>, <Mode>)" -ForEach @(
        @{ Mode = 'AllEligible'; Failing = 'Directory'; Activator = 'Enable-OPIMDirectoryRole'; Others = @('Enable-OPIMEntraIDGroup', 'Enable-OPIMAzureRole') }
        @{ Mode = 'AllEligible'; Failing = 'Group'; Activator = 'Enable-OPIMEntraIDGroup'; Others = @('Enable-OPIMDirectoryRole', 'Enable-OPIMAzureRole') }
        @{ Mode = 'AllEligible'; Failing = 'Azure'; Activator = 'Enable-OPIMAzureRole'; Others = @('Enable-OPIMDirectoryRole', 'Enable-OPIMEntraIDGroup') }
        @{ Mode = 'TenantAlias'; Failing = 'Directory'; Activator = 'Enable-OPIMDirectoryRole'; Others = @('Enable-OPIMEntraIDGroup', 'Enable-OPIMAzureRole') }
        @{ Mode = 'TenantAlias'; Failing = 'Group'; Activator = 'Enable-OPIMEntraIDGroup'; Others = @('Enable-OPIMDirectoryRole', 'Enable-OPIMAzureRole') }
        @{ Mode = 'TenantAlias'; Failing = 'Azure'; Activator = 'Enable-OPIMAzureRole'; Others = @('Enable-OPIMDirectoryRole', 'Enable-OPIMEntraIDGroup') }
    ) {
        # OPIM-12: a pillar whose listing cannot be read is reported as that error and ends there:
        # nothing it read is activated, and it is never reported as "no eligible ...". The other
        # pillars still run. Every listing returns one item; the failing one writes the record a
        # listing writes for a failed read -- after its item when $script:PartialRead is set, as a
        # read that fails after its first item does. The string form of a tenant alias runs every
        # pillar, so the two modes reach all six listings. The mock takes its preference from an
        # explicit -ErrorAction and is Continue otherwise, as a listing is under the default
        # preference: a module-scoped mock body reads the test scope's preference (Stop under the
        # build), never the caller's.
        BeforeAll {
            $script:FailingListing = $Failing
            $script:PartialRead = $false
            $MyRoleParams = if ($Mode -eq 'TenantAlias') {
                @{ TenantAlias = 'contoso'; TenantMapPath = 'TestDrive:\TenantMap.psd1' }
            } else {
                @{ AllEligible = $true; Confirm = $false }
            }
            $FakeDirectoryRole = [PSCustomObject]@{ id = 'elig-lf-001'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/' }
            $FakeDirectoryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            # memberType is set as Graph sets it: the type's MemberType ScriptProperty reads
            # $this.memberType, which resolves to itself on an object without the property.
            $FakeGroup = [PSCustomObject]@{ id = 'grp-lf-001'; groupId = 'group-id-001'; accessId = 'member'; memberType = 'Direct' }
            $FakeGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
            $FakeAzureRole = [PSCustomObject]@{ Name = 'az-lf-001'; Scope = '/subscriptions/sub-001' }
            $FakeAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ contoso = '00000000-0000-0000-0000-000000000001' }
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole {
                if ($script:FailingListing -ne 'Directory') { return $FakeDirectoryRole }
                if ($script:PartialRead) { $FakeDirectoryRole }
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup {
                if ($script:FailingListing -ne 'Group') { return $FakeGroup }
                if ($script:PartialRead) { $FakeGroup }
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole {
                if ($script:FailingListing -ne 'Azure') { return $FakeAzureRole }
                if ($script:PartialRead) { $FakeAzureRole }
                $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
            }
        }

        It "writes the listing's error" {
            # The command's own error stream, not -ErrorVariable: -ErrorVariable also collects the
            # record the listing raised and the command caught.
            $script:PartialRead = $false
            $Out = Enable-OPIMMyRole @MyRoleParams -ErrorAction Continue 2>&1
            $Written = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Written.Count | Should -Be 1
            $Written[0].FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
        }

        It 'activates nothing the failed listing read' {
            $script:PartialRead = $true
            Enable-OPIMMyRole @MyRoleParams -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM $Activator -Times 0 -Scope It
        }

        It 'does not report the failed listing as no eligible roles' {
            $script:PartialRead = $false
            $Out = Enable-OPIMMyRole @MyRoleParams -ErrorAction SilentlyContinue -Verbose 4>&1
            $Said = @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match 'No eligible' })
            $Said.Count | Should -Be 0
        }

        It 'goes on to list and activate the other pillars' {
            $script:PartialRead = $true
            Enable-OPIMMyRole @MyRoleParams -ErrorAction SilentlyContinue
            foreach ($Other in $Others) {
                Should -Invoke -ModuleName Omnicit.PIM $Other -Times 1 -Exactly -Scope It
            }
        }
    }

    Context 'When -AllEligibleDirectoryRoles is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeDirectoryRole = [PSCustomObject]@{
                id               = 'elig-dr-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                roleDefinition   = [PSCustomObject]@{ displayName = 'Security Reader' }
                principal        = [PSCustomObject]@{ displayName = 'Jane Doe' }
            }
            $FakeDirectoryRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($FakeDirectoryRole) }
        }

        It 'activates only directory roles' {
            Enable-OPIMMyRole -AllEligibleDirectoryRoles -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 1 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 0 -Scope It
        }

        It 'calls Connect-OPIM without -IncludeARM' {
            # Graph only: one sign-in, and none with -IncludeARM.
            Enable-OPIMMyRole -AllEligibleDirectoryRoles -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It -ParameterFilter {
                -not $IncludeARM
            }
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 0 -Scope It -ParameterFilter { $IncludeARM }
        }

        It 'passes -DeviceCode to Connect-OPIM when specified' {
            Enable-OPIMMyRole -AllEligibleDirectoryRoles -DeviceCode -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It -ParameterFilter {
                $DeviceCode -eq $true
            }
        }

        It 'does not ask for device code mode without -DeviceCode' {
            Enable-OPIMMyRole -AllEligibleDirectoryRoles -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It -ParameterFilter {
                -not $DeviceCode
            }
        }
    }

    Context 'When -AllEligibleEntraIDGroups is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeGroup = [PSCustomObject]@{ id = 'grp-elig-002'; groupId = 'group-id-002'; accessId = 'owner' }
            $FakeGroup.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @($FakeGroup) }
        }

        It 'activates only Entra ID group assignments' {
            Enable-OPIMMyRole -AllEligibleEntraIDGroups -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 1 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 0 -Scope It
        }

        It 'calls Connect-OPIM without -IncludeARM' {
            Enable-OPIMMyRole -AllEligibleEntraIDGroups -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It -ParameterFilter {
                -not $IncludeARM
            }
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 0 -Scope It -ParameterFilter { $IncludeARM }
        }
    }

    Context 'When -AllEligibleAzureRoles is specified' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeAzureRole = [PSCustomObject]@{ Name = 'az-role-002'; Scope = '/subscriptions/sub-002' }
            $FakeAzureRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($FakeAzureRole) }
        }

        It 'activates only Azure RBAC roles' {
            Enable-OPIMMyRole -AllEligibleAzureRoles -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup -Times 0 -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Enable-OPIMAzureRole -Times 1 -Scope It
        }

        It 'calls Connect-OPIM with -IncludeARM when -AllEligibleAzureRoles is used' {
            Enable-OPIMMyRole -AllEligibleAzureRoles -Confirm:$false
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Scope It -ParameterFilter {
                $IncludeARM -eq $true
            }
        }
    }

    Context 'When -TenantAlias is used with a hashtable config that has no category lists' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            $FakeTenantId = '00000000-0000-0000-0000-000000000003'
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{ noconfig = @{ TenantId = $FakeTenantId } }
            }
        }

        It 'does not call Get-OPIMDirectoryRole when no DirectoryRoles are configured' {
            Enable-OPIMMyRole -TenantAlias 'noconfig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMDirectoryRole -Times 0 -Scope It
        }

        It 'does not call Get-OPIMEntraIDGroup when no EntraIDGroups are configured' {
            Enable-OPIMMyRole -TenantAlias 'noconfig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup -Times 0 -Scope It
        }

        It 'does not call Get-OPIMAzureRole when no AzureRoles are configured' {
            Enable-OPIMMyRole -TenantAlias 'noconfig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMAzureRole -Times 0 -Scope It
        }

        It 'signs in to Graph only when the config lists no AzureRoles' {
            Enable-OPIMMyRole -TenantAlias 'noconfig' -TenantMapPath 'TestDrive:\TenantMap.psd1' -WarningAction SilentlyContinue
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 1 -Exactly -Scope It
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 0 -Scope It -ParameterFilter { $IncludeARM }
        }
    }

    Context 'When a tenant alias lists directory roles (OPIM-10, A13)' {
        # A directory role is activated only at the scope its entry names. An entry written before
        # 0.6.0 holds the roleDefinitionId alone and means the role at '/' only.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @() }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @() }
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    oldkey  = @{ TenantId = '00000000-0000-0000-0000-000000000003'; DirectoryRoles = @('role-def-001') }
                    aukey   = @{ TenantId = '00000000-0000-0000-0000-000000000003'; DirectoryRoles = @('role-def-001|/administrativeUnits/au-001') }
                    rootkey = @{ TenantId = '00000000-0000-0000-0000-000000000003'; DirectoryRoles = @('role-def-001|/') }
                    mixed   = @{ TenantId = '00000000-0000-0000-0000-000000000003'; DirectoryRoles = @('role-def-001', 'role-def-001|/') }
                    upper   = @{ TenantId = '00000000-0000-0000-0000-000000000003'; DirectoryRoles = @('ROLE-DEF-001|/ADMINISTRATIVEUNITS/AU-001') }
                    blank   = @{ TenantId = '00000000-0000-0000-0000-000000000003'; DirectoryRoles = @('', 'role-def-001|/administrativeUnits/au-001') }
                }
            }

            $RootPost = [PSCustomObject]@{
                id = 'elig-a13-001'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/'
                roleDefinition = [PSCustomObject]@{ displayName = 'Global Administrator' }
            }
            $AuPost = [PSCustomObject]@{
                id = 'elig-a13-002'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/administrativeUnits/au-001'
                directoryScope = [PSCustomObject]@{ displayName = 'Sales AU' }
                roleDefinition = [PSCustomObject]@{ displayName = 'Global Administrator' }
            }
            $OtherPost = [PSCustomObject]@{
                id = 'elig-a13-003'; roleDefinitionId = 'role-def-002'; directoryScopeId = '/'
                roleDefinition = [PSCustomObject]@{ displayName = 'User Administrator' }
            }
            foreach ($Post in @($RootPost, $AuPost, $OtherPost)) {
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @($RootPost, $AuPost, $OtherPost) }
            Mock -ModuleName Omnicit.PIM Enable-OPIMDirectoryRole { $script:EnabledPosts.Add($Role) }
        }
        BeforeEach {
            $script:EnabledPosts = [System.Collections.Generic.List[object]]::new()
        }

        It 'activates only the role at the root for an entry without a scope' {
            Enable-OPIMMyRole -TenantAlias oldkey -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $script:EnabledPosts.Count | Should -Be 1
            $script:EnabledPosts[0].roleDefinitionId | Should -BeExactly 'role-def-001'
            $script:EnabledPosts[0].directoryScopeId | Should -BeExactly '/'
            $Errs.Count | Should -Be 0
        }

        It 'activates exactly the configured scope for a new entry' {
            Enable-OPIMMyRole -TenantAlias aukey -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $script:EnabledPosts.Count | Should -Be 1
            $script:EnabledPosts[0].roleDefinitionId | Should -BeExactly 'role-def-001'
            $script:EnabledPosts[0].directoryScopeId | Should -BeExactly '/administrativeUnits/au-001'
            $Errs.Count | Should -Be 0
        }

        It 'activates the role at the root for an entry with the root scope' {
            Enable-OPIMMyRole -TenantAlias rootkey -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $script:EnabledPosts.Count | Should -Be 1
            $script:EnabledPosts[0].id | Should -BeExactly 'elig-a13-001'
            $script:EnabledPosts[0].directoryScopeId | Should -BeExactly '/'
            $Errs.Count | Should -Be 0
        }

        It 'activates the root post once for an old and a new entry of the same role' {
            Enable-OPIMMyRole -TenantAlias mixed -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $script:EnabledPosts.Count | Should -Be 1
            $script:EnabledPosts[0].id | Should -BeExactly 'elig-a13-001'
            $Errs.Count | Should -Be 0
        }

        It 'compares the key without regard to letter case' {
            Enable-OPIMMyRole -TenantAlias upper -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $script:EnabledPosts.Count | Should -Be 1
            $script:EnabledPosts[0].id | Should -BeExactly 'elig-a13-002'
            $script:EnabledPosts[0].directoryScopeId | Should -BeExactly '/administrativeUnits/au-001'
            $Errs.Count | Should -Be 0
        }

        It 'reads a blank entry as matching nothing, writes no error and activates only the real entry' {
            Enable-OPIMMyRole -TenantAlias blank -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $script:EnabledPosts.Count | Should -Be 1
            $script:EnabledPosts[0].id | Should -BeExactly 'elig-a13-002'
        }
    }

    Context 'When a tenant alias lists groups and Azure roles' {
        # The configured entries are read through the tenant map's key helper and compared without
        # regard to letter case; a blank entry matches nothing.
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Connect-OPIM {}
            Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return @() }
            Mock -ModuleName Omnicit.PIM Test-Path { return $true } -ParameterFilter { $Path -like '*.psd1' }
            Mock -ModuleName Omnicit.PIM Import-PowerShellDataFile {
                return @{
                    grpcase = @{ TenantId = '00000000-0000-0000-0000-000000000003'; EntraIDGroups = @('GROUP-001_MEMBER') }
                    azcase  = @{ TenantId = '00000000-0000-0000-0000-000000000003'; AzureRoles = @('ELIG-AZ-001') }
                    blanks  = @{
                        TenantId      = '00000000-0000-0000-0000-000000000003'
                        EntraIDGroups = @('', 'group-002_owner')
                        AzureRoles    = @('', 'elig-az-002')
                    }
                }
            }

            $GroupMember = [PSCustomObject]@{ id = 'elig-grp-001'; groupId = 'group-001'; accessId = 'member' }
            $GroupOwner  = [PSCustomObject]@{ id = 'elig-grp-002'; groupId = 'group-001'; accessId = 'owner' }
            $GroupOther  = [PSCustomObject]@{ id = 'elig-grp-003'; groupId = 'group-002'; accessId = 'owner' }
            foreach ($Post in @($GroupMember, $GroupOwner, $GroupOther)) {
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupEligibilitySchedule')
            }
            $AzureOne = [PSCustomObject]@{ Name = 'elig-az-001'; RoleDefinitionId = 'role-az-001'; ScopeId = '/subscriptions/sub-001' }
            $AzureTwo = [PSCustomObject]@{ Name = 'elig-az-002'; RoleDefinitionId = 'role-az-002'; ScopeId = '/subscriptions/sub-001' }
            # A post whose key is empty: a blank entry matches it no more than any other post.
            $AzureNoName = [PSCustomObject]@{ Name = ''; RoleDefinitionId = 'role-az-009'; ScopeId = '/subscriptions/sub-001' }
            foreach ($Post in @($AzureOne, $AzureTwo, $AzureNoName)) {
                $Post.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureEligibilitySchedule')
            }
            Mock -ModuleName Omnicit.PIM Get-OPIMEntraIDGroup { return @($GroupMember, $GroupOwner, $GroupOther) }
            Mock -ModuleName Omnicit.PIM Get-OPIMAzureRole { return @($AzureOne, $AzureTwo, $AzureNoName) }
            Mock -ModuleName Omnicit.PIM Enable-OPIMEntraIDGroup { $script:EnabledGroups.Add($Group) }
            Mock -ModuleName Omnicit.PIM Enable-OPIMAzureRole { $script:EnabledAzure.Add($Role) }
        }
        BeforeEach {
            $script:EnabledGroups = [System.Collections.Generic.List[object]]::new()
            $script:EnabledAzure  = [System.Collections.Generic.List[object]]::new()
        }

        It 'activates only the configured group, compared without regard to letter case' {
            Enable-OPIMMyRole -TenantAlias grpcase -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $script:EnabledGroups.Count | Should -Be 1
            $script:EnabledGroups[0].id | Should -BeExactly 'elig-grp-001'
            $script:EnabledAzure.Count | Should -Be 0
        }

        It 'activates only the configured Azure role, compared without regard to letter case' {
            Enable-OPIMMyRole -TenantAlias azcase -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $script:EnabledAzure.Count | Should -Be 1
            $script:EnabledAzure[0].Name | Should -BeExactly 'elig-az-001'
            $script:EnabledGroups.Count | Should -Be 0
        }

        It 'reads a blank group or Azure entry as matching nothing, writes no error and activates only the real entries' {
            Enable-OPIMMyRole -TenantAlias blanks -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $Errs.Count | Should -Be 0
            $script:EnabledGroups.Count | Should -Be 1
            $script:EnabledGroups[0].id | Should -BeExactly 'elig-grp-003'
            $script:EnabledAzure.Count | Should -Be 1
            $script:EnabledAzure[0].Name | Should -BeExactly 'elig-az-002'
        }
    }

    Context 'The default -TenantMapPath (OPIM-21)' {
        BeforeAll {
            $Param = (Get-Command Enable-OPIMMyRole).ScriptBlock.Ast.Body.ParamBlock.Parameters |
                Where-Object { $_.Name.VariablePath.UserPath -eq 'TenantMapPath' }
            $DefaultText = $Param.DefaultValue.Extent.Text
            $ExpectedPath = if ($IsWindows) {
                "$env:USERPROFILE\.config\Omnicit.PIM\TenantMap.psd1"
            } else {
                "$HOME/.config/Omnicit.PIM/TenantMap.psd1"
            }
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            Mock -ModuleName Omnicit.PIM Test-Path { $script:SeenPaths.Add($Path); $false }
        }
        BeforeEach {
            $script:SeenPaths = [System.Collections.Generic.List[string]]::new()
        }

        It 'builds the default from $HOME' {
            $Param | Should -Not -BeNullOrEmpty
            $DefaultText | Should -BeExactly "(Join-Path `$HOME '.config/Omnicit.PIM/TenantMap.psd1')"
        }

        It 'gives the same path as before on Windows and a path under $HOME elsewhere' {
            $Actual = & ([scriptblock]::Create($DefaultText))
            $Actual | Should -BeExactly $ExpectedPath
        }

        It 'reads that path when -TenantMapPath is not given' {
            Enable-OPIMMyRole -TenantAlias 'contoso' -ErrorVariable Errs -ErrorAction SilentlyContinue
            $script:SeenPaths | Should -Contain $ExpectedPath
            $Errs[-1].FullyQualifiedErrorId | Should -BeLike 'TenantMapNotFound*'
            Should -Invoke -ModuleName Omnicit.PIM Connect-OPIM -Times 0 -Scope It
        }
    }
}
