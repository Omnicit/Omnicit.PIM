BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire

    # The tenant of the module's session; a letter-repeat placeholder, not a version-4 id.
    $TenantA = 'aaaaaaaa-0000-0000-0000-00000000000a'

    # A context as Connect-MgGraph -AccessToken leaves it for this module.
    function New-TestGraphContext {
        param([hashtable]$Override = @{})
        $Values = [ordered]@{
            AuthType            = 'UserProvidedAccessToken'
            TokenCredentialType = 'UserProvidedAccessToken'
            ClientId            = 'cccccccc-0000-0000-0000-00000000000c'
            TenantId            = 'aaaaaaaa-0000-0000-0000-00000000000a'
            Account             = 'user@contoso.com'
            AppName             = 'opim-test-app'
            Environment         = 'Global'
            Scopes              = @('User.Read')
        }
        foreach ($Key in $Override.Keys) { $Values[$Key] = $Override[$Key] }
        [pscustomobject]$Values
    }

    # Seeds the module's auth state.
    function Set-TestAuthState {
        param([AllowNull()][object]$State)
        InModuleScope Omnicit.PIM -Parameters @{ S = $State } { param($S) $script:_OPIMAuthState = $S }
    }

    $OwnContext = New-TestGraphContext
    $OwnFingerprint = InModuleScope Omnicit.PIM -Parameters @{ C = $OwnContext } {
        param($C) Get-OPIMGraphSessionFingerprint -Context $C
    }
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMGraphSessionState' {
    BeforeEach {
        $script:SessionContext = $null
        Mock -ModuleName Omnicit.PIM Get-MgContext { $script:SessionContext }
    }
    AfterEach {
        Set-TestAuthState -State $null
    }

    Context 'When the module holds no session it connected' {
        It 'returns Untracked with no auth state and does not read the session' {
            $script:SessionContext = $OwnContext
            Set-TestAuthState -State $null
            InModuleScope Omnicit.PIM { Get-OPIMGraphSessionState } | Should -BeExactly 'Untracked'
            Should -Invoke -ModuleName Omnicit.PIM Get-MgContext -Times 0 -Scope It
        }

        It 'returns Untracked for a state without the GraphSessionFingerprint key and does not read the session' {
            # The shape the pillar tests and an older state carry, and a state that holds only the mode.
            $script:SessionContext = $OwnContext
            Set-TestAuthState -State @{ TenantId = $TenantA; GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1) }
            InModuleScope Omnicit.PIM { Get-OPIMGraphSessionState } | Should -BeExactly 'Untracked'
            Set-TestAuthState -State @{ DeviceCode = $true }
            InModuleScope Omnicit.PIM { Get-OPIMGraphSessionState } | Should -BeExactly 'Untracked'
            Should -Invoke -ModuleName Omnicit.PIM Get-MgContext -Times 0 -Scope It
        }

        It 'returns Untracked for a state that is not a dictionary, even one with a GraphSessionFingerprint property' {
            $script:SessionContext = $OwnContext
            Set-TestAuthState -State ([pscustomobject]@{ TenantId = $TenantA; GraphSessionFingerprint = $OwnFingerprint })
            InModuleScope Omnicit.PIM { Get-OPIMGraphSessionState } | Should -BeExactly 'Untracked'
            Should -Invoke -ModuleName Omnicit.PIM Get-MgContext -Times 0 -Scope It
        }
    }

    Context 'When the module recorded the session it connected' {
        It 'returns Own when the session in the process fingerprints to the recorded value' {
            $script:SessionContext = New-TestGraphContext
            Set-TestAuthState -State @{ TenantId = $TenantA; GraphSessionFingerprint = $OwnFingerprint }
            InModuleScope Omnicit.PIM { Get-OPIMGraphSessionState } | Should -BeExactly 'Own'
            Should -Invoke -ModuleName Omnicit.PIM Get-MgContext -Times 1 -Exactly -Scope It
        }

        It 'returns Absent when the process holds no session' {
            $script:SessionContext = $null
            Set-TestAuthState -State @{ TenantId = $TenantA; GraphSessionFingerprint = $OwnFingerprint }
            InModuleScope Omnicit.PIM { Get-OPIMGraphSessionState } | Should -BeExactly 'Absent'
            Should -Invoke -ModuleName Omnicit.PIM Get-MgContext -Times 1 -Exactly -Scope It
        }

        It 'returns Absent when the process holds no session and the recorded value is null' {
            $script:SessionContext = $null
            Set-TestAuthState -State @{ TenantId = $TenantA; GraphSessionFingerprint = $null }
            InModuleScope Omnicit.PIM { Get-OPIMGraphSessionState } | Should -BeExactly 'Absent'
        }

        It 'returns Changed when another session replaced the recorded one' {
            $script:SessionContext = New-TestGraphContext -Override @{ ClientId = 'dddddddd-0000-0000-0000-00000000000d' }
            Set-TestAuthState -State @{ TenantId = $TenantA; GraphSessionFingerprint = $OwnFingerprint }
            InModuleScope Omnicit.PIM { Get-OPIMGraphSessionState } | Should -BeExactly 'Changed'
        }

        It 'returns Changed when a session appears and the recorded value is null' {
            # The key is present: the module connected, and Get-MgContext then read no session.
            $script:SessionContext = $OwnContext
            Set-TestAuthState -State @{ TenantId = $TenantA; GraphSessionFingerprint = $null }
            InModuleScope Omnicit.PIM { Get-OPIMGraphSessionState } | Should -BeExactly 'Changed'
        }

        It 'returns Changed for a session that differs only in letter case' {
            $script:SessionContext = New-TestGraphContext -Override @{ Account = 'USER@contoso.com' }
            Set-TestAuthState -State @{ TenantId = $TenantA; GraphSessionFingerprint = $OwnFingerprint }
            InModuleScope Omnicit.PIM { Get-OPIMGraphSessionState } | Should -BeExactly 'Changed'
        }

        It 'returns Changed for a session whose AppName differs only by a soft hyphen (ordinal comparison)' {
            # -ceq compares with the invariant culture, which gives a soft hyphen (U+00AD) no weight, so
            # the two names compare equal there. Built at run time, since this file is ASCII only.
            $script:SessionContext = New-TestGraphContext -Override @{ AppName = ('opim-test' + [char]0xAD + '-app') }
            $OwnContext.AppName | Should -BeExactly 'opim-test-app'
            Set-TestAuthState -State @{ TenantId = $TenantA; GraphSessionFingerprint = $OwnFingerprint }
            InModuleScope Omnicit.PIM { Get-OPIMGraphSessionState } | Should -BeExactly 'Changed'
        }
    }
}
