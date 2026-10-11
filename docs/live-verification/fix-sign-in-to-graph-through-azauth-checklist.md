# Live verification checklist -- Microsoft Graph signs in through AzAuth, with the newest Microsoft.Graph.Authentication and with the floor (fix/sign-in-to-graph-through-azauth)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

Where a check says **Record:** instead of **Expect:**, the outcome is genuinely not known in
advance. Write down what actually happened rather than what looked plausible.

**This file runs only in the operator's designated test tenant** -- never a customer tenant -- and
only when the operator has asked for the run. The module runs there as the dedicated delegated test
user `opim-s2-live-user`, and the sweep and the fixture's teardown run as the dedicated app identity
`oer-live-cc`, whose only credential is a certificate; neither is ever the operator's own account.
The run writes to nothing outside the prefix `opim-s2-` (the sprint's fixture, whose eligibilities
this file activates and which section 4 tears down) and `opim-s27-` (this step's own objects, of
which there are none), with one named exception: the teardown removes the test user's membership in
the group `Exclude from CA` (decision P-10 (a)), which carries no prefix. Check 0.1 proves the
identity before any other check calls the module. If a browser window or a sign-in prompt appears
mid-run, STOP and run check 0.1 again: in this file every sign-in is a device code, and the proof of
0.1 holds only for the sign-in it checked.

**Two windows, never one process** (decision A10 of Sprint 1, kept in Sprint 2). Window A runs as
`oer-live-cc`, or with no identity, and reads files without the module. Window B runs the branch's
build as the test user, in a `pwsh -NoProfile`. **Window B runs twice, each time a fresh process:**
run L with the newest Microsoft.Graph.Authentication on the PowerShell Gallery, imported AFTER AzAuth
2.9.0, and run F with the floor, Microsoft.Graph.Authentication 2.36.0, imported BEFORE AzAuth. Both
take the module's dependencies from this step's raw folder, never from the profile. Every block in
sections 0 to 3 runs once in each run, and its Result holds both. Every block below names its window.

**No block prints a scope id, an object id, a tenant id, a sign-in name, a device code or a message
that holds one.** The blocks print counts, statuses, error ids, versions, display names of the
fixture's roles, group and resource groups, seconds and True/False.

## What changed and why this needs a live tenant

