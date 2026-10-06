BeforeAll {
    $script:ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath '..'))).Path

    # =====================================================================================
    # SOURCE HYGIENE -- read statically, one pass over the authored tree.
    #
    # The gate reads files and parses text. It imports nothing and runs no module code.
    #
    # '*.txt' and '*.md' are deliberately NOT in the include list. The about topic
    # (source/en-US/about_Omnicit.PIM.help.txt) belongs to the about-topic check,
    # tests/QA/about.tests.ps1, added later on this branch, which reads its bytes. If that coverage
    # is ever removed, add '*.txt' to this scan instead of leaving the file ungated.
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
