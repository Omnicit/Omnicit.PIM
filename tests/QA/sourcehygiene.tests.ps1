BeforeAll {
    $script:ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath '..'))).Path

    # =====================================================================================
    # SOURCE HYGIENE -- read statically, one pass over the authored tree.
    #
    # The gate reads files and parses text. It imports nothing and runs no module code.
    #
    # It holds seven checks, one Describe each, in this order (Pass 1 to Pass 5 below are the steps
    # of this BeforeAll behind the third, the sixth and the seventh):
    #   Source encoding -- ASCII only and no BOM, in every authored file.
    #   Cmdlet reference hygiene -- every Verb-OPIM name in source/**/*.ps1 names a command.
    #   Bearer-token hygiene -- every catch on a transport path scrubs first (call-edge closure).
    #   suffix.ps1 / psm1 mirror sync -- the region the two files share is byte-identical.
    #   Format and type data -- every .ps1xml parses as XML; no ScriptProperty reads its own name.
    #   Az boundary (decision A7) -- no Az command or module, .ps1xml script blocks included.
    #   Cloud hosts (decision A11) -- each cloud host is written only in Get-OPIMCloudEndpoint.
    #
    # '*.txt' and '*.md' are deliberately NOT in the include list. The about topic
    # (source/en-US/about_Omnicit.PIM.help.txt) belongs to the about-topic check,
    # tests/QA/about.tests.ps1, which reads its bytes. If that coverage is ever removed, add
    # '*.txt' to this scan instead of leaving the file ungated.
    # source/Formats/README.md is a shipped note that no command shows. Every path below is
    # compared with '/' separators, so the gate holds on every operating system.
    #
    # The floors of the first two checks sit just under the counts measured on 2026-10-06: source/
    # held 42 authored files of these extensions, tests/ 37 (this file included), and
    # source/**/*.ps1 38 files carrying 349 Verb-OPIM tokens. The tests/ floor leaves no slack,
    # since tests/Unit/Classes holds a single file. Raise a floor when the tree genuinely grows.
    # =====================================================================================
    $script:SourceFileFloor = 40
    $script:TestFileFloor = 36
    $script:CmdletRefFileFloor = 36
    $script:CmdletRefTokenFloor = 340

    $script:HygieneRoots = @(
        (Join-Path -Path $script:ProjectPath -ChildPath 'source')
        (Join-Path -Path $script:ProjectPath -ChildPath 'tests')
    )

    # A missing root is an error, not an empty scan: -ErrorAction Stop makes it fail the file.
    $script:HygieneFiles = @(
        Get-ChildItem -Path $script:HygieneRoots -Recurse -File -Include '*.ps1', '*.psd1', '*.psm1', '*.ps1xml' -ErrorAction Stop |
            ForEach-Object {
                $Bytes = [System.IO.File]::ReadAllBytes($_.FullName)
                [PSCustomObject]@{
                    Path         = $_.FullName
                    Extension    = $_.Extension
                    RelativePath = [System.IO.Path]::GetRelativePath($script:ProjectPath, $_.FullName).Replace('\', '/')
                    Bytes        = $Bytes
                    Text         = [System.Text.Encoding]::UTF8.GetString($Bytes)
                }
            }
    )

    # Named positive controls are looked up here. A threshold erodes as a tree grows; a named file
    # does not.
    $script:HygieneFilePaths = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($script:HygieneFiles | ForEach-Object { $_.RelativePath }),
        [System.StringComparer]::Ordinal)

    # =====================================================================================
    # CMDLET REFERENCES.
    #
    # A name is known when it is the basename of a function file under source/Public or
    # source/Private, an alias in the source manifest's AliasesToExport (Enable-OPIMMyRoles and
    # Disable-OPIMMyRoles are aliases, not files), or the name of a function defined inside
    # another function in one of those files (Invoke-OPIMGraphRequest's nested
    # Invoke-OPIMGraphSingle). The pattern is case-sensitive; the verb may carry an inner capital
    # (ConvertTo-OPIM...), and a family form with a trailing '*' (Get-OPIM*) names no command and
    # is not matched.
    # =====================================================================================
    $script:CmdletRefPattern = '\b[A-Z][A-Za-z]+-OPIM[A-Za-z]*\b(?!\*)'

    $script:KnownCommandNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($File in $script:HygieneFiles) {
        if ($File.RelativePath -match '^source/(Public|Private)/[^/]+\.ps1$') {
            $null = $script:KnownCommandNames.Add([System.IO.Path]::GetFileNameWithoutExtension($File.RelativePath))
        }
    }
    $script:ManifestAliases = @(
        (Import-PowerShellDataFile -Path (Join-Path -Path $script:ProjectPath -ChildPath (Join-Path -Path 'source' -ChildPath 'Omnicit.PIM.psd1'))).AliasesToExport
    )
    foreach ($Alias in $script:ManifestAliases) {
        $null = $script:KnownCommandNames.Add($Alias)
    }

    <#
        A function defined inside another function is a command the module defines as well, so its
        name is known too. It is found through the AST -- a function definition with another one
        above it -- never by a text match, so a name that appears only in prose never makes itself
        known.
    #>
    $script:NestedCommandNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($File in $script:HygieneFiles) {
        if ($File.RelativePath -notmatch '^source/(Public|Private)/[^/]+\.ps1$') { continue }
        $DefinitionAst = [System.Management.Automation.Language.Parser]::ParseInput($File.Text, $File.Path, [ref]$null, [ref]$null)
        foreach ($Definition in $DefinitionAst.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            $Above = $Definition.Parent
            while ($Above -and $Above -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $Above = $Above.Parent }
            if ($Above) { $null = $script:NestedCommandNames.Add($Definition.Name) }
        }
    }
    foreach ($Name in $script:NestedCommandNames) {
        $null = $script:KnownCommandNames.Add($Name)
    }

    $script:CmdletRefFiles = @($script:HygieneFiles | Where-Object {
            $_.RelativePath -like 'source/*' -and $_.Extension -eq '.ps1'
        })
    $script:CmdletRefTokenCount = 0
    $script:CmdletRefViolations = [System.Collections.Generic.List[string]]::new()
    foreach ($File in $script:CmdletRefFiles) {
        foreach ($TokenMatch in [System.Text.RegularExpressions.Regex]::Matches($File.Text, $script:CmdletRefPattern)) {
            $script:CmdletRefTokenCount++
            if (-not $script:KnownCommandNames.Contains($TokenMatch.Value)) {
                $Line = $File.Text.Substring(0, $TokenMatch.Index).Split("`n").Count
                $script:CmdletRefViolations.Add(('{0}:{1} -- references {2}, which is neither a function file under source/Public or source/Private, a function nested in one, nor an alias in AliasesToExport' -f
                        $File.RelativePath, $Line, $TokenMatch.Value))
            }
        }
    }

    # =====================================================================================
    # BEARER SCRUB -- one AST pass over source/, reusing the files already read above.
    #
    # The raw record of a failed request points, through its TargetObject and its exception chain,
    # at the HttpRequestMessage whose Authorization header carries the bearer token in plain text.
    # Remove-OPIMErrorRecord clears that header on the shared request object and drops the record
    # from the caller's $global:Error, so it must be the FIRST statement of every catch in a file
    # that can receive such a record.
    #
    # 'Transport' is anything that can put a credential on the wire or fail with a record of a
    # request that carried one: the module's Graph wrapper and the raw Graph call, the two web
    # cmdlets, the sign-ins (Connect-MgGraph and AzAuth's Get-AzToken), and the module's own ARM
    # wrapper (Invoke-OPIMArmRequest). No Az module command is on the list: the Az boundary pass
    # (Pass 4, below) refuses any call of one under source/ outright, so there is no Az call left
    # for this scan to hold to the scrub.
    # =====================================================================================
    $script:TransportCommands = @(
        'Invoke-OPIMGraphRequest', 'Invoke-MgGraphRequest', 'Invoke-WebRequest', 'Invoke-RestMethod',
        'Connect-MgGraph', 'Get-AzToken',
        'Invoke-OPIMArmRequest'
    )

    # The one first statement the scan accepts.
    $script:ScrubFirstStatementPattern = '^Remove-OPIMErrorRecord\s+-Record\s+\$PSItem\b'

    <#
        Catch clauses that legitimately do NOT scrub: none today. The table is keyed by file, and
        each value is a predicate over the CatchClauseAst that the catch must ALSO satisfy, so an
        entry never unguards a whole file -- a file key alone would silently unguard every OTHER
        catch in it. The predicate is the written justification: a structural property of the try
        body (for example a single call to a pure local helper) that proves no record of a request
        can reach the catch. Line numbers are never the anchor: they drift on every unrelated edit.
    #>
    $script:ScrubExemptions = @{}

    <#
        The floors sit just under the counts measured on 2026-10-10, after the six completer classes
        under source/Classes joined the closure through the run-string edge (below) and their
        catches were made to scrub first: 26 transport-reaching files under source/, the six classes
        among them, holding 85 of the 103 catch clauses in source/. The named control,
        source/Private/Invoke-OPIMGraphRequest.ps1, is asserted with its EXACT count instead (9: the three in its nested
        Get-ClaimsFromException; the one in each of its nested Get-GraphResponseFact and
        Get-GraphRetryAfterHeaderValue, which read a failure's status and Retry-After in both
        forms the Graph SDK raises (OPIM-28); the first attempt, the claims retry and the refresh
        retry, all three in its nested Invoke-OPIMGraphSingle; and the paging catch of -All,
        OPIM-13), so a catch that stops being seen fails there with a clear cause instead of
        quietly shrinking a total.
    #>
    $script:ScrubTransportFileFloor = 24
    $script:ScrubCatchFloor = 83
    $script:ScrubControlPath = 'source/Private/Invoke-OPIMGraphRequest.ps1'
    $script:ScrubControlCatchCount = 9

    <#
        THE RUN-STRING EDGE. A constant string handed to [scriptblock]::Create is code its file runs,
        so every command the string names is a call of that file, just as a command written out is.
        That is how the six completer classes reach the Get-OPIM* cmdlets:
        & ([scriptblock]::Create('Get-OPIMDirectoryRole -WarningAction SilentlyContinue')). Pass 1
        collects those names per file with Get-SourceHygieneRunnableName, and Pass 2 makes an edge of
        every one that names a module function, public or private.

        KNOWN LIMITS: only a static call of Create on a type written [scriptblock] or
        [System.Management.Automation.ScriptBlock] (in any letter case) whose first argument is a
        constant string is read. A string built at run time ([scriptblock]::Create($Text), or an
        expandable string that holds a variable), the type written another way
        ([Management.Automation.ScriptBlock]), and a string run by Invoke-Expression or by & $Name
        make no edge. Review has to catch those shapes; this pass cannot.
    #>
    function Get-SourceHygieneRunnableName {
        <#
        .SYNOPSIS
        Returns the name of every command a parsed file runs through a constant string handed to
        [scriptblock]::Create, in the order the strings and their commands appear.
        #>
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast]$Ast
        )
        foreach ($Node in $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)) {
            if (-not $Node.Static) { continue }
            if ($Node.Expression -isnot [System.Management.Automation.Language.TypeExpressionAst]) { continue }
            $TypeName = $Node.Expression.TypeName.FullName
            if (-not ([string]::Equals($TypeName, 'scriptblock', [System.StringComparison]::OrdinalIgnoreCase) -or
                    [string]::Equals($TypeName, 'System.Management.Automation.ScriptBlock', [System.StringComparison]::OrdinalIgnoreCase))) { continue }
            if ($Node.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or
                -not [string]::Equals($Node.Member.Value, 'Create', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $Argument = @($Node.Arguments)[0]
            if ($Argument -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { continue }
            $Inner = [System.Management.Automation.Language.Parser]::ParseInput($Argument.Value, [ref]$null, [ref]$null)
            foreach ($Call in $Inner.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $Name = $Call.GetCommandName()
                if (-not [string]::IsNullOrEmpty($Name)) { $Name }
            }
        }
    }

    <#
        =====================================================================================
        AZ BOUNDARY (Pass 4, decision A7, modelled on Omnicit.EntraRBAC's "Pass 8").

        THE PROPERTY. Omnicit.PIM signs in to Azure Resource Manager with AzAuth's Get-AzToken and
        sends every ARM request itself, through Invoke-OPIMArmRequest. It calls no Az module
        command, loads no Az module and declares none, so a user's own Az session and Az
        configuration are never touched and no Az module needs to be installed.

        The property used to be proven by mocks only: 'Should -Invoke <Az command> -Times 0' in the
        unit tests. Those assertions only run while the Az modules are installed, since Pester's
        Mock throws for a command it cannot resolve, and Sprint 2 step 1b takes the Az modules out
        of the build. This pass proves the property from the source text instead, independently of
        what is installed:
        it asks the PowerShell parser what source/ CALLS, so the prose that names an Az command to
        say the module does not call it (a comment, comment-based help) is never offered to it.

        THREE REFUSED SHAPES, found in every .ps1, .psm1 and .psd1 under source/ on the AST Pass 1
        already parsed (each file is parsed once), and in every script block of the .ps1xml files
        under source/, each parsed on its own (Get-SourceHygieneXmlScriptBlock):
          - Call: a command whose static name matches '-Az' (Connect-AzAccount), or that is
            module-qualified with an Az module (Az.Accounts\Get-AzContext). GetCommandName() also
            returns a quoted first element, so & 'Disconnect-AzAccount' is a call.
          - String: a quoted string whose text parses as such a call, the form a command takes
            through [scriptblock]::Create('...') or Invoke-Expression, and a command name built in
            an expandable string (& "Connect-AzAccount$Suffix"), which has no static name. A quoted
            string that IS a command's static name is the Call shape and is not reported twice.
          - Module: an Az module (Az, Az.Accounts, Az.Resources, ...) named as a quoted string or a
            bareword (Import-Module Az.Accounts, a manifest's RequiredModules entry), or required
            by #requires -Modules.

        THE ALLOW LIST is Get-AzToken alone, bare or qualified with AzAuth: AzAuth is not one of the
        Az modules, and acquiring a token is the whole design. The module's own nested helper
        Invoke-OPIMAzTokenCall does not match '-Az' and needs no entry.

        KNOWN LIMITS, stated rather than papered over. A command name assembled at run time (a name
        held in a variable and run with & $Name, or a string built from parts) is invisible to a
        parser: GetCommandName() returns $null for it, and no string holds the whole name. So is an
        Az command named by a bareword argument rather than called, as in
        & (Get-Command Connect-AzAccount) or $C = Get-Command -Name Get-AzContext; & $C, since a
        bareword argument is neither a call nor a quoted string. And so is an alias the Az modules
        export without -Az in its name (Resolve-Error, say), called bare. Review must catch these
        shapes; this pass cannot. The XML under source/ is no such gap: the pass also reads every
        script block of the .ps1xml files -- each GetScriptBlock, SetScriptBlock, ScriptBlock and
        Script element, the code the Types and Format files run at property access, as a method
        and at formatting -- and the limits above hold inside a script block as in a .ps1 file.

        The positive controls are the two known-answer Its, which run the detector over a text
        holding every refused shape and over in-memory Types and Format texts, and the named
        control: the two Get-AzToken calls of source/Private/Initialize-OPIMAuth.ps1, which a
        matcher that stopped seeing the tree would no longer find.
        =====================================================================================
    #>
    $script:AzAllowedCommands = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('Get-AzToken'), [System.StringComparer]::OrdinalIgnoreCase)
    $script:AzCommandPattern = '-Az'
    $script:AzModulePattern = '^Az(\.[A-Za-z0-9]+)*$'

    function Get-SourceHygieneAzFinding {
        <#
        .SYNOPSIS
        Returns one record per Az-shaped reference in a parsed file: Kind (Call, String or Module),
        Line, Name, and Allowed (true only for a call on the allow list).
        #>
        [OutputType([pscustomobject])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast]$Ast
        )
        $IsAzCall = {
            param($Name)
            $Parts = $Name -split '\\'
            ($Name -match $script:AzCommandPattern) -or ($Parts.Count -gt 1 -and $Parts[0] -match $script:AzModulePattern)
        }
        $IsAllowed = {
            param($Name)
            $Parts = $Name -split '\\'
            $script:AzAllowedCommands.Contains($Parts[-1]) -and ($Parts.Count -eq 1 -or $Parts[0] -eq 'AzAuth')
        }
        # Call: a command whose static name matches. GetCommandName() also returns the value of a quoted
        # first element, so & 'Disconnect-AzAccount' is a call.
        foreach ($Node in $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $Name = $Node.GetCommandName()
            if ([string]::IsNullOrEmpty($Name) -or -not (& $IsAzCall $Name)) { continue }
            [pscustomobject]@{ Kind = 'Call'; Line = $Node.Extent.StartLineNumber; Name = $Name; Allowed = [bool](& $IsAllowed $Name) }
        }
        # String: a quoted string that parses as an Az call. A string that is a command's first element
        # is skipped only when it gives the command a static name, which the Call pass has seen; an
        # expandable first element (& "Connect-AzAccount$Suffix") gives none, so it is read here.
        foreach ($Node in $Ast.FindAll({
                    ($args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                        $args[0].StringConstantType -ne [System.Management.Automation.Language.StringConstantType]::BareWord) -or
                    $args[0] -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
                }, $true)) {
            if ($Node.Parent -is [System.Management.Automation.Language.CommandAst] -and
                [object]::ReferenceEquals($Node.Parent.CommandElements[0], $Node) -and
                -not [string]::IsNullOrEmpty($Node.Parent.GetCommandName())) { continue }
            $Inner = [System.Management.Automation.Language.Parser]::ParseInput([string]$Node.Value, [ref]$null, [ref]$null)
            foreach ($Call in $Inner.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $Name = $Call.GetCommandName()
                if ([string]::IsNullOrEmpty($Name) -or -not (& $IsAzCall $Name) -or (& $IsAllowed $Name)) { continue }
                [pscustomobject]@{ Kind = 'String'; Line = $Node.Extent.StartLineNumber; Name = $Name; Allowed = $false }
            }
        }
        # Module: an Az module named as a string or a bareword, or in #requires -Modules.
        foreach ($Node in $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)) {
            if ($Node.Value -match $script:AzModulePattern) {
                [pscustomobject]@{ Kind = 'Module'; Line = $Node.Extent.StartLineNumber; Name = $Node.Value; Allowed = $false }
            }
        }
        if ($Ast -is [System.Management.Automation.Language.ScriptBlockAst] -and $Ast.ScriptRequirements) {
            $Lines = $Ast.Extent.Text -split "`n"
            foreach ($Required in @($Ast.ScriptRequirements.RequiredModules)) {
                if ($Required.Name -notmatch $script:AzModulePattern) { continue }
                $Line = 0
                for ($I = 0; $I -lt $Lines.Count; $I++) {
                    if ($Lines[$I] -match '^\s*#requires\b' -and $Lines[$I] -match [regex]::Escape($Required.Name)) { $Line = $I + 1; break }
                }
                [pscustomobject]@{ Kind = 'Module'; Line = $Line; Name = $Required.Name; Allowed = $false }
            }
        }
    }

    # The elements of a .ps1xml file that hold PowerShell code: a ScriptProperty's two accessors and
    # a ScriptMethod's body (Script) in a Types file, and every ScriptBlock of a Format file.
    $script:AzXmlScriptElements = @('GetScriptBlock', 'SetScriptBlock', 'ScriptBlock', 'Script')

    function Get-SourceHygieneXmlScriptBlock {
        <#
        .SYNOPSIS
        Returns one record per script element of a .ps1xml text, in document order: Path, Line (the
        line of the element's start tag), Element (its local name), Ast (its text, parsed) and Errors
        (the parse errors). A text that is not well-formed XML throws.
        #>
        [OutputType([pscustomobject])]
        param(
            [Parameter(Mandatory)]
            [string]$Text,

            [Parameter(Mandatory)]
            [string]$RelativePath
        )
        # PreserveWhitespace keeps the whitespace text beside a CDATA section, which the line of a
        # finding inside the element is counted through; without it that text is dropped.
        $Document = [System.Xml.Linq.XDocument]::Parse($Text,
            [System.Xml.Linq.LoadOptions]::SetLineInfo -bor [System.Xml.Linq.LoadOptions]::PreserveWhitespace)
        foreach ($Element in $Document.Descendants()) {
            if ($Element.Name.LocalName -notin $script:AzXmlScriptElements) { continue }
            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Element.Value, [ref]$null, [ref]$Errors)
            [pscustomobject]@{
                Path    = $RelativePath
                Line    = ([System.Xml.IXmlLineInfo]$Element).LineNumber
                Element = $Element.Name.LocalName
                Ast     = $Ast
                Errors  = @($Errors)
            }
        }
    }

    function Get-SourceHygieneXmlAzFinding {
        <#
        .SYNOPSIS
        Returns the findings of Get-SourceHygieneAzFinding for one script block that
        Get-SourceHygieneXmlScriptBlock returned, each with the block's Path and a Line counted in
        the file: the element's line plus the finding's own line in the block, less one.
        #>
        [OutputType([pscustomobject])]
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$Block
        )
        foreach ($Finding in @(Get-SourceHygieneAzFinding -Ast $Block.Ast)) {
            $Finding.Line = $Block.Line + $Finding.Line - 1
            $Finding | Add-Member -NotePropertyName Path -NotePropertyValue $Block.Path -PassThru
        }
    }

    <#
        The floors sit just under the counts Pass 1 measured on 2026-10-09: 65 parsed files under
        source/ (.ps1, .psm1, .psd1) holding 759 CommandAst nodes; and on 2026-10-10, 37 script
        blocks in the two .ps1xml files (the 29 GetScriptBlock of the Types file and the 8
        ScriptBlock of the Format file). A scan below a floor has lost a directory or broken its
        walk, not found less code; raise a floor when the tree genuinely grows.
    #>
    $script:AzParsedFileFloor = 63
    $script:AzCommandAstFloor = 740
    $script:AzXmlScriptBlockFloor = 35
    $script:AzFindings = [System.Collections.Generic.List[object]]::new()
    $script:AzParsedFileCount = 0
    $script:AzCommandAstCount = 0
    $script:AzXmlScriptBlockCount = 0

    <#
        =====================================================================================
        CLOUD HOSTS (Pass 5, decision A11, modelled on Omnicit.EntraRBAC's "Pass 6").

        THE PROPERTY. Every Graph, Azure Resource Manager and sign-in authority host of the four
        clouds (Global, USGov, USGovDoD, China) is written in ONE place, the private table
        source/Private/Get-OPIMCloudEndpoint.ps1, and every other file under source/ reads the
        table. A second copy of a host is a copy that can drift from the table, and on a sovereign
        tenant it sends a request or a credential across the wrong cloud boundary -- the failure
        A11 exists to rule out, and one no unit test sees, since a test mocks the transport and
        never reads a host.

        THE HOST LIST IS DERIVED, not retyped. The hosts this pass refuses are read out of the
        table's own AST (every string constant that starts with https://, its host by [uri]), so a
        fifth cloud added to the table is scanned for from that moment. $script:CloudHostDocumented
        is a written control, not the working list: the first It compares the two, so adding a
        cloud is a deliberate edit that stays red until a person updates the control (and the
        documentation of the hosts) in the same change. Only when the derivation yields nothing at
        all does the scan fall back to the control, so a broken derivation can neither empty the
        pattern (an empty alternation matches every string) nor turn the scan into a no-op; the
        derivation It is the one that goes red.

        WHY THE AST. A comment is a token and never an AST node, so help and comments that NAME a
        host (the table's own .DESCRIPTION does) are never offered to this scan. Every
        StringConstantExpressionAst of any kind (single or double quoted, here-string, bareword) and
        every ExpandableStringExpressionAst is read: a host spelled as a bareword argument
        (Write-Output management.chinacloudapi.cn) or inside an interpolated string
        ("https://$Tenant.login.microsoftonline.us") is as much a second copy as a quoted literal.
        The match is case-insensitive, so a host in capitals is caught as well; each finding names
        the host in the lower case the table holds it in.

        TWO EXEMPTIONS, and nothing else.
          - source/Private/Get-OPIMCloudEndpoint.ps1, WHOLE FILE: it is the table, and every literal
            in it is the table and not a copy of it.
          - source/Private/Invoke-OPIMArmRequest.ps1, ONE literal, found by its SHAPE and never by
            the file: the else branch of the assignment to $ArmBaseUrl,
            $ArmBaseUrl = if (...) { ... } elseif (...) { ... } else { 'https://management.azure.com' },
            the transport's one documented public-cloud fallback for a call with no auth state at
            all (where the request is refused for its missing token anyway). The function
            Test-SourceHygieneArmFallbackLiteral checks the node's parent chain -- the literal is
            the only element of its pipeline and the only statement of the ElseClause of an
            IfStatementAst (compared by reference, so the body of an if or an elseif does not
            qualify), whose parent is a plain assignment (the operator =, not +=) to the variable
            ArmBaseUrl -- and that the literal is exactly 'https://management.azure.com',
            so a sovereign host written into the fallback slot is refused as well. A file-level key would
            silently unguard every OTHER literal the transport might ever carry; the known-answer It
            holds a probe in that file that must stay refused.

        KNOWN LIMITS, stated rather than papered over. A host assembled at run time from parts
        ('https://graph.' + 'microsoft.us', a -f format, a [uri] built from a scheme and a name) is
        invisible to a parser: no node holds the whole host. A host in a .ps1xml file is not read
        at all, since this pass walks .ps1, .psm1 and .psd1 only, while the Types and Format files
        hold script blocks that run at property access and at formatting. A host escaped for a
        regular expression ('graph\.microsoft\.us' in a -match or -replace pattern) is not seen
        either: the string holds a backslash inside the host, so the plain host never occurs in it.
        A host that is only a PART of a longer name is reported (the match is a substring match),
        which errs on the side of refusing. Review has to catch the first three; this pass cannot.

        The positive controls are the known-answer It, which runs the detector over in-memory texts
        holding every refused shape and both exemptions, and the named control: the ARM fallback
        of Invoke-OPIMArmRequest, and the ten distinct hosts of the table, which a detector that
        stopped seeing the tree would no longer find.
        =====================================================================================
    #>
    $script:CloudEndpointPath = 'source/Private/Get-OPIMCloudEndpoint.ps1'
    $script:CloudArmFallbackPath = 'source/Private/Invoke-OPIMArmRequest.ps1'
    $script:CloudArmFallbackVariable = 'ArmBaseUrl'
    $script:CloudArmFallbackLiteral = 'https://management.azure.com'

    # The written control: the ten distinct hosts of the four clouds (USGovDoD shares the ARM and
    # authority hosts of USGov). Compared with the derived list by the first It of 'Cloud hosts'.
    $script:CloudHostDocumented = @(
        'graph.microsoft.com', 'management.azure.com', 'login.microsoftonline.com',
        'graph.microsoft.us', 'dod-graph.microsoft.us', 'management.usgovcloudapi.net', 'login.microsoftonline.us',
        'microsoftgraph.chinacloudapi.cn', 'management.chinacloudapi.cn', 'login.chinacloudapi.cn'
    )

    $script:CloudHostDerivationFailure = ''
    $script:CloudHostDerived = @()

    $CloudTableFile = @($script:HygieneFiles | Where-Object { $_.RelativePath -ceq $script:CloudEndpointPath }) | Select-Object -First 1
    if (-not $CloudTableFile) {
        $script:CloudHostDerivationFailure = "the endpoint table '$($script:CloudEndpointPath)' was not found among the scanned files, so no host could be derived from it"
    } else {
        $CloudTableErrors = $null
        $CloudTableAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $CloudTableFile.Text, $CloudTableFile.Path, [ref]$null, [ref]$CloudTableErrors)
        if ($CloudTableErrors.Count -gt 0) {
            $script:CloudHostDerivationFailure = "the endpoint table '$($script:CloudEndpointPath)' does not parse ($($CloudTableErrors.Count) error(s)), so no host could be derived from it"
        } else {
            $CloudDerived = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($Node in $CloudTableAst.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)) {
                if (-not $Node.Value.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                # [uri] is the parser the transports use, so a malformed entry of the table is
                # reported here instead of being half-matched.
                $CloudUri = $null
                if (-not [uri]::TryCreate($Node.Value, [System.UriKind]::Absolute, [ref]$CloudUri)) {
                    $script:CloudHostDerivationFailure = "the endpoint table holds an https:// string that is not an absolute URI: '$($Node.Value)'"
                    continue
                }
                if ($CloudUri.Host) { $null = $CloudDerived.Add($CloudUri.Host) }
            }
            $CloudDerivedSorted = [string[]]@($CloudDerived)
            [System.Array]::Sort($CloudDerivedSorted, [System.StringComparer]::Ordinal)
            $script:CloudHostDerived = $CloudDerivedSorted
            if ($CloudDerivedSorted.Count -eq 0 -and -not $script:CloudHostDerivationFailure) {
                $script:CloudHostDerivationFailure = "the endpoint table '$($script:CloudEndpointPath)' holds no https:// string constant, so no host could be derived from it"
            }
        }
    }

    # The derived list is the working one; the control stands in only when the derivation produced
    # nothing, so the scan below keeps its meaning while the derivation It reports the cause. The
    # longest host goes first in the alternation, so should one host ever be the prefix of another
    # the longer one is the finding. (A host that merely ends the other, as graph.microsoft.us ends
    # dod-graph.microsoft.us, needs no ordering: the match starts at the leftmost character.)
    $script:CloudHostNames = if (@($script:CloudHostDerived).Count -gt 0) { $script:CloudHostDerived } else { $script:CloudHostDocumented }
    $script:CloudHostRegex = [regex]::new(
        (@($script:CloudHostNames | Sort-Object -Property Length -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|'),
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

    function Test-SourceHygieneArmFallbackLiteral {
        <#
        .SYNOPSIS
        Returns true when a string node is the transport's one documented fallback: the sole
        statement of the else branch of an if (and the whole of its pipeline) that is assigned,
        with a plain =, to the variable ArmBaseUrl.
        #>
        [OutputType([bool])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast]$Node
        )
        if ($Node -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { return $false }
        if ($Node.Value -cne $script:CloudArmFallbackLiteral) { return $false }
        $Expression = $Node.Parent
        if ($Expression -isnot [System.Management.Automation.Language.CommandExpressionAst]) { return $false }
        $Pipeline = $Expression.Parent
        if ($Pipeline -isnot [System.Management.Automation.Language.PipelineAst]) { return $false }
        # The literal is the whole of its pipeline: 'https://management.azure.com' | Out-Null is not it.
        if ($Pipeline.PipelineElements.Count -ne 1) { return $false }
        $Block = $Pipeline.Parent
        if ($Block -isnot [System.Management.Automation.Language.StatementBlockAst]) { return $false }
        # ... and the whole of its block: { 'y'; 'https://management.azure.com' } is not the fallback.
        if ($Block.Statements.Count -ne 1) { return $false }
        $IfStatement = $Block.Parent
        if ($IfStatement -isnot [System.Management.Automation.Language.IfStatementAst]) { return $false }
        # Reference equality: the body of an if or an elseif has the same parent and must not pass.
        if (-not [object]::ReferenceEquals($IfStatement.ElseClause, $Block)) { return $false }
        $Assignment = $IfStatement.Parent
        if ($Assignment -isnot [System.Management.Automation.Language.AssignmentStatementAst]) { return $false }
        # A plain assignment: ArmBaseUrl += if (...) { ... } else { '...' } appends to the variable.
        if ($Assignment.Operator -ne [System.Management.Automation.Language.TokenKind]::Equals) { return $false }
        if ($Assignment.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { return $false }
        return ($Assignment.Left.VariablePath.UserPath -eq $script:CloudArmFallbackVariable)
    }

    function Get-SourceHygieneCloudHostFinding {
        <#
        .SYNOPSIS
        Returns one record per cloud host named by a string node of a parsed file: Path, Line, Host
        (lower case), Text (the node's first line) and Exempt (true for the endpoint table and for
        the ARM fallback literal).
        #>
        [OutputType([pscustomobject])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast]$Ast,

            [Parameter(Mandatory)]
            [string]$RelativePath
        )
        $IsTable = $RelativePath -ceq $script:CloudEndpointPath
        $IsFallbackFile = $RelativePath -ceq $script:CloudArmFallbackPath
        foreach ($Node in $Ast.FindAll({
                    $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                    $args[0] -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
                }, $true)) {
            $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($HostMatch in $script:CloudHostRegex.Matches([string]$Node.Value)) {
                $HostName = $HostMatch.Value.ToLowerInvariant()
                if (-not $Seen.Add($HostName)) { continue }
                [pscustomobject]@{
                    Path   = $RelativePath
                    Line   = $Node.Extent.StartLineNumber
                    Host   = $HostName
                    Text   = ($Node.Extent.Text -split "`r?`n")[0].Trim()
                    Exempt = [bool]($IsTable -or ($IsFallbackFile -and (Test-SourceHygieneArmFallbackLiteral -Node $Node)))
                }
            }
        }
    }

    $script:CloudHostFindings = [System.Collections.Generic.List[object]]::new()
    $script:CloudHostParsedFileCount = 0

    # --- Pass 1: parse every PowerShell-syntax source file exactly once. ---
    #
    # A .ps1xml file is XML, which the PowerShell parser would report as errors, so it is never
    # parsed whole: the Az boundary (Pass 4) parses each of its script blocks instead, through
    # Get-SourceHygieneXmlScriptBlock, and no other pass of this loop reads it.
    # .psd1 parses cleanly as a hashtable literal.
    $script:SourceUnits = [System.Collections.Generic.List[object]]::new()
    $script:ParseFailures = [System.Collections.Generic.List[string]]::new()

    foreach ($File in $script:HygieneFiles) {
        if ($File.RelativePath -notlike 'source/*') { continue }
        if ($File.Extension -eq '.ps1xml') {
            <#
                A file that is not well-formed XML yields no script block, so it would drop out of
                the walk without failing anything; it is recorded as a parse failure instead. So is
                a script block that does not parse, whose findings are not read, as for a .ps1 file.
            #>
            try {
                $XmlBlocks = @(Get-SourceHygieneXmlScriptBlock -Text $File.Text -RelativePath $File.RelativePath)
            } catch {
                $script:ParseFailures.Add(('{0} -- not well-formed XML: {1}' -f
                        $File.RelativePath, ($_.Exception.InnerException ?? $_.Exception).Message))
                continue
            }
            foreach ($Block in $XmlBlocks) {
                $script:AzXmlScriptBlockCount++
                if ($Block.Errors.Count -gt 0) {
                    $script:ParseFailures.Add(('{0}:{1} ({2}) -- {3} parse error(s), first: {4}' -f
                            $Block.Path, $Block.Line, $Block.Element, $Block.Errors.Count, $Block.Errors[0].Message))
                    continue
                }
                foreach ($Finding in @(Get-SourceHygieneXmlAzFinding -Block $Block)) {
                    $script:AzFindings.Add($Finding)
                }
            }
            continue
        }
        if ($File.Extension -notin '.ps1', '.psm1', '.psd1') { continue }

        $Tokens = $null
        $Errors = $null
        $FileAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $File.Text, $File.Path, [ref]$Tokens, [ref]$Errors)

        <#
            A file that fails to parse yields no CommandAst and no CatchClauseAst, so it would drop
            silently out of BOTH counters -- an unterminated here-string at the top of a file would
            remove it from this gate without failing anything. Record the failure instead.
        #>
        if ($Errors.Count -gt 0) {
            $script:ParseFailures.Add(('{0} -- {1} parse error(s), first: {2}' -f
                    $File.RelativePath, $Errors.Count, $Errors[0].Message))
            continue
        }

        # Pass 4 (the Az boundary) reads the same AST; see its comment above Pass 1.
        $script:AzParsedFileCount++
        $script:AzCommandAstCount += @($FileAst.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)).Count
        foreach ($Finding in @(Get-SourceHygieneAzFinding -Ast $FileAst)) {
            $Finding | Add-Member -NotePropertyName Path -NotePropertyValue $File.RelativePath
            $script:AzFindings.Add($Finding)
        }

        # Pass 5 (the cloud hosts) reads the same AST as well; see its comment above Pass 1.
        $script:CloudHostParsedFileCount++
        foreach ($Finding in @(Get-SourceHygieneCloudHostFinding -Ast $FileAst -RelativePath $File.RelativePath)) {
            $script:CloudHostFindings.Add($Finding)
        }

        <#
            Transport is detected through CommandAst.GetCommandName(), never a text grep:
            source/Private/Remove-OPIMErrorRecord.ps1 carries the literal 'Invoke-MgGraphRequest
            @InvokeParams' inside its .EXAMPLE help block, and a grep would score it as a transport
            file. The AST never sees comment tokens. ONE FindAll walk collects the three node kinds
            the passes below need; the walk count is what costs time, not the bucketing. The names
            run through [scriptblock]::Create take one walk more, in Get-SourceHygieneRunnableName,
            so the known-answer It runs the very code this pass runs.
        #>
        $Nodes = $FileAst.FindAll({
                $args[0] -is [System.Management.Automation.Language.CommandAst] -or
                $args[0] -is [System.Management.Automation.Language.CatchClauseAst] -or
                $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]
            }, $true)

        $CommandNames = [System.Collections.Generic.List[string]]::new()
        $StringValues = [System.Collections.Generic.List[string]]::new()
        $Catches = [System.Collections.Generic.List[object]]::new()
        $CallsTransport = $false

        foreach ($Node in $Nodes) {
            if ($Node -is [System.Management.Automation.Language.CommandAst]) {
                $CommandName = $Node.GetCommandName()
                if ($CommandName) {
                    $CommandNames.Add($CommandName)
                    if (-not $CallsTransport -and $script:TransportCommands -contains $CommandName) {
                        $CallsTransport = $true
                    }
                }
            } elseif ($Node -is [System.Management.Automation.Language.CatchClauseAst]) {
                $Catches.Add($Node)
            } else {
                $StringValues.Add($Node.Value)
            }
        }

        # Top-level definition only: a nested helper is part of its parent's body, not its own node.
        $Definition = $FileAst.FindAll({
                $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $false) | Select-Object -First 1

        $script:SourceUnits.Add([PSCustomObject]@{
                RelativePath   = $File.RelativePath
                FunctionName   = if ($Definition) { $Definition.Name } else { $null }
                IsPrivate      = [bool]($File.RelativePath -like 'source/Private/*')
                CommandNames   = $CommandNames
                StringValues   = $StringValues
                RunnableNames  = @(Get-SourceHygieneRunnableName -Ast $FileAst)
                Catches        = $Catches
                CallsTransport = $CallsTransport
                Edges          = $null
            })
    }

    <#
        --- Pass 2: whole-module call-edge closure. ---

        A file counts as transport-reaching when it calls a transport command DIRECTLY or calls,
        transitively, any module function that does: a public cmdlet that reaches Graph only through
        Initialize-OPIMAuth or Get-OPIMCurrentTenantInfo receives the same records. A string
        constant naming a PRIVATE module function also counts as an edge, so a helper called through
        a name held in a variable is not missed. A public name in a plain string is no edge (the
        manifest names every public cmdlet), but a command in a string handed to
        [scriptblock]::Create is one, public or private, since that string is run -- which is how
        the six completer classes reach the Get-OPIM* cmdlets (the run-string edge, above Pass 1).
        Comment-based help is a comment token and never an AST expression, so a name that appears
        only in help creates no edge.

        Reachability is a FIXED-POINT iteration over a boolean, not a memoized depth-first walk: a
        DFS that caches results its own re-entry guard truncated can silently under-reach across a
        call cycle. Seed each function with its own direct CallsTransport, then propagate along the
        edges until a full pass changes nothing. The lattice is monotone (false -> true only), so it
        terminates and reaches the same answer in any visit order.
    #>
    $script:AllFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $script:PrivateFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Unit in $script:SourceUnits) {
        if (-not $Unit.FunctionName) { continue }
        $null = $script:AllFunctions.Add($Unit.FunctionName)
        if ($Unit.IsPrivate) { $null = $script:PrivateFunctions.Add($Unit.FunctionName) }
    }

    foreach ($Unit in $script:SourceUnits) {
        $Edges = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($CommandName in $Unit.CommandNames) {
            if ($script:AllFunctions.Contains($CommandName)) { $null = $Edges.Add($CommandName) }
        }
        foreach ($Value in $Unit.StringValues) {
            if ($script:PrivateFunctions.Contains($Value)) { $null = $Edges.Add($Value) }
        }
        foreach ($Name in $Unit.RunnableNames) {
            if ($script:AllFunctions.Contains($Name)) { $null = $Edges.Add($Name) }
        }
        $Unit.Edges = $Edges
    }

    $script:TransportReach = @{}
    foreach ($Unit in $script:SourceUnits) {
        if ($Unit.FunctionName) { $script:TransportReach[$Unit.FunctionName] = $Unit.CallsTransport }
    }
    $Changed = $true
    while ($Changed) {
        $Changed = $false
        foreach ($Unit in $script:SourceUnits) {
            if (-not $Unit.FunctionName) { continue }
            if ($script:TransportReach[$Unit.FunctionName]) { continue }
            foreach ($Edge in $Unit.Edges) {
                # A miss returns $null, which is falsy: an edge to a name with no unit of its own
                # contributes no reachability.
                if ($script:TransportReach[$Edge]) {
                    $script:TransportReach[$Unit.FunctionName] = $true
                    $Changed = $true
                    break
                }
            }
        }
    }

    # --- Pass 3: the scrub scan itself, over every transport-reaching file. ---
    $script:ScrubViolations = [System.Collections.Generic.List[string]]::new()
    $script:ScrubCatchCount = 0
    $script:ScrubTransportFiles = [System.Collections.Generic.List[string]]::new()
    $script:ScrubCatchByFile = @{}

    foreach ($Unit in $script:SourceUnits) {
        # Edges are consulted even for a unit with no function of its own (the manifest, the
        # dev-mode loader, suffix.ps1, a class file), which is why this is not just a lookup by name.
        $ReachesTransport = $Unit.CallsTransport
        if (-not $ReachesTransport) {
            foreach ($Edge in $Unit.Edges) {
                if ($script:TransportReach[$Edge]) { $ReachesTransport = $true; break }
            }
        }
        if (-not $ReachesTransport) { continue }

        $script:ScrubTransportFiles.Add($Unit.RelativePath)
        $script:ScrubCatchByFile[$Unit.RelativePath] = $Unit.Catches.Count
        $Exemption = $script:ScrubExemptions[$Unit.RelativePath]

        foreach ($Catch in $Unit.Catches) {
            $script:ScrubCatchCount++

            # The @() wrap is load-bearing: an empty catch body returns $null here instead of
            # throwing on an empty ReadOnlyCollection.
            $FirstStatement = @($Catch.Body.Statements)[0]
            $FirstText = if ($FirstStatement) { $FirstStatement.Extent.Text.Trim() } else { '' }
            if ($FirstText -match $script:ScrubFirstStatementPattern) { continue }
            if ($Exemption -and (& $Exemption $Catch)) { continue }

            $Diagnostic = if ($FirstText) { ($FirstText -split "`n")[0] } else { '<empty catch body>' }
            $script:ScrubViolations.Add(('{0}:{1} -- first statement is: {2}' -f
                    $Unit.RelativePath, $Catch.Extent.StartLineNumber, $Diagnostic))
        }
    }
}

