# Live verification checklist -- a role or a group is named by its display name, an ambiguous name is refused, and -Scope and -AccessType pick one (feat/activate-by-display-name)

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
to nothing outside the prefixes `opim-s1-` (the sprint's fixture) and `opim-s14-` (this step's own
objects, of which there are none). Check 0.1 proves the identity before any other check calls the
module. If a browser window or a sign-in prompt appears mid-run, STOP and run check 0.1 again: in
this file every sign-in is a device code, and the proof of 0.1 holds only for the sign-in it checked.

**Two windows, never one process** (decision A10). Window A runs as `oer-live-cc`; window B runs the
module as the test user. The Microsoft Graph SDK holds one session per process, so the two never
share one. Every block below names its window.

**No block prints a scope id, an object id or a message that holds one.** An Azure scope carries the
subscription id and a completion text carries a schedule id, so the blocks print counts, error ids
and True/False, and mask the id in a completion text as `(id)`.

## What changed and why this needs a live tenant

- **A. A name is a display name or the old tab-completed form** ("feat: resolve a role or group by
  its display name"). `Resolve-OPIMSchedule` replaces `Resolve-RoleByName`: the id in the last
  parentheses wins when it is listed, and otherwise the whole string is the display name, compared
  exactly and without regard to letter case. A mock cannot show that the real display names the
  listings return are the ones the resolver compares.
- **B. Enable and Disable take the display name, `-Scope` and `-AccessType`** ("feat: activate and
  deactivate by display name, with -Scope and -AccessType"). An ambiguous name is `AmbiguousName`
  with the candidates and activates nothing; `-Scope` picks a scope, `-AccessType` the membership or
  the ownership, and a group name means the membership by default. Each name resolves on its own.
- **C. A role that is eligible but not active is reported as already deactivated** ("fix: report a
  role that is already deactivated as not active", OPIM-40). The second deactivation is a
  non-terminating `ActiveRoleNotFound`, never step 3's terminating "not found as an eligible role".
  "fix: never say already deactivated while the role is active" keeps that claim away from a role
  that is active under another key -- the old form with the eligibility id, as 0.5.1's completer
  wrote it, now names the active form instead -- and adds that an activation may not have finished.
- **D. The Get cmdlets take the display name** ("feat: let the Get cmdlets take a display name"), and
  **`Get-OPIMAzureRole` looks a role up among the listed ones** ("fix: look an Azure role up among the
  listed roles, at the given scope", OPIM-23). Step 2 measured the old form there as 0 rows and
  `InsufficientPermissions` twice.
- **E. The completers** ("feat: complete a unique role or group by its display name"). A unique name
  is offered bare, an ambiguous one in the old form, with an apostrophe doubled ("fix: escape every
  kind of single quote in a completion" covers the typographic ones too). `TabExpansion2` shows what
  a person at the console gets.
- **F. The documentation** ("docs: describe display names, -Scope and -AccessType"). Nothing to run.

The fixture of step 2 is used as it stands (decision A9): the test user `opim-s1-live-user`, the
group `opim-s1-grp` (eligible as member and as owner), the resource groups `opim-s1-rg` and
`opim-s1-rg2` (Reader eligible on each, the ambiguous Azure name), and the directory roles
Usage Summary Reports Reader and Message Center Privacy Reader at the directory scope. This file
creates no object, so it has no prerequisite script of its own.

## What this file does not check, and why

Class B, each proven by the unit tests named:

- **A directory role at more than one scope** (the root and an administrative unit), and `-Scope`
  with an administrative unit's id path or display name -- the fixture has no administrative unit
  (G9). `tests/Unit/Private/Find-OPIMScheduleMatch.Tests.ps1`, `Resolve-OPIMSchedule.Tests.ps1`,
  `tests/Unit/Public/Enable-OPIMDirectoryRole.Tests.ps1`.
- **A group the user holds only as owner**, and two groups with the same display name -- the fixture
  has one group, eligible both ways. `Find-OPIMScheduleMatch.Tests.ps1`, `Resolve-OPIMSchedule.Tests.ps1`.
- **A display name with an apostrophe, with parentheses, or with wildcard characters** -- no fixture
  role carries one. `Find-OPIMScheduleMatch.Tests.ps1`, `Get-OPIMCompletionText.Tests.ps1`.
- **`-Identity` that matches more than one post** -- ids are unique in a real tenant. The Enable and
  Disable test files.
- **A listing that fails** -- the test user can read its own lists, so no 403 is available.
  `Resolve-OPIMSchedule.Tests.ps1` and the Enable and Disable test files.
- **A scope with a trailing slash** -- refused by parameter validation before any request; the unit
  tests of the four Enable and Disable role cmdlets, `Get-OPIMAzureRole` and the resolver.

## Setup, once

The operator sets `OPIMLIVE_HOME` in both windows to the notes folder that holds the `OpimLive`
folder; no checklist holds that path. The test user's sign-in name and the test tenant's id are read
by the harness through OerLive and are never printed. Window B runs from the root of the step's
worktree, and its console output also goes to the file named in `OPIMLIVE_HOSTLOG`, where
`Connect-AzAccount` writes the Azure device code (OpimLive 1.0.2). Raw output goes to
`docs/live-verification/raw/opim-s14` (git-ignored), which is deleted once the results are written up.

### S.1. Find the build under test and tie it to the branch head

- [ ] **S.1** Window B. The newest build in `output/module/Omnicit.PIM/` was made after the branch head was committed.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$HeadTime = [datetimeoffset]::Parse((git log -1 --format=%cI))
"Branch head: $(git log -1 --format='%h %s')"
"Built version folder: $($Built.Directory.Name)"
"Built after the branch head was committed: $([datetimeoffset]$Built.LastWriteTime -gt $HeadTime)"
"Tracked changes in the working tree: $(@(git status --porcelain --untracked-files=no).Count)"
"The built module has the new resolver: $([bool](Select-String -LiteralPath (Join-Path $Built.DirectoryName 'Omnicit.PIM.psm1') -Pattern 'function Resolve-OPIMSchedule' -SimpleMatch -Quiet))"
```

**Expect:** the branch head's hash and subject; the version folder the branch's build printed;
`Built after the branch head was committed: True`; `Tracked changes in the working tree: 0`;
`The built module has the new resolver: True`.
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

- [ ] **S.3** Window A, as `oer-live-cc`. The fixture's user and group exist, and no object carries the prefix `opim-s14-`.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$null = Import-OerLiveConfig -Prefix 'opim-s14-'
Connect-OerLive -Graph
"Objects with the prefix opim-s14-: $(@(Find-OerLivePrefixed -Prefix 'opim-s14-' -ThrowOnUnread -Quiet).Count)"
"Objects with the prefix opim-s1- (the fixture): $(@(Find-OerLivePrefixed -Prefix 'opim-s1-' -ThrowOnUnread -Quiet).Count)"
Disconnect-OerLive
```

**Expect:** every identity check line of `oer-live-cc` `True`; `opim-s14-: 0`; `opim-s1-: 2` (the user
and the group; the resource groups are not directory objects).
**Failure looks like:** a 401 or 403 -- STOP (G6). Another count -- record each object by name and
STOP: the fixture is not the one this file assumes. A throw on an unread collection is a failed read,
never a `0`.

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
$Sign = Connect-OpimLiveUser -IncludeARM -RawFolder 'docs/live-verification/raw/opim-s14'
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
$State = & (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }
"Session tenant is the test tenant: $([string]::Equals([string]$State.TenantId, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
"Az context is the test tenant: $([string]::Equals([string](Get-AzContext).Tenant.Id, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
```

**Expect:** `Disconnect-OPIM, Disconnect-MgGraph and Disconnect-AzAccount ran first`; the rows
`Graph Information True ok` and `Azure Host False ok`; every True/False line `True`. The block
prints neither the account nor the tenant id.
**Failure looks like:** `False` on any line, or a `STOP` -- STOP: run `Disconnect-OPIM`, end window B
and run no other check.

Result:

### 0.2. Nothing is active, and the listings give the fixture

- [ ] **0.2** Window B. Before section 1 the test user holds no active assignment, and the three listings give step 2's counts.

```powershell
"Eligible: directory $(@(Get-OPIMDirectoryRole -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -ErrorAction Stop).Count)"
"Active: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** `Eligible: directory 2, group 2, Azure 2`; `Active: directory 0, group 0, Azure 0`.
**Failure looks like:** an active row -- record it and wait for it to end before section 1. Another
eligible count -- STOP: the fixture is not the one this file assumes.

Result:

### 1. A directory role by its display name

The justification in every activation is `opim-s14 live verification`.

### 1.1. Enable-OPIMDirectoryRole with the display name, twice

- [ ] **1.1** Window B. `Enable-OPIMDirectoryRole 'Usage Summary Reports Reader'` activates that role once; the second call gives a clear outcome and no second activation (G8).

```powershell
$Name = 'Usage Summary Reports Reader'
$First = @(Enable-OPIMDirectoryRole $Name -Justification 'opim-s14 live verification' -Hours 1 -ErrorAction Stop)
"First: output $($First.Count); status $($First.status); role $($First.roleDefinition.displayName); at the directory scope: $($First.directoryScopeId -eq '/')"
$Errors = @()
try { $Second = @(Enable-OPIMDirectoryRole $Name -Justification 'opim-s14 live verification' -Hours 1 -ErrorVariable Errors -ErrorAction SilentlyContinue) } catch { $Errors += $PSItem; $Second = @() }
"Second (G8): output $($Second.Count); errors $($Errors.Count), the last $(@($Errors)[-1].FullyQualifiedErrorId)"
"Active rows of the role: $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq $Name }).Count); of the other role: $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -ne $Name }).Count)"
```

**Expect:** `First: output 1; status Provisioned` (or `PendingProvisioning`), the role's name, `True`;
`Active rows of the role: 1; of the other role: 0`.
**Record:** the second call's outcome -- an error saying the role is already active (step 3:
`RoleAssignmentExists,Enable-OPIMDirectoryRole`) is a pass; a second request accepted or a crash is a
fail (G8).
**Failure looks like:** `EligibleRoleNotFound` or `AmbiguousName` on the first call -- the resolver
does not read the real display name; record the id and STOP.

Result:

### 1.2. The old form gives the same role

- [ ] **1.2** Window B. The old tab-completed form `'Usage Summary Reports Reader (id)'` resolves to the same eligibility as the display name, and enabling it again activates nothing new.

```powershell
$Name = 'Usage Summary Reports Reader'
$Eligible = @(Get-OPIMDirectoryRole -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq $Name })
if ($Eligible.Count -ne 1) { throw "Expected one eligible row, found $($Eligible.Count)." }
$Old = '{0} ({1})' -f $Eligible[0].roleDefinition.displayName, $Eligible[0].id
$ByName = @(Get-OPIMDirectoryRole $Name -ErrorAction Stop)
$ByOld = @(Get-OPIMDirectoryRole $Old -ErrorAction Stop)
"Get by name: $($ByName.Count) rows, status $((@($ByName.Status) | Sort-Object) -join ', '); by old form: $($ByOld.Count) rows, status $($ByOld.Status)"
"The eligible row is the same post: $(@($ByName | Where-Object Status -EQ 'Eligible')[0].id -eq $ByOld[0].id)"
$Errors = @()
try { $Again = @(Enable-OPIMDirectoryRole $Old -Justification 'opim-s14 live verification' -Hours 1 -ErrorVariable Errors -ErrorAction SilentlyContinue) } catch { $Errors += $PSItem; $Again = @() }
"Enable with the old form while active: output $($Again.Count); errors $($Errors.Count), the last $(@($Errors)[-1].FullyQualifiedErrorId)"
"Active rows of the role: $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq $Name }).Count)"
```

**Expect:** `Get by name: 2 rows, status Active, Eligible` (the role is active since 1.1, and an
eligible and an active post are two states, not two candidates); `by old form: 1 rows, status
Eligible`; `The eligible row is the same post: True`; the old form's Enable gives the same outcome as
1.1's second call; `Active rows of the role: 1`.
**Failure looks like:** `AmbiguousName` from `Get-OPIMDirectoryRole` with the display name -- the
eligible and active posts were counted as candidates; record and STOP.

Result:

### 2. A group by its display name

### 2.1. Enable-OPIMEntraIDGroup with the group's name activates the membership, twice

- [ ] **2.1** Window B. `Enable-OPIMEntraIDGroup 'opim-s1-grp'` activates the membership (Member is the default) and not the ownership; the second call gives a clear outcome (G8).

```powershell
$First = @(Enable-OPIMEntraIDGroup 'opim-s1-grp' -Justification 'opim-s14 live verification' -Hours 1 -ErrorAction Stop)
"First: output $($First.Count); status $($First.status); accessId $($First.accessId) at $([datetime]::UtcNow.ToString('HH:mm:ss')) UTC"
$Errors = @()
try { $Second = @(Enable-OPIMEntraIDGroup 'opim-s1-grp' -Justification 'opim-s14 live verification' -Hours 1 -ErrorVariable Errors -ErrorAction SilentlyContinue) } catch { $Errors += $PSItem; $Second = @() }
"Second (G8): output $($Second.Count); errors $($Errors.Count), the last $(@($Errors)[-1].FullyQualifiedErrorId)"
$Active = @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' })
"Active rows: member $(@($Active | Where-Object accessId -EQ 'member').Count), owner $(@($Active | Where-Object accessId -EQ 'owner').Count)"
```

**Expect:** `First: output 1`, a status that is not a failure, `accessId member`; `Active rows:
member 1, owner 0`.
**Record:** the second call's outcome, as in 1.1, and whether the membership is still active at 7.2
(OPIM-39: step 2 once saw a repeated activation remove it within seven minutes; step 3 did not).
**Failure looks like:** `accessId owner`, or an owner row -- the Member default is not applied: STOP.

Result:

### 2.2. -AccessType Owner activates the ownership, twice

- [ ] **2.2** Window B. `Enable-OPIMEntraIDGroup 'opim-s1-grp' -AccessType Owner` activates the ownership; the second call gives a clear outcome (G8).

```powershell
$First = @(Enable-OPIMEntraIDGroup 'opim-s1-grp' -AccessType Owner -Justification 'opim-s14 live verification' -Hours 1 -ErrorAction Stop)
"First: output $($First.Count); status $($First.status); accessId $($First.accessId) at $([datetime]::UtcNow.ToString('HH:mm:ss')) UTC"
$Errors = @()
try { $Second = @(Enable-OPIMEntraIDGroup 'opim-s1-grp' -AccessType Owner -Justification 'opim-s14 live verification' -Hours 1 -ErrorVariable Errors -ErrorAction SilentlyContinue) } catch { $Errors += $PSItem; $Second = @() }
"Second (G8): output $($Second.Count); errors $($Errors.Count), the last $(@($Errors)[-1].FullyQualifiedErrorId)"
$Active = @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' })
"Active rows: member $(@($Active | Where-Object accessId -EQ 'member').Count), owner $(@($Active | Where-Object accessId -EQ 'owner').Count)"
```

**Expect:** `First: output 1`, a status that is not a failure, `accessId owner`; `Active rows:
member 1, owner 1` (or member 0 if OPIM-39 struck -- record it).
**Record:** the second call's outcome, as in 1.1.
**Failure looks like:** `accessId member` -- `-AccessType` is not applied: STOP.

Result:

### 3. An Azure role by its display name

### 3.1. 'Reader' is ambiguous: AmbiguousName with two candidates, and nothing is activated

- [ ] **3.1** Window B. `Enable-OPIMAzureRole 'Reader'` matches Reader on both resource groups, is refused with `AmbiguousName` naming two candidates and `-Scope`, and activates nothing; a second call does the same (G8).

```powershell
$Before = @(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count
foreach ($Try in 1, 2) {
    $Errors = @()
    try { $Out = @(Enable-OPIMAzureRole 'Reader' -Justification 'opim-s14 live verification' -Hours 1 -ErrorVariable Errors -ErrorAction SilentlyContinue) } catch { $Errors += $PSItem; $Out = @() }
    $Own = @($Errors | Where-Object { $_.FullyQualifiedErrorId -like 'AmbiguousName,*' })
    $Message = if ($Own) { $Own[-1].Exception.Message } else { '' }
    $NamesBoth = $Message.Contains('-> opim-s1-rg (') -and $Message.Contains('-> opim-s1-rg2 (')
    "Call ${Try}: output $($Out.Count); errors $($Errors.Count), the last $(@($Errors)[-1].FullyQualifiedErrorId); candidates named $(([regex]::Matches($Message, ' at scope ')).Count); suggests -Scope: $($Message.Contains('-Scope')); names opim-s1-rg and opim-s1-rg2: $NamesBoth"
}
"Active Azure roles before: $Before; after: $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** each call `output 0`, the last error `AmbiguousName,Enable-OPIMAzureRole`, `candidates
named 2`, `suggests -Scope: True`, `names opim-s1-rg and opim-s1-rg2: True`; `Active Azure roles
before: 0; after: 0`.
**Failure looks like:** any output, or an active row after -- STOP: the module activated one of two
candidates (the defect this step closes).

Result:

### 3.2. -Scope picks opim-s1-rg, twice

- [ ] **3.2** Window B. `Enable-OPIMAzureRole 'Reader' -Scope <the scope of opim-s1-rg>` activates Reader on exactly that resource group; the second call gives a clear outcome (G8).

```powershell
$Rg = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg' })
$Rg2 = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg2' })
if ($Rg.Count -ne 1 -or $Rg2.Count -ne 1) { throw "Expected one eligible Reader on each resource group, found $($Rg.Count) and $($Rg2.Count)." }
$First = @(Enable-OPIMAzureRole 'Reader' -Scope $Rg[0].ScopeId -Justification 'opim-s14 live verification' -Hours 1 -ErrorAction Stop)
$RequestScope = @($First | ForEach-Object { if ($_.ScopeId) { [string]$_.ScopeId } else { [string]$_.Scope } })
"First: output $($First.Count); status $($First.Status); on opim-s1-rg: $($RequestScope.Count -eq 1 -and [string]::Equals($RequestScope[0], $Rg[0].ScopeId, [System.StringComparison]::OrdinalIgnoreCase))"
$Errors = @()
try { $Second = @(Enable-OPIMAzureRole 'Reader' -Scope $Rg[0].ScopeId.ToUpperInvariant() -Justification 'opim-s14 live verification' -Hours 1 -ErrorVariable Errors -ErrorAction SilentlyContinue) } catch { $Errors += $PSItem; $Second = @() }
"Second (G8, the scope in upper case): output $($Second.Count); errors $($Errors.Count), the last $(@($Errors)[-1].FullyQualifiedErrorId)"
$Active = @(Get-OPIMAzureRole -Activated -ErrorAction Stop | Where-Object RoleDefinitionDisplayName -EQ 'Reader')
"Active Reader rows (scope '/'): on opim-s1-rg $(@($Active | Where-Object { $_.ScopeId -eq $Rg[0].ScopeId }).Count), on opim-s1-rg2 $(@($Active | Where-Object { $_.ScopeId -eq $Rg2[0].ScopeId }).Count)"
```

**Expect:** `First: output 1`, a status that is not a failure, `on opim-s1-rg: True`; `Active Reader
rows (scope '/'): on opim-s1-rg 1, on opim-s1-rg2 0` (read at `/`, since ARM's listing at the
resource group scope lags, OPIM-41).
**Record:** the second call's outcome, as in 1.1 -- the scope in upper case must still name
opim-s1-rg (A12: compared without regard to letter case).
**Failure looks like:** a row on opim-s1-rg2 -- STOP: `-Scope` activated more than it named.

Result:

### 4. The completers, through TabExpansion2

The roles of sections 1 to 3 are active now: Usage Summary Reports Reader, the group's membership and
ownership, and Reader on opim-s1-rg. Each line prints the completion texts with the id in the last
parentheses masked as `(id)`.

### 4.1. Directory roles

- [ ] **4.1** Window B. The Enable completer offers both directory roles by their bare names; the Disable completer offers the active one by its bare name.

```powershell
$Show = { param($Line) $R = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length; (@($R.CompletionMatches.CompletionText) | ForEach-Object { $_ -replace '\(([^()]+)\)''$', "(id)'" }) -join ' | ' }
"Enable-OPIMDirectoryRole: $(& $Show 'Enable-OPIMDirectoryRole ')"
"Enable-OPIMDirectoryRole, typed 'Usage: $(& $Show "Enable-OPIMDirectoryRole 'Usage")"
"Disable-OPIMDirectoryRole: $(& $Show 'Disable-OPIMDirectoryRole ')"
```

**Expect:** `'Message Center Privacy Reader' | 'Usage Summary Reports Reader'` in either order;
`'Usage Summary Reports Reader'` for the typed prefix; `'Usage Summary Reports Reader'` for Disable.
**Failure looks like:** an old form for a unique name, or no completion -- record the line.

Result:

### 4.2. Groups

- [ ] **4.2** Window B. The group completers offer the membership by the bare name and the ownership in the old form; with `-AccessType Owner` typed, the ownership by the bare name.

```powershell
$Show = { param($Line) $R = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length; (@($R.CompletionMatches.CompletionText) | ForEach-Object { $_ -replace '\(([^()]+)\)''$', "(id)'" }) -join ' | ' }
"Enable-OPIMEntraIDGroup: $(& $Show 'Enable-OPIMEntraIDGroup ')"
"Enable-OPIMEntraIDGroup -AccessType Owner: $(& $Show 'Enable-OPIMEntraIDGroup -AccessType Owner ')"
"Disable-OPIMEntraIDGroup: $(& $Show 'Disable-OPIMEntraIDGroup ')"
```

**Expect:** `'opim-s1-grp' | 'opim-s1-grp - owner (id)'` for Enable; `'opim-s1-grp'` alone with
`-AccessType Owner`; for Disable the same two as Enable while both are active (or only
`'opim-s1-grp - owner (id)'` and no bare name if OPIM-39 removed the membership -- record it).
**Failure looks like:** two bare `'opim-s1-grp'` texts -- a text that names two posts: STOP.

Result:

### 4.3. Azure roles

- [ ] **4.3** Window B. The ambiguous Reader is offered in the old form on Enable, and by its bare name once `-Scope` names a resource group; the one active Reader is offered by its bare name on Disable.

```powershell
$Show = { param($Line) $R = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length; (@($R.CompletionMatches.CompletionText) | ForEach-Object { $_ -replace '\(([^()]+)\)''$', "(id)'" }) -join ' | ' }
$Rg = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg' })[0]
"Enable-OPIMAzureRole: $(& $Show 'Enable-OPIMAzureRole ')"
"Enable-OPIMAzureRole -Scope (opim-s1-rg): $(& $Show "Enable-OPIMAzureRole -Scope '$($Rg.ScopeId)' ")"
"Disable-OPIMAzureRole: $(& $Show 'Disable-OPIMAzureRole ')"
```

**Expect:** `'Reader -> opim-s1-rg (id)' | 'Reader -> opim-s1-rg2 (id)'` in either order; `'Reader'`
with `-Scope`; `'Reader'` for Disable.
**Failure looks like:** a bare `'Reader'` on the first line -- a text that names two posts: STOP.

Result:

### 5. Get-OPIMAzureRole by name and scope (OPIM-23)

### 5.1. -RoleName and -Identity find the role below the root scope

- [ ] **5.1** Window B. `Get-OPIMAzureRole 'Reader'` is ambiguous; with `-Scope` it returns that resource group's posts; the old form and `-Identity` return their post, with no `InsufficientPermissions` (step 2: 0 rows and two of them).

```powershell
$Rg = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg' })[0]
$Rg2 = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg2' })[0]
$Run = {
    param($Label, [hashtable]$Splat)
    $Errors = @()
    try { $Rows = @(Get-OPIMAzureRole @Splat -ErrorVariable Errors -ErrorAction SilentlyContinue) } catch { $Errors += $PSItem; $Rows = @() }
    "${Label}: rows $($Rows.Count), status $((@($Rows.Status) | Sort-Object) -join ', '); errors $($Errors.Count) $((@($Errors | ForEach-Object { $_.FullyQualifiedErrorId }) | Select-Object -Unique) -join ', ')"
}
& $Run "'Reader'" @{ RoleName = 'Reader' }
& $Run "'Reader' -Scope opim-s1-rg" @{ RoleName = 'Reader'; Scope = $Rg.ScopeId }
& $Run "'Reader' -Scope opim-s1-rg2" @{ RoleName = 'Reader'; Scope = $Rg2.ScopeId }
& $Run 'the old form of opim-s1-rg2' @{ RoleName = ('{0} -> {1} ({2})' -f $Rg2.RoleDefinitionDisplayName, $Rg2.ScopeDisplayName, $Rg2.Name) }
& $Run '-Identity of opim-s1-rg2' @{ Identity = $Rg2.Name }
& $Run '-Identity of opim-s1-rg2 -Scope opim-s1-rg' @{ Identity = $Rg2.Name; Scope = $Rg.ScopeId }
```

**Expect:** `'Reader'`: rows 0, the error `AmbiguousName,Get-OPIMAzureRole`; `-Scope opim-s1-rg`: rows 2,
status `Active, Eligible` (Reader there is active since 3.2), errors 0; `-Scope opim-s1-rg2`: rows 1,
status `Eligible`, errors 0; the old form: rows 1, errors 0; `-Identity`: rows 1, errors 0; `-Identity`
with the other scope: rows 0, errors 0. No line names `InsufficientPermissions`.
**Failure looks like:** `InsufficientPermissions` -- the lookup still goes to `/` by name (OPIM-23 is
not fixed): record and STOP.

Result:

### 6. The five-minute rule

### 6.1. Wait five minutes after the last activation

- [ ] **6.1** Window B. Five minutes pass after the last activation of sections 1 to 3.

```powershell
Start-Sleep -Seconds 310
"Waited: $([datetime]::UtcNow.ToString('HH:mm:ss')) UTC"
```

**Expect:** the time, at least five minutes after 3.2 finished.
**Failure looks like:** nothing can fail here; the wait is the check.

Result:

### 7. Deactivation by name, twice (G8 and OPIM-40)

### 7.1. Disable-OPIMDirectoryRole with the display name, then the old form

- [ ] **7.1** Window B. While the role is active, the old form with its ELIGIBILITY id deactivates nothing and names the active form instead of saying "already deactivated"; then `Disable-OPIMDirectoryRole 'Usage Summary Reports Reader'` deactivates the role; a second call with the name, and one with the old active form, each give a non-terminating `ActiveRoleNotFound` that says the role is already deactivated.

```powershell
$Name = 'Usage Summary Reports Reader'
$Active = @(Get-OPIMDirectoryRole -Activated -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq $Name })
$Eligible = @(Get-OPIMDirectoryRole -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq $Name })
"Active before: $($Active.Count) at $([datetime]::UtcNow.ToString('HH:mm:ss')) UTC"
$OldActive = if ($Active.Count -eq 1) { '{0} ({1})' -f $Active[0].roleDefinition.displayName, $Active[0].id }
$OldEligible = if ($Eligible.Count -eq 1) { '{0} ({1})' -f $Eligible[0].roleDefinition.displayName, $Eligible[0].id }
$Calls = @()
if ($OldEligible) { $Calls += @{ Label = 'eligible old form while active, call 0'; Arg = $OldEligible } }
$Calls += @{ Label = 'name, call 1'; Arg = $Name }, @{ Label = 'name, call 2'; Arg = $Name }
if ($OldActive) { $Calls += @{ Label = 'old active form, call 3'; Arg = $OldActive } }
foreach ($Call in $Calls) {
    $Errors = @(); $Reached = $false
    try { $Out = @(Disable-OPIMDirectoryRole $Call.Arg -ErrorVariable Errors -ErrorAction SilentlyContinue); $Reached = $true } catch { $Errors += $PSItem; $Out = @() }
    $Last = @($Errors)[-1]
    $Message = if ($Last) { $Last.Exception.Message } else { '' }
    "$($Call.Label): output $($Out.Count) status $(@($Out.status) -join ','); errors $($Errors.Count), the last $($Last.FullyQualifiedErrorId); says already deactivated: $($Message.Contains('already deactivated')); names the active form: $($Message.Contains('It is active as')); the next statement ran (non-terminating): $Reached; active rows now: $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq $Name }).Count)"
}
"Active after: $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** `Active before: 1`; call 0 `output 0`, the last error
`ActiveRoleNotFound,Disable-OPIMDirectoryRole`, `says already deactivated: False`, `names the active
form: True`, `active rows now: 1`; call 1 `output 1 status Revoked`, errors 0; calls 2 and 3 `output
0`, the last error `ActiveRoleNotFound,Disable-OPIMDirectoryRole`, `says already deactivated: True`,
`the next statement ran (non-terminating): True`; `Active after: 0`.
**Failure looks like:** call 0 deactivating the role, or saying "already deactivated" while the role
is active -- STOP (the review's C1). `ActiveDurationTooShort` -- 6.1 did not wait long enough; run 6.1
and this block again. `the next statement ran: False` -- the error is still terminating (OPIM-40 not
fixed).

Result:

### 7.2. Disable-OPIMEntraIDGroup with the group's name and with -AccessType Owner

- [ ] **7.2** Window B. `Disable-OPIMEntraIDGroup 'opim-s1-grp'` deactivates the membership and `-AccessType Owner` the ownership; each second call gives a non-terminating `ActiveRoleNotFound`.

```powershell
$Active = @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' })
"Active before: member $(@($Active | Where-Object accessId -EQ 'member').Count), owner $(@($Active | Where-Object accessId -EQ 'owner').Count) at $([datetime]::UtcNow.ToString('HH:mm:ss')) UTC"
$Calls = @(
    @{ Label = 'member, call 1'; Splat = @{ GroupName = 'opim-s1-grp' } }
    @{ Label = 'member, call 2'; Splat = @{ GroupName = 'opim-s1-grp' } }
    @{ Label = 'owner, call 1'; Splat = @{ GroupName = 'opim-s1-grp'; AccessType = 'Owner' } }
    @{ Label = 'owner, call 2'; Splat = @{ GroupName = 'opim-s1-grp'; AccessType = 'Owner' } }
)
foreach ($Call in $Calls) {
    $Errors = @(); $Reached = $false
    $Splat = $Call.Splat
    try { $Out = @(Disable-OPIMEntraIDGroup @Splat -ErrorVariable Errors -ErrorAction SilentlyContinue); $Reached = $true } catch { $Errors += $PSItem; $Out = @() }
    $Last = @($Errors)[-1]
    "$($Call.Label): output $($Out.Count) status $(@($Out.status) -join ',') accessId $(@($Out.accessId) -join ','); errors $($Errors.Count), the last $($Last.FullyQualifiedErrorId); says already deactivated: $([bool]($Last -and $Last.Exception.Message.Contains('already deactivated'))); names -AccessType Owner: $([bool]($Last -and $Last.Exception.Message.Contains('-AccessType Owner'))); non-terminating: $Reached"
}
"Active after: $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count)"
```

**Expect:** `Active before: member 1, owner 1`; `member, call 1` and `owner, call 1` `output 1 status
Revoked` with the matching accessId; the two second calls `output 0`, the last error
`ActiveRoleNotFound,Disable-OPIMEntraIDGroup`, `says already deactivated: True`, `non-terminating:
True`; `Active after: 0`.
**Record:** `names -AccessType Owner` on `member, call 2` (the ownership is still active then, so the
message may point at it); whether the membership was still active before (OPIM-39).
**Failure looks like:** `member, call 1` deactivating the ownership -- STOP: the Member default is not
applied to Disable.

Result:

### 7.3. Disable-OPIMAzureRole with -Scope

- [ ] **7.3** Window B. `Disable-OPIMAzureRole 'Reader' -Scope <opim-s1-rg>` deactivates Reader there; the second call gives a non-terminating `ActiveRoleNotFound`.

```powershell
$Rg = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg' })[0]
"Active Reader rows before: $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop | Where-Object RoleDefinitionDisplayName -EQ 'Reader').Count) at $([datetime]::UtcNow.ToString('HH:mm:ss')) UTC"
foreach ($Try in 1, 2) {
    $Errors = @(); $Reached = $false
    try { $Out = @(Disable-OPIMAzureRole 'Reader' -Scope $Rg.ScopeId -ErrorVariable Errors -ErrorAction SilentlyContinue); $Reached = $true } catch { $Errors += $PSItem; $Out = @() }
    $Last = @($Errors)[-1]
    "Call ${Try}: output $($Out.Count) status $(@($Out.Status) -join ','); errors $($Errors.Count), the last $($Last.FullyQualifiedErrorId); says already deactivated: $([bool]($Last -and $Last.Exception.Message.Contains('already deactivated'))); non-terminating: $Reached"
}
"Active Azure roles after: $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** `Active Reader rows before: 1`; call 1 `output 1 status Revoked`, errors 0; call 2
`output 0`, the last error `ActiveRoleNotFound,Disable-OPIMAzureRole`, `says already deactivated:
True`, `non-terminating: True`; `Active Azure roles after: 0`.
**Failure looks like:** as in 7.1.

Result:

## Teardown

This step creates no object of its own (prefix `opim-s14-`). The fixture (prefix `opim-s1-`) stays
until the sprint's last step (decision A9). Delete `docs/live-verification/raw/opim-s14` once the
results are written up.

### T.1. No object of this step is left

- [ ] **T.1** Window A, as `oer-live-cc`. No directory object carries the prefix `opim-s14-`, and the fixture's two directory objects are still there.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$null = Import-OerLiveConfig -Prefix 'opim-s14-'
Connect-OerLive -Graph
"Objects with the prefix opim-s14-: $(@(Find-OerLivePrefixed -Prefix 'opim-s14-' -ThrowOnUnread -Quiet).Count)"
"Objects with the prefix opim-s1- (the fixture): $(@(Find-OerLivePrefixed -Prefix 'opim-s1-' -ThrowOnUnread -Quiet).Count)"
Disconnect-OerLive
```

**Expect:** `opim-s14-: 0`; `opim-s1-: 2`, as in S.3.
**Failure looks like:** another number -- record each object by name. A throw on an unread collection
is a failed read, never a `0`.

Result:

### T.2. The test user holds no active assignment, and window B signs out

- [ ] **T.2** Window B. After section 7, the test user has no active directory role, group or Azure assignment, and the window signs out.

```powershell
"Active directory roles: $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count)"
"Active group assignments: $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count)"
"Active Azure roles: $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
Disconnect-OPIM
try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { $null = $PSItem }
"Window B signed out: $($null -eq (Get-MgContext) -and $null -eq (& (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }))"
```

**Expect:** `0` on all three, then `Window B signed out: True`. Nothing is left in the tenant on purpose
but the fixture.
**Failure looks like:** another row -- record it and when it ends. A terminating error is a failed
read, never a pass.

Result:
