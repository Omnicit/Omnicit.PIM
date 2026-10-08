BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMRequestOutcome' {
    Context 'When an activation request has a status' {
        It 'classifies <Status> as <Outcome>' -ForEach @(
            @{ Status = 'Provisioned';                 Outcome = 'Succeeded' }
            @{ Status = 'Granted';                     Outcome = 'Succeeded' }
            @{ Status = 'ScheduleCreated';             Outcome = 'Succeeded' }
            @{ Status = 'PendingApproval';             Outcome = 'AwaitingDecision' }
            @{ Status = 'PendingAdminDecision';        Outcome = 'AwaitingDecision' }
            @{ Status = 'PendingApprovalProvisioning'; Outcome = 'AwaitingDecision' }
            @{ Status = 'PendingProvisioning';         Outcome = 'InProgress' }
            @{ Status = 'PendingScheduleCreation';     Outcome = 'InProgress' }
            @{ Status = 'Accepted';                    Outcome = 'InProgress' }
            @{ Status = 'PendingEvaluation';           Outcome = 'InProgress' }
            @{ Status = 'ProvisioningStarted';         Outcome = 'InProgress' }
            @{ Status = 'PendingExternalProvisioning'; Outcome = 'InProgress' }
            @{ Status = 'AdminApproved';               Outcome = 'InProgress' }
            @{ Status = 'Failed';                      Outcome = 'Failed' }
            @{ Status = 'Denied';                      Outcome = 'Failed' }
            @{ Status = 'Canceled';                    Outcome = 'Failed' }
            @{ Status = 'Revoked';                     Outcome = 'Failed' }
            @{ Status = 'AdminDenied';                 Outcome = 'Failed' }
            @{ Status = 'TimedOut';                    Outcome = 'Failed' }
            @{ Status = 'Invalid';                     Outcome = 'Failed' }
            @{ Status = 'FailedAsResourceIsLocked';    Outcome = 'Failed' }
            @{ Status = 'PendingRevocation';           Outcome = 'Failed' }
            @{ Status = 'SomethingNew';                Outcome = 'Failed' }
            @{ Status = '';                            Outcome = 'Failed' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Status = $Status } {
                param($Status)
                Get-OPIMRequestOutcome -Status $Status
            } | Should -BeExactly $Outcome
        }

        It 'classifies a missing status as Failed' {
            InModuleScope Omnicit.PIM { Get-OPIMRequestOutcome -Status $null } | Should -BeExactly 'Failed'
        }

        It 'classifies a call without -Status as Failed' {
            InModuleScope Omnicit.PIM { Get-OPIMRequestOutcome } | Should -BeExactly 'Failed'
        }

        It 'classifies a status of only white space as Failed' {
            InModuleScope Omnicit.PIM { Get-OPIMRequestOutcome -Status '   ' } | Should -BeExactly 'Failed'
        }

        It 'ignores letter case: <Status>' -ForEach @(
            @{ Status = 'provisioned';         Outcome = 'Succeeded' }
            @{ Status = 'PENDINGAPPROVAL';     Outcome = 'AwaitingDecision' }
            @{ Status = 'pendingprovisioning'; Outcome = 'InProgress' }
            @{ Status = 'DENIED';              Outcome = 'Failed' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Status = $Status } {
                param($Status)
                Get-OPIMRequestOutcome -Status $Status
            } | Should -BeExactly $Outcome
        }

        It 'returns a single string' {
            $Result = InModuleScope Omnicit.PIM { Get-OPIMRequestOutcome -Status 'Provisioned' }
            @($Result).Count | Should -Be 1
            $Result | Should -BeOfType [string]
        }
    }

    Context 'When a deactivation request has a status' {
        It 'classifies <Status> as <Outcome> with -Deactivate' -ForEach @(
            @{ Status = 'Revoked';             Outcome = 'Succeeded' }
            @{ Status = 'PendingRevocation';   Outcome = 'InProgress' }
            @{ Status = 'PendingProvisioning'; Outcome = 'InProgress' }
            @{ Status = 'PendingApproval';     Outcome = 'AwaitingDecision' }
            @{ Status = 'Provisioned';         Outcome = 'Failed' }
            @{ Status = 'Granted';             Outcome = 'Failed' }
            @{ Status = 'ScheduleCreated';     Outcome = 'Failed' }
            @{ Status = 'Failed';              Outcome = 'Failed' }
            @{ Status = 'Canceled';            Outcome = 'Failed' }
            @{ Status = '';                    Outcome = 'Failed' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Status = $Status } {
                param($Status)
                Get-OPIMRequestOutcome -Status $Status -Deactivate
            } | Should -BeExactly $Outcome
        }

        It 'ignores letter case with -Deactivate: revoked' {
            InModuleScope Omnicit.PIM { Get-OPIMRequestOutcome -Status 'revoked' -Deactivate } | Should -BeExactly 'Succeeded'
        }
    }
}
