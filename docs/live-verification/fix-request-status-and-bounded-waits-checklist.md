# Live verification checklist -- a request is reported by its real status, every wait has a limit, and an active role is not requested again (fix/request-status-and-bounded-waits)

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
to nothing outside the prefixes `opim-s1-` (the sprint's fixture) and `opim-s15a-` (this step's own
objects, of which there are none). Check 0.2 proves the identity before any other check calls the
module. If a browser window or a sign-in prompt appears mid-run, STOP and run check 0.2 again: in
this file every sign-in is a device code, and the proof of 0.2 holds only for the sign-in it checked.

**Two windows, never one process** (decision A10). Window A runs as `oer-live-cc`; window B runs the
module as the test user. The Microsoft Graph SDK holds one session per process, so the two never
share one. Every block below names its window.

**No block prints a scope id, an object id or a message that holds one.** The blocks print counts,
statuses, error ids, seconds and True/False.

## What changed and why this needs a live tenant

- **A. A request is reported by its real status** ("feat: report every request by the status Graph
  or Azure gives it"). `Provisioned`, `Granted` and `ScheduleCreated` are successes; a pending
  request comes back with a warning; `Failed`, `Denied`, `Canceled`, `Revoked`, `AdminDenied` and any
  unknown status are the error `ActivationRequestFailed`. A deactivation succeeds on `Revoked`. A
  mock cannot show which statuses the services really return for each pillar.
- **B. Every wait has a limit** ("fix: bound every wait and write the final status back"). `-Wait`
  on the group and Azure cmdlets and `Wait-OPIMDirectoryRole` poll with a sleep, stop at
  `-TimeoutSeconds` (300 by default, `ActivationWaitTimedOut`), end at once on a request that waits
  for approval, and write the final status back onto the object. Step 2 measured the group `-Wait`
  returning after 13 s with the request's early status `PendingProvisioning` (OPIM-14).
- **C. `Wait-OPIMDirectoryRole` declares what it returns** ("fix: declare the type
  Wait-OPIMDirectoryRole returns"). Nothing to run beyond B.
- **D. `-NotBefore` reaches Azure** ("fix: send -NotBefore to Azure as the activation start",
  OPIM-15), and **a time without an offset is local time** ("fix: send a time without an offset as
  local time", OPIM-18). Step 2 measured a `-NotBefore` text without an offset as a 400
  `InvalidRoleAssignmentRequest` that activated nothing (local offset +02:00).
- **E. `Disable-OPIMAzureRole` names no eligibility** ("fix: send no linked eligibility when
  deactivating an Azure role", OPIM-24). Whether ARM needs one is measured here.
- **F. `-Hours` is 1 to 24** ("fix: refuse -Hours outside 1 to 24 before anything is sent", OPIM-25).
- **G. `-Activated` lists activations only** ("fix: list activations only with -Activated and
  refuse an ambiguous unpim entry", OPIM-17).
- **H. An active role or group is not requested again** ("fix: never request a role or group that
  is already active", OPIM-39). Step 2 saw a repeated activation of an active membership end the
  membership once; steps 3 and 4 did not see it again. This file measures it first, with a repeated
  request sent past the module.
- **I. A next link stays on the first request's host** ("fix: follow a next link only to the host
  of the first request", OPIM-46). Class B, see below.

The fixture of step 2 is used as it stands (decision A9): the test user `opim-s1-live-user`, the
group `opim-s1-grp` (eligible as member and as owner), the resource groups `opim-s1-rg` and
`opim-s1-rg2` (Reader eligible on each), and the directory roles Usage Summary Reports Reader and
Message Center Privacy Reader at the directory scope. This file creates no object. Its one write as
`oer-live-cc` is decision A18: `oer-live-cc`'s own service principal becomes a permanent owner of
`opim-s1-grp`, so that the test user is no longer the group's only owner and its ownership can be
deactivated; that owner stays until step 5b deletes the group.

## What this file does not check, and why

Class B, each proven by the unit tests named:

- **A request that waits for approval, fails or is denied** -- no fixture policy asks for approval,
  and the step must not change a policy. `tests/Unit/Private/Get-OPIMRequestOutcome.Tests.ps1`,
  `Write-OPIMRequestOutcome.Tests.ps1`, and the per-status contexts of the six Enable and Disable
  test files.
- **A wait that reaches `-TimeoutSeconds`, and a poll that fails** -- a provisioning that outlasts the
  limit cannot be produced on demand. The `-Wait` contexts of
  `tests/Unit/Public/Enable-OPIMEntraIDGroup.Tests.ps1` and `Enable-OPIMAzureRole.Tests.ps1`, and
  `Wait-OPIMDirectoryRole.Tests.ps1`.
- **A `createdDateTime` of Kind Local, or with another offset** -- `tests/Unit/Private/ConvertTo-OPIMUtcDateTime.Tests.ps1`
  and `Wait-OPIMDirectoryRole.Tests.ps1`.
- **A permanent assignment among the active ones** -- the test user holds none (G6).
  `tests/Unit/Public/Get-OPIMDirectoryRole.Tests.ps1`, `Get-OPIMEntraIDGroup.Tests.ps1`.
- **An ambiguous `unpim` configuration entry** -- the fixture has each role at one scope.
  `tests/Unit/Public/Disable-OPIMMyRole.Tests.ps1`.
- **A next link to another host** -- Graph sends none; `tests/Unit/Private/Invoke-OPIMGraphRequest.Tests.ps1`.

## Setup, once

The operator sets `OPIMLIVE_HOME` in both windows to the notes folder that holds the `OpimLive`
folder; no checklist holds that path. The test user's sign-in name and the test tenant's id are read
by the harness through OerLive and are never printed. Window B runs from the root of the step's
worktree, and its console output also goes to the file named in `OPIMLIVE_HOSTLOG`, where
`Connect-AzAccount` writes the Azure device code (OpimLive 1.0.2). Raw output goes to
`docs/live-verification/raw/opim-s15a` (git-ignored), which is deleted once the results are written
up. This step creates no object, so it has no prerequisite script; its one write as `oer-live-cc`
(decision A18) is check 0.1, which records the owners it found before it writes.

### S.1. Find the build under test and tie it to the branch head

- [ ] **S.1** Window B. The newest build in `output/module/Omnicit.PIM/` was made after the branch head was committed, and it holds this step's helpers.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$HeadTime = [datetimeoffset]::Parse((git log -1 --format=%cI))
$Psm1 = Join-Path $Built.DirectoryName 'Omnicit.PIM.psm1'
"Branch head: $(git log -1 --format='%h %s')"
"Built version folder: $($Built.Directory.Name)"
"Built after the branch head was committed: $([datetimeoffset]$Built.LastWriteTime -gt $HeadTime)"
"Tracked changes in the working tree: $(@(git status --porcelain --untracked-files=no).Count)"
"The built module reads a request status in one place: $([bool](Select-String -LiteralPath $Psm1 -Pattern 'function Get-OPIMRequestOutcome' -SimpleMatch -Quiet))"
"The built module reads a service time as UTC: $([bool](Select-String -LiteralPath $Psm1 -Pattern 'function ConvertTo-OPIMUtcDateTime' -SimpleMatch -Quiet))"
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
on the host log -- the Azure code cannot be completed; set it before 0.2.

Result:

### S.3. The fixture is in place, and this step has no object of its own

- [ ] **S.3** Window A, as `oer-live-cc`. The fixture's user and group exist, and no object carries the prefix `opim-s15a-`.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$null = Import-OerLiveConfig -Prefix 'opim-s15a-'
Connect-OerLive -Graph
"Objects with the prefix opim-s15a-: $(@(Find-OerLivePrefixed -Prefix 'opim-s15a-' -ThrowOnUnread -Quiet).Count)"
"Objects with the prefix opim-s1- (the fixture): $(@(Find-OerLivePrefixed -Prefix 'opim-s1-' -ThrowOnUnread -Quiet).Count)"
Disconnect-OerLive
```

**Expect:** every identity check line of `oer-live-cc` `True`; `opim-s15a-: 0`; `opim-s1-: 2` (the
user and the group; the resource groups are not directory objects).
**Failure looks like:** a 401 or 403 -- STOP (G6). Another count -- record each object by name and
STOP: the fixture is not the one this file assumes. A throw on an unread collection is a failed read,
never a `0`.

Result:

### 0. Preparation

### 0.1. `oer-live-cc` becomes a permanent owner of the fixture group (A18)

- [ ] **0.1** Window A, as `oer-live-cc`. Its own service principal is an owner of `opim-s1-grp`, so the test user is no longer the group's only owner.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'opim-s15a-'
Connect-OerLive -Graph
$GroupName = 'opim-s1-grp'
Assert-OerLivePrefix -Name $GroupName -Prefix 'opim-s1-'
$Read = Invoke-OerLiveGraph -Uri ("v1.0/groups?`$filter=displayName eq '{0}'&`$select=id,displayName" -f $GroupName)
Assert-OerLiveOk -Response $Read -Activity 'read the fixture group'
$Groups = @($Read.Body.value)
if ($Groups.Count -ne 1) { throw "STOP: expected one group named $GroupName, found $($Groups.Count)." }
Assert-OerLivePrefix -Name $Groups[0].displayName -Prefix 'opim-s1-'
$Sp = Invoke-OerLiveGraph -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $Cfg.AppId)
Assert-OerLiveOk -Response $Sp -Activity 'read the service principal of oer-live-cc'
$OwnersUri = "v1.0/groups/$($Groups[0].id)/owners?`$select=id"
$Before = Invoke-OerLiveGraph -Uri $OwnersUri -All
Assert-OerLiveOk -Response $Before -Activity 'read the owners of the fixture group'
$WasOwner = [bool](@($Before.Body.value) | Where-Object { $_.id -eq $Sp.Body.id })
Save-OerLiveBaseline -Name 'a18-owners' -Data @{ OwnerCount = @($Before.Body.value).Count; IdentityWasOwner = $WasOwner }
"Owners before: $(@($Before.Body.value).Count); oer-live-cc was an owner before: $WasOwner"
if (-not $WasOwner) {
    $Add = Invoke-OerLiveGraph -Method POST -Uri "v1.0/groups/$($Groups[0].id)/owners/`$ref" -Body @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($Sp.Body.id)" }
    Assert-OerLiveOk -Response $Add -Activity 'add oer-live-cc as an owner of the fixture group'
    "Owner added: $($Add.Ok)"
}
$IsOwner = $false
foreach ($Try in 1..6) {
    $After = Invoke-OerLiveGraph -Uri $OwnersUri -All
    Assert-OerLiveOk -Response $After -Activity 'read the owners of the fixture group again'
    $IsOwner = [bool](@($After.Body.value) | Where-Object { $_.id -eq $Sp.Body.id })
    if ($IsOwner) { break }
    Start-Sleep -Seconds 10
}
"Owners after: $(@($After.Body.value).Count); oer-live-cc is an owner: $IsOwner"
Disconnect-OerLive
```

**Expect:** every identity line `True`; `Owners before: 1` (the test user, whose ownership step 4
activated) and `oer-live-cc was an owner before: False`; `Owner added: True`; `Owners after: 2`;
`oer-live-cc is an owner: True`.
**Record:** the owner count before, if it is not 1 (the ownership may have ended since step 4).
**Failure looks like:** a 401 or 403 -- STOP (G6, a missing permission is never worked around). A
`STOP` from the prefix check -- STOP.

Result:

### 0.2. Identity check, Graph and Azure

- [ ] **0.2** Window B. `Connect-OpimLiveUser -IncludeARM` signs the module in to Graph and Azure with one device code each; the account is the test user and the tenant the test tenant.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
Import-Module (Join-Path $env:OPIMLIVE_HOME 'OpimLive/OpimLive.psm1') -Force
$Target = Get-OpimLiveTarget
$Sign = Connect-OpimLiveUser -IncludeARM -RawFolder 'docs/live-verification/raw/opim-s15a'
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

### 0.3. The ownership left from step 4 can now be deactivated (A18)

- [ ] **0.3** Window B. `Disable-OPIMEntraIDGroup 'opim-s1-grp' -AccessType Owner` deactivates the test user's ownership now that the group has a second owner; the request is reported by its status.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Owner = { @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'owner' }).Count }
"Active ownership rows before: $(& $Owner) at $((Get-Date -AsUTC).ToString('HH:mm:ss')) UTC"
$W = $null; $E = $null
$Out = @(Disable-OPIMEntraIDGroup 'opim-s1-grp' -AccessType Owner -WarningVariable W -WarningAction SilentlyContinue -ErrorVariable E -ErrorAction SilentlyContinue)
"Deactivation: output $($Out.Count); status $(@($Out.status) -join ','); accessId $(@($Out.accessId) -join ','); warnings $(@($W).Count); errors $(@($E).Count), the last $(@($E)[-1].FullyQualifiedErrorId)"
Start-Sleep -Seconds 45
"Active ownership rows 45 s later: $(& $Owner)"
```

**Expect:** `Active ownership rows before: 1`; `output 1; status Revoked; accessId owner; warnings 0;
errors 0`; `Active ownership rows 45 s later: 0`.
**Record:** if the ownership had already ended (`before: 0`), the call's outcome: a non-terminating
`ActiveRoleNotFound` is then a pass, and the ownership's deactivation is shown in 1.2 instead.
**Failure looks like:** `CannotDeleteLastAdminAssignment` -- 0.1 did not take effect; STOP.

Result:

### 0.4. Nothing is active, and the listings give the fixture

- [ ] **0.4** Window B. Before section 1 the test user holds no active assignment, and the three listings give step 2's counts.

```powershell
"Eligible: directory $(@(Get-OPIMDirectoryRole -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -ErrorAction Stop).Count)"
"Active: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** `Eligible: directory 2, group 2, Azure 2`; `Active: directory 0, group 0, Azure 0`.
**Failure looks like:** an active row -- record it and wait for it to end before section 1. Another
eligible count -- STOP: the fixture is not the one this file assumes.

Result:

### 1. Every wait ends, with the final status written back

The justification in every activation is `opim-s15a live verification`. Each check activates once
and then repeats the same call (G8).

### 1.1. A directory role through Wait-OPIMDirectoryRole, then the same call again

- [ ] **1.1** Window B. `Enable-OPIMDirectoryRole 'Usage Summary Reports Reader' | Wait-OPIMDirectoryRole -PassThru` ends with the role active and `Provisioned` written back on the request; the second call sends no request.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Name = 'Usage Summary Reports Reader'
$RequestsUri = "v1.0/roleManagement/directory/roleAssignmentScheduleRequests/filterByCurrentUser(on='principal')"
$Requests = { @((& (Get-Module Omnicit.PIM) { param($U) Invoke-OPIMGraphRequest -Uri $U -All } $RequestsUri).value).Count }
$Watch = [System.Diagnostics.Stopwatch]::StartNew()
$W1 = $null; $W2 = $null
$Request = @(Enable-OPIMDirectoryRole $Name -Justification 'opim-s15a live verification' -Hours 1 -WarningVariable W1 -WarningAction SilentlyContinue -ErrorAction Stop)
$AtRequest = [string]$Request[0].status
$Done = @($Request | Wait-OPIMDirectoryRole -PassThru -NoSummary -TimeoutSeconds 300 -WarningVariable W2 -WarningAction SilentlyContinue -ErrorAction Stop)
$Watch.Stop()
"Enable: output $($Request.Count); status in the answer $AtRequest; warnings $(@($W1).Count)"
"Wait: status on the request afterwards $($Request[0].status); PassThru $($Done.Count) row(s), an active instance: $(@($Done | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.DirectoryAssignmentScheduleInstance' }).Count -eq 1); warnings $(@($W2).Count)"
"Seconds from the request to done: $([int]$Watch.Elapsed.TotalSeconds)"
$Before = & $Requests
$W3 = $null; $E3 = $null
$Second = @(Enable-OPIMDirectoryRole $Name -Justification 'opim-s15a live verification' -Hours 1 -WarningVariable W3 -WarningAction SilentlyContinue -ErrorVariable E3 -ErrorAction SilentlyContinue)
"Second (G8): output $($Second.Count); warnings $(@($W3).Count), says already active: $([bool](@($W3) -match 'is already active')); errors $(@($E3).Count); requests sent: $((& $Requests) - $Before)"
"Active rows of the role: $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq $Name }).Count)"
```

**Expect:** `Enable: output 1`; `Wait: status on the request afterwards Provisioned; PassThru 1
row(s), an active instance: True`; `Second (G8): output 0; warnings 1, says already active: True;
errors 0; requests sent: 0`; `Active rows of the role: 1`.
**Record:** the status in the answer (`Provisioned`, or `PendingProvisioning` with one warning) and
the seconds to done.
**Failure looks like:** a timeout (`ActivationWaitTimedOut`) or a status other than `Provisioned`
written back -- record it; `requests sent: 1` -- the guard did not see the active role: STOP and
record.

Result:

### 1.2. The group membership with -Wait, then the same call again

- [ ] **1.2** Window B. `Enable-OPIMEntraIDGroup 'opim-s1-grp' -Wait` returns the membership with its final status `Provisioned`; once the listing shows it, the same call sends no request.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$RequestsUri = "v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests/filterByCurrentUser(on='principal')"
$Requests = { @((& (Get-Module Omnicit.PIM) { param($U) Invoke-OPIMGraphRequest -Uri $U -All } $RequestsUri).value).Count }
$Member = { @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'member' }).Count }
$Watch = [System.Diagnostics.Stopwatch]::StartNew()
$W1 = $null
$First = @(Enable-OPIMEntraIDGroup 'opim-s1-grp' -Wait -Hours 1 -Justification 'opim-s15a live verification' -WarningVariable W1 -WarningAction SilentlyContinue -ErrorAction Stop)
$Watch.Stop()
$Again = & (Get-Module Omnicit.PIM) { param($Id) Invoke-OPIMGraphRequest -Uri "v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests/$Id" } $First[0].id
"First: output $($First.Count); status returned $($First[0].status); accessId $($First[0].accessId); warnings $(@($W1).Count); seconds $([int]$Watch.Elapsed.TotalSeconds)"
"The returned status is the request's status read again: $([string]::Equals([string]$First[0].status, [string]$Again.status, [System.StringComparison]::OrdinalIgnoreCase))"
$Seen = 0
foreach ($Try in 1..12) { $Seen = & $Member; if ($Seen -ge 1) { break }; Start-Sleep -Seconds 10 }
"The listing shows the membership after about $(($Try - 1) * 10) s: $($Seen -ge 1)"
$Before = & $Requests
$W2 = $null; $E2 = $null
$Second = @(Enable-OPIMEntraIDGroup 'opim-s1-grp' -Hours 1 -Justification 'opim-s15a live verification' -WarningVariable W2 -WarningAction SilentlyContinue -ErrorVariable E2 -ErrorAction SilentlyContinue)
"Second (G8): output $($Second.Count); warnings $(@($W2).Count), says already active: $([bool](@($W2) -match 'is already active')); errors $(@($E2).Count); requests sent: $((& $Requests) - $Before)"
```

**Expect:** `First: output 1; status returned Provisioned; accessId member; warnings 0`; `The
returned status is the request's status read again: True`; the listing shows the membership;
`Second (G8): output 0; warnings 1, says already active: True; errors 0; requests sent: 0`.
**Record:** the seconds to done (step 2: `-Wait` came back after 13 s with `PendingProvisioning`, the
request's early status, OPIM-14), and how long the listing took to show the membership.
**Failure looks like:** `status returned PendingProvisioning` with no warning, or `requests sent: 1`
-- STOP and record.

Result:

### 1.3. Reader on opim-s1-rg with -Wait, then the same call again

- [ ] **1.3** Window B. `Enable-OPIMAzureRole 'Reader' -Scope <opim-s1-rg> -Wait` returns the activation with status `Provisioned`; the same call sends no request.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Rg = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg' })
if ($Rg.Count -ne 1) { throw "Expected one Reader eligibility on opim-s1-rg, found $($Rg.Count)." }
$Scope = $Rg[0].ScopeId
$Requests = { @(Get-AzRoleAssignmentScheduleRequest -Scope $Scope -Filter 'asRequestor()' -ErrorAction Stop).Count }
$Watch = [System.Diagnostics.Stopwatch]::StartNew()
$W1 = $null
$First = @(Enable-OPIMAzureRole 'Reader' -Scope $Scope -Wait -Hours 1 -Justification 'opim-s15a live verification' -WarningVariable W1 -WarningAction SilentlyContinue -ErrorAction Stop)
$Watch.Stop()
"First: output $($First.Count); status $($First[0].Status); warnings $(@($W1).Count); seconds $([int]$Watch.Elapsed.TotalSeconds)"
$Seen = 0
foreach ($Try in 1..12) { $Seen = @(Get-OPIMAzureRole -Activated -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg' }).Count; if ($Seen -ge 1) { break }; Start-Sleep -Seconds 10 }
"The listing shows the activation after about $(($Try - 1) * 10) s: $($Seen -ge 1)"
$Before = & $Requests
$W2 = $null; $E2 = $null
$Second = @(Enable-OPIMAzureRole 'Reader' -Scope $Scope -Hours 1 -Justification 'opim-s15a live verification' -WarningVariable W2 -WarningAction SilentlyContinue -ErrorVariable E2 -ErrorAction SilentlyContinue)
"Second (G8): output $($Second.Count); warnings $(@($W2).Count), says already active: $([bool](@($W2) -match 'is already active')); errors $(@($E2).Count); requests sent: $((& $Requests) - $Before)"
```

**Expect:** `First: output 1; status Provisioned; warnings 0`; the listing shows the activation;
`Second (G8): output 0; warnings 1, says already active: True; errors 0; requests sent: 0` -- which
also shows that the eligibility and the active instance carry the same role definition id form.
**Record:** the seconds; whether the answer was already `Provisioned` (then no poll was needed, and
the poll with `asRequestor()` stays class B).
**Failure looks like:** `requests sent: 1` -- the Azure guard did not match the active instance:
STOP and record the two id forms by shape only (never the ids).

Result:

### 2. A repeated request for an active membership (OPIM-39, measured first)

### 2.1. One repeated activation request sent past the module, then ten minutes of watching

- [ ] **2.1** Window B. A second `selfActivate` request for the active membership, sent with the module's transport but past its guard, is answered; the membership is watched for ten minutes.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Grp = @(Get-OPIMEntraIDGroup -AccessType member -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' })
if ($Grp.Count -ne 1) { throw "Expected one eligible membership of opim-s1-grp, found $($Grp.Count)." }
$Member = { @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'member' }).Count }
"Active membership rows before the repeated request: $(& $Member) at $((Get-Date -AsUTC).ToString('HH:mm:ss')) UTC"
$Body = @{
    action = 'selfActivate'; accessId = 'member'; groupId = $Grp[0].groupId; principalId = $Grp[0].principalId
    justification = 'opim-s15a OPIM-39 measurement'
    scheduleInfo = @{ startDateTime = (Get-Date -AsUTC).ToString('o'); expiration = @{ type = 'AfterDuration'; duration = 'PT1H' } }
}
try {
    $R = & (Get-Module Omnicit.PIM) { param($B) Invoke-OPIMGraphRequest -Method POST -Uri 'v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests' -Body $B } $Body
    "Repeated request: accepted, status $($R.status)"
} catch {
    "Repeated request: refused, $($PSItem.FullyQualifiedErrorId)"
}
$Start = Get-Date -AsUTC
foreach ($Minute in 1..10) {
    Start-Sleep -Seconds 60
    "After $([int]((Get-Date -AsUTC) - $Start).TotalSeconds) s: active membership rows $(& $Member)"
}
```

**Record:** Graph's answer to the repeated request (step 2: `Failed` with `RoleAssignmentExists`),
and the active membership rows each minute. A membership that disappears confirms OPIM-39: the guard
of 1.2 is then what keeps the module's own calls from causing it.
**Failure looks like:** the block itself failing before the request -- record and rerun once.

Result:

### 2.2. The test user is still a member, read as `oer-live-cc`

- [ ] **2.2** Window A, as `oer-live-cc`. After 2.1's ten minutes, the group's member list still holds the test user.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'opim-s15a-'
Connect-OerLive -Graph
$Read = Invoke-OerLiveGraph -Uri "v1.0/groups?`$filter=displayName eq 'opim-s1-grp'&`$select=id"
Assert-OerLiveOk -Response $Read -Activity 'read the fixture group'
$User = Invoke-OerLiveGraph -Uri ("v1.0/users/{0}?`$select=id" -f [uri]::EscapeDataString("opim-s1-live-user@$($Cfg.UserDomain)"))
Assert-OerLiveOk -Response $User -Activity 'read the test user'
$Members = Invoke-OerLiveGraph -Uri "v1.0/groups/$(@($Read.Body.value)[0].id)/members?`$select=id" -All
Assert-OerLiveOk -Response $Members -Activity 'read the members of the fixture group'
"The test user is a member of opim-s1-grp: $([bool](@($Members.Body.value) | Where-Object { $_.id -eq $User.Body.id })) at $((Get-Date -AsUTC).ToString('HH:mm:ss')) UTC"
Disconnect-OerLive
```

**Record:** True or False. `False` while 1.2's membership should still run is OPIM-39 confirmed.
**Failure looks like:** a 401 or 403 -- STOP (G6).

Result:

### 3. A start in the future (OPIM-15 and OPIM-18)

The start is written as local time without an offset, the form step 2 measured as a 400
`InvalidRoleAssignmentRequest`. Each activation names the role twice in one call.

### 3.1. A directory role from ten minutes ahead, named twice in one call

- [ ] **3.1** Window B. `Enable-OPIMDirectoryRole 'Message Center Privacy Reader', 'Message Center Privacy Reader' -NotBefore <local time in 10 minutes>` sends one request, answered `ScheduleCreated` with the right start in UTC and reported as a success.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Name = 'Message Center Privacy Reader'
$StartText = (Get-Date).AddMinutes(10).ToString('yyyy-MM-dd HH:mm:ss')
$Expected = [datetime]::ParseExact($StartText, 'yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture).ToUniversalTime()
$W = $null; $E = $null
$Out = @(Enable-OPIMDirectoryRole $Name, $Name -NotBefore $StartText -Hours 1 -Justification 'opim-s15a live verification' -WarningVariable W -WarningAction SilentlyContinue -ErrorVariable E -ErrorAction SilentlyContinue)
$global:OpimS15aDirectoryScheduled = @($Out | ForEach-Object { $_.id })
$Sent = & (Get-Module Omnicit.PIM) { param($V) ConvertTo-OPIMUtcDateTime -Value $V } $Out[0].scheduleInfo.startDateTime
"Output $($Out.Count); status $(@($Out.status) -join ','); warnings $(@($W).Count), says already requested by this command: $([bool](@($W) -match 'already requested by this command')); errors $(@($E).Count)"
"The start is the local time given, in UTC: $([math]::Abs(($Sent - $Expected).TotalSeconds) -le 1)"
"Active rows of the role now: $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq $Name }).Count)"
$W2 = $null; $E2 = $null
$Second = @(Enable-OPIMDirectoryRole $Name -NotBefore $StartText -Hours 1 -Justification 'opim-s15a live verification' -WarningVariable W2 -WarningAction SilentlyContinue -ErrorVariable E2 -ErrorAction SilentlyContinue)
$global:OpimS15aDirectoryScheduled += @($Second | ForEach-Object { $_.id })
"Second call (G8): output $($Second.Count); status $(@($Second.status) -join ','); warnings $(@($W2).Count); errors $(@($E2).Count), the last $(@($E2)[-1].FullyQualifiedErrorId)"
```

**Expect:** `Output 1; status ScheduleCreated; warnings 1, says already requested by this command:
True; errors 0`; `The start is the local time given, in UTC: True`; `Active rows of the role now:
0`.
**Record:** the second call's outcome (the role is not active yet, so the guard does not hold it):
Graph's refusal of a second schedule is a pass; a second accepted schedule is recorded and canceled
in 3.3.
**Failure looks like:** `InvalidRoleAssignmentRequest` (OPIM-18 not fixed) or an error for
`ScheduleCreated` -- STOP and record.

Result:

### 3.2. Reader on opim-s1-rg2 from ten minutes ahead, named twice in one call

- [ ] **3.2** Window B. `Enable-OPIMAzureRole 'Reader', 'Reader' -Scope <opim-s1-rg2> -NotBefore <local time in 10 minutes>` sends one request, answered `ScheduleCreated` with the right start, and reported as a success.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Rg2 = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg2' })
if ($Rg2.Count -ne 1) { throw "Expected one Reader eligibility on opim-s1-rg2, found $($Rg2.Count)." }
$StartText = (Get-Date).AddMinutes(10).ToString('yyyy-MM-dd HH:mm:ss')
$Expected = [datetime]::ParseExact($StartText, 'yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture).ToUniversalTime()
$W = $null; $E = $null
$Out = @(Enable-OPIMAzureRole 'Reader', 'Reader' -Scope $Rg2[0].ScopeId -NotBefore $StartText -Hours 1 -Justification 'opim-s15a live verification' -WarningVariable W -WarningAction SilentlyContinue -ErrorVariable E -ErrorAction SilentlyContinue)
$global:OpimS15aAzureScheduled = @($Out | ForEach-Object { @{ Name = $_.Name; Scope = $_.Scope } })
"Output $($Out.Count); status $(@($Out.Status) -join ','); warnings $(@($W).Count), says already requested by this command: $([bool](@($W) -match 'already requested by this command')); errors $(@($E).Count)"
"The start is the local time given, in UTC: $([math]::Abs(([datetime]$Out[0].ScheduleInfoStartDateTime).ToUniversalTime().Subtract($Expected).TotalSeconds) -le 1)"
"Active Reader rows on opim-s1-rg2 now: $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg2' }).Count)"
$W2 = $null; $E2 = $null
$Second = @(Enable-OPIMAzureRole 'Reader' -Scope $Rg2[0].ScopeId -NotBefore $StartText -Hours 1 -Justification 'opim-s15a live verification' -WarningVariable W2 -WarningAction SilentlyContinue -ErrorVariable E2 -ErrorAction SilentlyContinue)
$global:OpimS15aAzureScheduled += @($Second | ForEach-Object { @{ Name = $_.Name; Scope = $_.Scope } })
"Second call (G8): output $($Second.Count); status $(@($Second.Status) -join ','); warnings $(@($W2).Count); errors $(@($E2).Count), the last $(@($E2)[-1].FullyQualifiedErrorId)"
```

**Expect:** `Output 1; status ScheduleCreated; warnings 1, says already requested by this command:
True; errors 0`; `The start is the local time given, in UTC: True`; `Active Reader rows on
opim-s1-rg2 now: 0`.
**Record:** the second call's outcome, as in 3.1; and the start ARM echoes, if it differs by more
than a second.
**Failure looks like:** `ScheduleCreated` written as an error, or an activation that starts now
(`Provisioned`) -- STOP: `-NotBefore` did not reach ARM (OPIM-15).

Result:

### 3.3. The scheduled requests are canceled, so nothing becomes active

- [ ] **3.3** Window B. Each request of 3.1 and 3.2 is canceled before its start, and no schedule for those roles is left.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
foreach ($Id in @($global:OpimS15aDirectoryScheduled)) {
    try {
        $null = & (Get-Module Omnicit.PIM) { param($I) Invoke-OPIMGraphRequest -Method POST -Uri "v1.0/roleManagement/directory/roleAssignmentScheduleRequests/$I/cancel" } $Id
        "Directory request: cancel accepted"
    } catch { "Directory request: cancel refused, $($PSItem.FullyQualifiedErrorId)" }
}
foreach ($Req in @($global:OpimS15aAzureScheduled)) {
    try {
        Stop-AzRoleAssignmentScheduleRequest -Name $Req.Name -Scope $Req.Scope -ErrorAction Stop
        "Azure request: cancel accepted"
    } catch { "Azure request: cancel refused, $($PSItem.FullyQualifiedErrorId)" }
}
Start-Sleep -Seconds 30
$DirSchedules = @((& (Get-Module Omnicit.PIM) { Invoke-OPIMGraphRequest -Uri "v1.0/roleManagement/directory/roleAssignmentSchedules/filterByCurrentUser(on='principal')?`$expand=roleDefinition" -All }).value |
        Where-Object { $_.roleDefinition.displayName -eq 'Message Center Privacy Reader' })
$AzSchedules = @(Get-AzRoleAssignmentSchedule -Scope '/' -Filter 'asTarget()' -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg2' })
"Directory schedules left for Message Center Privacy Reader: $($DirSchedules.Count); Azure schedules left for Reader on opim-s1-rg2: $($AzSchedules.Count) at $((Get-Date -AsUTC).ToString('HH:mm:ss')) UTC"
```

**Expect:** each cancel accepted; `Directory schedules left ...: 0; Azure schedules left ...: 0`.
**Record:** a refused cancel, with its error id. A schedule that stays then becomes active at its
start and is deactivated in section 7 after the five-minute rule; say so on the result line.
**Failure looks like:** a schedule left with no record of why -- STOP: it would activate.

Result:

### 4. -Activated lists the activations of this file, and only activations

### 4.1. The counts, and the assignment type Graph reports

- [ ] **4.1** Window B. `-Activated` gives exactly the activations sections 1 and 2 made, and every raw instance carries the assignment type `Activated`.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$RawDirectory = @((& (Get-Module Omnicit.PIM) { Invoke-OPIMGraphRequest -Uri "v1.0/roleManagement/directory/roleAssignmentScheduleInstances/filterByCurrentUser(on='principal')" -All }).value)
$RawGroup = @((& (Get-Module Omnicit.PIM) { Invoke-OPIMGraphRequest -Uri "v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleInstances/filterByCurrentUser(on='principal')" -All }).value)
"Raw instances: directory $($RawDirectory.Count) with assignmentType $((@($RawDirectory | ForEach-Object { [string]$_.assignmentType }) | Sort-Object -Unique) -join ','); group $($RawGroup.Count) with assignmentType $((@($RawGroup | ForEach-Object { [string]$_.assignmentType }) | Sort-Object -Unique) -join ',')"
"-Activated: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** `Raw instances: directory 1 with assignmentType Activated; group 1 with assignmentType
activated` (any letter case); `-Activated: directory 1, group 1, Azure 1` -- the activations of 1.1,
1.2 and 1.3, and no more.
**Failure looks like:** an empty or other assignment type on a raw instance, or an `-Activated`
count below the raw one -- STOP: the filter of `-Activated` drops a real activation (the 0.x
changelog records that this filter was removed once for that reason).

Result:

### 5. -Hours outside 1 to 24 is refused before anything is sent

### 5.1. -Hours 0 and 25 on the three Enable cmdlets

- [ ] **5.1** Window B. `-Hours 0` and `-Hours 25` end at parameter binding on all three Enable cmdlets, and no request is sent.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Rg2 = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg2' })[0]
$Count = {
    @((& (Get-Module Omnicit.PIM) { Invoke-OPIMGraphRequest -Uri "v1.0/roleManagement/directory/roleAssignmentScheduleRequests/filterByCurrentUser(on='principal')" -All }).value).Count +
    @((& (Get-Module Omnicit.PIM) { Invoke-OPIMGraphRequest -Uri "v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests/filterByCurrentUser(on='principal')" -All }).value).Count +
    @(Get-AzRoleAssignmentScheduleRequest -Scope $Rg2.ScopeId -Filter 'asRequestor()' -ErrorAction Stop).Count
}
$Before = & $Count
$Ids = foreach ($Hours in 0, 25) {
    foreach ($Call in @(
            { Enable-OPIMDirectoryRole 'Message Center Privacy Reader' -Hours $Hours -ErrorAction Stop }
            { Enable-OPIMEntraIDGroup 'opim-s1-grp' -AccessType Owner -Hours $Hours -ErrorAction Stop }
            { Enable-OPIMAzureRole 'Reader' -Scope $Rg2.ScopeId -Hours $Hours -ErrorAction Stop })) {
        try { $null = & $Call; 'no error' } catch { $PSItem.FullyQualifiedErrorId }
    }
}
"Error ids: $($Ids -join '; ')"
"Requests sent: $((& $Count) - $Before)"
```

**Expect:** six times `ParameterArgumentValidationError,` followed by the cmdlet's name;
`Requests sent: 0`.
**Failure looks like:** `no error`, or `Requests sent` above 0 -- STOP: a request with an invalid
duration went out.

Result:

### 6. The five-minute rule

### 6.1. Five minutes have passed since the last activation

- [ ] **6.1** Window B. At least five minutes have passed since 1.3's activation.

```powershell
"Now: $((Get-Date -AsUTC).ToString('HH:mm:ss')) UTC"
```

**Expect:** a time at least five minutes after 1.3's result line.
**Failure looks like:** less -- wait, and run the block again.

Result:

### 7. Deactivation, each twice (G8 and OPIM-24)

### 7.1. The directory role

- [ ] **7.1** Window B. `Disable-OPIMDirectoryRole 'Usage Summary Reports Reader'` is reported `Revoked`; the second call is a non-terminating `ActiveRoleNotFound`.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
foreach ($Try in 1, 2) {
    $W = $null; $E = $null; $Reached = $false
    try { $Out = @(Disable-OPIMDirectoryRole 'Usage Summary Reports Reader' -WarningVariable W -WarningAction SilentlyContinue -ErrorVariable E -ErrorAction SilentlyContinue); $Reached = $true } catch { $E = @($E) + $PSItem; $Out = @() }
    "Call ${Try}: output $($Out.Count) status $(@($Out.status) -join ','); warnings $(@($W).Count); errors $(@($E).Count), the last $(@($E)[-1].FullyQualifiedErrorId); non-terminating: $Reached"
}
"Active directory roles after: $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** call 1 `output 1 status Revoked; warnings 0; errors 0`; call 2 `output 0`, the last error
`ActiveRoleNotFound,Disable-OPIMDirectoryRole`, `non-terminating: True`; `Active directory roles
after: 0`.
**Failure looks like:** `ActiveDurationTooShort` -- wait and run again; an `ActivationRequestFailed`
for `Revoked` -- STOP: a deactivation's success is reported as a failure.

Result:

### 7.2. The group membership

- [ ] **7.2** Window B. `Disable-OPIMEntraIDGroup 'opim-s1-grp'` is reported `Revoked`; once the listing has caught up, the second call is a non-terminating `ActiveRoleNotFound`.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
foreach ($Try in 1, 2) {
    if ($Try -eq 2) { Start-Sleep -Seconds 45 }
    $W = $null; $E = $null; $Reached = $false
    try { $Out = @(Disable-OPIMEntraIDGroup 'opim-s1-grp' -WarningVariable W -WarningAction SilentlyContinue -ErrorVariable E -ErrorAction SilentlyContinue); $Reached = $true } catch { $E = @($E) + $PSItem; $Out = @() }
    "Call ${Try}: output $($Out.Count) status $(@($Out.status) -join ',') accessId $(@($Out.accessId) -join ','); warnings $(@($W).Count); errors $(@($E).Count), the last $(@($E)[-1].FullyQualifiedErrorId); non-terminating: $Reached"
}
"Active group assignments after: $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count)"
```

**Expect:** call 1 `output 1 status Revoked accessId member; warnings 0; errors 0`; call 2 `output
0`, the last error `ActiveRoleNotFound,Disable-OPIMEntraIDGroup`, `non-terminating: True`; `Active
group assignments after: 0`.
**Record:** a `BadRequest` on call 2 if the listing still lagged after 45 s (OPIM-50).

Result:

### 7.3. Reader on opim-s1-rg, with no linked eligibility (OPIM-24)

- [ ] **7.3** Window B. `Disable-OPIMAzureRole 'Reader' -Scope <opim-s1-rg>`, which now names no eligibility, is reported `Revoked`; the second call is a non-terminating `ActiveRoleNotFound`.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Rg = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg' })[0]
foreach ($Try in 1, 2) {
    $W = $null; $E = $null; $Reached = $false
    try { $Out = @(Disable-OPIMAzureRole 'Reader' -Scope $Rg.ScopeId -WarningVariable W -WarningAction SilentlyContinue -ErrorVariable E -ErrorAction SilentlyContinue); $Reached = $true } catch { $E = @($E) + $PSItem; $Out = @() }
    "Call ${Try}: output $($Out.Count) status $(@($Out.Status) -join ','); the answer names a linked eligibility: $(@($Out | Where-Object { $_.LinkedRoleEligibilityScheduleId }).Count -gt 0); warnings $(@($W).Count); errors $(@($E).Count), the last $(@($E)[-1].FullyQualifiedErrorId); non-terminating: $Reached"
}
"Active Azure roles after: $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** call 1 `output 1 status Revoked`; call 2 `output 0`, the last error
`ActiveRoleNotFound,Disable-OPIMAzureRole`, `non-terminating: True`; `Active Azure roles after: 0`.
**Record:** whether ARM's answer names a linked eligibility of its own (the request sent none).
**Failure looks like:** an ARM error that asks for the linked eligibility -- record the error id and
STOP: Ruling P6's fallback (send the instance's own linked eligibility id) is then the fix.

Result:

## Teardown

This step created no object, so there is no prerequisite script to run. Its one write, `oer-live-cc`
as a permanent owner of `opim-s1-grp` (0.1, decision A18), stays on purpose: step 5b deletes the group
with all its owners. Every activation above was deactivated or canceled; the checks below read that
back.

### T.1. No object with the step's prefix, and the fixture as it was

- [ ] **T.1** Window A, as `oer-live-cc`. No object carries the prefix `opim-s15a-`, the fixture still has its two directory objects, and `oer-live-cc` is still an owner of `opim-s1-grp`.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'opim-s15a-'
Connect-OerLive -Graph
"Objects with the prefix opim-s15a-: $(@(Find-OerLivePrefixed -Prefix 'opim-s15a-' -ThrowOnUnread -Quiet).Count)"
"Objects with the prefix opim-s1- (the fixture): $(@(Find-OerLivePrefixed -Prefix 'opim-s1-' -ThrowOnUnread -Quiet).Count)"
$Read = Invoke-OerLiveGraph -Uri "v1.0/groups?`$filter=displayName eq 'opim-s1-grp'&`$select=id"
Assert-OerLiveOk -Response $Read -Activity 'read the fixture group'
$Sp = Invoke-OerLiveGraph -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $Cfg.AppId)
Assert-OerLiveOk -Response $Sp -Activity 'read the service principal of oer-live-cc'
$Owners = Invoke-OerLiveGraph -Uri "v1.0/groups/$(@($Read.Body.value)[0].id)/owners?`$select=id" -All
Assert-OerLiveOk -Response $Owners -Activity 'read the owners of the fixture group'
"Owners of opim-s1-grp: $(@($Owners.Body.value).Count); oer-live-cc is one of them: $([bool](@($Owners.Body.value) | Where-Object { $_.id -eq $Sp.Body.id }))"
Disconnect-OerLive
```

**Expect:** `opim-s15a-: 0`; `opim-s1-: 2`; `Owners of opim-s1-grp: 1; oer-live-cc is one of them:
True` (the test user's ownership was deactivated in 0.3).
**Failure looks like:** an `opim-s15a-` object -- record it by name; a 401 or 403 -- STOP (G6).

Result:

### T.2. Nothing active or scheduled, and window B signed out

- [ ] **T.2** Window B. No directory role, group assignment or Azure role of the test user is active or scheduled, and the window signs out.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
"Active directory roles: $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count)"
"Active group assignments: $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count)"
"Active Azure roles: $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
$DirectorySchedules = @((& (Get-Module Omnicit.PIM) { Invoke-OPIMGraphRequest -Uri "v1.0/roleManagement/directory/roleAssignmentSchedules/filterByCurrentUser(on='principal')" -All }).value)
$GroupSchedules = @((& (Get-Module Omnicit.PIM) { Invoke-OPIMGraphRequest -Uri "v1.0/identityGovernance/privilegedAccess/group/assignmentSchedules/filterByCurrentUser(on='principal')" -All }).value)
$AzureSchedules = @(Get-AzRoleAssignmentSchedule -Scope '/' -Filter 'asTarget()' -ErrorAction Stop | Where-Object { $_.ScopeDisplayName -like 'opim-s1-*' })
"Schedules (active or future): directory $($DirectorySchedules.Count), group $($GroupSchedules.Count), Azure on the fixture $($AzureSchedules.Count)"
Disconnect-OPIM
try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { $null = $PSItem }
try { Disconnect-AzAccount -ErrorAction Stop | Out-Null } catch { $null = $PSItem }
"Window B signed out: $($null -eq (Get-MgContext) -and $null -eq (& (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }))"
```

**Expect:** `0` on all three active counts; `Schedules (active or future): directory 0, group 0, Azure
on the fixture 0`; `Window B signed out: True`. Nothing is left in the tenant on purpose but the
fixture and 0.1's owner.
**Failure looks like:** another row -- record it, and deactivate or cancel it (after the five-minute
rule) before the step ends; a terminating error is a failed read, never a pass.

Result:
