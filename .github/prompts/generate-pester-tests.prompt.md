---
description: "Generate a Pester unit test file for a single Omnicit.PIM public function."
---

You are generating a Pester unit test file for **one** function in the Omnicit.PIM PowerShell module.

**Target function:** `${input:functionName}`
*(Example: `Get-OPIMDirectoryRole`, `Enable-OPIMDirectoryRole`, `Disable-OPIMAzureRole`)*

**Authority:** [CLAUDE.md](../../CLAUDE.md), section "Testing Conventions", owns every test rule for this repository; read it first. Where this prompt and that section differ, the section wins.

---

## Step 1 -- Read the source files

Read the source file for the target function:

```
source/Public/${input:functionName}.ps1
```

Also read the private helpers it may call:

- `source/Private/Invoke-OPIMGraphRequest.ps1`
- `source/Private/Get-MyId.ps1`
- `source/Private/Resolve-RoleByName.ps1`
- `source/Private/Convert-GraphHttpException.ps1`

Identify:
- All parameters and parameter sets
- Which external APIs are called (`Invoke-OPIMGraphRequest`, `Get-AzRole*`, `New-AzRole*`, etc.)
- The output type name(s) tagged on returned objects (e.g. `Omnicit.PIM.DirectoryEligibilitySchedule`)
- Whether the function supports `-WhatIf` (`SupportsShouldProcess`)
- Whether it accepts pipeline input

---

## Step 2 -- Conventions (apply every rule below -- do not deviate)

### File structure

- Output path: `tests/Unit/Public/${input:functionName}.Tests.ps1`
- **One `Describe` block** per file; name must match the function exactly.
- `BeforeAll` at the `Describe` level imports the module **by name** (never by path -- coverage is measured against the built module); `AfterAll` removes it.
- Use `Context` blocks to group scenarios; use `BeforeAll` inside each `Context` for shared arrangement.
- Use `BeforeEach` only when state must reset per `It`.
- `It` descriptions start with a third-person singular verb: *calls*, *returns*, *writes*, *throws*.

```powershell
Describe '${input:functionName}' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When called with default parameters (happy path)' {
        BeforeAll {
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
            # Arrange the remaining mocks here
        }
        It 'calls <API> with the expected method' { ... }
        It 'returns a typed PSCustomObject' { ... }
    }

    Context 'When the result set is empty' {
        It 'returns nothing without throwing' { ... }
    }

    Context 'When the API returns an error' {
        It 'writes a non-terminating error' { ... }
    }
}
```

### Contexts to cover

Include **all** that apply to the target function:

| Scenario | Required for |
|---|---|
| Happy path -- default parameters | All functions |
| Empty result set -- returns nothing, no throw | All `Get-*` functions |
| API error path -- non-terminating error emitted | All functions |
| `-WhatIf` / ShouldProcess -- assert 0 API calls | `Enable-*` and `Disable-*` only |
| `-Activated` parameter set | `Get-*` and `Disable-*` where applicable |
| `-All` parameter set | `Get-*` where applicable |
| `-Identity` and `-Filter` parameters | `Get-*` where applicable |
| Pipeline input (`-Role` / `-Group` parameter set) | `Enable-*` and `Disable-*` |
| `-Until` overrides `-Hours` | `Enable-*` functions |
| Policy validation errors (`JustificationRule`, `ExpirationRule`) | `Enable-*` functions |
| `ActiveDurationTooShort` error | `Disable-*` functions |
| `-PassThru` switch | `Wait-OPIMDirectoryRole` |

### Mocking -- authentication

The `Get-`, `Enable-` and `Disable-` cmdlets for directory roles, Azure roles and groups, and `Wait-OPIMDirectoryRole`, call `Initialize-OPIMAuth` first. **Always** mock it, in every `Context` that calls the function:

```powershell
Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
```

### Mocking -- Graph API

