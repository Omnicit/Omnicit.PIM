# Live verification checklists

This folder holds the live-verification checklists for this module. Each one is written while a
branch is in flight and is then run in the operator's designated test tenant -- never a customer
tenant -- and only when the operator has asked for that run. The module runs there as a dedicated
delegated test user, and the run's setup and teardown run as a dedicated app identity whose only
credential is a certificate; neither is ever the operator's own account. Nothing in CI ever
authenticates to a tenant (`CLAUDE.md`, SECURITY rule 1). The module activates privileged Entra ID
directory roles, Azure resource roles and PIM group memberships, so a live run is always a
deliberate act the operator switches on. The checklists record what was actually executed and what
came back, which is what lets a later reader tell a verified claim from an assumed one. No
checklist is committed yet; the first one arrives with the first live-verified change.

That also makes this folder the one place in the repository where live tenant console output is
pasted in on purpose. The rules below exist so the output can be kept without keeping the tenant
data inside it.

## Editing rule -- redact before you commit

Before a checklist is committed, every tenant identifier pasted from console output is replaced with
a placeholder:

- **Object ids** become `00000000-0000-0000-0000-0000000000NN`. `NN` counts up from `01` per
  DISTINCT identifier, in first-appearance order, and restarts in each file. The same identifier
  always gets the same placeholder within a file. If it does not, the checklist's own traceability
  breaks: several checks turn on two ids being the same, or on two ids differing.
- **An abbreviated id** in console output -- the `abcd1234-...` form some views print -- is redacted
  too, and is written out as the FULL placeholder, not an abbreviated one. Eight hex characters of a
  real object id is still a correlatable partial identifier, and a file showing a real prefix beside
  a placeholder for the same object contradicts itself.
- **Email addresses** outside `example.com`, `contoso.com` and `fabrikam.com` become
  `person1@example.com`, `person2@example.com`, ... on the same per-file, first-appearance rule.
- **A tenant's initial domain** -- the label in front of `.onmicrosoft.com` -- becomes `contoso`,
  or `fabrikam` where a second tenant has to be told apart from the first.
- **Credentials never go in at all -- and a credential is ROTATED, not redacted.** See the section
  below; this is the one rule here that redaction does not solve.

**Display names of test objects may stay.** A name a checklist created for its own run is not an
identifier: it is what makes the checklist readable, and it resolves to nothing outside the tenant
that no longer holds the object.

**The mapping from a real value to its placeholder is never written down in this repository.** Not
in a comment, not in a checklist appendix, not in a commit message, not in a scratch file inside the
working tree. A mapping table turns every placeholder back into the identifier it replaced, which
undoes the whole exercise. For the same reason, a real value never goes into an assertion message, a
test name, a commit message or a report -- refer to a hit by file and line number only.

## The placeholder register

Placeholders are allocated under two different rules, and confusing them is how they collide.

- **Inside a live-verification checklist**, `NN` restarts at `01` per file, as the rule above says.
  The same `NN` therefore denotes a DIFFERENT object in a different checklist, and that is fine:
  each checklist is read on its own.
- **Everywhere else** -- `source/`, `tests/`, `README.md` and `CHANGELOG.md` -- a placeholder is
  allocated GLOBALLY and means one slot across the whole repository, because the same fixture is
  read from several files at once. Those four are exactly what the gate scans for this rule.

The register below is the second rule's allocation. **Its only purpose is to stop two different
objects from being given the same placeholder**, which is the defect redaction hits more often than
any other: a redaction pass reuses a number, and from then on two unrelated objects look like one.

`tests/QA/dochygiene.tests.ps1` reads this register and fails on the ways it can disagree with
itself or with the tree: two rows whose slots overlap, a slot description that repeats, a table
without exactly one FREE row, an "Allocate from" sentence below that disagrees with the FREE rows,
a slot taken at or above a FREE start that is not one of the named outliers, a placeholder cell it
cannot read, and a placeholder used in `source/`, `tests/`, `README.md` or `CHANGELOG.md` that is
not registered here as taken. What it still cannot check is whether a description means what the
last person thought it meant: two objects given one registered slot look, to the gate, like one
object used twice. **The unique description per row is that human check.** Writing one forces you
to say what slot you are taking, and a slot that is already described is a collision you can see
before you commit.

