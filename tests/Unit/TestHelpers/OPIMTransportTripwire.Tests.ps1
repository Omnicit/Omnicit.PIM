# Known-answer suite for the transport tripwire (tests/Unit/TestHelpers/OPIMTransportTripwire.ps1).
#
# Rule for every test below: a transport name is NEVER called by name. It is resolved first, what it
# resolved to is asserted, and only the resolved command object is invoked -- so a broken
# installation fails an assertion and can never reach a real cmdlet. The places that call a
# transport name themselves from the module's scope (the Get-OPIMMsalApplication test and the
# module-code-path cases of the first Describe) first assert that the name resolves to the
# tripwire from the module scope.
#
# The suite holds its OWN expected list, never Get-OPIMTransportTripwireName, so deleting a name from
# the helper turns it red.

BeforeDiscovery {
    $script:Expected = @(
        @{ Name = 'Invoke-MgGraphRequest'; Module = 'Microsoft.Graph.Authentication'; Form = 'Cmdlet'; Arguments = @{ Method = 'GET'; Uri = 'v1.0/opim-tripwire-known-answer' } }
        @{ Name = 'Connect-MgGraph'; Module = 'Microsoft.Graph.Authentication'; Form = 'Cmdlet'; Arguments = @{} }
        @{ Name = 'Disconnect-MgGraph'; Module = 'Microsoft.Graph.Authentication'; Form = 'Cmdlet'; Arguments = @{} }
        @{ Name = 'Get-MgContext'; Module = 'Microsoft.Graph.Authentication'; Form = 'Cmdlet'; Arguments = @{} }
        # AzAuth's sign-in to Azure Resource Manager. A compiled cmdlet without IDynamicParameters
        # (measured 2026-10-09, AzAuth 2.9.0), so it is replaced in the plain Cmdlet form.
        @{ Name = 'Get-AzToken'; Module = 'AzAuth'; Form = 'Cmdlet'; Arguments = @{ Resource = 'https://management.azure.com'; Tenant = 'contoso.onmicrosoft.com' } }
        @{ Name = 'Invoke-WebRequest'; Module = 'Microsoft.PowerShell.Utility'; Form = 'Cmdlet'; Arguments = @{ Uri = 'https://opim-tripwire.invalid/known-answer' } }
        @{ Name = 'Invoke-RestMethod'; Module = 'Microsoft.PowerShell.Utility'; Form = 'Cmdlet'; Arguments = @{ Uri = 'https://opim-tripwire.invalid/known-answer' } }
    )
}

BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire

    # Resolves a name from the module's scope, where module code resolves it. -CommandType narrows
    # the lookup; without it, the result is what an unqualified call in module code would run.
    function Resolve-TripwireKnownAnswerCommand {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [string]$CommandType
        )
        $Module = Get-Module -Name Omnicit.PIM | Select-Object -First 1
        if ($CommandType) {
            & $Module { param($N, $T) Get-Command -Name $N -CommandType $T -ErrorAction Ignore } $Name $CommandType
        } else {
            & $Module { param($N) Get-Command -Name $N -ErrorAction Ignore } $Name
        }
    }

    # Invokes a RESOLVED command object from the module's scope, never a name.
    function Invoke-TripwireKnownAnswerCommand {
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.CommandInfo]$Command,

            [hashtable]$Arguments = @{}
        )
        $Module = Get-Module -Name Omnicit.PIM | Select-Object -First 1
        & $Module { param($C, $A) & $C @A } $Command $Arguments
    }

    # The real command a replacement was built from, found the way the helper finds it.
    function Get-TripwireKnownAnswerRealCommand {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [string]$Module
        )
        @(Get-Command -Name $Name -Module $Module -ErrorAction SilentlyContinue | Where-Object {
                $_.CommandType -in 'Cmdlet', 'Function' -and -not (Test-OPIMTransportTripwireFunction -Command $_)
            })
    }

    # Install-OPIMTransportTripwire starts new empty hit lists, so a test that reinstalls carries any
    # hit already recorded in this file over, and it stays visible to the root AfterAll.
    function Get-TripwireKnownAnswerCarry {
        $Queue = [System.AppDomain]::CurrentDomain.GetData('OPIMTransportTripwire.ParallelHits')
        [pscustomobject]@{
            Hits     = @($global:OPIMTransportTripwireHits)
            Parallel = if ($null -ne $Queue) { @($Queue.ToArray()) } else { @() }
        }
    }

    function Restore-TripwireKnownAnswerCarry {
        param(
            [Parameter(Mandatory)]
            [object]$Carry
        )
        foreach ($Hit in $Carry.Hits) { $global:OPIMTransportTripwireHits.Add($Hit) }
        $Queue = [System.AppDomain]::CurrentDomain.GetData('OPIMTransportTripwire.ParallelHits')
        foreach ($Hit in $Carry.Parallel) { $Queue.Enqueue($Hit) }
    }
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

