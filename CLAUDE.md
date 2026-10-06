# Omnicit.PIM - CLAUDE.md

Working rules for this repo. This file carries the **rules** -- the branch policy, how the module is
built, tested and published, the CHANGELOG and version model, the authentication architecture, and
the code, error-handling, test and security conventions -- and it is their single owner. The
Copilot files under `.github/` point here instead of restating them.

Do not restate project status, roster or release history here: `README.md` owns the cmdlet list,
`CHANGELOG.md` owns release history, and the GitHub issue tracker owns open work.

---

## Branch Policy -- ALWAYS CHECK FIRST

**`main` is protected on GitHub and a direct push to it is REJECTED BY THE SERVER.** That is
deliberate. It is not a lock to be worked around, and "continue on the current branch" is not an
option a user can consent to on `main` -- consent does not move a server-side rule. Every change
reaches `main` through a pull request.

**Before making any code change, Claude must:**

1. Determine the current branch (`git branch --show-current`).
2. If the current branch is `main`, create a feature branch before touching any files:
   `git checkout -b <branch-name>`, named from the table below. Propose the name and say what it is
   for; do not stop and wait for permission to leave `main`, since staying there cannot produce a
   push.
3. If the current branch is some OTHER shared branch, stop and ask the user which branch to use --
   there the old rule still holds, because the push would succeed.
4. Open a pull request against `main` when the work is ready. Never merge it without being asked to.

**Merge requirements, enforced by GitHub on `main`:**

- **Four status checks are required: `ubuntu-latest`, `windows-latest`, `macos-latest` and
  `package`.** The first three names come from the build-and-test matrix's
  `name: ${{ matrix.os }}` and the fourth from the `package` job's `name: package`, so the job name
  IS the required check name -- renaming a job, or changing the matrix, orphans the protection rule
  and blocks every open PR until the rule is renamed to match. Change both together.
- **The branch must be up to date with `main` before it can merge.** A branch that has fallen
  behind is rebased onto `main` and force-pushed; the checks then re-run against the rebased tip.
- **Linear history is required**, so a merge commit is refused. Squash merge is the convention here.
- **Every conversation on the PR must be resolved** before merge.

**Branch naming convention:**

| Change type | Prefix | Example |
|---|---|---|
| Bug fix | `fix/` | `fix/acrs-bearer-token-leak` |
| New feature | `feat/` | `feat/enable-myrole-parallel` |
| Tests / QA | `test/` | `test/fix-completer-mocks` |
| Documentation | `docs/` | `docs/claude-md-rules` |
| Chore | `chore/` | `chore/update-readme` |
| Refactor | `refactor/` | `refactor/simplify-error-handling` |
| Build / CI pipeline | `ci/` | `ci/publish-on-merge` |

The prefix is not cosmetic: `GitVersion.yml` reads it. A `feat/` (or `feature/`) branch builds a
Minor increment and a `fix/` (or `hotfix/`) branch a Patch increment on the branch itself; every
other prefix in the table matches no branch configuration and falls back to the defaults. No branch
publishes anything -- only `main` and a version tag do. See **CHANGELOG and Version**.

---

## Project Overview

`Omnicit.PIM` is a PowerShell 7.2+ module, Core-only (`CompatiblePSEditions = @('Core')`), for
Privileged Identity Management SELF-activation: the signed-in user lists, activates and deactivates
their own eligible assignments in three pillars:

- **Directory roles** -- Microsoft Entra ID roles, through Microsoft Graph.
- **Azure resource roles** -- Azure RBAC roles, through `Az.Resources`.
- **PIM for Groups** -- Entra ID group membership and ownership, through Microsoft Graph.

The command prefix is `OPIM` (`Get-OPIMDirectoryRole`, `Enable-OPIMAzureRole`, ...). Short aliases
are declared on the functions themselves: `pim` and `unpim` for `Enable-OPIMMyRole` and
`Disable-OPIMMyRole`, and the `*-PIM*` family (`Get-PIMRole`, `Enable-PIMADRole`, `Connect-PIM`,
...).

The module began as JAz.PIM by Justin Grote (@justinwgrote) and is overhauled and maintained by
Omnicit. It is MIT licensed and **published on the public PowerShell Gallery**: the newest stable
release is 0.5.1 (2026-05-29), and every merge to `main` publishes a preview -- see **Publishing**.

**The canonical working tree is the clone whose `origin` is `github.com/Omnicit/Omnicit.PIM`**,
wherever it sits on disk. The local path differs from machine to machine, so identify it with
`git remote get-url origin`, never by its directory, and do not treat a change made in any other
copy as made.

---

## Module Layout

```
source/
  Omnicit.PIM.psd1            # Manifest -- source of truth for exports, aliases, RequiredModules
  Omnicit.PIM.psm1            # Dev-mode loader ONLY (Classes -> Private -> Public). ModuleBuilder
                              #   replaces it at build time; see Common Pitfalls.
  suffix.ps1                  # Appended to the built psm1: the Update-TypeData -AppendPath call
                              #   for the Types.ps1xml file, mirrored in the dev-mode psm1
  Classes/                    # Six IArgumentCompleter classes (tab completion), loaded FIRST
  Private/                    # Internal helpers, one function per file
  Public/                     # Exported cmdlets, one per file, filename == function name
  Formats/                    # Omnicit.PIM.Format.ps1xml (FormatsToProcess) and
                              #   Omnicit.PIM.Types.ps1xml (loaded by suffix.ps1), plus a README.md
  en-US/                      # about_Omnicit.PIM.help.txt
tests/
  QA/module.tests.ps1         # The QA gate (below), run by ./build.ps1 -Tasks test
  Unit/Classes/               # ArgumentCompleters.Tests.ps1 -- all six completer classes
  Unit/Private/, Unit/Public/ # One *.Tests.ps1 per source file
build.yaml, build.ps1         # Sampler/ModuleBuilder config and bootstrap entry point
RequiredModules.psd1          # Build-time dependency resolver -- see Dependencies
GitVersion.yml                # Version computation -- see CHANGELOG and Version
.github/workflows/build-and-test.yml  # Build + Test on Linux, Windows, macOS, then package and
                              #   publish. The ONLY path that publishes -- see Publishing.
.github/scripts/PublishArtefact.ps1   # -Record / -Verify: proves the published bytes are the
                              #   tested bytes. Single owner of both halves; do not split it.
```

**The load order is Classes -> Private -> Public, and it is intentional.** The dev-mode psm1
dot-sources the three folders in that order (`source/Omnicit.PIM.psm1:19-32`), and ModuleBuilder
merges them into the built psm1 in the same order and then appends `suffix.ps1`. The completer
classes come first; the public cmdlets name them in their `[ArgumentCompleter()]` attributes.

**The build-and-test job's `if:` condition is wired to the merge gate -- do not read it as a
billing guard alone, and do not reason about it from GitHub's general rule for skipped jobs.** The
job is declared
`if: ${{ !github.event.repository.private || github.event_name == 'workflow_dispatch' }}`, because
standard runners are free and unmetered only on a PUBLIC repository. `ubuntu-latest`,
`windows-latest` and `macos-latest` are three of the four REQUIRED checks on `main`, and that
condition decides whether those three checks ever come into existence. The fourth, `package`, needs
`build-and-test`, so it does not run without them either.

**The mechanism is the MATRIX, not the skip.** GitHub documents the opposite of what happens here:
a job skipped by a condition reports Success and does NOT block a pull request ("Troubleshooting
required status checks"). That rule does not rescue this workflow, because `build-and-test` is a
matrix job and a job-level `if:` is evaluated BEFORE the matrix expands. The three legs are
therefore never created, so nothing ever reports the three check names -- and a required check that
never reports stays pending forever instead of passing (GitHub community discussion #9141). Make
this repository private and every pull request blocks permanently, including the pull request that
would fix it. Turning the repository private is therefore a change to this condition, or to the
protection rule, made in the SAME change and never afterwards.

**Rewriting this workflow as three separate jobs without a matrix INVERTS the failure, into the
worse one.** Without a matrix there is nothing to expand: the job-level `if:` would then skip three
jobs that do exist, each would report Success under the documented rule, and three of the four
required checks would go GREEN having run not one test. The matrix is what makes a skip fail loudly
here, so keep it -- or, if the jobs are ever split, make the required checks something a skipped
job cannot satisfy.

**Do not maintain a function roster in this file.** Read it from the tree instead:

```powershell
Get-ChildItem source/Public  -Filter '*.ps1' | Select-Object -ExpandProperty BaseName | Sort-Object
Get-ChildItem source/Private -Filter '*.ps1' | Select-Object -ExpandProperty BaseName | Sort-Object
Get-ChildItem source/Classes -Filter '*.ps1' | Select-Object -ExpandProperty BaseName | Sort-Object
```

`README.md` documents the cmdlets for their users. The authoritative export lists are
`FunctionsToExport` and `AliasesToExport` in `source/Omnicit.PIM.psd1`.

**The QA gate today is ONE file, `tests/QA/module.tests.ps1`**, run with everything else by
`./build.ps1 -Tasks test`. It holds:

- the changelog gates and the release version cap, which read `CHANGELOG.md`, the git diff against
  `origin/main` and the BUILT manifest (see **CHANGELOG and Version**);
- module import and removal;
- for every function the module defines -- public and private alike, since the cases are enumerated
  from inside the module with `Get-Command -CommandType Function` (30 on 2026-10-05) -- a unit test
  file under `tests/`, a clean `Invoke-ScriptAnalyzer` run on its source file, and help quality:
  `.SYNOPSIS`, a `.DESCRIPTION` over 40 characters, at least one `.EXAMPLE`, every parameter
  described.

The further gates Omnicit.EntraRBAC runs are **planned, not yet in this repository**: test hygiene
with a transport tripwire, documentation hygiene, source hygiene (ASCII and BOM among it), an about
topic check, and a README/about-topic sync. Nothing here enforces those rules yet; where this file
states one of them, review is what holds it until the gate lands.

---

## Build and Test Commands

```powershell
# Bootstrap build dependencies (first time or after a clean clone)
./build.ps1 -ResolveDependency -Tasks noop

# If the PSResourceGet bootstrap fails (for example with "Requested value 'V2' was not found"),
# use the ModuleFast resolver instead:
./build.ps1 -ResolveDependency -Tasks noop -UseModuleFast

# Build the module (output lands in output/module/Omnicit.PIM/<ver>/)
./build.ps1 -Tasks build

# Full test suite -- the authoritative gate, and the command every CI leg runs.
# QA tests + unit tests + per-function PSScriptAnalyzer + 80% code coverage enforcement
# (measured 2026-10-05: 703 passed, 0 failed, 1 skipped; coverage 83.7% over 1,699 analysed
#  commands; Pester 6.2.0)
./build.ps1 -Tasks test

# Import from source for quick local development
# (needs Az.Resources and Microsoft.Graph.Authentication on PSModulePath;
#  prepend output/RequiredModules if needed)
Import-Module ./source/Omnicit.PIM.psd1 -Force

# Import the built module
Import-Module ./output/module/Omnicit.PIM/<ver>/Omnicit.PIM.psd1 -Force
```

The Sampler test task measures coverage against the **built** module output, not `source/`, and
`build.yaml`'s `test` workflow does not include `build` (`build.yaml:63-70`; only the default
workflow, `./build.ps1` with no `-Tasks`, runs both). Always run `-Tasks build` before `-Tasks test`
after changing source files -- and never build while the tests are running. The coverage threshold
is 80 % (`build.yaml:152`).

**The build stamps the version GitVersion computes, and a local build needs GitVersion to do it.**
Sampler (`Get-SamplerBuildVersion`, Sampler 0.120.1) takes `$env:ModuleVersion` when it is set,
else runs `gitversion` or `dotnet-gitversion` from `PATH`, and else falls back to the source
manifest's placeholder `ModuleVersion = '1.0.0'` -- which the release version cap refuses, so the
QA gate goes red. CI installs `GitVersion.Tool` 5.12.0 and exports `ModuleVersion` before it
builds; locally, put GitVersion 5 on `PATH` and do not set `$env:ModuleVersion` by hand.

**Build tooling resolves `latest`, so a local `output/RequiredModules` goes stale and LOCAL GREEN IS
NOT CI GREEN.** `RequiredModules.psd1` asks for the newest release of every build tool
(InvokeBuild, PSScriptAnalyzer, Pester, ModuleBuilder, Configuration, Metadata,
ChangelogManagement, Sampler, Sampler.GitHubTasks), but a local tree is resolved once and then left
alone, while every CI run resolves afresh on a clean runner. The two RUNTIME modules are the
exception: `Az.Resources` 9.0.3 and `Microsoft.Graph.Authentication` 2.36.0 are pinned there,
equal to the manifest's floors, and the package and publish jobs install exactly those versions,
read from that file (see **Dependencies**). So a full local pass proves the suite against whatever
build tooling happens to be on disk, not against what the merge gate will run. Refresh before
trusting a local run, especially before opening or updating a PR:

```powershell
./build.ps1 -ResolveDependency -Tasks noop -UseModuleFast
```

`-UseModuleFast` is a DIFFERENT resolver from CI's (PSResourceGet, per `Resolve-Dependency.psd1`),
so the two trees can still differ in shape. The workflow's "Report resolved dependency versions"
step prints the versions each CI run actually resolved, and is the authority on what the gate
tested.

**A refresh ADDS versions and removes nothing.** PowerShell loads the HIGHEST version available when
importing by name, so a refreshed tree does test the new one -- but the directory is a growing
record of every version ever resolved, not a picture of what is currently requested. Confirm the
version under test with `Get-Module <name> -ListAvailable` rather than by reading the folder
listing, and delete the directory outright if a genuinely clean resolve is needed.

---

## Publishing

**Every merge to `main` publishes a new preview to the public PowerShell Gallery, and that is
PERMANENT.** The Gallery can unlist a version but cannot delete one. There is no staging step and
no deployment approval between merge and publish: merging the pull request is the decision to
publish it.

- **Publishing lives in `.github/workflows/build-and-test.yml`, in its `publish` job.** That job
  is the only thing in this repository that can publish. It runs only for a push to `main` or to
  a `v` tag in `Omnicit/Omnicit.PIM`, after `package`; a pull request or a fork cannot reach it.
  `./build.ps1 -Tasks publish` is deliberately undefined (it fails with "Missing task 'publish'")
  and must stay that way, so there is no local publishing path at all. Do NOT restore Sampler's
  `Publish_Release_To_GitHub` / `publish_module_to_gallery` tasks in `build.yaml`; the measured
  reasons are in that file's comment.
- **What is published is what was tested.** The `ubuntu-latest` leg records the commit, the
  computed and the manifest version, and a SHA-256 per file of the built module
  (`PublishArtefact.ps1 -Record`). `package` and `publish` each download that artefact and verify
  all of it from scratch (`-Verify`) before using it. `package` then rehearses the publish into a
  temporary local repository and installs and imports the result in a clean process; it never
  publishes.
- **A merge that changes only documentation publishes a new preview too.** The workflow has no
  path filter and must not be given one -- a preview per merge is the price of the merge-to-main
  trigger, not a defect to be filtered away.
- **`paths-ignore` must never be added to the `pull_request` trigger**, for the reason the matrix
  exists: a run that never happens never reports the four required checks, and a required check
  that never reports stays Pending forever.
- **The publish job tags every publish, and the tag is load-bearing.** Its last step creates the
  `v<version>` tag and a GitHub release whose notes are the built manifest's `ReleaseNotes` (marked
  as a prerelease for a preview). `GitVersion.yml` runs `mode: ContinuousDelivery`, where the
  preview counter advances on a TAG and not per commit: measured in Omnicit.EntraRBAC with
  GitVersion 5.12.0, two merges with no tag between them compute the SAME version. If a publish
  succeeds but the tag step fails, the next merge computes the same version, skips the publish
  (the idempotence check finds the version on the Gallery) and then creates the tag and release on
  ITS OWN commit -- not on the commit whose build the Gallery holds. So re-run the failed job
  before anything else merges: the re-run tags the commit it published. If a merge has already
  happened, move the tag and its release to the published commit by hand (a preview tag is outside
  the `Stable Version` ruleset; a stable tag can be moved only by that ruleset's bypass list).
- **Never create a version tag by hand outside that repair or a deliberate release.** The rule
  under **CHANGELOG and Version** has teeth here: a stray tag changes what gets PUBLISHED.
- **No approval stands between a merge or a `v` tag and the Gallery**, by decision, as in
  Omnicit.EntraRBAC. The `PIM` environment has no required reviewers: it scopes the
  `GALLERYAPITOKEN` secret to the `publish` job and admits only branch `main` and the stable
  `v<X.Y.Z>` tag patterns, none of which admits a hyphen. The gate for a preview is the pull request
  and its four required checks; the gate for a full release is the tag, which only the
  `Stable Version` tag ruleset's bypass list -- the repository admin role -- can create, move or
  delete. Both closures are repository SETTINGS on purpose: a tag push runs the workflow file at
  the tagged commit, so a check in the workflow is removed by the same commit that abuses it. Never
  widen an environment tag pattern past what the ruleset covers, and never to `v*`. The accepted
  residual: whoever can merge a pull request can publish a preview.
- **The workflow must never create, move or delete a stable tag.** The ruleset refuses
  `GITHUB_TOKEN` all three, so a stable run that tried would fail in its last step, AFTER the
  publish. On a `v` tag run the release step attaches the release to the tag already there; the
  only tag the workflow ever writes is a hyphenated preview tag, which the ruleset does not cover.
- **The publish job refuses a version its ref does not call for**, in the step "Refuse a version
  the triggering ref does not call for", straight after the artefact is verified and before
  anything is published or the secret is handed out: on a `v` tag the built version must equal the
  tag exactly and the tagged commit must be on `main`; on `main` the build must carry a prerelease
  label; any other ref is refused. It guards against MISTAKES, not an adversary -- the gate stays in
  the settings, since a changed workflow writes the step away. **A refused or misplaced stable tag
  stays where it is**, and nothing removes it for you: someone on the bypass list deletes it with
  `git push origin :refs/tags/v<X.Y.Z>` and, for a misplaced one, pushes it again on the `main`
  commit it was meant for.
- **A failed Gallery confirmation is not proof of a failed publish.** The job asks the Gallery for
  the exact version for up to 10 minutes and goes red if it cannot see it; check the Gallery before
  re-running, and never assume the version is free. A re-run is safe: the publish step skips a
  version that is already on the Gallery, and the release step skips a release that already exists.

**To cut a full release:**

1. Push `v<X.Y.Z>` on the `main` tip, once that commit's four checks are green. Only the
   `Stable Version` ruleset's bypass list -- the repository admin role -- can create that tag, and
   the push IS the release decision: nothing asks for an approval after it. The tag run builds,
   tests and packages again, and the refusal step then requires the built version to equal the tag
   and the commit to be on `main`. A tag outside the `PIM` environment's patterns is refused
   by the environment, visibly, and publishes nothing; the repair is a new pattern the ruleset also
   covers, never `v*`. A `v1.0.0` or higher tag also fails the release version cap until that cap
   is raised -- see **CHANGELOG and Version**.
2. Make the close-out the FIRST merge after the tag, exactly as the **close-out after a stable
   release** rule under **CHANGELOG and Version** describes. The invariant to check it against is
   `git show v<X.Y.Z>:CHANGELOG.md` -- the dated section must say what that tag actually shipped.

---

## CHANGELOG and Version

`CHANGELOG.md`'s `[Unreleased]` section **is** the next release's published `ReleaseNotes`, not a
per-PR log. The build (Sampler's `Create_changelog_release_output` task) rewrites its heading to
`## [<version>] - <date>` in `output/CHANGELOG.md` and copies the section verbatim into the built
manifest's `PrivateData.PSData.ReleaseNotes`, which the publish job also uses as the GitHub release
body.

- **Write `[Unreleased]` in release-note voice** -- product-level and user-visible: what this
  version is, and what changed for someone consuming the module. Budget **4,000 characters**,
  gated in `tests/QA/module.tests.ps1` (`:157-217`) on the section's `RawData`, which includes the
  `## [Unreleased]` heading and therefore reads slightly SHORT of what is actually published -- do
  not spend the difference. Sampler cuts the note at 10,000 characters; that is a backstop, not
  headroom.
- **The floor is on the BODY and is 50 characters -- about one sentence** (`:89`). The section
  after its heading line, trimmed, must reach it, in the source and in the built manifest alike. It
  is there to catch a MECHANICAL failure, an emptied or hand-converted section that publishes
  `ReleaseNotes` of length 0 while the build reports success, and it does not judge the text:
  whether a note says enough is decided in review. Never pad the section to get past it -- every
  merge publishes the padding to the Gallery for good.
- **Close-out after a stable release.** The close-out is the FIRST merge after a `v<X.Y.Z>` tag. It
  adds `## [X.Y.Z] - <date>` directly above the previous dated heading, moves the released notes
  under it, and leaves `[Unreleased]` holding exactly this sentence and nothing else, with `X.Y.Z`
  the version just released (template at `:97`):

  ```text
  No changes to the module since X.Y.Z. A preview published from this point differs from X.Y.Z only in documentation, tests or the build.
  ```

  It has to come first because every merge publishes `[Unreleased]` as a preview's `ReleaseNotes`:
  a merge landing between the tag and the close-out publishes a preview whose notes describe the
  previous release's changes as new. **The first change under `source/` after a close-out REPLACES
  the sentence** with a note of its own; it never adds the note after it.
  Wrapping the sentence across lines is fine. `tests/QA/module.tests.ps1` holds both halves: while
  the sentence stands it must be exactly that sentence for the latest dated section in
  `CHANGELOG.md` (`:339-371`), and it must not survive a diff that touches `source/`
  (`:373-395`).
- **Per-PR engineering detail belongs in the PR body and the commit message**, not in
  `CHANGELOG.md`. The published note is read by module consumers, not by reviewers.
- **When `[Unreleased]` approaches the budget, close the detail out.** Add a NEW dated
  `## [<version>] - <date>` heading directly above the previous dated one, move the accumulated
  detail under it, and rewrite `[Unreleased]` as a summary of the release as a whole.
- **Never convert, rename or delete the `## [Unreleased]` heading itself.** The build does that at
  release time against its own OUTPUT copy; the source file is never modified by a build. A
  hand-converted section leaves the source `[Unreleased]` empty, and the next build then publishes
  `ReleaseNotes` of length 0 while reporting success.
- **A PR that changes nothing under `source/` is not required to touch `CHANGELOG.md`.** The
  changed-file gate (`:126-147`) fires only on a path matching `^source/`, in the diff against
  `origin/main` plus anything staged or unstaged.
- **The two gates that read the BUILT artefact need a build.** They are "Built manifest
  ReleaseNotes is populated and not truncated" (`:219-337`) and the "Release version cap"
  (`:404-443`). `build.yaml`'s `test` workflow does not include `build`, so both measure whatever
  is already in `output/module/`. The published-notes gate also compares that artefact against the
  CURRENT `CHANGELOG.md` -- heading naming the built version, body byte-identical to the source
  section -- so a build older than your changelog edit turns it red. That is the right direction
  of failure, not a bug: it is exactly the state in which the source-side gates are green and the
  published note is wrong. The version cap reads only the artefact's own version. Either way: build
  before test, exactly as **Build and Test Commands** already requires. Both gates resolve the
  module under test with `Get-Module -ListAvailable | Select-Object -First 1` (`:70-71`), so they
  measure whichever copy ranks first on `PSModulePath` -- under `./build.ps1 -Tasks test` that is
  the built module, but a globally installed copy would be measured instead.

**The computed module version is held in the `0.x` line, at or above `0.5.1`.** The "Release
version cap" in `tests/QA/module.tests.ps1` holds the built version at `>= 0.5.1` and `< 1.0.0`
(`:427`, `:434`), independently of `GitVersion.yml`. A move to `1.0.0` is a release decision, not
something a commit message may make: raise the bound in the same change that calls `1.0.0`, and
never raise it just to make a build pass. A build that falls back to the source manifest's
placeholder `1.0.0` (no GitVersion, see **Build and Test Commands**) fails the cap too, by design.

**How the version is computed.** `GitVersion.yml` uses the GitVersion 5 schema with
`mode: ContinuousDelivery`. The base is the newest reachable version tag -- `v0.5.1` today, on
`5e06243`; `next-version: 0.0.1` sits below every tag and never wins. A tag sitting on HEAD is
returned verbatim. From the base comes **at most ONE increment**, never one per commit: the
branch's default -- Patch on `main`, Minor on a branch matching `^feat(ure)?s?[\/-]`, Patch on one
matching `^(hot)?fix(es)?[\/-]`, and the fallback defaults on every other branch -- unless a bump
message in the commits since that tag names a higher level. `main` carries the `preview` label, so
a merge after `v0.5.1` builds `0.5.2-preview<NNNN>`; measured on 2026-10-05, `feat/x` builds
`0.6.0-x0001`, a `fix/` branch `0.5.2-fix...`, and a `chore/` branch `0.5.2-chore...`. GitVersion
5.12 also needs a resolvable `main` ref to compute anything on a branch that matches no
configuration, so a clone without one cannot build such a branch.

**Do not create a version tag, or a `release/x.y.z` branch, outside a deliberate release.** Any
newer tag becomes the base, and one sitting on HEAD ships verbatim whatever its value. GitVersion's
default `release` branch configuration, which `GitVersion.yml` does not override, takes the version
from a `release/x.y.z` branch name. `release/` is not one of the prefixes in the branch-naming
table above.

**Two different shapes move the version from a message, and both must be kept out of commit
messages, PR titles and PR bodies.** `GitVersion.yml` (`:18-21`) recognises the semver bump token --
a plus sign, the word semver, a colon and a level (`+semver: major`, `+semver: minor`,
`+semver: patch` and their synonyms) -- and, for a major, a conventional-commit subject with an
exclamation mark before the colon (`fix!: ...`, `feat(x)!: ...`).

1. **Never quote a bump token** -- name it in words ("the semver major token"). A message that
   merely quotes the major token builds `1.0.0`, and one that quotes the minor token moves the
   version silently.
2. **Never write a conventional-commit breaking subject** -- a type, an optional scope, then an
   exclamation mark before the colon. Every such subject matches the second half of
   `major-version-bump-message` and builds `1.0.0`. That half is LIVE.

GitVersion reads every reachable commit message, and a squash merge copies the PR title and body
into `main`, so a squash title in the breaking form is enough on its own. File content is never
read and may quote either shape freely.

**Since every merge to `main` publishes, this is not a rule about a number in a build log.** What
one of those shapes does splits by level, and only one level is caught:

- **Major.** The version cap fails the build at `1.0.0`, so the merge turns `main` RED, `package`
  and `publish` never run, and nothing is published. The repair then happens on `main` under a
  broken required check instead of in an open PR, which is bad enough on its own.
- **Minor.** Nothing caps it. `main` carries `tag: preview`, so the merge publishes, for example,
  `0.6.0-preview0001` in place of `0.5.2-preview0001` -- a real version, on the public Gallery,
  that cannot be deleted, and a version line that was never chosen. There is no gate behind this
  one: the rule about what you type IS the control.

---

## Authentication Architecture

**Public:** `Connect-OPIM` (alias `Connect-PIM`), `Disconnect-OPIM` (alias `Disconnect-PIM`).
**Private:** `Initialize-OPIMAuth` (the single entry point), `Get-OPIMMsalApplication`,
`Invoke-OPIMGraphRequest`.

**`Initialize-OPIMAuth` is the single entry point.** The nine pillar cmdlets -- `Get-`, `Enable-`
and `Disable-` for `DirectoryRole`, `AzureRole` and `EntraIDGroup` -- and `Wait-OPIMDirectoryRole`
call it as the first statement of their `process` block (of their `begin` block in
`Enable-OPIMDirectoryRole` and `Wait-OPIMDirectoryRole`), and the three `*-OPIMAzureRole` cmdlets
pass `-IncludeARM`. `Connect-OPIM` resolves `-TenantAlias` from `TenantMap.psd1` and passes its
`-TenantId` and `-IncludeARM` on (`Connect-OPIM.ps1:63-91`); it is an optional pre-authentication
shortcut, since every pillar cmdlet authenticates on first use. `Enable-OPIMMyRole` and
`Disable-OPIMMyRole` call `Connect-OPIM` and then the pillar cmdlets. The `*-OPIMConfiguration`
cmdlets do not authenticate.

**It is idempotent.** It returns without a network call or a prompt when the cached Graph token is
for the same tenant label, has more than 5 minutes left, and neither `-ClaimsChallenge` nor
`-ForceRefresh` was passed (`Initialize-OPIMAuth.ps1:78-83`). A `Get-MgContext` fallback runs only
when the module's own `$script:_OPIMAuthState` already exists with more than 5 minutes left
(`:90-92`): it then accepts the live Graph context for the requested tenant -- or any tenant when
the request names none, which means `organizations` -- and relabels the module's own session
(`:93-101`). The fallback does not check where the live Graph context came from: while the
module's own state is fresh, a `Connect-MgGraph` made outside the module for the requested tenant
-- or for any tenant when none is requested (`organizations`) -- is accepted, and the module's
state is relabelled with the requested tenant label, keeping the old `GraphTokenExpiry`
(`Initialize-OPIMAuth.ps1:90-101`). Only without fresh module state, or with `-ClaimsChallenge`
or `-ForceRefresh`, does the fallback not run. With `-IncludeARM`, Azure counts as
connected only when a cached Az context for the tenant can mint an ARM token silently through
`Get-AzAccessToken` (`:105-125`): the Az module autosaves its context, so a bare context can
resurface in a new session with an expired token.

**Graph tokens come from MSAL.NET, reached by reflection.** `Get-OPIMMsalApplication` finds the
`Microsoft.Identity.Client` assembly (4.x or 5.x) that `Microsoft.Graph.Authentication` loads into
its own `AssemblyLoadContext`, falling back to loading the DLL from that module's folder
(`Get-OPIMMsalApplication.ps1:57-76`). It builds a public client application for the Microsoft
Graph Command Line Tools public client id -- no app registration -- with the authority
`https://login.microsoftonline.com/<tenant>` and the redirect URI `http://localhost` (`:93-140`).
The application is cached in `$script:_OPIMMsalApp`, its tenant in `$script:_OPIMMsalAppTenantId`,
and it is rebuilt only when the tenant changes (`:35-38`, `:154-155`). The reflection is of two
kinds. `Create`, `WithAuthority`, `WithRedirectUri` (`Get-OPIMMsalApplication.ps1:113-140`),
`AcquireTokenSilent` and `AcquireTokenInteractive` (`Initialize-OPIMAuth.ps1:165-172`, `:205-210`)
are found by name through `GetMethods()` and filtered on parameter count -- and, for
`WithAuthority`, `AcquireTokenSilent` and `AcquireTokenInteractive`, also on parameter type NAME
-- because types from the Graph SDK's load context are not identical to the same types in the
default one (the source's own comments: `Initialize-OPIMAuth.ps1:148-151`,
`Get-OPIMMsalApplication.ps1:109-112`).
A typed `GetMethod(name, [Type[]])` is used only with `[bool]` or `[string]` parameters --
`WithForceRefresh`, `WithUseEmbeddedWebView`, `WithLoginHint`, `WithClaims`
(`Initialize-OPIMAuth.ps1:186`, `:217`, `:224`, `:232`) -- or with none: `GetMethod('Build')`
(`Get-OPIMMsalApplication.ps1:143`).

**Acquisition order:** `AcquireTokenSilent` when an account is cached and no claims challenge was
given, chained with `.WithForceRefresh($true)` under `-ForceRefresh`
(`Initialize-OPIMAuth.ps1:163-200`); otherwise, or when that fails, `AcquireTokenInteractive` in
the SYSTEM BROWSER -- `.WithUseEmbeddedWebView($false)`, no WAM, no embedded view -- with a login
hint for a cached account and `.WithClaims()` for an ACRS step-up (`:203-245`). An interactive
failure is the terminating `InteractiveAuthFailed` (a headless system cannot open the browser). The
Graph token is then handed to `Connect-MgGraph -AccessToken` as a SecureString (`:278-279`).

**The Graph scope list is fixed -- do not change it.** One prompt covers every PIM surface
(`Initialize-OPIMAuth.ps1:139-146`):

```text
RoleEligibilitySchedule.ReadWrite.Directory
RoleAssignmentSchedule.ReadWrite.Directory
PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup
PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup
AdministrativeUnit.Read.All
User.Read
```

**Azure is signed in separately, by the Az module.** The Microsoft Graph Command Line Tools app is
not authorised for Azure Resource Manager, so `-IncludeARM` uses the Az module's own sign-in. When
no validated context exists, it disables WAM at PROCESS scope only
(`Update-AzConfig -EnableLoginByWam $false -Scope Process`; the persisted Az configuration is never
touched) and calls `Connect-AzAccount`, with `-Tenant` unless the tenant is `organizations`
(`:295-319`). A failed connection is the non-terminating `AzureConnectFailed`. The `Az.Resources`
cmdlets then run in that Az context.

**State.** `$script:_OPIMAuthState` holds `TenantId`, `Account`, `GraphTokenExpiry` and
`ClaimsSatisfied` (`:282-287`) -- never a token. The tokens themselves live in the MSAL
application's in-memory cache (`$script:_OPIMMsalApp`) and in the Graph SDK's context; see
**SECURITY**.

**`Disconnect-OPIM`** sets `$script:_OPIMAuthState`, `$script:_OPIMMsalApp`,
`$script:_OPIMMsalAppTenantId` and `$script:_MyIDCache` to `$null`, then calls `Disconnect-MgGraph`
and `Disconnect-AzAccount`, each with `-ErrorAction SilentlyContinue` inside a `try` whose `catch`
discards the error (`Disconnect-OPIM.ps1:22-28`). `Disconnect-AzAccount` acts on the current Az
context, whether or not the module established it.

**`Invoke-OPIMGraphRequest` owns the Graph transport.** It calls `Invoke-MgGraphRequest` with
`-Verbose:$false -ErrorAction Stop` (`Invoke-OPIMGraphRequest.ps1:101-110`) and, on a failure:

1. **ACRS claims-challenge retry.** It looks for `claims=` in the `WWW-Authenticate` header, the
   response body and the exception message, and decodes the value as URL-encoded JSON (the PIM 400
   `RoleAssignmentRequestAcrsValidationFailed` body form), base64url JSON (the 401 step-up header
   form) or raw JSON (`:61-98`). It then calls `Initialize-OPIMAuth -ClaimsChallenge` for one
   interactive step-up and retries exactly once; a second failure is converted and thrown
   (`:121-137`).
2. **Token-rejected retry.** A 401 that is not a claims challenge, or a message matching
   `InvalidAuthenticationToken`, `CompactToken`, `token is expired` or `Lifetime validation failed`,
   calls `Initialize-OPIMAuth -ForceRefresh` and retries once (`:143-157`).
3. **Error conversion.** Anything else is thrown as `Convert-GraphHttpException`'s record, whose
   `FullyQualifiedErrorId` is the Graph `error.code` (`:160`). A caller receives a response or a
   thrown `ErrorRecord` -- there is no side-channel protocol.

Its catches call `$null = $Error.Remove($PSItem)` first; see **Error Handling** for what that does
and does not do.

**The places that call the raw SDK or Az authentication directly today**, from a `Select-String`
over `source/` on 2026-10-05, listed as they are:

| File:line (under `source/`) | Call |
|---|---|
| `Private/Invoke-OPIMGraphRequest.ps1:110, 132, 152` | `Invoke-MgGraphRequest` -- the wrapper itself |
| `Private/Get-OPIMCurrentTenantInfo.ps1:44` | `Invoke-MgGraphRequest` for `v1.0/organization` (best-effort tenant display name) |
| `Public/Wait-OPIMDirectoryRole.ps1:101, 117` | `Invoke-MgGraphRequest` inside `ForEach-Object -Parallel`, with absolute `https://graph.microsoft.com/v1.0/...` URIs (`:101` passes `-ErrorAction Stop`, `:117` does not) |
| `Private/Initialize-OPIMAuth.ps1:279` | `Connect-MgGraph -AccessToken` |
| `Private/Initialize-OPIMAuth.ps1:120` | `Get-AzAccessToken` (silent validation; the token is discarded) |
| `Private/Initialize-OPIMAuth.ps1:311` | `Connect-AzAccount` |
| `Public/Disconnect-OPIM.ps1:27, 28` | `Disconnect-MgGraph`, `Disconnect-AzAccount` |

Beside these, the module reads `Get-MgContext` (`Initialize-OPIMAuth.ps1:93`,
`Get-OPIMMsalApplication.ps1:46`, `Get-MyId.ps1:26`, `Get-OPIMCurrentTenantInfo.ps1:30`), reads
`Get-AzContext` (`Initialize-OPIMAuth.ps1:105`), calls `Update-AzConfig` (`:303`), and calls the
`Az.Resources` cmdlets listed under **API Mapping**.

---

## API Mapping

Terminology differs from the PIM portal. Every Graph path is `v1.0`.

**Directory roles** (Graph, `roleManagement/directory/`):

| Graph resource | PIM concept |
|---|---|
| `roleEligibilitySchedules` | Roles eligible to activate (inactive) |
| `roleAssignmentScheduleInstances` | Currently active role assignments |
| `roleAssignmentScheduleRequests` | Activate (`SelfActivate`) or deactivate (`SelfDeactivate`) |

Reads use `filterByCurrentUser(on='principal')` and `$expand=principal,roledefinition`. Graph
`v1.0` cannot expand `directoryScope`, so `Get-OPIMDirectoryRole` fetches
`v1.0/directory<directoryScopeId>` through the wrapper for every item not at the root scope `/`
(`Get-OPIMDirectoryRole.ps1:126`, `:161-167`). A `SelfDeactivate` request is built from the ACTIVE
instance, never from an eligibility schedule: it sends the instance's `roleDefinitionId`,
`directoryScopeId` and `principalId`, and its `roleAssignmentScheduleId` as `targetScheduleId`
(`Disable-OPIMDirectoryRole.ps1:61-67`). After a request, `Restore-GraphProperty` copies
`roleDefinition`, `principal` and `directoryScope` from the source object into the response; it
makes no Graph call.

**Azure resource roles** (`Az.Resources`):

| Cmdlet | PIM concept |
|---|---|
| `Get-AzRoleEligibilitySchedule` | Eligible (inactive) RBAC roles |
| `Get-AzRoleAssignmentScheduleInstance` | Active RBAC assignments (`AssignmentType` `Activated`) |
| `New-AzRoleAssignmentScheduleRequest` | Activate (`SelfActivate`) or deactivate (`SelfDeactivate`) |
| `Get-AzRoleAssignmentScheduleRequest` | `Enable-OPIMAzureRole -Wait` polling |

Reads use the filter `asTarget()` at scope `/` unless `-Scope` names another. An Azure schedule's
id is its `Name`, not `id`; an activation sends `LinkedRoleEligibilityScheduleId = $Role.Name`
(`Enable-OPIMAzureRole.ps1:96-100`).

**PIM for Groups** (Graph, `identityGovernance/privilegedAccess/group/`):

| Graph resource | PIM concept |
|---|---|
| `eligibilitySchedules` | Eligible (inactive) group assignments |
| `assignmentScheduleInstances` | Active group assignments |
| `assignmentScheduleRequests` | `selfActivate` / `selfDeactivate` |

`accessId` is `member` or `owner`. A request carries `accessId`, `groupId` and `principalId`; reads
expand `group,principal`.

---

## Standard Parameter Patterns

**`Enable-OPIM*`** (`Enable-OPIMDirectoryRole`, `Enable-OPIMAzureRole`, `Enable-OPIMEntraIDGroup`):

- `-Role` / `-Group` -- schedule objects piped from the matching `Get-OPIM*` cmdlet.
- `-RoleName` / `-GroupName` -- tab-completed through the `IArgumentCompleter` class in
  `source/Classes/`; the value ends in `(<schedule id>)`, which `Resolve-RoleByName` parses back.
- `-Identity` -- a schedule id.
- `-Justification`, `-TicketNumber`, `-TicketSystem` -- the optional PIM policy fields.
- `-Hours` [int] -- default 1; users override it through `$PSDefaultParameterValues`.
- `-NotBefore` [DateTime] -- activation start, default now.
- `-Until` [DateTime] (alias `-NotAfter`) -- explicit end; takes precedence over `-Hours`.
- `-Wait` [switch] -- on all three. Directory roles hand the requests to `Wait-OPIMDirectoryRole`;
  Azure roles poll `Get-AzRoleAssignmentScheduleRequest`; groups poll the request's status while it
  is `Pending*`.
- `-WhatIf` / `-Confirm` through `[CmdletBinding(SupportsShouldProcess)]`.
- An already-active object piped in (from `Get-OPIM* -All`) is skipped with a verbose message.

**`Disable-OPIM*`:**

- `-Role` / `-Group` (piped), `-RoleName` / `-GroupName` -- tab-completed to *active* assignments --
  and `-Identity`.
- An eligible-only object piped in is skipped with a verbose message.
- `-WhatIf` / `-Confirm` through `[CmdletBinding(SupportsShouldProcess)]`.

**`Get-OPIM*`:**

- `-Activated` [switch] -- active instances instead of eligibility schedules.
- `-All` [switch] -- BOTH eligible and active in one call, tagged `Omnicit.PIM.*CombinedSchedule`
  with a `Status` column. Mutually exclusive with `-Activated`.
- `-RoleName` / `-GroupName`, `-Identity` -- one schedule.
- `-Filter` [string] -- an OData filter passed through, on `Get-OPIMDirectoryRole` and
  `Get-OPIMEntraIDGroup`; without `-Activated` both eligible and active are searched.
- `-Scope` [string] on `Get-OPIMAzureRole` -- default `/`; with `-Activated`, an exact scope match.
- `-AccessType` on `Get-OPIMEntraIDGroup` -- `member` or `owner`.

**Tab completion.** Each completer returns a quoted string ending in the schedule id in
parentheses, in a different format per pillar:

- Directory roles: `'<role> -> <scope display name> (<id>)'`, the scope part omitted at the root
  scope `/`.
- Azure roles: `'<role> -> <scope display name> (<Name>)'` -- the id is the schedule's `Name`.
- Groups: `'<group> - <accessId> (<id>)'` -- a dash, not an arrow.

`Resolve-RoleByName` (private) parses the trailing `(<id>)` and matches `.id` for directory roles
and groups, `.Name` for Azure. The completers call the `Get-OPIM*` cmdlets through
`& ([scriptblock]::Create('Get-OPIM...'))`, so a completion authenticates and calls Graph or ARM on
the prompt path. Keep that call form -- see **Testing Conventions**.

**Configuration CRUD.** The four `*-OPIMConfiguration` cmdlets manage `TenantMap.psd1`, which
`Connect-OPIM -TenantAlias` and `pim`/`unpim` read:

| Cmdlet | Operation | Notes |
|---|---|---|
| `Install-OPIMConfiguration` | Create | Mandatory `-TenantAlias`; `-TenantId` (resolved from the active Graph context when omitted); accepts pipeline input from `Get-OPIM*`. Error if the alias exists. `ConfirmImpact = 'High'`. |
| `Get-OPIMConfiguration` | Read | Optional `-TenantAlias` filter. Returns `Omnicit.PIM.TenantConfiguration` objects. |
| `Set-OPIMConfiguration` | Update | Mandatory `-TenantAlias`; optional `-TenantId`; accepts pipeline input from `Get-OPIM*`. Error if the alias is missing. `ConfirmImpact = 'High'`. |
| `Remove-OPIMConfiguration` | Delete | Mandatory `-TenantAlias`. Error if the alias or the file is missing. `ConfirmImpact = 'High'`. |

`Install-OPIMConfiguration` is create-only and has no `-Force`; an existing alias is changed with
`Set-OPIMConfiguration`. The private `Export-OPIMTenantMap` owns the PSD1 serialization and is
called by `Install`, `Set` and `Remove`; never inline it.

---

## Code Style

- **PascalCase for all variables, functions, and parameters** -- `$Response`, `$Request`,
  `$FakeRole`, `$ScheduleId`. Exceptions: automatic variables (`$PSCmdlet`, `$PSItem`, `$_`),
  preference variables (`$ErrorActionPreference`), boolean/null literals (`$null`, `$true`,
  `$false`), and the module-scope caches (`$script:_OPIMAuthState`, `$script:_OPIMMsalApp`,
  `$script:_OPIMMsalAppTenantId`, `$script:_MyIDCache`). Older code -- `Wait-OPIMDirectoryRole` in
  particular -- still has camelCase locals; new and edited lines follow the rule.
- **One function per file; filename must equal function name.**
- `[CmdletBinding(SupportsShouldProcess)]` on every state-changing function (every Enable- and
  Disable- cmdlet, and the configuration writers). Call `$PSCmdlet.ShouldProcess`, not
  `$PSCmdlet.ShouldContinue`.
- `[OutputType([PSCustomObject])]` on every function that returns type-tagged objects; do not
  declare `[OutputType([System.Collections.Hashtable])]` (`Wait-OPIMDirectoryRole` still does).
- **Output tagging is mandatory** -- never return a raw `Invoke-OPIMGraphRequest` hashtable (the
  default Key/Value formatter applies to it):
  ```powershell
  $Out = [PSCustomObject]$Response
  $Out.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.SomeTypeName')
  $Out
  ```
  The type name needs a matching `<View>` in `source/Formats/Omnicit.PIM.Format.ps1xml` and, if it
  needs ScriptProperty members, a `<Type>` entry in `source/Formats/Omnicit.PIM.Types.ps1xml`.
- **Never use `*` in `FunctionsToExport`** -- always list explicitly. ModuleBuilder rewrites
  `FunctionsToExport` (from the `Public/` file names) and `AliasesToExport` in the BUILT manifest,
  but the source manifest lists both explicitly too and governs an import from source, so keep it
  in step.
- `DefaultCommandPrefix` is NOT used in the manifest. Function names carry the `OPIM` prefix
  explicitly; adding it would double-prefix to `Get-OPIMOPIMDirectoryRole`.
- **Aliases are declared with the `[Alias()]` attribute on the function.** The dev-mode psm1
  exports them with `Export-ModuleMember -Alias *` (there is no alias map), and ModuleBuilder writes
  them into the built manifest's `AliasesToExport`. Add a new alias to the source manifest's
  `AliasesToExport` as well.
- **Naming:**

  | Concept | Pattern | Example |
  |---|---|---|
  | Function prefix | `OPIM` | `Get-OPIMDirectoryRole` |
  | Short aliases | `PIM` | `Get-PIMRole`, `Get-PIMADRole` |
  | Directory role noun | `DirectoryRole` | `Enable-OPIMDirectoryRole` |
  | Azure RBAC noun | `AzureRole` | `Enable-OPIMAzureRole` |
  | PIM for Groups noun | `EntraIDGroup` | `Enable-OPIMEntraIDGroup` |
  | Configuration CRUD | `*-OPIMConfiguration` | `Install`/`Get`/`Set`/`Remove-OPIMConfiguration` |
  | Authentication | `Connect`/`Disconnect-OPIM` | `Connect-OPIM` (alias `Connect-PIM`) |
  | Convenience activation | `Enable`/`Disable-OPIMMyRole` | `Enable-OPIMMyRole` (alias `pim`) |
  | Filename | `Verb-OPIMNoun.ps1` | `Disable-OPIMDirectoryRole.ps1` |

- **`$OdataFilter` for a built OData filter.** In a function with a `-Filter` parameter, a local
  `$Filter` shadows the parameter; name the local variable `$OdataFilter`.
- **ISO 8601 durations:** `[System.Xml.XmlConvert]::ToString([TimeSpan]::FromHours($Hours))`, which
  gives `PT1H`, as the three `Enable-OPIM*` cmdlets do.
- **The current user's object id:** `Get-MyId` (private) resolves it through `v1.0/me` and caches
  it in `$script:_MyIDCache`, keyed by user principal name. Use it rather than a new lookup. No
  module function calls it today.
- **PSScriptAnalyzer:** the QA gate requires zero findings, with the default rules, for every
  function's source file. A targeted suppression is acceptable only for a known false positive and
  only with a `Justification` string; **never suppress a rule that hides a real bug.** No function
  file carries a suppression today; the six completer classes carry two each
  (`PSAvoidUsingWriteHost` and `PSUseDeclaredVarsMoreThanAssignments`), each with a `Justification`.

---

## CRITICAL: ASCII-Only Source Files

Authored `.ps1` files are UTF-8 **without BOM**. They **must contain only ASCII characters** --
no em-dashes, no box-drawing characters, no arrows, no smart quotes, no curly apostrophes.

Without a BOM, PowerShell and PSScriptAnalyzer treat the file as ASCII. A non-ASCII character in
a BOM-less file fails PSScriptAnalyzer's `PSUseBOMForUnicodeEncodedFile` rule, which the QA gate
runs on every function's source file.

The only acceptable exception is a helper file that was verbatim-copied from a source that
already carries a UTF-8 BOM.

Use `--` (two hyphens) for em-dash contexts in comments and help text and `->` for an arrow. Use
straight quotes `'` and `"` only.

**This repository is not there yet.** Measured on 2026-10-05, on the text after any leading BOM:
18 of the 44 tracked files under `source/` and 3 of the 33 under `tests/` contain non-ASCII
characters (mostly em-dashes and box-drawing rules in comments), and 19 of those 21 carry a UTF-8
BOM -- which is why the per-function PSScriptAnalyzer run passes today. The two without a BOM are
`source/Omnicit.PIM.psm1` and `source/en-US/about_Omnicit.PIM.help.txt`, neither of which that run
analyses. A further 29 files (21 under `source/`, 8 under `tests/`) carry a BOM over pure ASCII
text. A source-hygiene gate for ASCII and BOM is planned, not yet in this repository. Until it
lands:

- **New files** are ASCII and UTF-8 without BOM.
- **New or edited lines** in an existing file are ASCII, whatever the rest of the file holds.
- **Never strip the BOM from a file that still contains a non-ASCII character** -- the
  per-function PSScriptAnalyzer run then fails on `PSUseBOMForUnicodeEncodedFile`. Make the file
  ASCII first, and drop the BOM in the same change.

---

## Error Handling

- **Non-terminating errors** in public functions: `$PSCmdlet.WriteError()` followed by `return` (in
  a `process` block) or `continue` (inside a `foreach` loop over multiple items). Never use bare
  `throw` in a public function -- it terminates the pipeline and prevents
  `-ErrorAction SilentlyContinue` from working. The two in `Wait-OPIMDirectoryRole` are deliberate
  and commented: `:79` runs inside `ForEach-Object -Parallel`, where `$PSCmdlet` does not exist,
  and `:145` is a bare re-throw in the `catch` around the progress loop (`:125-145`). Errors from
  the parallel jobs themselves surface through `Receive-Job -Wait` in the `finally` (`:146`).
- **Private helpers** such as `Resolve-RoleByName`, `Restore-GraphProperty` and `Get-MyId` may
  `throw` on caller error, and `Invoke-OPIMGraphRequest` throws the converted Graph error by
  design: the caller is responsible for catching and routing it.
- **`Write-CmdletError`** (private) emits a structured record. Its `-Message` expects an
  `[Exception]`, not a string (`Write-CmdletError.ps1:76`) -- always wrap bare strings:
  `[System.Exception]::new('message')`. `-InnerException` chains a caught exception, `-Terminating`
  throws instead of writing, and `-ErrorRecord` re-emits a record unchanged.
- **`ErrorDetails` must be set via the constructor** -- plain string assignment is silently ignored
  in some PowerShell versions:
  ```powershell
  $Err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('Your message here.')
  ```
- **Graph errors and Az.Resources errors differ by design.** A Graph failure reaches the caller as
  the record `Convert-GraphHttpException` built inside the wrapper: the Graph `error.code` as
  `FullyQualifiedErrorId`, `"<code>: <message>"` as `ErrorDetails`, and the original exception as
  `InnerException`. An `Az.Resources` error arrives in `$PSItem` as the cmdlet threw it; inspect
  `$PSItem.FullyQualifiedErrorId` (`.Split(',')[0]` where the id carries a suffix, as
  `Get-OPIMAzureRole.ps1:106` does) and pass it to `$PSCmdlet.WriteError()` or rewrap it with
  `Write-CmdletError`.
- **Special error codes have converters.** `ConvertTo-ActiveDurationTooShortError` turns
  `ActiveDurationTooShort` (a deactivation within 5 minutes of the activation) into a readable
  error in the three `Disable-` cmdlets; `ConvertTo-PolicyValidationError` does the same for
  `RoleAssignmentRequestPolicyValidationFailed` in the three `Enable-` cmdlets. Each returns
  `$false` when the error is not its kind, and the caller then writes the original.
  `Get-OPIMAzureRole` rewraps `InsufficientPermissions` with the rights it needs.
- **Never print, log or persist an error record from a failed request, or anything reached through
  it.** The record `Invoke-MgGraphRequest` throws carries the raw `HttpRequestMessage`, whose
  `Authorization: Bearer` header holds the token in plain text, as its target object
  (`Invoke-OPIMGraphRequest.ps1:112-113`). The rule as it stands: every catch that wraps a raw
  `Invoke-MgGraphRequest` call runs `$null = $Error.Remove($PSItem)` as its FIRST statement --
  `Invoke-OPIMGraphRequest.ps1:114, 134, 154` and `Get-OPIMCurrentTenantInfo.ps1:51` today. **That
  idiom was measured in Omnicit.EntraRBAC to remove nothing:** a module's `$Error` is a private list
  distinct from the caller's, and even against the caller's `$global:Error` the `ErrorRecord` bound
  to `$PSItem` is not the same object instance PowerShell stored there, so the reference-equality
  `Remove` silently no-ops. A replacement is planned, not yet in this repository. Until it lands,
  keep the idiom where it is, put it first in any new catch around a raw call (there should be none
  outside the wrapper), and never rely on it.
- **Error flow patterns:**
  ```powershell
  # In process blocks (single-item cmdlets: Disable-*, Get-*): use return
  process {
      try { ... } catch {
          $PSCmdlet.WriteError($Err)
          return   # <-- not continue
      }
  }

  # In foreach loops (Enable-* with multiple roles): use continue to try the next one
  foreach ($Role in $ResolvedRoles) {
      try { ... } catch {
          $PSCmdlet.WriteError($Err)
          continue   # <-- not return
      }
  }
  ```

---

## Testing Conventions

- **Tests are written in Pester 5 syntax** under `tests/Unit/{Classes,Private,Public}/`. The build
  resolves the newest Pester (`RequiredModules.psd1` asks for `latest`), and CI resolves it afresh
  on every run, so no version is a standing fact here; 6.2.0 was resolved when measured on
  2026-10-05. One `*.Tests.ps1` per source file -- the six completer classes share
  `Unit/Classes/ArgumentCompleters.Tests.ps1`. The QA gate (`tests/QA/module.tests.ps1`) requires
  a unit test file for every function.
- **Structure:** one `Describe` per file, named exactly after the function under test. Group
  scenarios (happy path, error cases, parameter sets) in `Context` blocks, with a `BeforeAll`
  inside each `Context` for shared arrangement; use `BeforeEach` only for state that must reset
  per `It`. `It` names start with a third-person singular verb: "calls", "returns", "writes",
  "throws". Write the scope prefix in lower case, `$script:_MyIDCache`, never `$SCRIPT:`.
- **Import by module name, not by path**, in the root `BeforeAll` -- importing by path breaks the
  Sampler coverage measurement, which targets the built module:
  ```powershell
  Describe 'Get-OPIMDirectoryRole' {
      BeforeAll {
          Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
          Import-Module Omnicit.PIM -Force
      }
      AfterAll {
          Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
      }
      # Context blocks ...
  }
  ```
- **Always mock `Initialize-OPIMAuth`** -- every pillar cmdlet and `Wait-OPIMDirectoryRole` calls it
  first (see **Authentication Architecture**), so without the mock the test attempts a real MSAL
  sign-in and hangs on the browser:
  ```powershell
  Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
  ```
- **Mock `Invoke-OPIMGraphRequest`, not `Invoke-MgGraphRequest`**, scoped to the module and to the
  call with a `-ParameterFilter`:
  ```powershell
  Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
      @{ value = @(
          @{ id = 'elig-001'; roleDefinitionId = 'role-def-001'; directoryScopeId = '/' }
      ) }
  } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }

  Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 1 -Exactly -Scope It
  ```
  The mock returns what the wrapper returns: the hashtable `Invoke-MgGraphRequest` parsed from the
  response. Earlier versions of `.github/instructions/pester-tests.instructions.md` and
  `.github/prompts/generate-pester-tests.prompt.md` said to mock `Invoke-MgGraphRequest`, mostly
  WITHOUT `-ModuleName`. That is wrong for every function that goes through the wrapper. A mock
  without `-ModuleName` does not intercept a call made from inside the module at all, so the real
  SDK call runs; a module-scoped mock of the raw call does intercept it, but then drives the real
  wrapper -- its retries, its `Initialize-OPIMAuth` step-up and refresh calls, its error conversion
  -- instead of testing the function at the module boundary. Mock the raw SDK only where the test
  is about that layer itself or the function calls it directly:
  `Invoke-OPIMGraphRequest.Tests.ps1` (the wrapper, mocked inside `InModuleScope`),
  `Get-OPIMCurrentTenantInfo.Tests.ps1` (`Invoke-MgGraphRequest` and `Get-MgContext`),
  `Initialize-OPIMAuth.Tests.ps1` (`Connect-MgGraph`, `Connect-AzAccount`, `Get-AzContext`,
  `Get-AzAccessToken`, `Get-OPIMMsalApplication`) and `Disconnect-OPIM.Tests.ps1`
  (`Disconnect-MgGraph`, `Disconnect-AzAccount`).
- **To simulate a Graph error, throw what the wrapper throws** -- an `ErrorRecord` whose
  `FullyQualifiedErrorId` is the Graph error code -- with `$PSCmdlet.ThrowTerminatingError()`; the
  same pattern as for `Az.Resources` below.
- **Mock `Az.Resources` cmdlets with `-ModuleName Omnicit.PIM`.** To simulate a terminating error
  with a specific `FullyQualifiedErrorId`, use `$PSCmdlet.ThrowTerminatingError()` -- **not**
  `throw [ErrorRecord]`, which PowerShell re-wraps on catch, losing the original id. Pester's mock
  wrapper has `[CmdletBinding()]`, so `$PSCmdlet` is available:
  ```powershell
  Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest {
      $PSCmdlet.ThrowTerminatingError(
          [System.Management.Automation.ErrorRecord]::new(
              [System.Exception]::new('Policy validation failed: JustificationRule'),
              'RoleAssignmentRequestPolicyValidationFailed',
              [System.Management.Automation.ErrorCategory]::InvalidOperation,
              $null
          )
      )
  }
  ```
  `Write-Error -ErrorId ... -ErrorAction Stop` also works where the code reads the id with
  `.Split(',')[0]`.
- **Private functions** are called inside `InModuleScope Omnicit.PIM { ... }`. A public function's
  test needs only `-ModuleName Omnicit.PIM` on its mocks.
- **Reset module-scoped caches** in `BeforeEach` when the function under test uses them -- not as a
  blanket pattern:
  ```powershell
  BeforeEach {
      InModuleScope Omnicit.PIM {
          $script:_OPIMAuthState = $null
          $script:_OPIMMsalApp   = $null
          $script:_MyIDCache     = $null
      }
  }
  ```
- **Completer classes.** `InModuleScope { Mock ... }` does NOT intercept a call made from a class
  method, because the method body is bound to the module's runspace at class-load time. The
  completers therefore call `Get-OPIM*` through
  `& ([scriptblock]::Create('Get-OPIMDirectoryRole'))`, which resolves the command through the
  normal pipeline where a mock can intercept it -- **do not revert that to a direct call.** Mock
  with `-ModuleName` OUTSIDE `InModuleScope`, and instantiate and call the class INSIDE it, since a
  module's class types are not visible to the test scope:
  ```powershell
  It 'returns completion results' {
      Mock -ModuleName Omnicit.PIM Get-OPIMDirectoryRole { return $FakeData }
      InModuleScope Omnicit.PIM {
          $Completer = [DirectoryEligibleRoleCompleter]::new()
          $Result = $Completer.CompleteArgument(
              'Enable-OPIMDirectoryRole', 'RoleName', '', $null, @{})
          $Result | Should -Not -BeNullOrEmpty
      }
  }
  ```
- **A `Mock -ModuleName` covers only calls made from inside the module.** A command the test body
  calls itself runs for real unless it has its own test-scope `Mock`. Mocks do not cross
  `ForEach-Object -Parallel` runspaces either.
- **Known exception: `Wait-OPIMDirectoryRole`'s tests reach the REAL Graph transport.** Three of
  them (`tests/Unit/Public/Wait-OPIMDirectoryRole.Tests.ps1:52-55`, `:75-78`, `:111-119`) pipe a
  request that has not expired with `-Timeout 0`, so the cmdlet starts its
  `ForEach-Object -Parallel -AsJob` block. The polling loop's first Graph call is the real, unmocked
  `Invoke-MgGraphRequest` at `source/Public/Wait-OPIMDirectoryRole.ps1:101`, run inside a thread
  job, where no mock reaches. It fails -- and the tests pass -- only because the test process holds
  no Graph context. Until the planned transport tripwire lands, that is the rule: **never run the
  unit tests in a pwsh session that holds a Graph context** (after `Connect-MgGraph` or
  `Connect-OPIM`) -- start a fresh process. The `-PassThru` test is skipped for the same reason (its
  skip comment's "integration tests" do not exist in this repository).
- **Pin `-ErrorAction` on any call whose non-terminating error the test observes or has to
  survive.** Module code reads the GLOBAL `$ErrorActionPreference`, which the workflow's
  `shell: pwsh` steps and many operator profiles set to Stop, and a test-local
  `$ErrorActionPreference` does not pin it. Capture errors with
  `-ErrorVariable Errors -ErrorAction SilentlyContinue`; never use `Should -Throw` for an API error
  from a public function, which emits non-terminating errors.
- **Test `-WhatIf` by invocation count**, not by catching an exception:
  `Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It`.
- **`Should -Invoke -Times N` is AT LEAST N for `N >= 1` -- add `-Exactly`.** `-Times 0` already
  means exactly zero: Pester implies `-Exactly` at zero (Pester 6.2.0, `Pester.psm1:17761`,
  `($Exactly -or ($Times -eq 0))`). Do not "fix" a bare `-Times 0`.
- **Never write the word "because" inside a `-Because` string.** Pester deletes EVERY occurrence of
  `because` plus the whitespace after it from the rendered message (Pester 6.2.0,
  `Pester.psm1:14345`), so the failure reads as scrambled prose. Use "since", or restructure.
- **Test data:** typed `PSCustomObject` input carrying the module's type names
  (`Omnicit.PIM.DirectoryEligibilitySchedule`, `Omnicit.PIM.AzureEligibilitySchedule`,
  `Omnicit.PIM.GroupEligibilitySchedule`), PascalCase variables, `contoso`/`fabrikam` for any
  tenant label, and an assertion on the output type tag rather than on a raw hashtable. Durations
  in a request body are ISO 8601 (`PT1H`).
- **A transport tripwire is planned, not yet in this repository.** In Omnicit.EntraRBAC every unit
  test file installs one that records and refuses any unmocked call reaching the SDK transport.
  Here nothing catches a missing mock yet except review -- or a test that hangs on a browser
  prompt -- and the `Wait-OPIMDirectoryRole` exception above stays open until it lands.

---

## SECURITY (Hard Rules - High Privilege)

This module activates **privileged Entra ID directory roles, Azure resource roles and PIM group
memberships** for the signed-in user. These rules are non-negotiable:

1. **Claude never makes live calls against a customer tenant, and CI never authenticates to a
   tenant.** Live verification happens only in the operator's designated test tenant, only as a
   dedicated test identity -- never with the operator's own account -- and only when the operator
   has asked for that run.
2. **Every unit test mocks authentication and the transport at the module boundary**:
   `Initialize-OPIMAuth` always, `Invoke-OPIMGraphRequest` for Graph, the `Az.Resources` cmdlets
   for Azure, and the raw SDK calls only where a function makes them directly (see **Testing
   Conventions**). Nothing in CI or tests authenticates. One known exception reaches the
   transport: `Wait-OPIMDirectoryRole`'s tests run a real `Invoke-MgGraphRequest` in a thread job,
   which fails only because the test process holds no Graph context -- so never run the unit tests
   in a pwsh session that holds one; start a fresh process. The planned transport tripwire is what
   will close this.
3. **Every state change supports `-WhatIf` and `-Confirm`** via
   `[CmdletBinding(SupportsShouldProcess)]` -- every Enable- and Disable- cmdlet, and
   `Install`/`Set`/`Remove-OPIMConfiguration` (`ConfirmImpact = 'High'`).
4. **The module never activates more than the user asked for.** An activation request names one
   eligibility -- one role definition at one scope for one principal, or one group and access type
   -- for the requested duration. A broader activation (another role, a wider scope, another group
   or access type, a longer duration, another tenant) is always a defect, never a feature; so is a
   deactivation the user did not ask for.
5. **Never log or write tokens.** `$script:_OPIMAuthState` holds no token, but tokens do live in
   the process: in the in-memory token cache of the MSAL application (`$script:_OPIMMsalApp`) and
   in the Graph SDK's context, which `Connect-MgGraph -AccessToken` receives as a SecureString.
   Never write either object out, log it or put it in an error record. Never write an access
   token, a refresh token or an `Authorization` header to output, to a verbose or debug stream, to
   a file or to a test fixture, and never print or persist an error record from a failed request
   (see **Error Handling**).

---

## Language

All code, comment-based help, and command output must be in **English**. Chat and communication
with the team may be in Swedish.

---

## Dependencies

| Module | Version | Used for |
|---|---|---|
| `Az.Resources` | 9.0.3 | Azure RBAC PIM (`Get`/`Enable`/`Disable-OPIMAzureRole`) |
| `Microsoft.Graph.Authentication` | 2.36.0 | `Connect-MgGraph -AccessToken`, `Invoke-MgGraphRequest` (inside the wrapper), and the MSAL assembly `Get-OPIMMsalApplication` reflects into |

The manifest declares both as `RequiredModules` (`source/Omnicit.PIM.psd1:54-57`), where a
`ModuleVersion` is a FLOOR, never an exact pin. `RequiredModules.psd1` (`:33-34`) pins the same two
versions EXACTLY for the build, the tests and the workflow's package and publish installs, which
read them from that file and refuse a missing or `latest` value. Keep the two files equal; every
other entry in `RequiredModules.psd1` is build tooling and stays `latest`. `Az.Resources` 9.0.3 is
the floor -- not the 5.6.0 that older documents cite.

`Az.Accounts` is not declared; it is installed as a dependency of the `Az.Resources` package (the
build resolved 5.5.3 beside it on 2026-10-05). `Connect-AzAccount`, `Get-AzContext`,
`Get-AzAccessToken`, `Update-AzConfig` and `Disconnect-AzAccount` come from it.

Do not add other `Microsoft.Graph.*` SDK modules. The module intentionally uses raw
`Invoke-MgGraphRequest` (through `Invoke-OPIMGraphRequest`) to avoid typed SDK coupling and SDK
version drift.

---

## Checklist: Adding a New Function

1. **Create the file:** `source/Public/Verb-OPIMNoun.ps1` for a public function, or
   `source/Private/<FunctionName>.ps1` for a private helper (several, such as `Get-MyId` and
   `Resolve-RoleByName`, carry no OPIM prefix). Either way the filename must match the function
   name exactly. Declare it with `function`, not `filter` (see **Common Pitfalls**).
2. **If public:** add it to `FunctionsToExport` in `source/Omnicit.PIM.psd1`, declare any alias
   with `[Alias()]` on the function, and add the alias to `AliasesToExport` there.
3. **If tab completion is needed:** add an `IArgumentCompleter` class in `source/Classes/` that
   calls the `Get-OPIM*` cmdlet through `& ([scriptblock]::Create('...'))`, and cover it in
   `tests/Unit/Classes/ArgumentCompleters.Tests.ps1`.
4. **Call `Initialize-OPIMAuth`** as the first statement of the `begin` or `process` block of any
   function that calls Graph or Azure. Pass `-IncludeARM` for a function that calls `Az.Resources`.
5. **Route all Graph calls through `Invoke-OPIMGraphRequest`.** Never call `Invoke-MgGraphRequest`
   directly.
6. **Tag output:** convert the response to `[PSCustomObject]`, insert a type name, add a `<View>`
   in `source/Formats/Omnicit.PIM.Format.ps1xml` and, if ScriptProperty members are needed, a
   `<Type>` in `source/Formats/Omnicit.PIM.Types.ps1xml`.
7. **Add full comment-based help:** `.SYNOPSIS`, a `.DESCRIPTION` over 40 characters, one
   `.PARAMETER` per parameter, and at least one `.EXAMPLE` -- the QA gate checks all four.
8. **Add a unit test file:** `tests/Unit/{Public|Private}/<FunctionName>.Tests.ps1`. Import by
   module name in `BeforeAll`, and mock `Initialize-OPIMAuth` and `Invoke-OPIMGraphRequest` (the
   shapes are under **Testing Conventions**).
9. **Document a change to the shipped module** in `CHANGELOG.md`'s `[Unreleased]` section, in
   release-note voice -- replacing the close-out sentence if it still stands -- and the usage in
   `README.md` for a public cmdlet.
10. **Keep the file ASCII-only** and UTF-8 without BOM.
11. **Run `./build.ps1 -Tasks build`, then `./build.ps1 -Tasks test`,** before committing -- it is
    the authoritative gate.

---

## Common Pitfalls

- **`DefaultCommandPrefix` is absent** from the manifest, on purpose -- see **Code Style**.
- **`Write-CmdletError -Message` expects an `[Exception]`**, not a string. Wrap bare strings:
  `[System.Exception]::new('message')`.
- **The source psm1 is the dev-mode loader only.** ModuleBuilder replaces it during the build with
  a merged psm1. Initialization that must survive in the built module belongs in `suffix.ps1`, and
  is mirrored in the dev-mode psm1.
- **`FormatsToProcess` is active; `TypesToProcess` is intentionally empty.** `Remove-Module` does
  not clean type data, so `TypesToProcess` made a second `Import-Module -Force` fail with "member
  is already present". Types are loaded by a single
  `Update-TypeData -AppendPath ... -ErrorAction SilentlyContinue` in `suffix.ps1` (`:4`), mirrored
  in the dev-mode psm1 (`:37`).
- **Parallel runspaces need an explicit Graph import.** `Wait-OPIMDirectoryRole` calls
  `Import-Module 'Microsoft.Graph.Authentication'` inside `ForEach-Object -Parallel` (`:68`); any
  new parallel block must do the same. Module functions, mocks and `$script:` state are not
  available there.
- **`Invoke-MgGraphRequest` must run with `-Verbose:$false -ErrorAction Stop`** -- it suppresses
  SDK noise and makes the failure catchable. `Invoke-OPIMGraphRequest` does it for every caller; all
  new code calls the wrapper instead.
- **`ErrorRecord.ErrorDetails` requires `[ErrorDetails]::new()`** -- see **Error Handling**.
- **Never use bare `throw` in public functions** -- see **Error Handling**.
- **A local `$Filter` shadows the `-Filter` parameter** -- name it `$OdataFilter`.
- **PowerShell 7.2+ Core only** (`CompatiblePSEditions = @('Core')`). Do not suggest Windows
  PowerShell 5.x or Desktop-compatible code.
- **`Install-OPIMConfiguration` is create-only** and has no `-Force` parameter; do not add one back.
  An existing alias is updated with `Set-OPIMConfiguration`.
- **`Export-OPIMTenantMap` (private) owns the PSD1 serialization** -- call it from `Install`, `Set`
  and `Remove` instead of inlining the StringBuilder block.
- **The `-TenantMapPath` default is built from `$env:USERPROFILE`** in `Connect-OPIM`, the four
  `*-OPIMConfiguration` cmdlets and `Enable`/`Disable-OPIMMyRole`. That variable is set on Windows
  only, and this module is Core-only and cross-platform: never build a new path from it.
- **`Restore-GraphProperty` is a `filter`, not a `function`.** The QA gate enumerates commands with
  `-CommandType Function`, so a filter gets no unit-test-file or PSScriptAnalyzer check from it.
  Declare new commands with `function`.
- **A help line starting with `.word`** is parsed as a help keyword and silently wipes the whole
  comment-based help block. Reword it.
- **Never commit module code directly to `main`.** Always work on a feature branch and PR -- see
  **Branch Policy**.
