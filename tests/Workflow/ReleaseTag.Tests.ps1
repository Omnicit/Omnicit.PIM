BeforeAll {
    $script:ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath '..'))).Path
    $script:ScriptPath = Join-Path -Path $script:ProjectPath -ChildPath (Join-Path -Path '.github' -ChildPath (Join-Path -Path 'scripts' -ChildPath 'ReleaseTag.ps1'))
    $script:WorkflowPath = Join-Path -Path $script:ProjectPath -ChildPath (Join-Path -Path '.github' -ChildPath (Join-Path -Path 'workflows' -ChildPath 'build-and-test.yml'))

    # =====================================================================================
    # THE TAG STEP'S DECISION, AND ITS WIRING.
    #
    # .github/scripts/ReleaseTag.ps1 is pure: it reads the facts the tag step gathered and answers
    # Create or Skip, or throws. These tests run it with made-up facts -- no gh, no git, no network
    # -- and read the workflow file statically for the half of the contract that lives in YAML:
    # the publish step's flag and the tag step's call. The publish job runs only after a merge, so
    # this file is the only place a pull request sees that code at all.
    # =====================================================================================

    # Commit ids made of one repeated digit: shaped like git's, naming nothing.
    $script:Sha = '1111111111111111111111111111111111111111'
    $script:OtherSha = '2222222222222222222222222222222222222222'
    $script:TagObject = '3333333333333333333333333333333333333333'

    function Invoke-ReleaseTag {
        <#
        .SYNOPSIS
        Runs ReleaseTag.ps1 with a main run's facts, changed by -Change.
        #>
        param([hashtable]$Change = @{})
        $Arguments = @{
            Version            = '0.6.1-preview0002'
            Sha                = $script:Sha
            Ref                = 'refs/heads/main'
            PublishedByThisJob = 'true'
            ReleaseExists      = $false
            RemoteTag          = @()
            Prerelease         = 'preview0002'
        }
        foreach ($Key in $Change.Keys) { $Arguments[$Key] = $Change[$Key] }
        & $script:ScriptPath @Arguments
    }

    function Get-ReleaseTagRefusal {
        <#
        .SYNOPSIS
        Returns the message ReleaseTag.ps1 refused with, or RETURNED when it did not refuse.
        #>
        param([hashtable]$Change = @{})
        try { $null = Invoke-ReleaseTag -Change $Change; 'RETURNED' } catch { $_.Exception.Message }
    }

    function Get-WorkflowStepRun {
        <#
        .SYNOPSIS
        Returns the run: block of the named workflow step, dedented, or $null.
        .DESCRIPTION
        The step starts at its '- name: <StepName>' line; its run: | block is every following line
        indented at least as far as the block's first line. Reads text only -- there is no YAML
        parser among the build's modules.
        #>
        param([string]$Text, [string]$StepName)
        $Lines = $Text -split '\r?\n'
        $Start = -1
        $Indent = ''
        for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
            if ($Lines[$Index] -match ('^(\s*)- name: ' + [regex]::Escape($StepName) + '\s*$')) {
                $Start = $Index
                $Indent = $Matches[1]
                break
            }
        }
        if ($Start -lt 0) { return $null }
        $Run = -1
        for ($Index = $Start + 1; $Index -lt $Lines.Count; $Index++) {
            $Line = $Lines[$Index]
            if ($Line.StartsWith($Indent + '- name: ') -or $Line -match '^\S') { break }
            if ($Line -match '^\s+run: \|\s*$') { $Run = $Index; break }
        }
        if ($Run -lt 0) { return $null }
        $Body = [System.Collections.Generic.List[string]]::new()
        $BodyIndent = -1
        for ($Index = $Run + 1; $Index -lt $Lines.Count; $Index++) {
            $Line = $Lines[$Index]
            if ($Line.Trim().Length -eq 0) { $Body.Add(''); continue }
            $Lead = $Line.Length - $Line.TrimStart().Length
            if ($BodyIndent -lt 0) { $BodyIndent = $Lead }
            if ($Lead -lt $BodyIndent) { break }
            $Body.Add($Line.Substring($BodyIndent))
        }
        ($Body -join "`n").TrimEnd()
    }
}