# The tripwire as module code meets it: a transport command reached from the module's own scope, not
# through a resolved command object. First in the file and without the BeforeEach below, which mocks
# Initialize-OPIMAuth -- the last case here runs the real function.
Describe 'OPIMTransportTripwire module code paths' {
    It 'gives the Get-AzToken replacement the parameters module code passes, and no dynamic parameters' {
        $Function = Resolve-TripwireKnownAnswerCommand -Name 'Get-AzToken' -CommandType Function
        Test-OPIMTransportTripwireFunction -Command $Function | Should -BeTrue
        $Real = @(Get-TripwireKnownAnswerRealCommand -Name 'Get-AzToken' -Module 'AzAuth')
        $Real.Count | Should -Be 1 -Because 'exactly one real Get-AzToken must exist in AzAuth'
        $Real[0] | Should -BeOfType ([System.Management.Automation.CmdletInfo])
        [System.Management.Automation.IDynamicParameters].IsAssignableFrom($Real[0].ImplementingType) | Should -BeFalse

        foreach ($Name in 'Resource', 'Tenant', 'Interactive', 'DeviceCode', 'Force') {
            $Function.Parameters.ContainsKey($Name) | Should -BeTrue -Because ('the replacement must carry -{0}, or a call that passes it fails to bind before it is recorded' -f $Name)
            $Function.Parameters[$Name].ParameterType | Should -Be $Real[0].Parameters[$Name].ParameterType
        }
        foreach ($Name in 'Interactive', 'DeviceCode', 'Force') {
            $Function.Parameters[$Name].SwitchParameter | Should -BeTrue -Because ('-{0} is a switch on the real cmdlet' -f $Name)
        }

        $Ast = $Function.ScriptBlock.Ast
        if ($Ast -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $Ast = $Ast.Body }
        $Ast.ParamBlock | Should -Not -BeNullOrEmpty
        $Ast.EndBlock | Should -Not -BeNullOrEmpty
        $Ast.DynamicParamBlock | Should -BeNullOrEmpty
    }

    It 'records and refuses Get-AzToken reached through module code, parameter names only' {
        $Resolved = Resolve-TripwireKnownAnswerCommand -Name 'Get-AzToken'
        Test-OPIMTransportTripwireFunction -Command $Resolved | Should -BeTrue -Because 'Get-AzToken must resolve to the tripwire from the module scope before module code calls it'
        $Before = $global:OPIMTransportTripwireHits.Count

        $Message = try {
            & (Get-Module -Name Omnicit.PIM | Select-Object -First 1) { Get-AzToken -Resource 'https://management.azure.com' -Tenant 'contoso.onmicrosoft.com' -DeviceCode }
            'RETURNED'
        } catch {
            $_.Exception.Message
        }

        try {
            $Message | Should -BeLike 'OPIM transport tripwire: a unit test reached the real Get-AzToken.*'
            $global:OPIMTransportTripwireHits.Count | Should -Be ($Before + 1)
            $Record = $global:OPIMTransportTripwireHits[$global:OPIMTransportTripwireHits.Count - 1]
            $Record.Command | Should -Be 'Get-AzToken'
            (@($Record.Parameters -split ',') | Sort-Object) -join ',' | Should -Be 'DeviceCode,Resource,Tenant'
            ($Record | Out-String) | Should -Not -BeLike '*contoso*'
            ($Record | Out-String) | Should -Not -BeLike '*management.azure.com*'
        } finally {
            while ($global:OPIMTransportTripwireHits.Count -gt $Before) {
                $global:OPIMTransportTripwireHits.RemoveAt($global:OPIMTransportTripwireHits.Count - 1)
            }
        }
    }

    It 'records and refuses Invoke-WebRequest reached through module code, parameter names only' {
        $Resolved = Resolve-TripwireKnownAnswerCommand -Name 'Invoke-WebRequest'
        Test-OPIMTransportTripwireFunction -Command $Resolved | Should -BeTrue -Because 'Invoke-WebRequest must resolve to the tripwire from the module scope before module code calls it'
        $Before = $global:OPIMTransportTripwireHits.Count

        $Message = try {
            & (Get-Module -Name Omnicit.PIM | Select-Object -First 1) { Invoke-WebRequest -Uri 'https://management.azure.com/opim-tripwire-known-answer' }
            'RETURNED'
        } catch {
            $_.Exception.Message
        }

        try {
            $Message | Should -BeLike 'OPIM transport tripwire: a unit test reached the real Invoke-WebRequest.*'
            $global:OPIMTransportTripwireHits.Count | Should -Be ($Before + 1)
            $Record = $global:OPIMTransportTripwireHits[$global:OPIMTransportTripwireHits.Count - 1]
            $Record.Command | Should -Be 'Invoke-WebRequest'
            $Record.Parameters | Should -Be 'Uri'
            ($Record | Out-String) | Should -Not -BeLike '*management.azure.com*'
        } finally {
            while ($global:OPIMTransportTripwireHits.Count -gt $Before) {
                $global:OPIMTransportTripwireHits.RemoveAt($global:OPIMTransportTripwireHits.Count - 1)
            }
        }
    }

    # Runs the real Initialize-OPIMAuth -IncludeARM against a cached Graph state that holds no ARM
    # token, with nothing but the tripwire in front of the AzAuth sign-in: the tripwire records the
    # Get-AzToken call and refuses it, and the refusal ends the function in AzureConnectFailed.
    It 'records Get-AzToken, parameter names only, when Initialize-OPIMAuth -IncludeARM reaches it unmocked, and ends in AzureConnectFailed' {
        # Asserted before module code runs, so a broken installation fails here and the sign-in
        # below can never reach the real Get-AzToken.
        $Resolved = Resolve-TripwireKnownAnswerCommand -Name 'Get-AzToken'
        Test-OPIMTransportTripwireFunction -Command $Resolved | Should -BeTrue -Because 'Get-AzToken must resolve to the tripwire from the module scope before module code calls it'
        $Real = @(Get-TripwireKnownAnswerRealCommand -Name 'Get-AzToken' -Module 'AzAuth')
        $Real.Count | Should -Be 1 -Because 'exactly one real Get-AzToken must exist in AzAuth'
        # Get-OPIMMsalApplication is never reached with a cached Graph token; the mock keeps it so.
        Mock -ModuleName Omnicit.PIM Get-OPIMMsalApplication {}
        $Before = $global:OPIMTransportTripwireHits.Count

        $Caught = InModuleScope Omnicit.PIM {
            # A cached Graph sign-in as Initialize-OPIMAuth writes it, with its account and no ARM token.
            $script:_OPIMAuthState = @{
                TenantId         = '22222222-2222-2222-2222-222222222222'
                TokenTenantId    = '22222222-2222-2222-2222-222222222222'
                AuthorityTenant  = '22222222-2222-2222-2222-222222222222'
                Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
                ObjectId         = '33333333-3333-3333-3333-333333333333'
                GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ClaimsSatisfied  = $false
                DeviceCode       = $true
                ArmToken         = $null
                ArmTokenExpiry   = $null
                ArmTokenTenantId = $null
                ArmTokenObjectId = $null
                ArmResourceUrl   = $null
            }
            $Outcome = $null
            try {
                Initialize-OPIMAuth -IncludeARM
            } catch {
                $Outcome = $PSItem
            } finally {
                $script:_OPIMAuthState = $null
            }
            $Outcome
        }

        try {
            $Caught | Should -Not -BeNullOrEmpty -Because 'the unmocked ARM sign-in must end the function'
            $Caught.FullyQualifiedErrorId | Should -BeLike 'AzureConnectFailed*'
            $Hits = @($global:OPIMTransportTripwireHits | Select-Object -Skip $Before)
            $TokenHits = @($Hits | Where-Object { $_.Command -eq 'Get-AzToken' })
            $TokenHits.Count | Should -Be 1 -Because ('the hit list must hold the one Get-AzToken call; it holds: {0}' -f ((@($Hits | ForEach-Object { $_.Command }) -join ', ')))
            @($TokenHits[0].Parameters -split ',') | Should -Contain 'Resource'
            @($TokenHits[0].Parameters -split ',') | Should -Contain 'Tenant'
            foreach ($Hit in $TokenHits) {
                foreach ($Name in @($Hit.Parameters -split ',')) {
                    @($Real[0].Parameters.Keys) | Should -Contain $Name -Because 'a hit holds parameter names only, each one a parameter of the real Get-AzToken'
                }
                ($Hit | Out-String) | Should -Not -BeLike '*22222222*'
                ($Hit | Out-String) | Should -Not -BeLike '*contoso*'
            }
        } finally {
            while ($global:OPIMTransportTripwireHits.Count -gt $Before) {
                $global:OPIMTransportTripwireHits.RemoveAt($global:OPIMTransportTripwireHits.Count - 1)
            }
        }
    }
}

