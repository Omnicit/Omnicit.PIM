BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Invoke-OPIMDeviceCodeAuth' {
    BeforeAll {
        # A stand-in with the shape of MSAL's device code API. ExecuteAsync runs the flow on a
        # thread-pool thread, as MSAL does, so the callback is invoked off the pipeline thread.
        if (-not ('OPIMTestFakes.DeviceCode.FakeDeviceCodeApp' -as [type])) {
            Add-Type -TypeDefinition @'
namespace OPIMTestFakes.DeviceCode {
    using System;
    using System.Collections.Generic;
    using System.Threading;
    using System.Threading.Tasks;

    public sealed class FakeDeviceCodeResult {
        public string Message { get; set; }
        public string UserCode { get; set; }
        public string DeviceCode { get; set; }
    }

    public sealed class FakeAccount {
        public string Username { get; set; }
    }

    public sealed class FakeAuthenticationResult {
        public string AccessToken { get; set; }
        public DateTimeOffset ExpiresOn { get; set; }
        public FakeAccount Account { get; set; }
    }

    public sealed class FakeDeviceCodeBuilder {
        private readonly FakeDeviceCodeApp _app;
        private readonly Func<FakeDeviceCodeResult, Task> _callback;
        public FakeDeviceCodeBuilder(FakeDeviceCodeApp app, Func<FakeDeviceCodeResult, Task> callback) { _app = app; _callback = callback; }
        public FakeDeviceCodeBuilder WithClaims(string claims) { _app.ClaimsSeen = claims; return this; }
        public Task<FakeAuthenticationResult> ExecuteAsync(CancellationToken cancellationToken) {
            FakeDeviceCodeApp app = _app;
            Func<FakeDeviceCodeResult, Task> callback = _callback;
            return Task.Run(async () => {
                app.CallbackThreadId = Thread.CurrentThread.ManagedThreadId;
                await callback(new FakeDeviceCodeResult { Message = app.Message, UserCode = "FAKECODE1", DeviceCode = "FAKE-DEVICE-CODE" });
                await Task.Delay(app.DelayMilliseconds);
                if (app.FailWith != null) { throw new InvalidOperationException(app.FailWith); }
                return new FakeAuthenticationResult {
                    AccessToken = "fake-graph-token",
                    ExpiresOn = DateTimeOffset.UtcNow.AddHours(1),
                    Account = new FakeAccount { Username = "user@contoso.com" }
                };
            });
        }
    }

    public sealed class FakeDeviceCodeApp {
        public string Message = "To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code FAKECODE1 to authenticate.";
        public string FailWith;
        public string ClaimsSeen;
        public string[] ScopesSeen;
        public int CallbackThreadId;
        public int DelayMilliseconds = 100;
        public FakeDeviceCodeBuilder AcquireTokenWithDeviceCode(IEnumerable<string> scopes, Func<FakeDeviceCodeResult, Task> callback) {
            ScopesSeen = new List<string>(scopes).ToArray();
            return new FakeDeviceCodeBuilder(this, callback);
        }
    }

    public sealed class FakeNoClaimsBuilder {
        public Task<FakeAuthenticationResult> ExecuteAsync(CancellationToken cancellationToken) {
            return Task.FromResult(new FakeAuthenticationResult { AccessToken = "fake-graph-token" });
        }
    }

    public sealed class FakeNoClaimsApp {
        public bool Called;
        public FakeNoClaimsBuilder AcquireTokenWithDeviceCode(IEnumerable<string> scopes, Func<FakeDeviceCodeResult, Task> callback) {
            Called = true;
            return new FakeNoClaimsBuilder();
        }
    }

    public sealed class FakeAppWithoutDeviceCode { }
}
'@
        }
    }

    Context 'When the device code flow succeeds' {
        BeforeAll {
            $App = [OPIMTestFakes.DeviceCode.FakeDeviceCodeApp]::new()
            $Scopes = [string[]]@('User.Read', 'AdministrativeUnit.Read.All')
            $PipelineThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
            $Records = @(InModuleScope Omnicit.PIM -Parameters @{ App = $App; Scopes = $Scopes } {
                    param($App, $Scopes)
                    Invoke-OPIMDeviceCodeAuth -MsalApp $App -Scopes $Scopes 6>&1
                })
            $Info = @($Records | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
            $Output = @($Records | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] })
        }

        It 'writes the sign-in message to the Information stream with the OPIMDeviceCode tag' {
            $Info.Count | Should -Be 1
            $Info[0].Tags | Should -Contain 'OPIMDeviceCode'
        }

        It 'writes the message text and nothing else of the device code result' {
            $Info[0].MessageData | Should -BeOfType [string]
            $Info[0].MessageData | Should -BeExactly $App.Message
        }

        It 'reaches the callback off the pipeline thread, as MSAL does' {
            $App.CallbackThreadId | Should -Not -Be 0
            $App.CallbackThreadId | Should -Not -Be $PipelineThreadId
        }

        It 'returns the authentication result of the flow' {
            $Output.Count | Should -Be 1
            $Output[0].AccessToken | Should -Be 'fake-graph-token'
        }

        It 'requests the scopes it was given' {
            $App.ScopesSeen | Should -Be $Scopes
        }

        It 'chains no claims without a claims challenge' {
            $App.ClaimsSeen | Should -BeNullOrEmpty
        }
    }

    Context 'When a claims challenge is given' {
        BeforeAll {
            $App = [OPIMTestFakes.DeviceCode.FakeDeviceCodeApp]::new()
            $Claims = '{"access_token":{"acrs":{"essential":true,"value":"c1"}}}'
            $null = InModuleScope Omnicit.PIM -Parameters @{ App = $App; Claims = $Claims } {
                param($App, $Claims)
                Invoke-OPIMDeviceCodeAuth -MsalApp $App -Scopes @('User.Read') -ClaimsChallenge $Claims 6>$null
            }
        }

        It 'chains the claims on the device code builder' {
            $App.ClaimsSeen | Should -BeExactly $Claims
        }
    }

    Context 'When a claims challenge is given and the builder has no WithClaims' {
        BeforeAll {
            $App = [OPIMTestFakes.DeviceCode.FakeNoClaimsApp]::new()
            $Caught = $null
            try {
                $null = InModuleScope Omnicit.PIM -Parameters @{ App = $App } {
                    param($App)
                    Invoke-OPIMDeviceCodeAuth -MsalApp $App -Scopes @('User.Read') -ClaimsChallenge '{"access_token":{}}' 6>$null
                }
            } catch {
                $Caught = $PSItem
            }
        }

        It 'throws MsalWithClaimsNotFound after building the device code request' {
            $App.Called | Should -BeTrue
            $Caught.FullyQualifiedErrorId | Should -BeLike 'MsalWithClaimsNotFound*'
        }
    }

    Context 'When the device code flow fails' {
        BeforeAll {
            $App = [OPIMTestFakes.DeviceCode.FakeDeviceCodeApp]::new()
            $App.FailWith = 'code_expired: the device code has expired'
            $Caught = $null
            try {
                $null = InModuleScope Omnicit.PIM -Parameters @{ App = $App } {
                    param($App)
                    Invoke-OPIMDeviceCodeAuth -MsalApp $App -Scopes @('User.Read') 6>$null
                }
            } catch {
                $Caught = $PSItem
            }
        }

        It 'reaches the flow before it fails' {
            $App.CallbackThreadId | Should -Not -Be 0
        }

        It 'throws the terminating error DeviceCodeAuthFailed' {
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -BeLike 'DeviceCodeAuthFailed*'
        }

        It 'names the cause, not the reflection call, in the message' {
            $Caught.Exception.Message | Should -Match 'code_expired'
            $Caught.Exception.Message | Should -Not -Match 'GetResult'
        }

        It 'keeps the cause as the inner exception' {
            $Caught.Exception.InnerException | Should -BeOfType [System.InvalidOperationException]
        }
    }

    Context 'When the MSAL application has no device code method' {
        BeforeAll {
            $App = [OPIMTestFakes.DeviceCode.FakeAppWithoutDeviceCode]::new()
            $Caught = $null
            try {
                $null = InModuleScope Omnicit.PIM -Parameters @{ App = $App } {
                    param($App)
                    Invoke-OPIMDeviceCodeAuth -MsalApp $App -Scopes @('User.Read') 6>$null
                }
            } catch {
                $Caught = $PSItem
            }
        }

        It 'throws DeviceCodeAuthFailed' {
            $Caught.FullyQualifiedErrorId | Should -BeLike 'DeviceCodeAuthFailed*'
            $Caught.Exception.Message | Should -Match 'AcquireTokenWithDeviceCode'
        }
    }
}
