#Requires -Version 7.2

<#
    .SYNOPSIS
        Decides whether the publish job creates its version's tag and release, skips, or stops red.

    .DESCRIPTION
        The last step of the publish job creates the v<version> tag and the GitHub release. The tag
        is what moves the next build's version -- GitVersion.yml runs mode: ContinuousDelivery,
        where the preview counter moves on a tag -- so a tag on the wrong commit changes what the
        next merge publishes. This script holds the whole decision so that it can be tested; the
        step only gathers the facts and acts on the answer.

        THE RULE: a tag or a release is created only on the commit whose build THIS job published.

        When the publish step found the version already on the Gallery and skipped, this job
        cannot tell which commit's build the Gallery holds. A later merge to main computes the
        same version while the tag is missing, and used to tag itself. So:
          - the release already exists: Skip;
          - the release is missing: REFUSE. The message names the version and the hand repair.
        A re-run of the publish job is such a job too: it finds the version on the Gallery.

        When this job did publish:
          - no tag yet, on main: Create, on -Sha;
          - the tag already names -Sha (a v<X.Y.Z> tag run, whose own tag started the run):
            Create, and gh attaches the release to that tag;
          - the release exists, or the tag names another commit: REFUSE, since the release would
            describe another commit than the published one;
          - a tag run whose tag is gone: REFUSE, since the workflow never creates a v<X.Y.Z> tag
            (the 'Stable Version' ruleset refuses GITHUB_TOKEN that).

        Returns one object -- Action ('Create' or 'Skip'), Tag, Target (-Sha for Create, $null for
        Skip) and Message, a line for the log. Every refusal is a terminating error whose message
        starts 'REFUSING TO TAG.' and names the version.

    .PARAMETER Version
        The version this job published or found published, as the built manifest composes it
        (PublishVersion), for example 0.6.1-preview0002 or 0.7.0.

    .PARAMETER Sha
        GITHUB_SHA, the commit this run built and tested. On a tag run it is the commit the tag
        names, not the tag object: the v0.6.0 run had head 7f0ce6a, its annotated tag 646f73d.

    .PARAMETER Ref
        GITHUB_REF. A ref under refs/tags/ is a tag run.

    .PARAMETER PublishedByThisJob
        The value the publish step writes to GITHUB_ENV after Publish-PSResource returns. Only the
        exact string 'true' counts; empty, missing or anything else means this job did not publish.

    .PARAMETER ReleaseExists
        Whether 'gh release view v<Version>' succeeded.

    .PARAMETER RemoteTag
        What 'git ls-remote origin refs/tags/v<Version> refs/tags/v<Version>^{}' printed: nothing
        for a missing tag, one line for a lightweight tag, two for an annotated one, whose ^{} line
        names the commit. Blank lines are ignored; any other line stops the decision.

    .PARAMETER Prerelease
        The built manifest's prerelease label, empty for a full release. It only shapes the hand
        repair command in a refusal.

    .EXAMPLE
        $Decision = ./.github/scripts/ReleaseTag.ps1 -Version $Version -Sha $env:GITHUB_SHA -Ref $env:GITHUB_REF -PublishedByThisJob $env:PublishedByThisJob -ReleaseExists $ReleaseExists -RemoteTag $RemoteTag -Prerelease $env:PublishPrerelease
#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+(-[0-9A-Za-z]+)?$')]
    [string]
    $Version,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{40}$', Options = 'None')]
    [string]
    $Sha,

    [Parameter(Mandatory = $true)]
    [string]
    $Ref,

    [Parameter()]
    [AllowNull()]
    [AllowEmptyString()]
    [string]
    $PublishedByThisJob,

    [Parameter(Mandatory = $true)]
    [bool]
    $ReleaseExists,

    [Parameter(Mandatory = $true)]
    [AllowNull()]
    [AllowEmptyCollection()]
    [AllowEmptyString()]
    [string[]]
    $RemoteTag,

    [Parameter()]
    [AllowNull()]
    [AllowEmptyString()]
    [string]
    $Prerelease
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ModuleName = 'Omnicit.PIM'
$Tag = "v$Version"
$IsTagRun = $Ref -clike 'refs/tags/*'
$Published = $PublishedByThisJob -ceq 'true'