Each row is a placeholder, a GENERIC description of the slot, and whether it is taken. **A
description says what KIND of object occupies the slot and where it is read -- never which object.**
Naming the object in clear text would rebuild the mapping this file just forbade.

| Placeholder | Slot (generic) | Status |
|---|---|---|
| `...000` | the conventional "any id" stand-in in help examples and README | taken |
| `...001` - `...005` | fixture ids in the unit tests: tenant ids in the tenant-map, configuration and sign-in tests | taken |
| `...006` | a group id in README's tenant-map example | taken |
| `...007` and up | -- | **FREE. Allocate from here.** |
| `...099` | a deliberately different tenant id in the configuration tests | taken |

Addresses follow the same global rule outside the checklists:

| Placeholder | Slot (generic) | Status |
|---|---|---|
| `person1` and up | -- | **FREE. Allocate from here.** |

`...099` sits outside the counting sequence and is listed so it is not handed out twice. Allocate
new object ids from `...007` and new addresses from `person1`, and add a row here in the same commit
that uses them -- a placeholder that is used but not registered is exactly the state the next person
allocates over.

**Four v4-shaped values are deliberately NOT placeholders**, and they are not in this register
because they name nothing in any tenant: the module's own GUID in the manifest, the Microsoft Graph
Command Line Tools first-party application id, and the Microsoft Entra built-in role template ids
for Global Administrator and Privileged Role Administrator, which a help example and `README.md`
use. They are named here in words only, since every GUID in a file under `docs/` must be a
placeholder, this file included. They are pinned by value in `tests/QA/dochygiene.tests.ps1`, which
fails if one of them stops being used. That pinned list is not a place to put a new value -- see
"What enforces this" below for what the gate does instead.

## Credentials -- the rule redaction cannot satisfy

Console output from this module can contain credentials, not only identifiers. The one that arrives
by accident is a **bearer token**, which nobody pastes on purpose. A failed Graph call produces an
`ErrorRecord` whose `TargetObject` is the raw `HttpRequestMessage`, and rendering that record --
with `Format-List`, in a transcript, or by pasting a console scrollback -- prints
`Authorization: Bearer <jwt>` in full. It appears in the middle of an otherwise ordinary error dump,
which is exactly why it gets missed. A **client secret** is the other shape the gate watches for. The
setup identity has none -- its only credential is a certificate -- so one appearing here is a
mistake by definition.

**An object id is a name; a credential is access.** Replacing an id with a placeholder closes that
leak. Replacing a credential with a placeholder closes nothing: by the time anyone notices, the
value has been committed, pushed, fetched by CI and cloned. So the rule is different in kind from
the ones above:

1. **Never paste one into a tracked file.** Not even briefly, not even "to be cleaned up before the
   PR". Redaction is the recovery path, not the plan.
2. **If one did reach a tracked file, ROTATE what it grants.** A client secret is deleted in the app
   registration and a new one issued. A bearer token expires on its own, but the session that
   minted it does not: revoke the test user's sessions. Then redact the file. Redaction alone is not
   a fix and must never be recorded as one.
3. **The record's SHAPE may stay.** Keeping
   `Authorization: Bearer <bearer-token-REDACTED>` inside a quoted error record is correct and often
   the point of the write-up -- the header's presence is the finding. Keep the structure, drop the
   value.
4. **Never quote the value in a commit message, a PR body, a test name or an assertion message.**
   That copies it out of the file it was removed from.

`tests/QA/dochygiene.tests.ps1` fails on a JWT-shaped string, an `Authorization:` header carrying an
actual value, or a client-secret-shaped string in any tracked file under `docs/`, `specs/`,
`source/` or `tests/`, and in `README.md` and `CHANGELOG.md` -- this folder included. Like the other
checks it reports file and line and never the value. Prose that merely names the header, and a
`<...>` or `REDACTED` stand-in, both pass -- the gate is aimed at values, not at vocabulary.

**A test fixture that has to be token-shaped says so in the value itself.** A test that proves the
module keeps a bearer token out of an error record or an output stream cannot do its job without
handing the module something shaped like a token, so forbidding the shape under `tests/` would
forbid exactly the security tests that matter most. Such a fixture carries `NOT-A-REAL-TOKEN` inside
the value, and the gate accepts that exactly as it accepts `REDACTED`. The marker has to be in the
VALUE, not in a comment beside it, so the declaration belongs to that literal and cannot be borrowed
by a real token pasted next to one -- which is also why a real credential pasted while debugging can
never satisfy it by accident.

A placeholder is only opaque while the real value it replaced appears nowhere else in the tree, so
redact every copy of a value, not just the first. Redaction changes files going forward; it never
rewrites history that already holds the original.

## Where raw output goes

Unredacted console output belongs in `docs/live-verification/raw/`, or in a `*.log` file in this
folder (`docs/live-verification/*.log`). Both are git-ignored (`.gitignore:30-31`), so the raw
material stays on disk while a run is being written up and is never staged. Redact on the way into
the checklist; never paste an unredacted block into a tracked `.md`.

`.gitignore` does not untrack anything already tracked, and that is deliberate here: the checklists
are the verification record and stay tracked. Only the raw material is ignored.

## What enforces this

`tests/QA/dochygiene.tests.ps1` runs as part of `./build.ps1 -Tasks test`. It covers every TRACKED
file under `docs/`, `specs/`, `source/` and `tests/`, and `README.md` and `CHANGELOG.md` at the
root -- these checklists, the payload that ships inside the built module, the test fixtures, the
repository's front page and the release notes. It reports the file and line of every hit and never
prints the value it matched; printing it would copy the identifier, or the credential, into every CI
log, which is precisely the leak the gate exists to prevent.

**An object id wrapped over two lines is found too.** A formatted table breaks a long cell at the
column edge and indents the rest, so a pasted id can land half on one line and half on the next,
where neither line matches on its own. The object-id checks therefore also read each file with its
line breaks, and the whitespace around them, removed, and report such an id at the line it starts
on. Redact a wrapped id in place, keeping the break where the console put it.

The email, tenant-domain and credential rules are the same everywhere. The **object-id** rule is
not, because the tree holds two different kinds of writing:

- **Under `docs/` and `specs/` every GUID is prose**, pasted out of a console. The rule is absolute:
  it must be a `00000000-0000-0000-0000-0000000000NN` placeholder.
- **Under `source/` and `tests/`, and in `README.md` and `CHANGELOG.md`, a GUID is a fixture or an
  example**, typed on purpose -- the registered placeholders, and a few letter-repeat fixtures such
  as `aaaaaaaa-...`. The rule there keys on the one structural property that separates a real
  identifier from an invented one: **a tenant-generated Entra ID object id, and an ARM subscription
  or resource id, is a version-4 UUID**, and no hand-written fixture needs to be. A v4-shaped GUID
  in those places is therefore either a real identifier or a fixture typed to look like one -- which
  is indistinguishable from the first by inspection, and just as bad.

  It is a shape heuristic, not a proof, and it is worth knowing which way it errs. Some well-known
  Microsoft identifiers are deliberately not v4 -- the Microsoft Graph service principal's own
  application id is hand-assigned in the all-zeros style -- and the check lets those through, which
  is right: a non-random id is a published constant, the same in every tenant, not somebody's
  directory object. The residual gap is the mirror image, a tenant identifier that is somehow not
  v4. Nothing generates one today. Redacting as you write, and the register above, stay the primary
  control.

That second rule is about SHAPE, not a list of approved values, and that is deliberate: it cannot be
satisfied by adding an entry to something. The four pinned exceptions named in the register above
are the whole of the list and do not grow.

