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
- **PowerShell 7.4+, Core only.** Do not build a new path from `$env:USERPROFILE` -- it is set on
  Windows only, and this module targets `CompatiblePSEditions = 'Core'`.

## Source file rules

- **One function per file, and the filename must equal the function name** --
  `source/Public/Verb-OPIMNoun.ps1` for an exported cmdlet, or `source/Private/<FunctionName>.ps1`
  for an internal helper.
- **Public functions are listed explicitly in `FunctionsToExport`** in `source/Omnicit.PIM.psd1`
  -- never `*`.
- **Every `.ps1`, `.psd1`, `.psm1` and `.ps1xml` file under `source/` and `tests/` is UTF-8
  without BOM and ASCII-only.** No em-dashes, no smart quotes, no box-drawing characters. Use `--`
  for an em-dash and straight quotes only. `tests/QA/sourcehygiene.tests.ps1` fails the test run on
  a BOM or a non-ASCII byte in any of them. See `CLAUDE.md` "CRITICAL: ASCII-Only Source Files".
- **PSScriptAnalyzer must report zero findings per function file.** A targeted suppression is only
  acceptable with a `Justification` string, for a known false positive -- never to hide a real
  finding.

## Tests

- **Tests are written in Pester 5 syntax**, one `*.Tests.ps1` file per source file under
  `tests/Unit/{Classes,Private,Public}/` -- except the six completer classes, which share
  `tests/Unit/Classes/ArgumentCompleters.Tests.ps1`. The build resolves the newest Pester. The QA
  gate requires a unit test file for every function the module defines.
- **Open every unit test file with the root form** from `CLAUDE.md` "Testing Conventions" -- copy
  the block from there. Its root `BeforeAll` imports the module by name, not by path (importing by
  path breaks the Sampler coverage measurement, which targets the built module), and then installs
  the transport tripwire; its root `AfterAll` checks the tripwire and removes it.
  `tests/QA/testhygiene.tests.ps1` fails a unit test file that does not wire the tripwire in that
  way.
- **Mock at the module boundary**, with `Mock -ModuleName Omnicit.PIM`: `Initialize-OPIMAuth` in
  every test that touches auth, Graph, or Azure, and the module's own transports --
  `Invoke-OPIMGraphRequest` for Graph and `Invoke-OPIMArmRequest` for Azure -- rather than the
  `Invoke-MgGraphRequest` or `Invoke-WebRequest` call beneath them (`Invoke-WebRequest` is mocked
  only in the ARM transport's own test file). The module calls no Az command, so mock none:
  ```powershell
  Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
  Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest { @{ value = @() } }
  Mock -ModuleName Omnicit.PIM Invoke-OPIMArmRequest { [pscustomobject]@{ value = @() } }
  ```
  Nothing in CI or in tests authenticates for real. A missing mock is caught by the transport
  tripwire: it records and refuses any unmocked call that reaches a real transport command, such
  as `Invoke-MgGraphRequest`, AzAuth's `Get-AzToken` or `Invoke-WebRequest`, and fails the test
  file. Inside a `ForEach-Object -Parallel` block, where no mock reaches, register a stand-in
  response instead. Run the tests in a fresh pwsh process. See `CLAUDE.md` "Testing Conventions".

## Everything else

Error handling, the Graph transport wrapper, authentication, argument completion, and the
CHANGELOG/version mechanics each have their own rules in `CLAUDE.md`. Read the section that
matches what you are touching before you touch it.
