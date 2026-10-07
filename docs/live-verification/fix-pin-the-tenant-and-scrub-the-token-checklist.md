# Live verification checklist -- a session stays on its tenant, refuses a Graph session it did not make, and keeps the token out of error records (fix/pin-the-tenant-and-scrub-the-token)

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
to nothing outside the prefixes `opim-s1-` (the sprint's fixture) and `opim-s13-` (this step's own
objects, of which there are none). Check 0.1 proves the identity before any other check calls the
module. If a browser window or a sign-in prompt appears mid-run, STOP and run check 0.1 again: in
this file every sign-in is a device code, and the proof of 0.1 holds only for the sign-in it checked.

**Two windows, never one process** (decision A10). Window A runs as `oer-live-cc`; window B runs the
module as the test user. The Microsoft Graph SDK holds one session per process, so the two never
share one. Check 3.1 is the one place where `oer-live-cc` signs in inside window B, and only with
`Connect-MgGraph` and its certificate: that foreign session is what the check is about. Every block
below names its window.

## What changed and why this needs a live tenant

- **A. The session stays on its tenant** ("fix: keep the signed-in tenant and refuse a token for
  another tenant", "fix: read the token's tenant without binding the token to a command"). A command
  that names no tenant keeps the session's; the Graph token's `tid` is compared with the requested
  tenant after every token (`TenantMismatch` otherwise); the MSAL app is rebuilt only when the tenant
  really changes; the token is read as a SecureString, never bound to a command. A mock cannot show
  that the real token carries `tid` where the module reads it, or that a real refresh keeps the tenant.
- **B. A Graph SDK session the module did not connect is refused** ("fix: refuse a Graph SDK session
  the module did not connect"). A mock cannot show that another `Connect-MgGraph` in the same process
  really changes what `Get-MgContext` reports, or that no request reaches Graph afterwards.
- **C. A refused sign-in closes the transport** ("fix: send nothing for a command whose sign-in was
  refused"). Seen live after B: the cmdlet that carries on past `GraphSessionChanged` sends nothing.
- **D. Azure on the Graph session's tenant, and no subscription prompt** ("fix: sign in to Azure only
  for the tenant of the Graph session", "test: prove that pim and unpim write a failed sign-in",
  "fix: never ask for a subscription when Azure signs in"). `Connect-AzAccount` always gets the
  session's tenant, an Az context is reused only for the same tenant and account, and the Azure
  sign-in turns the subscription prompt off for the process only.
- **E. The bearer scrub** ("fix: add Remove-OPIMErrorRecord and call it first in every transport
  catch", "fix: scrub the bearer token off every error record on a transport path", "fix: keep the
  original error id and scrub the Azure wait poll"). A real failed request leaves no `Authorization`
  header and no token in `$Error`, an `-ErrorVariable` or any inner exception.
- **F. Paging and a failed list** ("fix: read every page of a Graph list and fail with what was
  read", "fix: treat a later Graph page with no body as a failed read", "fix: report a failed role or
  group list as itself"). The fixture has fewer rows than a page, so live shows only that the listings
  still give the fixture's counts.
- **G. The documentation** ("docs: describe the pinned tenant, the refusals and the scrubbed error
  records"). Nothing to run live.

The fixture of step 2 is used as it stands (decision A9): the test user `opim-s1-live-user`, the
group `opim-s1-grp`, the resource groups `opim-s1-rg` and `opim-s1-rg2`, and the six eligibilities.
This file creates no object, so it has no prerequisite script of its own.

## What this file does not check, and why

- **A token for another tenant** (`TenantMismatch` for Graph, and for an Az context of another
  tenant) -- there is no second tenant (step 3's pre-decision), so it is class B: the unit tests in
  `tests/Unit/Private/Initialize-OPIMAuth.Tests.ps1` and `tests/Unit/Private/Get-OPIMArmRefusal.Tests.ps1`
  with a fixture token in the shape of the real token's claims recorded in check 1.2.
- **An Az context of another identity in the same tenant** -- the only other identity allowed in window
  B is `oer-live-cc`, and only through `Connect-MgGraph` in check 3.1; `Initialize-OPIMAuth.Tests.ps1`
  proves the new sign-in.
- **A later page that fails, and a list of several pages** -- class B, `tests/Unit/Private/Invoke-OPIMGraphRequest.Tests.ps1`,
  `Get-OPIMDirectoryRole.Tests.ps1` and `Get-OPIMEntraIDGroup.Tests.ps1`; the fixture has fewer rows
  than a page.
- **A 5xx answer** -- it cannot be produced on demand; the scrub after a 500 is in
  `tests/Unit/Public/Get-OPIMDirectoryRole.Tests.ps1`.
- **A list that fails for `-Identity`, `-RoleName` and `pim`** -- the test user can read its own lists, so
  no 403 is available; the unit tests of `Resolve-RoleByName` and the Enable-, Disable- and MyRole
  cmdlets prove it.
- **`pim` and `unpim` after a failed Graph or Azure sign-in** -- `Enable-OPIMMyRole.Tests.ps1` and
  `Disable-OPIMMyRole.Tests.ps1`; making a live sign-in fail on purpose would need a declined code in
  the middle of a MyRole run, which the harness cannot time.

## Setup, once

The operator sets `OPIMLIVE_HOME` in both windows to the notes folder that holds the `OpimLive`
folder; no checklist holds that path. The test user's sign-in name and the test tenant's id are read
by the harness through OerLive and are never printed. Window B runs from the root of the step's
worktree, and its console output also goes to the file named in `OPIMLIVE_HOSTLOG`, where
`Connect-AzAccount` writes the Azure device code (OpimLive 1.0.2). Raw output goes to
`docs/live-verification/raw/opim-s13` (git-ignored), which is deleted once the results are written up.

### S.1. Find the build under test and tie it to the branch head

- [ ] **S.1** Window B. The newest build in `output/module/Omnicit.PIM/` was made after the branch head was committed.

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
on the host log -- the Azure checks cannot complete their code; set it before section 2.

Result:

### S.3. The fixture is in place, and this step has no object of its own

- [ ] **S.3** Window A, as `oer-live-cc`. The fixture's user and group exist, and no object carries the prefix `opim-s13-`.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$null = Import-OerLiveConfig -Prefix 'opim-s13-'
Connect-OerLive -Graph
"Objects with the prefix opim-s13-: $(@(Find-OerLivePrefixed -Prefix 'opim-s13-' -ThrowOnUnread -Quiet).Count)"
"Objects with the prefix opim-s1- (the fixture): $(@(Find-OerLivePrefixed -Prefix 'opim-s1-' -ThrowOnUnread -Quiet).Count)"
Disconnect-OerLive
```

**Expect:** every identity check line of `oer-live-cc` `True`; `opim-s13-: 0`; `opim-s1-: 2` (the user
and the group; the resource groups are not directory objects).
**Failure looks like:** a 401 or 403 -- STOP (G6). Another count -- record each object by name and
STOP: the fixture is not the one this file assumes. A throw on an unread collection is a failed read,
never a `0`.

Result:

### 0. Preparation

### 0.1. Identity check

- [ ] **0.1** Window B. `Connect-OpimLiveUser` without `-IncludeARM` signs the module in with one device code; the account is the test user, the tenant the test tenant, and the session is pinned to the test tenant's id.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
Import-Module (Join-Path $env:OPIMLIVE_HOME 'OpimLive/OpimLive.psm1') -Force
$Target = Get-OpimLiveTarget
$Sign = Connect-OpimLiveUser -RawFolder 'docs/live-verification/raw/opim-s13'
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
$State = & (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }
"Session tenant is the test tenant: $([string]::Equals([string]$State.TenantId, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
"Token tenant is the test tenant: $([string]::Equals([string]$State.TokenTenantId, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
"The module recorded its Graph session: $([bool]$State.GraphSessionFingerprint)"
```

**Expect:** `Disconnect-OPIM, Disconnect-MgGraph and Disconnect-AzAccount ran first`; one row
`Graph Information True ok`; every True/False line `True`. The block prints neither the account nor
the tenant id.
**Failure looks like:** `False` on any line, or a `STOP` -- STOP: run `Disconnect-OPIM`, end window B
and run no other check.

Result:

### 1. The tenant is pinned

### 1.1. A cmdlet without a tenant, then a forced refresh, keeps the tenant and the MSAL app

- [ ] **1.1** Window B. `Get-OPIMDirectoryRole` and then `Initialize-OPIMAuth -ForceRefresh` without a tenant (the module's token-rejected retry) leave the session on the test tenant, reuse the same MSAL app and ask for no code.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Module = Get-Module Omnicit.PIM
$Target = Get-OpimLiveTarget
$Roles = @(Get-OPIMDirectoryRole -ErrorAction Stop)
"Eligible directory roles: $($Roles.Count)"
$AppBefore = & $Module { $script:_OPIMMsalApp }
$Records = @(& $Module { Initialize-OPIMAuth -ForceRefresh } 6>&1)
$State = & $Module { $script:_OPIMAuthState }
"Device code messages: $(@($Records | Where-Object { $_ -is [System.Management.Automation.InformationRecord] -and $_.Tags -contains 'OPIMDeviceCode' }).Count)"
"Session tenant is still the test tenant: $([string]::Equals([string]$State.TenantId, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
"Token tenant is the test tenant: $([string]::Equals([string]$State.TokenTenantId, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
"The same MSAL app (not rebuilt): $([object]::ReferenceEquals($AppBefore, (& $Module { $script:_OPIMMsalApp })))"
"Never relabelled to organizations: $($State.TenantId -ne 'organizations')"
```

**Expect:** `Eligible directory roles: 2`; `Device code messages: 0`; the four True/False lines `True`,
within seconds.
**Failure looks like:** a device code message -- the refresh was not silent; if the block has not
returned within 30 seconds, stop it, record a non-silent refresh and run 0.1 again. `False` on a
tenant line -- STOP: the tenant is not pinned (OPIM-07 is not fixed).

Result:

### 1.2. The real token carries its tenant where the module reads it (the recorded claims, class B)

- [ ] **1.2** Window B. The test user's real Graph token has a top-level `tid` equal to the test tenant, the module's own parser reads it, and its claim names are recorded -- never a value.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Target = Get-OpimLiveTarget
$Seen = & (Get-Module Omnicit.PIM) {
    param($TestTenant)
    # The module's own MSAL app, silently, as the module's refresh does; the token never leaves this scriptblock.
    $App = $script:_OPIMMsalApp
    $Method = $App.GetType().GetMethods() | Where-Object {
        $_.Name -eq 'AcquireTokenSilent' -and ($P = $_.GetParameters()).Count -eq 2 -and
        $P[0].ParameterType.Name -eq 'IEnumerable`1' -and $P[1].ParameterType.Name -match 'IAccount'
    } | Select-Object -First 1
    $CallArgs = [object[]]::new(2)
    $CallArgs[0] = [string[]]@('User.Read')
    $CallArgs[1] = $script:_OPIMAuthState.Account
    $Result = $Method.Invoke($App, $CallArgs).ExecuteAsync().GetAwaiter().GetResult()
    # .NET calls only: the token and its claims are never bound to a command (module logging records bound values).
    $Secure = [System.Net.NetworkCredential]::new('', $Result.AccessToken).SecurePassword
    $Segment = $Result.AccessToken.Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($Segment.Length % 4) { 2 { $Segment += '==' } 3 { $Segment += '=' } }
    $Doc = [System.Text.Json.JsonDocument]::Parse([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Segment)))
    $Names = [System.Collections.Generic.List[string]]::new()
    foreach ($P in $Doc.RootElement.EnumerateObject()) { $Names.Add($P.Name) }
    $Tid = $Doc.RootElement.GetProperty('tid').GetString()
    $Iss = $Doc.RootElement.GetProperty('iss').GetString()
    $Seen = [pscustomobject]@{
        Names        = (@($Names) | Sort-Object) -join ', '
        TidIsTest    = [string]::Equals($Tid, $TestTenant, [System.StringComparison]::OrdinalIgnoreCase)
        ParserIsTest = [string]::Equals([string](Get-OPIMTokenTenantId -AccessToken $Secure), $TestTenant, [System.StringComparison]::OrdinalIgnoreCase)
        IssuerHasTid = $Iss.Contains($Tid)
        Segments     = $Result.AccessToken.Split('.').Length
    }
    $Doc.Dispose()
    $Result = $null; $Secure = $null; $Tid = $null; $Iss = $null
    $Seen
} $Target.TenantId
"Claim names: $($Seen.Names)"
"tid equals the test tenant: $($Seen.TidIsTest)"
"Get-OPIMTokenTenantId on the real token equals the test tenant: $($Seen.ParserIsTest)"
"The issuer names the same tenant: $($Seen.IssuerHasTid)"
"Token segments: $($Seen.Segments)"
```

**Expect:** the claim names include `tid`, `iss`, `aud`, `scp`, `upn` and `oid`; the three True/False
lines `True`; `Token segments: 3`. Only names are printed: no claim value, and never the token.
**Record:** the claim names, which the unit tests' fixture `New-OPIMTestAccessToken` mirrors.
**Failure looks like:** `False` on a tenant line -- STOP: the module reads the tenant from somewhere
the real token does not carry it.

Result:

### 2. Azure on the session's tenant

### 2.1. Get-OPIMAzureRole after a Graph-only sign-in connects Azure to the same tenant, with a device code

- [ ] **2.1** Window B. With no Az context in the process, `Get-OPIMAzureRole` signs Azure in with a device code (never a silent reuse), to the test tenant and as the test user, asks for no subscription, and lists the fixture's two Azure roles.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Target = Get-OpimLiveTarget
try { Disconnect-AzAccount -ErrorAction Stop | Out-Null } catch { $null = $PSItem }
"Az context before: $([bool](Get-AzContext -ErrorAction SilentlyContinue))"
$UserConfigBefore = (Get-AzConfig -LoginExperienceV2 -Scope CurrentUser -ErrorAction SilentlyContinue).Value
$Raw = (Resolve-Path 'docs/live-verification/raw/opim-s13').Path
$Log = Join-Path $Raw ('az-{0}' -f [guid]::NewGuid().ToString('N'))
$Offset = (Get-Item -LiteralPath $env:OPIMLIVE_HOSTLOG).Length
$Info = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
foreach ($Arg in @('-NoProfile', '-NonInteractive', '-File', (Join-Path $env:OPIMLIVE_HOME 'OpimLive/opimlive-azure-helper.ps1'),
        '-Log', $env:OPIMLIVE_HOSTLOG, '-Offset', [string]$Offset, '-Cancel', "$Log.cancel", '-Result', "$Log.result",
        '-UserPrincipalName', $Target.UserPrincipalName, '-RawFolder', $Raw, '-LastStep', [string](& (Get-Module OpimLive) { $script:OpimLiveLastTotpStep }))) { $Info.ArgumentList.Add($Arg) }
$Info.UseShellExecute = $false; $Info.CreateNoWindow = $true; $Info.RedirectStandardOutput = $true; $Info.RedirectStandardError = $true
$Helper = [System.Diagnostics.Process]::Start($Info)
$HelperOut = $Helper.StandardOutput.ReadToEndAsync()
try {
    $Rows = @(Get-OPIMAzureRole -ErrorAction Stop)
} finally {
    [System.IO.File]::WriteAllText("$Log.cancel", 'cancel')
    $null = $Helper.WaitForExit(300000)
    $Codes = if (Test-Path -LiteralPath "$Log.result") { @(Get-Content -LiteralPath "$Log.result" | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json }) } else { @() }
    # A TOTP code is never used twice: hand the helper's last time step back to the harness, as Connect-OpimLiveUser does.
    foreach ($Row in $Codes) { & (Get-Module -Name OpimLive) { param($S) if ($S -gt $script:OpimLiveLastTotpStep) { $script:OpimLiveLastTotpStep = $S } } ([long]$Row.lastStep) }
    foreach ($Path in "$Log.result", "$Log.cancel") { if ([System.IO.File]::Exists($Path)) { [System.IO.File]::Delete($Path) } }
    $Helper.Dispose()
}
$Az = Get-AzContext
"Azure device codes completed by the helper: $(@($Codes | Where-Object { $_.app -eq 'Azure' -and $_.status -eq 'ok' }).Count)"
"Az context is the test tenant: $([string]::Equals([string]$Az.Tenant.Id, $Target.TenantId, [System.StringComparison]::OrdinalIgnoreCase))"
"Az context is the test user: $([string]::Equals([string]$Az.Account.Id, $Target.UserPrincipalName, [System.StringComparison]::OrdinalIgnoreCase))"
"Eligible Azure roles: $($Rows.Count); scopes: $((@($Rows.ScopeDisplayName) | Sort-Object) -join ', ')"
$Reader = [System.IO.StreamReader]::new([System.IO.FileStream]::new($env:OPIMLIVE_HOSTLOG, 'Open', 'Read', 'ReadWrite'))
$HostText = $Reader.ReadToEnd(); $Reader.Dispose()
"Subscription prompts in the host log so far: $(([regex]::Matches($HostText, '(?i)select a tenant and subscription|subscription name or number|tenant and subscription selection')).Count)"
"Process scope LoginExperienceV2: $((Get-AzConfig -LoginExperienceV2 -Scope Process -ErrorAction SilentlyContinue).Value)"
"CurrentUser LoginExperienceV2 unchanged: $((Get-AzConfig -LoginExperienceV2 -Scope CurrentUser -ErrorAction SilentlyContinue).Value -eq $UserConfigBefore)"
"Subscriptions the test user reaches: $(@(Get-AzSubscription -TenantId $Target.TenantId -ErrorAction SilentlyContinue).Count)"
```

**Expect:** `Az context before: False`; one Azure device code completed; the two context lines `True`;
`Eligible Azure roles: 2; scopes: opim-s1-rg, opim-s1-rg2`; `Subscription prompt ...: 0`; process
scope `Off`; `CurrentUser ... unchanged: True`.
**Record:** the number of subscriptions the test user reaches. With one, Az would not have asked even
without the change, so the live run shows only that the sign-in completes and that the settings are
set; the unit tests pin both settings.
**Failure looks like:** no Azure device code and a context anyway -- a silent reuse, STOP. A context
for another tenant or user -- STOP. A hang -- the subscription prompt or a lost code; stop the block
after 5 minutes and record it.

Result:

### 2.2. Connect-OPIM -DeviceCode -IncludeARM asks for no subscription (A15)

- [ ] **2.2** Window B. After `Disconnect-AzAccount`, `Connect-OpimLiveUser -IncludeARM -NoDisconnect` (which runs `Connect-OPIM -DeviceCode -IncludeARM`) completes the Azure code and nothing asks for a subscription.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
try { Disconnect-AzAccount -ErrorAction Stop | Out-Null } catch { $null = $PSItem }
$Offset = (Get-Item -LiteralPath $env:OPIMLIVE_HOSTLOG).Length
$Sign = Connect-OpimLiveUser -IncludeARM -NoDisconnect -RawFolder 'docs/live-verification/raw/opim-s13'
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
$Reader = [System.IO.StreamReader]::new([System.IO.FileStream]::new($env:OPIMLIVE_HOSTLOG, 'Open', 'Read', 'ReadWrite'))
$HostText = $Reader.ReadToEnd(); $Reader.Dispose()
"Subscription prompts in the host log so far: $(([regex]::Matches($HostText, '(?i)select a tenant and subscription|subscription name or number|tenant and subscription selection')).Count)"
"Az context has no default subscription (SkipContextPopulation): $($null -eq (Get-AzContext).Subscription.Id)"
```

**Expect:** the row `Azure Host False ok`, every True/False line of the harness `True`, `0` prompts.
**Record:** whether the Az context carries a subscription.
**Failure looks like:** a hang or a prompt -- STOP the block after 5 minutes and record it.

Result:

### 3. A foreign Graph SDK session

### 3.1. Another Connect-MgGraph in the module's process is refused, and nothing is sent

- [ ] **3.1** Window B. After `oer-live-cc` connects the process's Graph SDK session with its certificate, `Get-OPIMDirectoryRole` and `Get-OPIMAzureRole` are refused and no Graph request is sent.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Cc = & (Get-Module OerLive) { $script:OerLive.Config }
# Microsoft.Graph.Authentication 2.36.0 refuses a certificate Connect-MgGraph on top of the process's
# -AccessToken session ("MSAL deserialization failed to parse the cache contents", measured), so the SDK
# session is closed first. The module's own state is untouched: the process then holds a session the
# module did not connect, which is what this check is about.
try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { $null = $PSItem }
Connect-MgGraph -ClientId $Cc.AppId -TenantId $Cc.TenantId -CertificateThumbprint $Cc.CertificateThumbprint -ContextScope Process -NoWelcome -ErrorAction Stop
$Cc = $null
"The process's Graph session is now app-only: $((Get-MgContext).AuthType -eq 'AppOnly')"
$global:OpimS13GraphCalls = 0
function global:Invoke-MgGraphRequest { $global:OpimS13GraphCalls++; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @args }
try {
    # Each call in its own try: a window that runs this block under a try sees the module's terminating
    # refusal propagate (outside any try the cmdlet would carry on and be refused again at its send).
    $Errors = @()
    try { $Rows = @(Get-OPIMDirectoryRole -ErrorVariable Errors -ErrorAction SilentlyContinue) } catch { $Errors += $PSItem; $Rows = @() }
    "Get-OPIMDirectoryRole: rows $($Rows.Count); errors: $(@($Errors | ForEach-Object { $_.FullyQualifiedErrorId } | Select-Object -Unique) -join ', ')"
    $Errors = @()
    try { $Rows = @(Get-OPIMAzureRole -ErrorVariable Errors -ErrorAction SilentlyContinue) } catch { $Errors += $PSItem; $Rows = @() }
    "Get-OPIMAzureRole: rows $($Rows.Count); errors: $(@($Errors | ForEach-Object { $_.FullyQualifiedErrorId } | Select-Object -Unique) -join ', ')"
    "Graph requests sent by the module: $global:OpimS13GraphCalls"
} finally {
    Remove-Item -Path Function:\Invoke-MgGraphRequest -ErrorAction SilentlyContinue
}
"The session is still oer-live-cc's (never switched back by the module): $((Get-MgContext).AuthType -eq 'AppOnly')"
```

**Expect:** `app-only: True`; `Get-OPIMDirectoryRole: rows 0` with `GraphSessionChanged` among the errors;
`Get-OPIMAzureRole: rows 0` with `GraphSessionChanged` and `SignInRefused` (or only
`GraphSessionChanged`); `Graph requests sent by the module: 0`; the last line `True`. No value of the
app identity is printed.
**Failure looks like:** a row, or a request count above `0` -- STOP: the module sent a call under a
session it did not connect (OPIM-09 is not fixed). The last line `False` -- the module switched the
session back by itself, STOP.

Result:

### 3.2. Disconnect-MgGraph, Disconnect-OPIM and a new sign-in as the test user

- [ ] **3.2** Window B. The foreign session is closed, the module's state is cleared, and a new device code sign-in brings the module back as the test user.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { $null = $PSItem }
Disconnect-OPIM
"Auth state cleared: $($null -eq (& (Get-Module Omnicit.PIM) { $script:_OPIMAuthState }))"
$Sign = Connect-OpimLiveUser -IncludeARM -RawFolder 'docs/live-verification/raw/opim-s13'
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
"Eligible directory roles: $(@(Get-OPIMDirectoryRole -ErrorAction Stop).Count)"
```

**Expect:** `Auth state cleared: True`; the two rows `Graph Information True ok` and
`Azure Host False ok`; every True/False line `True`; `Eligible directory roles: 2`.
**Failure looks like:** `False` -- STOP as in 0.1.

Result:

### 4. The bearer scrub

### 4.1. A 404 and a 400 leave no token in any error record

- [ ] **4.1** Window B. A request for a schedule id that does not exist answers 404, an invalid filter answers 400, and a walk of `$Error`, the `-ErrorVariable` and every inner exception finds no `Authorization` header and no token.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Collected = [System.Collections.Generic.List[object]]::new()
# The module's own transport, in its own scope; -ErrorVariable there also keeps the raw SDK record the
# transport caught, which is the record the scrub has to have cleared.
foreach ($Probe in @(
        @{ Name = 'schedule id that does not exist'; Uri = ('v1.0/roleManagement/directory/roleEligibilitySchedules/{0}' -f [guid]::NewGuid()) }
        @{ Name = 'administrative unit that does not exist (the directoryScope lookup)'; Uri = ('v1.0/directory/administrativeUnits/{0}' -f [guid]::NewGuid()) }
    )) {
    $Records = @(& (Get-Module Omnicit.PIM) {
        param($Uri)
        $Ev = $null
        $Caught = $null
        try { $null = Invoke-OPIMGraphRequest -Uri $Uri -ErrorVariable Ev } catch { $Caught = $PSItem }
        @($Ev) + @($Caught) | Where-Object { $null -ne $_ }
    } $Probe.Uri)
    "$($Probe.Name): records $($Records.Count); ids: $(@($Records | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
    foreach ($E in $Records) { $Collected.Add($E) }
}
$Errors400 = @()
$Rows = @(Get-OPIMDirectoryRole -Filter "opimNoSuchProperty eq 'x'" -ErrorVariable Errors400 -ErrorAction SilentlyContinue)
"400 request through Get-OPIMDirectoryRole: rows $($Rows.Count); errors: $(@($Errors400 | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
foreach ($E in $Errors400) { $Collected.Add($E) }
foreach ($E in $global:Error) { $Collected.Add($E) }
$Seen = [System.Collections.Generic.HashSet[int]]::new()
$Queue = [System.Collections.Generic.Queue[object]]::new()
foreach ($C in $Collected) { $Queue.Enqueue($C) }
$Text = [System.Text.StringBuilder]::new()
$Requests = 0; $WithHeader = 0; $Walked = 0
while ($Queue.Count -gt 0 -and $Walked -lt 5000) {
    $Item = $Queue.Dequeue()
    if ($null -eq $Item -or -not $Seen.Add([System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Item))) { continue }
    $Walked++
    $null = $Text.AppendLine(($Item | Out-String))
    if ($Item -is [System.Net.Http.HttpRequestMessage]) { $Requests++; if ($Item.Headers.Contains('Authorization')) { $WithHeader++ }; $null = $Text.AppendLine($Item.Headers.ToString()) }
    foreach ($Name in 'Exception', 'InnerException', 'TargetObject', 'Response', 'RequestMessage', 'ErrorRecord') {
        try { $P = $Item.PSObject.Properties[$Name]; if ($P) { $Queue.Enqueue($P.Value) } } catch { $null = $PSItem }
    }
    try { if ($Item.PSObject.Properties['InnerExceptions']) { foreach ($I in $Item.InnerExceptions) { $Queue.Enqueue($I) } } } catch { $null = $PSItem }
}
$Rendered = $Text.ToString()
"Records and objects walked: $Walked; request messages reached: $Requests; with an Authorization header: $WithHeader"
"Token-shaped strings (eyJ) in the rendered records: $(([regex]::Matches($Rendered, 'eyJ')).Count)"
"Bearer values in the rendered records: $(([regex]::Matches($Rendered, '(?i)Bearer\s+[A-Za-z0-9._~+/=-]{16,}')).Count)"
$Rendered = $null; $Text = $null
```

**Expect:** the administrative unit probe gives a Graph code for a missing object
(`Request_ResourceNotFound`, a 404); the 400 request gives `rows 0` and a Graph code for a bad
request; `with an Authorization header: 0`; both counts `0`.
**Record:** the schedule id probe's code (a 404, or a 403 when a self-service user may not read a
schedule by id -- either is a 4xx the walk then covers), and how many request messages the walk
reached (each one is a raw SDK record whose header the scrub cleared).
**Failure looks like:** any count above `0` -- STOP and rotate nothing yet: the token did not leave the
process, but the scrub failed (OPIM-11 is not fixed). Never paste the rendered text anywhere.

Result:

### 4.2. A failed Azure read leaves no token in any error record

Added after the first run: check 6.3 showed that the caller's `-ErrorVariable` keeps the raw
`Az.Resources` records of a failed Azure command, and 4.1 walks Graph records only. The block reads at
a subscription that does not exist, so ARM refuses the read and nothing is written.

- [ ] **4.2** Window B. `Get-OPIMAzureRole` and `Get-OPIMAzureRole -Activated` at a subscription that does not exist fail, and a walk of `$Error`, the `-ErrorVariable` and every inner exception, request and request wrapper finds no `Authorization` header and no token.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
Import-Module (Join-Path $env:OPIMLIVE_HOME 'OpimLive/OpimLive.psm1') -Force
$Sign = Connect-OpimLiveUser -IncludeARM -RawFolder 'docs/live-verification/raw/opim-s13'
$Sign.Codes | Format-Table App, Stream, Tagged, Status -AutoSize
$Collected = [System.Collections.Generic.List[object]]::new()
$Scope = '/subscriptions/{0}' -f [guid]::NewGuid()
foreach ($Probe in @(@{ Name = 'eligible'; Activated = $false }, @{ Name = 'active'; Activated = $true })) {
    $AzErrors = @()
    $Switch = @{ Activated = $Probe.Activated }
    try { $Rows = @(Get-OPIMAzureRole -Scope $Scope @Switch -ErrorVariable AzErrors -ErrorAction SilentlyContinue) } catch { $AzErrors += $PSItem; $Rows = @() }
    "Azure $($Probe.Name) read at a subscription that does not exist: rows $($Rows.Count); records $($AzErrors.Count); ids: $(@($AzErrors | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
    foreach ($E in $AzErrors) { $Collected.Add($E) }
}
foreach ($E in $global:Error) { $Collected.Add($E) }
$Seen = [System.Collections.Generic.HashSet[int]]::new()
$Queue = [System.Collections.Generic.Queue[object]]::new()
foreach ($C in $Collected) { $Queue.Enqueue($C) }
$Text = [System.Text.StringBuilder]::new()
$Requests = 0; $WithHeader = 0; $Walked = 0
while ($Queue.Count -gt 0 -and $Walked -lt 5000) {
    $Item = $Queue.Dequeue()
    if ($null -eq $Item -or $Item -is [string] -or $Item.GetType().IsValueType -or -not $Seen.Add([System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Item))) { continue }
    $Walked++
    $null = $Text.AppendLine(($Item | Out-String))
    # A request message, or a wrapper that copied its headers (Microsoft.Rest's HttpRequestMessageWrapper).
    try {
        $H = $Item.PSObject.Properties['Headers']
        if ($H -and ($Item -is [System.Net.Http.HttpRequestMessage] -or $Item.GetType().Name -match 'Request')) {
            $Requests++
            $Has = if ($H.Value -is [System.Net.Http.Headers.HttpHeaders]) { $H.Value.Contains('Authorization') } elseif ($H.Value -is [System.Collections.IDictionary]) { $H.Value.Contains('Authorization') } else { $false }
            if ($Has) { $WithHeader++ }
            if ($H.Value -is [System.Collections.IDictionary]) { foreach ($K in $H.Value.Keys) { $null = $Text.AppendLine("${K}: $(@($H.Value[$K]) -join ',')") } } else { $null = $Text.AppendLine([string]$H.Value) }
        }
    } catch { $null = $PSItem }
    foreach ($Name in 'Exception', 'InnerException', 'TargetObject', 'Response', 'RequestMessage', 'Request', 'ErrorRecord') {
        try { $P = $Item.PSObject.Properties[$Name]; if ($P) { $Queue.Enqueue($P.Value) } } catch { $null = $PSItem }
    }
    try { if ($Item.PSObject.Properties['InnerExceptions']) { foreach ($I in $Item.InnerExceptions) { $Queue.Enqueue($I) } } } catch { $null = $PSItem }
}
$Rendered = $Text.ToString()
"Records and objects walked: $Walked; requests and request wrappers reached: $Requests; with an Authorization header: $WithHeader"
"Token-shaped strings (eyJ) in the rendered records: $(([regex]::Matches($Rendered, 'eyJ')).Count)"
"Bearer values in the rendered records: $(([regex]::Matches($Rendered, '(?i)Bearer\s+[A-Za-z0-9._~+/=-]{16,}')).Count)"
$Rendered = $null; $Text = $null
```

**Expect:** the two harness rows `Graph Information True ok` and `Azure Host False ok`; both reads
`rows 0` with an error; `with an Authorization header: 0`; both counts `0`.
**Record:** the error ids, and how many requests or request wrappers the walk reached (`0` means the
`Az.Resources` record carries no request at all).
**Failure looks like:** any count above `0` -- STOP as in 4.1. No error on a read -- record it and mark
the box `[~]`: no failed Azure record was produced to walk.

Result:

### 5. The listings

### 5.1. The listings give step 2's counts

- [ ] **5.1** Window B. The three listings, now read through every page, give the fixture's counts.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
"Eligible directory roles: $(@(Get-OPIMDirectoryRole -ErrorAction Stop).Count)"
"Eligible group assignments: $(@(Get-OPIMEntraIDGroup -ErrorAction Stop).Count)"
"Eligible Azure roles: $(@(Get-OPIMAzureRole -ErrorAction Stop).Count)"
"Combined directory rows (-All): $(@(Get-OPIMDirectoryRole -All -ErrorAction Stop).Count)"
"Combined group rows (-All): $(@(Get-OPIMEntraIDGroup -All -ErrorAction Stop).Count)"
```

**Expect:** `2`, `2`, `2`, and `2` and `2` for the combined rows while nothing is active (step 2's
2.1-2.3).
**Failure looks like:** another count -- record and STOP. A terminating error is a failed read, never
a pass.

Result:

### 6. The activations, each twice (G8)

Each activation uses the old string form, the one the tab completion offers: the name and the schedule
id in parentheses. The justification is `opim-s13 live verification`.

### 6.1. A directory role, activated twice

- [ ] **6.1** Window B. Usage Summary Reports Reader activates once; the second call gives a clear outcome and no second activation.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Role = @(Get-OPIMDirectoryRole -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq 'Usage Summary Reports Reader' })
if ($Role.Count -ne 1) { throw "Expected one eligible row, found $($Role.Count)." }
$Old = '{0} ({1})' -f $Role[0].roleDefinition.displayName, $Role[0].id
$First = Enable-OPIMDirectoryRole -RoleName $Old -Justification 'opim-s13 live verification' -Hours 1 -ErrorAction Stop
"First: status $($First.status)"
$Errors = @()
try { $Second = @(Enable-OPIMDirectoryRole -RoleName $Old -Justification 'opim-s13 live verification' -Hours 1 -ErrorVariable Errors -ErrorAction SilentlyContinue) } catch { $Errors += $PSItem; $Second = @() }
"Second (G8): output $($Second.Count); errors $($Errors.Count): $(@($Errors | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
"Active rows of the role: $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq 'Usage Summary Reports Reader' }).Count)"
```

**Expect:** `First: status Provisioned` (or `PendingProvisioning`); `Active rows of the role: 1`.
**Record:** the second call's outcome -- an error that says the role is already active is a pass; a
second request accepted or a crash is a fail (G8).
**Failure looks like:** a terminating error on the first call (record its error id), or more than one
active row -- STOP.

Result:

### 6.2. Group membership, activated twice

- [ ] **6.2** Window B. `opim-s1-grp` as member activates once; the second call gives a clear outcome.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Group = @(Get-OPIMEntraIDGroup -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'member' })
if ($Group.Count -ne 1) { throw "Expected one eligible member row, found $($Group.Count)." }
$Old = '{0} - {1} ({2})' -f $Group[0].group.displayName, $Group[0].accessId, $Group[0].id
$First = Enable-OPIMEntraIDGroup -GroupName $Old -Justification 'opim-s13 live verification' -Hours 1 -ErrorAction Stop
"First: status $($First.status) at $([datetime]::UtcNow.ToString('HH:mm:ss')) UTC"
$Errors = @()
try { $Second = @(Enable-OPIMEntraIDGroup -GroupName $Old -Justification 'opim-s13 live verification' -Hours 1 -ErrorVariable Errors -ErrorAction SilentlyContinue) } catch { $Errors += $PSItem; $Second = @() }
"Second (G8): output $($Second.Count); errors $($Errors.Count): $(@($Errors | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
"Active member rows: $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'member' }).Count)"
```

**Expect:** a first status that is not a failure; `Active member rows: 1`.
**Record:** the second call's outcome, as in 6.1, and whether the membership is still active at 6.5
(OPIM-39, measured once in step 2: a repeated activation removed it within seven minutes).
**Failure looks like:** as in 6.1.

Result:

### 6.3. Reader on opim-s1-rg, activated twice

- [ ] **6.3** Window B. Reader on `opim-s1-rg` activates once through the ARM gate; the second call gives a clear outcome.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Role = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeDisplayName -eq 'opim-s1-rg' })
if ($Role.Count -ne 1) { throw "Expected one eligible row, found $($Role.Count)." }
$Old = '{0} -> {1} ({2})' -f $Role[0].RoleDefinitionDisplayName, $Role[0].ScopeDisplayName, $Role[0].Name
$First = Enable-OPIMAzureRole -RoleName $Old -Justification 'opim-s13 live verification' -Hours 1 -ErrorAction Stop
"First: status $($First.Status)"
$Errors = @()
try { $Second = @(Enable-OPIMAzureRole -RoleName $Old -Justification 'opim-s13 live verification' -Hours 1 -ErrorVariable Errors -ErrorAction SilentlyContinue) } catch { $Errors += $PSItem; $Second = @() }
"Second (G8): output $($Second.Count); errors $($Errors.Count): $(@($Errors | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
"Active Reader rows (scope '/'): $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeId -eq $Role[0].ScopeId }).Count)"
```

**Expect:** a first status that is not a failure; `Active Reader rows (scope '/'): 1` (read at `/`,
since ARM's listing at the resource group scope lags, OPIM-41).
**Record:** the second call's outcome, as in 6.1.
**Failure looks like:** as in 6.1. `SignInRefused` or `TenantMismatch` on the first call -- STOP: the
ARM gate refused a session it should accept.

Result:

### 6.4. The five-minute rule

- [ ] **6.4** Window B. Five minutes pass after the last activation of 6.1 to 6.3.

```powershell
Start-Sleep -Seconds 310
"Waited: $([datetime]::UtcNow.ToString('HH:mm:ss')) UTC"
```

**Expect:** the time, at least five minutes after 6.3 finished.
**Failure looks like:** nothing can fail here; the wait is the check.

Result:

### 6.5. Each activation, deactivated twice

- [ ] **6.5** Window B. The directory role, the group membership and Reader on `opim-s1-rg` each deactivate once; each second call gives a clear outcome.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Dir = @(Get-OPIMDirectoryRole -Activated -ErrorAction Stop | Where-Object { $_.roleDefinition.displayName -eq 'Usage Summary Reports Reader' })
$Grp = @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-s1-grp' -and $_.accessId -eq 'member' })
$Eligible = @(Get-OPIMAzureRole -ErrorAction Stop | Where-Object { $_.ScopeDisplayName -eq 'opim-s1-rg' })[0]
$Arm = @(Get-OPIMAzureRole -Activated -ErrorAction Stop | Where-Object { $_.RoleDefinitionDisplayName -eq 'Reader' -and $_.ScopeId -eq $Eligible.ScopeId })
"Active before: directory $($Dir.Count), group member $($Grp.Count), Reader $($Arm.Count) at $([datetime]::UtcNow.ToString('HH:mm:ss')) UTC"
$Plan = @()
if ($Dir.Count -eq 1) { $Plan += @{ Name = 'directory'; Cmd = 'Disable-OPIMDirectoryRole'; Arg = @{ RoleName = ('{0} ({1})' -f $Dir[0].roleDefinition.displayName, $Dir[0].id) } } }
if ($Grp.Count -eq 1) { $Plan += @{ Name = 'group'; Cmd = 'Disable-OPIMEntraIDGroup'; Arg = @{ GroupName = ('{0} - {1} ({2})' -f $Grp[0].group.displayName, $Grp[0].accessId, $Grp[0].id) } } }
if ($Arm.Count -eq 1) { $Plan += @{ Name = 'Reader'; Cmd = 'Disable-OPIMAzureRole'; Arg = @{ RoleName = ('{0} -> {1} ({2})' -f $Arm[0].RoleDefinitionDisplayName, $Arm[0].ScopeDisplayName, $Arm[0].Name) } } }
foreach ($Step in $Plan) {
    foreach ($Try in 1, 2) {
        $Errors = @()
        $Arg = $Step.Arg
        try { $Out = @(& $Step.Cmd @Arg -ErrorVariable Errors -ErrorAction SilentlyContinue) } catch { $Errors += $PSItem; $Out = @() }
        "$($Step.Name) call ${Try}: output $($Out.Count) status $(@($Out | ForEach-Object { if ($_.status) { $_.status } else { $_.Status } }) -join ','); errors $($Errors.Count): $(@($Errors | ForEach-Object { $_.FullyQualifiedErrorId }) -join ', ')"
    }
}
"Active after: directory $(@(Get-OPIMDirectoryRole -Activated -ErrorAction Stop).Count), group $(@(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count), Azure $(@(Get-OPIMAzureRole -Activated -ErrorAction Stop).Count)"
```