**A tenant's initial domain is held to two fictional labels.** The label in front of
`.onmicrosoft.com`, `.onmicrosoft.us` or `.onmschina.cn` names exactly one tenant, as surely as its
tenant id does, and none of the rules above reads it. The gate fails on any such label other than
`contoso` and `fabrikam`, in every tracked file it covers. It reads `%40` as `@`, so a user principal
name URL-encoded into a request path is found, and `\.` as `.`, so a domain written as a regular
expression in a test is found too. A bare `onmicrosoft.com` with no label in front of it names no
tenant and passes. Replace a real label with `contoso`: the allowlist does not grow to make the gate
green, and an entry that no other file uses any more fails it until it is removed. Known gap:
unlike the object-id rule, the tenant-domain rule has no pass across line breaks, so a domain
wrapped by console output over two lines is not caught; redact as you write.

**The placeholder register above is read, not just cited.** The gate parses it and fails when it
disagrees with itself, on the defects listed in the register's own section, and when a placeholder
used in `source/`, `tests/`, `README.md` or `CHANGELOG.md` -- an all-zeros object id or a
`personN@example.com` address -- does not fall in a row marked taken. A reserved or FREE slot counts
as unregistered. A row that names a range covers only a tail made of three decimal digits, within
its bounds read as decimal numbers: a row `...010` - `...020` would cover `...015`, but not
`...01a`, although `...01a` lies inside that range read as hexadecimal. A row that names one
placeholder covers exactly that tail, letters included. Where it checks the register against
itself, it orders the three characters after `...` as hexadecimal. It reads a status cell as FREE
when it says FREE, as taken when it starts with "taken", and as reserved otherwise. A row it reads
only partly is reported. A row whose first cell holds no well-formed backticked `...` or `person`
token is taken for a header row and grants nothing, and a table left without its FREE row is
reported.

**A stand-in in angle brackets is written as code.** GitHub reads `<id>`, `<tenant-label>` or any
other `<word>` outside code as an HTML tag and renders nothing, so the redaction disappears from the
page and the sentence around it stops making sense. Put the stand-in inside backticks, or write it as
`\<id>` where a backtick would close a code span the line already has; quotes alone do not help. In
`CHANGELOG.md` use backticks only: the PowerShell Gallery shows its notes as plain text, where a
backslash would show instead of escaping anything. The same gate fails on such a bracket in any
tracked `.md` under `docs/` or `specs/`, and in `README.md` and `CHANGELOG.md`. Fenced blocks and
code spans are skipped. Exactly one tag outside code is allowed: the logo on the first line of
`README.md`, the first `<img>` element there whose one `src` is under `assets/`. The same tag on any
later line fails, and so does every other tag, in `README.md` too. If the logo leaves line 1, the
gate fails until it is put back or the exception is dropped.

The gate is a backstop, not a substitute for redacting as you write. It cannot see the one failure
the register above exists to prevent -- one registered placeholder given to two different objects --
because every value involved is already a valid, registered placeholder.

## Checklist template

A checklist is one file per branch, named `docs/live-verification/<branch-with-slash-as-dash>-checklist.md`:
the branch name with its slash written as a dash, so `fix/example-claim` gives
`docs/live-verification/fix-example-claim-checklist.md`. It is written while the branch is in
flight, in the shape below, which is the shape Omnicit.EntraRBAC's checklists already use. Write
every stand-in as code, as the paragraph "A stand-in in angle brackets is written as code" under
"What enforces this" says -- the headings below that carry one do so inside backticks.

**Raw console output goes to `docs/live-verification/raw/`** (git-ignored) **and is redacted on the
way into the checklist.** Nothing unredacted is pasted into the tracked `.md`. "Where raw output
goes" above has the detail, and "Editing rule" at the top has the redaction itself.

The sections, in this order:

1. **The title line**, `# Live verification checklist -- <claim> (<branch>)`: `<claim>` is one
   clause saying what the branch now does, `<branch>` the branch name, slash included.