Describe 'Source encoding' -Tags 'SourceHygiene' {

    It 'finds authored files in every scanned root' {
        <#
            Guards the whole Describe: an empty collection would make every other It vacuously pass,
            since a foreach over nothing asserts nothing. Asserted PER ROOT, not as one total, so
            losing either root fails on its own. The floor is defence in depth: the named controls
            below are what catch an enumeration that breaks.
        #>
        $SourceCount = @($script:HygieneFiles | Where-Object { $_.RelativePath -like 'source/*' }).Count
        $TestCount = @($script:HygieneFiles | Where-Object { $_.RelativePath -like 'tests/*' }).Count

        $SourceCount | Should -BeGreaterThan $script:SourceFileFloor -Because (
            'source/ held 42 authored files when this gate was written; a scan that drops to the floor or below has lost a directory, not shrunk')
        $TestCount | Should -BeGreaterThan $script:TestFileFloor -Because (
            'tests/ held 37 authored files when this gate was written; a scan that drops to the floor or below has lost a directory, not shrunk')
    }

    It 'scans the named control files' {
        # One named control per scanned root: the files whose disappearance a count would hide.
        $script:HygieneFilePaths.Contains('source/Private/Invoke-OPIMGraphRequest.ps1') |
            Should -BeTrue -Because 'the Graph wrapper must be in the encoding scan; if it is not, the source/ enumeration is broken'
        $script:HygieneFilePaths.Contains('tests/QA/sourcehygiene.tests.ps1') |
            Should -BeTrue -Because 'this gate scans itself; if it is not in its own collection, the tests/ enumeration is broken'
    }

    It 'contains no byte above 0x7F in any authored file' {
        $Checked = 0
        $Offenders = foreach ($File in $script:HygieneFiles) {
            $Checked++
            <#
                Fast path on the DECODED text: invalid UTF-8 decodes to U+FFFD and a BOM to U+FEFF,
                both above 0x7F, so a dirty file always trips the match. The match is
                case-SENSITIVE on purpose: a case-insensitive [^\x00-\x7F] lets U+212A (KELVIN SIGN)
                and U+0130 through, since the regex engine treats them as case variants of the ASCII
                letters k and i (measured on pwsh 7.6.6: -match False, -cmatch True). The per-byte
                count and offset run only for a file already known to be dirty, for the diagnostic.
            #>
            if ($File.Text -cnotmatch '[^\x00-\x7F]') { continue }

            $Count = 0
            foreach ($Byte in $File.Bytes) {
                if ($Byte -gt 0x7F) { $Count++ }
            }
            $FirstOffset = [Array]::FindIndex($File.Bytes, [Predicate[byte]] { param($B) $B -gt 0x7F })
            '{0} ({1} non-ASCII bytes, first at offset {2})' -f $File.RelativePath, $Count, $FirstOffset
        }
        $Checked | Should -BeGreaterThan ($script:SourceFileFloor + $script:TestFileFloor) -Because 'the check must have read the scanned tree; an empty scan would pass vacuously'
        $Offenders -join "`n" | Should -BeNullOrEmpty -Because @'
CLAUDE.md ("CRITICAL: ASCII-Only Source Files") requires authored .ps1/.psd1/.psm1/.ps1xml files to
be ASCII only. Use -- for an em-dash, -> for an arrow, straight quotes for smart quotes, and an ASCII
hyphen for a box-drawing rule in a .ps1 comment ('=' inside an XML comment, where '--' is illegal).
PSScriptAnalyzer's PSUseBOMForUnicodeEncodedFile does not cover this: it passes the moment a file
gains a BOM, and it never sees anything under tests/. The files listed are what is left to convert
'@
    }

    It 'carries no UTF-8 BOM in any authored file' {
        $Checked = 0
        $Offenders = foreach ($File in $script:HygieneFiles) {
            $Checked++
            if ($File.Bytes.Length -ge 3 -and
                $File.Bytes[0] -eq 0xEF -and $File.Bytes[1] -eq 0xBB -and $File.Bytes[2] -eq 0xBF) {
                $File.RelativePath
            }
        }
        $Checked | Should -BeGreaterThan ($script:SourceFileFloor + $script:TestFileFloor) -Because 'the check must have read the scanned tree; an empty scan would pass vacuously'
        $Offenders -join "`n" | Should -BeNullOrEmpty -Because @'
CLAUDE.md requires authored files to be UTF-8 WITHOUT a BOM. A BOM also silently disables
PSScriptAnalyzer's PSUseBOMForUnicodeEncodedFile rule, so a BOM-carrying file can hide non-ASCII
content from the analyzer entirely. There is deliberately NO allow-list here: no file in this tree
is a verbatim copy that has to keep a BOM. The files listed still carry one
'@
    }
}

