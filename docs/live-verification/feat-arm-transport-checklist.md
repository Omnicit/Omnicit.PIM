# Live verification checklist -- Azure roles go through AzAuth's sign-in and the module's own Azure Resource Manager transport, with the same rows, fields and errors as 0.6.0 (feat/arm-transport)

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
eligibilities of) and `opim-s21a-` (this step's own objects, of which there are none). Check 0.1
proves the identity before any other check calls the module. If a browser window or a sign-in prompt
appears mid-run, STOP and run check 0.1 again: in this file every sign-in is a device code, and the
proof of 0.1 holds only for the sign-in it checked.

**Three windows, never one process** (decision A10, and step 1a's comparison). Window A runs as
`oer-live-cc`. Window B runs the branch's build as the test user. Window C runs Omnicit.PIM 0.6.0
from the PowerShell Gallery, saved into the step's raw folder and never into the user's profile, as
the test user, for the comparisons with today's behaviour. The Microsoft Graph SDK holds one session
per process, so no two share one. Every block below names its window.

**No block prints a scope id, an object id, a tenant id or a message that holds one.** The blocks
print counts, statuses, error ids, display names of the fixture's roles and resource groups,
property names, seconds and True/False. Comparisons are written to files in the step's raw folder
and only their verdicts are printed.

## What changed and why this needs a live tenant

- **A. Azure is signed in with AzAuth** ("feat: sign in to Azure Resource Manager with AzAuth and
  check the account", "fix: drop a refused Azure token and wait as long as a device code lives").
  `Connect-OPIM -IncludeARM` acquires an Azure Resource Manager token with
  AzAuth's `Get-AzToken`, with a device code in device code mode, and refuses a token whose tenant or
  account is not the Graph session's (`TenantMismatch`, `AccountMismatch`). A mock cannot show that
  AzAuth's real device code reaches the Information stream while it waits, nor that the token Entra
  issues carries the claims the module compares.
- **B. Every Azure call goes through the module's own transport** ("feat: add the module's own Azure
  Resource Manager transport", "fix: keep every Azure Resource Manager request on its host and refuse
  an unreadable page", "fix: refuse an Azure answer that cannot be read or that repeats a page"). A mock cannot show that ARM accepts the module's requests: the
  `asTarget()` reads at `/` and at a resource group, the activation and deactivation requests, the
  `-Wait` poll, and the token sent with `-Authentication Bearer`.
- **C. The output keeps its shape** ("feat: read Azure roles through the module's own transport",
  decision A4). Sections 1 and 4 compare every row and every property with what 0.6.0 returns for
  the same fixture, one property at a time.
- **D. Activation, deactivation and the policy refusal keep their fields, statuses and error ids**
  ("feat: activate and deactivate Azure roles through the module's own transport", "fix: read the
  policy and cooldown errors from the Azure Resource Manager error body", "fix: send nothing for a
  role without an Azure scope and read a scope typed without a slash"). Section 2 compares the
  policy refusal with 0.6.0; section 3 activates and deactivates Reader on the fixture's two resource
  groups with `-Hours`, `-Until`, `-NotBefore` and `-Wait`, and through `pim` and `unpim`.
- **E. No Az command is called any more, and `Disconnect-OPIM` clears the module's Azure token**
  ("fix: stop disconnecting the Az context in Disconnect-OPIM"). Section 5 shows the silent reuse
  inside a session and a new sign-in after `Disconnect-OPIM`.

The mapping to the step's specification: sections 1 and 4 are its 1.x (the reads, with G8, and their
comparison with 0.6.0), section 2 its 3.x (the policy refusal), section 3 its 2.x (activation, `-Wait`,
deactivation, `pim` and `unpim`, with G8), section 5 its 4.x. Section 2 runs before section 3 because
the refusal needs a role that is not active, and section 4 after 3.2 because `-Activated` and `-All`
need an active role.

The fixture of Sprint 2 (decision A15) is used as it stands and is not changed: the test user
`opim-s2-live-user`, the group `opim-s2-grp` (eligible as member), the resource groups `opim-s2-rg`
and `opim-s2-rg2` (Reader eligible on each), and the directory roles Usage Summary Reports Reader and
Message Center Privacy Reader. Every activation below is deactivated again before the end.

## What this file does not check, and why

Class B, each proven by the unit tests named:

- **A token for another tenant or another account** (`TenantMismatch`, `AccountMismatch`, A3) -- the
  test tenant has one test user. `tests/Unit/Private/Initialize-OPIMAuth.Tests.ps1` and
  `tests/Unit/Private/Get-OPIMArmRefusal.Tests.ps1`; the stop condition of this run reads the same
  evidence in 0.1.
- **Throttling (429, 503 with `Retry-After`), the budgets, the deadline and the cap; the one 401
  refresh; a next link to another host; a failed page** -- none can be provoked on purpose.
  `tests/Unit/Private/Invoke-OPIMArmRequest.Tests.ps1`.
- **An ARM error body without an error code** (`ArmTransportError`) and a failure before any
  response -- `tests/Unit/Private/Convert-OPIMArmHttpException.Tests.ps1` and the transport's tests.
- **A role at the root scope `/`** -- the fixture has none; the paths are pinned in
  `tests/Unit/Public/Enable-OPIMAzureRole.Tests.ps1` and `Get-OPIMAzureRole.Tests.ps1`.
- **The interactive (browser) Azure sign-in** -- every sign-in here is a device code;
  `tests/Unit/Private/Initialize-OPIMAuth.Tests.ps1` pins `-Interactive` outside device code mode.

## Setup, once

The operator sets `OPIMLIVE_HOME` in windows B and C to the notes folder that holds the `OpimLive`
folder, and `OPIMLIVE_PREFIX` to `opim-s2-`; no checklist holds the path. The test user's sign-in
name and the test tenant's id are read by the harness through OerLive and are never printed. Windows
B and C run from the root of the step's worktree; their console output goes to the files named in
`OPIMLIVE_HOSTLOG` (window C needs it: 0.6.0's Azure device code is written by `Connect-AzAccount` to
the host). Raw output, the comparison files, the run's tenant map and the 0.6.0 module go to
`docs/live-verification/raw/opim-s21a` (git-ignored), which is deleted once the results are written
up. This step creates no object of its own, so it has no prerequisite script of its own; the
sprint's `Initialize-OpimS2Prereq.ps1` is run with `-WhatIf` only.

A block that runs the module in window B starts with the three-line prologue of the template. A block
that runs in both windows B and C starts with a three-line prologue of its own: it accepts the
branch's build in window B and 0.6.0 in window C, and stops on anything else. Window C never imports
the branch's build.

The PIM policies of the fixture's roles require a justification on activation (measured in the
fixture session), so every activation below passes one, except the refusal in section 2.

### S.1. Find the build under test and tie it to the branch head

- [x] **S.1** Window B. The newest build in `output/module/Omnicit.PIM/` was made after the branch head was committed, it holds the ARM transport, and AzAuth 2.9.0 is the AzAuth this window loads.

```powershell
$env:PSModulePath = (Resolve-Path 'output/RequiredModules').Path + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module (Resolve-Path 'output/RequiredModules/AzAuth/2.9.0/AzAuth.psd1').Path
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$HeadTime = [datetimeoffset]::Parse((git log -1 --format=%cI))
$Psm1 = Join-Path $Built.DirectoryName 'Omnicit.PIM.psm1'
"Branch head: $(git log -1 --format='%h %s')"
"Built version folder: $($Built.Directory.Name)"
"Built after the branch head was committed: $([datetimeoffset]$Built.LastWriteTime -gt $HeadTime)"
$Tracked = @(git status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0) { throw "git status exited with $LASTEXITCODE, so the working tree could not be read; repair the clone before any check below." }
"Tracked changes in the working tree: $($Tracked.Count)"
"The built module holds the ARM transport: $([bool](Select-String -LiteralPath $Psm1 -Pattern 'function Invoke-OPIMArmRequest' -SimpleMatch -Quiet))"
"AzAuth loaded: $((Get-Module AzAuth).Version)"
```

**Expect:** the branch head's hash and subject; the version folder; every True/False line `True`;
`Tracked changes in the working tree: 0`; `AzAuth loaded: 2.9.0`.
**Failure looks like:** `False`, a tracked change, or another AzAuth version -- build again, or start
a fresh window B, before any check below.

Result: 2026-10-09 18:27 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:22 UTC, window B: Branch head: 91ddadd (the checklist commit); Built version folder: 0.7.0; Built after the branch head was committed: False -- the build predated the checklist commits, which change no source; built again, 18:23 UTC: True. Tracked changes in the working tree: 0; The built module holds the ARM transport: True; AzAuth loaded: 2.9.0. Later commits on the branch change only this checklist.
```

### S.2. The harness loads

- [x] **S.2** Windows B and C. OerLive is 1.0.3, OpimLive is 1.0.4, the harness reads the test values through it, and the TOTP implementation reproduces RFC 6238.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME 'OpimLive/OpimLive.psm1') -Force
$Target = Get-OpimLiveTarget
"OerLive version: $((Get-OerLiveState).Version)"
"OpimLive version: $(& (Get-Module OpimLive) { $script:OpimLiveVersion })"
"Test user and tenant read (values hidden): $([bool]$Target.UserPrincipalName -and [bool]$Target.TenantId)"
"TOTP self-test: $(Get-OpimLiveTotp -SelfTest)"
"Host log set and present: $([bool]$env:OPIMLIVE_HOSTLOG -and (Test-Path -LiteralPath $env:OPIMLIVE_HOSTLOG))"
```

**Expect:** `OerLive version: 1.0.3`; `OpimLive version: 1.0.4`; the three other lines `True`, in
both windows.
**Failure looks like:** `False` on the self-test -- STOP: the harness would enter wrong codes.

Result: 2026-10-09 18:27 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:23 UTC, windows B and C: OerLive version: 1.0.3; OpimLive version: 1.0.4; Test user and tenant read (values hidden): True; TOTP self-test: True; Host log set and present: True (both windows).
```

### S.3. The fixture is in place, and nothing carries the step's prefix

- [x] **S.3** Window A, as `oer-live-cc`. The prerequisite script with `-WhatIf` finds every object of the fixture and would write nothing, and no object carries the prefix `opim-s21a-`.

```powershell
$Prereq = Join-Path $env:OPIMLIVE_HOME 'Initialize-OpimS2Prereq.ps1'
# A child process, so its host output -- the What if lines included -- arrives here as text.
$Lines = @(pwsh -NoProfile -NonInteractive -File $Prereq -WhatIf 2>&1 | ForEach-Object { ([string]$_) -replace '\x1b\[[0-9;]*m', '' })
"Lines 'exists; kept': $(@($Lines | Where-Object { $_ -match 'exists; kept' }).Count)"
"What if lines other than the transcript: $(@($Lines | Where-Object { $_ -match '^What if:' -and $_ -notmatch 'transcript' }).Count)"
$Lines | Where-Object { $_ -match "Sweep 'opim-s|Residue:|Group 'Exclude from CA'|PIM policy of|exists; kept" }
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$null = Import-OerLiveConfig -Prefix 'opim-s21a-'
Connect-OerLive -Graph
"Objects with the prefix opim-s21a-: $(@(Find-OerLivePrefixed -Prefix 'opim-s21a-' -ThrowOnUnread -Quiet).Count)"
Disconnect-OerLive
```

**Expect:** `Lines 'exists; kept': 10` (the user, the membership in `Exclude from CA`, the group,
the two directory role eligibilities, the group member eligibility, the two resource groups and the
two Azure eligibilities); `What if lines other than the transcript: 0`; the sweeps `opim-s1-` 0 and
`opim-s2-` 1 user, 1 group, 0 other; every PIM policy line without approval or authentication
context; `Objects with the prefix opim-s21a-: 0`.
**Failure looks like:** any `What if:` line that would create an object, a count other than 10, or a
prefixed object that is not the fixture's -- STOP (the fixture is missing something, or something
without the prefix exists): create nothing and ask for nothing. A 401 or 403 -- STOP (G6).

Result: 2026-10-09 18:27 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:21 UTC, window A as oer-live-cc: Lines 'exists; kept': 10; What if lines other than the transcript: 0. Sweep 'opim-s1-': 0; sweep 'opim-s2-': test user 1, test group 1, other prefixed objects 0. Group 'Exclude from CA': found 1, not role-assignable, not dynamic. Every PIM policy (both directory roles, the group member, Reader on opim-s2-rg and opim-s2-rg2): approval required False, authentication context False, on activation Justification. Residue: 2 rows, both from opim-s1 (R-L10 of Sprint 1), not touched. Every oer-live-cc identity line True. Objects with the prefix opim-s21a-: 0.
```

### S.4. The step's raw folder, and 0.6.0 for the comparison

- [x] **S.4** Window C. The raw folder is git-ignored; Omnicit.PIM 0.6.0 is saved there from the PowerShell Gallery and loaded from there, with the Az and Graph modules already installed, and the Az context stays in this process.

```powershell
$Raw = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s21a'
$null = New-Item -ItemType Directory -Force -Path $Raw
git check-ignore -q $Raw
"The raw folder is git-ignored: $($LASTEXITCODE -eq 0)"
$Saved = Join-Path $Raw 'module-0.6.0'
if (-not (Test-Path -LiteralPath (Join-Path $Saved 'Omnicit.PIM/0.6.0/Omnicit.PIM.psd1'))) {
    $null = New-Item -ItemType Directory -Force -Path $Saved
    Save-PSResource -Name Omnicit.PIM -Version '[0.6.0]' -Repository PSGallery -Path $Saved -SkipDependencyCheck -TrustRepository -ErrorAction Stop
}
Import-Module Az.Resources -RequiredVersion 9.0.3 -ErrorAction Stop
Import-Module (Join-Path $Saved 'Omnicit.PIM/0.6.0/Omnicit.PIM.psd1') -ErrorAction Stop
$null = Disable-AzContextAutosave -Scope Process
"Omnicit.PIM in this window: $((Get-Module Omnicit.PIM).Version), loaded from the raw folder: $((Get-Module Omnicit.PIM).ModuleBase.StartsWith($Saved, [System.StringComparison]::OrdinalIgnoreCase))"
"Omnicit.PIM 0.6.0 under the profile's module folders: $([bool](Get-Module -ListAvailable Omnicit.PIM | Where-Object { $_.Version -eq '0.6.0' -and -not $_.ModuleBase.StartsWith($Saved, [System.StringComparison]::OrdinalIgnoreCase) }))"
"Az.Resources $((Get-Module Az.Resources).Version); Az.Accounts $((Get-Module Az.Accounts).Version); Microsoft.Graph.Authentication $((Get-Module Microsoft.Graph.Authentication).Version)"
```

**Expect:** `True`; `Omnicit.PIM in this window: 0.6.0, loaded from the raw folder: True`;
`... under the profile's module folders: False`; the three dependency versions.
**Failure looks like:** `False` on the first line -- STOP: the module would be tracked. 0.6.0 found in
the profile -- record it; it was not put there by this run.

Result: 2026-10-09 18:27 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:23 UTC, window C: first run stopped at Save-PSResource (it refuses a -Path that does not exist; the block now creates the folder first, commit 5d8cf6f). 18:24 UTC: The raw folder is git-ignored: True; Omnicit.PIM in this window: 0.6.0, loaded from the raw folder: True; Omnicit.PIM 0.6.0 under the profile's module folders: False; Az.Resources 9.0.3; Az.Accounts 5.5.3; Microsoft.Graph.Authentication 2.40.0.
```

### S.5. The recorder of ARM's answers

- [x] **S.5** Window B. Every ARM answer this window receives is recorded, body only, in the step's raw folder, to be redacted into the unit tests' fixtures.

```powershell
$global:OpimS21aRecord = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s21a/arm-record.jsonl'
function global:Invoke-WebRequest {
    # Records the method, the path without its query, the status and the body of each response. The
    # request, its headers and the response headers are not recorded. The parameters are the ones the
    # module's transport passes, handed on by name.
    [CmdletBinding()]
    param([string]$Method = 'GET', [uri]$Uri, [string]$Authentication, [securestring]$Token, [switch]$SkipHttpErrorCheck, [object]$Body, [string]$ContentType)
    $Response = Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters
    $Line = [ordered]@{ utc = [datetime]::UtcNow.ToString('o'); method = $Method; path = $Uri.AbsolutePath; status = [int]$Response.StatusCode; content = [string]$Response.Content } | ConvertTo-Json -Compress -Depth 3
    [System.IO.File]::AppendAllText($global:OpimS21aRecord, $Line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    $Response
}
"Recorder in place: $((Get-Command Invoke-WebRequest).CommandType -eq 'Function')"
```

**Expect:** `Recorder in place: True`.
**Failure looks like:** `False` -- the fixtures cannot be recorded; record it and go on (the unit
tests keep their documented shapes).

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:24 UTC, window B: Recorder in place: True. Its first form relayed the transport's parameters with @args, which drops a switch given a value (-SkipHttpErrorCheck:$true) when the target is a cmdlet: 0.3's first run at 18:27 UTC ended in the module's own ArmTransportError ('failed before a response was received'), nothing sent. The block now declares the transport's parameters and relays @PSBoundParameters (tested offline first); run again at 18:28 UTC: Recorder in place: True.
```

### 0. Preparation

### 0.1. Identity check, Graph and Azure, branch build

- [x] **0.1** Window B. `Connect-OpimLiveUser -IncludeARM` signs the branch build in to Graph and Azure with one device code each, both on the Information stream; the Graph account is the test user, the tenant is the test tenant, and the module's ARM token is the test user's in the test tenant.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
Import-Module (Join-Path $env:OPIMLIVE_HOME 'OpimLive/OpimLive.psm1') -Force
$Target = Get-OpimLiveTarget
$Sign = Connect-OpimLiveUser -IncludeARM -RawFolder 'docs/live-verification/raw/opim-s21a'
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
$State = & (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }
"Session tenant is the test tenant: $([string]::Equals([string]$State.TokenTenantId, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
"ARM token held as a SecureString: $($State.ArmToken -is [securestring])"
"ARM token minutes left: $([int]($State.ArmTokenExpiry - [datetime]::UtcNow).TotalMinutes)"
"An Az context for the test user in this window: $([string]::Equals([string](Get-AzContext -ErrorAction SilentlyContinue).Account.Id, $Target.UserPrincipalName, [System.StringComparison]::OrdinalIgnoreCase))"
```

**Expect:** the rows `Graph Information True ok` and `AzureCli Information True ok`; every True/False
line of the harness `True` (Graph account, tenant, device code mode, Azure token user and tenant);
`Session tenant is the test tenant: True`; `ARM token held as a SecureString: True`; minutes left
above 5; `An Az context for the test user in this window: False` (the module signed nothing in with
Az). No line prints the account or the tenant id.
**Failure looks like:** `False` on any line, a `STOP`, or an Azure row that is not `AzureCli
Information True ok` -- STOP: run `Disconnect-OPIM`, end window B and run no other check. An ARM token
whose tenant or user is not the test user's is a STOP even though the module refused it (the
harness signed in wrong).

Result: 2026-10-09 18:27 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:24-18:25 UTC, window B (37 s): Disconnect-OPIM, Disconnect-MgGraph and Disconnect-AzAccount ran first; the Graph code and then the AzAuth code were completed in Edge, the Azure confirmation page naming Microsoft Azure CLI. Harness lines: Device code for Graph: stream Information, tag OPIMDeviceCode True, sign-in ok; Device code for AzureCli: stream Information, tag OPIMDeviceCode True, sign-in ok; Signed in to Graph as the test user: True; to the test tenant: True; the module remembers the device code mode: True; Azure token is the test user (the Graph sign-in's object id): True; Azure token is the test tenant: True. The block's Format-Table line then ended in the run's own window wrapper (it formatted each table record on its own; fixed in the wrapper, not in the module), so the remaining four lines ran at 18:25 UTC as the rest of the block, verbatim: Session tenant is the test tenant: True; ARM token held as a SecureString: True; ARM token minutes left: 66; An Az context for the test user in this window: False. No line printed the account or the tenant id.
```

### 0.2. Identity check, 0.6.0

- [x] **0.2** Window C. `Connect-OpimLiveUser -IncludeARM` signs 0.6.0 in to Graph and Azure (Az.Accounts) as the test user in the test tenant.

```powershell
if ((Get-Module Omnicit.PIM).Version -ne [version]'0.6.0') { throw 'Window C must hold 0.6.0 (S.4).' }
Import-Module (Join-Path $env:OPIMLIVE_HOME 'OpimLive/OpimLive.psm1') -Force
$Target = Get-OpimLiveTarget
$Sign = Connect-OpimLiveUser -IncludeARM -RawFolder 'docs/live-verification/raw/opim-s21a'
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
```

**Expect:** the rows `Graph Information True ok` and `Azure Host False ok`; every True/False line
`True` (Az context user and tenant).
**Failure looks like:** as 0.1 -- STOP, end window C.

Result: 2026-10-09 18:27 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:26 UTC, window C (34 s): rows Graph Information True ok and Azure Host False ok; Az.Accounts wrote its code as '[Login to Azure] ...' to the host and the helper completed it; every harness line True (Graph account and tenant, device code mode, Azure context user and tenant). Az.Accounts warned twice about EnableLoginByWam (0.6.0's Update-AzConfig).
```

### 0.3. What is eligible and what is active

- [x] **0.3** Window B. The fixture's eligibilities are listed, and nothing is active.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
"Eligible: directory $(@(Get-OPIMDirectoryRole -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -ErrorAction Stop).Count)"
"Active: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
@(Get-OPIMAzureRole -ErrorAction Stop) | ForEach-Object { "$($_.RoleDefinitionDisplayName) on $($_.ScopeDisplayName)" }
```

**Expect:** `Eligible: directory 2, group 1, Azure 2`; `Active: directory 0, group 0, Azure 0`;
`Reader on opim-s2-rg` and `Reader on opim-s2-rg2`.
**Failure looks like:** another eligible count -- STOP. Something already active -- record it; the
checks below count before and after. A terminating error from a read is a failed read, never a `0`.

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:28 UTC, window B (after the recorder fix in S.5): Eligible: directory 2, group 1, Azure 2; Active: directory 0, group 0, Azure 0; Reader on opim-s2-rg; Reader on opim-s2-rg2.
```

### 1. Reads, compared with 0.6.0 (the specification's 1.x)

Each check writes the rows of one read, from window B and from window C, to the raw folder
(`Export-Clixml`, which keeps the value types), and check 4.1 compares them.

### 1.1. The eligible roles

- [x] **1.1** Windows B and C. `Get-OPIMAzureRole` with no switch, written to the raw folder.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not (Get-Module Omnicit.PIM)) { throw 'Omnicit.PIM is not loaded in this window; run 0.1 (window B), or S.4 and 0.2 (window C), first.' }
if ((Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName -and (Get-Module Omnicit.PIM).Version -ne [version]'0.6.0') { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
$Raw = 'docs/live-verification/raw/opim-s21a'
$Window = if ((Get-Module Omnicit.PIM).Version -eq [version]'0.6.0') { 'C' } else { 'B' }
$Rows = @(Get-OPIMAzureRole -ErrorAction Stop)
$Rows | Export-Clixml -Path (Join-Path $Raw "cmp-eligible-$Window.clixml") -Depth 3
"Window $($Window): $($Rows.Count) rows; type names: $(($Rows[0].PSObject.TypeNames | Where-Object { $_ -like 'Omnicit.PIM.*' }) -join ', ')"
```

**Expect:** in both windows `2 rows`, type name `Omnicit.PIM.AzureEligibilitySchedule`.
**Failure looks like:** another count, or an error -- record it; 4.1 shows the difference.

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:28 UTC: Window B: 2 rows; type names: Omnicit.PIM.AzureEligibilitySchedule. Window C: 2 rows; type names: Omnicit.PIM.AzureEligibilitySchedule.
```

### 1.2. One role by name at one scope

- [x] **1.2** Windows B and C. `Get-OPIMAzureRole 'Reader' -Scope <opim-s2-rg>` (the scope taken from the eligible row, never printed), written to the raw folder.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not (Get-Module Omnicit.PIM)) { throw 'Omnicit.PIM is not loaded in this window; run 0.1 (window B), or S.4 and 0.2 (window C), first.' }
if ((Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName -and (Get-Module Omnicit.PIM).Version -ne [version]'0.6.0') { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
$Raw = 'docs/live-verification/raw/opim-s21a'
$Window = if ((Get-Module Omnicit.PIM).Version -eq [version]'0.6.0') { 'C' } else { 'B' }
$Rg = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg')[0].ScopeId
$Rows = @(Get-OPIMAzureRole 'Reader' -Scope $Rg -ErrorAction Stop)
$Rows | Export-Clixml -Path (Join-Path $Raw "cmp-byname-$Window.clixml") -Depth 3
"Window $($Window): $($Rows.Count) rows; scope display names: $(($Rows | ForEach-Object ScopeDisplayName) -join ', ')"
```

**Expect:** in both windows `1 rows`, `opim-s2-rg` (no role is active yet, so only the eligible post).
**Failure looks like:** `AmbiguousName`, `EligibleRoleNotFound`, another count -- record it.

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:28 UTC: Window B: 1 rows; scope display names: opim-s2-rg. Window C: 1 rows; scope display names: opim-s2-rg.
```

### 1.3. A plain listing at a resource group

- [x] **1.3** Windows B and C. `Get-OPIMAzureRole -Scope <opim-s2-rg2>`, the listing ARM answers for that scope, written to the raw folder.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not (Get-Module Omnicit.PIM)) { throw 'Omnicit.PIM is not loaded in this window; run 0.1 (window B), or S.4 and 0.2 (window C), first.' }
if ((Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName -and (Get-Module Omnicit.PIM).Version -ne [version]'0.6.0') { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
$Raw = 'docs/live-verification/raw/opim-s21a'
$Window = if ((Get-Module Omnicit.PIM).Version -eq [version]'0.6.0') { 'C' } else { 'B' }
$Rg2 = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg2')[0].ScopeId
$Rows = @(Get-OPIMAzureRole -Scope $Rg2 -ErrorAction Stop)
$Rows | Export-Clixml -Path (Join-Path $Raw "cmp-scope-$Window.clixml") -Depth 3
"Window $($Window): $($Rows.Count) rows; scope display names: $(($Rows | ForEach-Object ScopeDisplayName) -join ', ')"
```

**Expect:** in both windows `1 rows`, `opim-s2-rg2`.
**Failure looks like:** another count -- record it.

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:28 UTC: Window B: 1 rows; scope display names: opim-s2-rg2. Window C: 1 rows; scope display names: opim-s2-rg2.
```

### 1.4. The same read twice (G8)

- [x] **1.4** Window B. Two `Get-OPIMAzureRole` calls in a row give the same rows, and neither asks for a sign-in.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$First = @(Get-OPIMAzureRole -ErrorAction Stop | ForEach-Object Name | Sort-Object)
$Second = @(Get-OPIMAzureRole -ErrorAction Stop 6>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.InformationRecord]) { 'INFO' } else { $_.Name } } | Sort-Object)
"Same rows twice: $((Compare-Object $First $Second).Count -eq 0); device code messages: $(@($Second | Where-Object { $_ -eq 'INFO' }).Count)"
```

**Expect:** `Same rows twice: True; device code messages: 0`.
**Failure looks like:** `False`, or a device code -- record it; a sign-in mid-run is a STOP (run 0.1).

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:28 UTC, window B: Same rows twice: True; device code messages: 0.
```

### 2. The policy refusal, compared with 0.6.0 (the specification's 3.x)

### 2.1. An activation without a justification is refused with the same error id

- [x] **2.1** Windows B and C. `Enable-OPIMAzureRole 'Reader' -Scope <opim-s2-rg>` without `-Justification` is refused by the PIM policy, written as `RoleAssignmentRequestPolicyValidationFailed`, and nothing is activated.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not (Get-Module Omnicit.PIM)) { throw 'Omnicit.PIM is not loaded in this window; run 0.1 (window B), or S.4 and 0.2 (window C), first.' }
if ((Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName -and (Get-Module Omnicit.PIM).Version -ne [version]'0.6.0') { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
$Window = if ((Get-Module Omnicit.PIM).Version -eq [version]'0.6.0') { 'C' } else { 'B' }
$Rg = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg')[0].ScopeId
$Before = @(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count
$Out = @(Enable-OPIMAzureRole 'Reader' -Scope $Rg -Hours 1 -ErrorAction SilentlyContinue -ErrorVariable Errs 3>$null)
Start-Sleep -Seconds 20
$After = @(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count
"Window $($Window): results $($Out.Count); errors $($Errs.Count): $(($Errs | ForEach-Object FullyQualifiedErrorId | Select-Object -Last 1)); active before $Before, after $After"
"Message names the justification rule: $([bool]($Errs | Where-Object { $_.Exception.Message -match 'justification' }))"
```

**Expect:** in both windows `results 0`; the last error id
`RoleAssignmentRequestPolicyValidationFailed,Enable-OPIMAzureRole`; `active before 0, after 0`;
`Message names the justification rule: True`. The two windows give the same error id.
**Failure looks like:** another id in window B than in C -- a regression (G11). An activation
(`after` above `before`) -- STOP. A claims challenge or a refusal that names multi-factor
authentication -- STOP: Azure's mandatory MFA refuses the token (the sprint note's stop condition).

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:28-18:29 UTC. Window B: results 0; errors 5: RoleAssignmentRequestPolicyValidationFailed,Enable-OPIMAzureRole (the last of the -ErrorVariable entries, the cmdlet's own); active before 0, after 0; Message names the justification rule: True. Window C (0.6.0): results 0; errors 6: RoleAssignmentRequestPolicyValidationFailed,Enable-OPIMAzureRole; active before 0, after 0; True. The same error id in both windows. ARM's body, recorded: code RoleAssignmentRequestPolicyValidationFailed, message 'The following policy rules failed: JustificationRule - Justification is required'. No multi-factor refusal: this first ARM write reached the policy check.
```

### 3. Activation, deactivation, `-Wait`, `pim` and `unpim` (the specification's 2.x)

### 3.1. `-Hours` and `-Wait` on `opim-s2-rg`

- [x] **3.1** Window B. `Enable-OPIMAzureRole 'Reader' -Scope <opim-s2-rg> -Hours 1 -Wait -Justification ...` activates Reader on `opim-s2-rg` for one hour and returns the request with its final status.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Rg = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg')[0].ScopeId
$Elig = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg')[0]
$global:OpimS21aActivatedRg = [datetime]::UtcNow
$Req = @(Enable-OPIMAzureRole 'Reader' -Scope $Rg -Hours 1 -Wait -TimeoutSeconds 300 -Justification 'Omnicit.PIM step 1a live check 3.1' -ErrorAction SilentlyContinue -ErrorVariable Errs)
"Results $($Req.Count); errors $($Errs.Count) $(($Errs | ForEach-Object FullyQualifiedErrorId) -join ', ')"
if ($Req.Count -eq 1) {
    $R = $Req[0]
    "Type: $($R.PSObject.TypeNames[0]); Status: $($R.Status); RequestType: $($R.RequestType); ExpirationType: $($R.ExpirationType); ExpirationDuration: $($R.ExpirationDuration)"
    "Linked to the eligibility: $($R.LinkedRoleEligibilityScheduleId -like "*$($Elig.Name)"); scope is the resource group: $([string]::Equals($R.ScopeId, $Rg, [System.StringComparison]::OrdinalIgnoreCase)); principal is the eligibility's: $($R.PrincipalId -eq $Elig.PrincipalId)"
}
```

**Expect:** `Results 1; errors 0`; `Type: Omnicit.PIM.AzureAssignmentScheduleRequest`; `Status:
Provisioned` (or `Granted`); `RequestType: SelfActivate`; `ExpirationType: AfterDuration`;
`ExpirationDuration: PT1H`; the three True/False lines `True`.
**Failure looks like:** an error, or a status that is not a success -- record it; a refusal naming
multi-factor authentication -- STOP (as 2.1).

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:30 UTC, window B (15 s): Results 1; errors 0. Type: Omnicit.PIM.AzureAssignmentScheduleRequest; Status: Provisioned; RequestType: SelfActivate; ExpirationType: AfterDuration; ExpirationDuration: PT1H. Linked to the eligibility: True; scope is the resource group: True; principal is the eligibility's: True. ARM answered Provisioned at once, so -Wait had nothing to poll. Azure's mandatory MFA did not refuse the activation.
```

### 3.2. `-Activated` and `-All`, compared with 0.6.0 while Reader is active

- [x] **3.2** Windows B and C. `Get-OPIMAzureRole -Activated` and `-All`, once the activation of 3.1 is listed, written to the raw folder.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not (Get-Module Omnicit.PIM)) { throw 'Omnicit.PIM is not loaded in this window; run 0.1 (window B), or S.4 and 0.2 (window C), first.' }
if ((Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName -and (Get-Module Omnicit.PIM).Version -ne [version]'0.6.0') { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
$Raw = 'docs/live-verification/raw/opim-s21a'
$Window = if ((Get-Module Omnicit.PIM).Version -eq [version]'0.6.0') { 'C' } else { 'B' }
$Deadline = [datetime]::UtcNow.AddMinutes(8)
do { $Active = @(Get-OPIMAzureRole -Activated -ErrorAction Stop); if ($Active.Count -ge 1) { break }; Start-Sleep -Seconds 20 } while ([datetime]::UtcNow -lt $Deadline)
$All = @(Get-OPIMAzureRole -All -ErrorAction Stop)
$Active | Export-Clixml -Path (Join-Path $Raw "cmp-activated-$Window.clixml") -Depth 3
$All | Export-Clixml -Path (Join-Path $Raw "cmp-all-$Window.clixml") -Depth 3
"Window $($Window): activated $($Active.Count) ($(($Active | ForEach-Object { "$($_.RoleDefinitionDisplayName) on $($_.ScopeDisplayName), $($_.AssignmentType)" }) -join '; ')); all $($All.Count) ($(($All | ForEach-Object Status) -join ', '))"
```

**Expect:** in both windows `activated 1 (Reader on opim-s2-rg, Activated)` and `all 3 (Eligible,
Eligible, Active)` in some order.
**Failure looks like:** `activated 0` after eight minutes -- record it (ARM's listing lag, measured
in Sprint 1); the comparison in 4.1 then covers only the rows both windows saw.

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:30 UTC, the activation listed at once. Window B: activated 1 (Reader on opim-s2-rg, Activated); all 3 (Eligible, Eligible, Active). Window C: the same.
```

### 3.3. A second activation sends nothing (G8)

- [x] **3.3** Window B. The same `Enable-OPIMAzureRole` call again writes "already active" and sends no request.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Rg = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg')[0].ScopeId
$Puts = @(Get-Content -LiteralPath $global:OpimS21aRecord | ConvertFrom-Json | Where-Object method -EQ 'PUT').Count
$Out = @(Enable-OPIMAzureRole 'Reader' -Scope $Rg -Hours 1 -Justification 'Omnicit.PIM step 1a live check 3.3' -ErrorAction SilentlyContinue -ErrorVariable Errs -WarningVariable Warns 3>$null)
$PutsAfter = @(Get-Content -LiteralPath $global:OpimS21aRecord | ConvertFrom-Json | Where-Object method -EQ 'PUT').Count
"Results $($Out.Count); errors $($Errs.Count); warning names already active: $([bool]($Warns | Where-Object { "$_" -match 'already active' })); requests sent: $($PutsAfter - $Puts)"
```

**Expect:** `Results 0; errors 0; warning names already active: True; requests sent: 0`.
**Failure looks like:** a request sent -- record it (a second request can end the first, OPIM-39).

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:30 UTC, window B: Results 0; errors 0; warning names already active: True; requests sent: 0.
```

### 3.4. A deactivation inside five minutes is refused with `ActiveDurationTooShort`

- [x] **3.4** Window B. `Disable-OPIMAzureRole 'Reader' -Scope <opim-s2-rg>` within five minutes of 3.1 is refused by ARM, written as `ActiveDurationTooShort`, and the role stays active.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Rg = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg')[0].ScopeId
"Seconds since 3.1: $([int]([datetime]::UtcNow - $global:OpimS21aActivatedRg).TotalSeconds)"
$Out = @(Disable-OPIMAzureRole 'Reader' -Scope $Rg -ErrorAction SilentlyContinue -ErrorVariable Errs 3>$null)
"Results $($Out.Count); last error id: $(($Errs | ForEach-Object FullyQualifiedErrorId | Select-Object -Last 1)); still active: $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg').Count)"
```

**Record:** the seconds since 3.1 (under 300 for the check to mean anything), the result count, the
error id and the active count.
**Expect:** `Results 0`; `ActiveDurationTooShort,Disable-OPIMAzureRole`; `still active: 1`.
**Failure looks like:** a `Revoked` result -- record it; 3.7 then has nothing to deactivate.

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run 1, 18:30 UTC, 44 s after 3.1: Results 0; last error id RoleAssignmentDoesNotExist,Disable-OPIMAzureRole (ARM: 'The Role assignment does not exist.'); still active: 1. A measurement beyond the block, 18:31 UTC, window C with 0.6.0, 92 s after 3.1: ActiveDurationTooShort,Disable-OPIMAzureRole ('You must wait at least 5 minutes ...'); still active: 1. Run 2, 18:31 UTC, 108 s after 3.1, window B: Results 0; last error id ActiveDurationTooShort,Disable-OPIMAzureRole; still active: 1 (ARM: 'The Active duration is too short. Miniumum Required is 5 minutes.'). The first answer is ARM's window before the role assignment exists (same family as OPIM-41/50/53); after it the branch gives the same id and message as 0.6.0.
```

### 3.5. `-NotBefore` and `-Until` on `opim-s2-rg2`

- [x] **3.5** Window B. A scheduled activation of Reader on `opim-s2-rg2` sends its start and end in UTC and comes back as a scheduled request.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Rg2 = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg2')[0].ScopeId
$NotBefore = [datetime]::Now.AddMinutes(3)
$NotBefore = $NotBefore.AddTicks(-($NotBefore.Ticks % [TimeSpan]::TicksPerSecond))
$Until = $NotBefore.AddMinutes(60)
$global:OpimS21aStartRg2 = $NotBefore.ToUniversalTime()
$Req = @(Enable-OPIMAzureRole 'Reader' -Scope $Rg2 -NotBefore $NotBefore -Until $Until -Justification 'Omnicit.PIM step 1a live check 3.5' -ErrorAction SilentlyContinue -ErrorVariable Errs 3>$null)
"Results $($Req.Count); errors $($Errs.Count) $(($Errs | ForEach-Object FullyQualifiedErrorId) -join ', ')"
if ($Req.Count -eq 1) {
    $R = $Req[0]
    "Status: $($R.Status); ExpirationType: $($R.ExpirationType)"
    "Start equals -NotBefore in UTC: $([math]::Abs(($R.ScheduleInfoStartDateTime.ToUniversalTime() - $NotBefore.ToUniversalTime()).TotalSeconds) -lt 1)"
    "End equals -Until in UTC: $([math]::Abs(($R.ExpirationEndDateTime.ToUniversalTime() - $Until.ToUniversalTime()).TotalSeconds) -lt 1)"
}
```

**Expect:** `Results 1; errors 0`; `Status: ScheduleCreated` (or another scheduled status, recorded);
`ExpirationType: AfterDateTime`; both True/False lines `True`.
**Failure looks like:** `False` -- the time went to ARM in another zone (OPIM-18); record it.

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:32 UTC, window B (16 s): Results 1; errors 0; Status: Granted (recorded; ARM's answer for a start three minutes ahead); ExpirationType: AfterDateTime; Start equals -NotBefore in UTC: True; End equals -Until in UTC: True.
```

### 3.6. Five minutes after both activations

- [x] **3.6** Window B. The five-minute rule is waited out for both roles, and Reader on `opim-s2-rg2` has become active.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Wait = @(([datetime]::UtcNow - $global:OpimS21aActivatedRg), ([datetime]::UtcNow - $global:OpimS21aStartRg2)) | ForEach-Object { 320 - $_.TotalSeconds } | Measure-Object -Maximum
if ($Wait.Maximum -gt 0) { Start-Sleep -Seconds ([int][math]::Ceiling($Wait.Maximum)) }
$Deadline = [datetime]::UtcNow.AddMinutes(6)
do { $Rg2Active = @(Get-OPIMAzureRole -Activated -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg2').Count; if ($Rg2Active -ge 1) { break }; Start-Sleep -Seconds 20 } while ([datetime]::UtcNow -lt $Deadline)
"Seconds since 3.1: $([int]([datetime]::UtcNow - $global:OpimS21aActivatedRg).TotalSeconds); since the start of 3.5: $([int]([datetime]::UtcNow - $global:OpimS21aStartRg2).TotalSeconds); Reader on opim-s2-rg2 active: $Rg2Active"
```

**Expect:** both counts of seconds above 300; `Reader on opim-s2-rg2 active: 1`.
**Failure looks like:** `0` -- record it (the scheduled activation has not started, or ARM's listing
lags); 3.8 then deactivates only what is listed.

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:32-18:40 UTC, window B: Seconds since 3.1: 629; since the start of 3.5: 323; Reader on opim-s2-rg2 active: 1.
```

### 3.7. Deactivation of `opim-s2-rg`, twice (G8)

- [x] **3.7** Window B. `Disable-OPIMAzureRole 'Reader' -Scope <opim-s2-rg>` deactivates it (`Revoked`); the same call again writes `ActiveRoleNotFound` and sends nothing.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Rg = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg')[0].ScopeId
$R1 = @(Disable-OPIMAzureRole 'Reader' -Scope $Rg -ErrorAction SilentlyContinue -ErrorVariable Errs1 3>$null)
"First: results $($R1.Count); status $(($R1 | ForEach-Object Status) -join ', '); request type $(($R1 | ForEach-Object RequestType) -join ', '); errors $($Errs1.Count)"
Start-Sleep -Seconds 30
$Puts = @(Get-Content -LiteralPath $global:OpimS21aRecord | ConvertFrom-Json | Where-Object method -EQ 'PUT').Count
$R2 = @(Disable-OPIMAzureRole 'Reader' -Scope $Rg -ErrorAction SilentlyContinue -ErrorVariable Errs2 3>$null)
$PutsAfter = @(Get-Content -LiteralPath $global:OpimS21aRecord | ConvertFrom-Json | Where-Object method -EQ 'PUT').Count
"Second: results $($R2.Count); last error id $(($Errs2 | ForEach-Object FullyQualifiedErrorId | Select-Object -Last 1)); requests sent: $($PutsAfter - $Puts)"
$global:OpimS21aRevokedRg = [datetime]::UtcNow
```

**Expect:** `First: results 1; status Revoked; request type SelfDeactivate; errors 0`; `Second:
results 0; last error id ActiveRoleNotFound,Disable-OPIMAzureRole; requests sent: 0`.
**Failure looks like:** a crash or a second request -- record it (G8).

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:40-18:41 UTC, window B: First: results 1; status Revoked; request type SelfDeactivate; errors 0. Second: results 0; last error id ActiveRoleNotFound,Disable-OPIMAzureRole; requests sent: 0.
```

### 3.8. Deactivation of `opim-s2-rg2`

- [x] **3.8** Window B. `Disable-OPIMAzureRole 'Reader' -Scope <opim-s2-rg2>` deactivates the scheduled activation once it is active.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Rg2 = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg2')[0].ScopeId
$R = @(Disable-OPIMAzureRole 'Reader' -Scope $Rg2 -ErrorAction SilentlyContinue -ErrorVariable Errs 3>$null)
"Results $($R.Count); status $(($R | ForEach-Object Status) -join ', '); errors $(($Errs | ForEach-Object FullyQualifiedErrorId) -join ', ')"
```

**Expect:** `Results 1; status Revoked; errors` (none).
**Failure looks like:** `ActiveDurationTooShort` -- wait and run the block again;
`ActiveRoleNotFound` -- record it (3.6 found nothing active).

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:41 UTC, window B: Results 1; status Revoked; errors (none).
```

### 3.9. `pim` with an Azure entry, twice (G8)

- [~] **3.9** Window B. A tenant map alias holding Reader on `opim-s2-rg` activates it through `pim`; a second `pim` sends nothing.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s21a/TenantMap.psd1'
if (-not (Get-OPIMConfiguration -TenantAlias 's21a-az' -TenantMapPath $Map -ErrorAction SilentlyContinue)) {
    Get-OPIMAzureRole -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg' | Install-OPIMConfiguration -TenantAlias 's21a-az' -TenantMapPath $Map -Confirm:$false
}
$Wait = 90 - ([datetime]::UtcNow - $global:OpimS21aRevokedRg).TotalSeconds
if ($Wait -gt 0) { Start-Sleep -Seconds ([int][math]::Ceiling($Wait)) }
$global:OpimS21aPimRg = [datetime]::UtcNow
$First = @(Enable-OPIMMyRole -TenantAlias 's21a-az' -TenantMapPath $Map -Justification 'Omnicit.PIM step 1a live check 3.9' 2>&1 3>&1)
"First pim: results $(@($First | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' }).Count); statuses $(($First | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' } | ForEach-Object Status) -join ', '); errors $(@($First | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', ')"
Start-Sleep -Seconds 60
$Second = @(Enable-OPIMMyRole -TenantAlias 's21a-az' -TenantMapPath $Map -Justification 'Omnicit.PIM step 1a live check 3.9' 2>&1 3>&1)
"Second pim: results $(@($Second | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' }).Count); already active warnings $(@($Second | Where-Object { $_ -is [System.Management.Automation.WarningRecord] -and $_.Message -match 'already active' }).Count); errors $(@($Second | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count)"
```

**Expect:** `First pim: results 1; statuses Provisioned (or Granted); errors` (none); `Second pim:
results 0; already active warnings 1; errors 0`.
**Failure looks like:** `RoleAssignmentExists` on the first call -- ARM's window after the
deactivation in 3.7 (OPIM-53); record it and run the block again. A second request -- record it (G8).

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Run 1, 18:41-18:44 UTC: First pim: RoleAssignmentExists,Enable-OPIMAzureRole -- the active listing showed only 'Assigned' rows (see T.1) and ARM still held the assignment 2 minutes after 3.7's deactivation (OPIM-53). The block's second pim at 18:44:18 activated (recorded 201 Provisioned) but the block counted 0 results: its filter looked for Omnicit.PIM.AzureAssignmentScheduleRequest while pim returns Omnicit.PIM.MyRoleResult (block fixed). A diagnosis beyond the block, 18:44 UTC: a further pim wrote 'Reader -> opim-s2-rg is already active, so no new request was sent ...' and sent nothing. Run 2 (fixed block, 4 minutes after the unpim of 3.10), 18:54-18:55 UTC: First pim: results 1; statuses Provisioned. Second pim, 60 s later: results 0; already active warnings 0; errors 1 -- ARM's active listing at '/' was still empty 62 s after the activation, so the module requested again and ARM refused it, RoleAssignmentExists ('The Role assignment already exists.'); nothing was activated twice. Marked [~]: the G8 second call gave a clear refusal, not 'already active', because of ARM's listing lag, which 0.6.0 reads through the same API (OPIM-39's documented limit; step 5's scope).
```

### 3.10. `unpim` with the Azure entry, twice (G8)

- [x] **3.10** Window B. Five minutes after 3.9, `unpim` deactivates Reader on `opim-s2-rg`; a second `unpim` sends nothing.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s21a/TenantMap.psd1'
$Wait = 320 - ([datetime]::UtcNow - $global:OpimS21aPimRg).TotalSeconds
if ($Wait -gt 0) { Start-Sleep -Seconds ([int][math]::Ceiling($Wait)) }
$First = @(Disable-OPIMMyRole -TenantAlias 's21a-az' -TenantMapPath $Map 2>&1 3>&1)
"First unpim: results $(@($First | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' }).Count); statuses $(($First | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' } | ForEach-Object Status) -join ', '); errors $(@($First | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', ')"
Start-Sleep -Seconds 30
$Second = @(Disable-OPIMMyRole -TenantAlias 's21a-az' -TenantMapPath $Map 2>&1 3>&1)
"Second unpim: results $(@($Second | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' }).Count); errors $(@($Second | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count); other lines $(@($Second | Where-Object { $_ -is [System.Management.Automation.WarningRecord] -or $_ -is [string] }).Count)"
"Active Azure roles now: $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** `First unpim: results 1; statuses Revoked; errors` (none); `Second unpim: results 0;
errors 0`; `Active Azure roles now: 0`.
**Record:** the second call's other lines (a "not currently activated" message is expected).
**Failure looks like:** a crash, or a second request -- record it (G8).

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
18:46-18:50 UTC, window B (after the filter fix, the five minutes counted from the recorded activation at 18:44:18): First unpim: results 1; statuses Revoked; errors (none). Second unpim: results 0; errors 0; other lines 0. Active Azure roles now: 0. Run again after 3.9's second run, 18:56-19:00 UTC: the same lines.
```

### 4. The comparison with 0.6.0 (the specification's 1.x, A4)

### 4.1. Every row and every property, one at a time

- [x] **4.1** Window A (no module). Every read of section 1 and check 3.2 gives the same rows and, for every property, the same presence, value type and value in both windows.

```powershell
$Raw = 'docs/live-verification/raw/opim-s21a'
foreach ($Read in 'eligible', 'byname', 'scope', 'activated', 'all') {
    $B = @(Import-Clixml (Join-Path $Raw "cmp-$Read-B.clixml"))
    $C = @(Import-Clixml (Join-Path $Raw "cmp-$Read-C.clixml"))
    $Keys = @($B | ForEach-Object { "$($_.Name)|$($_.Status)" } | Sort-Object)
    "$($Read): rows B $($B.Count), C $($C.Count); same row keys: $((Compare-Object $Keys @($C | ForEach-Object { "$($_.Name)|$($_.Status)" } | Sort-Object)).Count -eq 0)"
    $Names = @($B + $C | ForEach-Object { $_.PSObject.Properties.Name } | Sort-Object -Unique)
    foreach ($P in $Names) {
        $InB = @($B | Where-Object { $_.PSObject.Properties[$P] }).Count -eq $B.Count
        $InC = @($C | Where-Object { $_.PSObject.Properties[$P] }).Count -eq $C.Count
        $SameType = $true; $SameValue = $true
        foreach ($Row in $B) {
            $Twin = @($C | Where-Object { $_.Name -eq $Row.Name -and $_.Status -eq $Row.Status })[0]
            if (-not $Twin) { $SameValue = $false; continue }
            $VB = $Row.$P; $VC = $Twin.$P
            $TB = if ($null -eq $VB) { 'null' } else { $VB.GetType().Name }
            $TC = if ($null -eq $VC) { 'null' } else { $VC.GetType().Name }
            if ($TB -ne $TC) { $SameType = $false }
            if ($VB -is [datetime] -and $VC -is [datetime]) { if ($VB.ToUniversalTime() -ne $VC.ToUniversalTime()) { $SameValue = $false } }
            elseif ([string]$VB -cne [string]$VC) { $SameValue = $false }
        }
        "  $($P): in B $InB; in C $InC; same type $SameType; same value $SameValue"
    }
}
```

**Expect:** for every read `same row keys: True`, and for every property `in B True; in C True; same
type True; same value True`.
**Record:** every property line that is not all `True`, with what differs (presence, type or value),
never the value.
**Failure looks like:** a property missing in B, another type, or another value -- a regression of
A4 within the step's scope (G11): fix it, and run sections 1 and 3.2 again.

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
19:01 UTC, window A (no module): every read has the same row keys in both windows (eligible 2/2, byname 1/1, scope 1/1, activated 1/1, all 3/3); 136 property lines in B True; in C True; same type True; same value True. The 7 others are -All's mixed rows: AssignmentType, LinkedRoleEligibilityScheduleId, LinkedRoleEligibilityScheduleInstanceId, OriginRoleAssignmentId, RequestId, RoleAssignmentScheduleId, UpdatedOn: in B False; in C False; same type True; same value True -- each belongs to one kind of row only; a row-by-row check shows every row with the same property names in both windows (eligible 27/27, active 30/30). A4 holds: the same names, types and values as 0.6.0.
```

### 5. Silent reuse and a new sign-in (the specification's 4.x)

### 5.1. The session reuses its tokens without a prompt

- [x] **5.1** Window B. An Azure read after the checks above signs in to nothing: no device code, and the module's ARM token is the same one.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$State = & (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }
$Expiry = $State.ArmTokenExpiry
$Out = @(Get-OPIMAzureRole -ErrorAction Stop 6>&1)
$State = & (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }
"Device code messages: $(@($Out | Where-Object { $_ -is [System.Management.Automation.InformationRecord] }).Count); rows: $(@($Out | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] }).Count); same ARM token expiry: $($State.ArmTokenExpiry -eq $Expiry); minutes left: $([int]($State.ArmTokenExpiry - [datetime]::UtcNow).TotalMinutes)"
```

**Expect:** `Device code messages: 0; rows: 2; same ARM token expiry: True`; minutes left above 5.
**Failure looks like:** a device code -- the cached token was not reused; record it. Minutes left at
or below 5 -- the block legitimately asks for a new token; run 5.2 instead and record it.

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
19:01 UTC, window B: Device code messages: 0; rows: 2; same ARM token expiry: True; minutes left: 31.
```

### 5.2. `Disconnect-OPIM`, then a new sign-in

- [x] **5.2** Window B. `Disconnect-OPIM` clears the module's tokens, Azure's included, and the next `Connect-OpimLiveUser -IncludeARM` signs in again with two device codes.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Old = (& (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }).ArmTokenExpiry
Disconnect-OPIM
"State cleared: $($null -eq (& (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }))"
$Sign = Connect-OpimLiveUser -IncludeARM -RawFolder 'docs/live-verification/raw/opim-s21a'
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
$State = & (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }
"A new ARM token: $($State.ArmToken -is [securestring] -and $State.ArmTokenExpiry -ne $Old)"
"Rows after the new sign-in: $(@(Get-OPIMAzureRole -ErrorAction Stop).Count)"
```

**Expect:** `State cleared: True`; the rows `Graph Information True ok` and `AzureCli Information True
ok`; every harness True/False line `True`; `A new ARM token: True`; `Rows after the new sign-in: 2`.
**Failure looks like:** no Azure code (AzAuth reused its credential without a prompt) -- record it;
the Azure check lines still decide. `False` on an identity line -- STOP.

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
19:01 UTC, window B (23 s): State cleared: True; rows Graph Information True ok and AzureCli Information True ok; every harness line True; A new ARM token: True; Rows after the new sign-in: 2.
```

## Teardown

This step created no object, so nothing is removed from the tenant. The checks verify that nothing
is left active, that no object carries the step's prefix, and that no window keeps a session.

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

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
19:01 UTC, window B: Active: directory 0, group 0, Azure 0. Recorded beyond the block: after each deactivation ARM's asTarget() instance listing kept the revoked activation for several minutes as an 'Assigned' row (status Provisioned, no end time, the activation's start) -- the module lists Activated rows only. Read as oer-live-cc at 19:03 UTC: the test user holds 0 role assignments, 0 schedule instances and 0 schedules on opim-s2-rg and on opim-s2-rg2.
```

### T.2. The windows sign out

- [x] **T.2** Windows B and C. Each window's session is cleared and its window ended.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not (Get-Module Omnicit.PIM)) { throw 'Omnicit.PIM is not loaded in this window; run 0.1 (window B), or S.4 and 0.2 (window C), first.' }
if ((Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName -and (Get-Module Omnicit.PIM).Version -ne [version]'0.6.0') { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
Disconnect-OPIM
try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { $null = $PSItem }
if ((Get-Module Omnicit.PIM).Version -eq [version]'0.6.0') { try { Disconnect-AzAccount -ErrorAction Stop | Out-Null } catch { $null = $PSItem } }
"Module state cleared: $($null -eq (& (Get-Module Omnicit.PIM) { $script:_OPIMAuthState })); Graph context left: $([bool](Get-MgContext))"
```

**Expect:** `Module state cleared: True; Graph context left: False` in both windows.
**Failure looks like:** `False` / `True` -- record it, and end the window.

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
19:01 UTC: window B: Module state cleared: True; Graph context left: False. Window C: the same. Both windows ended.
```

### T.3. The recorded answers

- [~] **T.3** Window A (no module). The recorder's file holds ARM's answers to every kind of request this file made; they are redacted into the unit tests' fixtures before the raw folder goes.

```powershell
$Rows = @(Get-Content -LiteralPath 'docs/live-verification/raw/opim-s21a/arm-record.jsonl' | ConvertFrom-Json)
$Rows | Group-Object { "$($_.method) $(($_.path -split '/providers/Microsoft.Authorization/')[-1] -replace '/[0-9a-fA-F-]{36}$', '/(name)') $($_.status)" } | Sort-Object Name | ForEach-Object { "$($_.Count) x $($_.Name)" }
"Bodies with an error code: $(@($Rows | Where-Object { $_.content -match '"error"\s*:' } | ForEach-Object { ($_.content | ConvertFrom-Json).error.code } | Sort-Object -Unique) -join ', ')"
```

**Record:** each kind of request with its count and status, and the error codes ARM sent.
**Expect:** at least the eligible and active lists (200), the activation and deactivation requests
(201), the poll list (200), and the error bodies `RoleAssignmentRequestPolicyValidationFailed` and
`ActiveDurationTooShort`.
**Failure looks like:** a kind missing -- the fixture of that kind keeps its documented shape, which
the result line says.

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
19:02 UTC, window A: 36 x GET roleEligibilitySchedules 200; 31 x GET roleAssignmentScheduleInstances 200; 8 x PUT roleAssignmentScheduleRequests 201; 5 x PUT 400. Error codes: ActiveDurationTooShort, RoleAssignmentDoesNotExist, RoleAssignmentExists, RoleAssignmentRequestPolicyValidationFailed. No GET of roleAssignmentScheduleRequests: every activation answered with a final status, so -Wait never polled; the poll stays proven by the unit tests only. Redacted into eight fixtures under tests/Unit/TestHelpers/ArmResponse/recorded-*.json (ids replaced by non-v4 placeholders, mail by user@contoso.com, the justification text neutral; OerLive's redactor finds nothing more).
```

### T.4. No object of the step, and the raw folder

- [x] **T.4** Window A, then the operator. No object carries `opim-s21a-`; the raw folder, with the comparison files, the recorder's file, the tenant map and the 0.6.0 module, is deleted once the results are written up.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$null = Import-OerLiveConfig -Prefix 'opim-s21a-'
Connect-OerLive -Graph
"Objects with the prefix opim-s21a-: $(@(Find-OerLivePrefixed -Prefix 'opim-s21a-' -ThrowOnUnread -Quiet).Count)"
Disconnect-OerLive
Remove-Item -LiteralPath 'docs/live-verification/raw/opim-s21a' -Recurse -Force
"Raw folder gone: $(-not (Test-Path -LiteralPath 'docs/live-verification/raw/opim-s21a'))"
"Untracked files under docs/live-verification: $(@(git status --porcelain --untracked-files=all -- docs/live-verification | Where-Object { $_.StartsWith('??') }).Count)"
```

**Expect:** `Objects with the prefix opim-s21a-: 0`; `Raw folder gone: True`; `Untracked files under
docs/live-verification: 0`.
**Failure looks like:** a prefixed object -- STOP (it was not made by this file). The fixture
`opim-s2-` stays on purpose until step 5.

Result: 2026-10-09 19:05 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
19:05 UTC, window A: Objects with the prefix opim-s21a-: 0; Raw folder gone: True; Untracked files under docs/live-verification: 1 -- the block's filter -like '??*' read ? as a wildcard and counted the modified checklist; with StartsWith('??') (block fixed): 0. The fixture opim-s2- stays until step 5.
```