2. **The preamble rule.** Four parts. First, the branch does not merge until every box has a
   written result, and an unticked box with no result line is an unrun check, never a passed one.
   Second, a check that is impossible to run says "cannot be verified, and therefore we do not know"
   on its result line, with the reason, and its box is marked `[~]`, never `[x]`. Third, a check
   that says **Record:** where the others say **Expect:** is one whose outcome is not known in
   advance: write down what actually happened, not what looked plausible. Fourth, the boundary: the
   file runs only in the operator's designated test tenant, never a customer tenant, and only when
   the operator has asked for the run; the module runs as the dedicated delegated test user and
   setup and teardown as a dedicated app identity, never the operator's own account; and the run
   writes to nothing outside the name prefix of its test objects.
3. **`## What changed and why this needs a live tenant`.** The changes, named by commit SUBJECT and
   never by hash, since a rebase onto `main` changes every hash; what a mock cannot show about
   them; and the objects the run creates, with the name prefix they all carry.
4. **`## What this file does not check, and why`.** Every claim of the branch that the checklist
   leaves to the unit tests, with the test file that proves it.
5. **`## Setup, once`.** Numbered `S.1`, `S.2`, ..., each a check in the same shape as the numbered
   checks below, so the setup is recorded too. A Setup check that comes before `0.1` does not call
   the module: it finds the build under test and ties it to the branch head, since the version
   alone cannot (GitVersion can compute the same version for two builds of one branch). The test
   objects are NOT created by a check. The operator's prerequisite script creates them, from
   outside the repository, as the dedicated app identity: it is planned with `-WhatIf` before it
   writes, and it writes a baseline of the tenant's counts before it creates anything. The checks
   VERIFY that step by reading the objects back as the test user; they do not perform it. The
   module itself signs in on first use, as the dedicated test user.
6. **The numbered sections and their checks.** Section 0, `### 0. Preparation`, comes first, and its
   check `### 0.1. Identity check` runs before any other check calls the module. It prints only
   `True` or `False` lines -- the signed-in account is the test user, the tenant is the test tenant
   -- and never the account or the tenant id themselves: it compares them with values the operator
   holds outside the repository and has set as variables in the session. A `False` stops the run.
   Every later section is a heading `### 1. <section title>`; each check under any section is
   `### 1.1. <title>`, `### 1.2. <title>`, and so on. Every check has, in this order:
   - the box `- [ ] **1.1** <one-line claim>`;
   - a fenced PowerShell block;
   - `**Expect:**` with what a pass looks like, or `**Record:**` where that is not known;
   - `**Failure looks like:**` with what a fail looks like, and whether to stop;
   - `Result:`, left empty when the file is written and filled in at the run.
