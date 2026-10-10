BeforeAll {
    $script:ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath '..'))).Path

    # =====================================================================================
    # SOURCE HYGIENE -- read statically, one pass over the authored tree.
    #
    # The gate reads files and parses text. It imports nothing and runs no module code.
    #
    # '*.txt' and '*.md' are deliberately NOT in the include list. The about topic
    # (source/en-US/about_Omnicit.PIM.help.txt) belongs to the about-topic check,
    # tests/QA/about.tests.ps1, which reads its bytes. If that coverage is ever removed, add
    # '*.txt' to this scan instead of leaving the file ungated.
    # source/Formats/README.md is a shipped note that no command shows. Every path below is
    # compared with '/' separators, so the gate holds on every operating system.
    #
    # The floors sit just under the counts measured on 2026-10-06: source/ held 42 authored files
    # of these extensions, tests/ 37 (this file included), and source/**/*.ps1 38 files carrying
    # 349 Verb-OPIM tokens. The tests/ floor leaves no slack, since tests/Unit/Classes holds a
    # single file. Raise a floor when the tree genuinely grows.
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
        The floors sit just under the counts measured on 2026-10-07, after every catch in a
        transport-reaching file was made to scrub first and the Connect-MgGraph hand-off in
        Initialize-OPIMAuth was wrapped: 20 transport-reaching files under source/ holding 30 of the
        52 catch clauses in source/. The named control,
        source/Private/Invoke-OPIMGraphRequest.ps1, is asserted with its EXACT count instead (9: the three in its nested
        Get-ClaimsFromException; the one in each of its nested Get-GraphResponseFact and
        Get-GraphRetryAfterHeaderValue, which read a failure's status and Retry-After in both
        forms the Graph SDK raises (OPIM-28); the first attempt, the claims retry and the refresh
        retry, all three in its nested Invoke-OPIMGraphSingle; and the paging catch of -All,
        OPIM-13), so a catch that stops being seen fails there with a clear cause instead of
        quietly shrinking a total.
    #>
    $script:ScrubTransportFileFloor = 18
    $script:ScrubCatchFloor = 28
    $script:ScrubControlPath = 'source/Private/Invoke-OPIMGraphRequest.ps1'
    $script:ScrubControlCatchCount = 9

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
        already parsed (each file is parsed once):
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
        export without -Az in its name (Resolve-Error, say), called bare. And so is the XML under
        source/: this pass reads .ps1, .psm1 and .psd1 only, while the Types and Format files hold
        script blocks (GetScriptBlock, ScriptBlock, ...) that run at property access and at
        formatting, where an Az command could sit unseen. Review must catch these shapes; this pass
        cannot.

        The positive controls are the known-answer It, which runs the detector over a text holding
        every refused shape, and the named control: the two Get-AzToken calls of
        source/Private/Initialize-OPIMAuth.ps1, which a matcher that stopped seeing the tree would
        no longer find.
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

    <#
        The floors sit just under the counts Pass 1 measured on 2026-10-09: 65 parsed files under
        source/ (.ps1, .psm1, .psd1) holding 759 CommandAst nodes. A scan below a floor has lost a
        directory or broken its walk, not found less code; raise a floor when the tree genuinely grows.
    #>
    $script:AzParsedFileFloor = 63
    $script:AzCommandAstFloor = 740
    $script:AzFindings = [System.Collections.Generic.List[object]]::new()
    $script:AzParsedFileCount = 0
    $script:AzCommandAstCount = 0

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
    # .ps1xml is excluded since it is XML, which the PowerShell parser would report as errors.
    # .psd1 parses cleanly as a hashtable literal.
    $script:SourceUnits = [System.Collections.Generic.List[object]]::new()
    $script:ParseFailures = [System.Collections.Generic.List[string]]::new()

    foreach ($File in $script:HygieneFiles) {
        if ($File.RelativePath -notlike 'source/*') { continue }
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
            the passes below need; the walk count is what costs time, not the bucketing.
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
        a name held in a variable is not missed; a public name does not, since the completer classes
        and the manifest name public cmdlets without being their callers. Comment-based help is a
        comment token and never an AST expression, so a name that appears only in help creates no
        edge.

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
            'source/ held 20 transport-reaching files on 2026-10-07; a scan at the floor or below has broken transport detection, not found fewer files. Found: {0}' -f ($script:ScrubTransportFiles -join ', '))
        $script:ScrubCatchCount | Should -BeGreaterThan $script:ScrubCatchFloor -Because (
            'those files held 30 of the 52 catch clauses in source/ on 2026-10-07; a count at the floor or below has broken the catch enumeration, not found fewer catches')
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

    It 'parses every source file and walks a meaningful number of command nodes' {
        # A missing floor would compare with $null, which every count passes.
        $script:AzParsedFileFloor | Should -BeGreaterThan 0
        $script:AzCommandAstFloor | Should -BeGreaterThan 0
        $script:ParseFailures | Should -BeNullOrEmpty
        $script:AzParsedFileCount | Should -BeGreaterOrEqual $script:AzParsedFileFloor
        $script:AzCommandAstCount | Should -BeGreaterOrEqual $script:AzCommandAstFloor
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
