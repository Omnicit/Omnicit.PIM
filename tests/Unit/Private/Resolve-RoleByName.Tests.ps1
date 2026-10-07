BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Resolve-RoleByName' {
    Context 'When -AD is specified and a matching role exists' {
        It 'calls Get-OPIMDirectoryRole to resolve the schedule' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMDirectoryRole {
                    [PSCustomObject]@{ id = 'abc-123'; roleDefinition = [PSCustomObject]@{ displayName = 'Global Administrator' } }
                }
                Resolve-RoleByName -RoleName 'Global Administrator (abc-123)' -AD
                Should -Invoke Get-OPIMDirectoryRole -Times 1 -Scope It
            }
        }

        It 'returns the role whose id matches the extracted schedule id' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMDirectoryRole {
                    [PSCustomObject]@{ id = 'abc-123'; roleDefinition = [PSCustomObject]@{ displayName = 'Global Administrator' } }
                }
                $result = Resolve-RoleByName -RoleName 'Global Administrator (abc-123)' -AD
                $result.id | Should -Be 'abc-123'
            }
        }
    }

    Context 'When -Group is specified and a matching group exists' {
        It 'calls Get-OPIMEntraIDGroup to resolve the schedule' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMEntraIDGroup {
                    [PSCustomObject]@{ id = 'grp-001'; displayName = 'Security Admins' }
                }
                Resolve-RoleByName -RoleName 'Security Admins (grp-001)' -Group
                Should -Invoke Get-OPIMEntraIDGroup -Times 1 -Scope It
            }
        }

        It 'returns the group whose id matches the extracted schedule id' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMEntraIDGroup {
                    [PSCustomObject]@{ id = 'grp-001'; displayName = 'Security Admins' }
                }
                $result = Resolve-RoleByName -RoleName 'Security Admins (grp-001)' -Group
                $result.id | Should -Be 'grp-001'
            }
        }
    }

    Context 'When neither -AD nor -Group is specified (Azure RBAC default)' {
        It 'calls Get-OPIMAzureRole to resolve the schedule' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMAzureRole {
                    [PSCustomObject]@{ Name = 'azure-001'; displayName = 'Contributor' }
                }
                Resolve-RoleByName -RoleName 'Contributor (azure-001)'
                Should -Invoke Get-OPIMAzureRole -Times 1 -Scope It
            }
        }

        It 'returns the role whose Name matches the extracted schedule id' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMAzureRole {
                    [PSCustomObject]@{ Name = 'azure-001'; displayName = 'Contributor' }
                }
                $result = Resolve-RoleByName -RoleName 'Contributor (azure-001)'
                $result.Name | Should -Be 'azure-001'
            }
        }
    }

    Context 'When -Activated is specified' {
        It 'passes -Activated to the underlying Get-OPIMDirectoryRole call' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMDirectoryRole {
                    [PSCustomObject]@{ id = 'abc-123' }
                }
                Resolve-RoleByName -RoleName 'Global Administrator (abc-123)' -AD -Activated
                Should -Invoke Get-OPIMDirectoryRole -Times 1 -Scope It -ParameterFilter { $Activated -eq $true }
            }
        }
    }

    Context 'When RoleName is null' {
        It 'throws indicating null RoleName is a bug' {
            InModuleScope Omnicit.PIM {
                { Resolve-RoleByName -RoleName $null } | Should -Throw '*RoleName was null*'
            }
        }
    }

    Context 'When no role matching the schedule ID is found' {
        It 'throws mentioning the schedule ID was not found' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMDirectoryRole { return @() }
                { Resolve-RoleByName -RoleName 'Global Administrator (abc-123)' -AD } |
                    Should -Throw '*was not found*'
            }
        }
    }

    Context 'When multiple roles share the same schedule ID' {
        It 'throws mentioning multiple roles were found' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMDirectoryRole {
                    @(
                        [PSCustomObject]@{ id = 'abc-123' },
                        [PSCustomObject]@{ id = 'abc-123' }
                    )
                }
                { Resolve-RoleByName -RoleName 'Global Administrator (abc-123)' -AD } |
                    Should -Throw '*Multiple roles found*'
            }
        }
    }

    Context 'When the listing fails' {
        # OPIM-12: a listing that cannot be read is thrown as itself, so the calling cmdlet stops as
        # it does for a name it cannot resolve. The mock writes the record a listing writes for a
        # failed read (a Graph 403 here); it never says the schedule was not found.
        # The mock takes its preference from an explicit -ErrorAction and is Continue otherwise, as a
        # listing is under the default preference: a module-scoped mock body reads the test scope's
        # preference (Stop under the build), never the caller's.
        It "throws the listing's error as itself (<Pillar>)" -ForEach @(
            @{ Lister = 'Get-OPIMDirectoryRole'; Pillar = 'AD' }
            @{ Lister = 'Get-OPIMEntraIDGroup'; Pillar = 'Group' }
            @{ Lister = 'Get-OPIMAzureRole'; Pillar = 'Azure' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Lister = $Lister; Pillar = $Pillar } {
                param($Lister, $Pillar)
                Mock $Lister {
                    $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                            [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
                }
                $Switches = @{ AD = $Pillar -eq 'AD'; Group = $Pillar -eq 'Group' }
                { Resolve-RoleByName -RoleName 'Role (id-1)' @Switches } | Should -Throw -ErrorId 'Forbidden*'
            }
        }

        It 'never reports a failed listing as not found (<Pillar>)' -ForEach @(
            @{ Lister = 'Get-OPIMDirectoryRole'; Pillar = 'AD' }
            @{ Lister = 'Get-OPIMEntraIDGroup'; Pillar = 'Group' }
            @{ Lister = 'Get-OPIMAzureRole'; Pillar = 'Azure' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Lister = $Lister; Pillar = $Pillar } {
                param($Lister, $Pillar)
                Mock $Lister {
                    $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                            [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
                }
                $Switches = @{ AD = $Pillar -eq 'AD'; Group = $Pillar -eq 'Group' }
                $Thrown = $null
                try { Resolve-RoleByName -RoleName 'Role (id-1)' @Switches } catch { $Thrown = $PSItem }
                $Thrown | Should -Not -BeNullOrEmpty -Because 'a listing that cannot be read must stop the resolution'
                $Thrown.Exception.Message | Should -Be 'Forbidden: denied'
                $Thrown.Exception.Message | Should -Not -Match 'not found'
                $Thrown.Exception.Message | Should -Not -Match 'report it as a bug'
            }
        }

        It "throws a real listing's 403 as itself" {
            # End to end: the real Get-OPIMEntraIDGroup reads through the transport mock, which
            # answers with the record the wrapper throws for a Graph 403.
            InModuleScope Omnicit.PIM {
                Mock Initialize-OPIMAuth {}
                Mock Invoke-OPIMGraphRequest {
                    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('Forbidden: Insufficient privileges to complete the operation.'), 'Forbidden',
                            [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
                }
                $Thrown = $null
                try { Resolve-RoleByName -RoleName 'Owners - member (grp-403)' -Group } catch { $Thrown = $PSItem }
                $Thrown | Should -Not -BeNullOrEmpty -Because 'a listing that cannot be read must stop the resolution'
                $Thrown.FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
                $Thrown.Exception.Message | Should -Not -Match 'not found'
                Should -Invoke Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It
            }
        }

        It 'passes -Activated to the failing listing and still throws its error' {
            InModuleScope Omnicit.PIM {
                Mock Get-OPIMEntraIDGroup {
                    $ErrorActionPreference = if ($PesterBoundParameters.ContainsKey('ErrorAction')) { $PesterBoundParameters['ErrorAction'] } else { 'Continue' }
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('Forbidden: denied'), 'Forbidden',
                            [System.Management.Automation.ErrorCategory]::PermissionDenied, $null))
                }
                { Resolve-RoleByName -RoleName 'Owners (grp-403)' -Group -Activated } | Should -Throw -ErrorId 'Forbidden*'
                Should -Invoke Get-OPIMEntraIDGroup -Times 1 -Exactly -Scope It -ParameterFilter { $Activated -eq $true }
            }
        }
    }
}
