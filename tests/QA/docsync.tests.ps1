BeforeAll {
    $script:ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath '..'))).Path

    # =====================================================================================
    # WHY THIS GATE EXISTS.
    #
    # README.md and the about topic say the same thing twice, for two audiences: the README for
    # someone looking at the repository, the about topic for someone at a prompt with the module
    # already installed. The about topic is held against the module by tests/QA/about.tests.ps1,
    # which checks that it names every exported cmdlet. A check of that kind matches anywhere in
    # the FILE, so a cmdlet mentioned once in a Quick Start snippet satisfies it while being absent
    # from the roster a reader actually reads. Nothing held the two documents against EACH OTHER.
    #
    # One binding, the roster. Every exported cmdlet is rostered in README's '## Available
    # Cmdlets' AND in the about topic's 'COMMAND COHORTS' -- in those SECTIONS, not merely somewhere
    # in the file -- and neither roster carries a name the other does not. README's '### Cohort (N)'
    # counts are held to the cmdlets each cohort actually lists, and sum to FunctionsToExport.
    # The about topic's cohorts carry no counts, so there is nothing there to drift.
    #
    # KNOWN NAMES. A Verb-OPIM token names a command, and a token is UNKNOWN when it is neither in
    # FunctionsToExport nor in AliasesToExport: Enable-OPIMMyRoles and Disable-OPIMMyRoles are
    # exported ALIASES with the Verb-OPIM shape, so prose may name them. Completeness and the
    # cohort counts are measured against FunctionsToExport ONLY -- an alias is never a roster
    # entry. The name pattern leaves out a family form written with a trailing asterisk
    # (Get-OPIM*), which names no command, and accepts an inner capital in the verb
    # (ConvertTo-OPIM...). Comparisons are ordinal: a name spelled in another case is a defect in
    # the document, not a match.
    #
    # WHAT THIS GATE DOES NOT DO, stated so it is not mistaken for more than it is: it does not bind
    # the prose around either structure. The two documents are written for their media and are NOT
    # held equal beyond the roster. A claim edited in one and not the other still passes here.
    # =====================================================================================

    $script:ReadmePath = Join-Path -Path $script:ProjectPath -ChildPath 'README.md'
    $script:AboutPath = Join-Path -Path $script:ProjectPath -ChildPath 'source' |
        Join-Path -ChildPath 'en-US' |
            Join-Path -ChildPath 'about_Omnicit.PIM.help.txt'
    $script:ManifestPath = Join-Path -Path $script:ProjectPath -ChildPath 'source' |
        Join-Path -ChildPath 'Omnicit.PIM.psd1'

    $script:ManifestData = Import-PowerShellDataFile -Path $script:ManifestPath
    $script:ExportedNames = @($script:ManifestData.FunctionsToExport)
    $script:KnownNames = @($script:ExportedNames) + @($script:ManifestData.AliasesToExport)
    $script:ReadmeLines = [System.IO.File]::ReadAllLines($script:ReadmePath)
    $script:AboutLines = [System.IO.File]::ReadAllLines($script:AboutPath)

    # The cmdlet-name shape used throughout both documents. Matching bare (the about topic writes
    # no backticks) and then filtering against the known names is deliberate: it is how a name that
    # is NOT exported gets noticed rather than silently skipped.
    $script:CmdletNamePattern = [regex]'\b[A-Z][A-Za-z]+-OPIM[A-Za-z]*\b(?!\*)'

    function Get-DocSyncRosterName {
        <#
        .SYNOPSIS
        Returns each distinct Verb-OPIM name in a text, compared case-sensitively.
        .DESCRIPTION
        Distinct by a case-sensitive comparison, which is what the -cin and -cnotin checks below
        use too: a name spelled in another case is a separate token, kept so the checks below can
        report it as unknown rather than fold it into the correctly spelled one.
        #>
        param([string]$Text)
        @($script:CmdletNamePattern.Matches($Text) | ForEach-Object { $_.Value } | Sort-Object -Unique -CaseSensitive)
    }

    function Get-DocSyncMarkdownSection {
        <#
            .SYNOPSIS
                Returns the lines of a Markdown section, heading excluded.

            .DESCRIPTION
                Ends at the next heading of the same level or shallower, so a '###' subsection
                inside a '##' section does not terminate it. Returns $null when the heading is
                absent, which every caller asserts on rather than treating as an empty section.
        #>
        [OutputType([string[]])]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [AllowEmptyString()]
            [string[]]$Line,

            [Parameter(Mandatory = $true)]
            [string]$Heading
        )

        $Level = ($Heading -split ' ')[0].Length
        $Start = -1

        for ($Index = 0; $Index -lt $Line.Count; $Index++) {
            if ($Line[$Index].Trim() -eq $Heading) {
                $Start = $Index + 1
                break
            }
        }

        if ($Start -lt 0) {
            return $null
        }

        $End = $Line.Count

        for ($Index = $Start; $Index -lt $Line.Count; $Index++) {
            if ($Line[$Index] -match ('^#{1,' + $Level + '} ')) {
                $End = $Index
                break
            }
        }

        if ($End -le $Start) {
            return @()
        }

        return $Line[$Start..($End - 1)]
    }

    function Get-DocSyncAboutSection {
        <#
            .SYNOPSIS
                Returns the lines of an about-topic section, heading excluded.

            .DESCRIPTION
                About topics have no markup: a section heading is an ALL-CAPS line at column zero.
                Returns $null when the heading is absent.
        #>
        [OutputType([string[]])]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [AllowEmptyString()]
            [string[]]$Line,

            [Parameter(Mandatory = $true)]
            [string]$Heading
        )

        $Start = -1

        for ($Index = 0; $Index -lt $Line.Count; $Index++) {
            if ($Line[$Index] -eq $Heading) {
                $Start = $Index + 1
                break
            }
        }

        if ($Start -lt 0) {
            return $null
        }

        $End = $Line.Count

        for ($Index = $Start; $Index -lt $Line.Count; $Index++) {
            if ($Line[$Index] -match '^[A-Z][A-Z ]+$') {
                $End = $Index
                break
            }
        }

        if ($End -le $Start) {
            return @()
        }

        return $Line[$Start..($End - 1)]
    }
}