**Never make real API calls.** Mock the module's Graph wrapper, `Invoke-OPIMGraphRequest`, always with `-ModuleName Omnicit.PIM` and a `-ParameterFilter` to scope the mock:

```powershell
Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
    return @{
        value = @(
            @{
                id               = 'elig-001'
                roleDefinitionId = 'role-def-001'
                directoryScopeId = '/'
                roleDefinition   = @{ displayName = 'Global Administrator' }
            }
        )
    }
} -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }
```

To simulate a Graph error, throw what the wrapper throws -- an `ErrorRecord` whose `FullyQualifiedErrorId` is the Graph error code:

```powershell
Mock -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest {
    $PSCmdlet.ThrowTerminatingError(
        [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('InsufficientPermissions: Access denied'),
            'InsufficientPermissions',
            [System.Management.Automation.ErrorCategory]::OperationStopped,
            $null
        )
    )
} -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }
```

> Without `-ParameterFilter`, all Graph calls (including scope-rehydration second calls) share the same mock, which causes unexpected failures in multi-call scenarios.

### Mocking -- Azure RBAC (Az.Resources)

```powershell
Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule        { return @() }
Mock -ModuleName Omnicit.PIM Get-AzRoleAssignmentScheduleInstance { return @() }
Mock -ModuleName Omnicit.PIM New-AzRoleAssignmentScheduleRequest  { }
```

### Mocking -- Private helpers

Private helpers live in module scope; always use `-ModuleName Omnicit.PIM`:

```powershell
Mock -ModuleName Omnicit.PIM Get-MyId              { return 'user-object-id-001' }
Mock -ModuleName Omnicit.PIM Resolve-RoleByName    { return $FakeRoleObject }
Mock -ModuleName Omnicit.PIM Restore-GraphProperty { return $InputObject }
```

> Without `-ModuleName`, Pester mocks the caller's scope; the module's internal calls are unaffected.

### Constructing pipeline input objects

```powershell
$EligibleRole = [PSCustomObject]@{
    id               = 'elig-001'
    roleDefinitionId = 'role-def-001'
    directoryScopeId = '/'
    principalId      = 'principal-001'
    roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
    principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
}
$EligibleRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
```

**Type names:**

| Pipeline target | TypeName |
|---|---|
| `Enable/Disable-OPIMDirectoryRole -Role` | `Omnicit.PIM.DirectoryEligibilitySchedule` |
| `Enable/Disable-OPIMAzureRole -Role` | `Omnicit.PIM.AzureEligibilitySchedule` |
| `Enable/Disable-OPIMEntraIDGroup -Group` | `Omnicit.PIM.GroupEligibilitySchedule` |

### Asserting typed output

Always verify the type tag -- never assert a raw hashtable:

```powershell
$Result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleRequest'
```

### Testing -WhatIf

```powershell
It 'does not call the API when -WhatIf is specified' {
    Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -WhatIf
    Should -Invoke -ModuleName Omnicit.PIM Invoke-OPIMGraphRequest -Times 0 -Scope It
}
```

> Test `-WhatIf` via `Should -Invoke` count -- not by catching exceptions. `$PSCmdlet.ShouldProcess` is called inside the function.

### Testing error paths

```powershell
It 'writes a non-terminating error on API failure' {
    $Errors = @()
    ${input:functionName} -ErrorVariable Errors -ErrorAction SilentlyContinue
    $Errors.Count | Should -BeGreaterThan 0
}
```

### Common pitfalls

- **Never** call `Connect-MgGraph` or `Connect-AzAccount` in tests, and always mock `Initialize-OPIMAuth`.
- **ISO 8601 durations** in request body assertions: `PT1H`, not `01:00:00`.
- Import the module by name (`Import-Module Omnicit.PIM -Force`), never by a path into `source/`.

---

## Step 3 -- Generate the test file

Create `tests/Unit/Public/${input:functionName}.Tests.ps1` following every rule above.

Do **not** create any other files. Do **not** add markdown documentation or summary comments.
