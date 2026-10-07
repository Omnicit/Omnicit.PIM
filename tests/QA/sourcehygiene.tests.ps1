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
    # source/Private, or an alias in the source manifest's AliasesToExport (Enable-OPIMMyRoles and
    # Disable-OPIMMyRoles are aliases, not files). The pattern is case-sensitive; the verb may
    # carry an inner capital (ConvertTo-OPIM...), and a family form with a trailing '*'
    # (Get-OPIM*) names no command and is not matched.
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
                $script:CmdletRefViolations.Add(('{0}:{1} -- references {2}, which is neither a function file under source/Public or source/Private nor an alias in AliasesToExport' -f
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
    # cmdlets, the two sign-ins and the silent ARM token check, and the four Az.Resources schedule
    # cmdlets, which are ARM requests whose failure records can carry the request.
    # =====================================================================================
    $script:TransportCommands = @(
        'Invoke-OPIMGraphRequest', 'Invoke-MgGraphRequest', 'Invoke-WebRequest', 'Invoke-RestMethod',
        'Connect-MgGraph', 'Connect-AzAccount', 'Get-AzAccessToken',
        'Get-AzRoleEligibilitySchedule', 'Get-AzRoleAssignmentScheduleInstance',
        'New-AzRoleAssignmentScheduleRequest', 'Get-AzRoleAssignmentScheduleRequest'
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
        transport-reaching file was made to scrub first: 20 transport-reaching files under source/
        holding 29 of the 50 catch clauses in source/. The named control,
        source/Private/Invoke-OPIMGraphRequest.ps1, is asserted with its EXACT count instead (7: the three in its nested
        Get-ClaimsFromException, the first attempt, the claims retry, the status read and the
        refresh retry), so a catch that stops being seen fails there with a clear cause instead of
        quietly shrinking a total.
    #>
    $script:ScrubTransportFileFloor = 18
    $script:ScrubCatchFloor = 27
    $script:ScrubControlPath = 'source/Private/Invoke-OPIMGraphRequest.ps1'
    $script:ScrubControlCatchCount = 7

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
    }

    It 'resolves every Verb-OPIM token in source/**/*.ps1 to a function file or an exported alias' {
        $script:CmdletRefTokenCount | Should -BeGreaterThan $script:CmdletRefTokenFloor -Because 'the scan must have found the references it checks; zero tokens would pass vacuously'
        $script:CmdletRefViolations -join "`n" | Should -BeNullOrEmpty -Because @'
a comment, a help block or a message naming a command that is neither a function file under
source/Public or source/Private nor an alias in AliasesToExport points a reader at a command that
fails when they run it. This is a TEXT scan over the whole file, not an AST walk, since a stale
reference lives in prose -- a comment token the parser never turns into a CommandAst. Fix the
reference; do not exempt a file from this scan
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
            'those files held 29 of the 50 catch clauses in source/ on 2026-10-07; a count at the floor or below has broken the catch enumeration, not found fewer catches')
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
