# Live verification checklist -- the module signs in with a device code, and a harness signs the test user in without a person (feat/device-code-sign-in)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

Where a check says **Record:** instead of **Expect:**, the outcome is genuinely not known in
advance. Write down what actually happened rather than what looked plausible.

**This file runs only in the operator's designated test tenant** -- never a customer tenant -- and
only when the operator has asked for the run. The module runs there as the dedicated delegated test
user `opim-s1-live-user`, and setup and teardown run as the dedicated app identity `oer-live-cc`,
whose only credential is a certificate; neither is ever the operator's own account. The run writes
to nothing outside the prefixes `opim-s1-` (the sprint's fixture) and `opim-s12-` (this step's own
objects, of which there are none). Check 0.1 proves the identity before any other check calls the
module. If a browser window or a sign-in prompt appears mid-run, STOP and run check 0.1 again: in
this file every sign-in is a device code, and the proof of 0.1 holds only for the sign-in it checked.

**Two windows, never one process** (decision A10). Window A runs the prerequisite script as
`oer-live-cc`; window B runs the module as the test user. The Microsoft Graph SDK holds one session
per process, so the two never share one. Every block below names its window.

## What changed and why this needs a live tenant

- **A. Device code sign-in** ("feat: sign in to Graph and Azure with a device code when asked").
  `Initialize-OPIMAuth` takes `-DeviceCode`, acquires the Graph token with MSAL's device code flow,
  writes the sign-in message to the Information stream with the tag `OPIMDeviceCode`, remembers the
  mode in its auth state for every later sign-in, and signs in to Azure with
  `Connect-AzAccount -UseDeviceAuthentication`. A mock cannot show that MSAL's callback really reaches
  the message, that Microsoft Entra accepts the flow for the Microsoft Graph Command Line Tools app,
  or that the module's next refresh stays silent.