# Where the tag points today. An annotated tag answers twice -- its own object, then the commit it
# names on the ^{} line -- and the commit wins. A line of any other shape is not guessed at.
$PlainCommit = ''
$PeeledCommit = ''
$LinePattern = '^([0-9a-f]{40})\trefs/tags/' + [regex]::Escape($Tag) + '(\^\{\})?$'
foreach ($Line in @($RemoteTag)) {
    if ([string]::IsNullOrWhiteSpace($Line)) { continue }
    $Answer = [regex]::Match($Line, $LinePattern)
    if (-not $Answer.Success) {
        throw "REFUSING TO TAG. git ls-remote answered '$Line' for $Tag, which is neither refs/tags/$Tag nor its peeled line, so where $Tag points cannot be read. Nothing was tagged. $ModuleName $Version may already be published, and if this job published it, a re-run cannot tag it: tag by hand -- see the comment on the tag step."
    }
    if ($Answer.Groups[2].Success) { $PeeledCommit = $Answer.Groups[1].Value } else { $PlainCommit = $Answer.Groups[1].Value }
}
$TagCommit = if ($PeeledCommit) { $PeeledCommit } else { $PlainCommit }

$Flag = if ([string]::IsNullOrEmpty($Prerelease)) { '' } else { ' --prerelease' }
$ReleaseCommand = "gh release create $Tag --verify-tag --title $Tag$Flag --notes-file <a file holding the Unreleased section of CHANGELOG.md at that commit>"
$PublishedCommit = "the commit of the workflow run whose publish job logged 'Publishing $ModuleName $Version' and, after the upload, 'Publish-PSResource returned without error'"
$Ruleset = "a v<X.Y.Z> tag only by the 'Stable Version' ruleset's bypass list"

if ($ReleaseExists) {
    if ($Published -and $TagCommit -cne $Sha) {
        $Where = if ($TagCommit) { "names $TagCommit" } else { 'names no commit' }
        throw "REFUSING TO TAG. This job published $ModuleName $Version from $Sha, but the release $Tag already exists and its tag $Where, so the release describes another commit than the one whose build the Gallery now holds. Nothing was created. Move $Tag and its release to $Sha by hand ($Ruleset); see Publishing in CLAUDE.md."
    }
    return [PSCustomObject]@{
        Action  = 'Skip'
        Tag     = $Tag
        Target  = $null
        Message = "SKIPPING: the release $Tag already exists. Nothing to create."
    }
}

if (-not $Published) {
    $Head = "REFUSING TO TAG. $ModuleName $Version is already on the PowerShell Gallery, but this job did not publish it: the publish step found it there and skipped. So this job cannot tell which commit's build the Gallery holds, the release $Tag does not exist, and nothing was tagged."
    if ($TagCommit) {
        throw "$Head The tag $Tag already exists, on $TagCommit, so only the release is missing. If $TagCommit is $PublishedCommit, create the release by hand: $ReleaseCommand. If it is not, move the tag to that commit first ($Ruleset)."
    }
    throw "$Head Until $Tag exists, every merge to main computes $Version again and publishes nothing. Tag by hand $PublishedCommit -- for a re-run of this job that is an earlier attempt of this run, on $Sha -- and create its release: git tag $Tag <that commit>; git push origin $Tag; $ReleaseCommand"
}

if ($TagCommit -and $TagCommit -cne $Sha) {
    throw "REFUSING TO TAG. This job published $ModuleName $Version from $Sha, but the tag $Tag already names $TagCommit, and gh would attach the release to that commit. Nothing was created. Move $Tag to $Sha by hand ($Ruleset), then create the release: $ReleaseCommand"
}

if (-not $TagCommit -and $IsTagRun) {
    throw "REFUSING TO TAG. This run was started by $Ref, but the tag $Tag no longer exists, and this workflow never creates a v<X.Y.Z> tag: the 'Stable Version' ruleset refuses it. $ModuleName $Version IS ALREADY PUBLISHED, from $Sha. Someone on the ruleset's bypass list pushes $Tag on $Sha again, then creates the release: $ReleaseCommand"
}

[PSCustomObject]@{
    Action  = 'Create'
    Tag     = $Tag
    Target  = $Sha
    Message = "This job published $ModuleName $Version from $Sha, so the release $Tag is created there."
}