Describe 'OPIMTransportTripwire' {
    # Per test, not only once: the re-import test below replaces the module instance, and a mock
    # made before it stays on the old one, so every test after it would otherwise run against a
    # module whose Initialize-OPIMAuth is not mocked.
    BeforeEach {
        Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
    }

    It 'names exactly the expected seven commands, with their modules and forms' -ForEach @(@{ ExpectedSpecs = $script:Expected }) {
        @($ExpectedSpecs).Count | Should -Be 7 -Because 'the known-answer list itself must not be empty or short, or the comparison below proves nothing'
        $Actual = Get-OPIMTransportTripwireName
        (@($Actual.Keys) | Sort-Object) -join ',' | Should -Be ((@($ExpectedSpecs | ForEach-Object { $_.Name }) | Sort-Object) -join ',')
        foreach ($Spec in $ExpectedSpecs) {
            $Actual[$Spec.Name].Module | Should -Be $Spec.Module -Because ('{0} must be resolved in the module that owns it' -f $Spec.Name)
            $Actual[$Spec.Name].Form | Should -Be $Spec.Form -Because ('{0} must be replaced in the form measured for it' -f $Spec.Name)
        }
    }

    It 'resolves <Name> from the module scope to the tripwire' -ForEach $script:Expected {
        $Resolved = Resolve-TripwireKnownAnswerCommand -Name $Name
        $Resolved | Should -BeOfType ([System.Management.Automation.FunctionInfo])
        Test-OPIMTransportTripwireFunction -Command $Resolved | Should -BeTrue
    }

    It "gives the <Name> replacement exactly the real command's parameters and parameter sets, and no dynamicparam" -ForEach $script:Expected {
        $Function = Resolve-TripwireKnownAnswerCommand -Name $Name -CommandType Function
        Test-OPIMTransportTripwireFunction -Command $Function | Should -BeTrue
        $Real = @(Get-TripwireKnownAnswerRealCommand -Name $Name -Module $Module)
        $Real.Count | Should -Be 1 -Because ('exactly one real {0} must exist in {1}' -f $Name, $Module)
        $Real = $Real[0]

        # Every replacement is built in the Cmdlet form; a new form needs checks of its own here.
        $Form | Should -Be 'Cmdlet'
        $Real | Should -BeOfType ([System.Management.Automation.CmdletInfo])
        [System.Management.Automation.IDynamicParameters].IsAssignableFrom($Real.ImplementingType) | Should -BeFalse

        (@($Function.Parameters.Keys) | Sort-Object) -join ',' | Should -Be ((@($Real.Parameters.Keys) | Sort-Object -Unique) -join ',')
        $Function.ParameterSets.Count | Should -Be $Real.ParameterSets.Count

        # A function made from scriptblock text carries a ScriptBlockAst, not a FunctionDefinitionAst,
        # so its dynamicparam block is read from the Ast itself. The param and end blocks are
        # asserted first so the null below is not vacuous.
        $Ast = $Function.ScriptBlock.Ast
        if ($Ast -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $Ast = $Ast.Body }
        $Ast | Should -BeOfType ([System.Management.Automation.Language.ScriptBlockAst])
        $Ast.ParamBlock | Should -Not -BeNullOrEmpty
        $Ast.EndBlock | Should -Not -BeNullOrEmpty
        $Ast.DynamicParamBlock | Should -BeNullOrEmpty
    }

    It 'keeps a Mock -ModuleName on <Name> winning and records no hit' -ForEach $script:Expected {
        Mock -ModuleName Omnicit.PIM -CommandName $Name -MockWith { 'mocked' }
        $Before = $global:OPIMTransportTripwireHits.Count

        $Resolved = Resolve-TripwireKnownAnswerCommand -Name $Name
        $Resolved.CommandType | Should -Be 'Alias'
        $Module = Get-Module -Name Omnicit.PIM | Select-Object -First 1
        $Target = & $Module { param($A) $A.ResolvedCommand } $Resolved
        $Target | Should -BeOfType ([System.Management.Automation.FunctionInfo])
        Test-OPIMTransportTripwireFunction -Command $Target | Should -BeFalse

        Invoke-TripwireKnownAnswerCommand -Command $Resolved -Arguments $Arguments | Should -Be 'mocked'
        $global:OPIMTransportTripwireHits.Count | Should -Be $Before
        Should -Invoke -ModuleName Omnicit.PIM -CommandName $Name -Times 1 -Exactly
    }

    It 'records and refuses an unmocked call to <Name>' -ForEach $script:Expected {
        $Resolved = Resolve-TripwireKnownAnswerCommand -Name $Name -CommandType Function
        Test-OPIMTransportTripwireFunction -Command $Resolved | Should -BeTrue
        $Before = $global:OPIMTransportTripwireHits.Count

        $Message = try {
            Invoke-TripwireKnownAnswerCommand -Command $Resolved -Arguments $Arguments
            'RETURNED'
        } catch {
            $_.Exception.Message
        }

        try {
            $Message | Should -BeLike ('OPIM transport tripwire: a unit test reached the real {0}.*' -f $Name)
            $global:OPIMTransportTripwireHits.Count | Should -Be ($Before + 1)
            $global:OPIMTransportTripwireHits[$global:OPIMTransportTripwireHits.Count - 1].Command | Should -Be $Name
        } finally {
            while ($global:OPIMTransportTripwireHits.Count -gt $Before) {
                $global:OPIMTransportTripwireHits.RemoveAt($global:OPIMTransportTripwireHits.Count - 1)
            }
        }
    }

    It 'records parameter names in a hit, never values' {
        $Resolved = Resolve-TripwireKnownAnswerCommand -Name 'Invoke-WebRequest' -CommandType Function
        Test-OPIMTransportTripwireFunction -Command $Resolved | Should -BeTrue
        $Before = $global:OPIMTransportTripwireHits.Count

        try {
            Invoke-TripwireKnownAnswerCommand -Command $Resolved -Arguments @{ Uri = 'https://opim-tripwire.invalid/NOT-A-REAL-TOKEN-sentinel-value' }
        } catch {
            $null = $_
        }

        try {
            $global:OPIMTransportTripwireHits.Count | Should -Be ($Before + 1)
            $Record = $global:OPIMTransportTripwireHits[$global:OPIMTransportTripwireHits.Count - 1]
            $Record.Parameters | Should -Be 'Uri'
            ($Record | Out-String) | Should -Not -BeLike '*sentinel*'
        } finally {
            while ($global:OPIMTransportTripwireHits.Count -gt $Before) {
                $global:OPIMTransportTripwireHits.RemoveAt($global:OPIMTransportTripwireHits.Count - 1)
            }
        }
    }

    It 'throws from Assert-OPIMTransportTripwire on a recorded hit' {
        $global:OPIMTransportTripwireHits.Add([pscustomobject]@{ Command = 'Invoke-WebRequest'; Caller = 'known-answer'; Parameters = 'Uri' })
        try {
            { Assert-OPIMTransportTripwire } | Should -Throw -ExpectedMessage '*reached Invoke-WebRequest from known-answer (parameters: Uri)*'
        } finally {
            $global:OPIMTransportTripwireHits.RemoveAt($global:OPIMTransportTripwireHits.Count - 1)
        }
    }

    It 'throws from Assert-OPIMTransportTripwire on a recorded -Parallel hit' {
        $Queue = [System.AppDomain]::CurrentDomain.GetData('OPIMTransportTripwire.ParallelHits')
        $Queue -is [System.Collections.Concurrent.ConcurrentQueue[object]] | Should -BeTrue -Because 'the queue must exist, or the enqueue below records nothing'
        $Saved = @($Queue.ToArray())
        $Queue.Enqueue([pscustomobject]@{ Command = 'Invoke-MgGraphRequest'; Caller = 'known-answer'; Parameters = 'Method,Uri' })
        try {
            { Assert-OPIMTransportTripwire } | Should -Throw -ExpectedMessage '*reached Invoke-MgGraphRequest in a -Parallel runspace from known-answer (parameters: Method,Uri)*'
        } finally {
            $Queue.Clear()
            foreach ($Hit in $Saved) { $Queue.Enqueue($Hit) }
        }
    }

    It 'throws from Assert-OPIMTransportTripwire when a name no longer resolves' {
        $Carry = Get-TripwireKnownAnswerCarry
        try {
            # Unqualified on purpose: Remove-Item honours no scope qualifier on the function: drive,
            # so 'function:global:...' would remove nothing. From here the nearest definition is the
            # global replacement, which is exactly what the precondition proves.
            Remove-Item -Path function:Disconnect-MgGraph
            Test-OPIMTransportTripwireFunction -Command (Resolve-TripwireKnownAnswerCommand -Name 'Disconnect-MgGraph' -CommandType Function) | Should -BeFalse -Because 'the replacement has to be gone, or the assertion below proves nothing'
            { Assert-OPIMTransportTripwire } | Should -Throw -ExpectedMessage '*Disconnect-MgGraph no longer resolves to the tripwire from the module scope*'
        } finally {
            Install-OPIMTransportTripwire
            Restore-TripwireKnownAnswerCarry -Carry $Carry
        }
    }

    It 'throws from Assert-OPIMTransportTripwire when the runspace form is no longer first on PSModulePath' {
        $Saved = $env:PSModulePath
        try {
            $env:PSModulePath = (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'opim-tripwire-known-answer') + [System.IO.Path]::PathSeparator + $env:PSModulePath
            { Assert-OPIMTransportTripwire } | Should -Throw -ExpectedMessage '*the -Parallel runspace form is no longer first on PSModulePath*'
        } finally {
            $env:PSModulePath = $Saved
        }
        { Assert-OPIMTransportTripwire } | Should -Not -Throw -Because 'with PSModulePath restored the same check must pass, or the throw above came from something else'
    }

    It 'keeps every replacement resolving from the module scope through a re-import of Omnicit.PIM, and restores the tripwire with Install-OPIMTransportTripwire' -ForEach @(@{ ExpectedSpecs = $script:Expected }) {
        # Every replacement is a global function, which a re-import does not touch.
        $Carry = Get-TripwireKnownAnswerCarry
        $Old = Get-Module -Name Omnicit.PIM | Select-Object -First 1
        try {
            Import-Module Omnicit.PIM -Force
            $New = Get-Module -Name Omnicit.PIM | Select-Object -First 1
            [object]::ReferenceEquals($Old, $New) | Should -BeFalse -Because 'the check below has to run against a NEW module instance'
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}

            $Message = try { Assert-OPIMTransportTripwire; 'PASSED' } catch { $_.Exception.Message }
            foreach ($Spec in $ExpectedSpecs) {
                $Message | Should -Not -BeLike ('*{0} no longer resolves*' -f $Spec.Name) -Because 'a global replacement survives a re-import'
                $FromNew = Resolve-TripwireKnownAnswerCommand -Name $Spec.Name -CommandType Function
                Test-OPIMTransportTripwireFunction -Command $FromNew | Should -BeTrue -Because ('{0} must still resolve to the tripwire from the NEW module scope' -f $Spec.Name)
            }
        } finally {
            Install-OPIMTransportTripwire
            Restore-TripwireKnownAnswerCarry -Carry $Carry
        }
        foreach ($Spec in $ExpectedSpecs) {
            $Resolved = Resolve-TripwireKnownAnswerCommand -Name $Spec.Name
            $Resolved | Should -BeOfType ([System.Management.Automation.FunctionInfo])
            Test-OPIMTransportTripwireFunction -Command $Resolved | Should -BeTrue
        }
    }

    It 'loads the stand-in in a -Parallel runspace, refusing and recording an unmocked call and serving a registered stand-in instead' {
        $Root = $global:OPIMTransportTripwireRunspaceRoot
        $Root | Should -Not -BeNullOrEmpty
        @($env:PSModulePath -split [System.IO.Path]::PathSeparator)[0] | Should -BeExactly $Root
        $Queue = [System.AppDomain]::CurrentDomain.GetData('OPIMTransportTripwire.ParallelHits')
        $Saved = @($Queue.ToArray())

        # Imports Microsoft.Graph.Authentication by name, as a -Parallel block must (source/ holds
        # none today; Wait-OPIMDirectoryRole once did), then resolves Invoke-MgGraphRequest and
        # invokes it only when it is the stand-in. The stand-in's module is identified by the root's
        # leaf, which carries a GUID unique to this installation, so a temp path the OS reports in
        # another spelling (a symlinked temp folder) still matches.
        $Probe = {
            Import-Module 'Microsoft.Graph.Authentication' -Verbose:$false 4>$null
            $RootLeaf = Split-Path -Path $using:Root -Leaf
            $Resolved = Get-Command -Name Invoke-MgGraphRequest -ErrorAction Ignore
            $IsStandIn = ($Resolved -is [System.Management.Automation.FunctionInfo]) -and
            $Resolved.ScriptBlock.ToString().Contains('OPIM-TRANSPORT-TRIPWIRE') -and
            $null -ne $Resolved.Module -and
            (Split-Path -Path (Split-Path -Path $Resolved.Module.ModuleBase -Parent) -Leaf) -ceq $RootLeaf
            $Outcome = if (-not $IsStandIn) {
                'NOT-STAND-IN'
            } else {
                try {
                    $Response = & $Resolved -Method GET -Uri 'v1.0/opim-tripwire-parallel'
                    'RETURNED:' + $Response.value.status
                } catch {
                    'REFUSED:' + $_.Exception.Message
                }
            }
            [pscustomobject]@{
                FirstPath = @($env:PSModulePath -split [System.IO.Path]::PathSeparator)[0]
                Outcome   = $Outcome
            }
        }

        try {
            $Refused = @(1 | ForEach-Object -Parallel $Probe)
            $Refused.Count | Should -Be 1
            $Refused[0].FirstPath | Should -BeExactly $Root
            $Refused[0].Outcome | Should -BeLike 'REFUSED:OPIM transport tripwire: a -Parallel runspace reached the real Invoke-MgGraphRequest.*'
            $Queue.Count | Should -Be ($Saved.Count + 1)
            $Last = @($Queue.ToArray())[-1]
            $Last.Command | Should -Be 'Invoke-MgGraphRequest'
            (@($Last.Parameters -split ',') | Sort-Object) -join ',' | Should -Be 'Method,Uri'
        } finally {
            $Queue.Clear()
            foreach ($Hit in $Saved) { $Queue.Enqueue($Hit) }
        }

        Register-OPIMParallelTransportStandIn -Name 'Invoke-MgGraphRequest' -Response @{ value = @(@{ status = 'Provisioned' }) }
        try {
            $Served = @(1 | ForEach-Object -Parallel $Probe)
            $Served.Count | Should -Be 1
            $Served[0].Outcome | Should -Be 'RETURNED:Provisioned'
            $Calls = @(Get-OPIMParallelTransportStandInCall)
            $Calls.Count | Should -Be 1
            $Calls[0].Command | Should -Be 'Invoke-MgGraphRequest'
            (@($Calls[0].Parameters -split ',') | Sort-Object) -join ',' | Should -Be 'Method,Uri'
            $Queue.Count | Should -Be $Saved.Count -Because 'a served stand-in call is not a hit'
        } finally {
            Unregister-OPIMParallelTransportStandIn
        }
        @(Get-OPIMParallelTransportStandInCall).Count | Should -Be 0 -Because 'Unregister-OPIMParallelTransportStandIn drains the call records'
    }

    It 'stops Get-OPIMMsalApplication with no cache and no Get-MgContext mock before the MSAL build' {
        # R3: Get-OPIMMsalApplication reaches the MSAL reflection only after its Get-MgContext call
        # (Get-OPIMMsalApplication.ps1:46), so an unmocked path stops there.
        $Resolved = Resolve-TripwireKnownAnswerCommand -Name 'Get-MgContext'
        Test-OPIMTransportTripwireFunction -Command $Resolved | Should -BeTrue -Because 'Get-MgContext must resolve to the tripwire, unmocked, before module code calls it'
        $Before = $global:OPIMTransportTripwireHits.Count

        $Outcome = InModuleScope Omnicit.PIM {
            $script:_OPIMMsalApp = $null
            $script:_OPIMMsalAppTenantId = $null
            $Message = try {
                Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com'
                'RETURNED'
            } catch {
                $_.Exception.Message
            }
            [pscustomobject]@{
                Message   = $Message
                AppIsNull = $null -eq $script:_OPIMMsalApp
            }
        }

        try {
            $Outcome.Message | Should -BeLike 'OPIM transport tripwire: a unit test reached the real Get-MgContext.*'
            $Outcome.AppIsNull | Should -BeTrue -Because 'the tripwire must stop the call before the MSAL application is built and cached'
            $global:OPIMTransportTripwireHits.Count | Should -Be ($Before + 1)
            $global:OPIMTransportTripwireHits[$global:OPIMTransportTripwireHits.Count - 1].Command | Should -Be 'Get-MgContext'
        } finally {
            while ($global:OPIMTransportTripwireHits.Count -gt $Before) {
                $global:OPIMTransportTripwireHits.RemoveAt($global:OPIMTransportTripwireHits.Count - 1)
            }
        }
    }

    # Uninstalls too, so it puts the tripwire back in a finally, like the one below. A marked function
    # left in the module scope is not a global replacement and the uninstall does not remove it; the
    # leftover check has to report it, and this proves that half of the check.
    It 'reports a marked function left in the module scope as still defined after uninstall' {
        $Carry = Get-TripwireKnownAnswerCarry
        $Module = Get-Module -Name Omnicit.PIM | Select-Object -First 1
        try {
            & $Module { Set-Item -Path 'function:script:Invoke-MgGraphRequest' -Value ([scriptblock]::Create('# OPIM-TRANSPORT-TRIPWIRE planted by the test')) }
            $Planted = Resolve-TripwireKnownAnswerCommand -Name 'Invoke-MgGraphRequest' -CommandType Function
            Test-OPIMTransportTripwireFunction -Command $Planted | Should -BeTrue
            $Planted.ScriptBlock.ToString() | Should -BeLike '*planted by the test*' -Because 'the module scope has to hold the planted function, or the uninstall below proves nothing'

            { Uninstall-OPIMTransportTripwire } | Should -Throw -ExpectedMessage '*still defined after uninstall: Invoke-MgGraphRequest*'
        } finally {
            # Unqualified, as the helper explains: the nearest definition from here is the planted one.
            & $Module { Remove-Item -Path 'function:Invoke-MgGraphRequest' -ErrorAction SilentlyContinue }
            Install-OPIMTransportTripwire
            Restore-TripwireKnownAnswerCarry -Carry $Carry
        }
        $Resolved = Resolve-TripwireKnownAnswerCommand -Name 'Invoke-MgGraphRequest' -CommandType Function
        Test-OPIMTransportTripwireFunction -Command $Resolved | Should -BeTrue
        $Resolved.ScriptBlock.ToString() | Should -Not -BeLike '*planted by the test*' -Because 'the planted function has to be gone from the module scope'
    }

    # LAST in the file: it uninstalls, and puts the tripwire back in a finally.
    It 'restores the real commands and removes the runspace form on uninstall, and puts the tripwire back on install' -ForEach @(@{ ExpectedSpecs = $script:Expected }) {
        @($ExpectedSpecs).Count | Should -Be 7
        $Carry = Get-TripwireKnownAnswerCarry
        $Root = $global:OPIMTransportTripwireRunspaceRoot
        $Root | Should -Not -BeNullOrEmpty
        [System.IO.Directory]::Exists($Root) | Should -BeTrue -Because 'the runspace root must exist before uninstall, or its absence after proves nothing'
        try {
            Uninstall-OPIMTransportTripwire
            foreach ($Spec in $ExpectedSpecs) {
                # Resolved only, never invoked: with the tripwire gone this is the real command.
                $Resolved = Resolve-TripwireKnownAnswerCommand -Name $Spec.Name
                $Resolved | Should -BeOfType ([System.Management.Automation.CmdletInfo])
            }
            @($env:PSModulePath -split [System.IO.Path]::PathSeparator) | Should -Not -Contain $Root
            [System.IO.Directory]::Exists($Root) | Should -BeFalse
            foreach ($Key in 'OPIMTransportTripwire.ParallelHits', 'OPIMTransportTripwire.StandIn', 'OPIMTransportTripwire.StandInCalls') {
                $null -eq [System.AppDomain]::CurrentDomain.GetData($Key) | Should -BeTrue -Because ('uninstall must clear the AppDomain key {0}' -f $Key)
            }
        } finally {
            Install-OPIMTransportTripwire
            Restore-TripwireKnownAnswerCarry -Carry $Carry
        }
        foreach ($Spec in $ExpectedSpecs) {
            $Resolved = Resolve-TripwireKnownAnswerCommand -Name $Spec.Name
            $Resolved | Should -BeOfType ([System.Management.Automation.FunctionInfo])
            Test-OPIMTransportTripwireFunction -Command $Resolved | Should -BeTrue
        }
        @($env:PSModulePath -split [System.IO.Path]::PathSeparator)[0] | Should -BeExactly $global:OPIMTransportTripwireRunspaceRoot
    }
}
