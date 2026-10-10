# Live verification checklist -- the module keeps the global cloud by default and sends a tenant alias's sign-in to the cloud the alias stores (feat/sovereign-clouds)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

Where a check says **Record:** instead of **Expect:**, the outcome is genuinely not known in
advance. Write down what actually happened rather than what looked plausible.

**This file runs only in the operator's designated test tenant** -- never a customer tenant -- and
only when the operator has asked for the run. The module runs there as the dedicated delegated test
user `opim-s2-live-user`, and the sweep runs as the dedicated app identity `oer-live-cc`, whose only
credential is a certificate; neither is ever the operator's own account. The run writes to nothing
outside the prefix `opim-s2-` (the sprint's fixture, which this file only reads and activates
eligibilities of) and `opim-s23-` (this step's own objects, of which there are none). Check 0.1
proves the identity before any other check calls the module. If a browser window or a sign-in prompt
appears mid-run, STOP and run check 0.1 again: in this file every sign-in is a device code, and the
proof of 0.1 holds only for the sign-in it checked.

**No sign-in in a sovereign cloud** (decision P-12, 2026-10-09: no). Section 2 sends one sign-in
request for the test tenant to the US Government authority and measures that it is refused there;
the test tenant lives in the global cloud, so the US Government authority cannot sign anyone in to
it, and no device code is ever completed for it. Nothing in this file completes a code that the
harness did not ask for.

**Two windows, never one process** (decision A10 of Sprint 1, kept in Sprint 2). Window A runs as
`oer-live-cc` and reads files without the module. Window B runs the branch's build as the test user,
in a `pwsh -NoProfile` that loads AzAuth 2.9.0 and Microsoft.Graph.Authentication 2.36.0 from the
build's own dependencies before the module. Every block below names its window.

**No block prints a scope id, an object id, a tenant id, a sign-in name or a message that holds
one.** The blocks print counts, statuses, error ids, AADSTS codes, host names of the clouds, display
names of the fixture's roles, group and resource groups, module names and versions, seconds and
True/False.

## What changed and why this needs a live tenant

- **A. One table owns every cloud endpoint, and the global cloud's values are the ones of before**
  ("feat: add the cloud endpoint table for the sovereign clouds", "feat: sign in to Microsoft Graph
  in the chosen cloud", "feat: sign in to Azure Resource Manager in the chosen cloud"). The MSAL
  authority, the Graph SDK's environment, the Azure Resource Manager resource and host and the
  next-link hosts are read from `Get-OPIMCloudEndpoint`. A unit test pins the global row to the old
  literals; only a live sign-in shows that the global path still signs in, connects and reaches both
  services as before (section 0, section 1).
- **B. `-Environment`, and a session keeps its cloud** ("feat: take -Environment and keep the
  session's cloud for its tenant"). A sign-in without `-Environment` and one with `-Environment
  Global` must be one session: no second sign-in, no new token (0.3).
- **C. The tenant map remembers the cloud** ("feat: remember the cloud of a tenant alias and sign in
  to it"). An alias written without `-Environment` in the global cloud stores no cloud and signs in
  to the global cloud (1.1); `pim` and `unpim` keep working from such a map for all three kinds
  (section 1, the regression of steps 1a, 1b and 2). An alias that stores `USGov` sends its sign-in
  to the US Government authority, where the global test tenant is refused, and nothing reaches the
  global cloud (section 2). A stored cloud the module does not know is refused before any sign-in
  (2.5).
- **D. The guards, the completion, the documentation and the release notes** ("test: refuse a cloud
  host anywhere outside the endpoint table", "test: keep the plaintext Graph token out of every
  command and hashtable", "test: hold the whole shape of the ARM fallback literal and quoted token
  members", "fix: keep warnings out of the Azure role completion", "fix: quote the alias in the
  suggested Set-OPIMConfiguration command", "docs: say in the release notes that the sovereign
  clouds are supported", "docs: describe the sovereign clouds and which are untested live", "docs:
  say a 0.6.x module drops the stored cloud, and name the cloud switch correctly", "docs: record the
  measured test figures"). 2.5 reads the quoted alias in the refusal; the rest has no live effect.
- **E. The harness, OpimLive 1.0.5** (outside the repository, scope 9). `Connect-OpimLiveUser` no
  longer calls `Disconnect-AzAccount` for a module with its own ARM transport; 0.1 records that no Az
  module is loaded after the sign-in in a window that can find the profile's Az modules.

The mapping to the step's specification: its 0.x is 0.3 (and 1.1's alias), its 1.x is section 1
(with 1.6 for the Graph SDK's own retry of a POST, finding 6 of step 2), its 2.x is section 2, and
G8 is 0.3, 1.3 and 1.5.

The fixture of Sprint 2 (decision A15) is used as it stands and is not changed: the test user
`opim-s2-live-user`, the group `opim-s2-grp` (eligible as member), the resource groups `opim-s2-rg`
and `opim-s2-rg2` (Reader eligible on each), and the directory roles Usage Summary Reports Reader and
Message Center Privacy Reader. Section 1 activates Usage Summary Reports Reader, the membership of
`opim-s2-grp` and Reader on `opim-s2-rg`, and deactivates all three again before the end. This step
creates no object in the tenant, so it has no prerequisite script of its own; the sprint's
`Initialize-OpimS2Prereq.ps1` is run with `-WhatIf` only. The run's tenant maps live in the raw
folder and are deleted with it.

## What this file does not check, and why

Class B (decision P-12), each proven by the tests named:

- **A sign-in that succeeds in USGov, USGovDoD or China, and a Graph or ARM request there** -- no test
  tenant exists in a sovereign cloud. `tests/Unit/Private/Get-OPIMCloudEndpoint.Tests.ps1` pins the
  authority, the Graph host and the ARM host of every cloud; `tests/Unit/Private/Initialize-OPIMAuth.Tests.ps1`
  pins the MSAL cloud, `Connect-MgGraph -Environment`, the AzAuth resource and `AZURE_AUTHORITY_HOST`
  per cloud; `tests/Unit/Private/Invoke-OPIMGraphRequest.Tests.ps1` and
  `tests/Unit/Private/Invoke-OPIMArmRequest.Tests.ps1` pin the next-link and ARM hosts of a sovereign
  session.
- **`AZURE_AUTHORITY_HOST` set around a sovereign Azure sign-in and put back afterwards, also after
  a failure** -- an Azure sign-in in a sovereign cloud needs a sovereign Graph session first;
  `tests/Unit/Private/Initialize-OPIMAuth.Tests.ps1`. Live, 0.1, 2.2 and T.2 record that the variable
  is never left set.
- **A switch of cloud drops the ARM token and passes `-Force`** -- `tests/Unit/Private/Initialize-OPIMAuth.Tests.ps1`.
- **No cloud host outside the table under `source/`** -- `tests/QA/sourcehygiene.tests.ps1`, Describe
  'Cloud hosts'.
- **`Install-` and `Set-OPIMConfiguration -Environment` for every value, and the map read back** --
  `tests/Unit/Public/Install-OPIMConfiguration.Tests.ps1`, `tests/Unit/Public/Set-OPIMConfiguration.Tests.ps1`,
  `tests/Unit/Private/Export-OPIMTenantMap.Tests.ps1`.
- **The interactive (browser) sign-in** -- every sign-in here is a device code.
- **That no network request at all reached a global-cloud host in section 2** -- no packet capture
  is taken. Section 2 shows instead that the module's MSAL application was built for the US
  Government authority, that no device code, no token and no Graph session came of it, and that the
  global session's tokens are unchanged.

## Setup, once

The operator sets `OPIMLIVE_HOME` in both windows to the notes folder that holds the `OpimLive`
folder, and `OPIMLIVE_PREFIX` to `opim-s2-` in window B; no checklist holds the path. The test user's
sign-in name and the test tenant's id are read by the harness through OerLive and are never printed.
Both windows run from the root of the step's worktree. Raw output and the run's tenant maps go to
`docs/live-verification/raw/opim-s23` (git-ignored), which is deleted once the results are written
up.

A block that runs the module in window B starts with the three-line prologue of the template.

The PIM policies of the fixture's roles and group require a justification on activation (measured
in the fixture session), so every activation below passes one.

### S.1. Find the build under test and tie it to the branch head

- [x] **S.1** Window A (no module). The newest build in `output/module/Omnicit.PIM/` was made after the branch head was committed, and it holds the cloud table.

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
"The built module holds the cloud table: $([bool](Select-String -LiteralPath $Psm1 -Pattern 'function Get-OPIMCloudEndpoint' -SimpleMatch -Quiet))"
$Raw = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s23'
$null = New-Item -ItemType Directory -Force -Path $Raw
git check-ignore -q $Raw
"The raw folder is git-ignored: $($LASTEXITCODE -eq 0)"
```

**Expect:** the branch head's hash and subject; the version folder; `Built after the branch head was
committed: True`; `Tracked changes in the working tree: 0`; the two last lines `True`.
**Failure looks like:** `False` on the third line or a tracked change -- build again before any check
below. `False` on the raw folder -- STOP: the tenant maps would be tracked.

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:36 UTC, window A (no module): Branch head: 728b1ee (the checklist commit); Built version folder: 0.7.0; Built after the branch head was committed: True (built again after the checklist commit, which changes no source); Tracked changes in the working tree: 0; The built module holds the cloud table: True; The raw folder is git-ignored: True.
```

### S.2. Window B loads the pinned dependencies

- [x] **S.2** Window B, a fresh `pwsh -NoProfile`, before anything else runs in it. AzAuth 2.9.0 and Microsoft.Graph.Authentication 2.36.0 are loaded from the build's own dependencies, no Az module is loaded, and `AZURE_AUTHORITY_HOST` is not set.

```powershell
$env:PSModulePath = (Resolve-Path 'output/RequiredModules').Path + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module (Resolve-Path 'output/RequiredModules/AzAuth/2.9.0/AzAuth.psd1').Path
Import-Module (Resolve-Path 'output/RequiredModules/Microsoft.Graph.Authentication/2.36.0/Microsoft.Graph.Authentication.psd1').Path
"AzAuth loaded: $((Get-Module AzAuth).Version)"
"Microsoft.Graph.Authentication loaded: $((Get-Module Microsoft.Graph.Authentication).Version)"
"Az modules loaded: $(@(Get-Module -Name 'Az', 'Az.*').Count); this window can find: $(@(Get-Module -ListAvailable -Name 'Az', 'Az.*').Count)"
"AZURE_AUTHORITY_HOST is set: $(Test-Path -LiteralPath 'Env:AZURE_AUTHORITY_HOST')"
"PowerShell: $($PSVersionTable.PSVersion)"
```

**Expect:** `AzAuth loaded: 2.9.0`; `Microsoft.Graph.Authentication loaded: 2.36.0`; `Az modules
loaded: 0`; `AZURE_AUTHORITY_HOST is set: False`; `PowerShell:` 7.4 or later.
**Record:** `this window can find:` -- the profile's Az modules, which 0.1 must not load.
**Failure looks like:** another version, or an Az module loaded -- end the window and start a fresh
one. `AZURE_AUTHORITY_HOST is set: True` -- STOP: the operator's environment would steer the Azure
sign-in; clear it in a fresh window first.

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:39 UTC, window B (the second; see 0.1 and 0.3): AzAuth loaded: 2.9.0; Microsoft.Graph.Authentication loaded: 2.36.0; Az modules loaded: 0; this window can find: 9 (recorded: the profile's Az modules); AZURE_AUTHORITY_HOST is set: False; PowerShell: 7.6.6. The first window B, 05:36 UTC: the same lines.
```

### S.3. The fixture is in place, and nothing carries the step's prefix

- [x] **S.3** Window A, as `oer-live-cc`. The prerequisite script with `-WhatIf` finds every object of the fixture and would write nothing, and no object carries the prefix `opim-s23-`.

```powershell
$Prereq = Join-Path $env:OPIMLIVE_HOME 'Initialize-OpimS2Prereq.ps1'
# A child process, so its host output -- the What if lines included -- arrives here as text.
$Lines = @(pwsh -NoProfile -NonInteractive -File $Prereq -WhatIf 2>&1 | ForEach-Object { ([string]$_) -replace '\x1b\[[0-9;]*m', '' })
"Lines 'exists; kept': $(@($Lines | Where-Object { $_ -match 'exists; kept' }).Count)"
"What if lines other than the transcript: $(@($Lines | Where-Object { $_ -match '^What if:' -and $_ -notmatch 'transcript' }).Count)"
$Lines | Where-Object { $_ -match "Sweep 'opim-s|Residue:|Group 'Exclude from CA'|PIM policy of|exists; kept" }
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$null = Import-OerLiveConfig -Prefix 'opim-s23-'
Connect-OerLive -Graph
"Objects with the prefix opim-s23-: $(@(Find-OerLivePrefixed -Prefix 'opim-s23-' -ThrowOnUnread -Quiet).Count)"
Disconnect-OerLive
```

**Expect:** `Lines 'exists; kept': 10`; `What if lines other than the transcript: 0`; the sweeps
`opim-s1-` 0 and `opim-s2-` 1 user, 1 group, 0 other; every PIM policy line without approval or
authentication context; `Objects with the prefix opim-s23-: 0`.
**Failure looks like:** any `What if:` line that would create an object, a count other than 10, or a
prefixed object that is not the fixture's -- STOP: create nothing and ask for nothing. A 401 or 403
-- STOP (G6).

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:36-05:37 UTC, window A as oer-live-cc: Lines 'exists; kept': 10; What if lines other than the transcript: 0. Sweep 'opim-s1-': 0; sweep 'opim-s2-': test user 1, test group 1, other prefixed objects 0. Group 'Exclude from CA': found 1, not role-assignable, not dynamic. Every PIM policy (both directory roles, the group member, Reader on opim-s2-rg and opim-s2-rg2): approval required False, authentication context False, on activation Justification. Residue: 2 rows, both from a Sprint 1 run, not touched. Every oer-live-cc identity line True. Objects with the prefix opim-s23-: 0.
```

### S.4. The harness loads in window B

- [x] **S.4** Window B. OerLive is 1.0.3, OpimLive is 1.0.5, the harness reads the test values through it, and the TOTP implementation reproduces RFC 6238.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME 'OpimLive/OpimLive.psm1') -Force
$Target = Get-OpimLiveTarget
"OerLive version: $((Get-OerLiveState).Version)"
"OpimLive version: $(& (Get-Module OpimLive) { $script:OpimLiveVersion })"
"Test user and tenant read (values hidden): $([bool]$Target.UserPrincipalName -and [bool]$Target.TenantId)"
"TOTP self-test: $(Get-OpimLiveTotp -SelfTest)"
```

**Expect:** `OerLive version: 1.0.3`; `OpimLive version: 1.0.5`; the next two lines `True`.
**Failure looks like:** `False` on the self-test -- STOP: the harness would enter wrong codes.

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:39 UTC, window B (the second): OerLive version: 1.0.3; OpimLive version: 1.0.5; Test user and tenant read (values hidden): True; TOTP self-test: True. The first window B, 05:36 UTC: the same lines.
```

### 0. Preparation

### 0.1. Identity check, in the global cloud

- [x] **0.1** Window B. `Connect-OpimLiveUser -IncludeARM`, which passes no `-Environment`, signs the build in to Graph and Azure with one device code each; the account is the test user, the tenant the test tenant, the ARM token the test user's in the test tenant; the session is in the global cloud on the global hosts; `AZURE_AUTHORITY_HOST` was never left set; and no Az module is loaded.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
"AzAuth $((Get-Module AzAuth).Version); Microsoft.Graph.Authentication $((Get-Module Microsoft.Graph.Authentication).Version)"
$Target = Get-OpimLiveTarget
$Sign = Connect-OpimLiveUser -IncludeARM -RawFolder 'docs/live-verification/raw/opim-s23'
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
$State = & (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }
$App = & (Get-Module Omnicit.PIM) { $script:_OPIMMsalApp }
"Session tenant is the test tenant: $([string]::Equals([string]$State.TokenTenantId, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
"Session cloud: $($State.Environment); MSAL app cloud: $(& (Get-Module Omnicit.PIM) { $script:_OPIMMsalAppEnvironment })"
$AuthorityText = [string]$App.Authority; if (-not $AuthorityText) { $AuthorityText = [string]$App.AppConfig.Authority.AuthorityInfo.CanonicalAuthority }
"MSAL authority host: $(([uri]$AuthorityText).Host)"
"Graph SDK environment: $((Get-MgContext).Environment)"
"ARM resource: $($State.ArmResourceUrl); ARM token held as a SecureString: $($State.ArmToken -is [securestring]); minutes left: $([int]($State.ArmTokenExpiry - [datetime]::UtcNow).TotalMinutes)"
"AZURE_AUTHORITY_HOST is set: $(Test-Path -LiteralPath 'Env:AZURE_AUTHORITY_HOST')"
"Az modules loaded: $(@(Get-Module -Name 'Az', 'Az.*').Count); this window can find: $(@(Get-Module -ListAvailable -Name 'Az', 'Az.*').Count)"
```

**Expect:** `AzAuth 2.9.0; Microsoft.Graph.Authentication 2.36.0`; the harness step line
`Disconnect-OPIM and Disconnect-MgGraph ran first (no Disconnect-AzAccount: the module has its own
ARM transport).`; the rows `Graph Information True ok` and `AzureCli Information True ok`; every
True/False line of the harness `True`; `Session tenant is the test tenant: True`; `Session cloud:
Global; MSAL app cloud: Global`; `MSAL authority host: login.microsoftonline.com`; `Graph SDK
environment: Global`; `ARM resource: https://management.azure.com`, `True`, minutes above 5;
`AZURE_AUTHORITY_HOST is set: False`; `Az modules loaded: 0`. No line prints the account or the
tenant id.
**Record:** `this window can find:` -- the Az modules the harness would have loaded before 1.0.5.
**Failure looks like:** `False` on any line, a `STOP`, or an Azure row that is not `AzureCli
Information True ok` -- STOP: run `Disconnect-OPIM`, end window B and run no other check. An ARM token
whose tenant or user is not the test user's is a STOP even though the module refused it (the harness
signed in wrong). Another host or cloud -- a defect within this step's scope (G11).

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:39-05:40 UTC, window B (the second; 25 s): AzAuth 2.9.0; Microsoft.Graph.Authentication 2.36.0. Harness step line: Disconnect-OPIM and Disconnect-MgGraph ran first (no Disconnect-AzAccount: the module has its own ARM transport). The Graph code and then the AzAuth code were completed in Edge: rows Graph Information True ok and AzureCli Information True ok; Signed in to Graph as the test user: True; to the test tenant: True; the module remembers the device code mode: True; Azure token is the test user (the Graph sign-in's object id): True; Azure token is the test tenant: True. Session tenant is the test tenant: True; Session cloud: Global; MSAL app cloud: Global; MSAL authority host: login.microsoftonline.com; Graph SDK environment: Global; ARM resource: https://management.azure.com; ARM token held as a SecureString: True; minutes left: 64; AZURE_AUTHORITY_HOST is set: False; Az modules loaded: 0; this window can find: 9 (recorded: the harness 1.0.5 no longer loads them). No line printed the account or the tenant id. Run 1, the first window B, 05:37 UTC: the same harness and identity lines; the operator's window wrapper (not the module) stopped on the block's Format-Table line, so the remaining lines ran verbatim in the same window at 05:37 with the table through Out-String, with the same results. That window was ended after 0.3 (see there), and a second window B ran S.2, S.4 and 0.1 to T.2.
```

### 0.2. What is eligible and what is active

- [x] **0.2** Window B. The fixture's eligibilities are listed, and nothing is active.

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

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:40 UTC, window B: Eligible: directory 2, group 1, Azure 2; Active: directory 0, group 0, Azure 0. (The first window B, 05:38 UTC: the same.)
```

### 0.3. Without `-Environment` and with `-Environment Global` is one session (G8)

- [x] **0.3** Window B. `Connect-OPIM -IncludeARM` and `Connect-OPIM -Environment Global -IncludeARM`, each run twice, show no device code and change neither token: the session signed in by 0.1 without `-Environment` is the session of `-Environment Global`.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Before = & (Get-Module Omnicit.PIM) { @{ Graph = $script:_OPIMAuthState.GraphTokenExpiry; Arm = $script:_OPIMAuthState.ArmTokenExpiry; App = $script:_OPIMMsalApp } }
$Runs = [ordered]@{
    'no -Environment, first'         = { Connect-OPIM -IncludeARM -ErrorAction Stop 6>&1 3>&1 }
    'no -Environment, second'        = { Connect-OPIM -IncludeARM -ErrorAction Stop 6>&1 3>&1 }
    '-Environment Global, first'     = { Connect-OPIM -Environment Global -IncludeARM -ErrorAction Stop 6>&1 3>&1 }
    '-Environment Global, second'    = { Connect-OPIM -Environment Global -IncludeARM -ErrorAction Stop 6>&1 3>&1 }
}
foreach ($Name in $Runs.Keys) {
    $Out = @(& $Runs[$Name])
    $Codes = @($Out | Where-Object { $_ -is [System.Management.Automation.InformationRecord] -and @($_.Tags) -contains 'OPIMDeviceCode' }).Count
    "$($Name): device codes $Codes; other lines $($Out.Count - $Codes)"
}
$After = & (Get-Module Omnicit.PIM) { @{ Graph = $script:_OPIMAuthState.GraphTokenExpiry; Arm = $script:_OPIMAuthState.ArmTokenExpiry; App = $script:_OPIMMsalApp; Cloud = $script:_OPIMAuthState.Environment } }
"Graph token unchanged: $($Before.Graph -eq $After.Graph); ARM token unchanged: $($Before.Arm -eq $After.Arm); same MSAL application: $([object]::ReferenceEquals($Before.App, $After.App)); session cloud: $($After.Cloud)"
```

**Expect:** four lines `device codes 0; other lines 0`; `Graph token unchanged: True; ARM token
unchanged: True; same MSAL application: True; session cloud: Global`.
**Failure looks like:** a device code or a changed token -- `-Environment Global` was taken as another
cloud than the session's: a defect within this step's scope (G11). Do not complete a code that
appears here; let it expire, and run 0.1 again.

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:40 UTC, window B (the second): no -Environment, first: device codes 0; other lines 0. no -Environment, second: device codes 0; other lines 0. -Environment Global, first: device codes 0; other lines 0. -Environment Global, second: device codes 0; other lines 0. Graph token unchanged: True; ARM token unchanged: True; same MSAL application: True; session cloud: Global. In the first window B (05:38 UTC) the block ran but printed nothing: the block's own variable Out overwrote the window wrapper's output-file variable of the same name, since the wrapper dot-sources each block. Nothing was written anywhere (the working tree stayed clean). That window was signed out (state cleared True, no Graph context, AZURE_AUTHORITY_HOST not set) and ended at 05:39; the wrapper's own variables now carry a prefix no block uses, and it renders Format-Table output in one piece.
```

### 1. `pim` and `unpim` for all three kinds, from a tenant map (regression of steps 1a, 1b and 2)

### 1.1. The tenant map stores no cloud for the global cloud, and its alias is the same session

- [x] **1.1** Window B. A tenant map in the raw folder holds one alias, written without `-Environment` while the session is in the global cloud, with Usage Summary Reports Reader, the membership of `opim-s2-grp` and Reader on `opim-s2-rg`; the file holds no `Environment` line and the alias reads as `Global`; and `Connect-OPIM -TenantAlias` for it is the session of 0.1.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s23/TenantMap.psd1'
if (-not (Test-Path -LiteralPath $Map)) {
    $Rows = @(
        @(Get-OPIMDirectoryRole -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq 'Usage Summary Reports Reader' })
        @(Get-OPIMEntraIDGroup -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s2-grp' -and $_.accessId -eq 'member' })
        @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg')
    )
    "Rows to store: $($Rows.Count)"
    # Its host lines name the stored keys, which hold ids, so they go nowhere.
    $Rows | Install-OPIMConfiguration -TenantAlias 's23-all' -TenantMapPath $Map -Confirm:$false 6>$null
}
$Config = Get-OPIMConfiguration -TenantAlias 's23-all' -TenantMapPath $Map -ErrorAction Stop
"Entries: directory $(@($Config.DirectoryRoles).Count), group $(@($Config.EntraIDGroups).Count), Azure $(@($Config.AzureRoles).Count); Environment: $($Config.Environment)"
"The file holds an Environment line: $([bool](Select-String -LiteralPath $Map -Pattern '^\s*Environment\s*=' -Quiet))"
$Before = & (Get-Module Omnicit.PIM) { @{ Graph = $script:_OPIMAuthState.GraphTokenExpiry; Arm = $script:_OPIMAuthState.ArmTokenExpiry } }
$Out = @(Connect-OPIM -TenantAlias 's23-all' -TenantMapPath $Map -IncludeARM -ErrorAction Stop 6>&1 3>&1)
$After = & (Get-Module Omnicit.PIM) { @{ Graph = $script:_OPIMAuthState.GraphTokenExpiry; Arm = $script:_OPIMAuthState.ArmTokenExpiry; Cloud = $script:_OPIMAuthState.Environment } }
"Connect-OPIM -TenantAlias s23-all: device codes $(@($Out | Where-Object { $_ -is [System.Management.Automation.InformationRecord] -and @($_.Tags) -contains 'OPIMDeviceCode' }).Count); tokens unchanged: $($Before.Graph -eq $After.Graph -and $Before.Arm -eq $After.Arm); session cloud: $($After.Cloud)"
```

**Expect:** `Rows to store: 3` (on the first run); `Entries: directory 1, group 1, Azure 1;
Environment: Global`; `The file holds an Environment line: False`; `device codes 0; tokens unchanged:
True; session cloud: Global`.
**Failure looks like:** another count -- record it, and do not run section 1 until the map holds the
three entries. An `Environment` line, or a device code -- a defect within this step's scope (G11).

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:40 UTC, window B: Rows to store: 3; Entries: directory 1, group 1, Azure 1; Environment: Global; The file holds an Environment line: False; Connect-OPIM -TenantAlias s23-all: device codes 0; tokens unchanged: True; session cloud: Global.
```

### 1.2. `pim` activates all three

- [x] **1.2** Window B. `pim -TenantAlias s23-all` activates the directory role, the group membership and Reader on `opim-s2-rg`, with no error, and all three are then listed as active.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s23/TenantMap.psd1'
$global:OpimS23Pim = [datetime]::UtcNow
$First = @(Enable-OPIMMyRole -TenantAlias 's23-all' -TenantMapPath $Map -Justification 'Omnicit.PIM step 3 live check 1.2' -Verbose 2>&1 3>&1 4>&1)
$Results = @($First | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' })
"First pim: results $($Results.Count); $(@($Results | ForEach-Object { '{0} {1} {2}' -f $_.Category, $_.DisplayName, $_.Status }) -join '; ')"
"Errors: $(@($First | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', '); warnings: $(@($First | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count)"
$global:OpimS23Throttle = @($First | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '(?i)throttl|Retry-After|\b(429|503|504)\b' }).Count
"Verbose lines of a throttled or retried Graph or ARM request: $global:OpimS23Throttle"
$Listed = @{}
while (([datetime]::UtcNow - $global:OpimS23Pim).TotalSeconds -lt 300 -and $Listed.Count -lt 3) {
    Start-Sleep -Seconds 15
    $Now = [int]([datetime]::UtcNow - $global:OpimS23Pim).TotalSeconds
    if (-not $Listed.ContainsKey('directory') -and @(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count -ge 1) { $Listed['directory'] = $Now }
    if (-not $Listed.ContainsKey('group') -and @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count -ge 1) { $Listed['group'] = $Now }
    if (-not $Listed.ContainsKey('Azure') -and @(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count -ge 1) { $Listed['Azure'] = $Now }
}
"Listed as active after (seconds): directory $($Listed['directory']), group $($Listed['group']), Azure $($Listed['Azure'])"
```

**Expect:** `First pim: results 3`, one row per kind (`DirectoryRole Usage Summary Reports Reader`,
`EntraIDGroup opim-s2-grp`, `AzureRole Reader`), each `Provisioned` or `Granted`; `Errors:` (none);
all three listed as active within 300 seconds.
**Record:** the seconds after which each kind was listed as active, and the count of throttle or
retry lines (1.6 reads it).
**Failure looks like:** fewer than three results, an error id, or a kind not listed within 300
seconds -- record it. A sign-in prompt -- STOP (0.1). An error naming a cloud or a host -- a defect
within this step's scope (G11).

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:40-05:41 UTC, window B: First pim: results 3; DirectoryRole Usage Summary Reports Reader Provisioned; EntraIDGroup opim-s2-grp Provisioned; AzureRole Reader Provisioned. Errors: (none); warnings: 0. Verbose lines of a throttled or retried Graph or ARM request: 0. Listed as active after (seconds, the first check after the call): directory 46, group 46, Azure 46.
```

### 1.3. A second `pim` sends nothing (G8)

- [x] **1.3** Window B. Once all three are listed as active, the same `pim` again writes "already active" for each and sends no request.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s23/TenantMap.psd1'
$Second = @(Enable-OPIMMyRole -TenantAlias 's23-all' -TenantMapPath $Map -Justification 'Omnicit.PIM step 3 live check 1.3' 2>&1 3>&1)
"Second pim, $([int]([datetime]::UtcNow - $global:OpimS23Pim).TotalSeconds) s after the first: results $(@($Second | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' }).Count); already active warnings $(@($Second | Where-Object { $_ -is [System.Management.Automation.WarningRecord] -and $_.Message -match 'already active' }).Count); errors $(@($Second | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', ')"
```

**Expect:** `results 0; already active warnings 3; errors` (none).
**Failure looks like:** a result, or `RoleAssignmentExists` -- a second request was sent: record it
(G8). ARM's and Graph's listing lag is known (OPIM-50, OPIM-53); 1.2 waits until each kind is
listed, so a second request here is a finding.

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:41 UTC, window B: Second pim, 54 s after the first: results 0; already active warnings 3; errors (none).
```

### 1.4. `unpim` deactivates all three after five minutes

- [x] **1.4** Window B. Five minutes after 1.2, `unpim -TenantAlias s23-all` deactivates all three, with no error.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s23/TenantMap.psd1'
$Wait = 320 - ([datetime]::UtcNow - $global:OpimS23Pim).TotalSeconds
if ($Wait -gt 0) { Start-Sleep -Seconds ([int][math]::Ceiling($Wait)) }
$global:OpimS23Unpim = [datetime]::UtcNow
$First = @(Disable-OPIMMyRole -TenantAlias 's23-all' -TenantMapPath $Map -Verbose 2>&1 3>&1 4>&1)
$Results = @($First | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' })
"First unpim: results $($Results.Count); $(@($Results | ForEach-Object { '{0} {1} {2}' -f $_.Category, $_.DisplayName, $_.Status }) -join '; ')"
"Errors: $(@($First | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', ')"
$global:OpimS23Throttle += @($First | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '(?i)throttl|Retry-After|\b(429|503|504)\b' }).Count
"Verbose lines of a throttled or retried Graph or ARM request, 1.2 and 1.4: $global:OpimS23Throttle"
```

**Expect:** `First unpim: results 3`, one row per kind, each `Revoked`; `Errors:` (none).
**Failure looks like:** `ActiveDurationTooShort` -- the five minutes were not waited out: run the block
again after a minute. Another error, or fewer results -- record it.

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:41-05:46 UTC, window B (the block waited until 320 s after 1.2's pim): First unpim: results 3; DirectoryRole Usage Summary Reports Reader Revoked; EntraIDGroup opim-s2-grp Revoked; AzureRole Reader Revoked. Errors: (none). Verbose lines of a throttled or retried Graph or ARM request, 1.2 and 1.4: 0.
```

### 1.5. A second `unpim` sends nothing (G8), and nothing is left active

- [x] **1.5** Window B. The same `unpim` again sends nothing and writes no error, and the listings show nothing active.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s23/TenantMap.psd1'
$Settled = $false
while (([datetime]::UtcNow - $global:OpimS23Unpim).TotalSeconds -lt 300 -and -not $Settled) {
    Start-Sleep -Seconds 15
    $Settled = (@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count + @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count + @(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count) -eq 0
}
"Listings settled after $([int]([datetime]::UtcNow - $global:OpimS23Unpim).TotalSeconds) s: $Settled"
$Second = @(Disable-OPIMMyRole -TenantAlias 's23-all' -TenantMapPath $Map 2>&1 3>&1)
"Second unpim: results $(@($Second | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' }).Count); errors $(@($Second | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count); other lines $(@($Second | Where-Object { $_ -is [System.Management.Automation.WarningRecord] -or $_ -is [string] }).Count)"
"Active: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** `Listings settled after ... s: True`; `Second unpim: results 0; errors 0`; `Active:
directory 0, group 0, Azure 0`.
**Record:** the seconds the listings took to settle, and the second call's other lines.
**Failure looks like:** a crash, or a second request -- record it (G8).

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:46 UTC, window B: Listings settled after 46 s: True; Second unpim: results 0; errors 0; other lines 0; Active: directory 0, group 0, Azure 0.
```

### 1.6. The Graph SDK's own retry of a POST (finding 6 of step 2)

- [~] **1.6** Window B, nothing to run. Whether the Graph SDK's own retry handler sent a POST of 1.2 or 1.4 again after a 503 or 504 that the module never saw.

**Record:** the count of throttle or retry lines from 1.2 and 1.4. The module writes a verbose line
only for a 429 or 503 that reaches it, after the Graph SDK's own retries; a 503 or 504 that the
SDK's handler retried and then answered with a success never reaches the module, and nothing the
module or this file can read shows it. With no such line, the check cannot be verified, and
therefore we do not know: it is marked `[~]` and reported as unmeasured. A line that names 503 or
504 for a POST is the measured case: record whether the role was then activated or deactivated once
(1.2 and 1.4 list one result per kind).
**Failure looks like:** two results for one kind in 1.2, or a `RoleAssignmentExists` there -- record
it as the measured resend.

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Cannot be verified, and therefore we do not know. 1.2 and 1.4 wrote 0 verbose lines of a throttled or retried Graph or ARM request, so no 429, 503 or 504 reached the module. Whether the Graph SDK's own retry handler sent a POST of 1.2 or 1.4 again after a 503 or 504 that it then answered itself is visible neither to the module nor to this file. 1.2 listed one result per kind and no RoleAssignmentExists, so no second activation was seen. Unmeasured; finding 6 of step 2 stays open.
```

### 2. A tenant alias in the US Government cloud (no sign-in in a sovereign cloud, P-12)

### 2.1. An alias that stores `USGov`

- [x] **2.1** Window B. `Install-OPIMConfiguration -Environment USGov` writes an alias for the test tenant with `Environment = 'USGov'` into a second map in the raw folder, and the alias reads as `USGov`.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Target = Get-OpimLiveTarget
$GovMap = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s23/TenantMap-usgov.psd1'
if (-not (Test-Path -LiteralPath $GovMap)) {
    Install-OPIMConfiguration -TenantAlias 's23-usgov' -TenantId $Target.TenantId -Environment USGov -TenantMapPath $GovMap -Confirm:$false 6>$null 3>$null
}
$Gov = Get-OPIMConfiguration -TenantAlias 's23-usgov' -TenantMapPath $GovMap -ErrorAction Stop
"Alias s23-usgov: Environment $($Gov.Environment); tenant is the test tenant: $([string]::Equals([string]$Gov.TenantId, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
"The file holds: $(@(Select-String -LiteralPath $GovMap -Pattern '^\s*Environment\s*=.*$' | ForEach-Object { $_.Line.Trim() }) -join ' | ')"
```

**Expect:** `Alias s23-usgov: Environment USGov; tenant is the test tenant: True`; `The file holds:
Environment    = 'USGov'`.
**Failure looks like:** another value -- a defect within this step's scope (G11).

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:46 UTC, window B: Alias s23-usgov: Environment USGov; tenant is the test tenant: True; The file holds: Environment    = 'USGov'.
```

### 2.2. The alias sends its sign-in to the US Government authority, where it is refused

- [x] **2.2** Window B, with the global session of 0.1 still signed in. `Connect-OPIM -TenantAlias s23-usgov` builds the module's MSAL application for the US Government authority and asks it for a device code for the test tenant; the authority refuses it, no device code is shown, nothing is signed in, and the global session is unchanged.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Target = Get-OpimLiveTarget
$GovMap = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s23/TenantMap-usgov.psd1'
$Before = & (Get-Module Omnicit.PIM) { @{ Graph = $script:_OPIMAuthState.GraphTokenExpiry; Arm = $script:_OPIMAuthState.ArmTokenExpiry; App = $script:_OPIMMsalApp } }
$Started = [datetime]::UtcNow
$Out = [System.Collections.Generic.List[object]]::new()
$Last = $null
try { Connect-OPIM -TenantAlias 's23-usgov' -TenantMapPath $GovMap -ErrorAction Stop 6>&1 3>&1 | ForEach-Object { $Out.Add($_) } } catch { $Last = $_ }
"Seconds: $([int]([datetime]::UtcNow - $Started).TotalSeconds)"
"Device codes shown: $(@($Out | Where-Object { $_ -is [System.Management.Automation.InformationRecord] -and @($_.Tags) -contains 'OPIMDeviceCode' }).Count)"
"Error: $($Last.FullyQualifiedErrorId) [$($Last.CategoryInfo.Category)]; AADSTS codes in it: $(@([regex]::Matches([string]$Last.Exception.Message + ' ' + [string]$Last.Exception.InnerException.Message, 'AADSTS\d+') | ForEach-Object Value | Select-Object -Unique) -join ', ')"
$App = & (Get-Module Omnicit.PIM) { $script:_OPIMMsalApp }
$AuthorityText = [string]$App.Authority; if (-not $AuthorityText) { $AuthorityText = [string]$App.AppConfig.Authority.AuthorityInfo.CanonicalAuthority }
"MSAL application rebuilt: $(-not [object]::ReferenceEquals($Before.App, $App)); its authority host: $(([uri]$AuthorityText).Host); its cloud: $(& (Get-Module Omnicit.PIM) { $script:_OPIMMsalAppEnvironment })"
$After = & (Get-Module Omnicit.PIM) { @{ Graph = $script:_OPIMAuthState.GraphTokenExpiry; Arm = $script:_OPIMAuthState.ArmTokenExpiry; Cloud = $script:_OPIMAuthState.Environment; Tid = $script:_OPIMAuthState.TokenTenantId } }
"Session unchanged: cloud $($After.Cloud), tokens unchanged $($Before.Graph -eq $After.Graph -and $Before.Arm -eq $After.Arm), still the test tenant $([string]::Equals([string]$After.Tid, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
"Graph SDK environment: $((Get-MgContext).Environment); AZURE_AUTHORITY_HOST is set: $(Test-Path -LiteralPath 'Env:AZURE_AUTHORITY_HOST')"
```

**Expect:** `Device codes shown: 0`; an error, its id recorded (`DeviceCodeAuthFailed` is the module's
id for a failed device code flow) with an AADSTS code; `MSAL application rebuilt: True; its authority
host: login.microsoftonline.us; its cloud: USGov`; `Session unchanged: cloud Global, tokens unchanged
True, still the test tenant True`; `Graph SDK environment: Global; AZURE_AUTHORITY_HOST is set:
False`.
**Record:** the seconds, the error id and the AADSTS code(s).
**Failure looks like:** a device code -- the US Government authority answered for the global test
tenant: do NOT complete it, let it expire (the block waits up to 15 minutes), and record it as a
finding. `login.microsoftonline.com`, or a changed global session -- the alias fell back to the
global cloud: STOP (a P0-family defect, G11 #3).

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:46-05:47 UTC, window B, with the global session of 0.1 signed in: Seconds: 1; Device codes shown: 0; Error: DeviceCodeAuthFailed,Initialize-OPIMAuth [AuthenticationError] (the block caught it under -ErrorAction Stop as Initialize-OPIMAuth raised it); AADSTS codes in it: AADSTS90038 (NationalCloudTenantRedirection: the tenant belongs to another national cloud); MSAL application rebuilt: True; its authority host: login.microsoftonline.us; its cloud: USGov; Session unchanged: cloud Global, tokens unchanged True, still the test tenant True; Graph SDK environment: Global; AZURE_AUTHORITY_HOST is set: False. The alias holds the real test tenant id, so a fallback to the global cloud would have shown a device code; none was shown.
```

### 2.3. The global session still works, and `-Environment` overrides the alias's cloud

- [x] **2.3** Window B. After 2.2 the global session lists the fixture with no sign-in, and `Connect-OPIM -TenantAlias s23-usgov -Environment Global -IncludeARM` is the global session.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$GovMap = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s23/TenantMap-usgov.psd1'
$Before = & (Get-Module Omnicit.PIM) { @{ Graph = $script:_OPIMAuthState.GraphTokenExpiry; Arm = $script:_OPIMAuthState.ArmTokenExpiry } }
$Reads = @(& { Get-OPIMDirectoryRole -ErrorAction Stop; Get-OPIMAzureRole -ErrorAction Stop } 6>&1)
"Eligible after 2.2: directory and Azure rows $(@($Reads | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] }).Count); device codes $(@($Reads | Where-Object { $_ -is [System.Management.Automation.InformationRecord] -and @($_.Tags) -contains 'OPIMDeviceCode' }).Count)"
$Out = @(Connect-OPIM -TenantAlias 's23-usgov' -TenantMapPath $GovMap -Environment Global -IncludeARM -ErrorAction Stop 6>&1 3>&1)
$After = & (Get-Module Omnicit.PIM) { @{ Graph = $script:_OPIMAuthState.GraphTokenExpiry; Arm = $script:_OPIMAuthState.ArmTokenExpiry; Cloud = $script:_OPIMAuthState.Environment } }
"Connect-OPIM -TenantAlias s23-usgov -Environment Global: device codes $(@($Out | Where-Object { $_ -is [System.Management.Automation.InformationRecord] -and @($_.Tags) -contains 'OPIMDeviceCode' }).Count); tokens unchanged $($Before.Graph -eq $After.Graph -and $Before.Arm -eq $After.Arm); session cloud $($After.Cloud)"
```

**Expect:** `directory and Azure rows 4; device codes 0`; `device codes 0; tokens unchanged True;
session cloud Global`.
**Failure looks like:** a device code -- the refused attempt in 2.2 cost the global session: record it
(G11). Do not complete the code.

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:47 UTC, window B: Eligible after 2.2: directory and Azure rows 4; device codes 0. Connect-OPIM -TenantAlias s23-usgov -Environment Global: device codes 0; tokens unchanged True; session cloud Global.
```

### 2.4. `pim` and `unpim` sign in to the alias's cloud

- [x] **2.4** Window B. `pim -TenantAlias s23-usgov` and `unpim -TenantAlias s23-usgov` send their sign-in to the US Government authority, where it is refused; nothing is listed, activated or deactivated, and the global session is unchanged.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$GovMap = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s23/TenantMap-usgov.psd1'
$Before = & (Get-Module Omnicit.PIM) { @{ Graph = $script:_OPIMAuthState.GraphTokenExpiry; Arm = $script:_OPIMAuthState.ArmTokenExpiry } }
foreach ($Command in 'Enable-OPIMMyRole', 'Disable-OPIMMyRole') {
    $Out = [System.Collections.Generic.List[object]]::new()
    $Caught = $null
    try { & $Command -TenantAlias 's23-usgov' -TenantMapPath $GovMap -ErrorAction Stop 6>&1 3>&1 | ForEach-Object { $Out.Add($_) } } catch { $Caught = $_ }
    $App = & (Get-Module Omnicit.PIM) { $script:_OPIMMsalApp }
    $AuthorityText = [string]$App.Authority; if (-not $AuthorityText) { $AuthorityText = [string]$App.AppConfig.Authority.AuthorityInfo.CanonicalAuthority }
    "$($Command): results $(@($Out | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' }).Count); device codes $(@($Out | Where-Object { $_ -is [System.Management.Automation.InformationRecord] -and @($_.Tags) -contains 'OPIMDeviceCode' }).Count); error $($Caught.FullyQualifiedErrorId); MSAL authority host $(([uri]$AuthorityText).Host)"
}
$After = & (Get-Module Omnicit.PIM) { @{ Graph = $script:_OPIMAuthState.GraphTokenExpiry; Arm = $script:_OPIMAuthState.ArmTokenExpiry; Cloud = $script:_OPIMAuthState.Environment } }
"Session unchanged: cloud $($After.Cloud), tokens unchanged $($Before.Graph -eq $After.Graph -and $Before.Arm -eq $After.Arm); AZURE_AUTHORITY_HOST is set: $(Test-Path -LiteralPath 'Env:AZURE_AUTHORITY_HOST')"
"Active: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** for each command `results 0; device codes 0`, the error of the refused sign-in, written
by that command, `MSAL authority host login.microsoftonline.us`; `Session unchanged: cloud Global,
tokens unchanged True; AZURE_AUTHORITY_HOST is set: False`; `Active: directory 0, group 0, Azure 0`.
**Record:** the error ids.
**Failure looks like:** a result, a device code, or `login.microsoftonline.com` -- the alias's cloud
was not used: STOP (G11 #3).

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:47 UTC, window B: Enable-OPIMMyRole: results 0; device codes 0; error DeviceCodeAuthFailed,Enable-OPIMMyRole; MSAL authority host login.microsoftonline.us. Disable-OPIMMyRole: results 0; device codes 0; error DeviceCodeAuthFailed,Disable-OPIMMyRole; MSAL authority host login.microsoftonline.us. Session unchanged: cloud Global, tokens unchanged True; AZURE_AUTHORITY_HOST is set: False. Active: directory 0, group 0, Azure 0.
```

### 2.5. An alias with a cloud the module does not know is refused before any sign-in

- [x] **2.5** Window B. A third map in the raw folder whose alias stores `Environment = 'Germany'` makes `Connect-OPIM` and `pim` write an error with no error id of their own, category `InvalidArgument`, and touch no sign-in: the MSAL application is not rebuilt.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Target = Get-OpimLiveTarget
$BadMap = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s23/TenantMap-unknown.psd1'
# Written by hand: Install- and Set-OPIMConfiguration refuse a cloud outside their ValidateSet.
"@{`n    's23-unknown' = @{`n        TenantId       = '$($Target.TenantId)'`n        Environment    = 'Germany'`n    }`n}" | Set-Content -LiteralPath $BadMap -Encoding utf8
$Before = & (Get-Module Omnicit.PIM) { $script:_OPIMMsalApp }
$Out = [System.Collections.Generic.List[object]]::new()
$Err = $null
try { Connect-OPIM -TenantAlias 's23-unknown' -TenantMapPath $BadMap -ErrorAction Stop 6>&1 3>&1 | ForEach-Object { $Out.Add($_) } } catch { $Err = $_ }
"Connect-OPIM: error id '$($Err.FullyQualifiedErrorId)' [$($Err.CategoryInfo.Category)]; names Germany: $($Err.Exception.Message -match 'Germany'); suggests the quoted alias: $($Err.Exception.Message.Contains("-TenantAlias 's23-unknown'")); device codes $(@($Out | Where-Object { $_ -is [System.Management.Automation.InformationRecord] }).Count)"
$Out = [System.Collections.Generic.List[object]]::new()
$Err = $null
try { Enable-OPIMMyRole -TenantAlias 's23-unknown' -TenantMapPath $BadMap -ErrorAction Stop 6>&1 3>&1 | ForEach-Object { $Out.Add($_) } } catch { $Err = $_ }
"pim: error id '$($Err.FullyQualifiedErrorId)' [$($Err.CategoryInfo.Category)]; results $(@($Out | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' }).Count)"
"MSAL application untouched: $([object]::ReferenceEquals($Before, (& (Get-Module Omnicit.PIM) { $script:_OPIMMsalApp })))"
```

**Expect:** `Connect-OPIM: error id 'Connect-OPIM' [InvalidArgument]; names Germany: True; suggests
the quoted alias: True; device codes 0`; `pim: error id 'Enable-OPIMMyRole' [InvalidArgument]; results 0`; `MSAL application
untouched: True`.
**Failure looks like:** a sign-in attempt (a rebuilt MSAL application) or a fallback to the global
cloud -- a defect within this step's scope (G11; a fallback is G11 #3).

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:47 UTC, window B: Connect-OPIM: error id 'Connect-OPIM' [InvalidArgument]; names Germany: True; suggests the quoted alias: True; device codes 0. pim: error id 'Enable-OPIMMyRole' [InvalidArgument]; results 0. MSAL application untouched: True.
```

## Teardown

This step created no object in the tenant, so nothing is removed from it. The checks verify that
nothing is left active, that no object carries the step's prefix, that no window keeps a session or
an `AZURE_AUTHORITY_HOST`, and that the raw folder with the three tenant maps is gone.

### T.1. Nothing is left active

- [x] **T.1** Window B. The test user has no active directory role, group assignment or Azure role.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
"Active: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** `Active: directory 0, group 0, Azure 0`.
**Failure looks like:** an active role -- deactivate it (after five minutes) and record it. A
terminating error is a failed read, never a `0`.

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:47 UTC, window B: Active: directory 0, group 0, Azure 0.
```

### T.2. Window B signs out

- [x] **T.2** Window B. The window's session is cleared, `AZURE_AUTHORITY_HOST` is not set, no Az module is loaded, and the window ended.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not (Get-Module Omnicit.PIM)) { throw 'Omnicit.PIM is not loaded in this window; run 0.1 first.' }
if ((Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
Disconnect-OPIM
try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { $null = $PSItem }
"Module state cleared: $($null -eq (& (Get-Module Omnicit.PIM) { $script:_OPIMAuthState })); MSAL cloud cleared: $($null -eq (& (Get-Module Omnicit.PIM) { $script:_OPIMMsalAppEnvironment })); Graph context left: $([bool](Get-MgContext))"
"AZURE_AUTHORITY_HOST is set: $(Test-Path -LiteralPath 'Env:AZURE_AUTHORITY_HOST'); Az modules loaded: $(@(Get-Module -Name 'Az', 'Az.*').Count)"
```

**Expect:** `Module state cleared: True; MSAL cloud cleared: True; Graph context left: False`;
`AZURE_AUTHORITY_HOST is set: False; Az modules loaded: 0`.
**Failure looks like:** `False` / `True` -- record it, and end the window.

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:47 UTC, window B: Module state cleared: True; MSAL cloud cleared: True; Graph context left: False; AZURE_AUTHORITY_HOST is set: False; Az modules loaded: 0. Window B ended 05:47 UTC. (The first window B was signed out the same way at 05:39 UTC and ended.)
```

### T.3. No object of the step, and the raw folder

- [x] **T.3** Window A, then the operator. No object carries `opim-s23-`; the raw folder, with the three tenant maps, is deleted once the results are written up.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$null = Import-OerLiveConfig -Prefix 'opim-s23-'
Connect-OerLive -Graph
"Objects with the prefix opim-s23-: $(@(Find-OerLivePrefixed -Prefix 'opim-s23-' -ThrowOnUnread -Quiet).Count)"
Disconnect-OerLive
Remove-Item -LiteralPath 'docs/live-verification/raw/opim-s23' -Recurse -Force
"Raw folder gone: $(-not (Test-Path -LiteralPath 'docs/live-verification/raw/opim-s23'))"
"Untracked files under docs/live-verification: $(@(git status --porcelain --untracked-files=all -- docs/live-verification | Where-Object { $_.StartsWith('??') }).Count)"
```

**Expect:** `Objects with the prefix opim-s23-: 0`; `Raw folder gone: True`; `Untracked files under
docs/live-verification: 0`.
**Failure looks like:** a prefixed object -- STOP (it was not made by this file). The fixture
`opim-s2-` stays on purpose until step 5.

Result: 2026-10-10 05:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
05:47 UTC, window A as oer-live-cc, after window B had ended: every oer-live-cc identity line True; Objects with the prefix opim-s23-: 0; Raw folder gone: True; Untracked files under docs/live-verification: 0. The fixture opim-s2- stays until step 5.
```
