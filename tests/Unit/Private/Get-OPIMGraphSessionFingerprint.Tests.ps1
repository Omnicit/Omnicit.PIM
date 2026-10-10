BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire

    # A context shaped like the one Connect-MgGraph -AccessToken leaves for this module (see the
    # contract Context below), with every IAuthContext property present. Letter-repeat GUIDs: none
    # is a version-4 id.
    function New-TestGraphContext {
        param([hashtable]$Override = @{})
        $Values = [ordered]@{
            AuthType               = 'UserProvidedAccessToken'
            TokenCredentialType    = 'UserProvidedAccessToken'
            ClientId               = 'cccccccc-0000-0000-0000-00000000000c'
            TenantId               = 'aaaaaaaa-0000-0000-0000-00000000000a'
            Account                = 'user@contoso.com'
            AppName                = 'opim-test-app'
            Environment            = 'Global'
            Scopes                 = @('User.Read', 'RoleAssignmentSchedule.ReadWrite.Directory')
            ContextScope           = 'Process'
            CertificateThumbprint  = $null
            CertificateSubjectName = $null
            ManagedIdentityId      = $null
            LoginHint              = $null
            HomeAccountId          = $null
            PSHostVersion          = [version]'7.6.0'
            ClientSecret           = $null
            Certificate            = $null
        }
        foreach ($Key in $Override.Keys) { $Values[$Key] = $Override[$Key] }
        [pscustomobject]$Values
    }

    # The fingerprint of one context, computed inside the module.
    function Get-TestFingerprint {
        param([AllowNull()][object]$Context)
        InModuleScope Omnicit.PIM -Parameters @{ C = $Context } { param($C) Get-OPIMGraphSessionFingerprint -Context $C }
    }
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMGraphSessionFingerprint' {
    # MEASURED in Omnicit.EntraRBAC on 2026-10-05 against Microsoft.Graph.Authentication 2.41.1, by
    # reflection over the type Get-MgContext declares: a Connect-MgGraph -AccessToken session, the one
    # this module makes, has AuthType and TokenCredentialType UserProvidedAccessToken, and ClientId,
    # TenantId, Account, AppName and Scopes from the token's appid, tid, upn, app_displayname and
    # scp or roles claims. This Context reads the SDK this build resolved (RequiredModules.psd1 pins
    # it), so a renamed or retyped property turns it red instead of leaving the fingerprint to compare
    # two empty values as equal.
    Context 'When the Graph SDK context type is read (the contract)' {
        BeforeAll {
            $ContextType = (Get-Command -Name Get-MgContext -Module Microsoft.Graph.Authentication).OutputType[0].Type
        }

        It 'declares IAuthContext as the output of Get-MgContext' {
            $ContextType.FullName | Should -Be 'Microsoft.Graph.PowerShell.Authentication.IAuthContext'
        }

        It 'exposes <Name> as <Type>, which the fingerprint reads' -ForEach @(
            @{ Name = 'AuthType'; Type = 'AuthenticationType' }
            @{ Name = 'TokenCredentialType'; Type = 'TokenCredentialType' }
            @{ Name = 'ClientId'; Type = 'String' }
            @{ Name = 'TenantId'; Type = 'String' }
            @{ Name = 'Account'; Type = 'String' }
            @{ Name = 'AppName'; Type = 'String' }
            @{ Name = 'Environment'; Type = 'String' }
            @{ Name = 'Scopes'; Type = 'String[]' }
        ) {
            $Property = $ContextType.GetProperty($Name)
            $Property | Should -Not -BeNullOrEmpty -Because "the fingerprint reads $Name"
            $Property.PropertyType.Name | Should -Be $Type
        }

        It 'also carries <Name>, which the fingerprint does not read' -ForEach @(
            @{ Name = 'ClientSecret'; Type = 'SecureString' }
            @{ Name = 'Certificate'; Type = 'X509Certificate2' }
        ) {
            $Property = $ContextType.GetProperty($Name)
            $Property | Should -Not -BeNullOrEmpty
            $Property.PropertyType.Name | Should -Be $Type
        }
    }

    Context 'When the context is given or read' {
        It 'returns null for a null context and does not read the session' {
            # An EXPLICIT -Context $null means "no session": the helper tells it from an omitted
            # -Context with $PSBoundParameters.ContainsKey, so it never falls back to Get-MgContext.
            Mock -ModuleName Omnicit.PIM Get-MgContext { }
            Get-TestFingerprint -Context $null | Should -BeNullOrEmpty
            Should -Invoke -ModuleName Omnicit.PIM Get-MgContext -Times 0 -Scope It
        }

        It 'calls Get-MgContext exactly once when no context is given, and returns null when there is no session' {
            Mock -ModuleName Omnicit.PIM Get-MgContext { }
            InModuleScope Omnicit.PIM { Get-OPIMGraphSessionFingerprint } | Should -BeNullOrEmpty
            Should -Invoke -ModuleName Omnicit.PIM Get-MgContext -Times 1 -Exactly -Scope It
        }

        It 'fingerprints the context Get-MgContext returns when no context is given' {
            $script:FixtureContext = New-TestGraphContext
            Mock -ModuleName Omnicit.PIM Get-MgContext { $script:FixtureContext }
            $FromCall = InModuleScope Omnicit.PIM { Get-OPIMGraphSessionFingerprint }
            $FromCall | Should -Not -BeNullOrEmpty
            $FromCall | Should -BeExactly (Get-TestFingerprint -Context $script:FixtureContext)
            Should -Invoke -ModuleName Omnicit.PIM Get-MgContext -Times 1 -Exactly -Scope It
        }

        It 'writes nothing to any stream' {
            $Context = New-TestGraphContext
            $Out = InModuleScope Omnicit.PIM -Parameters @{ C = $Context } {
                param($C) Get-OPIMGraphSessionFingerprint -Context $C -Verbose *>&1
            }
            @($Out).Count | Should -Be 1
            @($Out)[0] | Should -BeOfType [string]
        }
    }

    Context 'When two contexts are compared' {
        It 'gives two distinct context objects with equal values the same fingerprint' {
            # Two runspaces connected as the same identity to the same tenant must not refuse each other.
            $A = New-TestGraphContext
            $B = New-TestGraphContext
            [object]::ReferenceEquals($A, $B) | Should -BeFalse
            Get-TestFingerprint -Context $B | Should -BeExactly (Get-TestFingerprint -Context $A)
        }

        It 'ignores the order of the scopes' {
            $A = New-TestGraphContext
            $B = New-TestGraphContext -Override @{ Scopes = @('RoleAssignmentSchedule.ReadWrite.Directory', 'User.Read') }
            Get-TestFingerprint -Context $B | Should -BeExactly (Get-TestFingerprint -Context $A)
        }

        It 'tells one scope containing a space from two scopes' {
            # A joined string would give "a b" for both; the scopes are a JSON array, so a value holding
            # the separator can never make two sessions compare equal.
            $One = New-TestGraphContext -Override @{ Scopes = @('a b') }
            $Two = New-TestGraphContext -Override @{ Scopes = @('a', 'b') }
            Get-TestFingerprint -Context $Two | Should -Not -BeExactly (Get-TestFingerprint -Context $One)
        }

        It 'writes the scopes as a JSON array, an empty list as []' {
            $Some = New-TestGraphContext -Override @{ Scopes = @('User.Read') }
            $None = New-TestGraphContext -Override @{ Scopes = @() }
            Get-TestFingerprint -Context $Some | Should -Match '"Scopes":\["User\.Read"\]'
            Get-TestFingerprint -Context $None | Should -Match '"Scopes":\[\]'
        }

        It 'changes when <Name> changes' -ForEach @(
            @{ Name = 'AuthType'; Value = 'AppOnly' }
            @{ Name = 'TokenCredentialType'; Value = 'ClientCertificate' }
            @{ Name = 'ClientId'; Value = 'dddddddd-0000-0000-0000-00000000000d' }
            @{ Name = 'TenantId'; Value = 'bbbbbbbb-0000-0000-0000-00000000000b' }
            @{ Name = 'Account'; Value = 'other@contoso.com' }
            @{ Name = 'AppName'; Value = 'another-app' }
            @{ Name = 'Environment'; Value = 'USGov' }
            @{ Name = 'Scopes'; Value = @('User.Read') }
        ) {
            $A = New-TestGraphContext
            $B = New-TestGraphContext -Override @{ $Name = $Value }
            Get-TestFingerprint -Context $B | Should -Not -BeExactly (Get-TestFingerprint -Context $A)
        }

        It 'tells a certificate session for another app in the same tenant from the module''s own session' {
            $Own = New-TestGraphContext
            $Other = New-TestGraphContext -Override @{
                AuthType = 'AppOnly'; TokenCredentialType = 'ClientCertificate'
                ClientId = 'eeeeeeee-0000-0000-0000-00000000000e'; AppName = 'another-app'; Account = $null
                CertificateThumbprint = 'NOT-A-REAL-THUMBPRINT'; Scopes = @()
            }
            Get-TestFingerprint -Context $Other | Should -Not -BeExactly (Get-TestFingerprint -Context $Own)
        }

        It 'does not change when <Name> changes' -ForEach @(
            @{ Name = 'ContextScope'; Value = 'CurrentUser' }
            @{ Name = 'CertificateThumbprint'; Value = 'NOT-A-REAL-THUMBPRINT' }
            @{ Name = 'LoginHint'; Value = 'user@contoso.com' }
            @{ Name = 'HomeAccountId'; Value = 'home' }
            @{ Name = 'PSHostVersion'; Value = [version]'7.4.0' }
        ) {
            $A = New-TestGraphContext
            $B = New-TestGraphContext -Override @{ $Name = $Value }
            Get-TestFingerprint -Context $B | Should -BeExactly (Get-TestFingerprint -Context $A)
        }

        It 'builds a fingerprint for a context with no scopes and no account' {
            $Context = New-TestGraphContext -Override @{ Scopes = $null; Account = $null }
            Get-TestFingerprint -Context $Context | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When the context carries a secret' {
        It 'reads neither the client secret nor the certificate' {
            # Each getter RECORDS that it ran. A getter that throws proves nothing: PowerShell swallows
            # an exception raised by a ScriptProperty getter on member access and returns null, inside a
            # try as well (measured 2026-10-07, PowerShell 7.6.6), so a throwing getter passes with the
            # read in place.
            $Reads = [System.Collections.Generic.List[string]]::new()
            $Context = New-TestGraphContext
            $Context.PSObject.Properties.Remove('ClientSecret')
            $Context.PSObject.Properties.Remove('Certificate')
            $Context | Add-Member -MemberType ScriptProperty -Name ClientSecret -Value ({ $Reads.Add('ClientSecret') }.GetNewClosure())
            $Context | Add-Member -MemberType ScriptProperty -Name Certificate -Value ({ $Reads.Add('Certificate') }.GetNewClosure())
            Get-TestFingerprint -Context $Context | Should -Not -BeNullOrEmpty
            ($Reads -join ', ') | Should -BeNullOrEmpty -Because 'the fingerprint reads neither property'
            # The getters do fire when read, so the empty record above is evidence and not an inert hook.
            $null = $Context.ClientSecret
            $null = $Context.Certificate
            ($Reads -join ', ') | Should -BeExactly 'ClientSecret, Certificate'
        }

        It 'holds no secret and no token' {
            $Secret = [System.Net.NetworkCredential]::new('', 'NOT-A-REAL-TOKEN-secret-value').SecurePassword
            $Context = New-TestGraphContext -Override @{ ClientSecret = $Secret }
            $Fingerprint = Get-TestFingerprint -Context $Context
            $Fingerprint | Should -Not -Match 'NOT-A-REAL-TOKEN'
            $Fingerprint | Should -Not -Match 'eyJ'
        }
    }
}