Describe 'README and about topic stay in step' -Tags 'helpQuality' {

    BeforeAll {
        $script:ReadmeRoster = Get-DocSyncMarkdownSection -Line $script:ReadmeLines -Heading '## Available Cmdlets'
        $script:AboutRoster = Get-DocSyncAboutSection -Line $script:AboutLines -Heading 'COMMAND COHORTS'
    }

    It 'Should keep two names that differ only in case apart (known answer)' {
        $Names = @(Get-DocSyncRosterName -Text 'Get-OPIMDirectoryRole, Get-OPIMdirectoryRole and Get-OPIMDirectoryRole')
        $Names.Count | Should -Be 2 -Because 'a name spelled in another case is a separate token; folding it into the right spelling hides it from the unknown-name check'
        ($Names -ccontains 'Get-OPIMdirectoryRole') | Should -BeTrue
        ($Names -ccontains 'Get-OPIMDirectoryRole') | Should -BeTrue
    }

    It 'Should dedupe roster names only through Get-DocSyncRosterName (static)' {
        # The known answer above pins the helper, not its callers: a site reverted to an inline
        # Sort-Object -Unique would stay green on today's documents. This reads the file itself
        # with the parser (no module is imported) and holds both halves.
        $Tokens = $null
        $ParseErrors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$Tokens, [ref]$ParseErrors)
        $ParseErrors | Should -BeNullOrEmpty -Because 'this test file must parse; a parse error would leave the checks below measuring nothing'

        $Helpers = @($Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Get-DocSyncRosterName'
                }, $true))
        $Helpers.Count | Should -Be 1 -Because 'the file must define Get-DocSyncRosterName exactly once'
        $HelperStart = $Helpers[0].Extent.StartOffset
        $HelperEnd = $Helpers[0].Extent.EndOffset

        $Commands = @($Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.CommandAst] }, $true))

        $Sorts = @($Commands | Where-Object { $_.GetCommandName() -in 'Sort-Object', 'sort' })
        $Sorts.Count | Should -BeGreaterThan 0 -Because 'the helper itself sorts; zero Sort-Object commands means the parse found nothing and the check below is vacuous'
        $SortsOutside = @($Sorts | Where-Object { $_.Extent.StartOffset -lt $HelperStart -or $_.Extent.EndOffset -gt $HelperEnd })
        $SortsOutside | Should -BeNullOrEmpty -Because (
            'every Sort-Object in this file must sit inside Get-DocSyncRosterName, where it is case-sensitive; an inline dedup elsewhere folds a name spelled in another case into the right spelling. Found outside at offsets: {0}' -f
                (($SortsOutside | ForEach-Object { $_.Extent.StartOffset }) -join ', '))

        # The known answer above calls the helper too, with a literal text; counting it would let one
        # roster site go missing unnoticed. A site is a call that is fed a roster section.
        $Calls = @($Commands | Where-Object {
                $_.GetCommandName() -eq 'Get-DocSyncRosterName' -and
                ($_.Extent.StartOffset -lt $HelperStart -or $_.Extent.EndOffset -gt $HelperEnd) -and
                $_.Extent.Text -match 'script:(Readme|About)Roster\b'
            })
        $Calls.Count | Should -BeGreaterOrEqual 4 -Because 'the four roster sites (two rosters, two sets) must each call Get-DocSyncRosterName with a roster section; fewer means a site stopped using it'
    }

    It 'Should find the roster section in both documents' {
        # Every assertion below reads one of these two sections. A renamed heading would otherwise
        # hand them an empty collection, and a set comparison between two empty sets passes.
        $script:ReadmeRoster | Should -Not -BeNullOrEmpty -Because 'README.md must carry an "## Available Cmdlets" section; if it was renamed, every roster check below silently measures nothing'

        $script:AboutRoster | Should -Not -BeNullOrEmpty -Because 'the about topic must carry a "COMMAND COHORTS" section; if it was renamed, every roster check below silently measures nothing'

        $script:ExportedNames.Count |
            Should -BeGreaterThan 0 -Because 'FunctionsToExport must be readable; zero exported names would make every comparison below vacuous'
    }

    It 'Should roster every exported cmdlet in README''s Available Cmdlets section' {
        # A check that matches the whole file passes for a cmdlet mentioned only in a Quick Start
        # snippet, which is missing from the list a reader scrolls to. This check is scoped to the
        # section.
        $Rostered = @(Get-DocSyncRosterName -Text ($script:ReadmeRoster -join "`n"))

        $Rostered.Count | Should -BeGreaterThan 0 -Because 'the section must name cmdlets; zero means the section was found but parsed as empty'

        $Missing = @($script:ExportedNames | Where-Object { $_ -cnotin $Rostered })

        $Missing | Should -BeNullOrEmpty -Because (
            'every exported cmdlet must appear in README.md ## Available Cmdlets, not merely somewhere in the file; missing: {0}' -f ($Missing -join ', '))

        $Unknown = @($Rostered | Where-Object { $_ -cnotin $script:KnownNames })

        $Unknown | Should -BeNullOrEmpty -Because (
            'the README roster must name only exported cmdlets or exported aliases; unknown: {0}' -f ($Unknown -join ', '))
    }

    It 'Should roster every exported cmdlet in the about topic''s COMMAND COHORTS section' {
        $Rostered = @(Get-DocSyncRosterName -Text ($script:AboutRoster -join "`n"))

        $Rostered.Count | Should -BeGreaterThan 0 -Because 'the section must name cmdlets; zero means the section was found but parsed as empty'

        $Missing = @($script:ExportedNames | Where-Object { $_ -cnotin $Rostered })

        $Missing | Should -BeNullOrEmpty -Because (
            'every exported cmdlet must appear in the about topic COMMAND COHORTS section, not merely somewhere in the file; missing: {0}' -f ($Missing -join ', '))

        $Unknown = @($Rostered | Where-Object { $_ -cnotin $script:KnownNames })

        $Unknown | Should -BeNullOrEmpty -Because (
            'the about topic roster must name only exported cmdlets or exported aliases; unknown: {0}' -f ($Unknown -join ', '))
    }

    It 'Should roster the same cmdlets in both documents' {
        # The binding itself. The two checks above each compare a roster against
        # FunctionsToExport, so this one can only fail if a roster drifted in a way that also broke
        # one of them -- which is the point: it names the disagreement directly, so a reader sees
        # "these two documents differ" rather than two separate "missing from X" failures.
        $ReadmeSet = @(Get-DocSyncRosterName -Text ($script:ReadmeRoster -join "`n") | Where-Object { $_ -cin $script:ExportedNames })

        $AboutSet = @(Get-DocSyncRosterName -Text ($script:AboutRoster -join "`n") | Where-Object { $_ -cin $script:ExportedNames })

        $ReadmeSet.Count | Should -BeGreaterThan 0 -Because 'a comparison between two empty sets passes; the README roster must be non-empty for this check to mean anything'
        $AboutSet.Count | Should -BeGreaterThan 0 -Because 'a comparison between two empty sets passes; the about roster must be non-empty for this check to mean anything'

        $OnlyInReadme = @($ReadmeSet | Where-Object { $_ -cnotin $AboutSet })
        $OnlyInAbout = @($AboutSet | Where-Object { $_ -cnotin $ReadmeSet })

        ($OnlyInReadme + $OnlyInAbout) | Should -BeNullOrEmpty -Because (
            'README.md ## Available Cmdlets and the about topic COMMAND COHORTS must roster the same cmdlets. Only in README: {0}. Only in the about topic: {1}' -f
                $(if ($OnlyInReadme.Count) { $OnlyInReadme -join ', ' } else { '(none)' }),
            $(if ($OnlyInAbout.Count) { $OnlyInAbout -join ', ' } else { '(none)' }))
    }

    It 'Should declare a cohort size in README that matches the cohort''s contents' {
        <#
            Each '### Cohort (N)' in README carries a count, and nothing checked it. A cmdlet's
            HOME cohort is the first one that names it in backticks, in document order; a later
            mention is a cross-reference, not a second listing. That rule is what makes the counts
            checkable, and a cmdlet named in backticks under a cohort that is not its own would be
            counted there instead of in its own.
        #>
        $Text = $script:ReadmeRoster
        $Current = $null
        $Declared = [ordered]@{}
        $CohortMember = [ordered]@{}
        $Seen = @{}

        foreach ($Line in $Text) {
            if ($Line -match '^### (?<name>.+?)\s*\((?<count>\d+)\)\s*$') {
                $Current = $Matches['name']
                $Declared[$Current] = [int]$Matches['count']
                $CohortMember[$Current] = [System.Collections.Generic.List[string]]::new()
                continue
            }

            if ($null -eq $Current) {
                continue
            }

            foreach ($Match in ([regex]'`(?<name>[A-Z][A-Za-z]+-OPIM[A-Za-z]*)`').Matches($Line)) {
                $Name = $Match.Groups['name'].Value

                if ($Seen.ContainsKey($Name) -or $Name -cnotin $script:ExportedNames) {
                    continue
                }

                $Seen[$Name] = $Current
                $CohortMember[$Current].Add($Name)
            }
        }

        $Declared.Count | Should -BeGreaterThan 0 -Because 'README ## Available Cmdlets must carry "### Cohort (N)" subsections; zero means the heading shape changed and this check measured nothing'

        $Wrong = @(
            foreach ($Cohort in $Declared.Keys) {
                if ($CohortMember[$Cohort].Count -ne $Declared[$Cohort]) {
                    '{0} says ({1}) but rosters {2}' -f $Cohort, $Declared[$Cohort], $CohortMember[$Cohort].Count
                }
            }
        )

        $Wrong | Should -BeNullOrEmpty -Because (
            'every "### Cohort (N)" count in README.md must equal the number of cmdlets that cohort is the FIRST to name; {0}' -f ($Wrong -join '; '))

        $Unhomed = @($script:ExportedNames | Where-Object { -not $Seen.ContainsKey($_) })

        $Unhomed | Should -BeNullOrEmpty -Because (
            'every exported cmdlet must be listed in backticks under exactly one "### Cohort (N)" subsection; without a home it is in no cohort''s count: {0}' -f ($Unhomed -join ', '))

        $Total = ($Declared.Values | Measure-Object -Sum).Sum

        $Total | Should -Be $script:ExportedNames.Count -Because (
            'the cohort counts partition the exported set, so they must sum to FunctionsToExport ({0}); they sum to {1}' -f $script:ExportedNames.Count, $Total)
    }

    It 'Should use only the case-sensitive membership operators on roster variables (static)' {
        # Comparisons are ordinal (see the header): -in, -notin, -contains and -notcontains fold
        # case, so a roster check written with one would take Get-OPIMdirectoryRole for
        # Get-OPIMDirectoryRole and stay green on a misspelt document. This reads the file itself
        # with the parser (no module is imported) and holds every membership comparison whose
        # operand refers to one of the five roster variables below to the case-sensitive kinds.
        # It reads nothing else: not a hashtable lookup ($Seen.ContainsKey), not Compare-Object,
        # not -eq, and not a membership comparison on any other variable.
        $Tokens = $null
        $ParseErrors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$Tokens, [ref]$ParseErrors)
        $ParseErrors | Should -BeNullOrEmpty -Because 'this test file must parse; a parse error would leave the checks below measuring nothing'

        $RosterVariables = @('ExportedNames', 'KnownNames', 'Rostered', 'ReadmeSet', 'AboutSet')
        $SensitiveKinds = @('Cin', 'Cnotin', 'Ccontains', 'Cnotcontains')
        $InsensitiveKinds = @('In', 'Iin', 'NotIn', 'Inotin', 'Contains', 'Icontains', 'NotContains', 'Inotcontains')
        $MembershipKinds = $SensitiveKinds + $InsensitiveKinds

        $Comparisons = @($Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.BinaryExpressionAst] -and $Node.Operator.ToString() -cin $MembershipKinds
                }, $true) | Where-Object {
                    $Operands = @($_.Left, $_.Right)
                    $Roster = @($Operands | ForEach-Object {
                            $_.FindAll({
                                    param($Inner)
                                    $Inner -is [System.Management.Automation.Language.VariableExpressionAst] -and ($Inner.VariablePath.UserPath -split ':')[-1] -in $RosterVariables
                                }, $true)
                        })
                    $Roster.Count -gt 0
                })

        $Insensitive = @($Comparisons | Where-Object { $_.Operator.ToString() -cin $InsensitiveKinds } | ForEach-Object { $_.Extent.StartLineNumber })
        $Insensitive.Count | Should -Be 0 -Because ('a roster name spelled in another case is a defect in the document, so every -in, -notin, -contains or -notcontains on a roster variable must use its case-sensitive form (-cin, -cnotin, -ccontains, -cnotcontains); case-insensitive ones at lines: {0}' -f ($Insensitive -join ', '))

        $Sensitive = @($Comparisons | Where-Object { $_.Operator.ToString() -cin $SensitiveKinds })
        $Sensitive.Count | Should -BeGreaterOrEqual 9 -Because ('the roster checks held 9 case-sensitive membership comparisons on a roster variable on 2026-10-10; {0} means the scan lost them, and the check above then measures nothing' -f $Sensitive.Count)
    }
}