7. **`## Teardown`.** Numbered `T.1`, `T.2`, ..., accounting for every object and every eligibility
   the run created. The prerequisite script removes them (`-Teardown`, planned with `-WhatIf`
   first, the tenant's counts compared with the baseline), and the checks VERIFY what the module can
   still see afterwards; they do not perform the removal, and a claim in a box is only what its
   block can see. An Azure resource role eligibility is removed BEFORE the resource group it sits
   under, so that none is left pointing at a scope that no longer exists. It ends by saying what is
   left in the tenant on purpose, if anything.

Five rules for the code blocks, because a later step generates a note from each checklist:

- A block starts at column 0, never indented and never inside a list item.
- A block holds no angle-bracket placeholder. Use a concrete fictional value -- the test objects
  carry one prefix, here `opim-demo-` -- and keep the redaction stand-ins out of it.
- Every block that runs the module starts with the same three lines, the prologue: it finds this
  branch's build, stops when a different build of the module is already loaded in the window, and
  imports the build otherwise. The paths are relative, so every block runs from the repository root.
- A block is run in the window that `0.1` signed in. A fresh window runs `0.1` again first, since
  the sign-in belongs to the window and its identity is what `0.1` proves. If a sign-in prompt
  appears mid-run, STOP and run `0.1` again: the module signs in again, interactively, when its
  Graph token nears expiry, and the proof of `0.1` holds only for the sign-in it checked.
- A read whose count or emptiness is the expected outcome carries `-ErrorAction Stop`. The module
  reports a failed read as a non-terminating error, so without it the failure prints a count of
  `0` -- the very value a teardown check expects. Its `Failure looks like:` says that a terminating
  error is a failed read, never a pass.

A checklist as it is written, before any run:

````markdown
# Live verification checklist -- a WhatIf activation of a group sends no request (fix/example-claim)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

Where a check says **Record:** instead of **Expect:**, the outcome is genuinely not known in
advance. Write down what actually happened rather than what looked plausible.

**This file runs only in the operator's designated test tenant** -- never a customer tenant -- and
only when the operator has asked for the run. The module runs there as the dedicated delegated test
user, and setup and teardown run as a dedicated app identity whose only credential is a
certificate; neither is ever the operator's own account. The run writes to nothing outside the
prefix `opim-demo-`. Check 0.1 proves the identity before any other check calls the module. If a
sign-in prompt appears mid-run, STOP and run check 0.1 again: the module signs in again,
interactively, when its Graph token nears expiry, and the proof of 0.1 holds only for the sign-in
it checked.

## What changed and why this needs a live tenant

- **A. The WhatIf plan of an activation** ("Show the group in the WhatIf plan"). The plan names the
  group and its access type, and sends nothing. A mock cannot show that no request reached the
  tenant, so the check counts the active assignments before and after.

The run uses one group, `opim-demo-grp`, with the test user eligible for it as a member. The
operator's prerequisite script creates both (see Setup); no check here does.

## What this file does not check, and why

- **A policy that demands a justification** is proven by the mocked tests in
  `tests/Unit/Public/Enable-OPIMEntraIDGroup.Tests.ps1`; the test tenant's policy asks for none.

## Setup, once

The operator sets the session variables `OPIM_LIVE_TEST_USER` (the test user's sign-in name) and
`OPIM_LIVE_TEST_TENANT` (the test tenant's id) from notes kept outside the repository; no checklist
holds either value. The test group and the test user's eligibility for it are created by the
operator's prerequisite script, planned with `-WhatIf` first and run as the dedicated app identity,
which also writes the baseline of the tenant's counts. The checks below read them back; they create
nothing.

### S.1. Find the build under test and tie it to the branch head

- [ ] **S.1** The newest build in `output/module/Omnicit.PIM/` was made after the branch head was committed.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$HeadTime = [datetimeoffset]::Parse((git log -1 --format=%cI))
"Branch head: $(git log -1 --format='%h %s')"
"Built version folder: $($Built.Directory.Name)"
"Built after the branch head was committed: $([datetimeoffset]$Built.LastWriteTime -gt $HeadTime)"
$Tracked = @(git status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0) { throw "git status exited with $LASTEXITCODE, so the working tree could not be read; repair the clone before any check below." }
"Tracked changes in the working tree: $($Tracked.Count)"
```

**Expect:** the branch head's hash and subject; the version folder the branch's build printed;
`Built after the branch head was committed: True`; `Tracked changes in the working tree: 0`.
**Failure looks like:** `False`, or a tracked change -- the build may not be of this head, so build
again before any check below -- or an error from `git status`, which means the working tree could
not be read at all: repair the clone before any check below. The version alone proves nothing:
GitVersion can compute the same version for two builds of one branch.

Result:

### 0. Preparation

### 0.1. Identity check

- [ ] **0.1** The signed-in account is the test user and the tenant is the test tenant.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$TestUser = $env:OPIM_LIVE_TEST_USER
$TestTenant = $env:OPIM_LIVE_TEST_TENANT
if (-not $TestUser -or -not $TestTenant) { throw 'Set OPIM_LIVE_TEST_USER and OPIM_LIVE_TEST_TENANT from the operator notes first.' }
Connect-OPIM -TenantId $TestTenant
$Context = Get-MgContext
"Signed in as the test user: $($Context.Account -eq $TestUser)"
"Signed in to the test tenant: $($Context.TenantId -eq $TestTenant)"
```

**Expect:** `Signed in as the test user: True` and `Signed in to the test tenant: True`. The block
prints neither the account nor the tenant id, and nothing pasted into the result may either.
**Failure looks like:** `False` on either line, or a `throw` -- STOP: run `Disconnect-OPIM`, close
the window and run no other check.

Result:

### 0.2. The test group is eligible for the test user

- [ ] **0.2** The test user is eligible for `opim-demo-grp` as a member, through exactly one row.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Rows = @(Get-OPIMEntraIDGroup -AccessType member -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-demo-grp' })
"Eligible member rows for opim-demo-grp: $($Rows.Count)"
```

**Expect:** `Eligible member rows for opim-demo-grp: 1`.
**Failure looks like:** any other number -- STOP: `0` means the prerequisite script did not leave the
setup this file assumes, and `2` means a second group shares the name. A terminating error from the
read is a failed read, never a `0` and never a pass -- STOP: nothing was counted.

Result:

### 1. The plan

### 1.1. A WhatIf activation changes nothing

- [ ] **1.1** The plan names `opim-demo-grp` and the number of active assignments stays the same.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
$Target = @(Get-OPIMEntraIDGroup -AccessType member -ErrorAction Stop | Where-Object { $_.group.displayName -eq 'opim-demo-grp' })
if ($Target.Count -ne 1) { throw "Expected exactly one eligible member row for opim-demo-grp, found $($Target.Count)." }
$Before = @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count
$Target | Enable-OPIMEntraIDGroup -Hours 1 -WhatIf
$After = @(Get-OPIMEntraIDGroup -Activated -ErrorAction Stop).Count
"Active group assignments before: $Before; after the WhatIf: $After"
```

**Expect:** one `What if:` line whose target is `opim-demo-grp (member)`, then
`Active group assignments before: 0; after the WhatIf: 0`.
**Failure looks like:** the `throw` -- the selection did not find exactly one row, nothing was
sent, and the setup has to be put right first. A `What if:` target other than
`opim-demo-grp (member)` is a wrong selection, and with `-WhatIf` nothing was sent either. Only an
`after` count above `before` means a request went out -- STOP. A terminating error from either count
read is a failed read, never a `0` and never a pass -- STOP: no count exists, so the check proved
nothing.

Result:

## Teardown

The prerequisite script's `-Teardown`, planned with `-WhatIf` first and run as the dedicated app
identity, removes the group and the eligibility and compares the tenant's counts with the baseline.
The check below reads back what the test user can still see. It cannot see the group object, so the
script's own report is the record of that removal.

### T.1. No assignment for a test group is left

- [ ] **T.1** The test user holds no eligible or active assignment for a group whose name starts with `opim-demo-`.

```powershell
$Built = Get-ChildItem -Path 'output/module/Omnicit.PIM/*/Omnicit.PIM.psd1' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ((Get-Module Omnicit.PIM) -and (Get-Module Omnicit.PIM).ModuleBase -ne $Built.DirectoryName) { throw 'A different build of Omnicit.PIM is loaded; use a fresh window.' }
if (-not (Get-Module Omnicit.PIM)) { Import-Module $Built.FullName }
"Assignments left for opim-demo- groups: $(@(Get-OPIMEntraIDGroup -All -ErrorAction Stop | Where-Object { $_.group.displayName -like 'opim-demo-*' }).Count)"
```

**Expect:** `Assignments left for opim-demo- groups: 0`. Nothing is left in the tenant on purpose.
**Failure looks like:** any other number -- record each remaining assignment by group name and run
the prerequisite script's teardown again. A terminating error from the read is a failed read, never
a `0` and never a pass: the teardown is then unverified, so say so on the result line.

Result:
````

After a run, the box is ticked and its `Result:` line carries the time and a verdict:

````markdown
- [x] **1.1** The plan names `opim-demo-grp` and the number of active assignments stays the same.

Result: 2026-10-07 09:15 UTC.

```text
Verdict: PASS. One What if line for opim-demo-grp (member); active assignments 0 before and 0 after.
```
````
