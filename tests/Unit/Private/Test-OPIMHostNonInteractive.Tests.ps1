BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Test-OPIMHostNonInteractive' {
    # Ported from Omnicit.EntraRBAC (Test-OERHostNonInteractive, BL-100). The helper reads $Host, so
    # every case runs it in a host of its own: a child pwsh started with the switches under test, a
    # runspace made with no PSHost, and runspaces on a test host (below) whose name and user interface
    # each case chooses. Nothing in any of them signs in, sends a request or calls more of the module
    # than the helper itself.
    BeforeAll {
        $script:RepoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../..')).Path
        $script:ModuleBase = (Get-Module -Name Omnicit.PIM | Select-Object -First 1).ModuleBase
        $script:PwshPath = Join-Path -Path $PSHOME -ChildPath $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })

        # A test host for the in-process cases. TestHost takes the name it reports and its user
        # interface; FieldHostUI carries a private instance field named _throwOnReadAndPrompt, as
        # ConsoleHostUserInterface does, and PlainHostUI carries none. With ThrowOnUi set, reading the
        # host's UI throws; it is set only after the runspace is open, since opening it reads the UI.
        # The field is declared on the concrete class, where GetField with NonPublic finds it.
        if (-not ('OPIMHostNonInteractiveTest.TestHost' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;

namespace OPIMHostNonInteractiveTest
{
    public abstract class TestHostUIBase : PSHostUserInterface
    {
        public override PSHostRawUserInterface RawUI { get { return null; } }
        public override string ReadLine() { return string.Empty; }
        public override SecureString ReadLineAsSecureString() { return null; }
        public override void Write(string value) { }
        public override void Write(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value) { }
        public override void WriteLine(string value) { }
        public override void WriteErrorLine(string value) { }
        public override void WriteDebugLine(string message) { }
        public override void WriteVerboseLine(string message) { }
        public override void WriteWarningLine(string message) { }
        public override void WriteProgress(long sourceId, ProgressRecord record) { }
        public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> descriptions) { return null; }
        public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice) { return defaultChoice; }
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName) { return null; }
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes allowedCredentialTypes, PSCredentialUIOptions options) { return null; }
    }

    public sealed class FieldHostUI : TestHostUIBase
    {
        private bool _throwOnReadAndPrompt;
        public FieldHostUI(bool throwOnReadAndPrompt) { _throwOnReadAndPrompt = throwOnReadAndPrompt; }
        public bool Flag { get { return _throwOnReadAndPrompt; } }
    }

    public sealed class PlainHostUI : TestHostUIBase { }

    public sealed class TestHost : PSHost
    {
        private readonly string _name;
        private readonly PSHostUserInterface _ui;
        private readonly Guid _id = Guid.NewGuid();
        public bool ThrowOnUi { get; set; }
        public TestHost(string name, PSHostUserInterface ui) { _name = name; _ui = ui; }
        public override string Name { get { return _name; } }
        public override Version Version { get { return new Version(1, 0, 0); } }
        public override Guid InstanceId { get { return _id; } }
        public override PSHostUserInterface UI
        {
            get
            {
                if (ThrowOnUi) { throw new InvalidOperationException("This host has no user interface to read."); }
                return _ui;
            }
        }
        public override CultureInfo CurrentCulture { get { return CultureInfo.InvariantCulture; } }
        public override CultureInfo CurrentUICulture { get { return CultureInfo.InvariantCulture; } }
        public override void SetShouldExit(int exitCode) { }
        public override void EnterNestedPrompt() { }
        public override void ExitNestedPrompt() { }
        public override void NotifyBeginApplication() { }
        public override void NotifyEndApplication() { }
    }
}
'@
        }

        # Runs the helper in a new runspace -- on HostObject, or with no PSHost at all when it is
        # $null -- and reports the host's name, what the helper answered, whether the reflection step
        # the helper takes fails there (so a $false came from the catch, not from the host name
        # check), the records it left in that runspace's $Error and the runspace's error stream.
        # The runspace imports the built module's psm1 by path: the manifest would resolve its
        # RequiredModules through PSModulePath, where the tripwire's stand-in Graph module stands
        # first, and the helper needs neither dependency. Its $Error is cleared just before the call,
        # since the import itself can leave records there.
        function script:Invoke-RunspaceHostQuestion {
            param(
                [AllowNull()][System.Management.Automation.Host.PSHost]$HostObject,
                [bool]$ThrowOnUi
            )
            $Runspace = if ($null -eq $HostObject) {
                [runspacefactory]::CreateRunspace()
            } else {
                [runspacefactory]::CreateRunspace($HostObject)
            }
            $Runspace.Open()
            if ($null -ne $HostObject) { $HostObject.ThrowOnUi = $ThrowOnUi }
            $Shell = [powershell]::Create()
            try {
                $Shell.Runspace = $Runspace
                $null = $Shell.AddScript({
                        param($ModuleFile)
                        Import-Module -Name $ModuleFile -Force -ErrorAction Stop
                        $Instance = [System.Reflection.BindingFlags]'NonPublic,Instance'
                        $ReflectionFails = try {
                            $Ui = $Host.GetType().GetProperty('ExternalHost', $Instance).GetValue($Host).UI
                            $null -eq $Ui.GetType().GetField('_throwOnReadAndPrompt', $Instance)
                        } catch {
                            $true
                        }
                        $global:Error.Clear()
                        $Answer = & (Get-Module -Name Omnicit.PIM) { Test-OPIMHostNonInteractive }
                        [PSCustomObject]@{
                            HostName        = $Host.Name
                            ReflectionFails = $ReflectionFails
                            Answer          = $Answer
                            AnswerCount     = @($Answer).Count
                            IsBool          = $Answer -is [bool]
                            ErrorCount      = $global:Error.Count
                        }
                    }.ToString()).AddArgument((Join-Path -Path $script:ModuleBase -ChildPath 'Omnicit.PIM.psm1'))
                $Output = @($Shell.Invoke())
                [PSCustomObject]@{
                    Result = $Output[-1]
                    Errors = @($Shell.Streams.Error | ForEach-Object { $_.ToString() })
                }
            } finally {
                $Shell.Dispose()
                $Runspace.Dispose()
            }
        }
    }

    Context 'When it runs in a console host that pwsh started' {
        # Measured through a child pwsh, since only the console host's own start-up sets the switch.
        # The child imports the BUILT module by path, with -NoProfile, a PSModulePath of the repo's
        # output/module and output/RequiredModules and PowerShell's own module folder only, and every
        # proxy variable pointed at a closed local port; it calls nothing of the module but the
        # helper, and it is killed after 180 seconds. Its standard input is closed, so a prompt reads
        # end of input instead of waiting.
        BeforeAll {
            $script:ChildModuleRoot = Join-Path -Path $script:RepoRoot -ChildPath 'output/module'
            $script:ChildManifest = Join-Path -Path $script:ModuleBase -ChildPath 'Omnicit.PIM.psd1'
            $script:ChildModulePath = @(
                $script:ChildModuleRoot
                (Join-Path -Path $script:RepoRoot -ChildPath 'output/RequiredModules')
                (Join-Path -Path $PSHOME -ChildPath 'Modules')
            ) -join [System.IO.Path]::PathSeparator
            $script:ChildProxyNames = @('HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY', 'https_proxy', 'http_proxy', 'all_proxy')

            # The script every child runs. It takes its paths from the environment the parent gives
            # it, so no path is pasted into code.
            $script:ChildScript = Join-Path -Path $TestDrive -ChildPath 'Ask-HostQuestion.ps1'
            $ChildText = @(
                '$ErrorActionPreference = ''Stop'''
                '$env:PSModulePath = $env:OPIMTEST_PSMODULEPATH'
                'foreach ($Name in ''HTTPS_PROXY'', ''HTTP_PROXY'', ''ALL_PROXY'', ''https_proxy'', ''http_proxy'', ''all_proxy'') {'
                '    [System.Environment]::SetEnvironmentVariable($Name, ''http://127.0.0.1:9'')'
                '}'
                'Import-Module -Name $env:OPIMTEST_MANIFEST -Force -ErrorAction Stop'
                '''ANSWER:'' + (& (Get-Module -Name Omnicit.PIM) { Test-OPIMHostNonInteractive })'
            ) -join "`n"
            [System.IO.File]::WriteAllText($script:ChildScript, $ChildText + "`n", [System.Text.UTF8Encoding]::new($false))
            $script:ChildCommand = "& '{0}'" -f [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($script:ChildScript)

            function script:Invoke-ChildHostQuestion {
                param([string[]]$HostArgument)
                $Info = [System.Diagnostics.ProcessStartInfo]::new($script:PwshPath)
                foreach ($Argument in $HostArgument) { $Info.ArgumentList.Add($Argument) }
                $Info.UseShellExecute = $false
                $Info.RedirectStandardInput = $true
                $Info.RedirectStandardOutput = $true
                $Info.RedirectStandardError = $true
                $Info.Environment['PSModulePath'] = $script:ChildModulePath
                $Info.Environment['OPIMTEST_PSMODULEPATH'] = $script:ChildModulePath
                $Info.Environment['OPIMTEST_MANIFEST'] = $script:ChildManifest
                foreach ($Name in $script:ChildProxyNames) { $Info.Environment[$Name] = 'http://127.0.0.1:9' }
                $Process = [System.Diagnostics.Process]::Start($Info)
                try {
                    $Process.StandardInput.Close()
                    $StdOut = $Process.StandardOutput.ReadToEndAsync()
                    $StdErr = $Process.StandardError.ReadToEndAsync()
                    $TimedOut = -not $Process.WaitForExit(180000)
                    if ($TimedOut) {
                        $Process.Kill($true)
                        $null = $Process.WaitForExit(10000)
                    } else {
                        # The parameterless overload also waits for the redirected streams to end.
                        $Process.WaitForExit()
                    }
                    [PSCustomObject]@{
                        TimedOut = $TimedOut
                        ExitCode = if ($TimedOut) { $null } else { $Process.ExitCode }
                        Output   = @($StdOut.GetAwaiter().GetResult() -split '\r?\n' | Where-Object { $_ })
                        Error    = $StdErr.GetAwaiter().GetResult()
                    }
                } finally {
                    $Process.Dispose()
                }
            }
        }

        It 'imports a built module from the repo''s output/module' {
            # The children import the module this file imported; it has to be a build, not source.
            $script:ModuleBase.StartsWith($script:ChildModuleRoot, [System.StringComparison]::OrdinalIgnoreCase) | Should -BeTrue -Because "the module under test is at $($script:ModuleBase)"
            Test-Path -LiteralPath $script:ChildManifest | Should -BeTrue
        }

        It 'returns <Expected> for pwsh <Shown>' -ForEach @(
            @{ Shown = '-NonInteractive -File'; Expected = $true; Arguments = @('-NoProfile', '-NonInteractive', '-File', '<script>') }
            @{ Shown = '-noni -File, the shortest form of the switch'; Expected = $true; Arguments = @('-NoProfile', '-noni', '-File', '<script>') }
            @{ Shown = '-NonInteractive -Command'; Expected = $true; Arguments = @('-NoProfile', '-NonInteractive', '-Command', '<command>') }
            @{ Shown = '-File without -NonInteractive'; Expected = $false; Arguments = @('-NoProfile', '-File', '<script>') }
            @{ Shown = '-Command without -NonInteractive'; Expected = $false; Arguments = @('-NoProfile', '-Command', '<command>') }
            @{ Shown = '-File with -NonInteractive only as an argument of the script'; Expected = $false; Arguments = @('-NoProfile', '-File', '<script>', '-NonInteractive') }
        ) {
            $HostArgument = foreach ($Argument in $Arguments) {
                switch -CaseSensitive ($Argument) {
                    '<script>' { $script:ChildScript }
                    '<command>' { $script:ChildCommand }
                    default { $Argument }
                }
            }
            $Run = Invoke-ChildHostQuestion -HostArgument $HostArgument
            $Run.TimedOut | Should -BeFalse -Because 'the child is killed after 180 seconds'
            $Run.ExitCode | Should -Be 0 -Because "the child wrote: $($Run.Error)"
            @($Run.Output | Where-Object { $_ -like 'ANSWER:*' }) | Should -Be @("ANSWER:$Expected")
        }
    }

    Context 'When it runs in a host that is not the console host' {
        It 'returns $false in a runspace made with no PSHost (the Default Host)' {
            $Run = Invoke-RunspaceHostQuestion -HostObject $null
            $Run.Result.HostName | Should -BeExactly 'Default Host'
            $Run.Result.IsBool | Should -BeTrue
            $Run.Result.Answer | Should -BeFalse
            $Run.Result.ErrorCount | Should -Be 0
            $Run.Errors | Should -BeNullOrEmpty
        }

        It 'returns $false for another host whose user interface carries the switch set' {
            # The field reads $true here, so only the host name check can answer $false.
            $Ui = [OPIMHostNonInteractiveTest.FieldHostUI]::new($true)
            $Run = Invoke-RunspaceHostQuestion -HostObject ([OPIMHostNonInteractiveTest.TestHost]::new('OPIMTestHost', $Ui))
            $Run.Result.HostName | Should -BeExactly 'OPIMTestHost'
            $Run.Result.ReflectionFails | Should -BeFalse -Because 'the reflection would read the field as set'
            $Ui.Flag | Should -BeTrue
            $Run.Result.IsBool | Should -BeTrue
            $Run.Result.Answer | Should -BeFalse
            $Run.Result.ErrorCount | Should -Be 0
            $Run.Errors | Should -BeNullOrEmpty
        }
    }

    Context 'When a host named ConsoleHost has the field the helper reads' {
        It 'returns <Expected> when the field holds <Expected>' -ForEach @(
            @{ Expected = $true }
            @{ Expected = $false }
        ) {
            $Ui = [OPIMHostNonInteractiveTest.FieldHostUI]::new($Expected)
            $Run = Invoke-RunspaceHostQuestion -HostObject ([OPIMHostNonInteractiveTest.TestHost]::new('ConsoleHost', $Ui))
            $Run.Result.HostName | Should -BeExactly 'ConsoleHost'
            $Run.Result.ReflectionFails | Should -BeFalse
            $Run.Result.AnswerCount | Should -Be 1
            $Run.Result.IsBool | Should -BeTrue
            $Run.Result.Answer | Should -Be $Expected
            $Run.Result.ErrorCount | Should -Be 0
            $Run.Errors | Should -BeNullOrEmpty
        }
    }

    Context 'When the reflection fails' {
        # A host that calls itself ConsoleHost, so the helper gets past its host name check and into
        # the reflection, which then fails: the "any step of the reflection fails" path of its help,
        # which answers $false and leaves no record in $Error.
        It 'returns $false and leaves no error record when the user interface has no _throwOnReadAndPrompt field' {
            $Run = Invoke-RunspaceHostQuestion -HostObject ([OPIMHostNonInteractiveTest.TestHost]::new('ConsoleHost', [OPIMHostNonInteractiveTest.PlainHostUI]::new()))
            $Run.Result.HostName | Should -BeExactly 'ConsoleHost'
            $Run.Result.ReflectionFails | Should -BeTrue
            $Run.Result.AnswerCount | Should -Be 1
            $Run.Result.IsBool | Should -BeTrue
            $Run.Result.Answer | Should -BeFalse
            $Run.Result.ErrorCount | Should -Be 0
            $Run.Errors | Should -BeNullOrEmpty
        }

        It 'returns $false and leaves no error record when reading the user interface throws' {
            $FakeHost = [OPIMHostNonInteractiveTest.TestHost]::new('ConsoleHost', [OPIMHostNonInteractiveTest.FieldHostUI]::new($true))
            $Run = Invoke-RunspaceHostQuestion -HostObject $FakeHost -ThrowOnUi $true
            $Run.Result.HostName | Should -BeExactly 'ConsoleHost'
            $Run.Result.ReflectionFails | Should -BeTrue
            $Run.Result.AnswerCount | Should -Be 1
            $Run.Result.IsBool | Should -BeTrue
            $Run.Result.Answer | Should -BeFalse
            $Run.Result.ErrorCount | Should -Be 0
            $Run.Errors | Should -BeNullOrEmpty
        }
    }

    Context 'When it is called in the test process' {
        It 'returns one [bool] and leaves no error record' {
            $Result = InModuleScope Omnicit.PIM {
                $Before = $global:Error.Count
                $Answer = @(Test-OPIMHostNonInteractive -ErrorAction SilentlyContinue)
                [PSCustomObject]@{ Count = $Answer.Count; IsBool = ($Answer[0] -is [bool]); NewErrors = $global:Error.Count - $Before }
            }
            $Result.Count | Should -Be 1
            $Result.IsBool | Should -BeTrue
            $Result.NewErrors | Should -Be 0
        }

        It 'takes no parameters' {
            InModuleScope Omnicit.PIM {
                $Command = Get-Command -Name Test-OPIMHostNonInteractive
                $Own = @($Command.Parameters.Keys | Where-Object {
                        $_ -notin [System.Management.Automation.Cmdlet]::CommonParameters -and
                        $_ -notin [System.Management.Automation.Cmdlet]::OptionalCommonParameters
                    })
                $Own.Count | Should -Be 0
            }
        }
    }

    Context 'When the source is read' {
        It 'is the only file under source that names _throwOnReadAndPrompt' {
            $SourceRoot = Join-Path -Path $script:RepoRoot -ChildPath 'source'
            $Named = @(Get-ChildItem -Path $SourceRoot -Recurse -File -Filter '*.ps1' |
                    Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '_throwOnReadAndPrompt' } |
                    ForEach-Object { $_.Name })
            $Named | Should -Be @('Test-OPIMHostNonInteractive.ps1')
        }

        It 'is called in Initialize-OPIMAuth and by no other file under source' {
            $SourceRoot = Join-Path -Path $script:RepoRoot -ChildPath 'source'
            $Callers = @(Get-ChildItem -Path $SourceRoot -Recurse -File -Filter '*.ps1' |
                    Where-Object { $_.Name -ne 'Test-OPIMHostNonInteractive.ps1' -and
                        (Get-Content -LiteralPath $_.FullName -Raw) -match 'Test-OPIMHostNonInteractive' } |
                    ForEach-Object { $_.Name })
            $Callers | Should -Be @('Initialize-OPIMAuth.ps1')
        }
    }
}