**Expect:** each first call a non-failure status (`Revoked` or similar); `Active after: directory 0,
group 0, Azure 0`.
**Record:** each second call's outcome (OPIM-40, step 4: the second deactivation of a directory or
Azure role gives the terminating "not found as an eligible role"; the block catches it), and whether
the group membership was still active before (OPIM-39).
**Failure looks like:** `ActiveDurationTooShort` -- 6.4 did not wait long enough; run 6.4 and this
block again. A row left active -- record it.

Result:

## Teardown

This step creates no object of its own (prefix `opim-s13-`). The fixture (prefix `opim-s1-`) stays
until the sprint's last step (decision A9). Delete `docs/live-verification/raw/opim-s13` once the
results are written up.

### T.1. No object of this step is left

- [ ] **T.1** Window A, as `oer-live-cc`. No directory object carries the prefix `opim-s13-`, and the fixture's two directory objects are still there.

```powershell
Import-Module (Join-Path $env:OPIMLIVE_HOME '../../Omnicit Entra RBAC/Live-verifiering/OerLive/OerLive.psm1') -Force
$null = Import-OerLiveConfig -Prefix 'opim-s13-'
Connect-OerLive -Graph
"Objects with the prefix opim-s13-: $(@(Find-OerLivePrefixed -Prefix 'opim-s13-' -ThrowOnUnread -Quiet).Count)"
"Objects with the prefix opim-s1- (the fixture): $(@(Find-OerLivePrefixed -Prefix 'opim-s1-' -ThrowOnUnread -Quiet).Count)"
Disconnect-OerLive
```

**Expect:** `opim-s13-: 0`; `opim-s1-: 2`, as in S.3.
**Failure looks like:** another number -- record each object by name. A throw on an unread collection
is a failed read, never a `0`.

Result:

### T.2. The test user holds no active assignment, and window B signs out

- [ ] **T.2** Window B. After section 6, the test user has no active directory role, group or Azure assignment, and the window signs out.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
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
