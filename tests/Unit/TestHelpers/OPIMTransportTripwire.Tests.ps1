# Known-answer suite for the transport tripwire (tests/Unit/TestHelpers/OPIMTransportTripwire.ps1).
#
# Rule for every test below: a transport name is NEVER called by name. It is resolved first, what it
# resolved to is asserted, and only the resolved command object is invoked -- so a broken
# installation fails an assertion and can never reach a real cmdlet. The one place module code
# calls a transport name itself (the Get-OPIMMsalApplication test) first asserts that the name
# resolves to the tripwire from the module scope.
#
# The suite holds its OWN expected list, never Get-OPIMTransportTripwireName, so deleting a name from
# the helper turns it red.

BeforeDiscovery {
    $script:Expected = @(
        @{ Name = 'Invoke-MgGraphRequest'; Module = 'Microsoft.Graph.Authentication'; Form = 'Cmdlet'; Arguments = @{ Method = 'GET'; Uri = 'v1.0/opim-tripwire-known-answer' } }
        @{ Name = 'Connect-MgGraph'; Module = 'Microsoft.Graph.Authentication'; Form = 'Cmdlet'; Arguments = @{} }
        @{ Name = 'Disconnect-MgGraph'; Module = 'Microsoft.Graph.Authentication'; Form = 'Cmdlet'; Arguments = @{} }
        @{ Name = 'Get-MgContext'; Module = 'Microsoft.Graph.Authentication'; Form = 'Cmdlet'; Arguments = @{} }
        @{ Name = 'Connect-AzAccount'; Module = 'Az.Accounts'; Form = 'DynamicCmdlet'; Arguments = @{} }
        @{ Name = 'Disconnect-AzAccount'; Module = 'Az.Accounts'; Form = 'DynamicCmdlet'; Arguments = @{} }
        @{ Name = 'Get-AzContext'; Module = 'Az.Accounts'; Form = 'DynamicCmdlet'; Arguments = @{} }
        @{ Name = 'Get-AzAccessToken'; Module = 'Az.Accounts'; Form = 'DynamicCmdlet'; Arguments = @{ TenantId = 'contoso.onmicrosoft.com'; AsSecureString = $true } }
        @{ Name = 'Update-AzConfig'; Module = 'Az.Accounts'; Form = 'DynamicCmdlet'; Arguments = @{ EnableLoginByWam = $false; Scope = 'Process' } }
        @{ Name = 'Get-AzRoleEligibilitySchedule'; Module = 'Az.Resources'; Form = 'ModuleFunction'; Arguments = @{ Scope = '/' } }
        @{ Name = 'Get-AzRoleAssignmentScheduleInstance'; Module = 'Az.Resources'; Form = 'ModuleFunction'; Arguments = @{ Scope = '/' } }
        @{ Name = 'Get-AzRoleAssignmentScheduleRequest'; Module = 'Az.Resources'; Form = 'ModuleFunction'; Arguments = @{ Scope = '/' } }
        # The parameter shape source/Public/Enable-OPIMAzureRole.ps1:122 sends.
        @{ Name = 'New-AzRoleAssignmentScheduleRequest'; Module = 'Az.Resources'; Form = 'ModuleFunction'; Arguments = @{
                Name                            = 'opim-tripwire-request'
                Scope                           = '/'
                PrincipalId                     = 'opim-tripwire-principal'
                RoleDefinitionId                = 'opim-tripwire-role-definition'
                RequestType                     = 'SelfActivate'
                LinkedRoleEligibilityScheduleId = 'opim-tripwire-eligibility'
                Justification                   = 'opim tripwire known answer'
                ExpirationType                  = 'AfterDuration'
                ExpirationDuration              = 'PT1H'
            }
        }
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

Describe 'OPIMTransportTripwire' {
    # Per test, not only once: the re-import test below replaces the module instance, and a mock
    # made before it stays on the old one, so every test after it would otherwise run against a
    # module whose Initialize-OPIMAuth is not mocked.
    BeforeEach {
        Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
    }

    It 'the helper names exactly the expected fifteen commands, with their modules and forms' -ForEach @(@{ ExpectedSpecs = $script:Expected }) {
        @($ExpectedSpecs).Count | Should -Be 15 -Because 'the known-answer list itself must not be empty or short, or the comparison below proves nothing'
        $Actual = Get-OPIMTransportTripwireName
        (@($Actual.Keys) | Sort-Object) -join ',' | Should -Be ((@($ExpectedSpecs | ForEach-Object { $_.Name }) | Sort-Object) -join ',')
        foreach ($Spec in $ExpectedSpecs) {
            $Actual[$Spec.Name].Module | Should -Be $Spec.Module -Because ('{0} must be resolved in the module that owns it' -f $Spec.Name)
            $Actual[$Spec.Name].Form | Should -Be $Spec.Form -Because ('{0} must be replaced in the form measured for it' -f $Spec.Name)
        }
    }

    It '<Name> resolves from the module scope to the tripwire' -ForEach $script:Expected {
        $Resolved = Resolve-TripwireKnownAnswerCommand -Name $Name
        $Resolved | Should -BeOfType ([System.Management.Automation.FunctionInfo])
        Test-OPIMTransportTripwireFunction -Command $Resolved | Should -BeTrue
    }

    It "<Name>'s replacement has exactly the real command's parameters and parameter sets, and no dynamicparam" -ForEach $script:Expected {
        $Function = Resolve-TripwireKnownAnswerCommand -Name $Name -CommandType Function
        Test-OPIMTransportTripwireFunction -Command $Function | Should -BeTrue
        $Real = @(Get-TripwireKnownAnswerRealCommand -Name $Name -Module $Module)
        $Real.Count | Should -Be 1 -Because ('exactly one real {0} must exist in {1}' -f $Name, $Module)
        $Real = $Real[0]

        $ExpectedKeys = [System.Collections.Generic.List[string]]::new()
        foreach ($Key in $Real.Parameters.Keys) { $ExpectedKeys.Add($Key) }
        if ($Form -eq 'Cmdlet') {
            $Real | Should -BeOfType ([System.Management.Automation.CmdletInfo])
            [System.Management.Automation.IDynamicParameters].IsAssignableFrom($Real.ImplementingType) | Should -BeFalse
        } elseif ($Form -eq 'DynamicCmdlet') {
            $Real | Should -BeOfType ([System.Management.Automation.CmdletInfo])
            $Dynamic = ([System.Management.Automation.IDynamicParameters][Activator]::CreateInstance($Real.ImplementingType)).GetDynamicParameters()
            @($Dynamic.Keys).Count | Should -BeGreaterThan 0 -Because 'a DynamicCmdlet must return dynamic parameters, or the union below proves nothing'
            foreach ($Key in $Dynamic.Keys) {
                if (-not $ExpectedKeys.Contains($Key)) { $ExpectedKeys.Add($Key) }
            }
        } else {
            $Real | Should -BeOfType ([System.Management.Automation.FunctionInfo])
            $Real.Source | Should -Be 'Az.Resources'
        }

        (@($Function.Parameters.Keys) | Sort-Object) -join ',' | Should -Be ((@($ExpectedKeys) | Sort-Object -Unique) -join ',')
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

    It 'a Mock -ModuleName on <Name> still wins and records no hit' -ForEach $script:Expected {
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

    It 'an unmocked call to <Name> is recorded and refused' -ForEach $script:Expected {
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

    It 'a hit records parameter names, never values' {
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

    It 'a Mock -ModuleName on Update-AzConfig with a -ParameterFilter on EnableLoginByWam binds and matches the call shape module code uses' {
        # Initialize-OPIMAuth.ps1:303 calls Update-AzConfig -EnableLoginByWam $false -Scope Process
        # -ErrorAction SilentlyContinue. EnableLoginByWam is a DYNAMIC parameter of the real cmdlet,
        # so this proves the materialized static parameter binds under a mock and the filter sees it.
        Mock -ModuleName Omnicit.PIM Update-AzConfig { 'mocked' } -ParameterFilter { $EnableLoginByWam -eq $false }
        $Before = $global:OPIMTransportTripwireHits.Count

        $Resolved = Resolve-TripwireKnownAnswerCommand -Name 'Update-AzConfig'
        $Resolved.CommandType | Should -Be 'Alias'
        $Module = Get-Module -Name Omnicit.PIM | Select-Object -First 1
        Test-OPIMTransportTripwireFunction -Command (& $Module { param($A) $A.ResolvedCommand } $Resolved) | Should -BeFalse

        Invoke-TripwireKnownAnswerCommand -Command $Resolved -Arguments @{ EnableLoginByWam = $false; Scope = 'Process'; ErrorAction = 'SilentlyContinue' } | Should -Be 'mocked'
        $global:OPIMTransportTripwireHits.Count | Should -Be $Before
        Should -Invoke -ModuleName Omnicit.PIM Update-AzConfig -ParameterFilter { $EnableLoginByWam -eq $false -and $Scope -eq 'Process' } -Times 1 -Exactly
    }

    It 'Assert-OPIMTransportTripwire fails on a recorded hit' {
        $global:OPIMTransportTripwireHits.Add([pscustomobject]@{ Command = 'Invoke-WebRequest'; Caller = 'known-answer'; Parameters = 'Uri' })
        try {
            { Assert-OPIMTransportTripwire } | Should -Throw -ExpectedMessage '*reached Invoke-WebRequest from known-answer (parameters: Uri)*'
        } finally {
            $global:OPIMTransportTripwireHits.RemoveAt($global:OPIMTransportTripwireHits.Count - 1)
        }
    }

    It 'Assert-OPIMTransportTripwire fails on a recorded -Parallel hit' {
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

    It 'Assert-OPIMTransportTripwire fails when a name no longer resolves' {
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

    It 'Assert-OPIMTransportTripwire fails when the runspace form is no longer first on PSModulePath' {
        $Saved = $env:PSModulePath
        try {
            $env:PSModulePath = (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'opim-tripwire-known-answer') + [System.IO.Path]::PathSeparator + $env:PSModulePath
            { Assert-OPIMTransportTripwire } | Should -Throw -ExpectedMessage '*the -Parallel runspace form is no longer first on PSModulePath*'
        } finally {
            $env:PSModulePath = $Saved
        }
        { Assert-OPIMTransportTripwire } | Should -Not -Throw -Because 'with PSModulePath restored the same check must pass, or the throw above came from something else'
    }

    It 'a re-import of Omnicit.PIM is reported by Assert-OPIMTransportTripwire, and Install-OPIMTransportTripwire puts it back' -ForEach @(@{ ExpectedSpecs = $script:Expected }) {
        $FunctionNames = @($ExpectedSpecs | Where-Object { $_.Form -eq 'ModuleFunction' } | ForEach-Object { $_.Name })
        $GlobalNames = @($ExpectedSpecs | Where-Object { $_.Form -ne 'ModuleFunction' } | ForEach-Object { $_.Name })
        $FunctionNames.Count | Should -Be 4
        $Carry = Get-TripwireKnownAnswerCarry
        $Old = Get-Module -Name Omnicit.PIM | Select-Object -First 1
        try {
            Import-Module Omnicit.PIM -Force
            $New = Get-Module -Name Omnicit.PIM | Select-Object -First 1
            [object]::ReferenceEquals($Old, $New) | Should -BeFalse -Because 'the check below has to run against a NEW module instance'
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}

            $Message = try { Assert-OPIMTransportTripwire; 'PASSED' } catch { $_.Exception.Message }
            foreach ($Name in $FunctionNames) {
                $Message | Should -BeLike ('*{0} no longer resolves to the tripwire from the module scope*' -f $Name)
            }
            foreach ($Name in $GlobalNames) {
                $Message | Should -Not -BeLike ('*{0} no longer resolves*' -f $Name) -Because 'a global replacement survives a re-import'
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

    It 'a -Parallel runspace loads the stand-in, which refuses and records an unmocked call, and serves a registered stand-in instead' {
        $Root = $global:OPIMTransportTripwireRunspaceRoot
        $Root | Should -Not -BeNullOrEmpty
        @($env:PSModulePath -split [System.IO.Path]::PathSeparator)[0] | Should -BeExactly $Root
        $Queue = [System.AppDomain]::CurrentDomain.GetData('OPIMTransportTripwire.ParallelHits')
        $Saved = @($Queue.ToArray())

        # Imports Microsoft.Graph.Authentication by name, as Wait-OPIMDirectoryRole.ps1:68 does, then
        # resolves Invoke-MgGraphRequest and invokes it only when it is the stand-in. The stand-in's
        # module is identified by the root's leaf, which carries a GUID unique to this installation,
        # so a temp path the OS reports in another spelling (a symlinked temp folder) still matches.
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

    It 'Get-OPIMMsalApplication with no cache and no Get-MgContext mock is stopped by the tripwire before the MSAL build' {
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

    # LAST in the file: it uninstalls, and puts the tripwire back in a finally.
    It 'uninstall restores the real commands and removes the runspace form, and install puts the tripwire back' -ForEach @(@{ ExpectedSpecs = $script:Expected }) {
        @($ExpectedSpecs).Count | Should -Be 15
        $Carry = Get-TripwireKnownAnswerCarry
        $Root = $global:OPIMTransportTripwireRunspaceRoot
        $Root | Should -Not -BeNullOrEmpty
        [System.IO.Directory]::Exists($Root) | Should -BeTrue -Because 'the runspace root must exist before uninstall, or its absence after proves nothing'
        try {
            Uninstall-OPIMTransportTripwire
            foreach ($Spec in $ExpectedSpecs) {
                # Resolved only, never invoked: with the tripwire gone this is the real command.
                $Resolved = Resolve-TripwireKnownAnswerCommand -Name $Spec.Name
                if ($Spec.Form -eq 'ModuleFunction') {
                    $Resolved | Should -BeOfType ([System.Management.Automation.FunctionInfo])
                    $Resolved.Source | Should -Be 'Az.Resources'
                } else {
                    $Resolved | Should -BeOfType ([System.Management.Automation.CmdletInfo])
                }
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
