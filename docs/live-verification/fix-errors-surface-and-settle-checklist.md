# Live verification checklist -- every refused activation reaches the caller's -ErrorVariable, and the seconds right after a change settle (fix/errors-surface-and-settle)

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
this file activates and which section 4 tears down) and `opim-s25-` (this step's own objects, of
which there are none), with one named exception: the teardown removes the test user's membership in
the group `Exclude from CA` (decision P-10 (a)), which carries no prefix. Check 0.1 proves the
identity before any other check calls the module. If a browser window or a sign-in prompt appears
mid-run, STOP and run check 0.1 again: in this file every sign-in is a device code, and the proof of
0.1 holds only for the sign-in it checked.

**Two windows, never one process** (decision A10 of Sprint 1, kept in Sprint 2). Window A runs as
`oer-live-cc` and reads files without the module. Window B runs the branch's build as the test user,
in a `pwsh -NoProfile` that loads AzAuth 2.9.0 and Microsoft.Graph.Authentication 2.36.0 from the
build's own dependencies before the module. Every block below names its window.

**No block prints a scope id, an object id, a tenant id, a sign-in name or a message that holds
one.** The blocks print counts, statuses, error ids, display names of the fixture's roles, group and
resource groups, seconds and True/False.

## What changed and why this needs a live tenant

- **A. Every refusal inside `pim` and `unpim` reaches the caller's `-ErrorVariable`** ("fix: surface
  every refusal of a pim and unpim pillar in -ErrorVariable"). A pillar cmdlet piped into
  `ConvertTo-OPIMMyRoleResult` is not the last command of its pipeline, so its errors never reached
  the caller's `-ErrorVariable` (OPIM-52; measured in a scratch process, and live in Sprint 1 step 5b,
  1.3). Its error stream is now redirected into the converter, which writes each refusal through
  `pim` or `unpim`. A mock writes errors through a Pester function, so only a live refusal from Graph
  and Azure shows that the real pillar cmdlets' records arrive (section 1).
