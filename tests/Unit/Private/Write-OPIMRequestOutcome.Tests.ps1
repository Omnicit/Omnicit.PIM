BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Write-OPIMRequestOutcome' {
    BeforeAll {
        # A probe advanced function inside the module gives the helper a real PSCmdlet, so what it
        # writes through -Cmdlet lands in the probe's own warning and error streams.
        InModuleScope Omnicit.PIM {
            function script:Invoke-OutcomeProbe {
                [CmdletBinding()]
                param($Request, [string]$Status, [switch]$Deactivate)
                Write-OPIMRequestOutcome -Request $Request -Status $Status -Name 'Role X' -Deactivate:$Deactivate -Cmdlet $PSCmdlet
            }
        }

        # Runs the probe and returns what it output, warned and errored, under the quiet preferences.
        function Invoke-Probe {
            param($Request, [string]$Status, [switch]$Deactivate)
            InModuleScope Omnicit.PIM -Parameters @{ R = $Request; S = $Status; D = [bool]$Deactivate } {
                param($R, $S, $D)
                $Output = @(Invoke-OutcomeProbe -Request $R -Status $S -Deactivate:$D `
                        -WarningVariable W -WarningAction SilentlyContinue `
                        -ErrorVariable E -ErrorAction SilentlyContinue)
                [PSCustomObject]@{ Output = $Output; Warnings = @($W); Errors = @($E) }
            }
        }
    }

    Context 'When the request succeeded' {
        It 'returns the same object and writes nothing for <Status>' -ForEach @(
            @{ Status = 'Provisioned' }
            @{ Status = 'Granted' }
            @{ Status = 'ScheduleCreated' }
        ) {
            $Req = [PSCustomObject]@{ id = 'req-1'; status = 'PendingProvisioning' }
            $Result = Invoke-Probe -Request $Req -Status $Status
            @($Result.Output).Count | Should -Be 1
            [object]::ReferenceEquals($Result.Output[0], $Req) | Should -BeTrue
            $Req.status | Should -BeExactly $Status
            $Result.Warnings.Count | Should -Be 0
            $Result.Errors.Count | Should -Be 0
        }

        It 'returns the request for a deactivation that ended Revoked' {
            $Req = [PSCustomObject]@{ id = 'req-1'; status = 'Accepted' }
            $Result = Invoke-Probe -Request $Req -Status 'Revoked' -Deactivate
            [object]::ReferenceEquals($Result.Output[0], $Req) | Should -BeTrue
            $Req.status | Should -BeExactly 'Revoked'
            $Result.Warnings.Count | Should -Be 0
            $Result.Errors.Count | Should -Be 0
        }
    }

    Context 'When the request waits for a decision' {
        It 'returns the request with one warning that names the status: <Status>' -ForEach @(
            @{ Status = 'PendingApproval' }
            @{ Status = 'PendingAdminDecision' }
            @{ Status = 'PendingApprovalProvisioning' }
        ) {
            $Req = [PSCustomObject]@{ id = 'req-1'; status = 'PendingProvisioning' }
            $Result = Invoke-Probe -Request $Req -Status $Status
            @($Result.Output).Count | Should -Be 1
            [object]::ReferenceEquals($Result.Output[0], $Req) | Should -BeTrue
            $Req.status | Should -BeExactly $Status
            $Result.Warnings.Count | Should -Be 1
            "$($Result.Warnings[0])" | Should -BeExactly "Role X: the activation request is $Status. It waits for a decision and has not taken effect yet."
            $Result.Errors.Count | Should -Be 0
        }

        It 'says deactivation in the warning with -Deactivate' {
            $Req = [PSCustomObject]@{ id = 'req-1'; status = 'x' }
            $Result = Invoke-Probe -Request $Req -Status 'PendingApproval' -Deactivate
            $Result.Warnings.Count | Should -Be 1
            "$($Result.Warnings[0])" | Should -BeExactly 'Role X: the deactivation request is PendingApproval. It waits for a decision and has not taken effect yet.'
            [object]::ReferenceEquals($Result.Output[0], $Req) | Should -BeTrue
        }
    }

    Context 'When the service is still working on the request' {
        It 'returns the request with one warning that names the status: <Status>' -ForEach @(
            @{ Status = 'PendingProvisioning' }
            @{ Status = 'PendingScheduleCreation' }
            @{ Status = 'Accepted' }
        ) {
            $Req = [PSCustomObject]@{ id = 'req-1'; status = 'x' }
            $Result = Invoke-Probe -Request $Req -Status $Status
            @($Result.Output).Count | Should -Be 1
            [object]::ReferenceEquals($Result.Output[0], $Req) | Should -BeTrue
            $Req.status | Should -BeExactly $Status
            $Result.Warnings.Count | Should -Be 1
            "$($Result.Warnings[0])" | Should -BeExactly "Role X: the activation request is $Status and has not taken effect yet."
            $Result.Errors.Count | Should -Be 0
        }

        It 'returns a deactivation that is PendingRevocation with a warning that says deactivation' {
            $Req = [PSCustomObject]@{ id = 'req-1'; status = 'x' }
            $Result = Invoke-Probe -Request $Req -Status 'PendingRevocation' -Deactivate
            [object]::ReferenceEquals($Result.Output[0], $Req) | Should -BeTrue
            $Result.Warnings.Count | Should -Be 1
            "$($Result.Warnings[0])" | Should -BeExactly 'Role X: the deactivation request is PendingRevocation and has not taken effect yet.'
            $Result.Errors.Count | Should -Be 0
        }
    }

    Context 'When the request failed' {
        It 'returns nothing and writes one ActivationRequestFailed error for <Status>' -ForEach @(
            @{ Status = 'Denied' }
            @{ Status = 'Failed' }
            @{ Status = 'SomethingNew' }
        ) {
            $Req = [PSCustomObject]@{ id = 'req-1'; status = 'PendingProvisioning' }
            $Result = Invoke-Probe -Request $Req -Status $Status
            @($Result.Output).Count | Should -Be 0
            $Result.Errors.Count | Should -Be 1
            $Result.Errors[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Invoke-OutcomeProbe'
            [object]::ReferenceEquals($Result.Errors[-1].TargetObject, $Req) | Should -BeTrue
            $Result.Errors[-1].Exception.Message | Should -BeExactly "Role X: the activation request ended with status '$Status' and did not take effect."
            $Req.status | Should -BeExactly $Status
            $Result.Warnings.Count | Should -Be 0
        }

        It 'reports an empty status as no status' {
            $Req = [PSCustomObject]@{ id = 'req-1'; status = 'PendingProvisioning' }
            $Result = Invoke-Probe -Request $Req -Status ''
            @($Result.Output).Count | Should -Be 0
            $Result.Errors.Count | Should -Be 1
            $Result.Errors[-1].Exception.Message | Should -BeExactly 'Role X: the activation request ended with no status and did not take effect.'
        }

        It 'says deactivation in the error with -Deactivate' {
            $Req = [PSCustomObject]@{ id = 'req-1'; status = 'x' }
            $Result = Invoke-Probe -Request $Req -Status 'Failed' -Deactivate
            @($Result.Output).Count | Should -Be 0
            $Result.Errors.Count | Should -Be 1
            $Result.Errors[-1].Exception.Message | Should -BeExactly "Role X: the deactivation request ended with status 'Failed' and did not take effect."
        }

        It 'treats Provisioned as a failure for a deactivation' {
            $Req = [PSCustomObject]@{ id = 'req-1'; status = 'x' }
            $Result = Invoke-Probe -Request $Req -Status 'Provisioned' -Deactivate
            @($Result.Output).Count | Should -Be 0
            $Result.Errors.Count | Should -Be 1
            $Result.Errors[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Invoke-OutcomeProbe'
        }

        It 'treats Revoked as a failure for an activation' {
            $Req = [PSCustomObject]@{ id = 'req-1'; status = 'x' }
            $Result = Invoke-Probe -Request $Req -Status 'Revoked'
            @($Result.Output).Count | Should -Be 0
            $Result.Errors.Count | Should -Be 1
        }

        It 'ends the call once under -ErrorAction Stop, with ActivationRequestFailed as what it throws' {
            $Req = [PSCustomObject]@{ id = 'req-1'; status = 'x' }
            $Caught = [System.Collections.Generic.List[object]]::new()
            InModuleScope Omnicit.PIM -Parameters @{ R = $Req; Caught = $Caught } {
                param($R, $Caught)
                try {
                    Invoke-OutcomeProbe -Request $R -Status 'Failed' -ErrorAction Stop
                    $Caught.Add('returned')
                } catch {
                    $Caught.Add($PSItem)
                }
            }
            $Caught.Count | Should -Be 1
            $Caught[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $Caught[0].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Invoke-OutcomeProbe'
            $Caught[0].Exception.Message | Should -BeExactly "Role X: the activation request ended with status 'Failed' and did not take effect."
            [object]::ReferenceEquals($Caught[0].TargetObject, $Req) | Should -BeTrue
        }
    }

    Context 'When the request object carries no status property' {
        It 'adds a status note property that holds the status' {
            $Req = [PSCustomObject]@{ id = 'req-1' }
            $Result = Invoke-Probe -Request $Req -Status 'Provisioned'
            [object]::ReferenceEquals($Result.Output[0], $Req) | Should -BeTrue
            $Req.PSObject.Properties['status'] | Should -Not -BeNullOrEmpty
            $Req.PSObject.Properties['status'].MemberType | Should -Be 'NoteProperty'
            $Req.status | Should -BeExactly 'Provisioned'
            $Result.Errors.Count | Should -Be 0
        }

        It 'adds the status of a failed request too' {
            $Req = [PSCustomObject]@{ id = 'req-1' }
            $Result = Invoke-Probe -Request $Req -Status 'Denied'
            @($Result.Output).Count | Should -Be 0
            $Req.status | Should -BeExactly 'Denied'
            $Result.Errors.Count | Should -Be 1
        }

        It 'writes the status back onto a property written in another letter case' {
            $Req = [PSCustomObject]@{ id = 'req-1'; Status = 'Accepted' }
            $Result = Invoke-Probe -Request $Req -Status 'Provisioned'
            [object]::ReferenceEquals($Result.Output[0], $Req) | Should -BeTrue
            $Req.Status | Should -BeExactly 'Provisioned'
            @($Req.PSObject.Properties | Where-Object { $PSItem.Name -ieq 'status' }).Count | Should -Be 1
        }
    }

    Context 'When the status of the request object is read-only' {
        It 'leaves it as it is, throws nothing and returns the request' {
            $Req = [PSCustomObject]@{ id = 'req-1' }
            $Req | Add-Member -MemberType ScriptProperty -Name Status -Value { 'Provisioned' }
            $Result = Invoke-Probe -Request $Req -Status 'Provisioned'
            @($Result.Output).Count | Should -Be 1
            [object]::ReferenceEquals($Result.Output[0], $Req) | Should -BeTrue
            $Req.Status | Should -BeExactly 'Provisioned'
            $Result.Errors.Count | Should -Be 0
        }

        It 'still reports a failed status of a read-only request as an error' {
            $Req = [PSCustomObject]@{ id = 'req-1' }
            $Req | Add-Member -MemberType ScriptProperty -Name Status -Value { 'Denied' }
            $Result = Invoke-Probe -Request $Req -Status 'Denied'
            @($Result.Output).Count | Should -Be 0
            $Result.Errors.Count | Should -Be 1
            $Result.Errors[-1].FullyQualifiedErrorId | Should -BeExactly 'ActivationRequestFailed,Invoke-OutcomeProbe'
            $Req.Status | Should -BeExactly 'Denied'
        }
    }

    Context 'When it is called outside a cmdlet' {
        It 'refuses a -Cmdlet that is not a PSCmdlet' {
            { InModuleScope Omnicit.PIM {
                    Write-OPIMRequestOutcome -Request ([PSCustomObject]@{ status = 'x' }) -Status 'Provisioned' -Name 'Role X' -Cmdlet 'not a cmdlet'
                } } | Should -Throw
        }
    }
}
