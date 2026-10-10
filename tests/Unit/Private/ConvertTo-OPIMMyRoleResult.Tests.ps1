BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OPIMScrubFixture.ps1"
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'ConvertTo-OPIMMyRoleResult' {
    BeforeAll {
        # The converter writes an error record through the calling command's runtime (-Cmdlet), so every
        # call needs a command to be called from: an advanced function in the module's scope, removed again
        # in AfterAll.
        InModuleScope Omnicit.PIM {
            function script:Invoke-TestCaller {
                [CmdletBinding()] param([Parameter(ValueFromPipeline)]$InputObject)
                process { $InputObject | ConvertTo-OPIMMyRoleResult -Cmdlet $PSCmdlet }
            }
        }
    }

    AfterAll {
        InModuleScope Omnicit.PIM { Remove-Item -Path Function:\Invoke-TestCaller -ErrorAction SilentlyContinue }
    }
    Context 'When a DirectoryAssignmentScheduleRequest is piped in' {
        It 'returns an object tagged with Omnicit.PIM.MyRoleResult' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{
                    action           = 'SelfActivate'
                    status           = 'PendingProvisioning'
                    roleDefinitionId = 'role-def-001'
                    directoryScopeId = '/'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                    directoryScope   = $null
                    EndDateTime      = [datetime]'2026-04-20T15:00:00Z'
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')

                $Result = $FakeInput | Invoke-TestCaller

                $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.MyRoleResult'
            }
        }

        It 'maps Category to DirectoryRole' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{
                    action           = 'SelfActivate'
                    status           = 'PendingProvisioning'
                    roleDefinitionId = 'role-def-001'
                    directoryScopeId = '/'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                    directoryScope   = $null
                    EndDateTime      = $null
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')

                $Result = $FakeInput | Invoke-TestCaller

                $Result.Category | Should -Be 'DirectoryRole'
            }
        }

        It 'maps Scope to "Directory" when directoryScopeId is "/"' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{
                    action           = 'SelfActivate'
                    status           = 'PendingProvisioning'
                    roleDefinitionId = 'role-def-001'
                    directoryScopeId = '/'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
                    directoryScope   = $null
                    EndDateTime      = $null
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')

                $Result = $FakeInput | Invoke-TestCaller

                $Result.Scope | Should -Be 'Directory'
            }
        }
    }

    Context 'When a GroupAssignmentScheduleRequest is piped in' {
        It 'returns an object tagged with Omnicit.PIM.MyRoleResult' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{
                    action      = 'selfActivate'
                    status      = 'PendingProvisioning'
                    groupId     = 'group-id-001'
                    accessId    = 'member'
                    group       = [PSCustomObject]@{ displayName = 'Security Group' }
                    EndDateTime = $null
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleRequest')

                $Result = $FakeInput | Invoke-TestCaller

                $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.MyRoleResult'
            }
        }

        It 'maps Category to EntraIDGroup' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{
                    action      = 'selfActivate'
                    status      = 'PendingProvisioning'
                    groupId     = 'group-id-001'
                    accessId    = 'member'
                    group       = [PSCustomObject]@{ displayName = 'Security Group' }
                    EndDateTime = $null
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleRequest')

                $Result = $FakeInput | Invoke-TestCaller

                $Result.Category | Should -Be 'EntraIDGroup'
            }
        }

        It 'maps Scope to the accessId' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{
                    action      = 'selfActivate'
                    status      = 'PendingProvisioning'
                    groupId     = 'group-id-001'
                    accessId    = 'owner'
                    group       = [PSCustomObject]@{ displayName = 'Security Group' }
                    EndDateTime = $null
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.GroupAssignmentScheduleRequest')

                $Result = $FakeInput | Invoke-TestCaller

                $Result.Scope | Should -Be 'owner'
            }
        }
    }

    Context 'When an AzureAssignmentScheduleRequest is piped in' {
        It 'returns an object tagged with Omnicit.PIM.MyRoleResult' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{
                    RequestType               = 'SelfActivate'
                    Status                    = 'Provisioned'
                    RoleDefinitionDisplayName = 'Contributor'
                    ScopeDisplayName          = 'MySubscription'
                    ExpirationType            = 'AfterDateTime'
                    ExpirationDuration        = $null
                    ExpirationEndDateTime     = [datetime]'2026-04-20T16:00:00Z'
                    ScheduleInfoStartDateTime = $null
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleRequest')

                $Result = $FakeInput | Invoke-TestCaller

                $Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.MyRoleResult'
            }
        }

        It 'maps Category to AzureRole' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{
                    RequestType               = 'SelfActivate'
                    Status                    = 'Provisioned'
                    RoleDefinitionDisplayName = 'Contributor'
                    ScopeDisplayName          = 'MySubscription'
                    ExpirationType            = 'AfterDateTime'
                    ExpirationDuration        = $null
                    ExpirationEndDateTime     = $null
                    ScheduleInfoStartDateTime = $null
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleRequest')

                $Result = $FakeInput | Invoke-TestCaller

                $Result.Category | Should -Be 'AzureRole'
            }
        }

        It 'computes EndDateTime from start + AfterDuration when ExpirationType is AfterDuration' {
            InModuleScope Omnicit.PIM {
                $StartDt = [datetime]'2026-04-20T12:00:00Z'
                $FakeInput = [PSCustomObject]@{
                    RequestType               = 'SelfActivate'
                    Status                    = 'Provisioned'
                    RoleDefinitionDisplayName = 'Owner'
                    ScopeDisplayName          = 'ProdSub'
                    ExpirationType            = 'AfterDuration'
                    ExpirationDuration        = 'PT2H'
                    ExpirationEndDateTime     = $null
                    ScheduleInfoStartDateTime = $StartDt
                }
                $FakeInput.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.AzureAssignmentScheduleRequest')

                $Result = $FakeInput | Invoke-TestCaller

                $Result.EndDateTime | Should -Be ($StartDt.AddHours(2))
            }
        }
    }

    Context 'When an object with no recognised type is piped in' {
        It 'produces no output' {
            InModuleScope Omnicit.PIM {
                $FakeInput = [PSCustomObject]@{ foo = 'bar' }

                $Result = $FakeInput | Invoke-TestCaller

                $Result | Should -BeNullOrEmpty
            }
        }
    }

    Context 'When an error record comes down the pipeline (OPIM-52)' {
        It 'writes the record through the given cmdlet, so it reaches that command''s -ErrorVariable, and emits no result' {
            InModuleScope Omnicit.PIM {
                $Record = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('The following policy rules failed: ["JustificationRule"]'),
                    'RoleAssignmentRequestPolicyValidationFailed',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)

                $Out = @($Record | Invoke-TestCaller -ErrorVariable Caught -ErrorAction SilentlyContinue)

                $Out.Count | Should -Be 0
                @($Caught).Count | Should -Be 1
                @($Caught)[0].Exception.Message | Should -BeExactly 'The following policy rules failed: ["JustificationRule"]'
                @($Caught)[0].FullyQualifiedErrorId | Should -BeExactly 'RoleAssignmentRequestPolicyValidationFailed,Invoke-TestCaller'
            }
        }

        It 'removes the record''s earlier entry from $global:Error before writing it, so it is listed once' {
            # The engine skips a write of the record that already sits first in the list, so the earlier
            # entry is put below another error: only removing it keeps the record from being listed twice.
            InModuleScope Omnicit.PIM {
                $Exception = [System.Exception]::new('refused once')
                $Record = [System.Management.Automation.ErrorRecord]::new($Exception, 'SomeId',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
                $Later = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('a later error'), 'LaterId',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
                $global:Error.Insert(0, $Record)
                $global:Error.Insert(0, $Later)

                $Record | Invoke-TestCaller -ErrorAction SilentlyContinue

                @($global:Error | Where-Object { [object]::ReferenceEquals($_.Exception, $Exception) }).Count | Should -Be 1
            }
        }

        It 'scrubs the Authorization header off the request the record points at before it is written' {
            $F = New-ScrubFixture
            $F.Request.Headers.Contains('Authorization') | Should -BeTrue -Because 'the fixture must carry the header, or the scrub below proves nothing'
            InModuleScope Omnicit.PIM -ArgumentList $F.Record {
                param($Record)
                $Record | Invoke-TestCaller -ErrorAction SilentlyContinue
            }
            $F.Request.Headers.Contains('Authorization') | Should -BeFalse
        }

        It 'still converts the objects around an error record, in order' {
            InModuleScope Omnicit.PIM {
                $First = [PSCustomObject]@{
                    action           = 'SelfActivate'
                    status           = 'Provisioned'
                    directoryScopeId = '/'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Role A' }
                }
                $First.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')
                $Second = [PSCustomObject]@{
                    action           = 'SelfActivate'
                    status           = 'Provisioned'
                    directoryScopeId = '/'
                    roleDefinition   = [PSCustomObject]@{ displayName = 'Role C' }
                }
                $Second.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryAssignmentScheduleRequest')
                $Record = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Role B was refused'), 'RefusedB',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)

                $Out = @($First, $Record, $Second | Invoke-TestCaller -ErrorVariable Caught -ErrorAction SilentlyContinue)

                $Out.Count | Should -Be 2
                $Out[0].DisplayName | Should -BeExactly 'Role A'
                $Out[1].DisplayName | Should -BeExactly 'Role C'
                $Out[0].PSObject.TypeNames | Should -Contain 'Omnicit.PIM.MyRoleResult'
                @($Caught).Count | Should -Be 1
                @($Caught)[0].FullyQualifiedErrorId | Should -BeLike 'RefusedB*'
            }
        }
    }

    Context 'The -Cmdlet parameter (OPIM-52)' {
        It 'is mandatory, and typed as a PSCmdlet' {
            InModuleScope Omnicit.PIM {
                $Parameter = (Get-Command ConvertTo-OPIMMyRoleResult).Parameters['Cmdlet']
                $Parameter.ParameterType | Should -Be ([System.Management.Automation.PSCmdlet])
                $Parameter.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
            }
        }
    }
}