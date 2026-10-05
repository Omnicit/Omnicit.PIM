# Contributing to Omnicit.PIM

This is a short pointer, not a restatement. The full rules live in
[`CLAUDE.md`](../CLAUDE.md) at the repository root -- read it before your first PR. Below are the
rules an outside contributor is most likely to trip over.

## First clone

```powershell
./build.ps1 -ResolveDependency -Tasks noop
```

If that fails with `Requested value 'V2' was not found` (a PSResourceGet compatibility error), add
`-UseModuleFast`:

```powershell
./build.ps1 -ResolveDependency -Tasks noop -UseModuleFast
```

## Before you open a PR

- **Never commit directly to `main`.** The server rejects a direct push. Branch first -- `fix/`,
  `feat/`, `test/`, `docs/`, `chore/`, `refactor/`, or `ci/` -- and open a PR. See `CLAUDE.md`
  "Branch Policy".
- **Build, then test, in that order:**
  ```powershell
  ./build.ps1 -Tasks build
  ./build.ps1 -Tasks test
  ```
  The test task measures coverage against the module under `output/module/`, not against
  `source/` directly, so an unbuilt change is measured stale. Build before every test run after
  changing source files.
- **A local build needs GitVersion 5 on `PATH`.** Without it the build falls back to the source
  manifest's placeholder version and the QA gate goes red. Do not set `$env:ModuleVersion` by hand.
  See `CLAUDE.md` "Build and Test Commands".
- **80 percent code coverage is a hard floor**, enforced by the build.
- **CI runs the same two commands on three platforms.** Every pull request to `main` runs
  `./build.ps1 -ResolveDependency -Tasks build` and then `./build.ps1 -Tasks test` on Linux,
  Windows and macOS (`.github/workflows/build-and-test.yml`), and a fourth job, `package`,
  rehearses the publish without publishing. Those four checks are required to merge. Expect
  review once all four are green.
- **Keep version tokens out of commit messages, PR titles and PR bodies.** Every merge to `main`
  publishes a preview to the public PowerShell Gallery, and a version cannot be deleted from it
  once published. See `CLAUDE.md` "CHANGELOG and Version".
- **PowerShell 7.2+, Core only.** Do not build a new path from `$env:USERPROFILE` -- it is set on
  Windows only, and this module targets `CompatiblePSEditions = 'Core'`.

## Source file rules

- **One function per file, and the filename must equal the function name** --
  `source/Public/Verb-OPIMNoun.ps1` for an exported cmdlet, or `source/Private/<FunctionName>.ps1`
  for an internal helper.
- **Public functions are listed explicitly in `FunctionsToExport`** in `source/Omnicit.PIM.psd1`
  -- never `*`.
- **New files are UTF-8 without BOM and ASCII-only, and so is every new or edited line in an
  existing file.** No em-dashes, no smart quotes, no box-drawing characters. Use `--` for an
  em-dash and straight quotes only. Some older files still hold non-ASCII characters; a gate for
  this is planned, so review is what holds the rule until it lands.
- **PSScriptAnalyzer must report zero findings per function file.** A targeted suppression is only
  acceptable with a `Justification` string, for a known false positive -- never to hide a real
  finding.

## Tests

- **Tests are written in Pester 5 syntax**, one `*.Tests.ps1` file per source file under
  `tests/Unit/{Classes,Private,Public}/` -- except the six completer classes, which share
  `tests/Unit/Classes/ArgumentCompleters.Tests.ps1`. The build resolves the newest Pester. The QA
  gate requires a unit test file for every function the module defines.
- **Import the module by name, not by path**, in the root `BeforeAll`:
  ```powershell
  BeforeAll {
      Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
      Import-Module Omnicit.PIM -Force
  }

  AfterAll {
      Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
  }
  ```
  Importing by path breaks the Sampler coverage measurement, which targets the built module.
- **Mock at the module boundary**, with `Mock -ModuleName Omnicit.PIM`: `Initialize-OPIMAuth` in
  every test that touches auth, Graph, or Azure, and the module's own transport wrapper,
  `Invoke-OPIMGraphRequest`, rather than the `Invoke-MgGraphRequest` call beneath it. Mock the
  `Az.Resources` cmdlets the same way for Azure:
  ```powershell
  Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
  Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest { @{ value = @() } }
  ```
  Nothing in CI or in tests authenticates for real. Never run the unit tests in a pwsh session
  that already holds a Graph context (after `Connect-MgGraph` or `Connect-OPIM`) -- start a fresh
  process. A transport tripwire that fails a test reaching the real transport is planned, not yet
  in this repository; until it lands, review is what catches a missing mock. See `CLAUDE.md`
  "Testing Conventions".

## Everything else

Error handling, the Graph transport wrapper, authentication, argument completion, and the
CHANGELOG/version mechanics each have their own rules in `CLAUDE.md`. Read the section that
matches what you are touching before you touch it.