Describe 'Cmdlet reference hygiene' -Tags 'SourceHygiene' {

    It 'scans a meaningful number of source files and cmdlet-name tokens' {
        <#
            Without this, a detection bug that matched no files (a broken pattern, an empty file
            list) would make the assertion below pass VACUOUSLY.
        #>
        $script:CmdletRefFiles.Count | Should -BeGreaterThan $script:CmdletRefFileFloor -Because (
            'source/ held 38 .ps1 files when this gate was written; a scan that drops to the floor or below has lost a directory, not shrunk')
        $script:CmdletRefTokenCount | Should -BeGreaterThan $script:CmdletRefTokenFloor -Because (
            'source/**/*.ps1 carried 349 Verb-OPIM tokens when this gate was written; a scan that drops to the floor or below has broken detection, not found fewer references')
        $script:ManifestAliases | Should -Contain 'Enable-OPIMMyRoles' -Because (
            'the known names must include the manifest aliases; if the AliasesToExport read returned nothing, an alias reference would be reported as stale')
        @($script:NestedCommandNames) | Should -Contain 'Invoke-OPIMGraphSingle' -Because (
            'the known names must include the nested functions source/ defines; if the AST walk found none, a reference to the Graph wrapper''s request function would be reported as stale')
        $script:NestedCommandNames.Contains('Get-OPIMDirectoryRole') | Should -BeFalse -Because (
            'a top-level function is known by its file, never as a nested one')
    }

    It 'resolves every Verb-OPIM token in source/**/*.ps1 to a function file, a nested function or an exported alias' {
        $script:CmdletRefTokenCount | Should -BeGreaterThan $script:CmdletRefTokenFloor -Because 'the scan must have found the references it checks; zero tokens would pass vacuously'
        $script:CmdletRefViolations -join "`n" | Should -BeNullOrEmpty -Because @'
a comment, a help block or a message naming a command that is neither a function file under
source/Public or source/Private, a function nested in one of those files, nor an alias in
AliasesToExport points a reader at a command that fails when they run it. This is a TEXT scan
over the whole file, not an AST walk, since a stale reference lives in prose -- a comment token the
parser never turns into a CommandAst. Fix the reference; do not exempt a file from this scan
'@
    }
}

