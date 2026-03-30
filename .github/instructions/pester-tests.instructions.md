---
description: "Use when writing, reviewing, or debugging Pester tests for Omnicit.PIM. Covers Describe/Context/It nesting, mocking Invoke-MgGraphRequest and Az.Resources cmdlets, constructing pipeline input objects, asserting type-tagged output, and ShouldProcess testing. Never call live APIs in tests."
applyTo: "tests/**/*.ps1"
---

# Pester Test Conventions — Omnicit.PIM

## File and Naming

- Unit tests live in `tests/Unit/Public/<FunctionName>.Tests.ps1` or `tests/Unit/Private/<FunctionName>.Tests.ps1`.
- Filename must match the function under test: `Enable-OPIMDirectoryRole.Tests.ps1`.
- The QA suite (`tests/QA/module.tests.ps1`) expects a unit test file to exist at `tests\<FunctionName>.Tests.ps1` — keep this path resolving correctly.

## Nesting Structure

```powershell
Describe 'Enable-OPIMDirectoryRole' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }

    Context 'When called with -RoleName (happy path)' {
        BeforeAll {
            # Arrange mocks here
        }

        It 'calls Invoke-MgGraphRequest with POST' { ... }
        It 'outputs a typed PSCustomObject' { ... }
    }

    Context 'When the Graph API returns an error' {
        It 'writes a non-terminating error' { ... }
    }
}
```

- One `Describe` per function file.
- Use `Context` to group related scenarios (happy path, error cases, parameter set variations).
- Use `BeforeAll` inside each `Context` for shared arrangement; use `BeforeEach` only when state must reset per `It`.
- `It` descriptions start with a verb in third-person singular: _"calls"_, _"returns"_, _"writes"_, _"throws"_.

## Mocking Rules

**Never make real API calls.** Mock every external boundary at the start of each `Context`:

### Graph API

```powershell
Mock Invoke-MgGraphRequest {
    return @{
        value = @(
            @{
                id                  = 'elig-001'
                roleDefinitionId    = 'role-def-001'
                directoryScopeId    = '/'
                roleDefinition      = @{ displayName = 'Global Administrator' }
            }
        )
    }
} -ParameterFilter { $Method -eq 'GET' }
```

- Always provide a `-ParameterFilter` to scope the mock to the relevant method or URI.
- To simulate an error, throw a `System.Net.Http.HttpRequestException` (or `Microsoft.Graph.ServiceException`-style object); `Convert-GraphHttpException` parses the JSON body from the exception message:

```powershell
Mock Invoke-MgGraphRequest {
    $body = '{"error":{"code":"InsufficientPermissions","message":"Access denied"}}'
    throw [System.Net.Http.HttpRequestException]::new($body)
} -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }
```

### Azure RBAC (Az.Resources)

```powershell
Mock Get-AzRoleEligibilitySchedule { return @() }
Mock Get-AzRoleAssignmentScheduleInstance { return @() }
Mock New-AzRoleAssignmentScheduleRequest { }
```

To simulate a terminating error from an Az.Resources cmdlet with a specific `FullyQualifiedErrorId`, use `$PSCmdlet.ThrowTerminatingError()` — **not** `throw [ErrorRecord]`. Pester mock wrappers have `[CmdletBinding()]`, so `$PSCmdlet` is available. Using `throw [ErrorRecord]` causes PowerShell to re-wrap the exception on catch, losing the original `ErrorId`:

```powershell
Mock -ModuleName Omnicit.PIM Get-AzRoleEligibilitySchedule {
    $PSCmdlet.ThrowTerminatingError(
        [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('Insufficient permissions'),
            'InsufficientPermissions',
            [System.Management.Automation.ErrorCategory]::PermissionDenied,
            $null
        )
    )
}
```

### Private helpers

Private helpers are in module scope — mock them by module:

```powershell
Mock -ModuleName Omnicit.PIM Get-MyId { return 'user-object-id-001' }
Mock -ModuleName Omnicit.PIM Resolve-RoleByName { return $fakeRoleObject }
Mock -ModuleName Omnicit.PIM Restore-GraphProperty { return $InputObject }
```

## Constructing Pipeline Input Objects

Use typed `PSCustomObject` matching the module's type names to simulate piped input (e.g., from `Get-OPIMDirectoryRole`):

