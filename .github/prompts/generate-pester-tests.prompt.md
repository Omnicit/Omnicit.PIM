---
description: "Generate Pester unit tests for all Omnicit.PIM public functions following project conventions."
mode: "agent"
tools: ["read_file", "create_file", "list_dir", "semantic_search"]
---

You are generating Pester unit tests for the Omnicit.PIM PowerShell module.

## Step 1 — Read the conventions

Read the full instruction file at:
`.github/instructions/pester-tests.instructions.md`

Apply every rule in that file throughout this task.

## Step 2 — Inventory source functions

Read each of the following source files from `source/Public/` to understand parameters, pipeline input, output type names, and which external APIs they call:

- `source/Public/Get-OPIMDirectoryRole.ps1`
- `source/Public/Get-OPIMAzureRole.ps1`
- `source/Public/Get-OPIMEntraIDGroup.ps1`
- `source/Public/Enable-OPIMDirectoryRole.ps1`
- `source/Public/Enable-OPIMAzureRole.ps1`
- `source/Public/Enable-OPIMEntraIDGroup.ps1`
- `source/Public/Disable-OPIMDirectoryRole.ps1`
- `source/Public/Disable-OPIMAzureRole.ps1`
- `source/Public/Disable-OPIMEntraIDGroup.ps1`
- `source/Public/Wait-OPIMDirectoryRole.ps1`
- `source/Public/Enable-OPIMMyRoles.ps1`
- `source/Public/Install-OPIMConfiguration.ps1`

Also read the private helpers that tests will need to mock:
- `source/Private/Get-MyId.ps1`
- `source/Private/Resolve-RoleByName.ps1`
- `source/Private/Convert-GraphHttpException.ps1`

## Step 3 — Produce a test plan

Before generating any files, output a markdown table with one row per function:

| Function | Test file path | Contexts to cover | Mocks required |
|---|---|---|---|

Include at minimum these contexts for every function:
- Happy path (default parameters)
- Empty result set (returns nothing, no throw)
- API error path (non-terminating error emitted)
- `-WhatIf` / ShouldProcess (Enable-* and Disable-* only — assert 0 API calls)
- Any additional parameter sets (e.g., `-Activated`, `-All`, `-Identity`, `-Filter`)

## Step 4 — Generate the test files

For each function, create the test file at:
`tests/Unit/Public/<FunctionName>.Tests.ps1`

Rules (from the instruction file — do not deviate):

1. **One `Describe` block** per file, name matches the function.
2. **`BeforeAll`** at `Describe` level imports the module:
   ```powershell
   Import-Module "$PSScriptRoot/../../../Source/Omnicit.PIM.psd1" -Force