Describe 'Bearer-token hygiene' -Tags 'SourceHygiene' {

    It 'parses every scanned source file' {
        $script:ParseFailures -join "`n" | Should -BeNullOrEmpty -Because @'
a source file that fails to parse produces no CommandAst and no CatchClauseAst, so it silently drops
out of BOTH the transport-file counter and the catch counter below -- an unterminated here-string at
the top of a file removes it from this gate without failing anything. Fix the syntax error; do not
exclude the file
'@
    }

    It 'scans a meaningful number of catch clauses' {
        <#
            Without this, a detection bug that matched no files would make the gate below pass
            vacuously -- prove a guard can FAIL, not just that it can pass. The floors and the counts
            they sit under are in the BeforeAll.
        #>
        $script:ScrubTransportFiles.Count | Should -BeGreaterThan $script:ScrubTransportFileFloor -Because (
            'source/ held 26 transport-reaching files on 2026-10-10, the six completer classes among them; a scan at the floor or below has broken transport detection, not found fewer files. Found: {0}' -f ($script:ScrubTransportFiles -join ', '))
        $script:ScrubCatchCount | Should -BeGreaterThan $script:ScrubCatchFloor -Because (
            'those files held 85 of the 103 catch clauses in source/ on 2026-10-10; a count at the floor or below has broken the catch enumeration, not found fewer catches')
    }

    It 'counts every catch of the named control file' {
        <#
            The named positive control. source/Private/Invoke-OPIMGraphRequest.ps1 is the module's
            Graph transport wrapper and the one file that can never legitimately leave this scan. If
            a catch is genuinely added to or removed from that file, update the count deliberately.
        #>
        $script:ScrubCatchByFile.ContainsKey($script:ScrubControlPath) |
            Should -BeTrue -Because 'the Graph wrapper must be detected as a transport file; if it is not, transport detection is broken'
        $script:ScrubCatchByFile[$script:ScrubControlPath] | Should -Be $script:ScrubControlCatchCount -Because (
            'source/Private/Invoke-OPIMGraphRequest.ps1 holds {0} catch clauses, every one of them scrubbing first' -f $script:ScrubControlCatchCount)
    }

    It 'reaches the six completer classes through the commands their [scriptblock]::Create strings run' {
        <#
            The second named control. Each completer class lists through a Get-OPIM* cmdlet that it
            names only inside a string handed to [scriptblock]::Create, so the classes are on a
            transport path through the run-string edge of Pass 2 alone. The paths are read from
            the files on disk, not from the parsed units, so a class that stopped parsing is
            missing here as well as in the parse It above.
        #>
        $ClassPaths = @($script:HygieneFiles | Where-Object { $_.RelativePath -like 'source/Classes/*.ps1' } | ForEach-Object { $_.RelativePath })
        $ClassPaths.Count | Should -Be 6 -Because 'source/Classes holds the six completer classes; fewer means the scan lost them, more means a class was added and this control must name it'
        $Missing = @($ClassPaths | Where-Object { $script:ScrubTransportFiles -notcontains $_ })
        $Missing -join ', ' | Should -BeNullOrEmpty -Because (
            'a command in a string handed to [scriptblock]::Create is run, so it is a call; a class that lists through one is on a transport path and its catches must scrub first. Classes outside the closure')
    }

    It 'counts a command in a [scriptblock]::Create string as a call, and a public name in a plain string as none (known answer)' {
        # The positive control of the run-string edge, run through the function Pass 1 calls. Line 1
        # is the completers' own form and line 2 the full type name: both are calls. Line 3 is a
        # public name in a plain string, which is no call. Line 4 hands Create a variable, whose
        # text no parser can see. Line 5 writes the type and the method in other letter cases, which
        # PowerShell resolves the same. Line 6 calls Create on an instance and line 7 on another
        # type, and neither builds a script block from a constant: no call either.
        $Text = @'
$Listed = @(& ([scriptblock]::Create('Get-OPIMDirectoryRole -Activated')))
$Group = [System.Management.Automation.ScriptBlock]::Create('Get-OPIMEntraIDGroup')
$X = 'Get-OPIMAzureRole'
$Run = [scriptblock]::Create($Variable)
$Config = [ScriptBlock]::create('Get-OPIMConfiguration -TenantAlias contoso')
$Again = $Factory.Create('Disable-OPIMMyRole')
$Other = [string]::Create('Enable-OPIMMyRole')
'@
        $Errors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$Errors)
        $Errors | Should -BeNullOrEmpty -Because 'the known-answer text must parse, or it proves nothing'
        @(Get-SourceHygieneRunnableName -Ast $Ast) | Should -Be @('Get-OPIMDirectoryRole', 'Get-OPIMEntraIDGroup', 'Get-OPIMConfiguration')

        # The real-tree half of line 3: the source manifest names every public cmdlet in a plain
        # string (FunctionsToExport) and runs none of them, so Pass 2 gives it no edge and it is on
        # no transport path.
        @($script:ScrubTransportFiles) | Should -Not -Contain 'source/Omnicit.PIM.psd1' -Because (
            'a public name in a plain string is no call; the manifest lists the public cmdlets without running them')
    }

    It 'calls Remove-OPIMErrorRecord as the first statement of every catch on a transport path' {
        $script:ScrubViolations -join "`n" | Should -BeNullOrEmpty -Because @'
CLAUDE.md (Error Handling, SECURITY rule 5): the raw record of a failed request points at the
HttpRequestMessage whose Authorization header carries the bearer token in plain text, so
Remove-OPIMErrorRecord -Record $PSItem must be the FIRST statement of every catch in a file that
reaches Graph, ARM or a sign-in -- directly or through any module function it calls. The older
$Error.Remove($PSItem) idiom never worked: a module has its own private $Error list, and the record
bound to $PSItem is a different instance than the one PowerShell appended to the caller's
$global:Error. If a catch is genuinely exempt (no record of a request can reach it), add it to
$script:ScrubExemptions with a structural predicate rather than deleting this assertion. Catches that
do not scrub first
'@
    }
}

