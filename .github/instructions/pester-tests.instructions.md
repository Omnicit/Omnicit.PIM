---
description: "Use when writing, reviewing, or debugging Pester tests for Omnicit.PIM. The conventions live in CLAUDE.md, section Testing Conventions: importing the module by name, module-scoped mocks of Initialize-OPIMAuth, Invoke-OPIMGraphRequest and Az.Resources cmdlets, pipeline input objects, type-tagged output, and ShouldProcess testing. Never call live APIs in tests."
applyTo: "tests/**/*.ps1"
---

# Pester Test Conventions -- Omnicit.PIM

The conventions for this repository's tests live in [CLAUDE.md](../../CLAUDE.md), section
"Testing Conventions". Read that section before writing, reviewing or changing a test; it is the
single owner of those rules, and this file only points there.

The sections "SECURITY (Hard Rules - High Privilege)" and "Error Handling" in the same file say what
a test must never do and which errors a function is expected to emit.
