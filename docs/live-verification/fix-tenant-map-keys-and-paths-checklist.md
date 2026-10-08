# Live verification checklist -- a tenant map acts on a directory role only at its configured scope, stores an active Azure role by its eligibility, and the sprint's fixture is torn down (fix/tenant-map-keys-and-paths)

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
to nothing outside the prefixes `opim-s1-` (the sprint's fixture, which section 4 tears down) and
`opim-s15b-` (this step's own objects, of which there are none), with one named exception: check 4.2
takes the test user out of the group `Exclude from CA` and removes its assignment to the Microsoft
Graph Command Line Tools application, the two tenant changes the operator made for the test user in
step 2 (P-8), before the user is deleted. Check 0.1 proves the identity before any other check calls
the module. If a browser window or a sign-in prompt appears mid-run, STOP and run check 0.1 again:
in this file every sign-in is a device code, and the proof of 0.1 holds only for the sign-in it
checked.

**Two windows, never one process** (decision A10). Window A runs as `oer-live-cc`; window B runs the
module as the test user. The Microsoft Graph SDK holds one session per process, so the two never
share one. Every block below names its window.

**The tenant map of this run lives in the step's raw folder**,
`docs/live-verification/raw/opim-s15b/TenantMap.psd1` (git-ignored), never in the user's profile.
Every module call that reads a map passes `-TenantMapPath`.

**No block prints a scope id, an object id, a tenant id or a message that holds one.** The blocks
print counts, statuses, error ids, display names of the fixture's roles and groups, seconds and
True/False.

## What changed and why this needs a live tenant

- **A. A directory role is acted on only at the scope its entry names** ("fix: keep a configured
  directory role on its own scope", OPIM-10, decision A13). `Install-OPIMConfiguration` stores a
  directory role as `roleDefinitionId|directoryScopeId`; `pim` and `unpim` match that key exactly,
  and an entry from before (the role id alone) means the role at `/` only. A mock cannot show that
  a real Graph post's `roleDefinitionId` and `directoryScopeId` build the key that `pim` then finds,
  nor that an entry naming another scope activates nothing in a real tenant.
- **B. An active Azure role is stored by the eligibility it was activated from, with its own scope**
  ("fix: store an active Azure role by the eligibility it was activated from", "fix: store an active
  Azure role with its own scope and match it only there", OPIM-22). `pim` then activates it only while
  that eligibility is at that scope. The shape of ARM's `LinkedRoleEligibilityScheduleId` on a real
  instance (a bare name, as Microsoft's reference sample shows, or a full id) is measured here.
- **C. The configuration commands take the tenant only from the module's own sign-in** ("fix: take
  the tenant of a new alias only from the module's own sign-in", OPIM-45), **keep the tenant of a
  string-form alias** (OPIM-20), and **write a file that reads back an apostrophe** (OPIM-26). These
  touch only the map file; 1.1, 1.5 and 1.6 show them against the real session.
- **D. The sprint's fixture is torn down** (step 5b, scope 9 and 10): the prerequisite script's
  `-Teardown`, the two secrets in the vault, and the operator's two tenant changes for the test user
  (P-8).

The fixture of step 2 is used as it stands until section 4 removes it: the test user
`opim-s1-live-user`, the group `opim-s1-grp` (eligible as member and as owner), the resource groups
`opim-s1-rg` and `opim-s1-rg2` (Reader eligible on each), and the directory roles Usage Summary
Reports Reader and Message Center Privacy Reader at the directory scope. The test user's ownership
of `opim-s1-grp`, activated in step 4, cannot be deactivated while the test user is the group's only
owner (decision A18, OPIM-49); it ends when section 4 deletes the group, before the user.

## What this file does not check, and why

Class B, each proven by the unit tests named:

- **A role eligible at an administrative unit**, matched by its own key and not by the root key, and
  an old entry that does not reach it -- the fixture has no administrative unit.
  `tests/Unit/Public/Enable-OPIMMyRole.Tests.ps1` and `Disable-OPIMMyRole.Tests.ps1` (OPIM-10, A13),
  `tests/Unit/Private/ConvertTo-OPIMTenantMapKey.Tests.ps1`. Check 1.2 shows the safe half live: an
  entry naming another scope activates nothing.
- **An administrative unit the user may not read** (OPIM-19) -- the fixture has none.
  `tests/Unit/Public/Get-OPIMDirectoryRole.Tests.ps1`.
- **The default `-TenantMapPath` under `$HOME`** (OPIM-21) -- this file never touches the user's
  profile. The tests in the seven cmdlets' test files run on Windows, Linux and macOS in CI.
- **An active Azure role that names no eligibility, or one activated at a reduced scope** (refused
  with `LinkedEligibilityNotFound`, or stored with a scope no eligibility has, which activates
  nothing) -- the module activates only at the eligibility's own scope, and the fixture has no
  narrower scope to activate at. `tests/Unit/Private/ConvertTo-OPIMTenantMapKey.Tests.ps1`,
  `tests/Unit/Public/Enable-OPIMMyRole.Tests.ps1` and `Disable-OPIMMyRole.Tests.ps1`.
- **`Install-OPIMConfiguration` after another `Connect-MgGraph`, or with no sign-in at all**
  (OPIM-45) -- `tests/Unit/Private/Get-OPIMCurrentTenantInfo.Tests.ps1` and
  `tests/Unit/Public/Install-OPIMConfiguration.Tests.ps1`.
- **`Wait-OPIMDirectoryRole`'s expired request** (`ActivationAlreadyExpired`) --
  `tests/Unit/Public/Wait-OPIMDirectoryRole.Tests.ps1`.

## Setup, once

The operator sets `OPIMLIVE_HOME` in both windows to the notes folder that holds the `OpimLive`
folder; no checklist holds that path. The test user's sign-in name and the test tenant's id are read
by the harness through OerLive and are never printed. Window B runs from the root of the step's
worktree, and its console output also goes to the file named in `OPIMLIVE_HOSTLOG`, where
`Connect-AzAccount` writes the Azure device code (OpimLive 1.0.2). Raw output and the run's tenant
map go to `docs/live-verification/raw/opim-s15b` (git-ignored), which is deleted once the results
are written up. This step creates no object of its own, so it has no prerequisite script; the
sprint's prerequisite script `Initialize-OpimS1Prereq.ps1` tears the fixture down in section 4.

### S.1. Find the build under test and tie it to the branch head

- [ ] **S.1** Window B. The newest build in `output/module/Omnicit.PIM/` was made after the branch head was committed, and it holds this step's key helper.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$HeadTime = [datetimeoffset]::Parse((git log -1 --format=%cI))
$Psm1 = Join-Path $Built.DirectoryName 'Omnicit.PIM.psm1'
"Branch head: $(git log -1 --format='%h %s')"
"Built version folder: $($Built.Directory.Name)"
"Built after the branch head was committed: $([datetimeoffset]$Built.LastWriteTime -gt $HeadTime)"
"Tracked changes in the working tree: $(@(git status --porcelain --untracked-files=no).Count)"
"The built module holds the tenant map key helper: $([bool](Select-String -LiteralPath $Psm1 -Pattern 'function ConvertTo-OPIMTenantMapKey' -SimpleMatch -Quiet))"
```

**Expect:** the branch head's hash and subject; the version folder; every True/False line `True`;
`Tracked changes in the working tree: 0`.
**Failure looks like:** `False`, or a tracked change -- build again before any check below.

Result:

### S.2. The harness loads

- [ ] **S.2** Window B. OerLive is 1.0.3, the harness reads the test values through it, and the TOTP implementation reproduces RFC 6238.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME 'OpimLive/OpimLive.psm1') -Force
$Target = Get-OpimLiveTarget
"OerLive version: $((Get-OerLiveState).Version)"
"Test user and tenant read (values hidden): $([bool]$Target.UserPrincipalName -and [bool]$Target.TenantId)"
"TOTP self-test: $(Get-OpimLiveTotp -SelfTest)"
"Host log set and present: $([bool]$env:OPIMLIVE_HOSTLOG -and (Test-Path -LiteralPath $env:OPIMLIVE_HOSTLOG))"
```

**Expect:** `OerLive version: 1.0.3`; the three other lines `True`.
**Failure looks like:** `False` on the self-test -- STOP: the harness would enter wrong codes. `False`
on the host log -- the Azure code cannot be completed; set it before 0.1.

Result:

### S.3. The fixture is in place, and this step has no object of its own

- [ ] **S.3** Window A, as `oer-live-cc`. The fixture's user and group exist, and no object carries the prefix `opim-s15b-`.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$null = Import-OerLiveConfig -Prefix 'opim-s15b-'
Connect-OerLive -Graph
"Objects with the prefix opim-s15b-: $(@(Find-OerLivePrefixed -Prefix 'opim-s15b-' -ThrowOnUnread -Quiet).Count)"
"Objects with the prefix opim-s1- (the fixture): $(@(Find-OerLivePrefixed -Prefix 'opim-s1-' -ThrowOnUnread -Quiet).Count)"
Disconnect-OerLive
```

**Expect:** every identity check line of `oer-live-cc` `True`; `opim-s15b-: 0`; `opim-s1-: 2` (the
user and the group; the resource groups are not directory objects).
**Failure looks like:** a 401 or 403 -- STOP (G6). Another count -- record each object by name and
STOP: the fixture is not the one this file assumes. A throw on an unread collection is a failed read,
never a `0`.

Result:

### S.4. The run's tenant map folder

- [ ] **S.4** Window B. The run's tenant map goes to the step's raw folder, which git ignores, and not to the user's profile.

```powershell
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s15b/TenantMap.psd1'
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Map)
git check-ignore -q (Split-Path -Parent $Map)
"The map's folder is git-ignored: $($LASTEXITCODE -eq 0)"
"A map file is there already: $(Test-Path -LiteralPath $Map)"
"The map is under the profile's .config folder: $($Map.StartsWith((Join-Path $HOME '.config'), [System.StringComparison]::OrdinalIgnoreCase))"
```

**Expect:** `True`, `False`, `False`.
**Failure looks like:** `False` on the first line -- STOP: the map would be tracked. `True` on the
second -- a map from an earlier run; delete it, it belongs to this folder only.

Result:

### 0. Preparation

### 0.1. Identity check, Graph and Azure

- [ ] **0.1** Window B. `Connect-OpimLiveUser -IncludeARM` signs the module in to Graph and Azure with one device code each; the account is the test user and the tenant the test tenant.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
Import-Module (Join-Path $env:OPIMLIVE_HOME 'OpimLive/OpimLive.psm1') -Force
$Target = Get-OpimLiveTarget
$Sign = Connect-OpimLiveUser -IncludeARM -RawFolder 'docs/live-verification/raw/opim-s15b'
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
$State = & (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }
"Session tenant is the test tenant: $([string]::Equals([string]$State.TokenTenantId, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
"Az context is the test tenant: $([string]::Equals([string](Get-AzContext).Tenant.Id, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
```

**Expect:** `Disconnect-OPIM, Disconnect-MgGraph and Disconnect-AzAccount ran first`; the rows
`Graph Information True ok` and `Azure Host False ok`; every True/False line `True`. The block
prints neither the account nor the tenant id.
**Failure looks like:** `False` on any line, or a `STOP` -- STOP: run `Disconnect-OPIM`, end window B
and run no other check.

Result:

### 0.2. What is eligible and what is active

- [ ] **0.2** Window B. The fixture's eligibilities are listed, and nothing is active but the ownership from step 4.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
"Eligible: directory $(@(Get-OPIMDirectoryRole -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -ErrorAction Stop).Count)"
$ActiveGroups = @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop)
"Active: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $($ActiveGroups.Count) ($((@($ActiveGroups | ForEach-Object { "$($_.group.displayName) $($_.accessId)" })) -join ', ')), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** `Eligible: directory 2, group 2, Azure 2`; `Active: directory 0, group 1 (opim-s1-grp
owner), Azure 0`.
**Record:** the active group line, if it is not the ownership alone.
**Failure looks like:** another eligible count -- STOP: the fixture is not the one this file
assumes. A directory role or an Azure role already active -- record it; the checks below count
before and after. A terminating error from a read is a failed read, never a `0`.

Result:

### 1. A directory role is acted on only at its configured scope (OPIM-10)

### 1.1. `Install-OPIMConfiguration` stores the role with its scope, and the tenant of the module's own sign-in

- [ ] **1.1** Window B. One role piped from `Get-OPIMDirectoryRole` is stored as `roleDefinitionId|/`, under the tenant of the module's sign-in, without `-TenantId`.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s15b/TenantMap.psd1'
$Target = Get-OpimLiveTarget
$Role = @(Get-OPIMDirectoryRole -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq 'Usage Summary Reports Reader' })
if ($Role.Count -ne 1) { throw "Expected one eligible Usage Summary Reports Reader, found $($Role.Count)." }
$Role | Install-OPIMConfiguration -TenantAlias 's15b-dir' -TenantMapPath $Map -Confirm:$false
$Entry = (Import-PowerShellDataFile -LiteralPath $Map)['s15b-dir']
"Stored directory entries: $(@($Entry.DirectoryRoles).Count)"
"The entry is the role id and the root scope: $(@($Entry.DirectoryRoles)[0] -ceq "$($Role[0].roleDefinitionId)|/")"
"The alias's tenant is the tenant of the module's sign-in: $([string]::Equals([string]$Entry.TenantId, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
```

**Expect:** `Stored directory entries: 1`; both True/False lines `True`.
**Failure looks like:** the `throw` -- the fixture is not as 0.2 found it. `False` on the entry -- the
key is not `roleDefinitionId|/` (A13). `False` on the tenant -- OPIM-45 is not as built.

Result:

### 1.2. An entry for the role at another scope activates nothing

- [ ] **1.2** Window B. An entry naming the role at an administrative unit the user is not eligible at makes `pim` activate no directory role, although the role is eligible at `/`.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s15b/TenantMap.psd1'
$Role = @(Get-OPIMDirectoryRole -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq 'Usage Summary Reports Reader' })
if ($Role.Count -ne 1) { throw "Expected one eligible Usage Summary Reports Reader, found $($Role.Count)." }
$AtUnit = [PSCustomObject]@{ roleDefinitionId = $Role[0].roleDefinitionId; directoryScopeId = '/administrativeUnits/00000000-0000-0000-0000-000000000001' }
$AtUnit.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
$AtUnit | Install-OPIMConfiguration -TenantAlias 's15b-au' -TenantMapPath $Map -Confirm:$false
$Before = @(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count
$Out = @(Enable-OPIMMyRole -TenantAlias 's15b-au' -TenantMapPath $Map -ErrorVariable Errs -WarningVariable Warns -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
Start-Sleep -Seconds 15
$After = @(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count
"pim results: $($Out.Count); errors: $($Errs.Count); warnings: $($Warns.Count)"
"Active directory roles before: $Before; after: $After"
```

**Expect:** `pim results: 0; errors: 0; warnings: 0`; `Active directory roles before: 0; after: 0`.
Version 0.5.1 stored this entry as the role id alone and activated the role at `/` (OPIM-10).
**Failure looks like:** `after` above `before`, or a result -- STOP: `pim` activated a scope the entry
does not name (G3, SECURITY 4). A terminating error from a count read is a failed read, never a pass.

Result:

### 1.3. `pim` activates exactly the configured role, and a second call sends nothing (G8)

- [ ] **1.3** Window B. `pim -TenantAlias s15b-dir` activates Usage Summary Reports Reader at `/` and nothing else; the same call again sends no request.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s15b/TenantMap.psd1'
$Out1 = @(Enable-OPIMMyRole -TenantAlias 's15b-dir' -TenantMapPath $Map -ErrorVariable Errs1 -WarningVariable Warns1 -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
$global:S15bLastActivation = [datetime]::UtcNow
"First call: results $($Out1.Count) ($((@($Out1 | ForEach-Object { "$($_.DisplayName) $($_.Scope) $($_.Status)" })) -join '; ')); errors $($Errs1.Count); warnings $($Warns1.Count)"
Start-Sleep -Seconds 20
$Active = @(Get-OPIMDirectoryRole -Activated -ErrorAction Stop)
"Active: Usage Summary Reports Reader at the root $(@($Active | Where-Object { $_.roleDefinition.displayName -eq 'Usage Summary Reports Reader' -and $_.directoryScopeId -eq '/' }).Count); Message Center Privacy Reader $(@($Active | Where-Object { $_.roleDefinition.displayName -eq 'Message Center Privacy Reader' }).Count); all $($Active.Count)"
$Out2 = @(Enable-OPIMMyRole -TenantAlias 's15b-dir' -TenantMapPath $Map -ErrorVariable Errs2 -WarningVariable Warns2 -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
"Second call: results $($Out2.Count); errors $($Errs2.Count)$(if ($Errs2.Count) { ", last $($Errs2[-1].FullyQualifiedErrorId)" }); warning says already active: $([bool](@($Warns2 | Where-Object { "$_" -match 'is already active' })))"
```

**Expect:** first call `results 1 (Usage Summary Reports Reader Directory Provisioned); errors 0;
warnings 0`; `Active: ... at the root 1; Message Center Privacy Reader 0; all 1`; second call
`results 0; errors 0; warning says already active: True`.
**Failure looks like:** Message Center Privacy Reader active, or `all` above 1 -- STOP: more than the
entry names was activated. A second request on the second call (a result, or `RoleAssignmentExists`)
-- record it; the listing may lag (OPIM-50 class).

Result:

### 1.4. An entry written before 0.6.0 means the role at `/`

- [ ] **1.4** Window B. An alias written in the 0.5.x form, the role id alone, activates Message Center Privacy Reader at `/`; the same call again sends nothing.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s15b/TenantMap.psd1'
$Target = Get-OpimLiveTarget
$Role = @(Get-OPIMDirectoryRole -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq 'Message Center Privacy Reader' })
if ($Role.Count -ne 1) { throw "Expected one eligible Message Center Privacy Reader, found $($Role.Count)." }
$Lines = [System.Collections.Generic.List[string]]::new([string[]](Get-Content -LiteralPath $Map))
$Lines.Insert($Lines.LastIndexOf('}'), "    's15b-old' = @{ TenantId = '$($Target.TenantId)'; DirectoryRoles = @('$($Role[0].roleDefinitionId)') }")
Set-Content -LiteralPath $Map -Value $Lines -Encoding utf8NoBOM
"The entry holds no scope: $(-not ([string]@((Import-PowerShellDataFile -LiteralPath $Map)['s15b-old'].DirectoryRoles)[0]).Contains('|'))"
$Out1 = @(Enable-OPIMMyRole -TenantAlias 's15b-old' -TenantMapPath $Map -ErrorVariable Errs1 -WarningVariable Warns1 -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
$global:S15bLastActivation = [datetime]::UtcNow
"First call: results $($Out1.Count) ($((@($Out1 | ForEach-Object { "$($_.DisplayName) $($_.Scope) $($_.Status)" })) -join '; ')); errors $($Errs1.Count); warnings $($Warns1.Count)"
Start-Sleep -Seconds 20
$Active = @(Get-OPIMDirectoryRole -Activated -ErrorAction Stop)
"Active: Message Center Privacy Reader at the root $(@($Active | Where-Object { $_.roleDefinition.displayName -eq 'Message Center Privacy Reader' -and $_.directoryScopeId -eq '/' }).Count); all $($Active.Count)"
$Out2 = @(Enable-OPIMMyRole -TenantAlias 's15b-old' -TenantMapPath $Map -ErrorVariable Errs2 -WarningVariable Warns2 -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
"Second call: results $($Out2.Count); errors $($Errs2.Count)$(if ($Errs2.Count) { ", last $($Errs2[-1].FullyQualifiedErrorId)" }); warning says already active: $([bool](@($Warns2 | Where-Object { "$_" -match 'is already active' })))"
```

**Expect:** `The entry holds no scope: True`; first call `results 1 (Message Center Privacy Reader
Directory Provisioned); errors 0; warnings 0`; `Active: Message Center Privacy Reader at the root 1;
all 2` (with 1.3's role); second call `results 0; errors 0; warning says already active: True`.
**Failure looks like:** `results 0` on the first call -- the old entry no longer reaches the role at
`/`, which A13 keeps. `all` above 2 -- STOP.

Result:

### 1.5. `Set-OPIMConfiguration` keeps the tenant of a string-form alias (OPIM-20)

- [ ] **1.5** Window B. An alias in the old string form keeps its tenant when a role is piped to `Set-OPIMConfiguration` without `-TenantId`.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s15b/TenantMap.psd1'
$Target = Get-OpimLiveTarget
$Lines = [System.Collections.Generic.List[string]]::new([string[]](Get-Content -LiteralPath $Map))
$Lines.Insert($Lines.LastIndexOf('}'), "    's15b-str' = '$($Target.TenantId)'")
Set-Content -LiteralPath $Map -Value $Lines -Encoding utf8NoBOM
Get-OPIMDirectoryRole -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq 'Usage Summary Reports Reader' } | Set-OPIMConfiguration -TenantAlias 's15b-str' -TenantMapPath $Map -Confirm:$false
$Entry = (Import-PowerShellDataFile -LiteralPath $Map)['s15b-str']
"The alias is now a table: $($Entry -is [hashtable])"
"Its tenant is kept: $([string]::Equals([string]$Entry.TenantId, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
"Stored directory entries: $(@($Entry.DirectoryRoles).Count); with the root scope: $(@($Entry.DirectoryRoles | Where-Object { $_.EndsWith('|/') }).Count)"
```

**Expect:** `True`, `True`, `Stored directory entries: 1; with the root scope: 1`.
**Failure looks like:** `Its tenant is kept: False` -- OPIM-20 is not fixed: a `pim -TenantAlias`
with that alias would sign in to `organizations`.

Result:

### 1.6. An apostrophe in an alias reads back (OPIM-26)

- [ ] **1.6** Window B. Aliases with a straight and a typographic apostrophe are written, and the whole file still reads back.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s15b/TenantMap.psd1'
$Target = Get-OpimLiveTarget
$Straight = "s15b-o'brien"
$Curly = 's15b-o' + [char]0x2019 + 'neil'
Install-OPIMConfiguration -TenantAlias $Straight -TenantId $Target.TenantId -TenantMapPath $Map -Confirm:$false
Install-OPIMConfiguration -TenantAlias $Curly -TenantId $Target.TenantId -TenantMapPath $Map -Confirm:$false
$Read = Import-PowerShellDataFile -LiteralPath $Map
"The file reads back: True; aliases: $($Read.Count)"
"Both apostrophe aliases are there: $($Read.ContainsKey($Straight) -and $Read.ContainsKey($Curly))"
"Get-OPIMConfiguration finds them: $(@(Get-OPIMConfiguration -TenantAlias $Straight -TenantMapPath $Map -ErrorAction Stop).Count + @(Get-OPIMConfiguration -TenantAlias $Curly -TenantMapPath $Map -ErrorAction Stop).Count)"
```

**Expect:** `The file reads back: True; aliases: 6`; `True`; `Get-OPIMConfiguration finds them: 2`.
**Failure looks like:** a parse error from `Import-PowerShellDataFile` -- OPIM-26 is not fixed, and
every later check that reads the map fails too: remove the two lines by hand before going on.

Result:

### 2. Groups and Azure roles from the tenant map

### 2.1. Group membership and ownership by their keys, twice (G8)

- [ ] **2.1** Window B. The group's two eligibilities are stored as `groupId_member` and `groupId_owner`; `pim` activates the membership and sends nothing for the ownership that is already active; the same call again sends nothing.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s15b/TenantMap.psd1'
Get-OPIMEntraIDGroup -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' } | Install-OPIMConfiguration -TenantAlias 's15b-grp' -TenantMapPath $Map -Confirm:$false
$Keys = @((Import-PowerShellDataFile -LiteralPath $Map)['s15b-grp'].EntraIDGroups)
"Stored group entries: $($Keys.Count); member $(@($Keys | Where-Object { $_.EndsWith('_member') }).Count); owner $(@($Keys | Where-Object { $_.EndsWith('_owner') }).Count)"
$Out1 = @(Enable-OPIMMyRole -TenantAlias 's15b-grp' -TenantMapPath $Map -ErrorVariable Errs1 -WarningVariable Warns1 -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
$global:S15bLastActivation = [datetime]::UtcNow
"First call: results $($Out1.Count) ($((@($Out1 | ForEach-Object { "$($_.DisplayName) $($_.Scope) $($_.Status)" })) -join '; ')); errors $($Errs1.Count); warnings $($Warns1.Count) ($((@($Warns1 | ForEach-Object { if ("$_" -match 'is already active') { 'already active' } else { 'other' } })) -join ', '))"
Start-Sleep -Seconds 45
$Out2 = @(Enable-OPIMMyRole -TenantAlias 's15b-grp' -TenantMapPath $Map -ErrorVariable Errs2 -WarningVariable Warns2 -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
"Second call: results $($Out2.Count); errors $($Errs2.Count)$(if ($Errs2.Count) { ", last $($Errs2[-1].FullyQualifiedErrorId)" }); warnings saying already active: $(@($Warns2 | Where-Object { "$_" -match 'is already active' }).Count)"
$Active = @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' })
"Active for opim-s1-grp: member $(@($Active | Where-Object accessId -eq 'member').Count), owner $(@($Active | Where-Object accessId -eq 'owner').Count)"
```

**Expect:** `Stored group entries: 2; member 1; owner 1`; first call `results 1 (opim-s1-grp member
Provisioned); errors 0; warnings 1 (already active)`; second call `results 0; errors 0; warnings
saying already active: 2`; `Active for opim-s1-grp: member 1, owner 1`.
**Record:** the first call's warnings, if the ownership from step 4 is no longer active (0.2).
**Failure looks like:** a second request for the membership (a result or `RoleAssignmentExists` on
the second call) -- record it; the group listing lags about 30 s (OPIM-50), which the 45 s wait is
for.

Result:

### 2.2. An active Azure role is stored by its eligibility (OPIM-22)

- [ ] **2.2** Window B. Reader on `opim-s1-rg` is activated, piped from `Get-OPIMAzureRole -Activated` to `Install-OPIMConfiguration`, and stored as the name of its eligibility schedule with the role's own scope, not as the active instance.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s15b/TenantMap.psd1'
$Eligible = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg' })
if ($Eligible.Count -ne 1) { throw "Expected one eligible Reader on opim-s1-rg, found $($Eligible.Count)." }
$Request = @($Eligible | Enable-OPIMAzureRole -Hours 1 -ErrorAction Stop)
$global:S15bLastActivation = [datetime]::UtcNow
"Activation: $(@($Request | ForEach-Object Status) -join ', ')"
$Active = @()
foreach ($Try in 1..12) {
    $Active = @(Get-OPIMAzureRole -Activated -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg' })
    if ($Active.Count -ge 1) { break }
    Start-Sleep -Seconds 10
}
"Active Reader on opim-s1-rg listed: $($Active.Count) after $Try read(s)"
$Active | Install-OPIMConfiguration -TenantAlias 's15b-az' -TenantMapPath $Map -Confirm:$false -ErrorVariable Errs -ErrorAction SilentlyContinue
$Link = [string]$Active[0].LinkedRoleEligibilityScheduleId
"The instance's link is a bare name: $($Link -notmatch '/'); it holds the role's scope: $($Link.StartsWith([string]$Active[0].ScopeId + '/', [System.StringComparison]::OrdinalIgnoreCase))"
$Keys = @((Import-PowerShellDataFile -LiteralPath $Map)['s15b-az'].AzureRoles)
"Stored Azure entries: $($Keys.Count); errors: $($Errs.Count)"
"The entry is the eligibility's name and the role's scope: $($Keys.Count -eq 1 -and [string]::Equals($Keys[0], "$($Eligible[0].Name)|$($Eligible[0].ScopeId)", [System.StringComparison]::OrdinalIgnoreCase))"
"The entry names the active instance: $($Keys.Count -eq 1 -and $Keys[0].StartsWith([string]$Active[0].Name, [System.StringComparison]::OrdinalIgnoreCase))"
```

**Expect:** `Activation: Provisioned`; the active line `1`; **Record:** the link's shape (a bare name,
or a full id that holds the role's scope); `Stored Azure entries: 1; errors: 0`; `The entry is the
eligibility's name and the role's scope: True`; `The entry names the active instance: False`.
**Failure looks like:** `LinkedEligibilityNotFound` in the errors -- the real instance names no
eligibility, or names it at another scope: record it. `The entry is the eligibility's name and the
role's scope: False` -- OPIM-22 is not fixed for the shape ARM returns.

Result:

### 2.3. `pim` finds the stored Azure role

- [ ] **2.3** Window B. `pim -TenantAlias s15b-az` selects Reader on `opim-s1-rg` (and not on `opim-s1-rg2`) and, since it is active, sends nothing for it.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s15b/TenantMap.psd1'
$Out = @(Enable-OPIMMyRole -TenantAlias 's15b-az' -TenantMapPath $Map -ErrorVariable Errs -WarningVariable Warns -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
"pim results: $($Out.Count); errors: $($Errs.Count)$(if ($Errs.Count) { ", last $($Errs[-1].FullyQualifiedErrorId)" })"
"Warning names Reader on opim-s1-rg as already active: $([bool](@($Warns | Where-Object { "$_" -match 'Reader -> opim-s1-rg is already active' })))"
"Warning names opim-s1-rg2: $([bool](@($Warns | Where-Object { "$_" -match 'opim-s1-rg2' })))"
$Active = @(Get-OPIMAzureRole -Activated -ErrorAction Stop)
"Active Azure roles: $($Active.Count) ($((@($Active | ForEach-Object { "$($_.RoleDefinitionDisplayName) $($_.ScopeDisplayName)" })) -join '; '))"
```

**Expect:** `pim results: 0; errors: 0`; `Warning names Reader on opim-s1-rg as already active: True`;
`Warning names opim-s1-rg2: False`; `Active Azure roles: 1 (Reader opim-s1-rg)`. Before the fix the
stored instance name matched no eligible role, and `pim` wrote only a verbose "no eligible Azure
roles matched".
**Failure looks like:** no warning and no result -- the stored key matched nothing. A result for
`opim-s1-rg2`, or two active Azure roles -- STOP.

Result:

### 3. `unpim` deactivates exactly what the map names

### 3.1. The five-minute rule

- [ ] **3.1** Window B. Five minutes have passed since the last activation before any deactivation below.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
if (-not $global:S15bLastActivation) { throw 'No activation time is recorded in this window; run the activating checks in this window first.' }
$Latest = $global:S15bLastActivation
$Wait = [math]::Max(0, [math]::Ceiling(($Latest.AddMinutes(5.5) - [datetime]::UtcNow).TotalSeconds))
"Waiting $Wait s after the last activation this window sent"
Start-Sleep -Seconds $Wait
"Five and a half minutes after the last activation: $(([datetime]::UtcNow - $Latest).TotalMinutes -ge 5.5) at $([datetime]::UtcNow.ToString('HH:mm:ss')) UTC"
```

**Expect:** `True`.
**Failure looks like:** `False` -- run the block again.

Result:

### 3.2. `unpim` for the scoped and the old directory entries, twice (G8)

- [ ] **3.2** Window B. `unpim -TenantAlias s15b-dir` deactivates Usage Summary Reports Reader only, `unpim -TenantAlias s15b-old` Message Center Privacy Reader only; each again finds nothing to do.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s15b/TenantMap.psd1'
foreach ($Alias in 's15b-dir', 's15b-old') {
    $Out1 = @(Disable-OPIMMyRole -TenantAlias $Alias -TenantMapPath $Map -ErrorVariable Errs1 -ErrorAction SilentlyContinue)
    "$Alias first call: results $($Out1.Count) ($((@($Out1 | ForEach-Object { "$($_.DisplayName) $($_.Scope) $($_.Status)" })) -join '; ')); errors $($Errs1.Count)"
    Start-Sleep -Seconds 20
    "$Alias active after it: $((@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop | ForEach-Object { $_.roleDefinition.displayName })) -join ', ')"
    $Out2 = @(Disable-OPIMMyRole -TenantAlias $Alias -TenantMapPath $Map -ErrorVariable Errs2 -ErrorAction SilentlyContinue)
    "$Alias second call: results $($Out2.Count); errors $($Errs2.Count)$(if ($Errs2.Count) { ", last $($Errs2[-1].FullyQualifiedErrorId)" })"
}
```

**Expect:** `s15b-dir first call: results 1 (Usage Summary Reports Reader Directory Revoked); errors
0`; active after it: `Message Center Privacy Reader`; second call `results 0; errors 0`. Then
`s15b-old first call: results 1 (Message Center Privacy Reader Directory Revoked); errors 0`; active
after it: empty; second call `results 0; errors 0`.
**Failure looks like:** the first `unpim` deactivating both roles -- STOP: more than the entry names.
`ActiveDurationTooShort` -- 3.1 was not waited out; wait and run again.

Result:

### 3.3. `unpim` for the group

- [ ] **3.3** Window B. `unpim -TenantAlias s15b-grp` deactivates the membership; the ownership is refused as the group's last owner (OPIM-49).

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s15b/TenantMap.psd1'
$Out = @(Disable-OPIMMyRole -TenantAlias 's15b-grp' -TenantMapPath $Map -ErrorVariable Errs -ErrorAction SilentlyContinue)
"Results: $($Out.Count) ($((@($Out | ForEach-Object { "$($_.DisplayName) $($_.Scope) $($_.Status)" })) -join '; '))"
"Errors: $($Errs.Count); ids: $((@($Errs | ForEach-Object { ($_.FullyQualifiedErrorId -split ',')[0] } | Sort-Object -Unique)) -join ', ')"
Start-Sleep -Seconds 45
$Active = @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' })
"Active for opim-s1-grp: member $(@($Active | Where-Object accessId -eq 'member').Count), owner $(@($Active | Where-Object accessId -eq 'owner').Count)"
```

**Expect:** `Results: 1 (opim-s1-grp member Revoked)`; errors naming `CannotDeleteLastAdminAssignment`;
`Active for opim-s1-grp: member 0, owner 1`.
**Record:** the error ids exactly as they come.
**Failure looks like:** the membership still active after 45 s -- record it, and read again later
(OPIM-50).

Result:

### 3.4. `unpim` and `pim` for the stored Azure role, twice (G8)

- [ ] **3.4** Window B. `unpim -TenantAlias s15b-az` deactivates Reader on `opim-s1-rg`; then `pim -TenantAlias s15b-az` activates exactly that role, and again sends nothing.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s15b/TenantMap.psd1'
$Off = @(Disable-OPIMMyRole -TenantAlias 's15b-az' -TenantMapPath $Map -ErrorVariable ErrsOff -ErrorAction SilentlyContinue)
"unpim: results $($Off.Count) ($((@($Off | ForEach-Object { "$($_.DisplayName) $($_.Scope) $($_.Status)" })) -join '; ')); errors $($ErrsOff.Count)"
$Gone = $false
foreach ($Try in 1..12) {
    $Gone = @(Get-OPIMAzureRole -Activated -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' }).Count -eq 0
    if ($Gone) { break }
    Start-Sleep -Seconds 10
}
"No Reader active: $Gone after $Try read(s)"
$Out1 = @(Enable-OPIMMyRole -TenantAlias 's15b-az' -TenantMapPath $Map -ErrorVariable Errs1 -WarningVariable Warns1 -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
$global:S15bLastActivation = [datetime]::UtcNow
"pim first call: results $($Out1.Count) ($((@($Out1 | ForEach-Object { "$($_.DisplayName) $($_.Scope) $($_.Status)" })) -join '; ')); errors $($Errs1.Count); warnings $($Warns1.Count)"
$Active = @()
foreach ($Try in 1..12) {
    $Active = @(Get-OPIMAzureRole -Activated -ErrorAction Stop)
    if ($Active.Count -ge 1) { break }
    Start-Sleep -Seconds 10
}
"Active Azure roles: $($Active.Count) ($((@($Active | ForEach-Object { "$($_.RoleDefinitionDisplayName) $($_.ScopeDisplayName)" })) -join '; '))"
$Out2 = @(Enable-OPIMMyRole -TenantAlias 's15b-az' -TenantMapPath $Map -ErrorVariable Errs2 -WarningVariable Warns2 -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
"pim second call: results $($Out2.Count); errors $($Errs2.Count)$(if ($Errs2.Count) { ", last $($Errs2[-1].FullyQualifiedErrorId)" }); warning says already active: $([bool](@($Warns2 | Where-Object { "$_" -match 'is already active' })))"
```

**Expect:** `unpim: results 1 (Reader opim-s1-rg Revoked); errors 0`; `No Reader active: True`; pim
first call `results 1 (Reader opim-s1-rg Provisioned); errors 0; warnings 0`; `Active Azure roles: 1
(Reader opim-s1-rg)`; second call `results 0; errors 0; warning says already active: True`.
**Failure looks like:** Reader on `opim-s1-rg2` activated -- STOP. A second request on the second
call -- record it (ARM's listing can lag, as step 5a measured).

Result:

### 3.5. The last `unpim`

- [ ] **3.5** Window B. Five and a half minutes after 3.4's activation, `unpim -TenantAlias s15b-az` deactivates Reader on `opim-s1-rg`, and nothing is active but the ownership.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s15b/TenantMap.psd1'
if (-not $global:S15bLastActivation) { throw 'No activation time is recorded in this window; run 3.4 in this window first.' }
Start-Sleep -Seconds ([math]::Max(0, [math]::Ceiling(($global:S15bLastActivation.AddMinutes(5.5) - [datetime]::UtcNow).TotalSeconds)))
$Out = @(Disable-OPIMMyRole -TenantAlias 's15b-az' -TenantMapPath $Map -ErrorVariable Errs -ErrorAction SilentlyContinue)
"unpim: results $($Out.Count) ($((@($Out | ForEach-Object { "$($_.DisplayName) $($_.Scope) $($_.Status)" })) -join '; ')); errors $($Errs.Count)"
Start-Sleep -Seconds 45
"Active: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** `unpim: results 1 (Reader opim-s1-rg Revoked); errors 0`; `Active: directory 0, group 1,
Azure 0` (the group row is the ownership).
**Failure looks like:** a role still active -- record it; section 4 removes the eligibilities and the
user, which ends any activation, but the result is then `[~]`.

Result:

### 4. The fixture's teardown

### 4.1. Window B signs out

- [ ] **4.1** Window B. The module's session and the Graph and Azure sessions of the test user end before the user is deleted.

```powershell
Disconnect-OPIM
try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { $null = $PSItem }
try { Disconnect-AzAccount -ErrorAction Stop | Out-Null } catch { $null = $PSItem }
"Module state cleared: $($null -eq (& (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }))"
"No Graph context: $($null -eq (Get-MgContext))"
"No Az context: $($null -eq (Get-AzContext))"
```

**Expect:** three `True`. Window B is then ended.
**Failure looks like:** `False` -- end the process; its tokens die with it.

Result:

### 4.2. The operator's two tenant changes for the test user (P-8)

- [ ] **4.2** Window A, as `oer-live-cc`. Before the user is deleted, and only with the permission for each: the test user leaves the group `Exclude from CA`, and its assignment to the Microsoft Graph Command Line Tools application is removed.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'opim-s15b-'
Connect-OerLive -Graph
$Roles = @((Get-MgContext).Scopes)
$CanMembers = [bool]($Roles | Where-Object { $_ -in 'GroupMember.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All' })
$CanAppRoles = [bool]($Roles | Where-Object { $_ -in 'AppRoleAssignment.ReadWrite.All', 'Directory.ReadWrite.All' })
"oer-live-cc may remove a group member: $CanMembers; may remove an app role assignment: $CanAppRoles"
$Upn = 'opim-s1-live-user@{0}' -f $Cfg.UserDomain
Assert-OerLivePrefix -Name $Upn -Prefix 'opim-s1-'
$User = Invoke-OerLiveGraph -Uri ("v1.0/users/{0}?`$select=id,userPrincipalName" -f [uri]::EscapeDataString($Upn))
Assert-OerLiveOk -Response $User -Activity 'read the test user'
Assert-OerLivePrefix -Name ([string]$User.Body.userPrincipalName) -Prefix 'opim-s1-'
$UserId = [string]$User.Body.id
$Groups = Invoke-OerLiveGraph -All -Uri "v1.0/users/$UserId/memberOf/microsoft.graph.group?`$select=id,displayName,isAssignableToRole"
Assert-OerLiveOk -Response $Groups -Activity 'read the groups of the test user'
$Exclude = @(@($Groups.Body.value) | Where-Object { [string]$_.displayName -ceq 'Exclude from CA' })
"Member of Exclude from CA: $($Exclude.Count); it is role-assignable: $(@($Exclude | Where-Object { $_.isAssignableToRole }).Count -gt 0)"
$Assignments = Invoke-OerLiveGraph -All -Uri "v1.0/users/$UserId/appRoleAssignments?`$select=id,resourceDisplayName"
Assert-OerLiveOk -Response $Assignments -Activity 'read the app role assignments of the test user'
$Cli = @(@($Assignments.Body.value) | Where-Object { [string]$_.resourceDisplayName -ceq 'Microsoft Graph Command Line Tools' })
"Assignments to Microsoft Graph Command Line Tools: $($Cli.Count); all assignments: $(@($Assignments.Body.value).Count)"
if ($CanMembers -and $Exclude.Count -eq 1 -and -not $Exclude[0].isAssignableToRole) {
    $R = Invoke-OerLiveGraph -Method DELETE -Uri "v1.0/groups/$($Exclude[0].id)/members/$UserId/`$ref"
    "Removed from Exclude from CA: $($R.Ok) ($($R.Status) $($R.Code))"
}
if ($CanAppRoles) {
    foreach ($A in $Cli) {
        $R = Invoke-OerLiveGraph -Method DELETE -Uri "v1.0/users/$UserId/appRoleAssignments/$($A.id)"
        "Removed the assignment: $($R.Ok) ($($R.Status) $($R.Code))"
    }
}
Start-Sleep -Seconds 20
$Groups = Invoke-OerLiveGraph -All -Uri "v1.0/users/$UserId/memberOf/microsoft.graph.group?`$select=id,displayName"
$Assignments = Invoke-OerLiveGraph -All -Uri "v1.0/users/$UserId/appRoleAssignments?`$select=id,resourceDisplayName"
"After: member of Exclude from CA $(@(@($Groups.Body.value) | Where-Object { [string]$_.displayName -ceq 'Exclude from CA' }).Count); assignments to Microsoft Graph Command Line Tools $(@(@($Assignments.Body.value) | Where-Object { [string]$_.resourceDisplayName -ceq 'Microsoft Graph Command Line Tools' }).Count)"
Disconnect-OerLive
```

**Expect:** every identity line `True`; the two permission lines; `Member of Exclude from CA: 1`;
`Assignments to Microsoft Graph Command Line Tools: 1`; each removal `True (204 )`; `After: member
of Exclude from CA 0; assignments ... 0`.
**Record:** a permission line that is `False`: that removal is not made (scope 10 says only with the
permission), and the user's deletion in 4.4 ends the membership and the assignment instead.
**Failure looks like:** a 401 or 403 on a READ -- STOP (G6). A refused removal -- record it and do not
retry another way; 4.4 still deletes the user.

Result:

### 4.3. The teardown, planned

- [ ] **4.3** Window A, as `oer-live-cc`. `Initialize-OpimS1Prereq.ps1 -Teardown -WhatIf` plans the fixture's removal, and every target carries the prefix `opim-s1-`.

```powershell
& (Join-Path $env:OPIMLIVE_HOME 'Initialize-OpimS1Prereq.ps1') -Teardown -WhatIf
```

The `What if:` lines go to the window's host, so the window's whole output is kept and every
`What if:` line in it is read for its target.

**Expect:** every identity line `True`; the sweep finds the test user and the test group; the `What
if:` lines name the two Azure eligibilities, the two resource groups, the four directory and group
eligibilities, the group, the user and the two secrets, and every target starts with `opim-s1-`;
`WhatIf: nothing was removed`.
**Failure looks like:** a target without the prefix -- STOP. A 401 or 403 -- STOP (G6).

Result:

### 4.4. The teardown

- [ ] **4.4** Window A, as `oer-live-cc`. `Initialize-OpimS1Prereq.ps1 -Teardown` removes the Azure eligibilities, the resource groups, the directory and group eligibilities, the group (with the step 4 ownership), the user and the two secrets.

```powershell
& (Join-Path $env:OPIMLIVE_HOME 'Initialize-OpimS1Prereq.ps1') -Teardown
```

**Expect:** every identity line `True`; `Removed:` lines for the Azure eligibilities on `opim-s1-rg`
and `opim-s1-rg2`; `Deleted:` for both resource groups; `Remove-OerLiveTestObjects: removed N,
residue 0, unreadable 1` (the group's assignment schedules, which `oer-live-cc` cannot read, decision
B8; deleting the group removes them); `Removed: opim-s1-live-user-password from the vault` and the
same for `-totp`; `Sweep after the teardown: prefixed directory objects 0, prefixed resource groups 0`.
**Record:** each residue line exactly as it comes.
**Failure looks like:** a residue line -- record it; 4.5 decides. A 401 or 403 -- STOP (G6).

Result:

### 4.5. The sweep

- [ ] **4.5** Window A, as `oer-live-cc`. Nothing with the prefix `opim-s1` is left: no directory object, no resource group, no residue row, and no secret in the vault.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'opim-s15b-'
Connect-OerLive -Graph
"Directory objects with the prefix opim-s1-: $(@(Find-OerLivePrefixed -Prefix 'opim-s1-' -ThrowOnUnread -Quiet).Count)"
"Directory objects with the prefix opim-s15b-: $(@(Find-OerLivePrefixed -Prefix 'opim-s15b-' -ThrowOnUnread -Quiet).Count)"
$Deleted = Invoke-OerLiveGraph -All -Uri "v1.0/directory/deletedItems/microsoft.graph.user?`$select=id,userPrincipalName"
"Deleted users read: $($Deleted.Ok); of them with the prefix opim-s1-: $(@(@($Deleted.Body.value) | Where-Object { ([string]$_.userPrincipalName) -like '*opim-s1-*' }).Count)"
"Residue rows with a prefix opim-s1: $(@(Read-OerLiveResidue | Where-Object { ([string]$_['prefix']).StartsWith('opim-s1') }).Count)"
Connect-OerLive -Arm
$Rgs = Invoke-OerLiveArm -All -Path ("/subscriptions/{0}/resourcegroups?api-version=2021-04-01" -f $Cfg.SubscriptionId)
Assert-OerLiveOk -Response $Rgs -Activity 'list the resource groups'
"Resource groups with the prefix opim-s1-: $(@(@($Rgs.Body.value) | Where-Object { ([string]$_.name).StartsWith('opim-s1-', [System.StringComparison]::OrdinalIgnoreCase) }).Count)"
Disconnect-OerLive
Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
"Secrets left in the vault OpimLive with the prefix opim-s1-: $(@(Get-SecretInfo -Vault OpimLive -ErrorAction Stop | Where-Object { $_.Name -like 'opim-s1-*' }).Count)"
```

**Expect:** `opim-s1-: 0`; `opim-s15b-: 0`; `Resource groups ...: 0`; `Residue rows ...: 0`;
`Secrets ...: 0`.
**Record:** the deleted-users line: a deleted user stays in the recycle bin for 30 days unless it is
deleted for good, which this file does not do.
**Failure looks like:** any other count -- record each object by name; a directory object or a
resource group left is a STOP (G11 #5).

Result:

## Teardown

The fixture is removed in section 4 by the prerequisite script. The two checks below close the run.

### T.1. The step's raw folder

- [ ] **T.1** The step's raw folder, with the run's tenant map, the host log and any screenshot, is deleted once the results are written up.

```powershell
$Raw = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s15b'
Remove-Item -LiteralPath $Raw -Recurse -Force -ErrorAction SilentlyContinue
"The step's raw folder is gone: $(-not (Test-Path -LiteralPath $Raw))"
"Untracked files under docs/live-verification: $(@(git status --porcelain --untracked-files=all -- docs/live-verification | Where-Object { $_ -match '^\?\?' }).Count)"
```

**Expect:** `True`; `0`.
**Failure looks like:** `False` -- a process still holds a file; end it and run again.

Result:

### T.2. What is left on purpose

- [ ] **T.2** Nothing of the sprint's fixture is left in the tenant, and the operator's own changes that do not carry the prefix are listed for the operator.

```powershell
"Left on purpose by this file: the Conditional Access exclusions of the test account and the registration-campaign exclusion of the group Exclude from CA, which the operator made in step 2 and restores (P-8); the deleted user in the recycle bin (4.5)."
```

**Expect:** the line.
**Failure looks like:** --

Result:
