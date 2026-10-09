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
    # R3:  No unit test may reach the MSAL build behind Get-MgContext. (a) Get-OPIMMsalApplication
    #      is run only in the two named test files, called or named in a string that can run it
    #      (a name in a variable, Get-Command, a script block made from a string, Invoke-Expression),
    #      and there every Get-MgContext mock throws. (b) Initialize-OPIMAuth, which calls it, runs
    #      unmocked only where no Get-MgContext mock returns, or Get-OPIMMsalApplication is mocked too.
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

    # The files allowed to invoke Get-OPIMMsalApplication (R3).
    $script:MsalAllowed = @(
        'tests/Unit/Private/Get-OPIMMsalApplication.Tests.ps1'
        'tests/Unit/TestHelpers/OPIMTransportTripwire.Tests.ps1'
    )

    # The two commands whose run reaches a real MSAL client (R3): Get-OPIMMsalApplication builds one
    # past its Get-MgContext call, and Initialize-OPIMAuth calls Get-OPIMMsalApplication.
    $script:MsalName = 'Get-OPIMMsalApplication'
    $script:InitializeName = 'Initialize-OPIMAuth'

    # Pester commands whose string arguments name a command without running it: the target of a
    # Mock or of Should -Invoke, a block name, a -Because text (R3).
    $script:ReferenceOnlyCommands = @('Mock', 'Should', 'Assert-MockCalled', 'Describe', 'Context', 'It')

    # This gate names the commands it looks for, as data and in known-answer texts that it parses
    # and never runs, so the R3 reference scan skips this one file.
    $script:ReferenceScanExempt = @('tests/QA/testhygiene.tests.ps1')

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

    function Get-TestHygieneMockOf {
        <#
        .SYNOPSIS
        Returns each Mock command in a parsed file that mocks the named command, with its mock body.
        .DESCRIPTION
        The mocked command is the argument of -CommandName, or else the first string constant after
        Mock that is not the argument of -ModuleName. The mock body is the argument of -MockWith, or
        else the first script block that is not the argument of -ParameterFilter.
        #>
        [OutputType([pscustomobject])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast]$Ast,

            [Parameter(Mandatory)]
            [string]$Name
        )
        $Mocks = $Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Mock'
            }, $true)
        foreach ($Mock in $Mocks) {
            $Elements = $Mock.CommandElements
            $Named = @{}
            $Consumed = [System.Collections.Generic.HashSet[int]]::new()
            for ($Index = 1; $Index -lt $Elements.Count; $Index++) {
                $Element = $Elements[$Index]
                if ($Element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
                if ($Element.ParameterName -notin 'CommandName', 'ModuleName', 'MockWith', 'ParameterFilter') { continue }
                if ($Element.Argument) {
                    $Named[$Element.ParameterName] = $Element.Argument
                } elseif ($Index + 1 -lt $Elements.Count) {
                    $Named[$Element.ParameterName] = $Elements[$Index + 1]
                    $null = $Consumed.Add($Index + 1)
                }
            }
            $Mocked = if ($Named.ContainsKey('CommandName')) {
                $Named['CommandName']
            } else {
                $Free = for ($Index = 1; $Index -lt $Elements.Count; $Index++) {
                    if ($Elements[$Index] -is [System.Management.Automation.Language.StringConstantExpressionAst] -and -not $Consumed.Contains($Index)) { $Elements[$Index] }
                }
                @($Free)[0]
            }
            if ($Mocked -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or $Mocked.Value -ne $Name) { continue }
            $Body = if ($Named.ContainsKey('MockWith')) {
                $Named['MockWith']
            } else {
                $Blocks = for ($Index = 1; $Index -lt $Elements.Count; $Index++) {
                    if ($Elements[$Index] -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and -not $Consumed.Contains($Index)) { $Elements[$Index] }
                }
                @($Blocks)[0]
            }
            [pscustomobject]@{ Mock = $Mock; Body = $Body }
        }
    }

    function Test-TestHygieneTextRunsCommand {
        <#
        .SYNOPSIS
        Returns $true when a string, parsed as PowerShell, runs the named command.
        .DESCRIPTION
        True when the parsed text holds a command of that name, or a string that does, to a depth
        of three: the text of a script block made from a string, of Invoke-Expression, or a name
        kept in a variable and then called with & (R3). A text that does not contain the name is
        never parsed. A path such as tests/Unit/Private/<name>.Tests.ps1 names a script, not the
        command, and does not run it.
        #>
        [OutputType([bool])]
        param(
            [AllowNull()]
            [AllowEmptyString()]
            [string]$Text,

            [Parameter(Mandatory)]
            [string]$Name,

            [int]$Depth = 0
        )
        if ($Depth -gt 3 -or [string]::IsNullOrEmpty($Text)) { return $false }
        if ($Text.IndexOf($Name, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
        $Call = $Ast.Find({
                param($Node)
                $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq $Name
            }, $true)
        if ($Call) { return $true }
        $Strings = $Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $Node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
            }, $true)
        foreach ($String in $Strings) {
            if ($String.Value -ne $Text -and (Test-TestHygieneTextRunsCommand -Text $String.Value -Name $Name -Depth ($Depth + 1))) { return $true }
        }
        $false
    }

    function Get-TestHygieneCommandReference {
        <#
        .SYNOPSIS
        Returns each place in a parsed file that can run the named command, by line.
        .DESCRIPTION
        'Call' is a command of that name -- bare, quoted after &, or dot-sourced. 'String' is a
        string literal that can run it (Test-TestHygieneTextRunsCommand): a name kept in a
        variable, a Get-Command argument, a script block made from a string, Invoke-Expression.
        The name element of a command is the 'Call' half, and a string argument of a command in
        $script:ReferenceOnlyCommands names the command without running it; neither is a 'String'.
        #>
        [OutputType([pscustomobject])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast]$Ast,

            [Parameter(Mandatory)]
            [string]$Name
        )
        $Found = [System.Collections.Generic.List[object]]::new()
        $Calls = $Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq $Name
            }, $true)
        foreach ($Call in $Calls) { $Found.Add([pscustomobject]@{ Kind = 'Call'; Node = $Call; Line = $Call.Extent.StartLineNumber }) }

        $Strings = $Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $Node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
            }, $true)
        foreach ($String in $Strings) {
            $Owner = $String.Parent
            if ($Owner -is [System.Management.Automation.Language.CommandParameterAst]) { $Owner = $Owner.Parent }
            if ($Owner -is [System.Management.Automation.Language.CommandAst]) {
                if ([object]::ReferenceEquals($Owner.CommandElements[0], $String)) { continue }
                if ($script:ReferenceOnlyCommands -contains $Owner.GetCommandName()) { continue }
            }
            if (Test-TestHygieneTextRunsCommand -Text $String.Value -Name $Name) {
                $Found.Add([pscustomobject]@{ Kind = 'String'; Node = $String; Line = $String.Extent.StartLineNumber })
            }
        }
        $Found | Sort-Object -Property Line -Stable
    }

    function Get-TestHygieneScopeRoot {
        <#
        .SYNOPSIS
        Returns the parts of a parsed file whose Mock commands Pester has in effect where a node runs.
        .DESCRIPTION
        Follows Pester 5's mock scope outwards from the node: the body of the innermost It that
        holds it, and the BeforeAll and BeforeEach blocks that are direct statements of each
        enclosing Describe or Context and of the file itself. A sibling block's mocks are not in
        effect. Order inside an It is not read: a Mock written after the call still counts.
        #>
        [OutputType([System.Management.Automation.Language.Ast])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast]$Node
        )
        $SeenIt = $false
        for ($Current = $Node; $null -ne $Current; $Current = $Current.Parent) {
            if ($Current -isnot [System.Management.Automation.Language.ScriptBlockAst]) { continue }
            $Owner = if ($Current.Parent -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { $Current.Parent.Parent } else { $null }
            $OwnerName = if ($Owner -is [System.Management.Automation.Language.CommandAst]) { $Owner.GetCommandName() } else { $null }
            if ($null -eq $Current.Parent -or $OwnerName -in 'Describe', 'Context') {
                if ($null -eq $Current.EndBlock) { continue }
                foreach ($Statement in $Current.EndBlock.Statements) {
                    if ($Statement -isnot [System.Management.Automation.Language.PipelineAst]) { continue }
                    $Command = $Statement.PipelineElements[0]
                    if ($Command -is [System.Management.Automation.Language.CommandAst] -and $Command.GetCommandName() -in 'BeforeAll', 'BeforeEach') { $Statement }
                }
            } elseif ($OwnerName -eq 'It' -and -not $SeenIt) {
                $SeenIt = $true
                $Current
            }
        }
    }

    function Test-TestHygieneMockThrows {
        <#
        .SYNOPSIS
        Returns $true when a mock body holds a throw statement directly in its end block.
        #>
        [OutputType([bool])]
        param(
            [AllowNull()]
            [object]$Body
        )
        if ($Body -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst] -or $null -eq $Body.ScriptBlock.EndBlock) { return $false }
        @($Body.ScriptBlock.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.ThrowStatementAst] }).Count -gt 0
    }

    function Get-TestHygieneInitializeFinding {
        <#
        .SYNOPSIS
        Returns 'line N: reason' for each place in a parsed test file that can run Initialize-OPIMAuth
        unmocked where Get-MgContext is mocked to return and Get-OPIMMsalApplication is not mocked.
        .DESCRIPTION
        Unmocked, Initialize-OPIMAuth calls Get-OPIMMsalApplication, which builds a real MSAL client
        once Get-MgContext returns; the tripwire stands in for Get-MgContext only while no Mock
        replaces it. So at each Call or String of Initialize-OPIMAuth (Get-TestHygieneCommandReference),
        a Get-MgContext mock in effect whose body does not throw directly needs a Mock of
        Get-OPIMMsalApplication or of Initialize-OPIMAuth in effect beside it (R3b).
        #>
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast]$Ast
        )
        foreach ($Reference in @(Get-TestHygieneCommandReference -Ast $Ast -Name $script:InitializeName)) {
            $Returning = 0
            $Guarded = 0
            foreach ($Root in @(Get-TestHygieneScopeRoot -Node $Reference.Node)) {
                foreach ($Entry in @(Get-TestHygieneMockOf -Ast $Root -Name 'Get-MgContext')) {
                    if (-not (Test-TestHygieneMockThrows -Body $Entry.Body)) { $Returning++ }
                }
                $Guarded += @(Get-TestHygieneMockOf -Ast $Root -Name $script:MsalName).Count
                $Guarded += @(Get-TestHygieneMockOf -Ast $Root -Name $script:InitializeName).Count
            }
            if ($Returning -gt 0 -and $Guarded -eq 0) {
                'line {0}: can run Initialize-OPIMAuth unmocked where Get-MgContext is mocked to return and Get-OPIMMsalApplication is not mocked' -f $Reference.Line
            }
        }
    }

    function Get-TestHygieneMsalFinding {
        <#
        .SYNOPSIS
        Returns 'line N: reason' for each way a parsed test file breaks R3.
        .DESCRIPTION
        Outside the named files, any Call or String of Get-OPIMMsalApplication is refused
        (Get-TestHygieneCommandReference): a command of that name, or a string that can run it. Inside
        the named files, every Mock of Get-MgContext must have a mock body whose end block holds a
        throw statement directly -- a throw in a nested block, in the -ParameterFilter or nowhere does
        not count. Returns nothing for a file that keeps the rule.
        #>
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast]$Ast,

            [Parameter(Mandatory)]
            [bool]$Allowed
        )
        if (-not $Allowed) {
            foreach ($Reference in @(Get-TestHygieneCommandReference -Ast $Ast -Name $script:MsalName)) {
                if ($Reference.Kind -eq 'Call') {
                    'line {0}: invokes Get-OPIMMsalApplication outside the named files' -f $Reference.Line
                } else {
                    'line {0}: names Get-OPIMMsalApplication in a string that can run it, outside the named files' -f $Reference.Line
                }
            }
            return
        }
        foreach ($Entry in @(Get-TestHygieneMockOf -Ast $Ast -Name 'Get-MgContext')) {
            if (-not (Test-TestHygieneMockThrows -Body $Entry.Body)) {
                'line {0}: a Mock of Get-MgContext does not throw directly in its body' -f $Entry.Mock.Extent.StartLineNumber
            }
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

    It 'Should invoke Get-OPIMMsalApplication only where every Get-MgContext mock throws' {
        foreach ($Relative in $script:MsalAllowed) {
            Test-Path -LiteralPath (Join-Path -Path $script:ProjectPath -ChildPath $Relative) | Should -BeTrue -Because ('a named file must exist, or it silently allows nothing: {0}' -f $Relative)
        }
        foreach ($Relative in $script:ReferenceScanExempt) {
            Test-Path -LiteralPath (Join-Path -Path $script:ProjectPath -ChildPath $Relative) | Should -BeTrue -Because ('an exempt file must exist, or the entry is stale: {0}' -f $Relative)
        }

        $TestsRoot = Join-Path -Path $script:ProjectPath -ChildPath 'tests'
        $Files = @(Get-ChildItem -Path $TestsRoot -Recurse -File | Where-Object Extension -eq '.ps1')
        $Files.Count | Should -BeGreaterThan 0 -Because 'the gate must read at least one test file'
        $Hits = [System.Collections.Generic.List[string]]::new()
        $MocksChecked = 0
        foreach ($File in $Files) {
            $Relative = ConvertTo-TestHygieneRelativePath -Path $File.FullName
            if ($script:ReferenceScanExempt -contains $Relative) { continue }
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            $Allowed = $script:MsalAllowed -contains $Relative
            if ($Allowed) { $MocksChecked += @(Get-TestHygieneMockOf -Ast $Ast -Name 'Get-MgContext').Count }
            foreach ($Finding in @(Get-TestHygieneMsalFinding -Ast $Ast -Allowed $Allowed)) {
                $Hits.Add(('{0}: {1}' -f $Relative, $Finding))
            }
        }
        $MocksChecked | Should -BeGreaterThan 0 -Because 'Get-OPIMMsalApplication.Tests.ps1 mocks Get-MgContext; zero checked mocks means the check below read nothing'
        @($Hits).Count | Should -Be 0 -Because ('Get-OPIMMsalApplication builds a real MSAL application once Get-MgContext returns, so only the named files may run it, called or named in a string that can run it, and every Get-MgContext mock there must throw; zero means the rule holds. Breaches: {0}' -f ($Hits -join '; '))
    }

    It 'Should run Initialize-OPIMAuth unmocked only where the MSAL build stays out of reach' {
        foreach ($Relative in $script:ReferenceScanExempt) {
            Test-Path -LiteralPath (Join-Path -Path $script:ProjectPath -ChildPath $Relative) | Should -BeTrue -Because ('an exempt file must exist, or the entry is stale: {0}' -f $Relative)
        }
        $TestsRoot = Join-Path -Path $script:ProjectPath -ChildPath 'tests'
        $Files = @(Get-ChildItem -Path $TestsRoot -Recurse -File | Where-Object Extension -eq '.ps1')
        $Hits = [System.Collections.Generic.List[string]]::new()
        $References = 0
        foreach ($File in $Files) {
            $Relative = ConvertTo-TestHygieneRelativePath -Path $File.FullName
            if ($script:ReferenceScanExempt -contains $Relative) { continue }
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            $References += @(Get-TestHygieneCommandReference -Ast $Ast -Name $script:InitializeName).Count
            foreach ($Finding in @(Get-TestHygieneInitializeFinding -Ast $Ast)) { $Hits.Add(('{0}: {1}' -f $Relative, $Finding)) }
        }
        $References | Should -BeGreaterThan 0 -Because 'Initialize-OPIMAuth.Tests.ps1 calls Initialize-OPIMAuth; zero references means the scan read nothing'
        @($Hits).Count | Should -Be 0 -Because ('Initialize-OPIMAuth calls Get-OPIMMsalApplication, which builds a real MSAL client once Get-MgContext returns, so where a Get-MgContext mock returns, Get-OPIMMsalApplication or Initialize-OPIMAuth must be mocked too; zero means every place is. Places that are not: {0}' -f ($Hits -join '; '))
    }

    It 'Should tell a throwing Get-MgContext mock from one that returns (known answer)' {
        $Throwing = @'
Mock Get-MgContext { throw [System.InvalidOperationException]::new('stop') }
Mock -ModuleName Omnicit.PIM Get-MgContext { throw 'stop' } -ParameterFilter { $true }
Mock -CommandName Get-MgContext -MockWith { throw 'stop' }
Mock -ModuleName Omnicit.PIM Get-OtherCommand { }
Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com'
'@
        $Returning = @'
Mock Get-MgContext {}
Mock -ModuleName Omnicit.PIM Get-MgContext { $null }
Mock Get-MgContext -ParameterFilter { throw 'stop' } { 'returns' }
Mock -CommandName Get-MgContext -MockWith { if ($true) { throw 'stop' } }
'@
        $Parse = { param($Text) [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null) }

        @(Get-TestHygieneMockOf -Ast (& $Parse $Throwing) -Name 'Get-MgContext').Count | Should -Be 3 -Because 'each form of a Get-MgContext mock must be recognised, and a mock of another command must not'
        @(Get-TestHygieneMsalFinding -Ast (& $Parse $Throwing) -Allowed $true).Count | Should -Be 0 -Because 'a mock that throws directly must produce no finding'
        @(Get-TestHygieneMsalFinding -Ast (& $Parse $Returning) -Allowed $true) | Should -Be @(
            'line 1: a Mock of Get-MgContext does not throw directly in its body'
            'line 2: a Mock of Get-MgContext does not throw directly in its body'
            'line 3: a Mock of Get-MgContext does not throw directly in its body'
            'line 4: a Mock of Get-MgContext does not throw directly in its body'
        )
        @(Get-TestHygieneMsalFinding -Ast (& $Parse $Throwing) -Allowed $false) | Should -Be @('line 5: invokes Get-OPIMMsalApplication outside the named files')
    }

    It 'Should find each indirect way to run Get-OPIMMsalApplication (known answer)' {
        $Indirect = @'
$Command = 'Get-OPIMMsalApplication'
& $Command -TenantId 'contoso.onmicrosoft.com'
& (Get-Command -Name Get-OPIMMsalApplication) -TenantId 'contoso.onmicrosoft.com'
$Found = Get-Command Get-OPIMMsalApplication; $Found.ScriptBlock.Invoke()
& ([scriptblock]::Create('Get-OPIMMsalApplication -TenantId contoso.onmicrosoft.com'))
Invoke-Expression "Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com'"
& ([scriptblock]::Create("`$Name = 'Get-OPIMMsalApplication'; & `$Name"))
'@
        $ReferenceOnly = @'
Describe 'Get-OPIMMsalApplication' {
    It 'calls Get-OPIMMsalApplication once' {
        Mock -ModuleName Omnicit.PIM Get-OPIMMsalApplication { }
        Mock -CommandName Get-OPIMMsalApplication -MockWith { }
        Should -Invoke -ModuleName Omnicit.PIM Get-OPIMMsalApplication -Times 0 -Because 'Get-OPIMMsalApplication must not run'
        $Path = 'tests/Unit/Private/Get-OPIMMsalApplication.Tests.ps1'
    }
}
'@
        $Parse = { param($Text) [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null) }
        $Reason = 'names Get-OPIMMsalApplication in a string that can run it, outside the named files'

        @(Get-TestHygieneMsalFinding -Ast (& $Parse $Indirect) -Allowed $false) | Should -Be @(
            "line 1: $Reason"
            "line 3: $Reason"
            "line 4: $Reason"
            "line 5: $Reason"
            "line 6: $Reason"
            "line 7: $Reason"
        )
        @(Get-TestHygieneMsalFinding -Ast (& $Parse $ReferenceOnly) -Allowed $false).Count | Should -Be 0 -Because 'a Mock or Should -Invoke target, a block name, a -Because text and a file path name the command without running it'
        @(Get-TestHygieneMsalFinding -Ast (& $Parse $Indirect) -Allowed $true).Count | Should -Be 0 -Because 'in a named file only the Get-MgContext rule applies'
    }

    It 'Should find Initialize-OPIMAuth run unmocked where Get-MgContext returns and the MSAL build is not mocked (known answer)' {
        $Unguarded = @'
Describe 'x' {
    BeforeAll {
        Mock -ModuleName Omnicit.PIM Get-MgContext { $null }
    }
    It 'a' {
        InModuleScope Omnicit.PIM { Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' }
    }
    It 'b' {
        InModuleScope Omnicit.PIM {
            $Name = 'Initialize-OPIMAuth'
            & $Name
        }
    }
    It 'c' {
        InModuleScope Omnicit.PIM { & (Get-Command Initialize-OPIMAuth) }
    }
    It 'd' {
        InModuleScope Omnicit.PIM { & ([scriptblock]::Create('Initialize-OPIMAuth')) }
    }
}
'@
        $Guarded = @'
Describe 'x' {
    BeforeAll {
        Mock -ModuleName Omnicit.PIM Get-MgContext { $null }
        Mock -ModuleName Omnicit.PIM Get-OPIMMsalApplication { }
    }
    It 'a' { InModuleScope Omnicit.PIM { Initialize-OPIMAuth } }
}
Describe 'y' {
    BeforeAll {
        Mock -ModuleName Omnicit.PIM Get-MgContext { throw 'stop' }
    }
    It 'b' { InModuleScope Omnicit.PIM { Initialize-OPIMAuth } }
}
Describe 'w' {
    It 'e' {
        Mock -ModuleName Omnicit.PIM Get-MgContext { $null }
        Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth { }
        Initialize-OPIMAuth
    }
}
'@
        # Kept apart from $Guarded: a mock anywhere else in the same text would be in effect for the
        # whole file, and hide that this one is not in effect in a sibling block.
        $Sibling = @'
Describe 'z' {
    Context 'mocked here' {
        BeforeAll { Mock -ModuleName Omnicit.PIM Get-MgContext { $null } }
        It 'c' { $true | Should -BeTrue }
    }
    Context 'not here' {
        It 'd' { InModuleScope Omnicit.PIM { Initialize-OPIMAuth } }
    }
}
'@
        $FileRoot = @'
BeforeAll {
    Mock -ModuleName Omnicit.PIM Get-MgContext { $null }
}
Describe 'x' {
    It 'a' { InModuleScope Omnicit.PIM { Initialize-OPIMAuth } }
}
'@
        $Parse = { param($Text) [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null) }
        $Reason = 'can run Initialize-OPIMAuth unmocked where Get-MgContext is mocked to return and Get-OPIMMsalApplication is not mocked'

        @(Get-TestHygieneInitializeFinding -Ast (& $Parse $Unguarded)) | Should -Be @(
            "line 6: $Reason"
            "line 10: $Reason"
            "line 15: $Reason"
            "line 18: $Reason"
        )
        @(Get-TestHygieneInitializeFinding -Ast (& $Parse $Guarded)).Count | Should -Be 0 -Because 'a mocked MSAL build, a throwing Get-MgContext and a mocked Initialize-OPIMAuth each keep the real client out of reach'
        @(Get-TestHygieneInitializeFinding -Ast (& $Parse $Sibling)).Count | Should -Be 0 -Because 'a Get-MgContext mock in a sibling Context is not in effect where Initialize-OPIMAuth runs'
        @(Get-TestHygieneInitializeFinding -Ast (& $Parse $FileRoot)) | Should -Be @("line 5: $Reason")
    }

    It 'Should read only the strings that can run the command (known answer)' {
        Test-TestHygieneTextRunsCommand -Text 'Get-OPIMMsalApplication' -Name 'Get-OPIMMsalApplication' | Should -BeTrue
        Test-TestHygieneTextRunsCommand -Text 'tests/Unit/Private/Get-OPIMMsalApplication.Tests.ps1' -Name 'Get-OPIMMsalApplication' | Should -BeFalse
        Test-TestHygieneTextRunsCommand -Text 'Invoke-OPIMGraphRequest -Uri x' -Name 'Get-OPIMMsalApplication' | Should -BeFalse
        Test-TestHygieneTextRunsCommand -Text "`$N = 'Get-OPIMMsalApplication'; & `$N" -Name 'Get-OPIMMsalApplication' | Should -BeTrue
    }
}