Describe 'suffix.ps1 / psm1 mirror sync' -Tags 'SourceHygiene' {

    It 'keeps the mirrored region byte-identical between suffix.ps1 and the dev-mode psm1' {
        <#
            ModuleBuilder appends suffix.ps1 to the built psm1; the dev-mode loader
            (source/Omnicit.PIM.psm1) carries the same block for an import from source (CLAUDE.md,
            "Common Pitfalls"). The region runs from the line '# TypesToProcess is disabled in the
            manifest' to END OF FILE, so a block appended to either file later is inside the
            comparison with no gate edit. In suffix.ps1 the anchor must also be the FIRST line:
            ModuleBuilder appends the whole file, so a line above the anchor would reach the built
            module without ever being compared. (The psm1 legitimately holds the loader above it.)

            The bytes are decoded as Latin-1, which maps every byte to exactly one character, so the
            string comparison below IS a byte comparison. A UTF-8 BOM can stand only before the
            first line, and the pattern steps over it so the region never includes it.
        #>
        $Anchor = '(?m)^(?:\xEF\xBB\xBF)?(# TypesToProcess is disabled in the manifest[\s\S]*)\z'
        $SuffixBytes = [System.IO.File]::ReadAllBytes((Join-Path -Path $script:ProjectPath -ChildPath (Join-Path -Path 'source' -ChildPath 'suffix.ps1')))
        $Psm1Bytes = [System.IO.File]::ReadAllBytes((Join-Path -Path $script:ProjectPath -ChildPath (Join-Path -Path 'source' -ChildPath 'Omnicit.PIM.psm1')))
        $SuffixMatch = [System.Text.RegularExpressions.Regex]::Match([System.Text.Encoding]::Latin1.GetString($SuffixBytes), $Anchor)
        $Psm1Match = [System.Text.RegularExpressions.Regex]::Match([System.Text.Encoding]::Latin1.GetString($Psm1Bytes), $Anchor)
        $SuffixRegion = if ($SuffixMatch.Success) { $SuffixMatch.Groups[1].Value } else { $null }
        $Psm1Region = if ($Psm1Match.Success) { $Psm1Match.Groups[1].Value } else { $null }

        # Separates "the anchor found nothing" from "the regions differ": a $null pair would
        # otherwise pass the equality check vacuously.
        $SuffixRegion | Should -Not -BeNullOrEmpty -Because 'the mirrored region must be found in suffix.ps1 by its anchor line, or this gate compares nothing'
        $Psm1Region | Should -Not -BeNullOrEmpty -Because 'the mirrored region must be found in the dev-mode psm1 by its anchor line, or this gate compares nothing'
        $SuffixMatch.Index | Should -Be 0 -Because 'ModuleBuilder appends the whole of suffix.ps1 to the built module, so the anchor line must open the file; anything above it would ship without being compared with the psm1'
        $SuffixRegion | Should -Match 'Update-TypeData' -Because 'the compared region must hold the Update-TypeData call it exists to keep in step'
        $Psm1Region | Should -Match 'Update-TypeData' -Because 'the compared region must hold the Update-TypeData call it exists to keep in step'

        $Psm1Region | Should -BeExactly $SuffixRegion -Because (
            'suffix.ps1 is appended verbatim to the built module, so the dev-mode psm1 must carry the same region byte for byte -- otherwise an import from source (Import-Module ./source/Omnicit.PIM.psd1) and the built module load type data differently')
    }
}

