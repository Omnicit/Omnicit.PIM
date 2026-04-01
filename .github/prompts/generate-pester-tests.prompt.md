---
description: "Generate a Pester unit test file for a single Omnicit.PIM public function."
---

You are generating a Pester unit test file for **one** function in the Omnicit.PIM PowerShell module.

**Target function:** `${input:functionName}`
*(Example: `Get-OPIMDirectoryRole`, `Enable-OPIMDirectoryRole`, `Disable-OPIMAzureRole`)*

---

## Step 1 — Read the source files

Read the source file for the target function:

```
Source/Public/${input:functionName}.ps1
```

Also read the private helpers it may call:

- `Source/Private/Get-MyId.ps1`
- `Source/Private/Resolve-RoleByName.ps1`
- `Source/Private/Convert-GraphHttpException.ps1`

Identify:
- All parameters and parameter sets
- Which external APIs are called (`Invoke-MgGraphRequest`, `Get-AzRole*`, `New-AzRole*`, etc.)
- The output type name(s) tagged on returned objects (e.g. `Omnicit.PIM.DirectoryEligibilitySchedule`)
- Whether the function supports `-WhatIf` (`SupportsShouldProcess`)
- Whether it accepts pipeline input

---

## Step 2 — Conventions (apply every rule below — do not deviate)

### File structure

- Output path: `tests/Unit/Public/${input:functionName}.Tests.ps1`
- **One `Describe` block** per file; name must match the function exactly.
- `BeforeAll` at the `Describe` level imports the module from source; `AfterAll` removes it.
- Use `Context` blocks to group scenarios; use `BeforeAll` inside each `Context` for shared arrangement.
- Use `BeforeEach` only when state must reset per `It`.
- `It` descriptions start with a third-person singular verb: *calls*, *returns*, *writes*, *throws*.

```powershell
Describe '${input:functionName}' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../../../Source/Omnicit.PIM.psd1" -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When called with default parameters (happy path)' {
        BeforeAll {
            # Arrange mocks here
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
| Happy path — default parameters | All functions |
| Empty result set — returns nothing, no throw | All `Get-*` functions |
| API error path — non-terminating error emitted | All functions |
| `-WhatIf` / ShouldProcess — assert 0 API calls | `Enable-*` and `Disable-*` only |
| `-Activated` parameter set | `Get-*` and `Disable-*` where applicable |
| `-All` parameter set | `Get-*` where applicable |
| `-Identity` and `-Filter` parameters | `Get-*` where applicable |
| Pipeline input (`-Role` / `-Group` parameter set) | `Enable-*` and `Disable-*` |
| `-Until` overrides `-Hours` | `Enable-*` functions |
| Policy validation errors (`JustificationRule`, `ExpirationRule`) | `Enable-*` functions |
| `ActiveDurationTooShort` error | `Disable-*` functions |
| `-PassThru` switch | `Wait-OPIMDirectoryRole` |

### Mocking — Graph API

**Never make real API calls.** Always provide `-ParameterFilter` to scope the mock:

```powershell
Mock Invoke-MgGraphRequest {
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
} -ParameterFilter { $Method -eq 'GET' }
```

To simulate a Graph error:

```powershell
Mock Invoke-MgGraphRequest {
    throw [System.Net.Http.HttpRequestException]::new(
        '{"error":{"code":"InsufficientPermissions","message":"Access denied"}}'
    )
} -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }
```

> Without `-ParameterFilter`, all Graph calls (including scope-rehydration second calls) share the same mock, which causes unexpected failures in multi-call scenarios.

### Mocking — Azure RBAC (Az.Resources)

```powershell
Mock Get-AzRoleEligibilitySchedule        { return @() }
Mock Get-AzRoleAssignmentScheduleInstance { return @() }
Mock New-AzRoleAssignmentScheduleRequest  { }
```

### Mocking — Private helpers

Private helpers live in module scope; always use `-ModuleName Omnicit.PIM`:

```powershell
Mock -ModuleName Omnicit.PIM Get-MyId             { return 'user-object-id-001' }
Mock -ModuleName Omnicit.PIM Resolve-RoleByName   { return $fakeRoleObject }
Mock -ModuleName Omnicit.PIM Restore-GraphProperty { return $InputObject }
```

> Without `-ModuleName`, Pester mocks the caller's scope; the module's internal calls are unaffected.

### Constructing pipeline input objects

```powershell
$eligibleRole = [PSCustomObject]@{
    id               = 'elig-001'
    roleDefinitionId = 'role-def-001'
    directoryScopeId = '/'
    principalId      = 'principal-001'
    roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
    principal        = [PSCustomObject]@{ displayName = 'Jane Doe'; userPrincipalName = 'jane@contoso.com' }
}
$eligibleRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')
```

**Type names:**

| Pipeline target | TypeName |
|---|---|
| `Enable/Disable-OPIMDirectoryRole -Role` | `Omnicit.PIM.DirectoryEligibilitySchedule` |
| `Enable/Disable-OPIMAzureRole -Role` | `Omnicit.PIM.AzureEligibilitySchedule` |
| `Enable/Disable-OPIMEntraIDGroup -Group` | `Omnicit.PIM.GroupEligibilitySchedule` |

### Asserting typed output

Always verify the type tag — never assert a raw hashtable:

```powershell
$result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleRequest'
```

### Testing -WhatIf

```powershell
It 'does not call the API when -WhatIf is specified' {
    Enable-OPIMDirectoryRole -RoleName 'Global Administrator (elig-001)' -WhatIf
    Should -Invoke Invoke-MgGraphRequest -Times 0 -Scope It
}
```

> Test `-WhatIf` via `Should -Invoke` count — not by catching exceptions. `$PSCmdlet.ShouldProcess` is called inside the function.

### Testing error paths

```powershell
It 'writes a non-terminating error on API failure' {
    $errors = @()
    ${input:functionName} -ErrorVariable errors -ErrorAction SilentlyContinue
    $errors.Count | Should -BeGreaterThan 0
}
```

### Common pitfalls

- **Never** call `Connect-MgGraph` or `Connect-AzAccount` in tests.
- **ISO 8601 durations** in request body assertions: `PT1H`, not `01:00:00`.
- Module import path for `tests/Unit/Public/` is `"$PSScriptRoot/../../../Source/Omnicit.PIM.psd1"`.

---

## Step 3 — Generate the test file

Create `tests/Unit/Public/${input:functionName}.Tests.ps1` following every rule above.

Do **not** create any other files. Do **not** add markdown documentation or summary comments.
