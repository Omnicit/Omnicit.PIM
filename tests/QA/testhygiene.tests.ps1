BeforeAll {
    $script:ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath '..'))).Path

    # =====================================================================================
    # UNIT TEST HYGIENE -- THE TRANSPORT TRIPWIRE, HELD BY PRESENCE.
    #
    # tests/Unit/TestHelpers/OPIMTransportTripwire.ps1 replaces the commands through which module
    # code reaches a tenant or the network with functions that record the call and throw. It only
    # works in a file that installs it: a unit test file that forgets would run with nothing between
    # an unmocked module call and the real transport, and stay green. This gate requires, in every
    # unit test file, a root BeforeAll that calls Install-OPIMTransportTripwire AFTER the module
    # import, and a root AfterAll whose try calls Assert-OPIMTransportTripwire and whose finally calls
    # Uninstall-OPIMTransportTripwire -- a try with no catch, since a catch would swallow the
    # assert's throw and leave the file green. There is no exemption list: every unit test file
    # imports the module.
    #
    # R15: source/ may hold ForEach-Object -Parallel blocks only in the named files, and each may
    #      import only Microsoft.Graph.Authentication and call no tripwire name but its four, since
    #      the -Parallel runspace form (a stand-in Microsoft.Graph.Authentication) covers exactly that.
    # R3:  retired with the module's own MSAL client it guarded (decision A16): no unit test can reach
    #      an MSAL build any more, since Initialize-OPIMAuth signs in through AzAuth's Get-AzToken and
    #      Connect-MgGraph only, which the transport tripwire replaces and refuses.
    # Exact counts: Pester reads Should -Invoke X -Times N as AT LEAST N calls when N is 1 or more
    #      (only -Times 0 implies -Exactly), so a code path that makes one call too many -- a second
    #      activation request, say -- stays green. Every Should -Invoke in a unit test file whose
    #      -Times is not the constant 0 carries -Exactly.
    #
    # The gate reads files statically: it imports nothing and runs no module code. The QA gate
    # files are outside the tripwire on purpose: they call help, the analyzer and pure maps only.
    # =====================================================================================

    # The files allowed to hold ForEach-Object -Parallel blocks (R15). source/ holds no -Parallel
    # block: Wait-OPIMDirectoryRole, the one file that held one, polls in sequence through the
    # module's own transport. A future block goes on this list, and must then satisfy the
    # runspace-form rules below.
    $script:ParallelAllowed = @()

    # The four commands the -Parallel runspace form stands in for (Register-OPIMParallelTransportStandIn).
    $script:RunspaceFormNames = @('Invoke-MgGraphRequest', 'Connect-MgGraph', 'Disconnect-MgGraph', 'Get-MgContext')

    # The floor of the exact-count scan: the unit test files held 1479 Should -Invoke commands on
    # 2026-10-10. A scan under the floor has lost a directory or broken its walk, not found fewer
    # assertions; raise it when the tree genuinely grows.
    $script:InvokeAssertionFloor = 1477

    function Get-TestHygieneRootBlockBody {
        <#
        .SYNOPSIS
        Returns the scriptblock body of every ROOT call of the named Pester block in a parsed file.
        #>
        [OutputType([System.Management.Automation.Language.ScriptBlockAst])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.ScriptBlockAst]$Ast,

            [Parameter(Mandatory)]
            [string]$Name
        )
        if ($null -eq $Ast.EndBlock) { return }
        foreach ($Statement in $Ast.EndBlock.Statements) {
            if ($Statement -isnot [System.Management.Automation.Language.PipelineAst]) { continue }
            $Command = $Statement.PipelineElements[0]
            if ($Command -isnot [System.Management.Automation.Language.CommandAst]) { continue }
            if ($Command.GetCommandName() -ne $Name) { continue }
            $Block = @($Command.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] })[0]
            if ($Block) { $Block.ScriptBlock }
        }
    }

    function Get-TestHygieneDirectCall {
        <#
        .SYNOPSIS
        Returns every statement in a list that is a direct call of the named command.
        #>
        [OutputType([System.Management.Automation.Language.CommandAst])]
        param(
            [AllowNull()]
            [object]$Statements,

            [Parameter(Mandatory)]
            [string]$Name
        )
        foreach ($Statement in @($Statements)) {
            if ($Statement -isnot [System.Management.Automation.Language.PipelineAst]) { continue }
            $Command = $Statement.PipelineElements[0]
            if ($Command -is [System.Management.Automation.Language.CommandAst] -and $Command.GetCommandName() -eq $Name) {
                $Command
            }
        }
    }

    function Get-TestHygieneTripwireFinding {
        <#
        .SYNOPSIS
        Returns one reason per way a unit test file fails to install, check and uninstall the tripwire.
        .DESCRIPTION
        Parses the text and reads only its ROOT BeforeAll and AfterAll (pipelines directly in the
        file's end block). The Install and Assert/Uninstall calls must be direct statements of those
        blocks -- a call buried in a function that nothing invokes would otherwise pass. A root
        BeforeAll "calls Install before Import-Module" when the Install call's StartOffset is not
        greater than the StartOffset of the first Import-Module command in that block, or when the
        block has no Import-Module at all. The try around the Assert call must have no catch clause:
        a catch would swallow the assert's throw. Returns nothing for a file that wires the tripwire.
        #>
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [string]$Text
        )
        $Tokens = $null
        $Errors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$Tokens, [ref]$Errors)
        if (@($Errors).Count -gt 0) {
            'does not parse'
            return
        }

        $BeforeAll = @(Get-TestHygieneRootBlockBody -Ast $Ast -Name 'BeforeAll')
        if ($BeforeAll.Count -eq 0) {
            'no root BeforeAll'
        } else {
            $Installed = $false
            $InstalledInOrder = $false
            foreach ($Body in $BeforeAll) {
                $Installs = @(Get-TestHygieneDirectCall -Statements $Body.EndBlock.Statements -Name 'Install-OPIMTransportTripwire')
                if ($Installs.Count -eq 0) { continue }
                $Installed = $true
                $FirstImport = @($Body.FindAll({
                            param($Node)
                            $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Import-Module'
                        }, $true) | Sort-Object -Property { $_.Extent.StartOffset })[0]
                if ($FirstImport -and $Installs[0].Extent.StartOffset -gt $FirstImport.Extent.StartOffset) {
                    $InstalledInOrder = $true
                }
            }
            if (-not $Installed) {
                'root BeforeAll does not call Install-OPIMTransportTripwire'
            } elseif (-not $InstalledInOrder) {
                'root BeforeAll calls Install-OPIMTransportTripwire before Import-Module'
            }
        }

        $AfterAll = @(Get-TestHygieneRootBlockBody -Ast $Ast -Name 'AfterAll')
        if ($AfterAll.Count -eq 0) {
            'no root AfterAll'
        } else {
            $Checked = $false
            foreach ($Body in $AfterAll) {
                foreach ($Statement in @($Body.EndBlock.Statements)) {
                    if ($Statement -isnot [System.Management.Automation.Language.TryStatementAst]) { continue }
                    if ($null -eq $Statement.Finally) { continue }
                    if ($Statement.CatchClauses.Count -gt 0) { continue }
                    $Asserts = @(Get-TestHygieneDirectCall -Statements $Statement.Body.Statements -Name 'Assert-OPIMTransportTripwire')
                    $Uninstalls = @(Get-TestHygieneDirectCall -Statements $Statement.Finally.Statements -Name 'Uninstall-OPIMTransportTripwire')
                    if ($Asserts.Count -gt 0 -and $Uninstalls.Count -gt 0) { $Checked = $true }
                }
            }
            if (-not $Checked) {
                'root AfterAll does not call Assert-OPIMTransportTripwire inside a try with no catch whose finally calls Uninstall-OPIMTransportTripwire'
            }
        }
    }

    function Get-TestHygieneTripwireNameList {
        <#
        .SYNOPSIS
        Reads the transport names from the keys of the table in the helper's
        Get-OPIMTransportTripwireName, statically -- the helper is parsed, never run.
        #>
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $Function = $Ast.Find({
                param($Node)
                $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Get-OPIMTransportTripwireName'
            }, $true)
        if ($null -eq $Function) { return }
        $Table = @($Function.Body.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.HashtableAst]
                }, $true) | Sort-Object -Property { $_.KeyValuePairs.Count } -Descending)[0]
        if ($null -eq $Table) { return }
        foreach ($Pair in $Table.KeyValuePairs) {
            if ($Pair.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $Pair.Item1.Value }
        }
    }

    function Get-TestHygieneParallelFinding {
        <#
        .SYNOPSIS
        Returns 'line N: reason' for each ForEach-Object -Parallel block in a parsed source file that
        the -Parallel runspace form does not cover (R15).
        .DESCRIPTION
        A block is a ForEach-Object command (or its alias % or foreach) carrying a -Parallel
        parameter (any prefix of three letters or more). Refused: a block in a file outside the
        named list; a -Parallel argument that is not a literal script block, which cannot be read;
        an Import-Module inside the block whose arguments are anything but the module name
        Microsoft.Graph.Authentication; and a call inside the block of a tripwire name outside the
        four the runspace form stands in for. Returns nothing for a file whose blocks are covered.
        #>
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast]$Ast,

            [Parameter(Mandatory)]
            [bool]$Allowed,

            [Parameter(Mandatory)]
            [string[]]$TransportNames,

            [Parameter(Mandatory)]
            [string[]]$RunspaceFormNames
        )
        foreach ($Block in @(Get-TestHygieneParallelBlock -Ast $Ast)) {
            $Line = $Block.Command.Extent.StartLineNumber
            if (-not $Allowed) {
                'line {0}: ForEach-Object -Parallel outside the named list' -f $Line
            }
            if ($Block.Body -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                'line {0}: the -Parallel argument is not a literal script block' -f $Line
                continue
            }
            $Commands = $Block.Body.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst]
                }, $true)
            foreach ($Command in $Commands) {
                $Name = $Command.GetCommandName()
                if ($Name -eq 'Import-Module') {
                    $Arguments = @($Command.CommandElements | Select-Object -Skip 1 | Where-Object { $_ -isnot [System.Management.Automation.Language.CommandParameterAst] })
                    $Graph = @($Arguments | Where-Object {
                            $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $_.Value -eq 'Microsoft.Graph.Authentication'
                        })
                    if ($Arguments.Count -eq 0 -or $Graph.Count -ne $Arguments.Count) {
                        'line {0}: Import-Module inside -Parallel names something other than Microsoft.Graph.Authentication' -f $Command.Extent.StartLineNumber
                    }
                } elseif ($Name -and ($TransportNames -contains $Name) -and ($RunspaceFormNames -notcontains $Name)) {
                    'line {0}: {1} inside -Parallel is not covered by the runspace form' -f $Command.Extent.StartLineNumber, $Name
                }
            }
        }
    }

    function Get-TestHygieneParallelBlock {
        <#
        .SYNOPSIS
        Returns each ForEach-Object -Parallel command in a parsed file, with the -Parallel argument.
        #>
        [OutputType([pscustomobject])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast]$Ast
        )
        $Commands = $Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -in 'ForEach-Object', '%', 'foreach'
            }, $true)
        foreach ($Command in $Commands) {
            $Elements = $Command.CommandElements
            for ($Index = 1; $Index -lt $Elements.Count; $Index++) {
                $Element = $Elements[$Index]
                if ($Element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
                if ($Element.ParameterName.Length -lt 3) { continue }
                if (-not 'Parallel'.StartsWith($Element.ParameterName, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                $Body = if ($Element.Argument) { $Element.Argument } elseif ($Index + 1 -lt $Elements.Count) { $Elements[$Index + 1] } else { $null }
                [pscustomobject]@{ Command = $Command; Body = $Body }
                break
            }
        }
    }

    function Get-TestHygieneInvokeAssertion {
        <#
        .SYNOPSIS
        Returns every Should -Invoke command in a parsed file, and every Pester 6 Should-Invoke.
        #>
        [OutputType([System.Management.Automation.Language.CommandAst])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast]$Ast
        )
        $Ast.FindAll({
                param($Node)
                if ($Node -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
                $Name = $Node.GetCommandName()
                if ($Name -eq 'Should-Invoke') { return $true }
                if ($Name -ne 'Should') { return $false }
                @($Node.CommandElements | Where-Object {
                        $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Invoke'
                    }).Count -gt 0
            }, $true)
    }

    function Get-TestHygieneInexactInvoke {
        <#
        .SYNOPSIS
        Returns every Should -Invoke in a parsed file whose -Times is not the constant 0 and that
        carries no -Exactly switch.
        .DESCRIPTION
        Pester reads Should -Invoke X -Times N as AT LEAST N calls when N is 1 or more; only
        -Times 0 implies -Exactly. The commands are those of Get-TestHygieneInvokeAssertion. The
        -Times argument is read in both forms, -Times 1 and -Times:1, and counts as 0 only when it
        is the numeric constant 0: a variable or any other expression is reported. -Exactly counts
        when it stands alone or as -Exactly:$true. A command with no -Times is not reported, and
        neither is a -Times written abbreviated or a count passed by position, which this scan
        does not read.
        #>
        [OutputType([System.Management.Automation.Language.CommandAst])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast]$Ast
        )
        foreach ($Command in @(Get-TestHygieneInvokeAssertion -Ast $Ast)) {
            $Elements = $Command.CommandElements
            $HasTimes = $false
            $Times = $null
            $Exactly = $false
            for ($Index = 1; $Index -lt $Elements.Count; $Index++) {
                $Element = $Elements[$Index]
                if ($Element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
                if ($Element.ParameterName -eq 'Times') {
                    $HasTimes = $true
                    $Times = if ($Element.Argument) { $Element.Argument } elseif ($Index + 1 -lt $Elements.Count) { $Elements[$Index + 1] } else { $null }
                } elseif ($Element.ParameterName -eq 'Exactly') {
                    $Exactly = $null -eq $Element.Argument -or (
                        $Element.Argument -is [System.Management.Automation.Language.VariableExpressionAst] -and $Element.Argument.VariablePath.UserPath -eq 'true')
                }
            }
            if (-not $HasTimes -or $Exactly) { continue }
            $IsZero = $Times -is [System.Management.Automation.Language.ConstantExpressionAst] -and
                $Times -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $Times.Value -eq 0
            if (-not $IsZero) { $Command }
        }
    }

    function ConvertTo-TestHygieneRelativePath {
        <#
        .SYNOPSIS
        Returns a path relative to the repository root, with forward slashes.
        #>
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )
        [System.IO.Path]::GetRelativePath($script:ProjectPath, $Path).Replace('\', '/')
    }
}

Describe 'Unit test hygiene' -Tags 'TestHygiene' {
    It 'Should install, check and uninstall the transport tripwire in every unit test file' {
        $UnitRoot = Join-Path -Path $script:ProjectPath -ChildPath (Join-Path -Path 'tests' -ChildPath 'Unit')
        $Files = @(Get-ChildItem -Path $UnitRoot -Recurse -File | Where-Object Name -like '*.Tests.ps1')
        $Files.Count | Should -BeGreaterThan 0 -Because 'the gate must measure at least one unit test file; zero files means the enumeration failed and the check ran on nothing'

        $Hits = [System.Collections.Generic.List[string]]::new()
        $Checked = 0
        foreach ($File in $Files) {
            $Relative = ConvertTo-TestHygieneRelativePath -Path $File.FullName
            $Checked++
            foreach ($Reason in @(Get-TestHygieneTripwireFinding -Text ([System.IO.File]::ReadAllText($File.FullName)))) {
                $Hits.Add(('{0}: {1}' -f $Relative, $Reason))
            }
        }

        $Checked | Should -Be $Files.Count -Because 'every unit test file must be checked; there is no exemption list'
        @($Hits).Count | Should -Be 0 -Because ('every unit test file must call Install-OPIMTransportTripwire as a direct statement of its root BeforeAll, after an Import-Module in that block, and end with a root AfterAll {{ try {{ Assert-OPIMTransportTripwire }} finally {{ Uninstall-OPIMTransportTripwire }} }} whose try has no catch; zero findings means every file does. Files that do not: {0}' -f ($Hits -join '; '))
    }

    It 'Should tell a file that wires the tripwire from one that does not (known answer)' {
        $Correct = @'
BeforeAll {
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/x.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'x' { It 'y' { 1 | Should -Be 1 } }
'@
        $NoInstall = @'
BeforeAll {
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/x.ps1"
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'x' { It 'y' { 1 | Should -Be 1 } }
'@
        $InstallFirst = @'
BeforeAll {
    . "$PSScriptRoot/x.ps1"
    Install-OPIMTransportTripwire
    Import-Module Omnicit.PIM -Force
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'x' { It 'y' { 1 | Should -Be 1 } }
'@
        $NoAfterAll = @'
BeforeAll {
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/x.ps1"
    Install-OPIMTransportTripwire
}

Describe 'x' { It 'y' { 1 | Should -Be 1 } }
'@
        $NoTryFinally = @'
BeforeAll {
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/x.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    Assert-OPIMTransportTripwire
    Uninstall-OPIMTransportTripwire
}

Describe 'x' { It 'y' { 1 | Should -Be 1 } }
'@
        # An empty catch swallows the assert's throw, so the file stays green whatever was reached.
        $CatchSwallows = @'
BeforeAll {
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/x.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } catch { } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'x' { It 'y' { 1 | Should -Be 1 } }
'@
        $AfterAllReason = 'root AfterAll does not call Assert-OPIMTransportTripwire inside a try with no catch whose finally calls Uninstall-OPIMTransportTripwire'
        @(Get-TestHygieneTripwireFinding -Text $Correct).Count | Should -Be 0 -Because 'a correctly wired file must produce no finding, or the gate would fail every file'
        @(Get-TestHygieneTripwireFinding -Text $NoInstall) | Should -Be @('root BeforeAll does not call Install-OPIMTransportTripwire')
        @(Get-TestHygieneTripwireFinding -Text $InstallFirst) | Should -Be @('root BeforeAll calls Install-OPIMTransportTripwire before Import-Module')
        @(Get-TestHygieneTripwireFinding -Text $NoAfterAll) | Should -Be @('no root AfterAll')
        @(Get-TestHygieneTripwireFinding -Text $NoTryFinally) | Should -Be @($AfterAllReason)
        @(Get-TestHygieneTripwireFinding -Text $CatchSwallows) | Should -Be @($AfterAllReason)
    }

    It 'Should hold ForEach-Object -Parallel blocks only where the runspace form covers them' {
        $Helper = Join-Path -Path $script:ProjectPath -ChildPath (Join-Path -Path 'tests' -ChildPath (Join-Path -Path 'Unit' -ChildPath (Join-Path -Path 'TestHelpers' -ChildPath 'OPIMTransportTripwire.ps1')))
        $TransportNames = @(Get-TestHygieneTripwireNameList -Path $Helper)
        $TransportNames.Count | Should -BeGreaterThan $script:RunspaceFormNames.Count -Because 'the tripwire names must be read from the helper, or the check below compares against nothing'
        foreach ($Name in $script:RunspaceFormNames) {
            $TransportNames | Should -Contain $Name -Because 'the runspace form stands in for tripwire names only'
        }

        # An empty list means no -Parallel block is allowed anywhere in source/, which the scan below
        # enforces: every block it finds is then outside the named list. The known-answer It below
        # proves the scan can fail, so an empty list does not make this check measure nothing.
        foreach ($Relative in $script:ParallelAllowed) {
            $Path = Join-Path -Path $script:ProjectPath -ChildPath $Relative
            Test-Path -LiteralPath $Path | Should -BeTrue -Because ('a named file must exist, or it silently allows nothing: {0}' -f $Relative)
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
            @(Get-TestHygieneParallelBlock -Ast $Ast).Count | Should -BeGreaterThan 0 -Because ('a named file must hold a ForEach-Object -Parallel block, or its entry is stale: {0}' -f $Relative)
        }

        $SourceRoot = Join-Path -Path $script:ProjectPath -ChildPath 'source'
        $Files = @(Get-ChildItem -Path $SourceRoot -Recurse -File | Where-Object Extension -eq '.ps1')
        $Files.Count | Should -BeGreaterThan 0 -Because 'the gate must read at least one source file'
        $Hits = [System.Collections.Generic.List[string]]::new()
        foreach ($File in $Files) {
            $Relative = ConvertTo-TestHygieneRelativePath -Path $File.FullName
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            $Findings = @(Get-TestHygieneParallelFinding -Ast $Ast -Allowed ($script:ParallelAllowed -contains $Relative) -TransportNames $TransportNames -RunspaceFormNames $script:RunspaceFormNames)
            foreach ($Finding in $Findings) { $Hits.Add(('{0}: {1}' -f $Relative, $Finding)) }
        }
        @($Hits).Count | Should -Be 0 -Because ('the -Parallel runspace form loads a stand-in Microsoft.Graph.Authentication and covers its four commands only, so a -Parallel block must sit in a named file, import only that module and call no other tripwire name; zero means every block does. Blocks that do not: {0}' -f ($Hits -join '; '))
    }

    It 'Should tell a -Parallel block the runspace form covers from one it does not (known answer)' {
        $Names = @('Invoke-MgGraphRequest', 'Connect-MgGraph', 'Disconnect-MgGraph', 'Get-MgContext', 'Get-AzContext', 'Invoke-WebRequest')
        $Graph = @('Invoke-MgGraphRequest', 'Connect-MgGraph', 'Disconnect-MgGraph', 'Get-MgContext')
        $Covered = @'
$Items | ForEach-Object -ThrottleLimit 5 -AsJob -Parallel {
    Import-Module 'Microsoft.Graph.Authentication' -Verbose:$false 4>$null
    Invoke-MgGraphRequest -Method Get -Uri 'u'
}
$Items | ForEach-Object { Get-AzContext }
'@
        $OtherModule = @'
$Items | ForEach-Object -Parallel {
    Import-Module Az.Accounts
    Invoke-MgGraphRequest -Method Get -Uri 'u'
}
'@
        $OtherName = @'
$Items | % -Parallel {
    Import-Module 'Microsoft.Graph.Authentication'
    Get-AzContext
    Invoke-WebRequest -Uri 'u'
}
'@
        $NotLiteral = @'
$Items | ForEach-Object -Parallel $Block
'@
        $Parse = { param($Text) [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null) }

        @(Get-TestHygieneParallelFinding -Ast (& $Parse $Covered) -Allowed $true -TransportNames $Names -RunspaceFormNames $Graph).Count |
            Should -Be 0 -Because 'a covered block in a named file, and a plain ForEach-Object, must produce no finding'
        @(Get-TestHygieneParallelFinding -Ast (& $Parse $Covered) -Allowed $false -TransportNames $Names -RunspaceFormNames $Graph) |
            Should -Be @('line 1: ForEach-Object -Parallel outside the named list')
        @(Get-TestHygieneParallelFinding -Ast (& $Parse $OtherModule) -Allowed $true -TransportNames $Names -RunspaceFormNames $Graph) |
            Should -Be @('line 2: Import-Module inside -Parallel names something other than Microsoft.Graph.Authentication')
        @(Get-TestHygieneParallelFinding -Ast (& $Parse $OtherName) -Allowed $true -TransportNames $Names -RunspaceFormNames $Graph) |
            Should -Be @('line 3: Get-AzContext inside -Parallel is not covered by the runspace form', 'line 4: Invoke-WebRequest inside -Parallel is not covered by the runspace form')
        @(Get-TestHygieneParallelFinding -Ast (& $Parse $NotLiteral) -Allowed $true -TransportNames $Names -RunspaceFormNames $Graph) |
            Should -Be @('line 1: the -Parallel argument is not a literal script block')
    }

    It 'Should give every Should -Invoke with a -Times other than 0 the -Exactly switch' {
        $UnitRoot = Join-Path -Path $script:ProjectPath -ChildPath (Join-Path -Path 'tests' -ChildPath 'Unit')
        $Files = @(Get-ChildItem -Path $UnitRoot -Recurse -File | Where-Object Name -like '*.Tests.ps1')
        $Files.Count | Should -BeGreaterThan 0 -Because 'the gate must read at least one unit test file; zero files means the enumeration failed and the check ran on nothing'

        $Hits = [System.Collections.Generic.List[string]]::new()
        $Scanned = 0
        foreach ($File in $Files) {
            $Relative = ConvertTo-TestHygieneRelativePath -Path $File.FullName
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            $Scanned += @(Get-TestHygieneInvokeAssertion -Ast $Ast).Count
            foreach ($Command in @(Get-TestHygieneInexactInvoke -Ast $Ast)) {
                $Hits.Add(('{0}:{1}' -f $Relative, $Command.Extent.StartLineNumber))
            }
        }

        $Scanned | Should -BeGreaterOrEqual $script:InvokeAssertionFloor -Because ('the unit test files held 1479 Should -Invoke commands on 2026-10-10; {0} scanned means the walk lost files or broke, not that the tree shrank' -f $Scanned)
        @($Hits).Count | Should -Be 0 -Because ('Pester reads -Times N without -Exactly as AT LEAST N calls, so an extra activation, deactivation or write request would stay green; every Should -Invoke whose -Times is not the constant 0 must carry -Exactly. {0} do not: {1}' -f $Hits.Count, ($Hits -join '; '))
    }

    It 'Should tell an inexact Should -Invoke from an exact one (known answer)' {
        $Text = @'
Should -Invoke X -Times 1 -Scope It
Should -Invoke X -Times:2
Should -Invoke X -Times $N
Should -Invoke X -Times 1 -Exactly
Should -Invoke X -Exactly -Times 2
Should -Invoke X -Times 0
Should -Not -Invoke X
Should -Invoke X -Scope It
Should-Invoke -CommandName X -Times 1
Should -Invoke X -Times 1 -Exactly:$false
Should -Invoke X -Times 1 -Exactly:$true
1 | Should -Be 1
Mock X { }
'@
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)

        @(Get-TestHygieneInvokeAssertion -Ast $Ast).Count | Should -Be 11 -Because 'each Should -Invoke and Should-Invoke counts toward the floor, and no other Should or Mock does'
        @(Get-TestHygieneInexactInvoke -Ast $Ast | ForEach-Object { $_.Extent.StartLineNumber }) | Should -Be @(1, 2, 3, 9, 10) -Because 'a -Times other than the constant 0, in either form and also as a variable, needs -Exactly; -Times 0 and a command without -Times are not counts to hold'
    }
}