- **A. Microsoft Graph signs in through AzAuth** ("fix: sign in to Microsoft Graph through AzAuth and
  drop the module's own MSAL client"). The Graph token now comes from AzAuth's `Get-AzToken`, for the
  Microsoft Graph Command Line Tools client and the module's six scopes, as Omnicit.EntraRBAC signs in
  (decision A16), and the module builds no MSAL client of its own: 0.7.0 failed to build it with a
  Microsoft.Graph.Authentication newer than 2.36.0 beside AzAuth. A mock cannot show that AzAuth
  returns a token Microsoft Graph accepts for those scopes, with the newest SDK and with the floor,
  in either import order (sections 0 and 1).
- **B. Every device code request makes AzAuth build a new credential** (EntraRBAC's rule A17, the
  same commit). So each sign-in prints a new code, and the codes are counted: one for Microsoft Graph
  and one for Azure Resource Manager (0.1, 2.2, 3.2).
- **C. What the module keeps** (the same commit, and "test: prove the step-up, the renewal and the
  device code flow through AzAuth", "test: prove the device code of a renewal and a retry, and pin the
  kept error ids exactly"): the cached return for the same tenant, account and cloud with more than
  five minutes left (2.1), and the refusal of a Graph SDK session the module did not connect (3.1).
- **D. The gates and the documentation** ("test: refuse MSAL reflection and prove the sign-in path
  with each Graph SDK", "docs: describe the Microsoft Graph sign-in through AzAuth", "docs: say in the
  release notes that Microsoft Graph signs in through AzAuth", "docs: name only the commands that sign
  in, in the 0.7.1 release note", "docs: say that a token Azure rejects signs in to both again", "test:
  pin the using namespace shape of the MSAL pass and the string Account of the state", "docs: say that
  a token Azure rejects signs in to both, and qualify what AzAuth does", "docs: re-measure three line
  references in CLAUDE.md after the help edits"). No live effect; see the next
  section.
- **E. The fixture's teardown** (step 7, scope 6). Section 4 removes the sprint's fixture, recreated
  for this step, with `Initialize-OpimS2Prereq.ps1 -Teardown` as `oer-live-cc`.

The mapping to the step's specification: its S.x is S.4, its 0.x is 0.1, its 1.x is section 1, its 2.x
is section 2, its 3.x is section 3 and its 4.x is section 4; "everything twice" is run L and run F, and
G8 is 1.3 and 1.5.

The fixture of Sprint 2 (decision A15), recreated for this step by the session `opim-s2-fixtur2`, is
used as it stands until section 4 removes it: the test user `opim-s2-live-user`, the group
`opim-s2-grp` (eligible as member), the resource groups `opim-s2-rg` and `opim-s2-rg2` (Reader
eligible on each), and the directory roles Usage Summary Reports Reader and Message Center Privacy
Reader. Every activation passes a justification, which the fixture's policies require. This step
creates no object in the tenant. The run's tenant map and module folders live in the raw folder and
are deleted with it.

## What this file does not check, and why

Class B, each proven by the tests named:

- **An authentication context step-up through AzAuth** -- the fixture's PIM policies ask for no
  authentication context, and one that did would be a STOP. `tests/Unit/Private/Initialize-OPIMAuth.Tests.ps1`
  (the step-up contexts) and `tests/Unit/Private/Invoke-OPIMGraphRequest.Tests.ps1`.
- **A renewal near the token's expiry, and the retry after Microsoft Graph rejects a token** -- a run
  would have to wait out a token's lifetime, and a rejection cannot be provoked.
  `tests/Unit/Private/Initialize-OPIMAuth.Tests.ps1`.
- **The interactive (browser) sign-in** -- the harness completes device codes only. The clean-process
  test in `tests/QA/module.tests.ps1` drives the browser path to a stand-in `Get-AzToken` with the
  floor and the newest Graph SDK, in both import orders, and the C-check after the merge covers it
  live (below).
- **The sovereign clouds and `AZURE_AUTHORITY_HOST` around the Graph sign-in** -- decision P-12.
  `tests/Unit/Private/Initialize-OPIMAuth.Tests.ps1`.
- **No MSAL reflection is left in the source** -- `tests/QA/sourcehygiene.tests.ps1` (Describe 'MSAL
  reflection'). S.1 reads the build for the same fact.
- **A device code sign-in to a tenant that is not the account's home tenant** (a guest account) -- the
  test tenant is the test user's home tenant, and no second tenant or guest identity exists for this
  run (G1). The module's tenant lock refuses a token issued for another tenant than the one asked for
  (`TenantMismatch`, `tests/Unit/Private/Initialize-OPIMAuth.Tests.ps1`), so the risk is a refused
  sign-in, never one in the wrong tenant; whether AzAuth's device code path honours `-Tenant` for a
  guest is not known.
- **The C-check after the merge** -- the operator runs `Connect-OPIM -IncludeARM` with the published
  preview and the operator's own Microsoft Graph SDK, and activates nothing. It runs after the merge
  and is no box here.

## Setup, once

The operator sets `OPIMLIVE_HOME` in both windows to the notes folder that holds the `OpimLive`
folder, and in window B `OPIMLIVE_PREFIX` to `opim-s2-` and `OPIMS27_RUN` to `L` or `F`; no
checklist holds the path. The test user's sign-in name and the test tenant's id are read by the
harness through OerLive and are never printed. Both windows run from the root of the step's
worktree. Raw output, the run's tenant map and the module folders go to
`docs/live-verification/raw/opim-s27` (git-ignored), which is deleted once the results are written up.

A block that runs the module in window B starts with the three-line prologue of the template.

### S.1. Find the build under test and tie it to the branch head

- [x] **S.1** Window A (no module). The newest build in `output/module/Omnicit.PIM/` was made after the branch head was committed, it signs in to Microsoft Graph through AzAuth and holds no MSAL client, and the raw folder is git-ignored.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$HeadTime = [datetimeoffset]::Parse((git log -1 --format=%cI))
"Branch head: $(git log -1 --format='%h %s')"
"Built version folder: $($Built.Directory.Name)"
"Built after the branch head was committed: $([datetimeoffset]$Built.LastWriteTime -gt $HeadTime)"
$Tracked = @(git status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0) { throw "git status exited with $LASTEXITCODE, so the working tree could not be read; repair the clone before any check below." }
"Tracked changes in the working tree: $($Tracked.Count)"
$Psm1 = Join-Path $Built.DirectoryName 'Omnicit.PIM.psm1'
"The built module defines Get-OPIMMsalApplication: $([bool](Select-String -LiteralPath $Psm1 -Pattern 'function Get-OPIMMsalApplication' -SimpleMatch -Quiet))"
"The built module names Microsoft.Identity.Client: $([bool](Select-String -LiteralPath $Psm1 -Pattern 'Microsoft.Identity.Client' -SimpleMatch -Quiet))"
"The built module asks AzAuth for the Microsoft Graph token: $([bool](Select-String -LiteralPath $Psm1 -Pattern 'ClientId\s+=\s+\$GraphClientId' -Quiet))"
$Raw = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s27'
$null = New-Item -ItemType Directory -Force -Path $Raw
git check-ignore -q $Raw
"The raw folder is git-ignored: $($LASTEXITCODE -eq 0)"
```

**Expect:** the branch head's hash and subject; the version folder; `Built after the branch head was
committed: True`; `Tracked changes in the working tree: 0`; `defines Get-OPIMMsalApplication: False`;
`names Microsoft.Identity.Client: False`; `asks AzAuth for the Microsoft Graph token: True`; `The raw
folder is git-ignored: True`.
**Failure looks like:** `False` on the third line or a tracked change -- build again before any check
below. An MSAL line `True` -- the build is not this branch's: build again. `False` on the raw folder --
STOP: the tenant map would be tracked.

Result: 2026-10-11 14:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
14:33 UTC on 707b326, window A (no module): Branch head: 707b326 (docs: re-measure three line references in CLAUDE.md after the help edits); Built version folder: 0.7.1; Built after the branch head was committed: True; Tracked changes in the working tree: 0; The built module defines Get-OPIMMsalApplication: False; The built module names Microsoft.Identity.Client: False; The built module asks AzAuth for the Microsoft Graph token: True; The raw folder is git-ignored: True. The build is the one the final gate made on 707b326 (resolve, build, test: 3,679 passed, 0 failed, 0 skipped).
```

### S.2. The module folders of the step

- [x] **S.2** Window A (no module, no identity). AzAuth 2.9.0 and Microsoft.Graph.Authentication 2.36.0 are copied from the build's own dependencies, and the newest Microsoft.Graph.Authentication is saved from the PowerShell Gallery, all into the raw folder; nothing is imported and nothing goes to the profile.

```powershell
$Modules = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s27/modules'
$null = New-Item -ItemType Directory -Force -Path $Modules
foreach ($Pin in 'AzAuth/2.9.0', 'Microsoft.Graph.Authentication/2.36.0') {
    $Target = Join-Path $Modules $Pin
    if (-not (Test-Path -LiteralPath $Target)) {
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target)
        Copy-Item -LiteralPath (Join-Path (Get-Location).Path "output/RequiredModules/$Pin") -Destination $Target -Recurse
    }
}
Save-PSResource -Name 'Microsoft.Graph.Authentication' -Repository PSGallery -Path $Modules -TrustRepository -SkipDependencyCheck -ErrorAction Stop
$Graph = @(Get-ChildItem -LiteralPath (Join-Path $Modules 'Microsoft.Graph.Authentication') -Directory | Sort-Object { [version]$_.Name } | ForEach-Object Name)
"AzAuth folders: $(@(Get-ChildItem -LiteralPath (Join-Path $Modules 'AzAuth') -Directory | ForEach-Object Name) -join ', ')"
"Microsoft.Graph.Authentication folders: $($Graph -join ', ')"
"The newest is at least 2.41.1: $([version]$Graph[-1] -ge [version]'2.41.1')"
"Modules loaded in this window: $(@(Get-Module -Name 'AzAuth', 'Microsoft.Graph.Authentication', 'Omnicit.PIM').Count)"
```

**Expect:** `AzAuth folders: 2.9.0`; two Graph folders, `2.36.0` and the newest; `The newest is at
least 2.41.1: True`; `Modules loaded in this window: 0`.
**Record:** the newest version.
**Failure looks like:** an error from `Save-PSResource` -- the Gallery cannot be reached: STOP run L
until it can. `False` -- record the version; run L still tests the newest one there is.

Result: 2026-10-11 13:56 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
13:55 UTC, window A (no module, no identity): AzAuth folders: 2.9.0; Microsoft.Graph.Authentication folders: 2.36.0, 2.41.1 (2.36.0 and AzAuth copied from the build's own dependencies, 2.41.1 saved from the PowerShell Gallery with Save-PSResource, the newest there today); The newest is at least 2.41.1: True; Modules loaded in this window: 0.
```

### S.3. Window B loads the dependencies of its run

- [x] **S.3** Window B, a fresh `pwsh -NoProfile`, before anything else runs in it, once per run. Run L loads AzAuth 2.9.0 and then the newest Microsoft.Graph.Authentication; run F loads Microsoft.Graph.Authentication 2.36.0 and then AzAuth 2.9.0. No Az module is loaded, and `AZURE_AUTHORITY_HOST` is not set.

```powershell
$Run = $env:OPIMS27_RUN
if ($Run -notin 'L', 'F') { throw 'Set OPIMS27_RUN to L or F first.' }
$Modules = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s27/modules'
$AzAuth = Join-Path $Modules 'AzAuth/2.9.0/AzAuth.psd1'
$Folders = @(Get-ChildItem -LiteralPath (Join-Path $Modules 'Microsoft.Graph.Authentication') -Directory | Sort-Object { [version]$_.Name })
$Folder = if ($Run -eq 'L') { $Folders[-1] } else { $Folders | Where-Object Name -EQ '2.36.0' }
$Graph = Join-Path $Folder.FullName 'Microsoft.Graph.Authentication.psd1'
if ($Run -eq 'L') { Import-Module $AzAuth; Import-Module $Graph } else { Import-Module $Graph; Import-Module $AzAuth }
"Run $Run, imported $(if ($Run -eq 'L') { 'AzAuth, then Microsoft.Graph.Authentication' } else { 'Microsoft.Graph.Authentication, then AzAuth' })"
"AzAuth loaded: $(@(Get-Module AzAuth | ForEach-Object Version) -join ', ') from the raw folder: $((Get-Module AzAuth).ModuleBase.StartsWith($Modules))"
"Microsoft.Graph.Authentication loaded: $(@(Get-Module Microsoft.Graph.Authentication | ForEach-Object Version) -join ', ') from the raw folder: $((Get-Module Microsoft.Graph.Authentication).ModuleBase.StartsWith($Modules))"
"Az modules loaded: $(@(Get-Module -Name 'Az', 'Az.*').Count)"
"AZURE_AUTHORITY_HOST is set: $(Test-Path -LiteralPath 'Env:AZURE_AUTHORITY_HOST')"
"PowerShell: $($PSVersionTable.PSVersion)"
```

**Expect:** run L: `AzAuth loaded: 2.9.0 ... True`, `Microsoft.Graph.Authentication loaded:` the newest
of S.2 `... True`; run F: `2.9.0 ... True` and `2.36.0 ... True`; both runs `Az modules loaded: 0`,
`AZURE_AUTHORITY_HOST is set: False`, `PowerShell:` 7.4 or later.
**Failure looks like:** another version, two versions of one module, or `False` on a raw-folder line
-- end the window and start a fresh one. `AZURE_AUTHORITY_HOST is set: True` -- STOP: clear it in a
fresh window first.

Result: 2026-10-11 14:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run L, 14:34 UTC, window B-L (a fresh pwsh -NoProfile): imported AzAuth, then Microsoft.Graph.Authentication; AzAuth loaded: 2.9.0 from the raw folder: True; Microsoft.Graph.Authentication loaded: 2.41.1 from the raw folder: True; Az modules loaded: 0; AZURE_AUTHORITY_HOST is set: False; PowerShell: 7.6.6. Run F, 14:43 UTC, window B-F (a fresh pwsh -NoProfile): imported Microsoft.Graph.Authentication, then AzAuth; AzAuth loaded: 2.9.0 from the raw folder: True; Microsoft.Graph.Authentication loaded: 2.36.0 from the raw folder: True; Az modules loaded: 0; AZURE_AUTHORITY_HOST is set: False; PowerShell: 7.6.6.
```

### S.4. The fixture is in place, and nothing carries the step's prefix

- [x] **S.4** Window A, as `oer-live-cc`. The prerequisite script with `-WhatIf` finds every object of the fixture and would write nothing, and no object carries the prefix `opim-s27-`.

```powershell
$Prereq = Join-Path $env:OPIMLIVE_HOME 'Initialize-OpimS2Prereq.ps1'
# A child process, so its host output -- the What if lines included -- arrives here as text.
$Lines = @(pwsh -NoProfile -NonInteractive -File $Prereq -WhatIf 2>&1 | ForEach-Object { ([string]$_) -replace '\x1b\[[0-9;]*m', '' })
"Lines 'exists; kept': $(@($Lines | Where-Object { $_ -match 'exists; kept' }).Count)"
"What if lines other than the transcript: $(@($Lines | Where-Object { $_ -match '^What if:' -and $_ -notmatch 'transcript' }).Count)"
$Lines | Where-Object { $_ -match "Sweep 'opim-s|Residue:|Group 'Exclude from CA'|PIM policy of|exists; kept" }
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$null = Import-OerLiveConfig -Prefix 'opim-s27-'
Connect-OerLive -Graph
"Objects with the prefix opim-s27-: $(@(Find-OerLivePrefixed -Prefix 'opim-s27-' -ThrowOnUnread -Quiet).Count)"
Disconnect-OerLive
```

**Expect:** `Lines 'exists; kept': 10`; `What if lines other than the transcript: 0`; the sweeps
`opim-s1-` 0 and `opim-s2-` 1 user, 1 group, 0 other; every PIM policy line without approval or
authentication context and with a justification on activation; `Objects with the prefix opim-s27-: 0`.
**Failure looks like:** any `What if:` line that would create an object, a count other than 10, or a
prefixed object that is not the fixture's -- STOP: create nothing and ask for nothing. A 401 or 403
-- STOP (G6).

Result: 2026-10-11 13:56 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
13:55 UTC, window A as oer-live-cc: Lines 'exists; kept': 10; What if lines other than the transcript: 0. Sweep 'opim-s1-': 0; sweep 'opim-s2-': test user 1, test group 1, other prefixed objects 0. Group 'Exclude from CA': found 1, not role-assignable, not dynamic, oer-live-cc may write its members. Every PIM policy (both directory roles, the group member, Reader on opim-s2-rg and opim-s2-rg2): approval required False, authentication context False, on activation Justification. Residue: 4 rows, 2 from a run without the prefix opim-s2, not touched. Every oer-live-cc identity line True. Objects with the prefix opim-s27-: 0.
```

### S.5. The harness loads in window B

- [x] **S.5** Window B, once per run, after S.3. OerLive is 1.0.3, OpimLive is 1.0.5, the harness reads the test values through it, and the TOTP implementation reproduces RFC 6238.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME 'OpimLive/OpimLive.psm1') -Force
$Target = Get-OpimLiveTarget
"OerLive version: $((Get-OerLiveState).Version)"
"OpimLive version: $(& (Get-Module OpimLive) { $script:OpimLiveVersion })"
"Test user and tenant read (values hidden): $([bool]$Target.UserPrincipalName -and [bool]$Target.TenantId)"
"TOTP self-test: $(Get-OpimLiveTotp -SelfTest)"
"Dependencies still the run's: AzAuth $(@(Get-Module AzAuth | ForEach-Object Version) -join ', '); Microsoft.Graph.Authentication $(@(Get-Module Microsoft.Graph.Authentication | ForEach-Object Version) -join ', ')"
```

**Expect:** `OerLive version: 1.0.3`; `OpimLive version: 1.0.5`; the next two lines `True`; the
dependencies of S.3, one version each.
**Failure looks like:** `False` on the self-test -- STOP: the harness would enter wrong codes. A
second version of a dependency -- end the window and start a fresh one.

Result: 2026-10-11 14:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run L 14:34 UTC and run F 14:43 UTC, each in its own window B: OerLive version: 1.0.3; OpimLive version: 1.0.5; Test user and tenant read (values hidden): True; TOTP self-test: True; Dependencies still the run's: run L AzAuth 2.9.0 and Microsoft.Graph.Authentication 2.41.1, run F AzAuth 2.9.0 and Microsoft.Graph.Authentication 2.36.0, one version each.
```

### 0. Preparation

### 0.1. Identity check, and the codes of a first sign-in

- [x] **0.1** Window B, each run. `Connect-OpimLiveUser -IncludeARM` signs the build in to Microsoft Graph and Azure with one device code each, both through AzAuth; the account is the test user, the tenant the test tenant, and the ARM token the test user's in the test tenant; the module built no MSAL client; no Az module is loaded.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
"Run $($env:OPIMS27_RUN) -- AzAuth $(@(Get-Module AzAuth | ForEach-Object Version) -join ', '); Microsoft.Graph.Authentication $(@(Get-Module Microsoft.Graph.Authentication | ForEach-Object Version) -join ', ')"
$Target = Get-OpimLiveTarget
$Sign = Connect-OpimLiveUser -IncludeARM -RawFolder 'docs/live-verification/raw/opim-s27'
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
"Device codes: $(@($Sign.Codes).Count)"
$Module = Get-Module Omnicit.PIM
$State = & $Module { $script:_OPIMAuthState }
"Session tenant is the test tenant: $([string]::Equals([string]$State.TokenTenantId, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
"Session cloud: $($State.Environment); device code mode: $($State.DeviceCode); ARM token held as a SecureString: $($State.ArmToken -is [securestring]); minutes left: Graph $([int]($State.GraphTokenExpiry - [datetime]::UtcNow).TotalMinutes), ARM $([int]($State.ArmTokenExpiry - [datetime]::UtcNow).TotalMinutes)"
"The module has an MSAL helper: $([bool](& $Module { Get-Command -Name 'Get-OPIMMsalApplication', 'Invoke-OPIMDeviceCodeAuth' -CommandType Function -ErrorAction Ignore }))"
"The module holds an MSAL application: $([bool](& $Module { Get-Variable -Name '_OPIMMsalApp*' -Scope Script -ErrorAction Ignore }))"
$Msal = foreach ($Context in [System.Runtime.Loader.AssemblyLoadContext]::All) { foreach ($Assembly in $Context.Assemblies) { if ($Assembly.GetName().Name -eq 'Microsoft.Identity.Client') { '{0} in {1}' -f $Assembly.GetName().Version, $Context.Name } } }
"MSAL copies loaded in the process (recorded): $(@($Msal) -join '; ')"
"Az modules loaded: $(@(Get-Module -Name 'Az', 'Az.*').Count)"
```

**Expect:** the dependencies of S.3; the rows `Graph Information True ok` and `AzureCli Information
True ok`; `Device codes: 2`; every True/False line of the harness `True`; `Session tenant is the test
tenant: True`; `Session cloud: Global; device code mode: True`, `True`, minutes above 5 for both;
`The module has an MSAL helper: False`; `The module holds an MSAL application: False`; `Az modules
loaded: 0`. No line prints the account or the tenant id.
**Record:** the MSAL copies loaded in the process (AzAuth's and the Graph SDK's own, which the module
does not use).
**Failure looks like:** an error that names `Microsoft.IdentityModel.Abstractions` or a failed MSAL
build -- the defect of 0.7.0 is still there: a defect within this step's scope (G11). `False` on any
other line, a `STOP`, or a row that is not `ok` -- STOP: run `Disconnect-OPIM`, end window B and run
no other check. An ARM token whose tenant or user is not the test user's is a STOP even though the
module refused it (the harness signed in wrong).

Result: 2026-10-11 14:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run L, 14:34 UTC (28 s): AzAuth 2.9.0; Microsoft.Graph.Authentication 2.41.1. Harness: Disconnect-OPIM and Disconnect-MgGraph ran first; the Graph code and then the AzAuth code were completed in Edge; rows Graph Information True ok and AzureCli Information True ok; Device codes: 2; every harness identity line True. Session tenant is the test tenant: True; Session cloud: Global; device code mode: True; ARM token held as a SecureString: True; minutes left: Graph 60, ARM 70; The module has an MSAL helper: False; The module holds an MSAL application: False; MSAL copies loaded in the process (recorded): 4.90.0.0 in the load context Microsoft.Graph.Authentication and 4.83.1.0 in an unnamed one (AzAuth's), neither used by the module; Az modules loaded: 0. Run F, 14:44 UTC (23 s): AzAuth 2.9.0; Microsoft.Graph.Authentication 2.36.0; the same rows and lines; Device codes: 2; minutes left: Graph 70, ARM 64; MSAL helper False, MSAL application False; MSAL copies (recorded): 4.82.1.0 in msgraph-load-context and 4.83.1.0 in an unnamed one; Az modules loaded: 0. With the newest Microsoft.Graph.Authentication imported after AzAuth, the sign-in worked: no error naming Microsoft.IdentityModel.Abstractions and no MSAL build. No line printed the account, the tenant id or a code.
```

### 0.2. What is eligible and what is active

- [x] **0.2** Window B, each run. The fixture's eligibilities are listed, and nothing is active.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
"Eligible: directory $(@(Get-OPIMDirectoryRole -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -ErrorAction Stop).Count)"
"Active: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** `Eligible: directory 2, group 1, Azure 2`; `Active: directory 0, group 0, Azure 0`.
**Failure looks like:** another eligible count -- STOP. Something already active -- record it; the
checks below count before and after. A terminating error from a read is a failed read, never a `0`.

Result: 2026-10-11 14:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run L 14:35 UTC and run F 14:44 UTC: Eligible: directory 2, group 1, Azure 2; Active: directory 0, group 0, Azure 0 (both runs).
```

### 1. `pim` and `unpim` for all three kinds from a tenant map

### 1.1. The tenant map of the run

- [x] **1.1** Window B, each run. A tenant map in the raw folder holds the alias `s27-all`: Usage Summary Reports Reader, the membership of `opim-s2-grp` and Reader on `opim-s2-rg`.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s27/TenantMap.psd1'
if (-not (Test-Path -LiteralPath $Map)) {
    $Rows = @(
        @(Get-OPIMDirectoryRole -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq 'Usage Summary Reports Reader' })
        @(Get-OPIMEntraIDGroup -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s2-grp' -and $_.accessId -eq 'member' })
        @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg')
    )
    "Rows to store: $($Rows.Count)"
    # Its host lines name the stored keys, which hold ids, so they go nowhere.
    $Rows | Install-OPIMConfiguration -TenantAlias 's27-all' -TenantMapPath $Map -Confirm:$false 6>$null
}
$Config = Get-OPIMConfiguration -TenantAlias 's27-all' -TenantMapPath $Map -ErrorAction Stop
# A list the alias does not hold reads as $null, and @($null).Count is 1, so only real entries are counted.
"s27-all: directory $(@($Config.DirectoryRoles | Where-Object { $_ }).Count), group $(@($Config.EntraIDGroups | Where-Object { $_ }).Count), Azure $(@($Config.AzureRoles | Where-Object { $_ }).Count); Environment: $($Config.Environment)"
```

**Expect:** `Rows to store: 3` (run L only; run F finds the map); `s27-all: directory 1, group 1,
Azure 1; Environment: Global`.
**Failure looks like:** another count -- record it, and do not run 1.2 until the map holds the
entries.

Result: 2026-10-11 14:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run L 14:35 UTC: Rows to store: 3; s27-all: directory 1, group 1, Azure 1; Environment: Global. Run F 14:44 UTC: the map was found, nothing stored again; s27-all: directory 1, group 1, Azure 1; Environment: Global.
```

### 1.2. `pim` activates all three

- [x] **1.2** Window B, each run. `pim -TenantAlias s27-all` with a justification activates the directory role, the group membership and Reader, with no error, and all three are then listed as active.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s27/TenantMap.psd1'
$global:OpimS27On = [datetime]::UtcNow
$On = @(Enable-OPIMMyRole -TenantAlias 's27-all' -TenantMapPath $Map -Justification "Omnicit.PIM step 7 live check 1.2, run $env:OPIMS27_RUN" 2>&1 3>&1)
"pim s27-all: results $(@($On | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' } | ForEach-Object { '{0} {1}' -f $_.DisplayName, $_.Status }) -join '; ')"
"Errors: $(@($On | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', '); warnings: $(@($On | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count)"
$Listed = $null
while (([datetime]::UtcNow - $global:OpimS27On).TotalSeconds -lt 180 -and -not $Listed) {
    $Counts = @(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count, @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count, @(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)
    if (@($Counts | Where-Object { $_ -ge 1 }).Count -eq 3) { $Listed = [int]([datetime]::UtcNow - $global:OpimS27On).TotalSeconds } else { Start-Sleep -Seconds 5 }
}
"All three listed as active after (seconds): $Listed; active: directory $($Counts[0]), group $($Counts[1]), Azure $($Counts[2])"
```

**Expect:** three results -- `Usage Summary Reports Reader`, `opim-s2-grp` and `Reader`, each
`Provisioned` (or `Granted`); `Errors:` none; a number of seconds below 180; `active: directory 1,
group 1, Azure 1`.
**Record:** the seconds.
**Failure looks like:** an error, or fewer than three results -- record it; a sign-in error is a
defect within this step's scope (G11). A sign-in prompt -- STOP (0.1). More than one active post of a
kind -- STOP (SECURITY 4).

Result: 2026-10-11 14:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run L 14:35 UTC (33 s): pim s27-all: results Usage Summary Reports Reader Provisioned; opim-s2-grp Provisioned; Reader Provisioned; Errors: none; warnings: 0; All three listed as active after (seconds): 33; active: directory 1, group 1, Azure 1. Run F 14:44 UTC (32 s): the same three results, each Provisioned, no error, no warning; All three listed as active after (seconds): 32; active: directory 1, group 1, Azure 1.
```

### 1.3. `pim` again sends nothing (G8)

- [x] **1.3** Window B, each run. The same `pim` straight after 1.2 activates nothing more: each of the three is reported as already active, with no error.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s27/TenantMap.psd1'
$Again = @(Enable-OPIMMyRole -TenantAlias 's27-all' -TenantMapPath $Map -Justification "Omnicit.PIM step 7 live check 1.3, run $env:OPIMS27_RUN" 2>&1 3>&1)
"pim s27-all again: results $(@($Again | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' }).Count); already active warnings $(@($Again | Where-Object { $_ -is [System.Management.Automation.WarningRecord] -and $_.Message -match 'already active' }).Count); errors: $(@($Again | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', ')"
"Active: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** `results 0; already active warnings 3; errors:` none; `Active: directory 1, group 1, Azure 1`.
**Failure looks like:** a result, or an active count above 1 -- STOP (G8, SECURITY 4): a second
activation was sent.

Result: 2026-10-11 14:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run L 14:36 UTC: pim s27-all again: results 0; already active warnings 3; errors: none; Active: directory 1, group 1, Azure 1. Run F 14:45 UTC: the same lines.
```

### 1.4. `unpim` after five minutes deactivates all three

- [x] **1.4** Window B, each run. Five minutes after 1.2, `unpim -TenantAlias s27-all` deactivates the three, with no error, and the lists then show nothing active.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s27/TenantMap.psd1'
$Wait = 320 - ([datetime]::UtcNow - $global:OpimS27On).TotalSeconds
if ($Wait -gt 0) { Start-Sleep -Seconds ([int][math]::Ceiling($Wait)) }
$Off = @(Disable-OPIMMyRole -TenantAlias 's27-all' -TenantMapPath $Map 2>&1 3>&1)
"unpim s27-all: results $(@($Off | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' } | ForEach-Object { '{0} {1}' -f $_.DisplayName, $_.Status }) -join '; '); errors: $(@($Off | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', ')"
$Gone = [datetime]::UtcNow
$Settled = $false
while (([datetime]::UtcNow - $Gone).TotalSeconds -lt 300 -and -not $Settled) {
    Start-Sleep -Seconds 10
    $Counts = @(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count, @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count, @(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)
    $Settled = @($Counts | Where-Object { $_ -ne 0 }).Count -eq 0
}
"Lists settled after $([int]([datetime]::UtcNow - $Gone).TotalSeconds) s: $Settled; active: directory $($Counts[0]), group $($Counts[1]), Azure $($Counts[2])"
```

**Expect:** three results, each `Revoked`; `errors:` none; `settled ... : True; active: directory 0,
group 0, Azure 0`.
**Record:** the seconds.
**Failure looks like:** `ActiveDurationTooShort` -- run the block again after a minute. `False` --
record it, and deactivate before section 4.

Result: 2026-10-11 14:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run L 14:36-14:41 UTC (the block waited until 320 s after 1.2): unpim s27-all: results Usage Summary Reports Reader Revoked; opim-s2-grp Revoked; Reader Revoked; errors: none; Lists settled after 12 s: True; active: directory 0, group 0, Azure 0. Run F 14:45-14:51 UTC: the same three results, each Revoked, no error; Lists settled after 12 s: True; active: directory 0, group 0, Azure 0.
```

### 1.5. `unpim` again sends nothing (G8)

- [x] **1.5** Window B, each run. The same `unpim` straight after 1.4 deactivates nothing and reports no error: each of the three is not active.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s27/TenantMap.psd1'
$Again = @(Disable-OPIMMyRole -TenantAlias 's27-all' -TenantMapPath $Map -Verbose 2>&1 3>&1 4>&1)
"unpim s27-all again: results $(@($Again | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' }).Count); not currently activated: $(@($Again | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match 'not currently activated' }).Count); errors: $(@($Again | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', ')"
```

**Expect:** `results 0; not currently activated: 3; errors:` none.
**Failure looks like:** a result -- a deactivation was sent for a post the list did not show: record
it. An error -- record it.

Result: 2026-10-11 14:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run L 14:41 UTC: unpim s27-all again: results 0; not currently activated: 3; errors: none. Run F 14:51 UTC: the same line.
```

### 2. The cached sign-in, and a new one

### 2.1. A cached sign-in asks AzAuth for nothing

- [x] **2.1** Window B, each run. `Connect-OPIM -DeviceCode -IncludeARM` and the three listings on the session of 0.1 call `Get-AzToken` zero times, print no device code, and leave both tokens' expiry as it was.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Module = Get-Module Omnicit.PIM
$Before = & $Module { $script:_OPIMAuthState }
$GraphExpiry = $Before.GraphTokenExpiry
$ArmExpiry = $Before.ArmTokenExpiry
$global:OpimS27AzTokenCalls = 0
# A function of this name answers the module's call before AzAuth's cmdlet does; it counts and refuses.
function global:Get-AzToken { $global:OpimS27AzTokenCalls++; throw 'Step 7 check 2.1: the module asked AzAuth for a token.' }
try {
    $Out = @(Connect-OPIM -DeviceCode -IncludeARM 6>&1 3>&1 2>&1)
    $Eligible = "directory $(@(Get-OPIMDirectoryRole -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -ErrorAction Stop).Count)"
} finally {
    Remove-Item -Path Function:\Get-AzToken -ErrorAction SilentlyContinue
}
$After = & $Module { $script:_OPIMAuthState }
"Get-AzToken calls: $global:OpimS27AzTokenCalls; device code records: $(@($Out | Where-Object { $_ -is [System.Management.Automation.InformationRecord] -and $_.Tags -contains 'OPIMDeviceCode' }).Count); errors: $(@($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', ')"
"Graph token expiry unchanged: $($After.GraphTokenExpiry -eq $GraphExpiry); ARM token expiry unchanged: $($After.ArmTokenExpiry -eq $ArmExpiry); minutes left: Graph $([int]($After.GraphTokenExpiry - [datetime]::UtcNow).TotalMinutes), ARM $([int]($After.ArmTokenExpiry - [datetime]::UtcNow).TotalMinutes)"
"Eligible: $Eligible"
```

**Expect:** `Get-AzToken calls: 0; device code records: 0; errors:` none; both `unchanged: True`,
minutes above 5; `Eligible: directory 2, group 1, Azure 2`.
**Failure looks like:** a call above 0 or a device code record -- the cached sign-in was not used: a
defect within this step's scope (G11). Minutes at or below 5 -- the token was due for renewal; run
2.2 and then this block again.

Result: 2026-10-11 14:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run L 14:41 UTC: Get-AzToken calls: 0; device code records: 0; errors: none; Graph token expiry unchanged: True; ARM token expiry unchanged: True; minutes left: Graph 53, ARM 63; Eligible: directory 2, group 1, Azure 2. Run F 14:51 UTC: Get-AzToken calls: 0; device code records: 0; errors: none; both expiry lines True; minutes left: Graph 64, ARM 57; Eligible: directory 2, group 1, Azure 2.
```

### 2.2. `Disconnect-OPIM`, and a new sign-in asks for two codes again

- [x] **2.2** Window B, each run. `Disconnect-OPIM` clears the module's state, and a new `Connect-OpimLiveUser -IncludeARM` signs in with one new device code for Microsoft Graph and one for Azure, as the test user.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
Disconnect-OPIM
"Auth state cleared: $($null -eq (& (Get-Module Omnicit.PIM) { $script:_OPIMAuthState })); Graph context left: $([bool](Get-MgContext))"
$Sign = Connect-OpimLiveUser -IncludeARM -RawFolder 'docs/live-verification/raw/opim-s27'
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
"Device codes: $(@($Sign.Codes).Count)"
"Eligible: directory $(@(Get-OPIMDirectoryRole -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -ErrorAction Stop).Count)"
```

**Expect:** `Auth state cleared: True; Graph context left: False`; the rows `Graph Information True ok`
and `AzureCli Information True ok`; `Device codes: 2`; every True/False line of the harness `True`;
`Eligible: directory 2, group 1, Azure 2`.
**Failure looks like:** `False`, a `STOP` or a row that is not `ok` -- STOP as in 0.1. A hang without a
second code -- AzAuth reused a device code credential: a defect within this step's scope (G11).

Result: 2026-10-11 14:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run L 14:42 UTC (24 s): Auth state cleared: True; Graph context left: False; the harness completed a new Graph code and a new AzAuth code: rows Graph Information True ok and AzureCli Information True ok; Device codes: 2; every harness identity line True; Eligible: directory 2, group 1, Azure 2. Run F 14:51 UTC (24 s): the same lines; Device codes: 2. Neither run hung waiting for a code.
```

### 3. A Graph SDK session the module did not connect

### 3.1. Another Connect-MgGraph in the module's process is refused, and nothing is sent

- [x] **3.1** Window B, each run. After `oer-live-cc` connects the process's Graph SDK session with its certificate, `Get-OPIMDirectoryRole` and `Get-OPIMAzureRole` are refused with `GraphSessionChanged`, no Microsoft Graph or Azure Resource Manager request is sent, and the module never takes the session back.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Cc = & (Get-Module OerLive) { $script:OerLive.Config }
# The Graph SDK refuses a certificate Connect-MgGraph on top of the process's -AccessToken session
# (measured in Sprint 1, step 3), so the SDK session is closed first. The module's own state is
# untouched: the process then holds a session the module did not connect, which is what this check is about.
try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { $null = $PSItem }
Connect-MgGraph -ClientId $Cc.AppId -TenantId $Cc.TenantId -CertificateThumbprint $Cc.CertificateThumbprint -ContextScope Process -NoWelcome -ErrorAction Stop
$Cc = $null
"The process's Graph session is now app-only: $((Get-MgContext).AuthType -eq 'AppOnly')"
$global:OpimS27GraphCalls = 0
$global:OpimS27ArmCalls = 0
function global:Invoke-MgGraphRequest { $global:OpimS27GraphCalls++; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @args }
function global:Invoke-WebRequest { $global:OpimS27ArmCalls++; Microsoft.PowerShell.Utility\Invoke-WebRequest @args }
try {
    # Each call in its own try: the runner's try sees the module's terminating refusal propagate.
    $Errors = @()
    try { $Rows = @(Get-OPIMDirectoryRole -ErrorVariable Errors -ErrorAction SilentlyContinue) } catch { $Errors += $PSItem; $Rows = @() }
    "Get-OPIMDirectoryRole: rows $($Rows.Count); errors: $(@($Errors | ForEach-Object { $_.FullyQualifiedErrorId } | Select-Object -Unique) -join ', ')"
    $Errors = @()
    try { $Rows = @(Get-OPIMAzureRole -ErrorVariable Errors -ErrorAction SilentlyContinue) } catch { $Errors += $PSItem; $Rows = @() }
    "Get-OPIMAzureRole: rows $($Rows.Count); errors: $(@($Errors | ForEach-Object { $_.FullyQualifiedErrorId } | Select-Object -Unique) -join ', ')"
    "Requests sent by the module: Microsoft Graph $global:OpimS27GraphCalls, Azure Resource Manager $global:OpimS27ArmCalls"
} finally {
    Remove-Item -Path Function:\Invoke-MgGraphRequest, Function:\Invoke-WebRequest -ErrorAction SilentlyContinue
}
"The session is still oer-live-cc's (never switched back by the module): $((Get-MgContext).AuthType -eq 'AppOnly')"
```

**Expect:** `app-only: True`; `Get-OPIMDirectoryRole: rows 0` with `GraphSessionChanged` among the
errors; `Get-OPIMAzureRole: rows 0` with `GraphSessionChanged` (and `SignInRefused`, or only
`GraphSessionChanged`); `Requests sent by the module: Microsoft Graph 0, Azure Resource Manager 0`;
the last line `True`. No value of the app identity is printed.
**Failure looks like:** a row, or a request count above `0` -- STOP: the module sent a call under a
session it did not connect. The last line `False` -- the module switched the session back by itself,
STOP.

Result: 2026-10-11 14:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run L 14:42 UTC: The process's Graph session is now app-only: True; Get-OPIMDirectoryRole: rows 0; errors: GraphSessionChanged,Initialize-OPIMAuth; Get-OPIMAzureRole: rows 0; errors: GraphSessionChanged,Initialize-OPIMAuth (the expectation's "or only GraphSessionChanged"); Requests sent by the module: Microsoft Graph 0, Azure Resource Manager 0; The session is still oer-live-cc's (never switched back by the module): True. Run F 14:51 UTC: the same lines. No value of the app identity was printed.
```

### 3.2. Disconnect-MgGraph, Disconnect-OPIM and a new sign-in as the test user

- [x] **3.2** Window B, each run. The foreign session is closed, the module's state is cleared, and a new device code sign-in brings the module back as the test user, with two codes.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { $null = $PSItem }
Disconnect-OPIM
"Auth state cleared: $($null -eq (& (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }))"
$Sign = Connect-OpimLiveUser -IncludeARM -RawFolder 'docs/live-verification/raw/opim-s27'
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
"Device codes: $(@($Sign.Codes).Count)"
"Eligible: directory $(@(Get-OPIMDirectoryRole -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -ErrorAction Stop).Count)"
```

**Expect:** `Auth state cleared: True`; the rows `Graph Information True ok` and `AzureCli Information
True ok`; `Device codes: 2`; every True/False line `True`; `Eligible: directory 2, group 1, Azure 2`.
**Failure looks like:** `False` -- STOP as in 0.1.

Result: 2026-10-11 14:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run L 14:42 UTC (23 s): Auth state cleared: True; rows Graph Information True ok and AzureCli Information True ok; Device codes: 2; every True/False line True; Eligible: directory 2, group 1, Azure 2. Run F 14:51 UTC (23 s): the same lines.
```

### 4. The fixture's teardown (step 7, scope 6)

### 4.1. Window B signs out

- [x] **4.1** Window B, the last block of each run. Nothing is active, the window's session is cleared, no Az module is loaded, and the window ends.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not (Get-Module Omnicit.PIM)) { throw 'Omnicit.PIM is not loaded in this window; run 0.1 first.' }
if ((Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
"Active: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
Disconnect-OPIM
try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { $null = $PSItem }
"Module state cleared: $($null -eq (& (Get-Module Omnicit.PIM) { $script:_OPIMAuthState })); Graph context left: $([bool](Get-MgContext)); Az modules loaded: $(@(Get-Module -Name 'Az', 'Az.*').Count)"
```

**Expect:** `Active: directory 0, group 0, Azure 0`; `Module state cleared: True; Graph context left:
False; Az modules loaded: 0`.
**Failure looks like:** an active role -- deactivate it (after five minutes) before 4.2.

Result: 2026-10-11 14:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run L 14:43 UTC: Active: directory 0, group 0, Azure 0; Module state cleared: True; Graph context left: False; Az modules loaded: 0; window B-L ended 14:43 UTC. Run F 14:52 UTC: the same lines; window B-F ended 14:52 UTC.
```

### 4.2. The teardown planned with `-WhatIf`

- [x] **4.2** Window A, as `oer-live-cc`, after both runs. `Initialize-OpimS2Prereq.ps1 -Teardown -WhatIf` lists what it would remove, every target carries the prefix `opim-s2`, except the one named membership, and nothing is removed.

```powershell
$Prereq = Join-Path $env:OPIMLIVE_HOME 'Initialize-OpimS2Prereq.ps1'
$Lines = @(pwsh -NoProfile -NonInteractive -File $Prereq -Teardown -WhatIf 2>&1 | ForEach-Object { ([string]$_) -replace '\x1b\[[0-9;]*m', '' })
$WhatIf = @($Lines | Where-Object { $_ -match '^What if:' -and $_ -notmatch 'transcript' })
"What if lines other than the transcript: $($WhatIf.Count)"
"Targets without the prefix opim-s2: $(@($WhatIf | Where-Object { $_ -notmatch 'opim-s2' }).Count)"
"Targets outside the prefix that are the named membership: $(@($WhatIf | Where-Object { $_ -match "membership in the group 'Exclude from CA'" }).Count)"
$WhatIf | ForEach-Object { ($_ -split 'on target "')[-1].TrimEnd('".') }
$Lines | Where-Object { $_ -match 'Teardown \d/6|Sweep|Prefixed resource groups|WhatIf:' }
```

**Expect:** a number of `What if` lines; `Targets without the prefix opim-s2: 0`; `Targets outside the
prefix that are the named membership: 1`; the targets listed by name (the membership, the Azure
eligibilities on `opim-s2-rg` and `opim-s2-rg2`, the two resource groups, `opim-s2-grp`, the
directory role eligibilities and the user, the two secrets).
**Record:** the count and the target names.
**Failure looks like:** a target without the prefix other than the named membership -- STOP (G11 #5):
remove nothing.

Result: 2026-10-11 14:56 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
14:53 UTC, window A as oer-live-cc: What if lines other than the transcript: 13; Targets without the prefix opim-s2: 0; Targets outside the prefix that are the named membership: 1. Targets: opim-s2-live-user's membership in the group 'Exclude from CA'; the Azure eligibility of opim-s2-live-user on opim-s2-rg and on opim-s2-rg2; the resource groups opim-s2-rg and opim-s2-rg2; the group opim-s2-grp; the user's eligibilities for Message Center Privacy Reader and Usage Summary Reports Reader at '/'; the group's member eligibility and the group (listed by Remove-OerLiveTestObjects in a WhatIf run, since the group is not deleted first); opim-s2-live-user; the two secrets in the vault OpimLive. Nothing was removed; the list is the one step 5 planned.
```

### 4.3. The teardown

- [x] **4.3** Window A, as `oer-live-cc`. `Initialize-OpimS2Prereq.ps1 -Teardown -Unattended` removes the membership, the Azure eligibilities, the resource groups, the group, the directory role eligibilities, the user and the two secrets, in that order.

```powershell
$Prereq = Join-Path $env:OPIMLIVE_HOME 'Initialize-OpimS2Prereq.ps1'
$Lines = @(pwsh -NoProfile -NonInteractive -File $Prereq -Teardown -Unattended 2>&1 | ForEach-Object { ([string]$_) -replace '\x1b\[[0-9;]*m', '' })
$Lines | Where-Object { $_ -match 'Teardown \d/6|Removed|Deleted|Remove-OerLiveTestObjects|Sweep after|not in the vault|STOP|Residue' }
```

**Expect:** the six steps in order; `Removed: opim-s2-live-user from 'Exclude from CA'`; the two
Azure eligibilities removed before `Deleted: the resource group opim-s2-rg` and `opim-s2-rg2`;
`Deleted: the group opim-s2-grp`; `Remove-OerLiveTestObjects: removed` with `residue 0, unreadable 0`;
both secrets removed; `Sweep after the teardown: prefixed directory objects 0, prefixed resource
groups 0`.
**Record:** the step lines as printed.
**Failure looks like:** a `STOP`, a residue or a sweep count above 0 -- record it; run the block again
once replication has caught up (a second run is idempotent; in step 5 the user could be deleted only
by the second run). Anything left after a second run is a residue line for the report (G11 #5 if an
object cannot be removed at all).

Result: 2026-10-11 14:56 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run 1, 14:53-14:54 UTC, window A as oer-live-cc: 1/6 Removed: opim-s2-live-user from 'Exclude from CA' (204). 2/6 Removed: the Azure eligibility of opim-s2-live-user on opim-s2-rg and on opim-s2-rg2. 3/6 Deleted: the resource groups opim-s2-rg and opim-s2-rg2 (each converged after 2 reads). 4/6 Deleted: the group opim-s2-grp (204). 5/6 (Remove-OerLiveTestObjects): both directory role eligibilities removed (201), the group's member eligibility removed (201), the group already gone (404); DELETE of the user answered 403 Authorization_RequestDenied right after its eligibilities went, so the user was disabled and became a residue row; removed 4, residue 1, unreadable 1. 6/6: both secrets removed. Sweep after the teardown: prefixed directory objects 1, prefixed resource groups 0. Run 2, 14:55 UTC, after replication (as the step asks and as in step 5): steps 1-4 found nothing left; DELETE user 204; removed 1, residue 0, unreadable 0; the secrets were not in the vault. Sweep after the teardown: prefixed directory objects 1 (the user deleted seconds before; 4.4 reads 0).
```

### 4.4. The sweep after the teardown

- [x] **4.4** Window A, as `oer-live-cc`. No object and no resource group carries the prefix `opim-s2-`, no object carries `opim-s27-`, and the vault holds no secret of the fixture.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'opim-s2-'
Connect-OerLive -Graph
"Objects with the prefix opim-s2-: $(@(Find-OerLivePrefixed -Prefix 'opim-s2-' -ThrowOnUnread -Quiet).Count)"
"Objects with the prefix opim-s27-: $(@(Find-OerLivePrefixed -Prefix 'opim-s27-' -ThrowOnUnread -Quiet).Count)"
Connect-OerLive -Arm
$Rgs = Invoke-OerLiveArm -All -Path ("/subscriptions/{0}/resourcegroups?api-version=2021-04-01" -f $Cfg.SubscriptionId)
$null = Assert-OerLiveOk -Response $Rgs -Activity 'Listing the resource groups'
"Resource groups with the prefix opim-s2-: $(@(@($Rgs.Body.value) | Where-Object { ([string]$_.name).StartsWith('opim-s2-', [System.StringComparison]::OrdinalIgnoreCase) }).Count)"
Disconnect-OerLive
Import-Module -Name Microsoft.PowerShell.SecretManagement -ErrorAction Stop
"Secrets of the fixture in the vault OpimLive: $(@(Get-SecretInfo -Vault OpimLive -Name 'opim-s2-*' -ErrorAction SilentlyContinue).Count)"
"Residue rows of this sprint in raw\residue.json: $(@(Read-OerLiveResidue | Where-Object { ([string]$_['prefix']).StartsWith('opim-s2', [System.StringComparison]::OrdinalIgnoreCase) }).Count)"
```

**Expect:** `Objects with the prefix opim-s2-: 0`; `Objects with the prefix opim-s27-: 0`; `Resource
groups with the prefix opim-s2-: 0`; `Secrets of the fixture in the vault OpimLive: 0`.
**Record:** the residue rows of the sprint (two rows from step 5's teardown stood in the file before
this run, for objects that no longer exist).
**Failure looks like:** a count above 0 -- run 4.3 again after replication; anything left after that
is a line in the report (G11 #5 if it cannot be removed). A 401 or 403 -- STOP (G6).

Result: 2026-10-11 14:56 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
14:55 UTC, window A as oer-live-cc: every oer-live-cc identity line True (Graph and Azure Resource Manager); Objects with the prefix opim-s2-: 0; Objects with the prefix opim-s27-: 0; Resource groups with the prefix opim-s2-: 0; Secrets of the fixture in the vault OpimLive: 0. Recorded: Residue rows of this sprint in raw\residue.json: 3 -- the two rows of step 5's teardown and the row of run 1 of 4.3 above, all for objects that no longer exist. The prerequisite script does not call Clear-OerLiveResidue while rows of another prefix are in the file, and OerLive and its raw folder are outside this step's write access, so the rows stay. The deleted test user lies in the directory's deleted items for 30 days.
```

## Teardown

Section 4 removed the fixture. The check below verifies the local side: the raw folder with the
module folders and the tenant map is gone, and no untracked file is left under
`docs/live-verification`. Nothing is left in the tenant on purpose; the test user lies in the
directory's deleted items for 30 days.

### T.1. The raw folder

- [x] **T.1** Window A, after both window B runs have ended. The raw folder, with the module folders and the tenant map, is deleted once the results are written up, and nothing untracked is left.

```powershell
Remove-Item -LiteralPath 'docs/live-verification/raw/opim-s27' -Recurse -Force
"Raw folder gone: $(-not (Test-Path -LiteralPath 'docs/live-verification/raw/opim-s27'))"
"Untracked files under docs/live-verification: $(@(git status --porcelain --untracked-files=all -- docs/live-verification | Where-Object { $_.StartsWith('??') }).Count)"
```

**Expect:** `Raw folder gone: True`; `Untracked files under docs/live-verification: 0`.
**Failure looks like:** `False` or an untracked file -- remove it before the results are committed.

Result: 2026-10-11 14:57 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
14:57 UTC, window A, after both window B runs had ended and the results were written up: Raw folder gone: True (it held the module folders of S.2, 172 files, and the run's tenant map); Untracked files under docs/live-verification: 0. Nothing is left in the tenant on purpose; the deleted test user lies in the directory's deleted items for 30 days, and the three residue rows of 4.4 stay in OerLive's raw\residue.json.
```