- **B. The public switch** ("feat: add -DeviceCode to Connect-OPIM, Enable-OPIMMyRole and
  Disable-OPIMMyRole"). The sign-in runs through `Connect-OPIM -DeviceCode` here.
- **C. The live harness** (outside the repository, in the operator's notes): `OpimLive.psm1`
  completes each device code in Microsoft Edge through Playwright with the test user's password and a
  TOTP code from the SecretStore, and the prerequisite script `Initialize-OpimS1Prereq.ps1` creates
  the fixture as `oer-live-cc`. This run is their first.

The fixture, created by the prerequisite script and kept until the sprint's last step (decision A9):
the test user `opim-s1-live-user`, the security group `opim-s1-grp`, the resource groups `opim-s1-rg`
and `opim-s1-rg2`, and the test user's eligibilities, each for 30 days -- the directory roles Usage
Summary Reports Reader and Message Center Privacy Reader at `/`, `opim-s1-grp` as member and as
owner, and Reader on both resource groups. Nothing in this file creates an object.

## What this file does not check, and why

- **Without `-DeviceCode` the sign-in is unchanged** -- the existing tests of
  `tests/Unit/Private/Initialize-OPIMAuth.Tests.ps1` and `tests/Unit/Public/Connect-OPIM.Tests.ps1`
  stay green, and the new ones prove the switch is not passed without it.
- **The ACRS step-up in device code mode** (`WithClaims` on the device code request) --
  `tests/Unit/Private/Invoke-OPIMDeviceCodeAuth.Tests.ps1` and
  `tests/Unit/Private/Invoke-OPIMGraphRequest.Tests.ps1`; the test roles carry no authentication
  context, so no live claims challenge is possible.
- **A device code flow that expires** and **a null token** (never the browser) --
  `tests/Unit/Private/Invoke-OPIMDeviceCodeAuth.Tests.ps1` and
  `tests/Unit/Private/Initialize-OPIMAuth.Tests.ps1`. A declined code is checked live in 1.5, since a
  unit test runs inside a `try` and cannot show what a person sees after a failed sign-in.
- **`Enable-OPIMMyRole -DeviceCode` and `Disable-OPIMMyRole -DeviceCode`** pass the switch to
  `Connect-OPIM` -- `tests/Unit/Public/Enable-OPIMMyRole.Tests.ps1` and
  `tests/Unit/Public/Disable-OPIMMyRole.Tests.ps1`; the sign-in itself is the same `Connect-OPIM`
  path this file runs.
- **The bugs the step measures but does not fix** (OPIM-14, OPIM-18, OPIM-23, OPIM-24) -- section 4
  records the baseline; the fixes and their tests come in later steps.

## Setup, once

The operator sets `OPIMLIVE_HOME` in both windows to the notes folder that holds
`Initialize-OpimS1Prereq.ps1` and the `OpimLive` folder; no checklist holds that path. The test
user's sign-in name and the test tenant's id are read by the harness through OerLive and are never
printed. Window B runs from the repository root, and its console output must also reach a file named in `OPIMLIVE_HOSTLOG`: Az.Accounts 5.5.3 writes the Azure device code to the host only, and `Connect-OpimLiveUser -IncludeARM` reads it there from a helper process (OpimLive 1.0.2).

### S.1. Find the build under test and tie it to the branch head

- [x] **S.1** Window B. The newest build in `output/module/Omnicit.PIM/` was made after the branch head was committed.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$HeadTime = [datetimeoffset]::Parse((git log -1 --format=%cI))
"Branch head: $(git log -1 --format='%h %s')"
"Built version folder: $($Built.Directory.Name)"
"Built after the branch head was committed: $([datetimeoffset]$Built.LastWriteTime -gt $HeadTime)"
"Tracked changes in the working tree: $(@(git status --porcelain --untracked-files=no).Count)"
```

**Expect:** the branch head's hash and subject; the version folder the branch's build printed;
`Built after the branch head was committed: True`; `Tracked changes in the working tree: 0`.
**Failure looks like:** `False`, or a tracked change -- build again before any check below.

Result: 2026-10-06 15:04 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Window B, 2026-10-06 14:25 UTC, the round 1 worktree (local branch opim-s1-steg2-r1, pushed as feat/device-code-sign-in).
Branch head: 23f7662 docs: correct the Connect-OPIM line reference and the device-code-only state
Built version folder: 0.6.0
Built after the branch head was committed: True
Tracked changes in the working tree: 0
```

### S.2. P-4 is in place and the harness loads

- [x] **S.2** Window B. OerLive is 1.0.3, the harness reads the test values through it, and the TOTP implementation reproduces RFC 6238.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME 'OpimLive/OpimLive.psm1') -Force
$Target = Get-OpimLiveTarget
"OerLive version: $((Get-OerLiveState).Version)"
"Test user and tenant read (values hidden): $([bool]$Target.UserPrincipalName -and [bool]$Target.TenantId)"
"TOTP self-test: $(Get-OpimLiveTotp -SelfTest)"
```

**Expect:** `OerLive version: 1.0.3`; both other lines `True`.
**Failure looks like:** `STOP: P-4` from `Get-OpimLiveTarget` (OerLive is older than 1.0.3) -- STOP,
the step waits for P-4. `False` on the self-test -- STOP: the harness would enter wrong codes.

Result: 2026-10-06 15:04 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
OerLive version: 1.0.3
Test user and tenant read (values hidden): True
TOTP self-test: True
```

### S.3. Playwright is installed, and no browser was downloaded

- [x] **S.3** Window B. `playwright-core` is installed in the harness's own folder and loads; Edge is the browser.

```powershell
& (Join-Path $env:OPIMLIVE_HOME 'OpimLive/Install-OpimLivePlaywright.ps1') -WhatIf
& (Join-Path $env:OPIMLIVE_HOME 'OpimLive/Install-OpimLivePlaywright.ps1')
```

**Expect:** the plan line from `-WhatIf`, then `Microsoft Edge is installed: True`, the installed
version and `Node can load it: True`.
**Failure looks like:** an npm error or `False` -- STOP: nothing below can complete a sign-in.

Result: 2026-10-06 15:04 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
What if: Performing the operation "npm install playwright-core@^1 (no browser download, no install scripts)" on target "%LOCALAPPDATA%\OpimLive\node".
Microsoft Edge is installed: True
added 1 package in 18s
playwright-core 1.63.0 in %LOCALAPPDATA%\OpimLive\node; Node can load it: True
No Playwright browser was downloaded: True
```

### S.4. The prerequisite plan names only prefixed targets

- [x] **S.4** Window A, as `oer-live-cc`. The prerequisite script's `-WhatIf` plan writes nothing and every target in the tenant or the vault starts with `opim-s1-`.

```powershell
New-Item -ItemType Directory -Force -Path 'docs/live-verification/raw/opim-s12' | Out-Null
$Out = @(& pwsh -NoProfile -File (Join-Path $env:OPIMLIVE_HOME 'Initialize-OpimS1Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
$Out | Set-Content -Path 'docs/live-verification/raw/opim-s12/prereq-whatif.txt'
$Targets = @($Out | Select-String -Pattern 'on target "(.+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value })
$InTenant = @($Targets | Where-Object { $_ -notlike 'raw\*' })
"What-if targets: $($Targets.Count); in the tenant or the vault: $($InTenant.Count)"
"Targets without the prefix opim-s1-: $(@($InTenant | Where-Object { $_ -notlike 'opim-s1-*' }).Count)"
"Lines with STOP: $(@($Out | Select-String -Pattern 'STOP').Count)"
$InTenant
```

**Expect:** ten targets in the tenant or the vault on a first run (the user with its password into the
vault, the group, two directory role, two group and two Azure eligibilities, two resource groups), `0` without
the prefix and `0` lines with STOP; the list names only `opim-s1-` objects. The identity check lines
of `oer-live-cc`, which the block writes to `prereq-whatif.txt` and does not print, are all `True`
there.
**Failure looks like:** a target without the prefix -- STOP (stop condition: a target without the
step's or the fixture's prefix). A STOP line -- STOP and record it: a policy that requires approval or
an authentication context, or a 401 or 403 on `oer-live-cc`'s path (section 5).

Result: 2026-10-06 15:04 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
What-if targets: 12; in the tenant or the vault: 10
Targets without the prefix opim-s1-: 0
Lines with STOP: 0
opim-s1-live-user (enabled, no licence, password into the vault only)
opim-s1-grp (security group)
opim-s1-live-user: eligible for directory role 'Usage Summary Reports Reader' at '/' for 30 days
opim-s1-live-user: eligible for directory role 'Message Center Privacy Reader' at '/' for 30 days
opim-s1-grp: opim-s1-live-user eligible as member for 30 days
opim-s1-grp: opim-s1-live-user eligible as owner for 30 days
opim-s1-rg (location swedencentral)
opim-s1-rg: opim-s1-live-user eligible as Reader for 30 days
opim-s1-rg2 (location swedencentral)
opim-s1-rg2: opim-s1-live-user eligible as Reader for 30 days
Every identity check line of oer-live-cc (Graph and ARM): True. Residue: raw\residue.json holds no rows.
```

### S.5. The prerequisite script creates the fixture

- [x] **S.5** Window A, as `oer-live-cc`. The fixture exists and reads back as expected.

```powershell
$Out = @(& pwsh -NoProfile -File (Join-Path $env:OPIMLIVE_HOME 'Initialize-OpimS1Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Out | Set-Content -Path 'docs/live-verification/raw/opim-s12/prereq.txt'
$Out | Select-String -Pattern 'identity check|PIM policy of|Created:|exists; kept|Read back|Sweep|STOP'
```

**Expect:** every identity check line `True`; for each of the two directory roles, both access
types of `opim-s1-grp` and Reader on both resource groups a policy line with `approval required:
False; authentication context: False`; `Read back as oer-live-cc: directory role eligibilities 2
(expected 2), group eligibilities 2 (expected 2), Azure eligibilities 2 (expected 2)`; the sweep after
the prerequisite shows 1 user, 1 group and 0 other objects with the prefix.
**Failure looks like:** a STOP line -- STOP and record it in section 5. A count other than 2 -- STOP:
the fixture is not the one this file assumes.

Result: 2026-10-06 15:04 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run 1, 14:27 UTC: stopped before the first tenant write. Creating the SecretStore (harness 1.0.0, Set-SecretStoreConfiguration
-Authentication None) first created a store with the default configuration and waited at the console for a store password.
Nothing was created in the tenant. Harness 1.0.1 creates a store without data with Reset-SecretStore -Authentication None
-Interaction None (store: authentication None, interaction None, vault OpimLive, 0 secrets before the run).

Run 2, 14:39-14:40 UTC, as oer-live-cc:
Every identity check line (Graph and ARM): True. Residue: raw\residue.json holds no rows.
Stored opim-s1-live-user-password in the vault OpimLive (value not shown).
Created: opim-s1-live-user.
Created: opim-s1-grp.
Created: opim-s1-live-user: eligible for directory role 'Usage Summary Reports Reader' at '/' for 30 days (Provisioned, 2 attempt(s)).
Created: opim-s1-live-user: eligible for directory role 'Message Center Privacy Reader' at '/' for 30 days (Provisioned, 1 attempt(s)).
Created: opim-s1-grp: opim-s1-live-user eligible as member for 30 days (Provisioned, 1 attempt(s)).
Created: opim-s1-grp: opim-s1-live-user eligible as owner for 30 days (Provisioned, 1 attempt(s)).
Created: opim-s1-rg. Created: opim-s1-rg: opim-s1-live-user eligible as Reader for 30 days (Provisioned, 1 attempt(s)).
Created: opim-s1-rg2. Created: opim-s1-rg2: opim-s1-live-user eligible as Reader for 30 days (Provisioned, 1 attempt(s)).
Six policy lines, each "approval required: False; authentication context: False" (see 5.3).
Read back as oer-live-cc: directory role eligibilities 2 (expected 2), group eligibilities 2 (expected 2), Azure eligibilities 2 (expected 2).
Sweep after the prereq: 1 user(s), 1 group(s), 0 other object(s) with the prefix.
```

### S.6. The test user's first sign-in registers its TOTP

- [~] **S.6** Window B. The harness registers a software TOTP method for the test user, and the key is in the vault (the spec's first 1.x item; it runs here because every sign-in below needs it).

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME 'OpimLive/OpimLive.psm1') -Force
$Registered = Register-OpimLiveTotp -Confirm:$false
"Registration: $($Registered.Status) at $($Registered.Step)"
"The key is in the vault: $($Registered.KeyStored)"
```

**Expect:** `Registration: ok at registered` and `The key is in the vault: True`. No screenshot was
taken after the authenticator setup started (only the folder's earlier files exist).
**Record:** whether Security info showed the registration interrupt or the page itself.
**Failure looks like:** `registration-blocked` -- STOP (stop condition: registration needs a trusted
location, a Temporary Access Pass or a compliant device; check 5.2). `password-change-required` or
`mfa-already-registered` -- STOP: the fixture is not the one this file assumes.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Not by the harness; registered by hand by the operator, on the operator's decision.
Harness runs 1-15 (from 14:41 UTC): runs 1-2 timed out at the unknown interrupt "Let's keep your account secure" (handled
from harness 1.0.1); runs 3-15 passed it, and each time Microsoft Edge 154.0.4258.48 under Playwright crashed (exit code
3221225477, 0xC0000005, the browser process) as the registration wizard opened -- headless and headed, with the sandbox,
without Playwright's default flags, with --disable-gpu, and with WebAuthn and 15 more navigator APIs hidden. Run 16
(15:54 UTC, after the operator's Conditional Access exclusions): the same crash. The operator's own InPrivate Edge did
not crash on the same page.
The operator then registered the method with OpimLive\Register-OpimLiveTotpByHand.ps1: Security info shows
"Authenticator app -- Time-based one-time password (TOTP)"; the key is in the vault: True.
Tenant changes the operator made for the test user on the way (each on the operator's decision): exclusions from the
Conditional Access policies that require phishing-resistant MFA and that block the device code flow, an assignment to
the enterprise app Microsoft Graph Command Line Tools (AADSTS50105 before it), and an exclusion from the Microsoft
Authenticator registration campaign.
```

### 0. Preparation

### 0.1. Identity check

- [x] **0.1** Window B. `Connect-OpimLiveUser` without `-IncludeARM` signs the module in with one device code, and the account is the test user and the tenant the test tenant.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
Import-Module (Join-Path $env:OPIMLIVE_HOME 'OpimLive/OpimLive.psm1') -Force
$Sign = Connect-OpimLiveUser
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
```

**Expect:** `Disconnect-OPIM, Disconnect-MgGraph and Disconnect-AzAccount ran first`; one row
`Graph Information True ok`; then the line `Signed in to Graph as the test user` (with its source in
parentheses) ending `True`, `Signed in to the test tenant: True` and `The module remembers the device
code mode: True`. No browser window appeared (the
harness's Edge runs headless), and the block prints neither the account nor the tenant id.
**Failure looks like:** `False` on any line, or a `STOP` -- STOP: run `Disconnect-OPIM`, close the
window and run no other check. A `blocked` status is stop condition 5.1.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Attempts before the pass: 18:46 UTC "You don't have access to this" after the password (Conditional Access, device code
flow; see 5.1); 19:04 UTC AADSTS50105 after the TOTP code (the app required an assignment); 19:17 UTC timeout at
"Improve your sign-ins" (the Microsoft Authenticator nudge; harness 1.0.2 skips it while a skip is left).
Pass, 19:19 UTC, harness 1.0.2:
Disconnect-OPIM, Disconnect-MgGraph and Disconnect-AzAccount ran first.
Edge: skip the Microsoft Authenticator nudge (Skip for now (3 times left)); confirm the expected app; signed in.
Device code for Graph: stream Information, tag OPIMDeviceCode True, sign-in ok.
Signed in to Graph as the test user (Get-MgContext): True
Signed in to the test tenant: True
The module remembers the device code mode: True
App   Stream      Tagged Status
Graph Information   True ok
No browser window appeared (Edge ran headless). MSAL's real types (AcquireTokenWithDeviceCode through reflection, the
compiled callback, DeviceCodeResult.Message) work live: the message arrived with the tag and the token was issued.
```

### 1. The sign-in

### 1.1. A second cmdlet in the same process does not sign in again

- [x] **1.1** Window B. `Get-OPIMDirectoryRole` after 0.1 writes no device code message and lists the eligible roles.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Records = @(Get-OPIMDirectoryRole -ErrorAction Stop 6>&1)
"Device code messages: $(@($Records | Where-Object { $_ -is [System.Management.Automation.InformationRecord] -and $_.Tags -contains 'OPIMDeviceCode' }).Count)"
"Eligible directory roles listed: $(@($Records | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] }).Count)"
```

**Expect:** `Device code messages: 0` and `Eligible directory roles listed: 2`.
**Failure looks like:** a device code message -- the cached session was not reused; record it. A
terminating error is a failed read, never a pass.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Device code messages: 0
Eligible directory roles listed: 2
```

### 1.2. With `-IncludeARM`, Graph and Azure each sign in with a device code

- [x] **1.2** Window B. `Connect-OpimLiveUser -IncludeARM` completes two device codes, the Graph one on the Information stream with the tag and the Azure one from `Connect-AzAccount`'s own output (Az.Accounts 5.5.3 writes it to the host; the harness reads it in a helper process).

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Sign = Connect-OpimLiveUser -IncludeARM
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
```

**Expect:** two rows, `Graph Information True ok` and `Azure Host False ok`, and every True/False
line `True`, the two Azure lines included.
**Record:** whether the Azure device code arrived while `Connect-AzAccount` was still waiting (it
must, or the block hangs until the code expires), and how many seconds the block took.
**Failure looks like:** a hang with one row -- the Azure message did not reach the pipeline while
Connect-AzAccount waited; stop the block, record it, and STOP the Azure part (a harness change, not a
module change). `False` -- STOP as in 0.1.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Pass, 20:35 UTC, harness 1.0.2, in 44 s:
Device code for Graph: stream Information, tag OPIMDeviceCode True, sign-in ok.
Device code for Azure: stream Host, tag OPIMDeviceCode False, sign-in ok.
Signed in to Graph as the test user (Get-MgContext): True; test tenant: True; device code mode remembered: True
Azure context is the test user: True; Azure context is the test tenant: True
App   Stream      Tagged Status
Graph Information   True ok
Azure Host         False ok
Recorded: the Azure code arrived while Connect-AzAccount was still waiting, about 1 s after the Graph sign-in.
Before the pass (19:21-20:33 UTC) the Azure part hung until the code expired after 15 minutes ("a hang with one row"):
Az.Accounts 5.5.3 writes its code as an information record from inside Connect-AzAccount's own wait loop, not as a
warning, and harness code run in the module's process at that moment did not get past its first steps (in the
pipeline and in a thread job alike), while Az's host output reaches no transcript. Harness 1.0.2 therefore signs Graph in
first and, in a second Connect-OPIM -DeviceCode -IncludeARM call (Graph cached, only the module's Azure step runs),
lets a helper process read the Azure code from the window's console output. The module itself delivers the Azure code
in 0.7 s when nothing else runs (separate measurement, 19:58 UTC); nothing in the module changed.
```

### 1.3. A forced refresh stays silent and keeps the device code mode

- [x] **1.3** Window B. The refresh that the module's token-rejected retry runs completes without a device code and keeps the mode.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Module = Get-Module Omnicit.PIM
$Target = Get-OpimLiveTarget
$Records = @(& $Module { param($TenantId) Initialize-OPIMAuth -TenantId $TenantId -ForceRefresh } $Target.TenantId 6>&1)
"Device code messages: $(@($Records | Where-Object { $_ -is [System.Management.Automation.InformationRecord] -and $_.Tags -contains 'OPIMDeviceCode' }).Count)"
"Device code mode kept: $([bool](& $Module { $script:_OPIMAuthState }).DeviceCode)"
```

**Record:** both lines. A silent refresh prints `0` and `True` within seconds.
**Failure looks like:** a device code message -- the refresh token was not used. The block then waits
for a code nobody completes: if it has not returned within 30 seconds, press Ctrl+C, record a
non-silent refresh, and run 0.1 again before going on.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Device code messages: 0
Device code mode kept: True
The block returned within a second.
```

### 1.4. Disconnect-OPIM clears the mode, and the next sign-in is a device code again

- [x] **1.4** Window B. After `Disconnect-OPIM` the auth state is gone, and `Connect-OpimLiveUser -IncludeARM` signs in with device codes, never a browser.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
Disconnect-OPIM
"Auth state cleared: $($null -eq (& (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }))"
$Sign = Connect-OpimLiveUser -IncludeARM -NoDisconnect
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
```

**Expect:** `Auth state cleared: True`; then the two rows of 1.2 and every True/False line `True`.
**Failure looks like:** a browser window -- STOP: the mode was not passed again. `False` -- STOP as in 0.1.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Auth state cleared: True
Device code for Graph: stream Information, tag OPIMDeviceCode True, sign-in ok.
Device code for Azure: stream Host, tag OPIMDeviceCode False, sign-in ok.
Every True/False line True, the two Azure lines included. No browser window.
```

### 1.5. A declined device code ends with one error and keeps the mode

- [x] **1.5** Window B. A device code declined on the confirmation page ends `Connect-OPIM -DeviceCode` with `DeviceCodeAuthFailed` alone, no browser opens, the mode stays, and the next sign-in is a device code again.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
Import-Module (Join-Path $env:OPIMLIVE_HOME 'OpimLive/OpimLive.psm1') -Force
$Target = Get-OpimLiveTarget
Disconnect-OPIM
$Seen = [System.Collections.Generic.List[string]]::new()
try { Connect-OPIM -DeviceCode -TenantId $Target.TenantId 6>&1 2>&1 | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) { $Seen.Add($_.FullyQualifiedErrorId); return }
    if ($_ -is [System.Management.Automation.InformationRecord] -and $_.Tags -contains 'OPIMDeviceCode' -and "$($_.MessageData)" -match 'enter the code\s+([A-Z0-9]{6,16})') {
        $Done = Complete-OpimLiveDeviceCode -Code $Matches[1] -App Graph -UserPrincipalName $Target.UserPrincipalName -RawFolder 'docs/live-verification/raw/opim-s12' -Decline
        "Edge: $($Done.Status)"
    }
} } catch { $Seen.Add($_.FullyQualifiedErrorId) }
"Errors: $($Seen.Count): $($Seen -join ', ')"
"Device code mode kept: $([bool](& (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }).DeviceCode)"
$Sign = Connect-OpimLiveUser -IncludeARM -NoDisconnect
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
```

**Expect:** `Edge: declined`; `Errors: 1: DeviceCodeAuthFailed,Initialize-OPIMAuth` (the error is terminating by design, so the block catches it); `Device code
mode kept: True`; no browser window; then the two rows of 1.2 and every True/False line `True`, which
leaves the window signed in for section 2.
**Failure looks like:** a second error such as `NoAccessToken`, `Device code mode kept: False`, or a
browser window -- record it; the failure path is not what the module promises. `False` after the new
sign-in -- STOP as in 0.1.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run with the corrected block (the error is terminating by design, ruling 15, so the block catches it):
Edge: declined
Errors: 1: DeviceCodeAuthFailed,Initialize-OPIMAuth
Device code mode kept: True
No browser window; no NoAccessToken. The cause in the error: AADSTS700171 (end-user declined).
Then Graph Information True ok and Azure Host False ok, every True/False line True.
The first run with the original block: Edge declined, the module raised only DeviceCodeAuthFailed (from
Invoke-OPIMDeviceCodeAuth, rethrown by Initialize-OPIMAuth), and the terminating error ended the block before its
summary lines, since 2>&1 does not capture a terminating error.
```

### 2. The listings

### 2.1. Exactly the two directory roles

- [x] **2.1** Window B. `Get-OPIMDirectoryRole` lists exactly the fixture's two directory roles at `/`.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Rows = @(Get-OPIMDirectoryRole -ErrorAction Stop)
"Eligible directory roles: $($Rows.Count)"
"All are the fixture's roles at '/': $(@($Rows | Where-Object { $_.roleDefinition.displayName -in 'Usage Summary Reports Reader', 'Message Center Privacy Reader' -and $_.directoryScopeId -eq '/' }).Count -eq $Rows.Count)"
```

**Expect:** `Eligible directory roles: 2` and `True`.
**Failure looks like:** another count or `False` -- record the role names and STOP. A terminating
error is a failed read, never a `0` and never a pass.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Eligible directory roles: 2
All are the fixture's roles at '/': True
```

### 2.2. Exactly the two group eligibilities

- [x] **2.2** Window B. `Get-OPIMEntraIDGroup` lists `opim-s1-grp` as member and as owner, and nothing else.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Rows = @(Get-OPIMEntraIDGroup -ErrorAction Stop)
"Eligible group assignments: $($Rows.Count)"
"All are opim-s1-grp: $(@($Rows | Where-Object { $_.group.displayName -eq 'opim-s1-grp' }).Count -eq $Rows.Count)"
"Access types: $((@($Rows.accessId) | Sort-Object) -join ', ')"
```

**Expect:** `2`, `True` and `Access types: member, owner`.
**Failure looks like:** another count or `False` -- record and STOP. A terminating error is a failed
read, never a pass.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Eligible group assignments: 2
All are opim-s1-grp: True
Access types: member, owner
```

### 2.3. Exactly the two Azure eligibilities

- [x] **2.3** Window B. `Get-OPIMAzureRole` lists Reader on `opim-s1-rg` and on `opim-s1-rg2`, and nothing else.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Rows = @(Get-OPIMAzureRole -ErrorAction Stop)
"Eligible Azure roles: $($Rows.Count)"
"All are Reader: $(@($Rows | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' }).Count -eq $Rows.Count)"
"Scopes: $((@($Rows.ScopeDisplayName) | Sort-Object) -join ', ')"
```

**Expect:** `2`, `True` and `Scopes: opim-s1-rg, opim-s1-rg2`.
**Failure looks like:** another count, `False` or another scope -- record and STOP. A terminating
error is a failed read, never a pass.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Eligible Azure roles: 2
All are Reader: True
Scopes: opim-s1-rg, opim-s1-rg2
```

### 3. The activations, each twice (G8)

Each activation uses the old string form, the one the tab completion offers: the name and the
schedule id in parentheses. The justification is `opim-s1 live verification`.

### 3.1. A directory role, activated twice

- [x] **3.1** Window B. Usage Summary Reports Reader activates once; the second call gives a clear outcome and no second activation.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Role = @(Get-OPIMDirectoryRole -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq 'Usage Summary Reports Reader' })
if ($Role.Count -ne 1) { throw "Expected one eligible row, found $($Role.Count)." }
$Old = '{0} ({1})' -f $Role[0].roleDefinition.displayName, $Role[0].id
$First = Enable-OPIMDirectoryRole -RoleName $Old -Justification 'opim-s1 live verification' -Hours 1 -ErrorAction Stop
"First: status $($First.status)"
$Errors = @()
$Second = @(Enable-OPIMDirectoryRole -RoleName $Old -Justification 'opim-s1 live verification' -Hours 1 -ErrorVariable Errors -ErrorAction SilentlyContinue)
"Second (G8): output $($Second.Count); errors $($Errors.Count): $(@($Errors | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
"Active rows of the role: $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq 'Usage Summary Reports Reader' }).Count)"
```

**Expect:** `First: status Provisioned` (or `PendingProvisioning`); `Active rows of the role: 1`.
**Record:** the second call's outcome -- an error that says the role is already active is a pass; a
second request accepted or a crash is a fail (G8).
**Failure looks like:** a terminating error on the first call (record its error id), or more than one
active row -- STOP.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
First: status Provisioned
Second (G8): output 0; error RoleAssignmentExists ("The Role assignment already exists."), from Enable-OPIMDirectoryRole
Active rows of the role: 1
```

### 3.2. Group membership, activated twice

- [x] **3.2** Window B. `opim-s1-grp` as member activates once; the second call gives a clear outcome.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Group = @(Get-OPIMEntraIDGroup -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'member' })
if ($Group.Count -ne 1) { throw "Expected one eligible member row, found $($Group.Count)." }
$Old = '{0} - {1} ({2})' -f $Group[0].group.displayName, $Group[0].accessId, $Group[0].id
$First = Enable-OPIMEntraIDGroup -GroupName $Old -Justification 'opim-s1 live verification' -Hours 1 -ErrorAction Stop
"First: status $($First.status)"
$Errors = @()
$Second = @(Enable-OPIMEntraIDGroup -GroupName $Old -Justification 'opim-s1 live verification' -Hours 1 -ErrorVariable Errors -ErrorAction SilentlyContinue)
"Second (G8): output $($Second.Count); errors $($Errors.Count): $(@($Errors | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
"Active member rows: $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'member' }).Count)"
```

**Expect:** a first status that is not a failure; `Active member rows: 1`.
**Record:** the second call's outcome, as in 3.1.
**Failure looks like:** as in 3.1.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
First: status PendingProvisioning
Second (G8): output 0; error RoleAssignmentExists (Request_BadRequest: "One or more added object references already
exist for the following modified properties: 'members'."), from Enable-OPIMEntraIDGroup
Active member rows: 1
FINDING (see 3.6): the membership was gone at 20:47 UTC. The first request (20:40:12) is Provisioned for PT1H, the
repeat (20:40:19) Failed, and no instance is left; oer-live-cc read the group at 20:48: the test user is not a member.
A single activation without a repeat stayed active for 5.5 minutes (4.4, 4.5).
```

### 3.3. Reader on opim-s1-rg, activated twice

- [~] **3.3** Window B. Reader on `opim-s1-rg` activates once; the second call gives a clear outcome.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Role = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg' })
if ($Role.Count -ne 1) { throw "Expected one eligible row, found $($Role.Count)." }
$Old = '{0} -> {1} ({2})' -f $Role[0].RoleDefinitionDisplayName, $Role[0].ScopeDisplayName, $Role[0].Name
$First = Enable-OPIMAzureRole -RoleName $Old -Justification 'opim-s1 live verification' -Hours 1 -ErrorAction Stop
"First: status $($First.Status)"
$Errors = @()
$Second = @(Enable-OPIMAzureRole -RoleName $Old -Justification 'opim-s1 live verification' -Hours 1 -ErrorVariable Errors -ErrorAction SilentlyContinue)
"Second (G8): output $($Second.Count); errors $($Errors.Count): $(@($Errors | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
"Active Reader rows on opim-s1-rg: $(@(Get-OPIMAzureRole -Activated -Scope $Role[0].ScopeId -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' }).Count)"
```

**Expect:** a first status that is not a failure; `Active Reader rows on opim-s1-rg: 1`.
**Record:** the second call's outcome, as in 3.1.
**Failure looks like:** as in 3.1.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
First: status Provisioned
Second (G8): output 0; error RoleAssignmentExists ("The Role assignment already exists."), from Enable-OPIMAzureRole
Active Reader rows on opim-s1-rg: 0 -- about 20 s after the activation. The same read gave 1 at 20:47 UTC, and
Get-OPIMAzureRole -Activated without -Scope gave the row at 20:41 with a ScopeId equal to the eligible row's: ARM's
listing at the resource group scope lagged, not the filter. Marked partial: the count line did not show 1 when it ran.
```

### 3.4. The five-minute rule

- [x] **3.4** Window B. Five minutes pass after the last activation of 3.1 to 3.3, so the deactivations below are not refused for being too early.

```powershell
Start-Sleep -Seconds 310
"Waited: $([datetime]::UtcNow.ToString('HH:mm:ss')) UTC"
```

**Expect:** the time, at least five minutes after 3.3 finished.
**Failure looks like:** nothing can fail here; the wait is the check.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Waited: 20:47:02 UTC (3.3 finished at 20:40:58 UTC).
```

### 3.5. The directory role, deactivated twice

- [~] **3.5** Window B. Usage Summary Reports Reader deactivates once; the second call gives a clear outcome.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Active = @(Get-OPIMDirectoryRole -Activated -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq 'Usage Summary Reports Reader' })
if ($Active.Count -ne 1) { throw "Expected one active row, found $($Active.Count)." }
$Old = '{0} ({1})' -f $Active[0].roleDefinition.displayName, $Active[0].id
$First = Disable-OPIMDirectoryRole -RoleName $Old -ErrorAction Stop
"First: status $($First.status)"
$Errors = @()
$Second = @(Disable-OPIMDirectoryRole -RoleName $Old -ErrorVariable Errors -ErrorAction SilentlyContinue)
"Second (G8): output $($Second.Count); errors $($Errors.Count): $(@($Errors | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
"Active rows of the role: $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq 'Usage Summary Reports Reader' }).Count)"
```

**Expect:** `First: status Revoked` (or a non-failure status); `Active rows of the role: 0`.
**Record:** the second call's outcome -- an error that says the role is not active is a pass; a crash is a fail (G8).
**Failure looks like:** `ActiveDurationTooShort` -- 3.4 did not wait long enough; run 3.4 again. Any other error -- record it.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
First: status Revoked
Second (G8): a TERMINATING error, "Schedule ID ... from 'Usage Summary Reports Reader (...)' was not found as an eligible
role for this user", which ended the block before its summary lines. No second deactivation, but the outcome is a
terminating error with a misleading text (the role is eligible; it is no longer active) -- finding.
Read afterwards (20:47:53 UTC): active rows of the role: 0.
```

### 3.6. Group membership, deactivated twice

- [~] **3.6** Window B. `opim-s1-grp` as member deactivates once; the second call gives a clear outcome.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Active = @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'member' })
if ($Active.Count -ne 1) { throw "Expected one active member row, found $($Active.Count)." }
$Old = '{0} - {1} ({2})' -f $Active[0].group.displayName, $Active[0].accessId, $Active[0].id
$First = Disable-OPIMEntraIDGroup -GroupName $Old -ErrorAction Stop
"First: status $($First.status)"
$Errors = @()
$Second = @(Disable-OPIMEntraIDGroup -GroupName $Old -ErrorVariable Errors -ErrorAction SilentlyContinue)
"Second (G8): output $($Second.Count); errors $($Errors.Count): $(@($Errors | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
"Active member rows: $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'member' }).Count)"
```

**Expect:** a non-failure status; `Active member rows: 0`.
**Record:** the second call's outcome, as in 3.5.
**Failure looks like:** as in 3.5.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Cannot be verified, and therefore we do not know: "Expected one active member row, found 0." The member activation of
3.2 had disappeared before this check (see 3.2); nothing was deactivated here.
```

### 3.7. Reader on opim-s1-rg, deactivated twice (also the OPIM-24 baseline)

- [~] **3.7** Window B. Reader on `opim-s1-rg` is deactivated with the old string form; the outcome of both calls is recorded.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Eligible = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object { $_.ScopeDisplayName -eq 'opim-s1-rg' })[0]
$Active = @(Get-OPIMAzureRole -Activated -Scope $Eligible.ScopeId -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' })
if ($Active.Count -ne 1) { throw "Expected one active row, found $($Active.Count)." }
$Old = '{0} -> {1} ({2})' -f $Active[0].RoleDefinitionDisplayName, $Active[0].ScopeDisplayName, $Active[0].Name
foreach ($Try in 1, 2) {
    $Errors = @()
    $Out = @(Disable-OPIMAzureRole -RoleName $Old -ErrorVariable Errors -ErrorAction SilentlyContinue)
    "Call ${Try}: output $($Out.Count) status $(@($Out.Status) -join ','); errors $($Errors.Count): $(@($Errors | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
}
"Active Reader rows on opim-s1-rg: $(@(Get-OPIMAzureRole -Activated -Scope $Eligible.ScopeId -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' }).Count)"
```

**Record:** both calls and the count. The step fixes no bug: if the first call fails, that is the
OPIM-24 baseline (check 4.3), and the activation ends on its own after one hour.
**Failure looks like:** a crash, or a second deactivation accepted after a first that succeeded --
record it (G8).

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Call 1: output 1 status Revoked; errors 0 -- the old string form deactivates (OPIM-24 baseline, see 4.3).
Call 2: a TERMINATING error, "Schedule ID ... from 'Reader -> opim-s1-rg (...)' was not found as an eligible role for
this user", which ended the block before the count line (as in 3.5).
Read afterwards (20:49:41 UTC): active Azure roles: 0; active directory roles: 0.
```

### 4. Baselines for later steps, without a fix

### 4.1. OPIM-18 -- a start time given as text

- [x] **4.1** Window B. `-NotBefore` given as text without an offset: the start Graph records, compared with what the text meant in local time.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Group = @(Get-OPIMEntraIDGroup -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'owner' })
if ($Group.Count -ne 1) { throw "Expected one eligible owner row, found $($Group.Count)." }
$Local = [datetime]::Now.AddMinutes(3)
$Text = $Local.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)
$Request = Enable-OPIMEntraIDGroup -Group $Group[0] -Justification 'opim-s1 live verification' -Hours 1 -NotBefore $Text -ErrorAction Stop
$Raw = $Request.scheduleInfo.startDateTime
$Recorded = if ($Raw -is [datetime]) { [datetimeoffset]$Raw.ToUniversalTime() } else { [datetimeoffset]::Parse([string]$Raw, [cultureinfo]::InvariantCulture) }
$Meant = [datetimeoffset]::new([datetime]::ParseExact($Text, 'yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture))
"Local UTC offset of this machine: $([System.TimeZoneInfo]::Local.GetUtcOffset([datetime]::Now))"
"Meant start (UTC): $($Meant.UtcDateTime.ToString('yyyy-MM-dd HH:mm'))"
"Recorded start (UTC): $($Recorded.UtcDateTime.ToString('yyyy-MM-dd HH:mm'))"
"Status: $($Request.status); request id kept for 4.2: $([bool]$Request.id)"
$global:OpimS12NotBeforeRequestId = $Request.id
```

**Record:** the three times. If the recorded start differs from the meant one by the local offset,
Graph read the text as UTC (OPIM-18). With a local offset of zero the check cannot tell them apart:
mark it `[~]` and say so.
**Failure looks like:** a terminating error -- record it; nothing was activated.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Recorded (OPIM-18 baseline): Enable-OPIMEntraIDGroup -NotBefore '<local time + 3 min, as text>' ended with
InvalidRoleAssignmentRequest ("The role assignment request is invalid.", HTTP 400) from Graph; nothing was activated.
The module sends $NotBefore.ToString('o'); a time given as text has DateTime Kind Unspecified, so the start went out
without an offset (for example 2026-10-06T22:52:00.0000000). Local UTC offset of this machine: +02:00. Meant start and
recorded start cannot be compared, since no request was created; the step fixes nothing.
```

### 4.2. OPIM-18, cleanup -- the scheduled owner activation does not stay

- [~] **4.2** Window B. The owner activation of 4.1 is cancelled while it is scheduled, or deactivated after five minutes once it has started.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Id = $global:OpimS12NotBeforeRequestId
$Status = $null
$Now = Invoke-MgGraphRequest -Method GET -Uri "v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests/$Id" -OutputType HashTable -SkipHttpErrorCheck -StatusCodeVariable 'Status'
"Request status now: $($Now['status']) (HTTP $Status)"
if ($Now['status'] -in 'Granted', 'Scheduled', 'ScheduleCreated', 'PendingScheduleCreation') {
    $Cancel = $null
    $null = Invoke-MgGraphRequest -Method POST -Uri "v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests/$Id/cancel" -OutputType HashTable -SkipHttpErrorCheck -StatusCodeVariable 'Cancel'
    "Cancel: HTTP $Cancel"
} else {
    Start-Sleep -Seconds 310
    Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'owner' } | Disable-OPIMEntraIDGroup -ErrorAction Stop | Out-Null
}
"Active owner rows: $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'owner' }).Count)"
```

**Expect:** `Active owner rows: 0`, after a cancel (HTTP 204) or a deactivation.
**Failure looks like:** a row left -- record it; it ends on its own one hour after its start.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Nothing to clean: 4.1 created no request (request id from 4.1 present: False). Active owner rows: 0 (20:50:12 UTC).
```

### 4.3. OPIM-23 and OPIM-24 -- Azure by its old string form

- [x] **4.3** Window B. `Get-OPIMAzureRole -RoleName` with the old string form, and the outcome of 3.7's deactivation, are recorded as they are.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Role = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object { $_.ScopeDisplayName -eq 'opim-s1-rg' })[0]
$Old = '{0} -> {1} ({2})' -f $Role.RoleDefinitionDisplayName, $Role.ScopeDisplayName, $Role.Name
$Errors = @()
$Found = @(Get-OPIMAzureRole -RoleName $Old -ErrorVariable Errors -ErrorAction SilentlyContinue)
"Get-OPIMAzureRole -RoleName (old form): rows $($Found.Count); errors $($Errors.Count): $(@($Errors | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
"Rows that are the opim-s1-rg eligibility: $(@($Found | Where-Object { $_.Name -eq $Role.Name }).Count)"
```

**Record:** the two lines, as the OPIM-23 baseline, and copy 3.7's first call here as the OPIM-24
baseline.
**Failure looks like:** nothing is a failure here; the step fixes neither.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Get-OPIMAzureRole -RoleName (old form): rows 0; errors 4: InsufficientPermissions (Get-AzRoleEligibilitySchedule and
Get-AzRoleAssignmentScheduleInstance by name at scope '/', ARM: "use $filter=asTarget()"), each rewrapped by
Get-OPIMAzureRole
Rows that are the opim-s1-rg eligibility: 0
OPIM-23 baseline: the old form finds nothing and fails with InsufficientPermissions.
OPIM-24 baseline (3.7): Disable-OPIMAzureRole with the old form deactivated on the first call (Revoked); the second
call ended with a terminating "not found as an eligible role".
```

### 4.4. OPIM-14 -- a group activation with -Wait

- [x] **4.4** Window B. `Enable-OPIMEntraIDGroup -Wait` for the member eligibility: how long it waits and what it returns.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Group = @(Get-OPIMEntraIDGroup -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'member' })
if ($Group.Count -ne 1) { throw "Expected one eligible member row, found $($Group.Count)." }
$Watch = [System.Diagnostics.Stopwatch]::StartNew()
$Request = Enable-OPIMEntraIDGroup -Group $Group[0] -Justification 'opim-s1 live verification' -Hours 1 -Wait -ErrorAction Stop
"Returned after $([int]$Watch.Elapsed.TotalSeconds) s; status in the output: $($Request.status)"
"Active member rows: $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'member' }).Count)"
```

**Record:** the seconds, the status in the output and the count. If the block has not returned after
five minutes, stop it with Ctrl+C and record a hang.
**Failure looks like:** nothing is a failure here; the step fixes nothing. Deactivate the member row
in 4.5.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Returned after 13 s; status in the output: PendingProvisioning
Active member rows: 1
OPIM-14 baseline: -Wait returns with the request's early status, not a final one.
```

### 4.5. OPIM-14, cleanup

- [x] **4.5** Window B. Five minutes after 4.4 the member activation is deactivated.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
Start-Sleep -Seconds 310
Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'member' } | Disable-OPIMEntraIDGroup -ErrorAction Stop | Out-Null
"Active member rows: $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'member' }).Count)"
```

**Expect:** `Active member rows: 0`.
**Failure looks like:** a row left -- record it; it ends on its own after one hour.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Before the deactivation, 20:56:08 UTC (5.5 minutes after 4.4, no repeat): active member rows 1 (a read added to the
block, for the finding in 3.2).
Right after Disable-OPIMEntraIDGroup: Active member rows: 1; read again at 20:56:30 UTC: 0. The deactivation took
effect a few seconds later.
```

### 5. The stop measurements (P-3)

### 5.1. Device code is not blocked by Conditional Access

- [~] **5.1** Window B. Every device code sign-in of 0.1, 1.2 and 1.4 completed.

```powershell
Get-ChildItem -Path 'docs/live-verification/raw/opim-s12' -Filter '*blocked*' -ErrorAction SilentlyContinue | Measure-Object | ForEach-Object { "Screenshots of a blocked sign-in: $($_.Count)" }
```

**Expect:** `0`, and the result lines of 0.1, 1.2 and 1.4 show only `ok` rows.
**Failure looks like:** a `blocked` status in any of them -- STOP: Philip decides (an exclusion for the
test user, or the manual device code of P-1).

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Screenshots of a blocked sign-in: 1 -- the first 0.1 attempt, 18:46 UTC: "You don't have access to this ... an
authentication flow that is restricted by your admin", right after the password. Stop condition: device code blocked by
Conditional Access. The operator decided and excluded the test user; every device code sign-in after that completed
(0.1, 1.2, 1.4, 1.5).
```

### 5.2. Security info registration needs no trusted location, pass or device

- [~] **5.2** Window B. The registration of S.6 completed.

```powershell
"Key in the vault: $(Import-Module (Join-Path $env:OPIMLIVE_HOME 'OpimLive/OpimLive.psm1') -Force; [bool](Get-OpimLiveSecret -Name 'opim-s1-live-user-totp'))"
```

**Expect:** `Key in the vault: True`, and S.6's result is `ok`.
**Failure looks like:** S.6 ended `registration-blocked` -- STOP: Philip decides (an exclusion or a
Temporary Access Pass).

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Registration needed no trusted location, Temporary Access Pass or compliant device: the interrupt asked only for Next,
and the operator registered the method in an ordinary InPrivate window. The harness could not, since Edge crashes under
Playwright (S.6). Key in the vault: True.
```

### 5.3. No test role's policy requires approval or an authentication context

- [x] **5.3** Window A. The prerequisite script's policy lines.

```powershell
Select-String -Path 'docs/live-verification/raw/opim-s12/prereq.txt' -Pattern 'PIM policy of' | ForEach-Object { $_.Line }
```

**Expect:** six lines -- two directory roles, `opim-s1-grp` member and owner, Reader on two resource
groups -- each with `rules read: True; approval required: False; authentication context: False`.
**Record:** what each line says is required on activation (MFA is expected).
**Failure looks like:** `True` on approval or authentication context -- STOP: Philip decides (other
roles, or a policy change restored in the teardown).

Result: 2026-10-06 15:04 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
PIM policy of directory role 'Usage Summary Reports Reader': rules read: True; approval required: False; authentication context: False; on activation: Justification; longest activation: PT8H
PIM policy of directory role 'Message Center Privacy Reader': rules read: True; approval required: False; authentication context: False; on activation: Justification; longest activation: PT1H
PIM policy of opim-s1-grp (member): rules read: True; approval required: False; authentication context: False; on activation: Justification; longest activation: PT8H
PIM policy of opim-s1-grp (owner): rules read: True; approval required: False; authentication context: False; on activation: Justification; longest activation: PT8H
PIM policy of Reader on opim-s1-rg: rules read: True; approval required: False; authentication context: False; on activation: Justification; longest activation: PT8H
PIM policy of Reader on opim-s1-rg2: rules read: True; approval required: False; authentication context: False; on activation: Justification; longest activation: PT8H
Required on activation: a justification only. No policy requires MFA on activation.
```

### 5.4. Graph and ARM refuse oer-live-cc no write

- [x] **5.4** Window A. The prerequisite script ran without a 401 or a 403 on `oer-live-cc`'s path.

```powershell
"STOP lines in the prerequisite run: $(@(Select-String -Path 'docs/live-verification/raw/opim-s12/prereq.txt' -Pattern 'STOP').Count)"
```

**Expect:** `0`.
**Failure looks like:** a STOP line naming 401 or 403 -- STOP: a missing permission is Philip's
decision (G6), never worked around.

Result: 2026-10-06 15:04 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
STOP lines in the prerequisite run: 0
```

## Teardown

This step creates no object of its own (prefix `opim-s12-`). The fixture (prefix `opim-s1-`) stays
until the sprint's last step (decision A9); its teardown is only planned here, with `-WhatIf`. Delete
`docs/live-verification/raw/opim-s12` once the results are written up; the fixture's baseline in the
prerequisite script's own raw folder stays for the fixture's teardown.

### T.1. No object of this step is left

- [x] **T.1** Window A, as `oer-live-cc`. No directory object carries the prefix `opim-s12-`.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$null = Import-OerLiveConfig -Prefix 'opim-s12-'
Connect-OerLive -Graph
"Objects with the prefix opim-s12-: $(@(Find-OerLivePrefixed -Prefix 'opim-s12-' -ThrowOnUnread -Quiet).Count)"
Disconnect-OerLive
```

**Expect:** `Objects with the prefix opim-s12-: 0`.
**Failure looks like:** another number -- record each object by name; it was not created by this
file. A throw on an unread collection is a failed read, never a `0`.

Result: 2026-10-06 15:04 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Every identity check line of oer-live-cc: True.
Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'opim-s12-' is left.
Objects with the prefix opim-s12-: 0
```

### T.2. The fixture's teardown plan

- [x] **T.2** Window A, as `oer-live-cc`. `Initialize-OpimS1Prereq.ps1 -Teardown -WhatIf` plans the removal of exactly the fixture, Azure eligibilities before their resource groups, and removes nothing.

```powershell
$Out = @(& pwsh -NoProfile -File (Join-Path $env:OPIMLIVE_HOME 'Initialize-OpimS1Prereq.ps1') -Teardown -WhatIf 2>&1 | ForEach-Object { "$_" })
$Out | Set-Content -Path 'docs/live-verification/raw/opim-s12/teardown-whatif.txt'
$Targets = @($Out | Select-String -Pattern 'on target "(.+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value })
$InTenant = @($Targets | Where-Object { $_ -notlike 'raw\*' })
"Planned removals: $($InTenant.Count); without the prefix opim-s1-: $(@($InTenant | Where-Object { $_ -notlike 'opim-s1-*' }).Count)"
$InTenant
```

**Expect:** the plan names the two Azure eligibilities before the two resource groups, then the two
directory role eligibilities, the two group eligibilities, the group, the user and the two secrets;
`0` without the prefix; the teardown line ends `(WhatIf: nothing was removed)`.
**Failure looks like:** a target without the prefix -- STOP. A planned removal that is not part of
the fixture -- record it.

Result: 2026-10-06 15:04 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Planned removals: 12; without the prefix opim-s1-: 0
opim-s1-rg: Azure eligibility of opim-s1-live-user
opim-s1-rg2: Azure eligibility of opim-s1-live-user
opim-s1-rg
opim-s1-rg2
opim-s1-live-user: eligible 'Message Center Privacy Reader' assignment at directory scope '/'
opim-s1-live-user: eligible 'Usage Summary Reports Reader' assignment at directory scope '/'
opim-s1-grp: PIM for Groups member eligibility of a principal
opim-s1-grp: PIM for Groups owner eligibility of a principal
opim-s1-grp
opim-s1-live-user
opim-s1-live-user-password in the SecretStore vault OpimLive
opim-s1-live-user-totp in the SecretStore vault OpimLive
Teardown of 'opim-s1-': removed 0, residue 0, unreadable 0 (WhatIf: nothing was removed).
```

### T.3. The test user holds no active assignment

- [x] **T.3** Window B. After sections 3 and 4, the test user has no active directory role, group or Azure assignment.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
"Active directory roles: $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count)"
"Active group assignments: $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count)"
"Active Azure roles: $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
Disconnect-OPIM
```

**Expect:** `0` on all three, then the window signs out.
**Record:** an Azure row left by 3.7 (OPIM-24) and when it ends. Nothing else is left in the tenant
on purpose but the fixture.
**Failure looks like:** another row -- record it. A terminating error is a failed read, never a pass.

Result: 2026-10-06 21:00 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Active directory roles: 0
Active group assignments: 0
Active Azure roles: 0
Window B signed out (Disconnect-OPIM). No Azure row was left by 3.7.
```
