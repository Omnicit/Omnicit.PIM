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

    <#
        The four command cohorts the about topic is expected to orient a reader across. Each
        entry lists cmdlets that belong to that cohort; naming any ONE of them satisfies the
        cohort. Defined at discovery so Pester can expand one test case per cohort. The cohorts
        are the ones README.md's "Available Cmdlets" section counts, and tests/QA/docsync.tests.ps1
        holds the two documents to the same roster.
    #>
    $cohortCases = @(
        @{
            Cohort = 'Directory roles'
            Any    = @('Get-OPIMDirectoryRole', 'Enable-OPIMDirectoryRole', 'Disable-OPIMDirectoryRole',
                'Wait-OPIMDirectoryRole')
        }
        @{
            Cohort = 'Groups'
            Any    = @('Get-OPIMEntraIDGroup', 'Enable-OPIMEntraIDGroup', 'Disable-OPIMEntraIDGroup')
        }
        @{
            Cohort = 'Azure roles'
            Any    = @('Get-OPIMAzureRole', 'Enable-OPIMAzureRole', 'Disable-OPIMAzureRole')
        }
        @{
            Cohort = 'Sign-in and configuration'
            Any    = @('Connect-OPIM', 'Disconnect-OPIM', 'Install-OPIMConfiguration',
                'Get-OPIMConfiguration', 'Set-OPIMConfiguration', 'Remove-OPIMConfiguration',
                'Enable-OPIMMyRole', 'Disable-OPIMMyRole')
        }
    )
}

BeforeAll {
    # Convert-Path required for PS7 or Join-Path fails
    $projectPath = "$($PSScriptRoot)\..\.." | Convert-Path

    if (-not $ProjectName)
    {
        $ProjectName = Get-SamplerProjectName -BuildRoot $projectPath
    }

    $script:moduleName = $ProjectName
    $script:aboutFileName = 'about_{0}.help.txt' -f $script:moduleName

    $script:sourceAboutPath = Join-Path -Path $projectPath -ChildPath 'source' |
        Join-Path -ChildPath 'en-US' |
            Join-Path -ChildPath $script:aboutFileName

    $script:sourceManifestPath = Join-Path -Path $projectPath -ChildPath 'source' |
        Join-Path -ChildPath ('{0}.psd1' -f $script:moduleName)

    $script:manifestData = Import-PowerShellDataFile -Path $script:sourceManifestPath
    $script:exportedNames = $script:manifestData.FunctionsToExport

    <#
        A name the about topic may write without being a roster entry: an exported alias.
        Enable-OPIMMyRoles and Disable-OPIMMyRoles are aliases of the two MyRole cmdlets and have the
        Verb-OPIM shape, so the "names only exported cmdlets" check below must treat them as known.
        Known names are the exported functions plus the exported aliases.
    #>
    $script:knownNames = @($script:exportedNames) + @($script:manifestData.AliasesToExport)

    <#
        The shape of a command name in the topic: a capitalised verb (an inner capital is allowed,
        ConvertTo-OPIM...), the module prefix, and a noun, ending at a word boundary that is not
        followed by an asterisk. A family form written with a trailing asterisk (Get-OPIM*) names
        no command, so the lookahead leaves it out.
    #>
    $script:cmdletNamePattern = '\b[A-Z][A-Za-z]+-OPIM[A-Za-z]*\b(?!\*)'

    <#
        Read the raw bytes rather than Get-Content so the BOM and any non-ASCII byte are
        observable. Authored files in this module are UTF-8 without BOM and ASCII-only, which
        means a BOM-less file with a high byte fails the PSUseBOMForUnicodeEncodedFile gate.
    #>
    $script:aboutBytes = [System.IO.File]::ReadAllBytes($script:sourceAboutPath)
    $script:aboutText = [System.Text.Encoding]::UTF8.GetString($script:aboutBytes)
}

Describe 'About topic' -Tags 'helpQuality' {
    It 'Should exist in the source tree' {
        Test-Path -Path $script:sourceAboutPath | Should -BeTrue -Because 'the about topic is the in-box overview'
    }

    It 'Should ship in the built module' {
        $builtModule = Get-Module -Name $script:moduleName -ListAvailable | Select-Object -First 1
        $builtModule | Should -Not -BeNullOrEmpty -Because 'the built module must be discoverable'

        $builtAbout = Join-Path -Path (Split-Path -Path $builtModule.Path -Parent) -ChildPath 'en-US' |
            Join-Path -ChildPath $script:aboutFileName

        Test-Path -Path $builtAbout | Should -BeTrue -Because 'build.yaml CopyPaths must copy en-US into the built module'
    }

    It 'Should ship the same bytes that the source tree holds' {
        <#
            Every content assertion below reads the SOURCE file, but the copy a consumer reads
            through Get-Help about_Omnicit.PIM is the built one. Without this check a stale
            built copy -- an edit without a rebuild, or a CopyPaths regression -- passes them all.
        #>
        $builtModule = Get-Module -Name $script:moduleName -ListAvailable | Select-Object -First 1
        $builtAbout = Join-Path -Path (Split-Path -Path $builtModule.Path -Parent) -ChildPath 'en-US' |
            Join-Path -ChildPath $script:aboutFileName

        (Get-FileHash -Path $builtAbout).Hash |
            Should -Be (Get-FileHash -Path $script:sourceAboutPath).Hash -Because (
                'the built about topic must match source; run ./build.ps1 -Tasks build after editing it')
    }

    It 'Should be UTF-8 without a BOM' {
        $script:aboutBytes.Length | Should -BeGreaterThan 0

        $hasBom = $script:aboutBytes.Length -ge 3 -and
            $script:aboutBytes[0] -eq 0xEF -and
            $script:aboutBytes[1] -eq 0xBB -and
            $script:aboutBytes[2] -eq 0xBF

        $hasBom | Should -BeFalse -Because 'authored files in this module are UTF-8 without BOM'
    }

    It 'Should contain only ASCII characters' {
        $nonAscii = @($script:aboutBytes | Where-Object { $_ -gt 0x7F })

        $nonAscii.Count | Should -Be 0 -Because 'a BOM-less file must be ASCII-only; use -- rather than an em-dash'
    }

    It 'Should name only cmdlets that are exported' {
        $named = [regex]::Matches($script:aboutText, $script:cmdletNamePattern) |
            ForEach-Object { $_.Value } |
                Sort-Object -Unique

        $named | Should -Not -BeNullOrEmpty -Because 'the about topic must name the module cmdlets'

        $unknown = @($named | Where-Object { $_ -notin $script:knownNames })

        $unknown | Should -BeNullOrEmpty -Because (
            'every Verb-OPIM name in the about topic must be an exported cmdlet or an exported alias; unknown: {0}' -f ($unknown -join ', '))
    }

    It 'Should name every exported cmdlet' {
        $missing = @($script:exportedNames | Where-Object {
                $script:aboutText -notmatch ('\b{0}\b' -f [regex]::Escape($_))
            })

        $missing | Should -BeNullOrEmpty -Because (
            'the COMMAND COHORTS section is generated from FunctionsToExport; missing: {0}' -f ($missing -join ', '))
    }

    It 'Should name at least one cmdlet from the <Cohort> cohort' -ForEach $cohortCases {
        $found = @($Any | Where-Object { $script:aboutText -match ('\b{0}\b' -f [regex]::Escape($_)) })

        $found | Should -Not -BeNullOrEmpty -Because (
            'the about topic is the in-box orientation and must cover the {0} cohort' -f $Cohort)
    }
}
