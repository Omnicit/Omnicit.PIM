# Live verification checklist -- the module imports and signs in to Azure in a process that can find no Az module, and `pim` and `unpim` still serve all three kinds (feat/drop-az-dependencies)

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
eligibilities of) and `opim-s21b-` (this step's own objects, of which there are none). Check 0.1
proves the identity before any other check calls the module. If a browser window or a sign-in prompt
appears mid-run, STOP and run check 0.1 again: in this file every sign-in is a device code, and the
proof of 0.1 holds only for the sign-in it checked.

**Two windows, never one process** (decision A10 of Sprint 1, kept in Sprint 2). Window A runs as
`oer-live-cc`, and reads files without the module. Window B runs the branch's build as the test
user, in a `pwsh -NoProfile` whose module path holds only a folder of the step's own -- AzAuth,
Microsoft.Graph.Authentication and the two SecretStore modules the harness needs -- and PowerShell's
own modules: no Az module can be found or loaded there. Every block below names its window.

**No block prints a scope id, an object id, a tenant id or a message that holds one.** The blocks
print counts, statuses, error ids, display names of the fixture's roles, group and resource groups,
module names and versions, seconds and True/False.

## What changed and why this needs a live tenant

- **A. The module depends on AzAuth and Microsoft.Graph.Authentication, and on no Az module**
  ("feat: declare AzAuth and drop Az.Resources from the dependencies"). The manifest declares
  Microsoft.Graph.Authentication 2.36.0 and AzAuth 2.9.0 and no longer Az.Resources; the three
  `#requires -module Az.Resources` lines are gone; `RequiredModules.psd1` and the workflow's install
  loops follow. A unit test imports the build in a clean process, but it cannot show that the module
  signs in to Microsoft Graph and to Azure Resource Manager, and activates and deactivates all three
  kinds, in a process where no Az module can be found: AzAuth is now loaded at import, beside the
  MSAL that Microsoft.Graph.Authentication carries, before the first Graph sign-in.
- **B. PowerShell 7.4 is the floor** ("fix: require PowerShell 7.4 and mock Azure at the module's
  transport in the contributor guides"). Check S.3 records the window's version.
- **C. A gate refuses an Az call under `source/`, and the tripwire loses its Az names** ("test:
  refuse any Az call under source/ and take the Az names off the tripwire", "test: make every branch
  of the Az boundary gate fail when it is removed"). Test code only; no live effect.
- **D. The release notes and the documentation** ("docs: say in the release notes that the Az
  modules are no longer needed", "docs: describe the dependencies without the Az modules and AzAuth's
  process-wide credential", "docs: say which MSAL is found, why the floor is 7.4, and what the Az
  boundary can see", "docs: say AzAuth is a floor, what the Az boundary cannot read, and the measured
  gate"). No live effect.

The mapping to the step's specification: section 0 is its 0.x (a clean process with no Az module on
its module path signs in with `Connect-OPIM -DeviceCode -IncludeARM`, and no Az module is loaded
afterwards), section 1 its 1.x (`pim` and `unpim` for all three kinds from a tenant map, each twice
for G8).

The fixture of Sprint 2 (decision A15) is used as it stands and is not changed: the test user
`opim-s2-live-user`, the group `opim-s2-grp` (eligible as member), the resource groups `opim-s2-rg`
and `opim-s2-rg2` (Reader eligible on each), and the directory roles Usage Summary Reports Reader and
Message Center Privacy Reader. Section 1 activates Usage Summary Reports Reader, the membership of
`opim-s2-grp` and Reader on `opim-s2-rg`, and deactivates all three again before the end. This step
creates no object, so it has no prerequisite script of its own; the sprint's
`Initialize-OpimS2Prereq.ps1` is run with `-WhatIf` only.

## What this file does not check, and why

Class B, each proven by the tests named:

- **No Az call, and no Az module named in a string, a bareword or a `#requires` line, under
  `source/`, as far as a parser can see** -- `tests/QA/sourcehygiene.tests.ps1`, Describe 'Az
  boundary', with its known-answer positive control and its stated known limits.
- **The import in a clean process on Linux and macOS** -- `tests/QA/module.tests.ps1`, Describe
  'Runtime dependencies', It 'Should load no Az module when the build is imported in a clean
  process', which runs on all three legs of the workflow; the `package` job installs the dependencies
  the manifest declares and imports the package on Linux.
- **A refused import on PowerShell 7.2 or 7.3** -- PowerShell enforces the manifest's
  `PowerShellVersion`; this machine has PowerShell 7.6.6 only. `tests/QA/module.tests.ps1` pins the
  value (at least 7.4, and at least what every declared dependency requires).
- **`Install-Module Omnicit.PIM` from the PowerShell Gallery bringing AzAuth along** -- only the
  preview a merge publishes can show it; the `package` job rehearses the publish and the install
  from a local repository.
- **The interactive (browser) sign-in** -- every sign-in here is a device code;
  `tests/Unit/Private/Initialize-OPIMAuth.Tests.ps1` pins `-Interactive` outside device code mode.

## Setup, once

The operator sets `OPIMLIVE_HOME` in window B to the notes folder that holds the `OpimLive` folder,
and `OPIMLIVE_PREFIX` to `opim-s2-`; no checklist holds the path. The test user's sign-in name and
the test tenant's id are read by the harness through OerLive and are never printed. Both windows run
from the root of the step's worktree. Raw output, the step's module folder and the run's tenant map
go to `docs/live-verification/raw/opim-s21b` (git-ignored), which is deleted once the results are
written up.

A block that runs the module in window B starts with the three-line prologue of the template.

The PIM policies of the fixture's roles and group require a justification on activation (measured
in the fixture session), so every activation below passes one.

### S.1. Find the build under test and tie it to the branch head

- [ ] **S.1** Window A (no module). The newest build in `output/module/Omnicit.PIM/` was made after the branch head was committed, and its manifest declares AzAuth and Microsoft.Graph.Authentication, no Az module, and PowerShell 7.4.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$HeadTime = [datetimeoffset]::Parse((git log -1 --format=%cI))
"Branch head: $(git log -1 --format='%h %s')"
"Built version folder: $($Built.Directory.Name)"
"Built after the branch head was committed: $([datetimeoffset]$Built.LastWriteTime -gt $HeadTime)"
$Tracked = @(git status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0) { throw "git status exited with $LASTEXITCODE, so the working tree could not be read; repair the clone before any check below." }
"Tracked changes in the working tree: $($Tracked.Count)"
$Manifest = Import-PowerShellDataFile -LiteralPath $Built.FullName
"Declared dependencies: $(@($Manifest.RequiredModules | ForEach-Object { '{0} {1}' -f $_.ModuleName, $_.ModuleVersion } | Sort-Object) -join ', ')"
"PowerShellVersion: $($Manifest.PowerShellVersion)"
"A #requires line of the built module names an Az module: $([bool](Select-String -LiteralPath (Join-Path $Built.DirectoryName 'Omnicit.PIM.psm1') -Pattern '^\s*#requires\b.*\bAz(\.\w+)?\b' -Quiet))"
```

**Expect:** the branch head's hash and subject; the version folder; `Built after the branch head was
committed: True`; `Tracked changes in the working tree: 0`; `Declared dependencies: AzAuth 2.9.0,
Microsoft.Graph.Authentication 2.36.0`; `PowerShellVersion: 7.4`; the last line `False`.
**Failure looks like:** `False` on the second line or a tracked change -- build again before any
check below. Another dependency list -- the build is not this branch's: STOP.

Result:

### S.2. The step's module folder

- [ ] **S.2** Window A (no module). The raw folder is git-ignored, and the step's module folder holds AzAuth 2.9.0 and Microsoft.Graph.Authentication 2.36.0 from the build's own dependencies and the two SecretStore modules the harness needs, and no Az module.

```powershell
$Raw = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s21b'
$Modules = Join-Path $Raw 'modules'
$null = New-Item -ItemType Directory -Force -Path $Modules
git check-ignore -q $Raw
"The raw folder is git-ignored: $($LASTEXITCODE -eq 0)"
$Sources = @(
    (Resolve-Path 'output/RequiredModules/AzAuth/2.9.0').Path
    (Resolve-Path 'output/RequiredModules/Microsoft.Graph.Authentication/2.36.0').Path
    (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretManagement | Sort-Object Version -Descending | Select-Object -First 1).ModuleBase
    (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretStore | Sort-Object Version -Descending | Select-Object -First 1).ModuleBase
)
foreach ($Source in $Sources) {
    $Name = Split-Path -Leaf (Split-Path -Parent $Source)
    $Version = Split-Path -Leaf $Source
    $Target = Join-Path (Join-Path $Modules $Name) $Version
    if (-not (Test-Path -LiteralPath $Target)) {
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target)
        Copy-Item -LiteralPath $Source -Destination $Target -Recurse
    }
}
Get-ChildItem -LiteralPath $Modules -Directory | ForEach-Object { "$($_.Name) $((Get-ChildItem -LiteralPath $_.FullName -Directory | ForEach-Object Name) -join ', ')" }
"An Az module in the folder: $([bool](Get-ChildItem -LiteralPath $Modules -Directory | Where-Object { $_.Name -match '^Az(\.|$)' }))"
```

**Expect:** `True`; the four lines `AzAuth 2.9.0`, `Microsoft.Graph.Authentication 2.36.0`,
`Microsoft.PowerShell.SecretManagement 1.1.1`, `Microsoft.PowerShell.SecretStore 1.0.5`; `An Az
module in the folder: False`.
**Failure looks like:** `False` on the first line -- STOP: the copies would be tracked. A missing
dependency -- resolve the build's dependencies again (`./build.ps1 -ResolveDependency -Tasks noop
-UseModuleFast`) and run the block again.

Result:

### S.3. Window B finds no Az module

- [ ] **S.3** Window B, a fresh `pwsh -NoProfile`, before anything else runs in it. Its module path is the step's module folder and PowerShell's own modules only; no Az module can be found or is loaded; PowerShell is 7.4 or later.

```powershell
$env:PSModulePath = (Resolve-Path 'docs/live-verification/raw/opim-s21b/modules').Path + [System.IO.Path]::PathSeparator + (Join-Path $PSHOME 'Modules')
"Module path entries: $(@($env:PSModulePath -split [System.IO.Path]::PathSeparator | Where-Object { $_ }).Count)"
"Az modules this window can find: $(@(Get-Module -ListAvailable -Name 'Az', 'Az.*').Count)"
"Az modules loaded: $(@(Get-Module -Name 'Az', 'Az.*').Count)"
"Modules loaded: $(@(Get-Module | ForEach-Object Name | Sort-Object) -join ', ')"
"PowerShell: $($PSVersionTable.PSVersion)"
```

**Expect:** `Module path entries: 2`; `Az modules this window can find: 0`; `Az modules loaded: 0`;
only `Microsoft.PowerShell.*` modules loaded; `PowerShell:` 7.4 or later.
**Failure looks like:** an Az module found or loaded -- the window is not clean: end it and start a
fresh one; never continue in it.

Result:

### S.4. The fixture is in place, and nothing carries the step's prefix

- [ ] **S.4** Window A, as `oer-live-cc`. The prerequisite script with `-WhatIf` finds every object of the fixture and would write nothing, and no object carries the prefix `opim-s21b-`.

```powershell
$Prereq = Join-Path $env:OPIMLIVE_HOME 'Initialize-OpimS2Prereq.ps1'
# A child process, so its host output -- the What if lines included -- arrives here as text.
$Lines = @(pwsh -NoProfile -NonInteractive -File $Prereq -WhatIf 2>&1 | ForEach-Object { ([string]$_) -replace '\x1b\[[0-9;]*m', '' })
"Lines 'exists; kept': $(@($Lines | Where-Object { $_ -match 'exists; kept' }).Count)"
"What if lines other than the transcript: $(@($Lines | Where-Object { $_ -match '^What if:' -and $_ -notmatch 'transcript' }).Count)"
$Lines | Where-Object { $_ -match "Sweep 'opim-s|Residue:|Group 'Exclude from CA'|PIM policy of|exists; kept" }
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$null = Import-OerLiveConfig -Prefix 'opim-s21b-'
Connect-OerLive -Graph
"Objects with the prefix opim-s21b-: $(@(Find-OerLivePrefixed -Prefix 'opim-s21b-' -ThrowOnUnread -Quiet).Count)"
Disconnect-OerLive
```

**Expect:** `Lines 'exists; kept': 10` (the user, the membership in `Exclude from CA`, the group,
the two directory role eligibilities, the group member eligibility, the two resource groups and the
two Azure eligibilities); `What if lines other than the transcript: 0`; the sweeps `opim-s1-` 0 and
`opim-s2-` 1 user, 1 group, 0 other; every PIM policy line without approval or authentication
context; `Objects with the prefix opim-s21b-: 0`.
**Failure looks like:** any `What if:` line that would create an object, a count other than 10, or a
prefixed object that is not the fixture's -- STOP (the fixture is missing something, or something
without the prefix exists): create nothing and ask for nothing. A 401 or 403 -- STOP (G6).

Result:

### S.5. The harness loads in window B, and still no Az module

- [ ] **S.5** Window B. OerLive is 1.0.3, OpimLive is 1.0.4, the harness reads the test values through it, the TOTP implementation reproduces RFC 6238, and loading the harness loaded no Az module.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME 'OpimLive/OpimLive.psm1') -Force
$Target = Get-OpimLiveTarget
"OerLive version: $((Get-OerLiveState).Version)"
"OpimLive version: $(& (Get-Module OpimLive) { $script:OpimLiveVersion })"
"Test user and tenant read (values hidden): $([bool]$Target.UserPrincipalName -and [bool]$Target.TenantId)"
"TOTP self-test: $(Get-OpimLiveTotp -SelfTest)"
"Az modules this window can find: $(@(Get-Module -ListAvailable -Name 'Az', 'Az.*').Count); loaded: $(@(Get-Module -Name 'Az', 'Az.*').Count)"
```

**Expect:** `OerLive version: 1.0.3`; `OpimLive version: 1.0.4`; the next two lines `True`; `Az
modules this window can find: 0; loaded: 0`.
**Failure looks like:** `False` on the self-test -- STOP: the harness would enter wrong codes. An Az
module -- end the window (S.3).

Result:

### 0. Preparation

### 0.1. Identity check, Graph and Azure, in a window without Az

- [ ] **0.1** Window B. The build loads AzAuth 2.9.0 and Microsoft.Graph.Authentication 2.36.0 from the step's folder and no Az module; `Connect-OpimLiveUser -IncludeARM` signs it in to Graph and Azure with one device code each, both on the Information stream; the Graph account is the test user, the tenant is the test tenant, the module's ARM token is the test user's in the test tenant; and afterwards no Az module is loaded.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Modules = (Resolve-Path 'docs/live-verification/raw/opim-s21b/modules').Path
foreach ($Name in 'AzAuth', 'Microsoft.Graph.Authentication') {
    $M = Get-Module -Name $Name
    "$Name $($M.Version), from the step's folder: $($M.ModuleBase.StartsWith($Modules, [System.StringComparison]::OrdinalIgnoreCase))"
}
"Az modules loaded before the sign-in: $(@(Get-Module -Name 'Az', 'Az.*').Count)"
$Target = Get-OpimLiveTarget
$Sign = Connect-OpimLiveUser -IncludeARM -RawFolder 'docs/live-verification/raw/opim-s21b'
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
$State = & (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }
"Session tenant is the test tenant: $([string]::Equals([string]$State.TokenTenantId, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
"ARM token held as a SecureString: $($State.ArmToken -is [securestring])"
"ARM token minutes left: $([int]($State.ArmTokenExpiry - [datetime]::UtcNow).TotalMinutes)"
"Az modules loaded after the sign-in: $(@(Get-Module -Name 'Az', 'Az.*').Count); this window can find: $(@(Get-Module -ListAvailable -Name 'Az', 'Az.*').Count)"
```

**Expect:** `AzAuth 2.9.0, from the step's folder: True`; `Microsoft.Graph.Authentication 2.36.0,
from the step's folder: True`; `Az modules loaded before the sign-in: 0`; the rows `Graph Information
True ok` and `AzureCli Information True ok`; every True/False line of the harness `True` (Graph
account, tenant, device code mode, Azure token user and tenant); `Session tenant is the test tenant:
True`; `ARM token held as a SecureString: True`; minutes left above 5; `Az modules loaded after the
sign-in: 0; this window can find: 0`. No line prints the account or the tenant id.
**Failure looks like:** `False` on any line, a `STOP`, or an Azure row that is not `AzureCli
Information True ok` -- STOP: run `Disconnect-OPIM`, end window B and run no other check. An ARM token
whose tenant or user is not the test user's is a STOP even though the module refused it (the
harness signed in wrong). An import error naming a missing module -- the build still depends on
something the step's folder does not hold: a defect within this step's scope (G11).

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

### 1. `pim` and `unpim` for all three kinds, from a tenant map (the specification's 1.x)

### 1.1. The tenant map

- [ ] **1.1** Window B. A tenant map in the raw folder holds one alias with Usage Summary Reports Reader, the membership of `opim-s2-grp` and Reader on `opim-s2-rg`, one entry each, stored from the listed eligibilities.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s21b/TenantMap.psd1'
if (-not (Test-Path -LiteralPath $Map)) {
    $Rows = @(
        @(Get-OPIMDirectoryRole -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq 'Usage Summary Reports Reader' })
        @(Get-OPIMEntraIDGroup -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s2-grp' -and $_.accessId -eq 'member' })
        @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object ScopeDisplayName -EQ 'opim-s2-rg')
    )
    "Rows to store: $($Rows.Count)"
    $Rows | Install-OPIMConfiguration -TenantAlias 's21b-all' -TenantMapPath $Map -Confirm:$false
}
$Config = Get-OPIMConfiguration -TenantAlias 's21b-all' -TenantMapPath $Map -ErrorAction Stop
"Entries: directory $(@($Config.DirectoryRoles).Count), group $(@($Config.EntraIDGroups).Count), Azure $(@($Config.AzureRoles).Count)"
```

**Expect:** `Rows to store: 3`; `Entries: directory 1, group 1, Azure 1`.
**Failure looks like:** another count -- record it, and do not run section 1 until the map holds the
three entries.

Result:

### 1.2. `pim` activates all three

- [ ] **1.2** Window B. `pim -TenantAlias s21b-all` activates the directory role, the group membership and Reader on `opim-s2-rg`, with no error, and all three are then listed as active.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s21b/TenantMap.psd1'
$global:OpimS21bPim = [datetime]::UtcNow
$First = @(Enable-OPIMMyRole -TenantAlias 's21b-all' -TenantMapPath $Map -Justification 'Omnicit.PIM step 1b live check 1.2' 2>&1 3>&1)
$Results = @($First | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' })
"First pim: results $($Results.Count); $(@($Results | ForEach-Object { '{0} {1} {2}' -f $_.Category, $_.DisplayName, $_.Status }) -join '; ')"
"Errors: $(@($First | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', '); warnings: $(@($First | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count)"
$Listed = @{}
while (([datetime]::UtcNow - $global:OpimS21bPim).TotalSeconds -lt 300 -and $Listed.Count -lt 3) {
    Start-Sleep -Seconds 15
    $Now = [int]([datetime]::UtcNow - $global:OpimS21bPim).TotalSeconds
    if (-not $Listed.ContainsKey('directory') -and @(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count -ge 1) { $Listed['directory'] = $Now }
    if (-not $Listed.ContainsKey('group') -and @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count -ge 1) { $Listed['group'] = $Now }
    if (-not $Listed.ContainsKey('Azure') -and @(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count -ge 1) { $Listed['Azure'] = $Now }
}
"Listed as active after (seconds): directory $($Listed['directory']), group $($Listed['group']), Azure $($Listed['Azure'])"
```

**Expect:** `First pim: results 3`, one row per kind (`DirectoryRole Usage Summary Reports Reader`,
`EntraIDGroup opim-s2-grp`, `AzureRole Reader`), each `Provisioned` or `Granted`; `Errors:` (none);
all three listed as active within 300 seconds.
**Record:** the seconds after which each kind was listed as active.
**Failure looks like:** fewer than three results, an error id, or a kind not listed within 300
seconds -- record it. An Azure error naming AzAuth or `Get-AzToken`, or `AzureConnectFailed` -- a
defect within this step's scope (G11).

Result:

### 1.3. A second `pim` sends nothing (G8)

- [ ] **1.3** Window B. Once all three are listed as active, the same `pim` again writes "already active" for each and sends no request.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s21b/TenantMap.psd1'
$Second = @(Enable-OPIMMyRole -TenantAlias 's21b-all' -TenantMapPath $Map -Justification 'Omnicit.PIM step 1b live check 1.3' 2>&1 3>&1)
"Second pim, $([int]([datetime]::UtcNow - $global:OpimS21bPim).TotalSeconds) s after the first: results $(@($Second | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' }).Count); already active warnings $(@($Second | Where-Object { $_ -is [System.Management.Automation.WarningRecord] -and $_.Message -match 'already active' }).Count); errors $(@($Second | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', ')"
```

**Expect:** `results 0; already active warnings 3; errors` (none).
**Failure looks like:** a result, or `RoleAssignmentExists` -- a second request was sent: record it
(G8). ARM's and Graph's listing lag is known (OPIM-50, OPIM-53); 1.2 waits until each kind is
listed, so a second request here is a finding.

Result:

### 1.4. `unpim` deactivates all three after five minutes

- [ ] **1.4** Window B. Five minutes after 1.2, `unpim -TenantAlias s21b-all` deactivates all three, with no error.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s21b/TenantMap.psd1'
$Wait = 320 - ([datetime]::UtcNow - $global:OpimS21bPim).TotalSeconds
if ($Wait -gt 0) { Start-Sleep -Seconds ([int][math]::Ceiling($Wait)) }
$global:OpimS21bUnpim = [datetime]::UtcNow
$First = @(Disable-OPIMMyRole -TenantAlias 's21b-all' -TenantMapPath $Map 2>&1 3>&1)
$Results = @($First | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' })
"First unpim: results $($Results.Count); $(@($Results | ForEach-Object { '{0} {1} {2}' -f $_.Category, $_.DisplayName, $_.Status }) -join '; ')"
"Errors: $(@($First | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object FullyQualifiedErrorId) -join ', ')"
```

**Expect:** `First unpim: results 3`, one row per kind, each `Revoked`; `Errors:` (none).
**Failure looks like:** `ActiveDurationTooShort` -- the five minutes were not waited out: run the block
again after a minute. Another error, or fewer results -- record it.

Result:

### 1.5. A second `unpim` sends nothing (G8), and nothing is left active

- [ ] **1.5** Window B. The same `unpim` again sends nothing and writes no error, and the listings show nothing active.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Map = Join-Path (Get-Location).Path 'docs/live-verification/raw/opim-s21b/TenantMap.psd1'
$Settled = $false
while (([datetime]::UtcNow - $global:OpimS21bUnpim).TotalSeconds -lt 300 -and -not $Settled) {
    Start-Sleep -Seconds 15
    $Settled = (@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count + @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count + @(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count) -eq 0
}
"Listings settled after $([int]([datetime]::UtcNow - $global:OpimS21bUnpim).TotalSeconds) s: $Settled"
$Second = @(Disable-OPIMMyRole -TenantAlias 's21b-all' -TenantMapPath $Map 2>&1 3>&1)
"Second unpim: results $(@($Second | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.PIM.MyRoleResult' }).Count); errors $(@($Second | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count); other lines $(@($Second | Where-Object { $_ -is [System.Management.Automation.WarningRecord] -or $_ -is [string] }).Count)"
"Active: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
"Az modules loaded: $(@(Get-Module -Name 'Az', 'Az.*').Count); this window can find: $(@(Get-Module -ListAvailable -Name 'Az', 'Az.*').Count)"
```

**Expect:** `Listings settled after ... s: True`; `Second unpim: results 0; errors 0`; `Active:
directory 0, group 0, Azure 0`; `Az modules loaded: 0; this window can find: 0`.
**Record:** the seconds the listings took to settle, and the second call's other lines.
**Failure looks like:** a crash, or a second request -- record it (G8). An Az module loaded -- a
defect within this step's scope (G11).

Result:

## Teardown

This step created no object, so nothing is removed from the tenant. The checks verify that nothing
is left active, that no object carries the step's prefix, and that no window keeps a session.

### T.1. Nothing is left active

- [ ] **T.1** Window B. The test user has no active directory role, group assignment or Azure role.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
"Active: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** `Active: directory 0, group 0, Azure 0`.
**Failure looks like:** an active role -- deactivate it (after five minutes) and record it. A
terminating error is a failed read, never a `0`.

Result:

### T.2. Window B signs out

- [ ] **T.2** Window B. The window's session is cleared and the window ended.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not (Get-Module Omnicit.PIM)) { throw 'Omnicit.PIM is not loaded in this window; run 0.1 first.' }
if ((Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
Disconnect-OPIM
try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { $null = $PSItem }
"Module state cleared: $($null -eq (& (Get-Module Omnicit.PIM) { $script:_OPIMAuthState })); Graph context left: $([bool](Get-MgContext))"
```

**Expect:** `Module state cleared: True; Graph context left: False`.
**Failure looks like:** `False` / `True` -- record it, and end the window.

Result:

### T.3. No object of the step, and the raw folder

- [ ] **T.3** Window A, then the operator. No object carries `opim-s21b-`; the raw folder, with the step's module folder and the tenant map, is deleted once the results are written up.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$null = Import-OerLiveConfig -Prefix 'opim-s21b-'
Connect-OerLive -Graph
"Objects with the prefix opim-s21b-: $(@(Find-OerLivePrefixed -Prefix 'opim-s21b-' -ThrowOnUnread -Quiet).Count)"
Disconnect-OerLive
Remove-Item -LiteralPath 'docs/live-verification/raw/opim-s21b' -Recurse -Force
"Raw folder gone: $(-not (Test-Path -LiteralPath 'docs/live-verification/raw/opim-s21b'))"
"Untracked files under docs/live-verification: $(@(git status --porcelain --untracked-files=all -- docs/live-verification | Where-Object { $_.StartsWith('??') }).Count)"
```

**Expect:** `Objects with the prefix opim-s21b-: 0`; `Raw folder gone: True`; `Untracked files under
docs/live-verification: 0`.
**Failure looks like:** a prefixed object -- STOP (it was not made by this file). The fixture
`opim-s2-` stays on purpose until step 5.

Result:
