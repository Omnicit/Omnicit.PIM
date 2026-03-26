# Versioning & Development Workflow

This module uses [Semantic Versioning 2.0.0](https://semver.org) (SemVer) driven automatically by
[GitVersion](https://gitversion.net/) — **no manual version editing required**. The version is
derived entirely from the Git commit history and optional Git tags.

---

## Table of Contents

- [Semantic Versioning — What Each Part Means](#semantic-versioning--what-each-part-means)
- [Version Mode — ContinuousDelivery (ManualDeployment in v6)](#version-mode)
- [How Commit Messages Drive the Version](#how-commit-messages-drive-the-version)
- [Branch Strategy](#branch-strategy)
- [Pre-release vs Stable Releases](#pre-release-vs-stable-releases)
- [Step-by-Step Development Workflow](#step-by-step-development-workflow)
- [GitVersion v6 Migration Notes](#gitversion-v6-migration-notes)
- [Current Configuration Reference](#current-configuration-reference)

---

## Semantic Versioning — What Each Part Means

A version number takes the form **`MAJOR.MINOR.PATCH`**, e.g. `1.3.2`.

| Part | Increment when… | Example for this module |
|---|---|---|
| **MAJOR** | You introduce a **breaking change** — callers must update their code | Removing a parameter, renaming a function, changing output type |
| **MINOR** | You add **new functionality** in a backwards-compatible way | New `Enable-OPIM*` function, new `-Wait` switch, new PIM pillar support |
| **PATCH** | You make a **backwards-compatible bug fix** | Fixing a Graph API call, correcting error message text, deactivation bug fix |

> **Rule of thumb:** if a consumer of this module would need to change their scripts after updating,
> it is a **MAJOR** bump. If they get a new feature for free, it's a **MINOR** bump. Everything else
> is a **PATCH**.

---

## Version Mode

The module uses GitVersion's **ContinuousDelivery** mode
([docs](https://gitversion.net/docs/reference/modes/continuous-delivery)).

In this mode:

- Every commit on `main` produces a **pre-release** version (e.g. `0.2.0-preview0001`).
- The `preview0001` counter is the number of commits since the last Git tag (or the beginning of
  the repository if no tags exist yet).
- **Tags are optional** during day-to-day development, but creating a tag on a commit **promotes
  that specific commit to a stable release** (`0.2.0` with no pre-release suffix).
- The *next* version after a stable tag is calculated from the commit messages that follow.

### Reading a pre-release version

```
0.2.0-preview0003
│ │ │  └──────── 3 commits on main since the last tag (or repo start)
│ │ └─────────── PATCH  — no patch bump messages since last version point
│ └───────────── MINOR  — a feature/minor commit was found in history
└─────────────── MAJOR  — no breaking change commit found
```

---

## How Commit Messages Drive the Version

GitVersion scans commit messages. The **first matching rule wins** (top to bottom).

| Version bump | Pattern (case-insensitive) | Example commit messages |
|---|---|---|
| **MAJOR** | `breaking change`, `breaking`, `major` | `Breaking change: Remove -Hours parameter` |
| **MINOR** | `add`, `adds`, `feature`, `features`, `minor` | `Add Enable-OPIMMyRoles function` |
| **PATCH** | `fix`, `patch` | `Fix SelfDeactivate using wrong schedule ID` |
| **None** | `+semver: none` or `+semver: skip` | `Update README +semver: none` |

### Rules

1. The bump message is evaluated **at the time of the release**, scanning all commits since the
   last tag (or repo start). The highest bump found wins.
2. If **no** bump message is found in any commit, GitVersion falls back to a `PATCH` increment for
   `main` (default branch increment is `Patch`).
3. Adding `+semver: none` or `+semver: skip` anywhere in the message **suppresses** that commit from
   triggering any bump — useful for documentation changes, dependency updates, or CI tweaks.

### Examples

```
# Triggers a MINOR bump (0.2.0 → 0.3.0 at next tag)
Add Get-OPIMEntraIDGroup function

# Triggers a PATCH bump (0.2.0 → 0.2.1 at next tag)
Fix incorrect directoryScopeId used during SelfDeactivate

# Does NOT increment anything
Update README with new usage examples +semver: none

# Triggers a MAJOR bump (0.2.0 → 1.0.0 at next tag)
Breaking change: Rename -RoleName to -Name across all Enable/Disable cmdlets
```

> **Case-insensitive:** the patterns match regardless of capitalisation.
> `BREAKING CHANGE`, `Breaking Change`, and `breaking change` all trigger a MAJOR bump.

---

## Branch Strategy

### `main`

The primary branch. All completed work is merged here. Every commit on `main` produces a
pre-release build (`0.2.0-preview000N`).

### `feature/<name>` branches

Used for new features. Branch from `main`, do your work, then open a PR back to `main`.

- Pre-release label on builds from the branch: `<branch-name>` (e.g. `0.2.0-get-entra-group.1`)
- When merged into `main`, the commit message of the merge **determines the version bump**.
- Use a descriptive merge commit message: `Add Get-OPIMEntraIDGroup function`.

```
git checkout -b feature/get-entra-group
# ... make changes, commit ...
git push origin feature/get-entra-group
# open PR → GitHub merge commit message drives the bump
```

### `fix/<name>` or `hotfix/<name>` branches

Used for bug fixes. Branch from `main`.

- Pre-release label on builds from the branch: `fix` (e.g. `0.2.0-fix.1`)
- Merge commit message should contain `fix` or `patch`.

```
git checkout -b fix/selfdeactivate-schedule-id
# ... fix, commit: "Fix SelfDeactivate using wrong schedule ID" ...
# open PR to main
```

---

## Pre-release vs Stable Releases

| Scenario | Version produced | NuGet package version |
|---|---|---|
| Commit on `main`, no tags exist | `0.2.0-preview0003` | `0.2.0-preview0003` |
| Tag `v0.2.0` placed on a commit | `0.2.0` | `0.2.0` |
| New commit on `main` after `v0.2.0` tag (with fix message) | `0.2.1-preview0001` | `0.2.1-preview0001` |
| New commit on `main` after `v0.2.0` tag (with feature message) | `0.3.0-preview0001` | `0.3.0-preview0001` |

### Tagging a stable release

Creating a tag marks that exact commit as a stable, published version.

```powershell
# Tag the current HEAD as a stable release
git tag v0.2.0
git push origin v0.2.0
```

The Azure Pipeline's Deploy stage triggers automatically when a `v*` tag is pushed to `main`,
publishing the module to the PowerShell Gallery.

> **You do not need to tag for every commit.** Pre-release versions are fully functional and are
> deployed to testing environments automatically. Tag only when you are ready to publish a stable
> release to the Gallery.

---

## Step-by-Step Development Workflow

### Developing a new feature

```
1. git checkout -b feature/my-feature
2. Make changes, commit with: "Add <description of feature>"
3. git push origin feature/my-feature
4. Open a Pull Request → merge with commit message "Add <description>"
5. CI builds → produces 0.X.0-preview000N
6. When ready to release: git tag vX.Y.Z && git push origin vX.Y.Z
```

### Fixing a bug

```
1. git checkout -b fix/my-bug
2. Make changes, commit with: "Fix <description of bug>"
3. git push origin fix/my-bug
4. Open a Pull Request → merge with commit message "Fix <description>"
5. CI builds → produces 0.X.1-preview000N
```

### Releasing a stable version

```
1. Verify the pre-release build on main is correct
2. git tag v<major>.<minor>.<patch>   e.g.  git tag v0.2.0
3. git push origin v0.2.0
4. Pipeline Deploy stage runs → publishes to PowerShell Gallery + creates GitHub Release
```

### Documenting-only / CI-only changes

Add `+semver: none` or `+semver: skip` anywhere in the commit message:

```
Update CHANGELOG formatting +semver: none
```

---

## GitVersion v6 Migration Notes

The current configuration targets **GitVersion 5.x** (installed via
`dotnet tool install --global GitVersion.Tool --version 5.*` in the pipeline).

When upgrading to **v6**, the following changes to [GitVersion.yml](../GitVersion.yml) are
required:

| v5 config | v6 equivalent | Notes |
|---|---|---|
| `mode: ContinuousDelivery` | `deployment-mode: ManualDeployment` | Renamed — same behaviour |
| `tag:` (branch property) | `label:` | Renamed |
| `useBranchName` (magic string) | `{BranchName}` | Magic string replaced with placeholder |
| `continuous-delivery-fallback-tag` | Removed | No longer needed |
| `NuGetVersionV2` (output variable) | Removed | Use `SemVer` or `MajorMinorPatch` + `PreReleaseLabelWithDash` |

The `azure-pipelines.yml` uses `$gitVersionObject.NuGetVersionV2` as the `ModuleVersion`
environment variable passed to the build step. This **must be updated** to use `FullSemVer` or
`SemVer` when moving to v6.

Also update the pipeline install:
```yaml
# v5 (current)
dotnet tool install --global GitVersion.Tool --version 5.*

# v6
dotnet tool install --global GitVersion.Tool --version 6.*
```

### v6: `Mainline` strategy (replaces Mainline mode)

In v6, the old `mode: Mainline` no longer exists. Instead, a `strategies` array at the root level
enables equivalent behaviour if needed:

```yaml
# v6 equivalent of old Mainline mode
strategies:
  - Mainline
  - TaggedCommit
```

The current **ContinuousDelivery / ManualDeployment** setup is the recommended approach for
modules published to the PowerShell Gallery — pre-release builds are free-flowing, and stable
versions are controlled by tagging.

---

## Current Configuration Reference

Below is an annotated summary of [GitVersion.yml](../GitVersion.yml):

```yaml
mode: ContinuousDelivery          # Pre-release on every commit; tags mark stable releases

next-version: 0.0.1               # Starting floor if no tags and no bump messages found

# Commit message patterns — first match wins, case-insensitive
major-version-bump-message: '(breaking\schange|breaking|major)\b'
minor-version-bump-message: '(adds?|features?|minor)\b'
patch-version-bump-message: '\s?(fix|patch)'
no-bump-message: '\+semver:\s?(none|skip)'

branches:
  master:                         # Applies to 'main' branch (matched via regex below)
    tag: preview                  # Pre-release label: preview0001, preview0002, …
    regex: ^main$

  feature:
    increment: Minor              # Feature branches default to a MINOR bump
    tag: useBranchName            # Pre-release label taken from the branch name

  hotfix:
    increment: Patch              # Hotfix branches default to a PATCH bump
    tag: fix
```
