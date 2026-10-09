BeforeDiscovery {
    $projectPath = "$($PSScriptRoot)\..\.." | Convert-Path

    <#
        If the QA tests are run outside of the build script (e.g with Invoke-Pester)
        the parent scope has not set the variable $ProjectName.
    #>
    if (-not $ProjectName)
    {
        # Assuming project folder name is project name.
        $ProjectName = Get-SamplerProjectName -BuildRoot $projectPath
    }

    $script:moduleName = $ProjectName

    Remove-Module -Name $script:moduleName -Force -ErrorAction SilentlyContinue

    $mut = Get-Module -Name $script:moduleName -ListAvailable |
        Select-Object -First 1 |
            Import-Module -Force -ErrorAction Stop -PassThru
}

BeforeAll {
    # Convert-Path required for PS7 or Join-Path fails
    $projectPath = "$($PSScriptRoot)\..\.." | Convert-Path
    # Get git-related project path. This is relevant for modules that will not be deployed in the root folder of Git.
    $gitTopLevelPath = (&git rev-parse --show-toplevel)
    $gitRelatedModulePath = (($projectPath -replace [regex]::Escape([IO.Path]::DirectorySeparatorChar), '/') -replace $gitTopLevelPath, '')
    if (-not [string]::IsNullOrEmpty($gitRelatedModulePath)) { $gitRelatedModulePath = $gitRelatedModulePath.Trim('/')  + '/' }
    $escapedGitRelatedModulePath = [regex]::Escape($gitRelatedModulePath)

    <#
        If the QA tests are run outside of the build script (e.g with Invoke-Pester)
        the parent scope has not set the variable $ProjectName.
    #>
    if (-not $ProjectName)
    {
        # Assuming project folder name is project name.
        $ProjectName = Get-SamplerProjectName -BuildRoot $projectPath
    }

    $script:moduleName = $ProjectName

    $sourcePath = (
        Get-ChildItem -Path $projectPath\*\*.psd1 |
            Where-Object -FilterScript {
                ($_.Directory.Name -match 'source|src' -or $_.Directory.Name -eq $_.BaseName) `
                    -and $(
                    try
                    {
                        Test-ModuleManifest -Path $_.FullName -ErrorAction Stop
                    }
                    catch
                    {
                        $false
                    }
                )
            }
    ).Directory.FullName

    <#
        The module under test, re-resolved for the RUN phase. The $mut set by the BeforeDiscovery
        at the top of this file lives in Pester's DISCOVERY session state; the two BeforeDiscovery
        blocks below can read it, but an It cannot. The release gates in this file need the built
        artefact at run time, so resolve it again here exactly the way discovery does --
        Get-Module -ListAvailable, first match -- which under ./build.ps1 -Tasks test is the BUILT
        module, i.e. ModuleBase output/module/<name>/<version>/ and Version the computed
        ModuleVersion.
    #>
    $script:moduleUnderTest = Get-Module -Name $script:moduleName -ListAvailable |
        Select-Object -First 1
}

Describe 'Changelog Management' -Tag 'Changelog' {
    # Evaluated at discovery, so both diff-based checks below skip on exactly the same condition.
    $gitWorkTreeUnavailable = -not ([bool](Get-Command git -ErrorAction SilentlyContinue) -and
        [bool](&(Get-Process -Id $PID).Path -NoProfile -Command 'git rev-parse --is-inside-work-tree 2>$null'))

    BeforeAll {
        <#
            The floor on the release-note BODY -- the section after its heading line, trimmed.
            About one sentence. It exists to catch a MECHANICAL failure, not a thin note: an
            emptied or hand-converted Unreleased section publishes ReleaseNotes of length 0 while
            the build reports success (measured in this repository on 2026-10-09 with Sampler
            0.120.1: the build succeeded and the built manifest's ReleaseNotes were empty). Whether
            the text is any good is decided in review, which no length floor can do: filler of any
            length passes one. See "## CHANGELOG and Version" in CLAUDE.md.
        #>
        $releaseNoteBodyMinimumLength = 50

        <#
            The whole of the Unreleased section between a stable release and the next change to
            the module, with {0} the latest stable version. See "## CHANGELOG and Version" in
            CLAUDE.md. Its opening clause is what makes it detectable: the claim "no changes to the
            module" is the part that turns false the moment source/ changes.
        #>
        $closeOutSentenceTemplate = 'No changes to the module since {0}. A preview published from this point differs from {0} only in documentation, tests or the build.'
        $closeOutOpeningClause = 'No changes to the module since'

        <#
            Get the list of changed files compared with branch main: the committed diff against
            origin/main plus everything staged or unstaged. One function, so every check that asks
            "did this PR change the module" reads the same diff.
        #>
        function Get-ChangedProjectFile
        {
            $filesChanged = @()
            # Only run if there is a remote called origin
            if (((git remote) -match 'origin'))
            {
                $headCommit = &git rev-parse HEAD
                $defaultBranchCommit = &git rev-parse origin/main
                $filesChanged += (&git @('diff', "$defaultBranchCommit...$headCommit", '--name-only') |
                    Where-Object { $_ -match "^$escapedGitRelatedModulePath" }) -replace "^$escapedGitRelatedModulePath", ""
            }

            $filesStagedAndUnstaged = (&git @('diff', 'HEAD', '--name-only') 2>&1 |
                Where-Object { $_ -match "^$escapedGitRelatedModulePath" }) -replace "^$escapedGitRelatedModulePath", ""

            $filesChanged += $filesStagedAndUnstaged

            $filesChanged
        }
    }

    It 'Changelog has been updated' -Skip:$gitWorkTreeUnavailable {
        $filesChanged = @(Get-ChangedProjectFile)

        <#
            Only require a changelog entry when the SHIPPED module changed. The paths above have
            already had the $gitRelatedModulePath prefix stripped and git reports them with forward
            slashes, so a source file is anything matching '^source/'. Per the "## CHANGELOG and
            Version" section of CLAUDE.md: the changelog is a customer-facing document, and forcing
            an entry out of a test-only, QA-only, docs-only or build-only PR fills it with noise
            that no reader of the published release notes can use.
        #>
        $sourceFilesChanged = @($filesChanged | Where-Object { $_ -match '^source/' })

        if ($sourceFilesChanged)
        {
            $filesChanged | Should -Contain 'CHANGELOG.md' -Because (
                'a PR that changes the shipped module documents itself in the CHANGELOG.md ' +
                '[Unreleased] section, while a test-only, QA-only, docs-only or build-only PR does ' +
                "not have to. Changed under source/: $($sourceFilesChanged -join ', ')."
            )
        }
    }

    It 'Changelog format compliant with keepachangelog format' -Skip:(![bool](Get-Command git -EA SilentlyContinue)) {
        { Get-ChangelogData -Path (Join-Path $ProjectPath 'CHANGELOG.md') -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Changelog should have an Unreleased header' {
            (Get-ChangelogData -Path (Join-Path -Path $ProjectPath -ChildPath 'CHANGELOG.md') -ErrorAction Stop).Unreleased | Should -Not -BeNullOrEmpty
    }

    It 'Changelog Unreleased section fits the published ReleaseNotes budget' {
        <#
            The Unreleased section IS the next release's notes: Sampler's
            Create_changelog_release_output task rewrites its heading to '## [<version>] - <date>'
            in output/CHANGELOG.md and copies that section's RawData into the built manifest's
            PrivateData.PSData.ReleaseNotes (Sampler 0.120.1,
            Changelog.changelogmanagement.build.ps1:108, 123-130, 176).

            Two-sided on purpose, against opposite failures. The ceiling catches the oversize
            section that Sampler would cut mid-sentence at 10,000 characters. The floor catches
            the reverse -- an emptied Unreleased section publishes an empty release note, and a
            bare ceiling check cannot see that, because a short length is less than any ceiling.
            Neither assertion is redundant and neither is inert.

            The floor measures the BODY, not RawData: an empty section still comes back as the
            17-character string '## [Unreleased]' plus two newlines, so a floor on RawData has to
            sit above the heading's own length before it can see the empty shape at all.
        #>
        $changelogPath = Join-Path -Path $ProjectPath -ChildPath 'CHANGELOG.md'
        $unreleased = (Get-ChangelogData -Path $changelogPath -ErrorAction Stop).Unreleased

        $unreleased.RawData | Should -Not -BeNullOrEmpty -Because 'a null Unreleased section would make the length check below read 0 and pass silently: $null.Length is the integer 0, not $null'

        $unreleasedLength = $unreleased.RawData.Length
        $headingLine, $body = $unreleased.RawData -split "`n", 2

        $headingLine | Should -BeExactly '## [Unreleased]' -Because (
            'the body floor below measures everything after the FIRST line of the section, so that ' +
            'line must be the Unreleased heading itself. If it is not, the split would measure the ' +
            'wrong text; this stops the check instead of letting it cut at the wrong line.'
        )

        $bodyLength = ([string]$body).Trim().Length

        $bodyLength | Should -BeGreaterOrEqual $releaseNoteBodyMinimumLength -Because (
            'the Unreleased section is published verbatim as the release notes on every merge to ' +
            'main, and an emptied or hand-converted section publishes ReleaseNotes of length 0 while ' +
            'the build reports success. The floor is there to catch that mechanical failure, not to ' +
            "judge the text: $releaseNoteBodyMinimumLength characters is about one sentence, and " +
            'the quality of the note is decided in review. With nothing new to say after a stable ' +
            'release, write the close-out sentence described in CLAUDE.md -- never filler. The body ' +
            "after the heading line is currently $bodyLength characters."
        )

        $unreleasedLength | Should -BeLessOrEqual 4000 -Because (
            '4,000 characters is the working budget for a release-note summary: enough for what ' +
            'changed and why, short enough that the PowerShell Gallery description stays readable. ' +
            "It is currently $unreleasedLength characters. Sampler's hard truncation at 10,000 " +
            '(Changelog.changelogmanagement.build.ps1:123-130) is the backstop that silently ' +
            'cuts the note mid-sentence, not the budget -- do not treat the gap between the two ' +
            'as headroom. ' +
            'Note the measurement here reads SHORT of the published article: RawData includes the ' +
            "15-character '## [Unreleased]' heading, while the published section carries the " +
            "longer '## [<version>] - <date>' form (29 characters for '## [0.5.2-chore] - " +
            "2026-10-05', so about 14 characters more, and more again for a longer version or " +
            'prerelease label). Per-PR detail does not belong here: close finished work under a ' +
            "dated '## [<version>] - <date>' section, or leave it in the PR body -- see CLAUDE.md " +
            '-- but never convert the Unreleased heading by hand: Sampler does that at build ' +
            'time, and a hand-converted section leaves Unreleased empty.'
        )
    }

    It 'Built manifest ReleaseNotes is populated and not truncated' {
        <#
            The two checks above measure the SOURCE side; this one measures what actually reached
            the shipped artefact, which is the only thing a Gallery consumer ever sees. It reads the
            BUILT manifest -- $moduleUnderTest.ModuleBase is output/module/<name>/<version>/ --
            because that is where Sampler's Update-Manifest writes PrivateData.PSData.ReleaseNotes
            (Changelog.changelogmanagement.build.ps1:176).

            Because it compares the built artefact against the current CHANGELOG.md, a stale
            output/module/ trips it too. That is deliberate: a stale build is exactly the state in
            which the source-side gates above are green while the published note is wrong. Rebuild
            with ./build.ps1 -Tasks build.
        #>
        $script:moduleUnderTest | Should -Not -BeNullOrEmpty -Because (
            "the module '$($script:moduleName)' must resolve from PSModulePath for the release " +
            'gates to have anything to measure; run ./build.ps1 -Tasks build first.'
        )

        $builtManifestPath = Join-Path -Path $script:moduleUnderTest.ModuleBase -ChildPath "$($script:moduleName).psd1"

        Test-Path -Path $builtManifestPath | Should -BeTrue -Because (
            "the manifest '$builtManifestPath' must exist; run ./build.ps1 -Tasks build first."
        )

        $builtManifest = Import-PowerShellDataFile -Path $builtManifestPath
        $psData = $builtManifest.PrivateData.PSData

        $psData | Should -Not -BeNullOrEmpty -Because (
            "'$builtManifestPath' has no PrivateData.PSData block, so it cannot be the built " +
            'manifest; run ./build.ps1 -Tasks build first.'
        )

        $psData.Keys | Should -Contain 'ReleaseNotes' -Because (
            "'$builtManifestPath' carries no PrivateData.PSData.ReleaseNotes key at all, so the " +
            'module under test is not a built module; run ./build.ps1 -Tasks build first.'
        )

        $releaseNotes = $psData.ReleaseNotes

        $releaseNotes | Should -Not -BeNullOrEmpty -Because (
            'an empty PrivateData.PSData.ReleaseNotes means Sampler Create_changelog_release_output ' +
            'found nothing to publish -- a release shipped with no notes at all, the same outcome ' +
            'as a published note that was cut short, reached from the opposite direction. The ' +
            "source manifest ships ReleaseNotes = '' as a placeholder and the build fills it in, so " +
            'an empty value here is a real build failure, never a reason to skip.'
        )

        $publishedHeadingLine, $publishedBody = $releaseNotes -split "`n", 2
        $publishedBodyLength = ([string]$publishedBody).Trim().Length

        $publishedBodyLength | Should -BeGreaterOrEqual $releaseNoteBodyMinimumLength -Because (
            'the published release notes must carry a body after their heading line, matching the ' +
            'floor the Unreleased section is held to above. An emptied or hand-converted section ' +
            'publishes a note with nothing in it while the build reports success. The body after ' +
            "the heading line is currently $publishedBodyLength characters. A stale artefact " +
            'reaches this assertion too, so if the current CHANGELOG.md Unreleased section is ' +
            'longer than that, run ./build.ps1 -Tasks build first and re-measure.'
        )

        $releaseNotes.Length | Should -BeLessThan 10000 -Because (
            'Sampler truncates with .Substring(0, 10000) ' +
            '(Changelog.changelogmanagement.build.ps1:123-130), so a length of exactly 10,000 is ' +
            'the signature of a note that was cut, not a note that happened to fit. They are ' +
            "currently $($releaseNotes.Length) characters."
        )

        <#
            Sampler's Create_changelog_release_output rewrites the heading with the version it
            reads back from the BUILT manifest -- ModuleVersion, plus '-' and the Prerelease label
            when there is one -- so the published heading must name exactly that version. The
            closing bracket is part of the expected prefix, so '0.5.2' cannot pass for
            '0.5.2-preview0001', nor the other way round.
        #>
        $builtVersion = [string]$builtManifest.ModuleVersion

        if ($psData.Prerelease)
        {
            $builtVersion = "$builtVersion-$($psData.Prerelease)"
        }

        $expectedHeadingPrefix = "## [$builtVersion]"

        $publishedHeadingLine | Should -MatchExactly ('^' + [regex]::Escape($expectedHeadingPrefix)) -Because (
            "the published heading must start with '$expectedHeadingPrefix', the version this " +
            'artefact was built as. Any other version means the heading was not rewritten for this ' +
            'build, so the note is published under another release. If the heading names an ' +
            'older build, output/module/ is stale: rebuild with ./build.ps1 -Tasks build.'
        )

        <#
            Length alone cannot see a cut that lands under 10,000 (a shorter cap, a different
            Sampler, a hand-edited manifest), nor a change in the middle of the note. So compare
            the WHOLE body after the heading line, published against source, exactly.
            Update-Changelog -LinkMode none rewrites only the heading line, and measured on
            2026-10-05 against a fresh build the two bodies were byte-identical -- 138 bytes each,
            LF line endings on both sides, the same two trailing newlines -- so nothing is
            normalized here. A comparison of the last 400 characters only would pass a character
            removed from the middle of the body.
        #>
        $sourceUnreleased = (Get-ChangelogData -Path (Join-Path -Path $ProjectPath -ChildPath 'CHANGELOG.md') -ErrorAction Stop).Unreleased.RawData

        $sourceUnreleased | Should -Not -BeNullOrEmpty -Because 'the body comparison below needs a source section to compare against'

        $sourceHeadingLine, $sourceBody = $sourceUnreleased -split "`n", 2

        $sourceHeadingLine | Should -BeExactly '## [Unreleased]' -Because (
            'the comparison below drops the FIRST line of each side as its heading, so the first ' +
            'line of the source section must be the Unreleased heading itself; this stops the check ' +
            'instead of letting it compare from the wrong line.'
        )

        [string]$publishedBody | Should -BeExactly ([string]$sourceBody) -Because (
            'the published release notes must be the CHANGELOG.md Unreleased section with only its ' +
            'heading line rewritten. Update-Changelog -LinkMode none changes nothing else, so any ' +
            'difference in the body is a note that was cut short -- the cut Sampler makes at ' +
            '10,000 characters -- or altered on the way to the manifest. If this fails and the ' +
            'note looks complete, output/module/ is stale: rebuild with ./build.ps1 -Tasks build.'
        )
    }

    It 'Changelog close-out sentence names the latest released version' {
        <#
            After a stable release, the close-out pull request leaves Unreleased holding exactly
            the close-out sentence for that release, and nothing else (CLAUDE.md, "## CHANGELOG and
            Version"). Every merge publishes a preview with Unreleased as its ReleaseNotes, so a
            sentence naming the wrong version tells a Gallery reader that the preview is based on
            a release it is not. Whitespace is collapsed before comparing, since the sentence is
            longer than one wrapped Markdown line.
        #>
        $changelogData = Get-ChangelogData -Path (Join-Path -Path $ProjectPath -ChildPath 'CHANGELOG.md') -ErrorAction Stop
        $unreleasedBody = ($changelogData.Unreleased.RawData -split "`n", 2)[1]
        $unreleasedText = (([string]$unreleasedBody) -replace '\s+', ' ').Trim()

        if ($unreleasedText.Contains($closeOutOpeningClause))
        {
            $latestReleased = @($changelogData.Released)[0]

            $latestReleased | Should -Not -BeNullOrEmpty -Because (
                'the Unreleased section carries the close-out sentence, which names the latest ' +
                'released version, but CHANGELOG.md has no dated release section for it to name.'
            )

            $expectedSentence = $closeOutSentenceTemplate -f $latestReleased.Version

            $unreleasedText | Should -BeExactly $expectedSentence -Because (
                'the Unreleased section carries the close-out sentence, so it must be exactly that ' +
                "sentence for the latest dated section in CHANGELOG.md, [$($latestReleased.Version)] " +
                "-- the section the close-out moved the last release's notes into. Any other " +
                'version, or any other text beside it, publishes a preview whose notes describe ' +
                'the wrong release.'
            )
        }
    }

    It 'Changelog close-out sentence is replaced by the first change to the module' -Skip:$gitWorkTreeUnavailable {
        <#
            The close-out sentence claims there are no changes to the module since the last stable
            release. The first pull request that changes source/ after a close-out makes that
            false, so it REPLACES the sentence with a note of its own; it never adds its note after
            it. Reads the same diff, and skips on the same condition, as 'Changelog has been
            updated' above.
        #>
        $sourceFilesChanged = @(Get-ChangedProjectFile | Where-Object { $_ -match '^source/' })

        if ($sourceFilesChanged)
        {
            $unreleasedRawData = (Get-ChangelogData -Path (Join-Path -Path $ProjectPath -ChildPath 'CHANGELOG.md') -ErrorAction Stop).Unreleased.RawData
            $unreleasedText = (([string]$unreleasedRawData) -replace '\s+', ' ').Trim()

            $unreleasedText.Contains($closeOutOpeningClause) | Should -BeFalse -Because (
                "this change touches source/ ($($sourceFilesChanged -join ', ')), but the " +
                "Unreleased section still says '$closeOutOpeningClause ...'. That is no longer " +
                'true, and every merge publishes it as the release notes. Replace the close-out ' +
                'sentence with a note describing this change; do not add the note after it.'
            )
        }
    }
}

<#
    The 'Changelog' tag is shared with the changelog Describe above ON PURPOSE. An ExcludeTag:
    Changelog added to build.yaml to quieten the changelog suite would silently take the version
    cap with it, and the gate would go green with nothing holding the cap at all. Keep the tags
    equal, or split them in the same change that adds an explicit run of both.
#>
Describe 'Release version cap' -Tags 'Changelog' {
    It 'Should build a version in the 0.x line, at or above 0.5.1' {
        <#
            Read from the module under test rather than by re-running GitVersion: what matters is
            the version that was actually stamped into the artefact, whatever produced it. Every
            merge to main publishes that version to the PowerShell Gallery, where it can never be
            deleted.
        #>
        $script:moduleUnderTest | Should -Not -BeNullOrEmpty -Because (
            "the module '$($script:moduleName)' must resolve from PSModulePath for this gate to " +
            'have a version to measure; run ./build.ps1 -Tasks build first.'
        )

        $builtVersion = $script:moduleUnderTest.Version

        <#
            Guard the guard. $null -lt [version]'1.0.0' evaluates to $true in PowerShell, so an
            unresolved version would sail through the upper bound below, and the gate would assert
            only half of what it claims.
        #>
        $builtVersion | Should -Not -BeNullOrEmpty -Because 'a null version would satisfy the -BeLessThan comparison below and make this gate inert'
        $builtVersion | Should -BeOfType [System.Version] -Because 'the comparisons below must be version comparisons, not string ones: as strings "10.0.0" sorts before "2.0.0"'

        $builtVersion | Should -BeGreaterOrEqual ([System.Version]'0.5.1') -Because (
            "the module built $builtVersion. The newest stable release is 0.5.1 and its v0.5.1 tag " +
            'is the base GitVersion counts from. A version below it means the version pipeline did ' +
            "not run or a tag is missing from the clone (a shallow clone has none). Fix the " +
            'pipeline; do not lower this bound to make a build pass.'
        )

        $builtVersion | Should -BeLessThan ([System.Version]'1.0.0') -Because (
            "the module built $builtVersion. A move to 1.0.0 is a release decision, not something a " +
            "commit message may make on its own: GitVersion.yml's major-version-bump-message is " +
            "live for the major token and for a conventional-commit breaking subject, and the " +
            "source manifest's placeholder ModuleVersion is 1.0.0, which a build without GitVersion " +
            'falls back to. When 1.0.0 is called, raise this bound in the same change -- never the ' +
            'assertion alone, and never merely to make a build pass.'
        )
    }
}

Describe 'General module control' -Tags 'FunctionalQuality' {
    It 'Should import without errors' {
        { Import-Module -Name $script:moduleName -Force -ErrorAction Stop } | Should -Not -Throw

        Get-Module -Name $script:moduleName | Should -Not -BeNullOrEmpty
    }

    It 'Should remove without error' {
        { Remove-Module -Name $script:moduleName -ErrorAction Stop } | Should -Not -Throw

        Get-Module $script:moduleName | Should -BeNullOrEmpty
    }
}

Describe 'Runtime dependencies' -Tags 'FunctionalQuality' {
    BeforeAll {
        # The BUILT manifest -- what the package and publish jobs validate and publish.
        $script:BuiltManifestPath = Join-Path -Path $script:moduleUnderTest.ModuleBase -ChildPath ('{0}.psd1' -f $script:moduleName)
        $script:BuiltManifest = Import-PowerShellDataFile -LiteralPath $script:BuiltManifestPath
        $script:RequiredModulesData = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $projectPath -ChildPath 'RequiredModules.psd1')
        $script:DeclaredNames = @($script:BuiltManifest.RequiredModules | ForEach-Object {
                if ($_ -is [System.Collections.IDictionary]) { $_.ModuleName } else { [string]$_ }
            } | Sort-Object)
    }

    It 'Should declare AzAuth and Microsoft.Graph.Authentication, and no Az module' {
        $script:DeclaredNames | Should -Be @('AzAuth', 'Microsoft.Graph.Authentication')
    }

    It 'Should hold every declared floor equal to the exact pin the tests ran against' {
        foreach ($Entry in $script:BuiltManifest.RequiredModules) {
            $Pin = [string]$script:RequiredModulesData[$Entry.ModuleName]
            $Pin | Should -Not -BeNullOrEmpty -Because ('RequiredModules.psd1 must pin {0}' -f $Entry.ModuleName)
            $Pin | Should -Not -Be 'latest' -Because ('a runtime dependency is pinned exactly, never latest: {0}' -f $Entry.ModuleName)
            [string]$Entry.ModuleVersion | Should -Be $Pin -Because ('the manifest floor of {0} must be the version the tests ran against' -f $Entry.ModuleName)
        }
    }

    It 'Should resolve no Az module for the build or the tests' {
        @($script:RequiredModulesData.Keys | Where-Object { $_ -match '^Az(\.|$)' }) | Should -BeNullOrEmpty
    }

    It 'Should install exactly the declared dependencies in the package and the publish job' {
        $Yaml = Get-Content -LiteralPath (Join-Path -Path $projectPath -ChildPath '.github/workflows/build-and-test.yml') -Raw
        $Loops = @([regex]::Matches($Yaml, 'foreach \(\$Name in ([^)]+)\)'))
        $Loops.Count | Should -Be 2 -Because 'the package and the publish job each install the runtime dependencies in one loop'
        foreach ($Loop in $Loops) {
            $Names = @([regex]::Matches($Loop.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
            $Names | Should -Be $script:DeclaredNames
        }
    }

    It 'Should load no Az module when the build is imported in a clean process' {
        # A clean pwsh with no profile imports the BUILT manifest by path, which loads its declared
        # dependencies from PSModulePath. Locally the profile holds the Az modules, so a dependency on
        # one loads it here; in CI none is installed, so a dependency on one fails the import. Either
        # way the test goes red.
        $Probe = Join-Path -Path $TestDrive -ChildPath 'Import-OPIMInCleanProcess.ps1'
        Set-Content -LiteralPath $Probe -Encoding utf8NoBOM -Value @'
param([Parameter(Mandatory)][string]$Manifest)
$ErrorActionPreference = 'Stop'
Import-Module -Name $Manifest -Force
[pscustomobject]@{
    Imported     = @(Get-Module -Name 'Omnicit.PIM').Count
    Dependencies = @(Get-Module -Name 'AzAuth', 'Microsoft.Graph.Authentication' | ForEach-Object { $_.Name } | Sort-Object -Unique)
    Az           = @(Get-Module -Name 'Az', 'Az.*' | ForEach-Object { $_.Name } | Sort-Object -Unique)
} | ConvertTo-Json -Compress
'@
        $Pwsh = (Get-Process -Id $PID).Path
        $Output = @(& $Pwsh -NoProfile -NonInteractive -File $Probe -Manifest $script:BuiltManifestPath 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ('the built module must import in a clean process: {0}' -f ($Output -join ' '))
        $Result = $Output[-1] | ConvertFrom-Json
        $Result.Imported | Should -Be 1
        @($Result.Dependencies) | Should -Be @('AzAuth', 'Microsoft.Graph.Authentication') -Because 'the import must load the declared dependencies, or an empty Az list proves nothing'
        @($Result.Az) | Should -BeNullOrEmpty -Because 'importing Omnicit.PIM must load no Az module'
    }

    It 'Should require at least PowerShell 7.4, and at least what every declared dependency requires' {
        $Own = [version]$script:BuiltManifest.PowerShellVersion
        $Own | Should -BeGreaterOrEqual ([version]'7.4') -Because 'AzAuth 2.9.0 requires PowerShell 7.4, and the floor of the module must name that requirement itself, so that an older PowerShell refuses the import with the requirement of Omnicit.PIM named'
        foreach ($Entry in $script:BuiltManifest.RequiredModules) {
            # -ListAvailable reads the manifest from disk and imports nothing.
            $Dependency = @(Get-Module -Name $Entry.ModuleName -ListAvailable | Where-Object { $_.Version -eq [version]$Entry.ModuleVersion })[0]
            $Dependency | Should -Not -BeNullOrEmpty -Because ('{0} {1} must be resolved for the build' -f $Entry.ModuleName, $Entry.ModuleVersion)
            if ($Dependency.PowerShellVersion) {
                $Own | Should -BeGreaterOrEqual $Dependency.PowerShellVersion -Because ('{0} {1} requires PowerShell {2}' -f $Entry.ModuleName, $Entry.ModuleVersion, $Dependency.PowerShellVersion)
            }
        }
    }
}

BeforeDiscovery {
    # Must use the imported module to build test cases.
    $allModuleFunctions = & $mut { Get-Command -Module $args[0] -CommandType Function } $script:moduleName

    # Build test cases.
    $testCases = @()

    foreach ($function in $allModuleFunctions)
    {
        $testCases += @{
            Name = $function.Name
        }
    }
}

Describe 'Quality for module' -Tags 'TestQuality' {
    BeforeDiscovery {
        if (Get-Command -Name Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)
        {
            $scriptAnalyzerRules = Get-ScriptAnalyzerRule
        }
        else
        {
            if ($ErrorActionPreference -ne 'Stop')
            {
                Write-Warning -Message 'ScriptAnalyzer not found!'
            }
            else
            {
                throw 'ScriptAnalyzer not found!'
            }
        }

        <#
            The [OutputType] gate below is scoped to the EXPORTED functions only. $testCases holds
            every function the module defines, private helpers included, which is right for the two
            checks that stay on it (a unit test file, a clean Script Analyzer run). CLAUDE.md asks
            for [OutputType] on "every function that returns type-tagged objects", and that rule is
            about the public surface: a private helper must not start failing this gate.

            The export list comes from $mut.ExportedFunctions, the module the first BeforeDiscovery
            in this file already imported, so it is the module system's own resolved export list and
            needs neither a second manifest read nor a source path. The set is case-insensitive, and
            $exportedTestCases is filtered out of $testCases so it can never drift from the set the
            two older checks run against.
        #>
        $exportedFunctionNames = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]$mut.ExportedFunctions.Keys, [System.StringComparer]::OrdinalIgnoreCase)
        $exportedTestCases = @($testCases | Where-Object { $exportedFunctionNames.Contains($_.Name) })
    }

    It 'Should have a unit test for <Name>' -ForEach $testCases {
        Get-ChildItem -Path 'tests\' -Recurse -Include "$Name.Tests.ps1" | Should -Not -BeNullOrEmpty
    }

    It 'Should pass Script Analyzer for <Name>' -ForEach $testCases -Skip:(-not $scriptAnalyzerRules) {
        $functionFile = Get-ChildItem -Path $sourcePath -Recurse -Include "$Name.ps1"

        $pssaResult = (Invoke-ScriptAnalyzer -Path $functionFile.FullName)
        $report = $pssaResult | Format-Table -AutoSize | Out-String -Width 110
        $pssaResult | Should -BeNullOrEmpty -Because `
            "some rule triggered.`r`n`r`n $report"
    }

    It 'Should discover every exported function for the [OutputType] gate' -ForEach @(@{ DiscoveredNames = @($exportedTestCases | ForEach-Object { $_.Name }) }) {
        <#
            The [OutputType] gate below runs one It per discovered case, and an empty -ForEach
            generates NO It. Whether that is an error depends on the Pester version and its
            Run.FailOnNullOrEmptyForEach setting (Pester 6.2.0, measured, fails the whole container
            with an unnamed error; a setting that allows it passes on nothing). This check holds the
            discovered set against the SOURCE manifest's explicit FunctionsToExport -- a read that
            does not go through the module under test -- so an empty or short set is a named red
            gate here whichever way that setting falls.
        #>
        $manifest = Import-PowerShellDataFile -Path (
            Join-Path -Path $sourcePath -ChildPath "$($script:moduleName).psd1")
        $expectedNames = @($manifest.FunctionsToExport)

        $expectedNames.Count | Should -BeGreaterThan 0 -Because 'the source manifest must list the exported functions; zero would make the comparison below vacuous'

        $missingNames = @($expectedNames | Where-Object { $DiscoveredNames -notcontains $_ })
        @($DiscoveredNames).Count | Should -Be $expectedNames.Count -Because (
            'the [OutputType] gate must run for every exported function; it discovered {0} of {1}. Not discovered: {2}' -f
            @($DiscoveredNames).Count, $expectedNames.Count, ($missingNames -join ', '))
    }

    It 'Should declare an [OutputType(...)] for <Name>' -ForEach $exportedTestCases {
        <#
            Every exported function must declare [OutputType(...)]: [PSCustomObject] for a cmdlet
            that returns type-tagged objects, [void] for one that emits nothing. The check reads
            the attribute from the PARAM BLOCK's own Attributes collection -- an [OutputType()]
            written before param(...) attaches there, not to the FunctionDefinitionAst -- so it
            does not care which line the attribute sits on, only that it is declared. The file
            lookup and parse are the ones the help checks below use.
        #>
        $functionFile = Get-ChildItem -Path $sourcePath -Recurse -Include "$Name.ps1"

        $scriptFileRawContent = Get-Content -Raw -Path $functionFile.FullName

        $abstractSyntaxTree = [System.Management.Automation.Language.Parser]::ParseInput($scriptFileRawContent, [ref] $null, [ref] $null)

        $astSearchDelegate = { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }

        $parsedFunction = $abstractSyntaxTree.FindAll( $astSearchDelegate, $true ) |
            Where-Object -FilterScript {
                $_.Name -eq $Name
            }

        $outputTypeAttribute = @($parsedFunction.Body.ParamBlock.Attributes) |
            Where-Object { $_.TypeName.Name -eq 'OutputType' }

        $outputTypeAttribute | Should -Not -BeNullOrEmpty -Because (
            "$Name must declare [OutputType([PSCustomObject])] for tagged output or [OutputType([void])] when it emits nothing, beside its [CmdletBinding(...)]")
    }
}

Describe 'Help for module' -Tags 'helpQuality' {
    It 'Should have .SYNOPSIS for <Name>' -ForEach $testCases {
        $functionFile = Get-ChildItem -Path $sourcePath -Recurse -Include "$Name.ps1"

        $scriptFileRawContent = Get-Content -Raw -Path $functionFile.FullName

        $abstractSyntaxTree = [System.Management.Automation.Language.Parser]::ParseInput($scriptFileRawContent, [ref] $null, [ref] $null)

        $astSearchDelegate = { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }

        $parsedFunction = $abstractSyntaxTree.FindAll( $astSearchDelegate, $true ) |
            Where-Object -FilterScript {
                $_.Name -eq $Name
            }

        $functionHelp = $parsedFunction.GetHelpContent()

        $functionHelp.Synopsis | Should -Not -BeNullOrEmpty
    }

    It 'Should have a .DESCRIPTION with length greater than 40 characters for <Name>' -ForEach $testCases {
        $functionFile = Get-ChildItem -Path $sourcePath -Recurse -Include "$Name.ps1"

        $scriptFileRawContent = Get-Content -Raw -Path $functionFile.FullName

        $abstractSyntaxTree = [System.Management.Automation.Language.Parser]::ParseInput($scriptFileRawContent, [ref] $null, [ref] $null)

        $astSearchDelegate = { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }

        $parsedFunction = $abstractSyntaxTree.FindAll($astSearchDelegate, $true) |
            Where-Object -FilterScript {
                $_.Name -eq $Name
            }

        $functionHelp = $parsedFunction.GetHelpContent()

        $functionHelp.Description.Length | Should -BeGreaterThan 40
    }

    It 'Should have at least one (1) example for <Name>' -ForEach $testCases {
        $functionFile = Get-ChildItem -Path $sourcePath -Recurse -Include "$Name.ps1"

        $scriptFileRawContent = Get-Content -Raw -Path $functionFile.FullName

        $abstractSyntaxTree = [System.Management.Automation.Language.Parser]::ParseInput($scriptFileRawContent, [ref] $null, [ref] $null)

        $astSearchDelegate = { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }

        $parsedFunction = $abstractSyntaxTree.FindAll( $astSearchDelegate, $true ) |
            Where-Object -FilterScript {
                $_.Name -eq $Name
            }

        $functionHelp = $parsedFunction.GetHelpContent()

        $functionHelp.Examples.Count | Should -BeGreaterThan 0
        $functionHelp.Examples[0] | Should -Match ([regex]::Escape($function.Name))
        $functionHelp.Examples[0].Length | Should -BeGreaterThan ($function.Name.Length + 10)

    }

    It 'Should have described all parameters for <Name>' -ForEach $testCases {
        $functionFile = Get-ChildItem -Path $sourcePath -Recurse -Include "$Name.ps1"

        $scriptFileRawContent = Get-Content -Raw -Path $functionFile.FullName

        $abstractSyntaxTree = [System.Management.Automation.Language.Parser]::ParseInput($scriptFileRawContent, [ref] $null, [ref] $null)

        $astSearchDelegate = { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }

        $parsedFunction = $abstractSyntaxTree.FindAll( $astSearchDelegate, $true ) |
            Where-Object -FilterScript {
                $_.Name -eq $Name
            }

        $functionHelp = $parsedFunction.GetHelpContent()

        $parameters = $parsedFunction.Body.ParamBlock.Parameters.Name.VariablePath.ForEach({ $_.ToString() })

        foreach ($parameter in $parameters)
        {
            $functionHelp.Parameters.($parameter.ToUpper()) | Should -Not -BeNullOrEmpty -Because ('the parameter {0} must have a description' -f $parameter)
            $functionHelp.Parameters.($parameter.ToUpper()).Length | Should -BeGreaterThan 25 -Because ('the parameter {0} must have descriptive description' -f $parameter)
        }
    }
}

Describe 'README documentation' -Tags 'helpQuality' {
    BeforeAll {
        $script:readmePath = Join-Path -Path $projectPath -ChildPath 'README.md'
        $script:readmeText = if (Test-Path -Path $script:readmePath)
        {
            Get-Content -Path $script:readmePath -Raw
        }
        else
        {
            ''
        }

        $manifest = Import-PowerShellDataFile -Path (
            Join-Path -Path $sourcePath -ChildPath "$($script:moduleName).psd1")
        $script:exportedNames = @($manifest.FunctionsToExport)

        <#
            The names README may use are the exported functions AND the exported aliases. Two of the
            aliases, Enable-OPIMMyRoles and Disable-OPIMMyRoles, have the same Verb-OPIMNoun shape
            as a cmdlet and README names them on purpose, so a check that knew only the functions
            would call them unknown. The other aliases (pim, unpim, Connect-PIM, ...) do not match
            the Verb-OPIM pattern and need no entry, but listing them all keeps the rule simple.
        #>
        $script:knownNames = $script:exportedNames + @($manifest.AliasesToExport)
    }

    It 'Should exist at the repository root' {
        Test-Path -Path $script:readmePath | Should -BeTrue
    }

    It 'Should document every exported cmdlet' {
        <#
            An exported cmdlet counts as documented when README names it as a whole word and not as
            a wildcard family form (Get-OPIM*), which names no command. The whole-word boundary
            also keeps the alias Enable-OPIMMyRoles from standing in for Enable-OPIMMyRole.
        #>
        $script:exportedNames | Should -Not -BeNullOrEmpty -Because 'the manifest must list FunctionsToExport for this check to measure anything'

        $missing = $script:exportedNames | Where-Object {
            $script:readmeText -notmatch ('(?m)\b{0}\b(?!\*)' -f [regex]::Escape($_))
        }

        $missing | Should -BeNullOrEmpty -Because (
            'README.md must name every cmdlet in FunctionsToExport; missing: {0}' -f ($missing -join ', '))
    }

    It 'Should not name a function that does not exist' {
        <#
            The pattern is a Verb-OPIMNoun token. The verb part is [A-Za-z]+ so a verb with an inner
            capital (ConvertTo-) is matched, and the negative lookahead skips a family form written
            with a trailing asterisk (Get-OPIM*, Enable-OPIM*), which names no single command.
        #>
        $named = [regex]::Matches($script:readmeText, '\b[A-Z][A-Za-z]+-OPIM[A-Za-z]*\b(?!\*)') |
            ForEach-Object { $_.Value } | Sort-Object -Unique
        $named | Should -Not -BeNullOrEmpty -Because 'README.md must name the module cmdlets'

        $unknown = $named | Where-Object { $_ -notin $script:knownNames }

        $unknown | Should -BeNullOrEmpty -Because (
            'every Verb-OPIM name in README.md must resolve to an exported function or alias; unknown: {0}' -f ($unknown -join ', '))
    }
}