```powershell
$eligibleRole = [PSCustomObject]@{
    id               = 'elig-001'
    roleDefinitionId = 'role-def-001'
    directoryScopeId = '/'
    roleDefinition   = [PSCustomObject]@{ displayName = 'Global Administrator' }
    principal        = [PSCustomObject]@{ displayName = 'Jane Doe' }
}
$eligibleRole.PSObject.TypeNames.Insert(0, 'Omnicit.PIM.DirectoryEligibilitySchedule')

# Pipe it:
$result = $eligibleRole | Enable-OPIMDirectoryRole -Justification 'Testing'
```

**Type names to use:**

| Cmdlet input | TypeName |
|---|---|
| `Enable/Disable-OPIMDirectoryRole -Role` | `Omnicit.PIM.DirectoryEligibilitySchedule` |
| `Enable/Disable-OPIMAzureRole -Role` | `Omnicit.PIM.AzureEligibilitySchedule` |
| `Enable/Disable-OPIMEntraIDGroup -Group` | `Omnicit.PIM.GroupEligibilitySchedule` |

## Asserting Typed Output

Always verify the output carries the correct type tag (never assert raw hashtable):

```powershell
$result.PSObject.TypeNames | Should -Contain 'Omnicit.PIM.DirectoryAssignmentScheduleRequest'
```

## Testing ShouldProcess / -WhatIf

All `Enable-*` and `Disable-*` functions support `-WhatIf`. Test that no API call is made:

```powershell
It 'does not call the API when -WhatIf is specified' {
    Enable-OPIMDirectoryRole -RoleName 'Global Administrator' -WhatIf
    Should -Invoke Invoke-MgGraphRequest -Times 0 -Scope It
}
```

## Testing Error Paths

```powershell
It 'writes a non-terminating error on InsufficientPermissions' {
    Mock Invoke-MgGraphRequest {
        throw [System.Net.Http.HttpRequestException]::new(
            '{"error":{"code":"InsufficientPermissions","message":"Use -All"}}'
        )
    }

    { Get-OPIMDirectoryRole } | Should -Not -Throw
    # Optionally capture error stream:
    $errors = @()
    Get-OPIMDirectoryRole -ErrorVariable errors -ErrorAction SilentlyContinue
    $errors.Count | Should -BeGreaterThan 0
}
```

## Module Import in BeforeAll

Always import from source (not the built output) so tests run against the current code:

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../../Source/Omnicit.PIM.psd1" -Force
}

AfterAll {
    Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
}
```

Adjust the relative path depth to match the test file location:
- `tests/Unit/Public/` → `../../../Source/Omnicit.PIM.psd1`
- `tests/Unit/Private/` → `../../../Source/Omnicit.PIM.psd1`

## Testing Private Functions

Private functions (in `Source/Private/`) are not exported, so they cannot be called directly from outside the module. Wrap the entire body of each `It` block in `InModuleScope Omnicit.PIM { }` to reach them:

```powershell
It 'returns the expected value' {
    InModuleScope Omnicit.PIM {
        # Call the private function directly here
        $result = Get-MyId
        $result | Should -BeOfType [Guid]
    }
}
```

> `InModuleScope` is required to **call** a private function. It is **not** required for public function tests — use `-ModuleName Omnicit.PIM` on `Mock` only for those.

### Resetting module-scoped state

Some private functions use `$SCRIPT:*` variables as caches (e.g., `Get-MyId` uses `$SCRIPT:_MyIDCache`). Always reset these at the start of each `It` (or in a `BeforeEach`) to prevent cross-test state leakage:

```powershell
BeforeEach {
    InModuleScope Omnicit.PIM { $SCRIPT:_MyIDCache = $null }
}
```

Only apply this when the function under test explicitly uses a module-scoped variable — do not add it as a blanket pattern to every test file.

## Common Pitfalls

- **Never call `Connect-MgGraph` or `Connect-AzAccount`** in tests — mock all dependencies instead.
- **`-ModuleName Omnicit.PIM` is required** when mocking private functions — without it, Pester mocks the caller's scope and the module's internal calls are unaffected.
- **ISO 8601 durations** — if asserting the request body, duration is formatted as `PT1H` not `01:00:00`. Use `[System.Xml.XmlConvert]::ToString(...)` to generate expected values.
- **`$PSCmdlet.ShouldProcess`** is called inside the function; test `-WhatIf` behavior via `Should -Invoke` assertion count, not by catching exceptions.
- **`-ParameterFilter` on `Invoke-MgGraphRequest`** — without it, all Graph calls (including scope-rehydration second calls) match the same mock, which may cause unexpected behavior in multi-call scenarios.