Describe 'ReleaseTag.ps1' {
    Context 'When this job published the version' {
        It 'creates the tag and the release on GITHUB_SHA when neither exists' {
            $Decision = Invoke-ReleaseTag
            $Decision.Action | Should -BeExactly 'Create'
            $Decision.Tag | Should -BeExactly 'v0.6.1-preview0002'
            $Decision.Target | Should -BeExactly $script:Sha
        }

        It 'creates the release on a tag run whose annotated tag names GITHUB_SHA' {
            $Decision = Invoke-ReleaseTag -Change @{
                Version    = '0.7.0'
                Ref        = 'refs/tags/v0.7.0'
                Prerelease = ''
                RemoteTag  = @("$($script:TagObject)`trefs/tags/v0.7.0", "$($script:Sha)`trefs/tags/v0.7.0^{}")
            }
            $Decision.Action | Should -BeExactly 'Create'
            $Decision.Target | Should -BeExactly $script:Sha
        }

        It 'creates the release when a lightweight tag already names GITHUB_SHA' {
            $Decision = Invoke-ReleaseTag -Change @{ RemoteTag = @("$($script:Sha)`trefs/tags/v0.6.1-preview0002") }
            $Decision.Action | Should -BeExactly 'Create'
            $Decision.Target | Should -BeExactly $script:Sha
        }

        It 'skips when the release already exists on GITHUB_SHA' {
            $Decision = Invoke-ReleaseTag -Change @{ ReleaseExists = $true; RemoteTag = @("$($script:Sha)`trefs/tags/v0.6.1-preview0002") }
            $Decision.Action | Should -BeExactly 'Skip'
            $Decision.Target | Should -BeNullOrEmpty
        }

        It 'refuses when the release already exists on another commit' {
            $Message = Get-ReleaseTagRefusal -Change @{ ReleaseExists = $true; RemoteTag = @("$($script:OtherSha)`trefs/tags/v0.6.1-preview0002") }
            $Message | Should -BeLike 'REFUSING TO TAG.*'
            $Message | Should -BeLike "*$($script:OtherSha)*"
            $Message | Should -BeLike "*$($script:Sha)*"
        }

        It 'refuses when the tag already names another commit' {
            $Message = Get-ReleaseTagRefusal -Change @{ RemoteTag = @("$($script:OtherSha)`trefs/tags/v0.6.1-preview0002") }
            $Message | Should -BeLike 'REFUSING TO TAG.*'
            $Message | Should -BeLike "*already names $($script:OtherSha)*"
        }

        It 'refuses to create a stable tag on a tag run whose tag is gone' {
            $Message = Get-ReleaseTagRefusal -Change @{ Version = '0.7.0'; Ref = 'refs/tags/v0.7.0'; Prerelease = ''; RemoteTag = @() }
            $Message | Should -BeLike 'REFUSING TO TAG.*'
            $Message | Should -BeLike '*never creates*'
        }
    }

    Context 'When the publish step skipped' {
        It 'skips when the release already exists' {
            $Decision = Invoke-ReleaseTag -Change @{ PublishedByThisJob = ''; ReleaseExists = $true; RemoteTag = @("$($script:OtherSha)`trefs/tags/v0.6.1-preview0002") }
            $Decision.Action | Should -BeExactly 'Skip'
        }

        It 'refuses, naming the version, the Gallery and the hand repair, when the release is missing' {
            $Message = Get-ReleaseTagRefusal -Change @{ PublishedByThisJob = '' }
            $Message | Should -BeLike 'REFUSING TO TAG.*'
            $Message | Should -BeLike '*Omnicit.PIM 0.6.1-preview0002 is already on the PowerShell Gallery*'
            $Message | Should -BeLike '*git tag v0.6.1-preview0002 *'
            $Message | Should -BeLike '*git push origin v0.6.1-preview0002*'
            $Message | Should -BeLike '*gh release create v0.6.1-preview0002 --verify-tag*--prerelease*'
            $Message | Should -BeLike "*$($script:Sha)*"
        }

        It 'refuses on a tag run whose release is missing, naming the tag''s commit and the release command' {
            $Message = Get-ReleaseTagRefusal -Change @{
                PublishedByThisJob = ''
                Version            = '0.7.0'
                Ref                = 'refs/tags/v0.7.0'
                Prerelease         = ''
                RemoteTag          = @("$($script:TagObject)`trefs/tags/v0.7.0", "$($script:Sha)`trefs/tags/v0.7.0^{}")
            }
            $Message | Should -BeLike 'REFUSING TO TAG.*'
            $Message | Should -BeLike "*already exists, on $($script:Sha)*"
            $Message | Should -BeLike '*gh release create v0.7.0 --verify-tag*'
            $Message | Should -Not -BeLike '*--prerelease*'
        }

        It 'counts only the exact value true as published (<Value>)' -TestCases @(
            @{ Value = '' }
            @{ Value = 'false' }
            @{ Value = 'True' }
            @{ Value = '1' }
            @{ Value = ' true' }
        ) {
            param($Value)
            Get-ReleaseTagRefusal -Change @{ PublishedByThisJob = $Value } | Should -BeLike 'REFUSING TO TAG.*'
        }

        It 'counts a missing PublishedByThisJob as not published' {
            $Message = try {
                $null = & $script:ScriptPath -Version '0.6.1-preview0002' -Sha $script:Sha -Ref 'refs/heads/main' -ReleaseExists $false -RemoteTag @() -Prerelease 'preview0002'
                'RETURNED'
            } catch { $_.Exception.Message }
            $Message | Should -BeLike 'REFUSING TO TAG.*'
        }
    }

    Context 'When git ls-remote answered something else' {
        It 'refuses a line for another ref' {
            $Message = Get-ReleaseTagRefusal -Change @{ RemoteTag = @("$($script:Sha)`trefs/tags/v0.6.1-preview00021") }
            $Message | Should -BeLike '*cannot be read*'
        }

        It 'refuses a line that is not a commit id and a ref' {
            Get-ReleaseTagRefusal -Change @{ RemoteTag = @('fatal: unable to access the remote') } | Should -BeLike '*cannot be read*'
        }

        It 'ignores blank lines' {
            (Invoke-ReleaseTag -Change @{ RemoteTag = @('', '   ') }).Action | Should -BeExactly 'Create'
        }
    }

    Context 'When its input is malformed' {
        It 'refuses a GITHUB_SHA that is not a full lower-case commit id' -TestCases @(
            @{ Value = 'abc123' }
            @{ Value = '1111111111111111111111111111111111111111'.ToUpper().Replace('1', 'A') }
        ) {
            param($Value)
            { Invoke-ReleaseTag -Change @{ Sha = $Value } } | Should -Throw
        }

        It 'refuses a version that is not a module version' {
            { Invoke-ReleaseTag -Change @{ Version = '0.6.1 preview' } } | Should -Throw
        }
    }

    Context 'When the workflow runs it' {
        BeforeAll {
            $script:WorkflowText = [System.IO.File]::ReadAllText($script:WorkflowPath)
            $script:PublishRun = Get-WorkflowStepRun -Text $script:WorkflowText -StepName 'Publish to the PowerShell Gallery'
            $script:TagRun = Get-WorkflowStepRun -Text $script:WorkflowText -StepName 'Tag the published commit and create the release'
        }

        It 'finds the publish step and the tag step' {
            $script:PublishRun | Should -Not -BeNullOrEmpty -Because 'a renamed step would hand every check below an empty text'
            $script:TagRun | Should -Not -BeNullOrEmpty -Because 'a renamed step would hand every check below an empty text'
        }

        It 'holds PowerShell that parses in both steps' {
            foreach ($Run in $script:PublishRun, $script:TagRun) {
                $Errors = $null
                $null = [System.Management.Automation.Language.Parser]::ParseInput($Run, [ref]$null, [ref]$Errors)
                @($Errors).Count | Should -Be 0 -Because ('the publish job runs only after a merge, so a syntax error here would first show after a publish: {0}' -f (@($Errors | ForEach-Object { $_.Message }) -join '; '))
            }
        }

        It 'writes PublishedByThisJob only after Publish-PSResource returns, and nowhere else' {
            [regex]::Matches($script:WorkflowText, 'PublishedByThisJob=').Count | Should -Be 1 -Because 'only the publish step may set the flag, once'
            $Write = $script:PublishRun.IndexOf("'PublishedByThisJob=true'")
            $Write | Should -BeGreaterThan $script:PublishRun.IndexOf('Publish-PSResource -Path')
            $script:PublishRun.IndexOf('Publish-PSResource -Path') | Should -BeGreaterThan $script:PublishRun.IndexOf('SKIPPING THE PUBLISH')
        }

        It 'hands the decision to ReleaseTag.ps1 with the job''s facts' {
            $script:TagRun | Should -Match '\./\.github/scripts/ReleaseTag\.ps1 '
            $script:TagRun | Should -Match '-Sha \$env:GITHUB_SHA'
            $script:TagRun | Should -Match '-Ref \$env:GITHUB_REF'
            $script:TagRun | Should -Match '-PublishedByThisJob \$env:PublishedByThisJob'
            $script:TagRun | Should -Match '-ReleaseExists \$ReleaseExists'
            $script:TagRun | Should -Match '-RemoteTag \$RemoteTag'
        }

        It 'returns on Skip before it creates anything' {
            # Single-quoted patterns: in a double-quoted one a `$ would reach the regex as an anchor.
            $Skip = [regex]::Match($script:TagRun, 'if \(\$Decision\.Action -ceq ''Skip''\) \{ return \}')
            $Skip.Success | Should -BeTrue
            $Skip.Index | Should -BeLessThan $script:TagRun.IndexOf('gh @Arguments')
        }

        It 'creates the release on the decision''s target, never on GITHUB_SHA directly' {
            $script:TagRun | Should -Match '''--target'', \$Decision\.Target'
            $script:TagRun | Should -Not -Match '''--target'', \$env:GITHUB_SHA'
        }
    }

    Context 'When PSScriptAnalyzer reads it' {
        It 'reports nothing' {
            $Findings = @(Invoke-ScriptAnalyzer -Path $script:ScriptPath)
            $Findings.Count | Should -Be 0 -Because (($Findings | ForEach-Object { '{0}:{1} {2}' -f $_.RuleName, $_.Line, $_.Message }) -join '; ')
        }
    }
}