Describe 'Format and type data' -Tags 'SourceHygiene' {

    BeforeAll {
        <#
            A ScriptProperty of Omnicit.PIM.Types.ps1xml must not read a member of its own name
            through $this (OPIM-48). An object's own NoteProperty shadows a type-data ScriptProperty
            of the same name, compared without regard to case, so such a property runs only on an
            object WITHOUT the note, and there $this.<same name> resolves to the ScriptProperty
            itself: unbounded recursion that kills the process. The echoes read the note by member
            type instead, $this.PSObject.Properties.Match('<name>', 'NoteProperty').

            The detector is given the XML TEXT, so a test can feed it a copy of the file. It parses
            every GetScriptBlock and SetScriptBlock of every Type/Members/ScriptProperty with the
            PowerShell parser and reports each MemberExpressionAst whose expression is the variable
            this and whose member is a constant string equal to the property's Name, ignoring case
            (a method call on the member is a MemberExpressionAst too). It returns Walked (the
            ScriptProperty members read, the floor of the walk), ParseErrors, and Findings.

            KNOWN LIMITS, which review has to catch: a member name assembled at run time
            ($this.$Name, $this.('member' + 'Type')), a read through $_ or $PSItem, which the
            detector does not follow, and a self-read through another member of the same object
            ($this.PSObject.Properties['MemberType'].Value). Nothing here runs module code.
        #>
        function Get-SourceHygieneSelfReadingProperty {
            [OutputType([pscustomobject])]
            param(
                [Parameter(Mandatory)]
                [string]$Xml
            )
            $Document = [xml]::new()
            $Document.LoadXml($Xml)
            $Walked = 0
            $ParseErrors = [System.Collections.Generic.List[string]]::new()
            $Findings = [System.Collections.Generic.List[pscustomobject]]::new()
            foreach ($TypeNode in $Document.SelectNodes('/Types/Type')) {
                $TypeName = $TypeNode.SelectSingleNode('Name').InnerText.Trim()
                foreach ($PropertyNode in $TypeNode.SelectNodes('Members/ScriptProperty')) {
                    $Walked++
                    $PropertyName = $PropertyNode.SelectSingleNode('Name').InnerText.Trim()
                    foreach ($Accessor in 'GetScriptBlock', 'SetScriptBlock') {
                        $BlockNode = $PropertyNode.SelectSingleNode($Accessor)
                        if ($null -eq $BlockNode) { continue }
                        $Errors = $null
                        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($BlockNode.InnerText, [ref]$null, [ref]$Errors)
                        foreach ($ParseError in $Errors) {
                            $ParseErrors.Add(('{0}/{1} {2}: {3}' -f $TypeName, $PropertyName, $Accessor, $ParseError.Message))
                        }
                        foreach ($Node in $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.MemberExpressionAst] }, $true)) {
                            if ($Node.Expression -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
                            if ($Node.Expression.VariablePath.UserPath -ne 'this') { continue }
                            if ($Node.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { continue }
                            if (-not [string]::Equals($Node.Member.Value, $PropertyName, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                            $Findings.Add([pscustomobject]@{
                                    Type     = $TypeName
                                    Property = $PropertyName
                                    Accessor = $Accessor
                                    Line     = $Node.Extent.StartLineNumber
                                    Read     = $Node.Extent.Text
                                })
                        }
                    }
                }
            }
            [pscustomobject]@{
                Walked      = $Walked
                ParseErrors = $ParseErrors.ToArray()
                Findings    = $Findings.ToArray()
            }
        }
    }

    It 'parses every .ps1xml file under source/ as XML' {
        <#
            suffix.ps1 loads Omnicit.PIM.Types.ps1xml with Update-TypeData -ErrorAction
            SilentlyContinue, so a Types file that stops being well-formed XML -- for example a box
            rule turned into '--' inside an XML comment -- stops loading SILENTLY: the import
            succeeds and the type members are missing. A broken Format file fails the import
            instead. Either way, this names the file first.
        #>
        $XmlFiles = @($script:HygieneFiles | Where-Object { $_.RelativePath -like 'source/*' -and $_.Extension -eq '.ps1xml' })
        $XmlFiles.Count | Should -BeGreaterThan 1 -Because 'source/Formats holds the Format and the Types file; fewer than two means the scan lost them'

        $Failures = foreach ($File in $XmlFiles) {
            try {
                $Document = [xml]::new()
                $Document.Load($File.Path)
            } catch {
                '{0} -- {1}' -f $File.RelativePath, ($_.Exception.InnerException ?? $_.Exception).Message
            }
        }
        $Failures -join "`n" | Should -BeNullOrEmpty -Because 'every .ps1xml file under source/ must be well-formed XML, or PowerShell cannot load it'
    }

    It 'tells a ScriptProperty that reads its own name from one that reads the note by member type (known answer)' {
        # The positive control of the next It: if the detector stops matching, this text no longer
        # yields its findings. Each Type below is one case, named for what it holds.
        $Text = @'
<?xml version="1.0" encoding="utf-8"?>
<Types>
  <Type>
    <Name>Case.OwnName</Name>
    <Members>
      <ScriptProperty>
        <Name>MemberType</Name>
        <GetScriptBlock>
          $this.memberType
        </GetScriptBlock>
      </ScriptProperty>
    </Members>
  </Type>
  <Type>
    <Name>Case.MatchForm</Name>
    <Members>
      <ScriptProperty>
        <Name>MemberType</Name>
        <GetScriptBlock>
          foreach ($Note in $this.PSObject.Properties.Match('memberType', [System.Management.Automation.PSMemberTypes]::NoteProperty)) { $Note.Value }
        </GetScriptBlock>
      </ScriptProperty>
    </Members>
  </Type>
  <Type>
    <Name>Case.OwnNameOtherCase</Name>
    <Members>
      <ScriptProperty>
        <Name>AccessId</Name>
        <GetScriptBlock>
          $this.AccessID
        </GetScriptBlock>
      </ScriptProperty>
    </Members>
  </Type>
  <Type>
    <Name>Case.OtherMember</Name>
    <Members>
      <ScriptProperty>
        <Name>RoleName</Name>
        <GetScriptBlock>
          $this.roleDefinition.displayName
        </GetScriptBlock>
      </ScriptProperty>
    </Members>
  </Type>
  <Type>
    <Name>Case.OtherObject</Name>
    <Members>
      <ScriptProperty>
        <Name>MemberType</Name>
        <GetScriptBlock>
          $Other.memberType
        </GetScriptBlock>
      </ScriptProperty>
    </Members>
  </Type>
  <Type>
    <Name>Case.OwnNameInSetter</Name>
    <Members>
      <ScriptProperty>
        <Name>AssignmentType</Name>
        <GetScriptBlock>
          $this.scheduleInfo
        </GetScriptBlock>
        <SetScriptBlock>
          $this.assignmentType = $args[0]
        </SetScriptBlock>
      </ScriptProperty>
    </Members>
  </Type>
</Types>
'@
        $Result = Get-SourceHygieneSelfReadingProperty -Xml $Text
        $Result.ParseErrors | Should -BeNullOrEmpty
        $Result.Walked | Should -Be 6
        @($Result.Findings | ForEach-Object { '{0} {1} {2} {3}' -f $_.Type, $_.Property, $_.Accessor, $_.Read }) | Should -Be @(
            'Case.OwnName MemberType GetScriptBlock $this.memberType'
            'Case.OwnNameOtherCase AccessId GetScriptBlock $this.AccessID'
            'Case.OwnNameInSetter AssignmentType SetScriptBlock $this.assignmentType'
        )
    }

    It 'reads no member of its own name through $this in any ScriptProperty of the Types file' {
        # The path is named, not found by a pattern: a renamed Types file must turn this red instead
        # of leaving it with nothing to read.
        $TypesFile = @($script:HygieneFiles | Where-Object { $_.RelativePath -eq 'source/Formats/Omnicit.PIM.Types.ps1xml' })
        $TypesFile.Count | Should -Be 1 -Because 'the gate reads the Types file by its path, and a renamed file would leave it with nothing to check'

        $Result = Get-SourceHygieneSelfReadingProperty -Xml $TypesFile[0].Text
        # 29 ScriptProperty members today; the floor sits under it, so an emptied walk cannot pass.
        $Result.Walked | Should -BeGreaterOrEqual 25 -Because 'a walk that read almost no ScriptProperty proves nothing'
        $Result.ParseErrors -join "`n" | Should -BeNullOrEmpty -Because 'a script block that does not parse cannot be checked'

        $Report = $Result.Findings | ForEach-Object { '{0} / {1} ({2}, line {3}): {4}' -f $_.Type, $_.Property, $_.Accessor, $_.Line, $_.Read }
        $Report -join "`n" | Should -BeNullOrEmpty -Because (
            'an object''s own note of the same name shadows the ScriptProperty, so a ScriptProperty runs only on an object without that note, and there a $this read of its own name calls the property itself until the stack overflows and the process dies; read the note with $this.PSObject.Properties.Match(''<name>'', ''NoteProperty'') instead')
    }
}

Describe 'Az boundary' -Tags 'SourceHygiene' {

    It 'recognises every Az shape it refuses, and allows only AzAuth''s Get-AzToken (known answer)' {
        # The positive control of the gate: if the matcher, the string pass or the module pass stops
        # matching, this text no longer yields its findings. Every branch of the detector has a line
        # of its own: line 7 is an expandable string (it holds a variable), the form a run-time
        # argument takes; line 15 is a command name built in an expandable string, which has no
        # static name; line 16 is the allow list's module qualifier; line 17 is an allowed name under
        # an Az module, refused; and line 18 is an Az module qualifier on a name without -Az.
        $Text = @'
#requires -Modules Az.Resources
function Test-AzShape {
    Connect-AzAccount -Identity
    Az.Accounts\Get-AzContext
    & 'Disconnect-AzAccount'
    $null = [scriptblock]::Create('Get-AzAccessToken')
    Invoke-Expression "Update-AzConfig -Scope $Scope"
    Import-Module Az.Accounts
    $Manifest = @{ RequiredModules = @(@{ ModuleName = 'Az.Resources'; ModuleVersion = '9.0.3' }) }
    # Connect-AzAccount in a comment is no call
    Get-AzToken -Resource 'https://management.azure.com'
    Invoke-OPIMAzTokenCall
    Write-Verbose 'Run Connect-AzAccount yourself for an Az session of your own.'
    Get-OPIMAzureRole
    & "Connect-AzAccount$Suffix"
    AzAuth\Get-AzToken -Resource 'https://management.azure.com'
    Az.Accounts\Get-AzToken
    Az.Accounts\Resolve-Error
}
'@
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
        $All = @(Get-SourceHygieneAzFinding -Ast $Ast)
        @($All | Where-Object { -not $_.Allowed } | Sort-Object -Property Line, Kind | ForEach-Object { '{0} {1} {2}' -f $_.Line, $_.Kind, $_.Name }) | Should -Be @(
            '1 Module Az.Resources'
            '3 Call Connect-AzAccount'
            '4 Call Az.Accounts\Get-AzContext'
            '5 Call Disconnect-AzAccount'
            '6 String Get-AzAccessToken'
            '7 String Update-AzConfig'
            '8 Module Az.Accounts'
            '9 Module Az.Resources'
            '15 String Connect-AzAccount$Suffix'
            '17 Call Az.Accounts\Get-AzToken'
            '18 Call Az.Accounts\Resolve-Error'
        )
        @($All | Where-Object Allowed | ForEach-Object { '{0} {1}' -f $_.Line, $_.Name }) | Should -Be @('11 Get-AzToken', '16 AzAuth\Get-AzToken')
    }

    It 'finds an Az command in a script block of a .ps1xml file, and allows Get-AzToken there (known answer)' {
        # The positive control of the .ps1xml walk, run through the functions Pass 1 calls. The Types
        # text holds one case per script element the walk reads: a call (line 8), a command run
        # through [scriptblock]::Create (line 12, its & written &amp; as XML requires), the allowed
        # Get-AzToken (line 16), a SetScriptBlock whose call sits on its third line (line 19), a
        # ScriptMethod body in a CDATA section (line 26), and a script block that does not parse
        # (line 32), which Pass 1 reports as a parse failure instead of reading it. The NoteProperty
        # of line 34 and the column Label of the Format text name Az commands as data, which is never
        # run, so the walk reads neither. A finding's line is the line of the file it sits on.
        $Types = @'
<?xml version="1.0" encoding="utf-8"?>
<Types>
  <Type>
    <Name>Case.Types</Name>
    <Members>
      <ScriptProperty>
        <Name>Call</Name>
        <GetScriptBlock>Connect-AzAccount</GetScriptBlock>
      </ScriptProperty>
      <ScriptProperty>
        <Name>RunString</Name>
        <GetScriptBlock>&amp; ([scriptblock]::Create('Get-AzContext'))</GetScriptBlock>
      </ScriptProperty>
      <ScriptProperty>
        <Name>Allowed</Name>
        <GetScriptBlock>Get-AzToken -Resource x</GetScriptBlock>
        <SetScriptBlock>
          $Value = $args[0]
          Set-AzContext -Subscription $Value
        </SetScriptBlock>
      </ScriptProperty>
      <ScriptMethod>
        <Name>Method</Name>
        <Script>
          <![CDATA[
          Update-AzConfig -Scope Process
          ]]>
        </Script>
      </ScriptMethod>
      <ScriptProperty>
        <Name>Broken</Name>
        <GetScriptBlock>if ($this.Name) {</GetScriptBlock>
      </ScriptProperty>
      <NoteProperty>
        <Name>Connect-AzAccount</Name>
        <Value>Get-AzContext</Value>
      </NoteProperty>
    </Members>
  </Type>
</Types>
'@
        $Format = @'
<?xml version="1.0" encoding="utf-8"?>
<Configuration>
  <ViewDefinitions>
    <View>
      <Name>Case.Format</Name>
      <ViewSelectedBy>
        <TypeName>Case.Format</TypeName>
      </ViewSelectedBy>
      <TableControl>
        <TableHeaders>
          <TableColumnHeader>
            <Label>Get-AzContext</Label>
          </TableColumnHeader>
        </TableHeaders>
        <TableRowEntries>
          <TableRowEntry>
            <TableColumnItems>
              <TableColumnItem>
                <ScriptBlock>Get-AzRoleAssignment</ScriptBlock>
              </TableColumnItem>
            </TableColumnItems>
          </TableRowEntry>
        </TableRowEntries>
      </TableControl>
    </View>
  </ViewDefinitions>
</Configuration>
'@
        $Blocks = @(
            Get-SourceHygieneXmlScriptBlock -Text $Types -RelativePath 'source/Formats/Case.Types.ps1xml'
            Get-SourceHygieneXmlScriptBlock -Text $Format -RelativePath 'source/Formats/Case.Format.ps1xml'
        )
        @($Blocks | ForEach-Object { '{0}:{1} {2} {3}' -f $_.Path, $_.Line, $_.Element, ($_.Errors.Count -gt 0) }) | Should -Be @(
            'source/Formats/Case.Types.ps1xml:8 GetScriptBlock False'
            'source/Formats/Case.Types.ps1xml:12 GetScriptBlock False'
            'source/Formats/Case.Types.ps1xml:16 GetScriptBlock False'
            'source/Formats/Case.Types.ps1xml:17 SetScriptBlock False'
            'source/Formats/Case.Types.ps1xml:24 Script False'
            'source/Formats/Case.Types.ps1xml:32 GetScriptBlock True'
            'source/Formats/Case.Format.ps1xml:19 ScriptBlock False'
        )

        # As in Pass 1, a script block that does not parse is not read, and a finding's line counts
        # from the line of its element.
        $Findings = foreach ($Block in $Blocks) {
            if ($Block.Errors.Count -gt 0) { continue }
            foreach ($Finding in @(Get-SourceHygieneXmlAzFinding -Block $Block)) {
                [pscustomobject]@{
                    Text    = '{0}:{1} {2} {3}' -f $Finding.Path, $Finding.Line, $Finding.Kind, $Finding.Name
                    Allowed = $Finding.Allowed
                }
            }
        }
        @($Findings | Where-Object { -not $_.Allowed } | ForEach-Object Text) | Should -Be @(
            'source/Formats/Case.Types.ps1xml:8 Call Connect-AzAccount'
            'source/Formats/Case.Types.ps1xml:12 String Get-AzContext'
            'source/Formats/Case.Types.ps1xml:19 Call Set-AzContext'
            'source/Formats/Case.Types.ps1xml:26 Call Update-AzConfig'
            'source/Formats/Case.Format.ps1xml:19 Call Get-AzRoleAssignment'
        )
        @($Findings | Where-Object Allowed | ForEach-Object Text) | Should -Be @('source/Formats/Case.Types.ps1xml:16 Call Get-AzToken')
    }

    It 'parses every source file and walks a meaningful number of command nodes' {
        # A missing floor would compare with $null, which every count passes.
        $script:AzParsedFileFloor | Should -BeGreaterThan 0
        $script:AzCommandAstFloor | Should -BeGreaterThan 0
        $script:ParseFailures | Should -BeNullOrEmpty
        $script:AzParsedFileCount | Should -BeGreaterOrEqual $script:AzParsedFileFloor
        $script:AzCommandAstCount | Should -BeGreaterOrEqual $script:AzCommandAstFloor
    }

    It 'reads a meaningful number of script blocks in the .ps1xml files' {
        # The floor of the .ps1xml walk: a walk that lost a file, an element name or its loop would
        # read no script block at all, which is indistinguishable from a clean tree without this. The
        # Types file alone holds fewer script blocks than the floor, and so does the Format file.
        $script:AzXmlScriptBlockFloor | Should -BeGreaterThan 0 -Because 'a missing floor would compare with $null, which every count passes'
        $script:ParseFailures | Should -BeNullOrEmpty
        $script:AzXmlScriptBlockCount | Should -BeGreaterOrEqual $script:AzXmlScriptBlockFloor -Because (
            'the two .ps1xml files under source/ held 37 script blocks on 2026-10-10 (29 GetScriptBlock in the Types file, 8 ScriptBlock in the Format file); a count under the floor has broken the walk, not found less code')
    }

    It 'sees the two Get-AzToken calls of Initialize-OPIMAuth, the named control' {
        # The real-tree half of the positive control: a matcher that stopped seeing the tree would
        # find no Az-shaped call at all, which is indistinguishable from a clean tree without this.
        @($script:AzFindings | Where-Object {
                $_.Allowed -and $_.Path -eq 'source/Private/Initialize-OPIMAuth.ps1'
            }).Count | Should -Be 2
    }

    It 'calls, runs, requires and declares no Az module command anywhere under source/' {
        $Violations = @($script:AzFindings | Where-Object { -not $_.Allowed } | ForEach-Object {
                '{0}:{1} -- {2} {3}' -f $_.Path, $_.Line, $_.Kind, $_.Name
            })
        ($Violations -join '; ') | Should -BeNullOrEmpty -Because (
            'Omnicit.PIM signs in to Azure with AzAuth''s Get-AzToken and sends every request itself ' +
            '(Invoke-OPIMArmRequest); it calls, loads and declares no Az module (A7). Do not add the ' +
            'offending name to the allow list: a new Az dependency is a design decision, not an entry here')
    }
}

Describe 'Cloud hosts' -Tags 'SourceHygiene' {

    It 'derives the ten cloud hosts from the table and matches the documented list' {
        # Asserted in this order on purpose: the comparison names what has to change together, and the
        # count is the backstop it cannot be, since Compare-Object over two EMPTY lists returns
        # nothing and would pass if the derivation and the control were emptied in one edit.
        $script:CloudHostDerivationFailure | Should -BeNullOrEmpty -Because (
            'the whole list this pass scans for is read out of the endpoint table; if that read failed, the scan is measuring the written control and not the table')

        $Documented = [string[]]@($script:CloudHostDocumented)
        [System.Array]::Sort($Documented, [System.StringComparer]::Ordinal)
        $Difference = @(Compare-Object -ReferenceObject $Documented -DifferenceObject @($script:CloudHostDerived) -CaseSensitive |
                ForEach-Object { '{0} {1}' -f $_.SideIndicator, $_.InputObject })
        $Difference -join "`n" | Should -BeNullOrEmpty -Because @'
the hosts derived from source/Private/Get-OPIMCloudEndpoint.ps1 no longer match the documented list
in this gate ($script:CloudHostDocumented). A '=>' line is a host the table resolves and this gate
does not name -- most likely a cloud was added to the table. Adding a cloud is a deliberate edit:
update $script:CloudHostDocumented here, and every place that documents the cloud hosts, in the
same change that adds the row. A '<=' line is the reverse -- a host this gate names that the table
no longer resolves. Do not delete this assertion to get past it. The hosts that differ
'@

        @($script:CloudHostDerived).Count | Should -Be 10 -Because (
            'the four clouds resolve ten distinct hosts (USGovDoD shares the ARM and authority hosts of USGov); zero means the derivation stopped firing, and any other count means the table gained or lost a cloud')
    }

    It 'recognises every refused shape and exempts only the table and the ARM fallback (known answer)' {
        # The positive control of the gate: if a node kind, the match or an exemption stops working,
        # these texts no longer yield their findings. Every text is parsed in memory with the
        # detector's own entry point, under the path that decides its exemption.
        $Run = {
            param([string]$Text, [string]$Path)
            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$Errors)
            if ($Errors.Count -gt 0) { throw "the known-answer text for '$Path' does not parse: $($Errors[0].Message)" }
            @(Get-SourceHygieneCloudHostFinding -Ast $Ast -RelativePath $Path)
        }
        $ShowHost = { param($Findings) @($Findings | Sort-Object -Property Line, Host | ForEach-Object { '{0} {1}' -f $_.Line, $_.Host }) }
        $ShowExempt = { param($Findings) @($Findings | Sort-Object -Property Line, Host | ForEach-Object { '{0} {1} {2}' -f $_.Line, $_.Host, $_.Exempt }) }

        # (a) Refused shapes, in a file that is neither the table nor the transport: line 1 a quoted
        # literal, line 2 an expandable string (it holds a variable), line 3 a bareword argument, line
        # 4 a quoted literal in capitals (the match ignores case); line 5 is a comment, which is no AST
        # node, and yields nothing.
        $Refused = @'
$Graph = 'https://graph.microsoft.us/v1.0'
$Authority = "https://$Tenant.login.microsoftonline.us"
Write-Output management.chinacloudapi.cn
$Shout = 'GRAPH.MICROSOFT.COM'
# login.microsoftonline.com
'@
        $Elsewhere = & $Run $Refused 'source/Private/Fake.ps1'
        & $ShowHost $Elsewhere | Should -Be @(
            '1 graph.microsoft.us'
            '2 login.microsoftonline.us'
            '3 management.chinacloudapi.cn'
            '4 graph.microsoft.com'
        )
        @($Elsewhere | Where-Object Exempt).Count | Should -Be 0 -Because 'a file that is neither the table nor the transport has no exemption'

        # (b) The same text IS the table when it sits under the table's path: all four are exempt.
        $InTable = & $Run $Refused 'source/Private/Get-OPIMCloudEndpoint.ps1'
        @($InTable).Count | Should -Be 4
        @($InTable | Where-Object { -not $_.Exempt }).Count | Should -Be 0 -Because 'the table is exempt whole, since every literal in it is the table'

        # (c) The transport's one exemption is a SHAPE, not a file. Line 1 is the fallback itself (an
        # elseif before the else is part of the real shape); line 2 is an unrelated literal in the same
        # file; line 3 is the same else literal assigned to another variable; lines 4 and 5 are the
        # literal in the body of an elseif and of the if (same parent as the else, a different clause);
        # line 6 is a sovereign host in the fallback slot; line 7 is no if at all; line 8 is the
        # literal as the argument of a command, and line 9 is an expandable string, both inside the
        # else; line 10 is the literal as the second statement of the else block, line 11 the literal
        # as the first element of a longer pipeline, and line 12 an append (+=) to the variable.
        $Transport = @'
$ArmBaseUrl = if ($A) { 'x' } elseif ($B) { 'y' } else { 'https://management.azure.com' }
$Probe = 'https://management.chinacloudapi.cn'
$Other = if ($A) { 'x' } else { 'https://management.azure.com' }
$ArmBaseUrl = if ($A) { 'x' } elseif ($B) { 'https://management.azure.com' } else { 'y' }
$ArmBaseUrl = if ($A) { 'https://management.azure.com' } else { 'y' }
$ArmBaseUrl = if ($A) { 'x' } else { 'https://management.chinacloudapi.cn' }
$ArmBaseUrl = 'https://management.azure.com'
$ArmBaseUrl = if ($A) { 'x' } else { Write-Output 'https://management.azure.com' }
$ArmBaseUrl = if ($A) { 'x' } else { "https://$Suffix.management.azure.com" }
$ArmBaseUrl = if ($A) { 'x' } else { 'y'; 'https://management.azure.com' }
$ArmBaseUrl = if ($A) { 'x' } else { 'https://management.azure.com' | Out-Null }
$ArmBaseUrl += if ($A) { 'x' } else { 'https://management.azure.com' }
'@
        & $ShowExempt (& $Run $Transport 'source/Private/Invoke-OPIMArmRequest.ps1') | Should -Be @(
            '1 management.azure.com True'
            '2 management.chinacloudapi.cn False'
            '3 management.azure.com False'
            '4 management.azure.com False'
            '5 management.azure.com False'
            '6 management.chinacloudapi.cn False'
            '7 management.azure.com False'
            '8 management.azure.com False'
            '9 management.azure.com False'
            '10 management.azure.com False'
            '11 management.azure.com False'
            '12 management.azure.com False'
        )
        # The fallback is exempt in the transport and nowhere else.
        @(& $Run $Transport 'source/Private/Fake.ps1' | Where-Object Exempt).Count | Should -Be 0 -Because 'the fallback exemption belongs to the transport file alone'

        # (d) A here-string is one node and reports its start line; each host it holds is one finding;
        # a host that ends another (graph.microsoft.us inside dod-graph.microsoft.us) is not reported
        # on top of it; a string with no cloud host, a module name and a documentation address yield
        # nothing.
        $Shapes = @(
            '$Cloud = @'''
            'GraphRoot: https://dod-graph.microsoft.us/v1.0'
            'Authority: https://login.chinacloudapi.cn/'
            '''@'
            '$Learn = ''https://learn.microsoft.com/graph'''
            '$Module = ''Microsoft.Graph.Authentication'''
            '$Message = "no cloud host here"'
        ) -join "`n"
        & $ShowHost (& $Run $Shapes 'source/Private/Fake.ps1') | Should -Be @(
            '1 dod-graph.microsoft.us'
            '1 login.chinacloudapi.cn'
        )
    }

    It 'parses every source file' {
        # A missing floor would compare with $null, which every count passes. The floor is the Az
        # boundary's: both passes read the same parsed files, so the counts must agree as well.
        $script:AzParsedFileFloor | Should -BeGreaterThan 0
        $script:ParseFailures | Should -BeNullOrEmpty
        $script:CloudHostParsedFileCount | Should -BeGreaterOrEqual $script:AzParsedFileFloor
        $script:CloudHostParsedFileCount | Should -Be $script:AzParsedFileCount -Because 'both passes read the files Pass 1 parsed, so a file one of them lost is a file the loop skipped'
    }

    It 'sees the ARM fallback of Invoke-OPIMArmRequest, the named control' {
        # The real-tree half of the positive control: a detector that stopped seeing the tree would
        # find no host at all, which is indistinguishable from a clean tree without this.
        $Transport = @($script:CloudHostFindings | Where-Object { $_.Path -ceq 'source/Private/Invoke-OPIMArmRequest.ps1' -and $_.Exempt })
        $Transport.Count | Should -Be 1 -Because 'the transport keeps exactly one documented public-cloud fallback literal'
        $Transport[0].Host | Should -BeExactly 'management.azure.com'

        $Table = @($script:CloudHostFindings | Where-Object { $_.Path -ceq 'source/Private/Get-OPIMCloudEndpoint.ps1' })
        @($Table | Where-Object { -not $_.Exempt }).Count | Should -Be 0 -Because 'every finding in the table is exempt'
        @($Table | Select-Object -ExpandProperty Host -Unique).Count | Should -Be 10 -Because (
            'the table names the ten distinct hosts of the four clouds; a detector that stopped seeing its string constants would find fewer')
    }

    It 'names no cloud host outside the table anywhere under source/' {
        $Violations = @($script:CloudHostFindings | Where-Object { -not $_.Exempt } | ForEach-Object {
                '{0}:{1} -- {2}' -f $_.Path, $_.Line, $_.Host
            })
        ($Violations -join '; ') | Should -BeNullOrEmpty -Because (
            'source/Private/Get-OPIMCloudEndpoint.ps1 is the single owner of every Graph, ARM and authority host of the four clouds (A11); ' +
            'a second copy can drift from the table and sends a request or a credential across the wrong cloud boundary on a sovereign tenant. ' +
            'Read the host from Get-OPIMCloudEndpoint instead. The only other exemption is the transport''s documented fallback literal, found by its shape')
    }
}