- **B. `Get-OPIMAzureRole -Activated -Scope` reads at the root** ("fix: read active Azure roles at the
  root and keep the asked scope"). Azure's list at a resource group lagged a new activation by about
  20 seconds (OPIM-41); only a live activation shows the row at once (2.1).
- **C. An Azure activation refused with `RoleAssignmentExists` right after a change** ("fix: settle an
  Azure activation refused right after a change", "fix: bound the Azure retry window and name the
  permanent case"). The active list is read again; an active role gets the "already active" warning,
  and otherwise a new request is sent every 10 seconds for up to a minute (OPIM-53). Only Azure's own
  timing after a deactivation shows whether the retry lands (2.2, 2.3).
- **D. A group deactivation Graph refuses moments after another** ("fix: report a group deactivated
  moments ago as not active"). `RoleAssignmentDoesNotExist` is reported as `ActiveRoleNotFound`
  (OPIM-50). This file records which code Graph gives today (3.3) and that a deactivation inside the
  first five minutes is still `ActiveDurationTooShort`, never `ActiveRoleNotFound` (3.2).
- **E. The configured Azure entry in an ambiguous `unpim` match, the throttle waits, and the release
  notes** ("fix: name the configured Azure entry in an ambiguous unpim match", "fix: never wait out
  throttling in tab completion or past a -Wait deadline", "docs: say which -Wait reads the deadline
  bounds", "docs: bound the throttle and retry claims in help and README to the code", "test: hold that
  no role after a refusal reaches the pillar under Stop", "test: keep the $global:Error counts
  independent of earlier test files", "docs: write the 0.7.0 release notes as one note", "docs: keep
  the 0.7.0 release notes within what the code does", "docs: record the measured test figures"). No live effect this file can provoke; see the
  next section.
- **F. The fixture's teardown** (decision A10, scope 7). Section 4 removes the sprint's fixture with
  `Initialize-OpimS2Prereq.ps1 -Teardown` as `oer-live-cc`: the membership in `Exclude from CA`
  first, the Azure eligibilities before their resource groups, the group before its PIM for Groups
  entries (OPIM-54), then the directory role eligibilities, the user and the two secrets.

The mapping to the step's specification: its 1.x is section 1, its 2.x is 2.2 and 2.3, its 3.x is the
second half of 2.1, its 4.x is section 3, its 5.x is section 4, and G8 is 1.3, 2.3 and 3.4.

The fixture of Sprint 2 (decision A15) is used as it stands until section 4 removes it: the test
user `opim-s2-live-user`, the group `opim-s2-grp` (eligible as member), the resource groups
`opim-s2-rg` and `opim-s2-rg2` (Reader eligible on each), and the directory roles Usage Summary
Reports Reader and Message Center Privacy Reader. The PIM policies of the fixture require a
justification on activation (measured in the fixture session); section 1 relies on that refusal,
and every other activation passes a justification. This step creates no object in the tenant, so it
has no prerequisite script of its own. The run's tenant map lives in the raw folder and is deleted
with it.

## What this file does not check, and why

Class B, each proven by the tests named:

- **Tab completion never waits out throttling, and `-Wait` never waits past `-TimeoutSeconds` for a
  throttled read** -- throttling cannot be provoked in the test tenant on purpose.
  `tests/Unit/Classes/ArgumentCompleters.Tests.ps1`, `tests/Unit/Private/Set-OPIMCompletionState.Tests.ps1`,
  `tests/Unit/Private/Invoke-OPIMGraphRequest.Tests.ps1`, `tests/Unit/Private/Invoke-OPIMArmRequest.Tests.ps1`,
  `tests/Unit/Public/Wait-OPIMDirectoryRole.Tests.ps1`, `tests/Unit/Public/Enable-OPIMEntraIDGroup.Tests.ps1`,
  `tests/Unit/Public/Enable-OPIMAzureRole.Tests.ps1`.
- **The configured Azure entry named in an ambiguous `unpim` match** -- the fixture holds one Reader
  per resource group, so no entry matches two active posts. `tests/Unit/Public/Disable-OPIMMyRole.Tests.ps1`.
- **One prompt per refusal under `-ErrorAction Inquire`** -- no block can answer a prompt.
  `tests/Unit/Public/Enable-OPIMMyRole.Tests.ps1` pins the pillar's forced `Continue`.
- **`pim` under `-ErrorAction Stop` ends at the first refusal after emitting the results before it**
  -- the fixture refuses all three kinds alike. `tests/Unit/Public/Enable-OPIMMyRole.Tests.ps1`.
- **A `BadRequest` group deactivation stays `BadRequest`, and no refusal other than
  `RoleAssignmentExists` is ever sent again** -- `tests/Unit/Public/Disable-OPIMEntraIDGroup.Tests.ps1`,
  `tests/Unit/Public/Enable-OPIMAzureRole.Tests.ps1`.
- **The 60-second give-up of the Azure retry and its message** -- reached live only if Azure keeps
  refusing for a minute (2.3 records it if it happens). `tests/Unit/Public/Enable-OPIMAzureRole.Tests.ps1`.

## Setup, once

The operator sets `OPIMLIVE_HOME` in both windows to the notes folder that holds the `OpimLive`
folder, and `OPIMLIVE_PREFIX` to `opim-s2-` in window B; no checklist holds the path. The test user's
sign-in name and the test tenant's id are read by the harness through OerLive and are never printed.
Both windows run from the root of the step's worktree. Raw output and the run's tenant map go to
`docs/live-verification/raw/opim-s25` (git-ignored), which is deleted once the results are written
up.

A block that runs the module in window B starts with the three-line prologue of the template.

### S.1. Find the build under test and tie it to the branch head

- [ ] **S.1** Window A (no module). The newest build in `output/module/Omnicit.PIM/` was made after the branch head was committed, and it holds this branch's changes.

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
"The built module forwards pillar errors: $([bool](Select-String -LiteralPath $Psm1 -Pattern 'ConvertTo-OPIMMyRoleResult -Cmdlet $PSCmdlet' -SimpleMatch -Quiet))"
"The built module retries RoleAssignmentExists: $([bool](Select-String -LiteralPath $Psm1 -Pattern 'still sees an earlier assignment' -SimpleMatch -Quiet))"
"The built module holds Set-OPIMCompletionState: $([bool](Select-String -LiteralPath $Psm1 -Pattern 'function Set-OPIMCompletionState' -SimpleMatch -Quiet))"
$Raw = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s25'
$null = New-Item -ItemType Directory -Force -Path $Raw
git check-ignore -q $Raw
"The raw folder is git-ignored: $($LASTEXITCODE -eq 0)"
```

**Expect:** the branch head's hash and subject; the version folder; `Built after the branch head was
committed: True`; `Tracked changes in the working tree: 0`; the four last lines `True`.
**Failure looks like:** `False` on the third line or a tracked change -- build again before any check
below. `False` on the raw folder -- STOP: the tenant map would be tracked.

Result:

### S.2. Window B loads the pinned dependencies

- [ ] **S.2** Window B, a fresh `pwsh -NoProfile`, before anything else runs in it. AzAuth 2.9.0 and Microsoft.Graph.Authentication 2.36.0 are loaded from the build's own dependencies, no Az module is loaded, and `AZURE_AUTHORITY_HOST` is not set.

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
**Record:** `this window can find:`.
**Failure looks like:** another version, or an Az module loaded -- end the window and start a fresh
one. `AZURE_AUTHORITY_HOST is set: True` -- STOP: clear it in a fresh window first.

Result:

### S.3. The fixture is in place, and nothing carries the step's prefix

- [ ] **S.3** Window A, as `oer-live-cc`. The prerequisite script with `-WhatIf` finds every object of the fixture and would write nothing, and no object carries the prefix `opim-s25-`.

```powershell
$Prereq = Join-Path $env:OPIMLIVE_HOME 'Initialize-OpimS2Prereq.ps1'
# A child process, so its host output -- the What if lines included -- arrives here as text.
$Lines = @(pwsh -NoProfile -NonInteractive -File $Prereq -WhatIf 2>&1 | ForEach-Object { ([string]$_) -replace '\x1b\[[0-9;]*m', '' })
"Lines 'exists; kept': $(@($Lines | Where-Object { $_ -match 'exists; kept' }).Count)"
"What if lines other than the transcript: $(@($Lines | Where-Object { $_ -match '^What if:' -and $_ -notmatch 'transcript' }).Count)"
$Lines | Where-Object { $_ -match "Sweep 'opim-s|Residue:|Group 'Exclude from CA'|PIM policy of|exists; kept" }
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$null = Import-OerLiveConfig -Prefix 'opim-s25-'
Connect-OerLive -Graph
"Objects with the prefix opim-s25-: $(@(Find-OerLivePrefixed -Prefix 'opim-s25-' -ThrowOnUnread -Quiet).Count)"
Disconnect-OerLive
```

**Expect:** `Lines 'exists; kept': 10`; `What if lines other than the transcript: 0`; the sweeps
`opim-s1-` 0 and `opim-s2-` 1 user, 1 group, 0 other; every PIM policy line without approval or
authentication context and with a justification on activation; `Objects with the prefix opim-s25-: 0`.
**Failure looks like:** any `What if:` line that would create an object, a count other than 10, or a
prefixed object that is not the fixture's -- STOP: create nothing and ask for nothing. A 401 or 403
-- STOP (G6).

Result:

### S.4. The harness loads in window B

- [ ] **S.4** Window B. OerLive is 1.0.3, OpimLive is 1.0.5, the harness reads the test values through it, and the TOTP implementation reproduces RFC 6238.

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

Result:

### 0. Preparation

### 0.1. Identity check

- [ ] **0.1** Window B. `Connect-OpimLiveUser -IncludeARM` signs the build in to Graph and Azure with one device code each; the account is the test user, the tenant the test tenant, and the ARM token the test user's in the test tenant; no Az module is loaded.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
"AzAuth $((Get-Module AzAuth).Version); Microsoft.Graph.Authentication $((Get-Module Microsoft.Graph.Authentication).Version)"
$Target = Get-OpimLiveTarget
$Sign = Connect-OpimLiveUser -IncludeARM -RawFolder 'docs/live-verification/raw/opim-s25'
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
$State = & (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }
"Session tenant is the test tenant: $([string]::Equals([string]$State.TokenTenantId, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
"Session cloud: $($State.Environment); ARM token held as a SecureString: $($State.ArmToken -is [securestring]); minutes left: $([int]($State.ArmTokenExpiry - [datetime]::UtcNow).TotalMinutes)"
"Az modules loaded: $(@(Get-Module -Name 'Az', 'Az.*').Count)"
```

**Expect:** `AzAuth 2.9.0; Microsoft.Graph.Authentication 2.36.0`; the rows `Graph Information True
ok` and `AzureCli Information True ok`; every True/False line of the harness `True`; `Session tenant
is the test tenant: True`; `Session cloud: Global`, `True`, minutes above 5; `Az modules loaded: 0`.
No line prints the account or the tenant id.
**Failure looks like:** `False` on any line, a `STOP`, or an Azure row that is not `AzureCli
Information True ok` -- STOP: run `Disconnect-OPIM`, end window B and run no other check. An ARM token
whose tenant or user is not the test user's is a STOP even though the module refused it (the harness
signed in wrong).

Result:

### 0.2. What is eligible and what is active

- [ ] **0.2** Window B. The fixture's eligibilities are listed, and nothing is active.

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

Result:

### 1. A refusal inside `pim` reaches `-ErrorVariable` (OPIM-52)

### 1.1. The tenant map of the run

- [ ] **1.1** Window B. A tenant map in the raw folder holds the alias `s25-all` (Usage Summary Reports Reader, the membership of `opim-s2-grp` and Reader on `opim-s2-rg`) and the alias `s25-az` (Reader on `opim-s2-rg` only).

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s25/TenantMap.psd1'
if (-not (Test-Path -LiteralPath $Map)) {
    $Reader = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg')
    $Rows = @(
        @(Get-OPIMDirectoryRole -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq 'Usage Summary Reports Reader' })
        @(Get-OPIMEntraIDGroup -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s2-grp' -and $_.accessId -eq 'member' })
        $Reader
    )
    "Rows to store: s25-all $($Rows.Count), s25-az $($Reader.Count)"
    # Their host lines name the stored keys, which hold ids, so they go nowhere.
    $Rows | Install-OPIMConfiguration -TenantAlias 's25-all' -TenantMapPath $Map -Confirm:$false 6>$null
    $Reader | Install-OPIMConfiguration -TenantAlias 's25-az' -TenantMapPath $Map -Confirm:$false 6>$null
}
foreach ($Alias in 's25-all', 's25-az') {
    $Config = Get-OPIMConfiguration -TenantAlias $Alias -TenantMapPath $Map -ErrorAction Stop
    # A list the alias does not hold reads as $null, and @($null).Count is 1, so only real entries are counted.
    "$($Alias): directory $(@($Config.DirectoryRoles | Where-Object { $_ }).Count), group $(@($Config.EntraIDGroups | Where-Object { $_ }).Count), Azure $(@($Config.AzureRoles | Where-Object { $_ }).Count); Environment: $($Config.Environment)"
}
```

**Expect:** `Rows to store: s25-all 3, s25-az 1` (on the first run); `s25-all: directory 1, group 1,
Azure 1; Environment: Global`; `s25-az: directory 0, group 0, Azure 1; Environment: Global`.
**Failure looks like:** another count -- record it, and do not run section 1 until the map holds the
entries.

Result:

### 1.2. `pim` without a justification, under `-ErrorAction SilentlyContinue`

- [ ] **1.2** Window B. `pim -TenantAlias s25-all` with no justification is refused by the policy for all three kinds; each refusal is in `-ErrorVariable`, nothing reaches the error stream, and nothing is activated.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s25/TenantMap.psd1'
$Caught = $null
$Out = @(Enable-OPIMMyRole -TenantAlias 's25-all' -TenantMapPath $Map -ErrorVariable Caught -ErrorAction SilentlyContinue 2>&1 3>&1)
$Results = @($Out | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' })
$Refusals = @($Caught | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'RoleAssignmentRequestPolicyValidationFailed*' })
"Results: $($Results.Count); error stream records: $(@($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count); warnings: $(@($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count)"
"-ErrorVariable: records $(@($Caught).Count); policy refusals $($Refusals.Count): $(@($Refusals | ForEach-Object FullyQualifiedErrorId) -join ', ')"
"Every refusal names the justification rule: $(@($Refusals | Where-Object { $_.Exception.Message -notmatch '(?i)justification' }).Count -eq 0)"
"Other records in -ErrorVariable: $(@($Caught | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] -or $_.FullyQualifiedErrorId -notlike 'RoleAssignmentRequestPolicyValidationFailed*' } | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.FullyQualifiedErrorId } else { $_.GetType().Name } }) -join ', ')"
"Active: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** `Results: 0; error stream records: 0`; `policy refusals 3`, each
`RoleAssignmentRequestPolicyValidationFailed,Enable-OPIMMyRole`; `Every refusal names the
justification rule: True`; `Active: directory 0, group 0, Azure 0`.
**Record:** `records` and the other records in `-ErrorVariable`.
**Failure looks like:** `policy refusals 0` -- the defect of OPIM-52 is still there: a defect within
this step's scope (G11). A result, or an active role -- STOP: the policy did not refuse, and something
was activated without a justification.

Result:

### 1.3. The same under `-ErrorAction Continue`, twice (G8)

- [ ] **1.3** Window B. The same `pim` under `-ErrorAction Continue` writes each refusal to the error stream once and puts it in `-ErrorVariable`; run twice, it gives the same answer and activates nothing.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s25/TenantMap.psd1'
foreach ($Try in 1, 2) {
    $Caught = $null
    $Out = @(Enable-OPIMMyRole -TenantAlias 's25-all' -TenantMapPath $Map -ErrorVariable Caught -ErrorAction Continue 2>&1 3>&1)
    $Stream = @($Out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    "Call $($Try): results $(@($Out | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' }).Count); error stream $($Stream.Count): $(@($Stream | ForEach-Object FullyQualifiedErrorId) -join ', '); policy refusals in -ErrorVariable $(@($Caught | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'RoleAssignmentRequestPolicyValidationFailed*' }).Count)"
}
"Active: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** for each call `results 0; error stream 3`, each
`RoleAssignmentRequestPolicyValidationFailed,Enable-OPIMMyRole`, and `policy refusals in
-ErrorVariable 3`; `Active: directory 0, group 0, Azure 0`.
**Failure looks like:** `error stream 6` -- a refusal written twice: a defect within this step's
scope (G11). `policy refusals in -ErrorVariable 0` -- as in 1.2. A result -- STOP, as in 1.2.

Result:

### 2. Azure right after a change (OPIM-41, OPIM-53)

### 2.1. An activation, and `-Activated -Scope` straight after it

- [ ] **2.1** Window B. `pim -TenantAlias s25-az` with a justification activates Reader on `opim-s2-rg`; straight after it, `Get-OPIMAzureRole -Activated -Scope` for that resource group shows the row, at the same read as `Get-OPIMAzureRole -Activated`.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s25/TenantMap.psd1'
$global:OpimS25RgScope = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg')[0].ScopeId
$global:OpimS25Az = [datetime]::UtcNow
$First = @(Enable-OPIMMyRole -TenantAlias 's25-az' -TenantMapPath $Map -Justification 'Omnicit.PIM step 5 live check 2.1' 2>&1 3>&1)
"pim s25-az: results $(@($First | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' } | ForEach-Object { '{0} {1}' -f $_.DisplayName, $_.Status }) -join '; '); errors $(@($First | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', ')"
$Seen = @{}
while (([datetime]::UtcNow - $global:OpimS25Az).TotalSeconds -lt 180 -and $Seen.Count -lt 2) {
    $Now = [int]([datetime]::UtcNow - $global:OpimS25Az).TotalSeconds
    if (-not $Seen.ContainsKey('scope') -and @(Get-OPIMAzureRole -Activated -Scope $global:OpimS25RgScope -ErrorAction Stop).Count -ge 1) { $Seen['scope'] = $Now }
    if (-not $Seen.ContainsKey('root') -and @(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count -ge 1) { $Seen['root'] = $Now }
    if ($Seen.Count -lt 2) { Start-Sleep -Seconds 5 }
}
"Seconds after the pim until the row showed: -Activated -Scope opim-s2-rg $($Seen['scope']); -Activated $($Seen['root'])"
```

**Expect:** `pim s25-az: results Reader Provisioned` (or `Granted`) and no error; both rows shown
within 180 seconds, `-Activated -Scope` no later than the root read of the same round (it is now the
same request).
**Record:** both seconds.
**Failure looks like:** the `-Scope` row later than the root row, or missing while the root row shows
-- the read is still made at the resource group: a defect within this step's scope (G11).

Result:

### 2.2. `unpim` and then `pim` at once

- [ ] **2.2** Window B. Five minutes after 2.1, `unpim -TenantAlias s25-az` deactivates Reader, and `pim -TenantAlias s25-az` straight after it activates Reader again -- or reports it already active -- within about a minute, with no error.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s25/TenantMap.psd1'
$Wait = 320 - ([datetime]::UtcNow - $global:OpimS25Az).TotalSeconds
if ($Wait -gt 0) { Start-Sleep -Seconds ([int][math]::Ceiling($Wait)) }
$Off = @(Disable-OPIMMyRole -TenantAlias 's25-az' -TenantMapPath $Map 2>&1 3>&1)
"unpim s25-az: results $(@($Off | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' } | ForEach-Object { '{0} {1}' -f $_.DisplayName, $_.Status }) -join '; '); errors $(@($Off | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', ')"
$Started = [datetime]::UtcNow
$global:OpimS25Az2 = $Started
$On = @(Enable-OPIMMyRole -TenantAlias 's25-az' -TenantMapPath $Map -Justification 'Omnicit.PIM step 5 live check 2.2' -Verbose 2>&1 3>&1 4>&1)
"pim s25-az straight after, $([int]([datetime]::UtcNow - $Started).TotalSeconds) s: results $(@($On | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' } | ForEach-Object { '{0} {1}' -f $_.DisplayName, $_.Status }) -join '; ')"
"New requests after RoleAssignmentExists: $(@($On | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match 'still sees an earlier assignment' }).Count); already active warnings: $(@($On | Where-Object { $_ -is [System.Management.Automation.WarningRecord] -and $_.Message -match 'already active' }).Count); errors: $(@($On | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', ')"
```

**Expect:** `unpim s25-az: results Reader Revoked` and no error; `pim s25-az straight after` with
`results Reader Provisioned` (or `Granted`) and no error, or `results` none with one `already active`
warning; the seconds at most about 70.
**Record:** the seconds, and the count of new requests after `RoleAssignmentExists` (0 when Azure
did not refuse at all).
**Failure looks like:** `RoleAssignmentExists,Enable-OPIMMyRole` -- Azure still refused after the
minute: record the message (it names the earlier assignment); this is the documented give-up, and a
finding if it recurs. Two results, or `ActiveDurationTooShort` on the `unpim` (the five minutes were
not waited out) -- record it. A sign-in prompt -- STOP (0.1).

Result:

### 2.3. `pim` again straight away: Azure's window, and a second call (G8)

- [ ] **2.3** Window B. `pim -TenantAlias s25-az` runs twice more, straight after 2.2. When 2.2 activated Reader, neither call sends a second activation. When 2.2 ended in the give-up and nothing is active, the first call measures how long after the deactivation Azure accepts a new activation, and the second call sends no second activation.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s25/TenantMap.psd1'
$Reference = $global:OpimS25Az2
"Active Azure roles before: $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
$Accepted = 0
foreach ($Try in 1, 2) {
    $Started = [datetime]::UtcNow
    $Again = @(Enable-OPIMMyRole -TenantAlias 's25-az' -TenantMapPath $Map -Justification "Omnicit.PIM step 5 live check 2.3, call $Try" -Verbose 2>&1 3>&1 4>&1)
    $Results = @($Again | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' })
    $Errors = @($Again | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    if ($Results.Count -gt 0) { $Accepted += $Results.Count; $global:OpimS25Az2 = $Started }
    "Call $Try, started $([int]($Started - $Reference).TotalSeconds) s after 2.2's pim, took $([int]([datetime]::UtcNow - $Started).TotalSeconds) s: results $(@($Results | ForEach-Object { '{0} {1}' -f $_.DisplayName, $_.Status }) -join '; '); already active warnings $(@($Again | Where-Object { $_ -is [System.Management.Automation.WarningRecord] -and $_.Message -match 'already active' }).Count); new requests after RoleAssignmentExists $(@($Again | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match 'still sees an earlier assignment' }).Count)"
    "  Errors: $(@($Errors | ForEach-Object FullyQualifiedErrorId) -join ', '); the message names the earlier assignment: $(@($Errors | Where-Object { $_.Exception.Message -match 'still sees an earlier assignment' }).Count -eq $Errors.Count)"
}
"Activations accepted in 2.2 and 2.3 together: $Accepted (2.2 accepted none when it ended in the give-up); active Azure roles: $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** never more than one activation accepted in 2.2 and 2.3 together; each error
`RoleAssignmentExists,Enable-OPIMMyRole` with a message that names the earlier assignment (`True`).
When 2.2 activated Reader (`Active Azure roles before: 1`): both calls `results` none, each with an
`already active` warning or the `RoleAssignmentExists` error. When 2.2 ended in the give-up
(`Active Azure roles before: 0`): call 2 `results` none, with an `already active` warning or the
`RoleAssignmentExists` error.
**Record:** for each call the seconds after 2.2's `pim`, how long it took, the count of new requests
and the outcome -- in the give-up case, call 1's outcome tells how long after the deactivation Azure
accepted a new activation (or that it still refused).
**Failure looks like:** two activations accepted in 2.2 and 2.3 together, or a result in a call
while Reader was already active -- STOP (G8, SECURITY 4). An error other than `RoleAssignmentExists`
-- record it.

Result:
### 2.4. `unpim` after five minutes, and nothing left active in Azure

- [ ] **2.4** Window B. Five minutes after the activation of 2.2 or 2.3, `unpim -TenantAlias s25-az` deactivates Reader, and Azure then lists nothing active.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s25/TenantMap.psd1'
$Wait = 320 - ([datetime]::UtcNow - $global:OpimS25Az2).TotalSeconds
if ($Wait -gt 0) { Start-Sleep -Seconds ([int][math]::Ceiling($Wait)) }
$Off = @(Disable-OPIMMyRole -TenantAlias 's25-az' -TenantMapPath $Map 2>&1 3>&1)
"unpim s25-az: results $(@($Off | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' } | ForEach-Object { '{0} {1}' -f $_.DisplayName, $_.Status }) -join '; '); errors $(@($Off | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', ')"
$Gone = [datetime]::UtcNow
$Settled = $false
while (([datetime]::UtcNow - $Gone).TotalSeconds -lt 300 -and -not $Settled) {
    Start-Sleep -Seconds 15
    $Settled = @(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count -eq 0
}
"Azure list settled after $([int]([datetime]::UtcNow - $Gone).TotalSeconds) s: $Settled"
```

**Expect:** `unpim s25-az: results Reader Revoked` and no error (`results` none when 2.2 and 2.3
activated nothing); `Azure list settled after ... s: True`.
**Failure looks like:** `ActiveDurationTooShort` -- run the block again after a minute. `False` --
record it, and deactivate before the teardown.

Result:

### 3. A group deactivated twice within seconds (OPIM-50)

### 3.1. The group membership is activated

- [ ] **3.1** Window B. `Enable-OPIMEntraIDGroup 'opim-s2-grp'` with a justification activates the membership, and it is then listed as active.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$global:OpimS25Grp = [datetime]::UtcNow
$On = @(Enable-OPIMEntraIDGroup 'opim-s2-grp' -Justification 'Omnicit.PIM step 5 live check 3.1' 2>&1 3>&1)
"Activation: status $(@($On | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.GroupAssignmentScheduleRequest' } | ForEach-Object status) -join ','); errors $(@($On | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', ')"
$Listed = $null
while (([datetime]::UtcNow - $global:OpimS25Grp).TotalSeconds -lt 180 -and -not $Listed) {
    Start-Sleep -Seconds 5
    if (@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s2-grp' }).Count -ge 1) { $Listed = [int]([datetime]::UtcNow - $global:OpimS25Grp).TotalSeconds }
}
"Listed as active after (seconds): $Listed"
```

**Expect:** `Activation: status Provisioned` (or `Granted`) and no error; a number of seconds below 180.
**Failure looks like:** an error or no listing -- record it, and do not run 3.2 to 3.4.

Result:

### 3.2. A deactivation inside the first five minutes is `ActiveDurationTooShort`

- [ ] **3.2** Window B. Straight after 3.1, `Disable-OPIMEntraIDGroup 'opim-s2-grp'` is refused for the five-minute rule, reported as `ActiveDurationTooShort` -- never as `ActiveRoleNotFound` -- and the membership stays active.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Caught = $null
$Out = @(Disable-OPIMEntraIDGroup 'opim-s2-grp' -ErrorVariable Caught -ErrorAction SilentlyContinue)
$Written = @($Caught | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like '*,Disable-OPIMEntraIDGroup' })
"$([int]([datetime]::UtcNow - $global:OpimS25Grp).TotalSeconds) s after the activation: output $($Out.Count); written by the cmdlet: $(@($Written | ForEach-Object FullyQualifiedErrorId) -join ', ')"
"Every record in -ErrorVariable: $(@($Caught | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.FullyQualifiedErrorId } else { $_.GetType().Name } }) -join ', ')"
"Membership still listed as active: $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s2-grp' }).Count)"
```

**Expect:** `output 0`; written by the cmdlet `ActiveDurationTooShort,Disable-OPIMEntraIDGroup`;
`Membership still listed as active: 1`.
**Record:** every record in `-ErrorVariable` -- the Graph code of a deactivation inside the first five
minutes.
**Failure looks like:** `ActiveRoleNotFound,Disable-OPIMEntraIDGroup` while the membership is still
active -- the OPIM-50 mapping calls an active membership not active: a defect within this step's
scope (G11); narrow the mapping before anything else runs.

Result:

### 3.3. Two deactivations within seconds

- [ ] **3.3** Window B. Five minutes after 3.1, `Disable-OPIMEntraIDGroup 'opim-s2-grp'` deactivates the membership, and a second call straight after it is a non-terminating `ActiveRoleNotFound`.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Wait = 320 - ([datetime]::UtcNow - $global:OpimS25Grp).TotalSeconds
if ($Wait -gt 0) { Start-Sleep -Seconds ([int][math]::Ceiling($Wait)) }
$global:OpimS25GrpOff = [datetime]::UtcNow
foreach ($Try in 1, 2) {
    $Caught = $null
    $Reached = $false
    try { $Out = @(Disable-OPIMEntraIDGroup 'opim-s2-grp' -ErrorVariable Caught -ErrorAction SilentlyContinue); $Reached = $true } catch { $Out = @(); $Caught = @($Caught) + $PSItem }
    $Written = @($Caught | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like '*,Disable-OPIMEntraIDGroup' })
    $Graph = @($Caught | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -notlike '*,Disable-OPIMEntraIDGroup' -and $_.FullyQualifiedErrorId -notlike '*,Resolve-OPIMSchedule' })
    "Call $Try, $([int]([datetime]::UtcNow - $global:OpimS25GrpOff).TotalSeconds) s after the first: output $($Out.Count) status $(@($Out.status) -join ','); written by the cmdlet: $(@($Written | ForEach-Object FullyQualifiedErrorId) -join ', '); non-terminating: $Reached"
    "  Graph records under it: $(@($Graph | ForEach-Object FullyQualifiedErrorId) -join ', '); the message says Graph reports it does not exist: $(@($Written | Where-Object { $_.Exception.Message -match 'reports that it does not exist' }).Count -gt 0); says eligible but not active: $(@($Written | Where-Object { $_.Exception.Message -match 'eligible but not active' }).Count -gt 0)"
}
```

**Expect:** `Call 1`: `output 1 status Revoked`, nothing written by the cmdlet; `Call 2` within 30
seconds: `output 0`, written by the cmdlet `ActiveRoleNotFound,Disable-OPIMEntraIDGroup`,
`non-terminating: True`, and one of the two message lines `True`.
**Record:** the Graph records under call 2 (the code Graph gives when the list still showed the
membership; none when the list had caught up and nothing was sent), and which message it was.
**Failure looks like:** `BadRequest,Disable-OPIMEntraIDGroup` (or another code) on call 2 with a Graph
record of that code -- the code Graph gives today is not the one mapped (R-50a): record its message;
a G11 round adds a narrow match. `ActiveDurationTooShort` on call 1 -- the five minutes were not
waited out: run the block again after a minute.

Result:

### 3.4. Once the list has caught up, a deactivation sends nothing (G8)

- [ ] **3.4** Window B. When the list no longer shows the membership, `Disable-OPIMEntraIDGroup 'opim-s2-grp'` is `ActiveRoleNotFound` from the name resolution, with no Graph record under it, and nothing is active.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Settled = $false
while (([datetime]::UtcNow - $global:OpimS25GrpOff).TotalSeconds -lt 300 -and -not $Settled) {
    $Settled = @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s2-grp' }).Count -eq 0
    if (-not $Settled) { Start-Sleep -Seconds 10 }
}
"Group list settled $([int]([datetime]::UtcNow - $global:OpimS25GrpOff).TotalSeconds) s after the deactivation: $Settled"
$Caught = $null
$Out = @(Disable-OPIMEntraIDGroup 'opim-s2-grp' -ErrorVariable Caught -ErrorAction SilentlyContinue)
$Written = @($Caught | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like '*,Disable-OPIMEntraIDGroup' })
"Deactivation: output $($Out.Count); written by the cmdlet: $(@($Written | ForEach-Object FullyQualifiedErrorId) -join ', '); says eligible but not active: $(@($Written | Where-Object { $_.Exception.Message -match 'eligible but not active' }).Count -gt 0); Graph records: $(@($Caught | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -match 'Invoke-OPIMGraphRequest' }).Count)"
"Active: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** `settled ... s after the deactivation: True`; `output 0`, written by the cmdlet
`ActiveRoleNotFound,Disable-OPIMEntraIDGroup`, `says eligible but not active: True`, `Graph records:
0`; `Active: directory 0, group 0, Azure 0`.
**Failure looks like:** a Graph record -- a request was sent for a membership the list no longer
shows: record it. Something active -- deactivate it (after five minutes) before section 4.

Result:

### 4. The fixture's teardown (decision A10, scope 7)

### 4.1. Window B signs out

- [ ] **4.1** Window B. Nothing is active, the window's session is cleared, no Az module is loaded, and the window ends.

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

Result:

### 4.2. The teardown planned with `-WhatIf`

- [ ] **4.2** Window A, as `oer-live-cc`. `Initialize-OpimS2Prereq.ps1 -Teardown -WhatIf` lists what it would remove, every target carries the prefix `opim-s2`, except the one named membership, and nothing is removed.

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

Result:

### 4.3. The teardown

- [ ] **4.3** Window A, as `oer-live-cc`. `Initialize-OpimS2Prereq.ps1 -Teardown -Unattended` removes the membership, the Azure eligibilities, the resource groups, the group, the directory role eligibilities, the user and the two secrets, in that order.

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
once replication has caught up (a second run is idempotent). Anything left after a second run is a
residue line for the report (G11 #5 if an object cannot be removed at all).

Result:

### 4.4. The sweep after the teardown

- [ ] **4.4** Window A, as `oer-live-cc`. No object and no resource group carries the prefix `opim-s2-`, no object carries `opim-s25-`, and the vault holds no secret of the fixture.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'opim-s2-'
Connect-OerLive -Graph
"Objects with the prefix opim-s2-: $(@(Find-OerLivePrefixed -Prefix 'opim-s2-' -ThrowOnUnread -Quiet).Count)"
"Objects with the prefix opim-s25-: $(@(Find-OerLivePrefixed -Prefix 'opim-s25-' -ThrowOnUnread -Quiet).Count)"
Connect-OerLive -Arm
$Rgs = Invoke-OerLiveArm -All -Path ("/subscriptions/{0}/resourcegroups?api-version=2021-04-01" -f $Cfg.SubscriptionId)
$null = Assert-OerLiveOk -Response $Rgs -Activity 'Listing the resource groups'
"Resource groups with the prefix opim-s2-: $(@(@($Rgs.Body.value) | Where-Object { ([string]$_.name).StartsWith('opim-s2-', [System.StringComparison]::OrdinalIgnoreCase) }).Count)"
Disconnect-OerLive
Import-Module -Name Microsoft.PowerShell.SecretManagement -ErrorAction Stop
"Secrets of the fixture in the vault OpimLive: $(@(Get-SecretInfo -Vault OpimLive -Name 'opim-s2-*' -ErrorAction SilentlyContinue).Count)"
"Residue rows of this sprint in raw\residue.json: $(@(Read-OerLiveResidue | Where-Object { ([string]$_['prefix']).StartsWith('opim-s2', [System.StringComparison]::OrdinalIgnoreCase) }).Count)"
```

**Expect:** `Objects with the prefix opim-s2-: 0`; `Objects with the prefix opim-s25-: 0`; `Resource
groups with the prefix opim-s2-: 0`; `Secrets of the fixture in the vault OpimLive: 0`; `Residue rows of
this sprint in raw\residue.json: 0`.
**Failure looks like:** a count above 0 -- run 4.3 again after replication; anything left after that
is a line in the report (G11 #5 if it cannot be removed). A 401 or 403 -- STOP (G6).

Result:

## Teardown

Section 4 removed the fixture. The check below verifies the local side: the raw folder with the
tenant map is gone, and no untracked file is left under `docs/live-verification`. Nothing is left in
the tenant on purpose; the test user lies in the directory's deleted items for 30 days.

### T.1. The raw folder

- [ ] **T.1** Window A, after window B has ended. The raw folder, with the tenant map, is deleted once the results are written up, and nothing untracked is left.

```powershell
Remove-Item -LiteralPath 'docs/live-verification/raw/opim-s25' -Recurse -Force
"Raw folder gone: $(-not (Test-Path -LiteralPath 'docs/live-verification/raw/opim-s25'))"
"Untracked files under docs/live-verification: $(@(git status --porcelain --untracked-files=all -- docs/live-verification | Where-Object { $_.StartsWith('??') }).Count)"
```

**Expect:** `Raw folder gone: True`; `Untracked files under docs/live-verification: 0`.
**Failure looks like:** `False` or an untracked file -- remove it before the results are committed.

Result:
