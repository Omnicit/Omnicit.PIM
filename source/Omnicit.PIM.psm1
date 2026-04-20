# ============================================================
# SOURCE-MODE LOADER — FOR LOCAL DEVELOPMENT ONLY
# ============================================================
# This file is used exclusively when importing the module directly from source:
#
#   Import-Module ./Source/Omnicit.PIM.psd1 -Force
#
# It is NOT part of the compiled (built) module. During a build (./build.ps1),
# ModuleBuilder merges all Classes/, Private/, and Public/ .ps1 files into a
# single Omnicit.PIM.psm1, prepends any `using namespace` statements, and
# appends suffix.ps1. The contents of this source psm1 are therefore discarded
# and replaced entirely by that merged output.
#
# Initialization that must run in the compiled module (type data, format data)
# belongs in source/suffix.ps1, which is appended by ModuleBuilder as
# configured in build.yaml (`suffix: suffix.ps1`).
# ============================================================

# Load order: Classes (completers/types) -> Private (helpers) -> Public (exported functions)
$PublicFunctions = [System.Collections.Generic.List[string]]::new()
foreach ($ScriptPathItem in 'Classes', 'Private', 'Public') {
    $ScriptSearchFilter = [io.path]::Combine($PSScriptRoot, $ScriptPathItem, '*.ps1')
    Get-ChildItem -Recurse -Path $ScriptSearchFilter -Exclude '*.Tests.ps1' -ErrorAction SilentlyContinue |
        ForEach-Object {
            . $PSItem
            if ($ScriptPathItem -eq 'Public') {
                $PublicFunctions.Add($PSItem.BaseName)
            }
        }
}

Export-ModuleMember -Function $PublicFunctions -Alias *

# TypesToProcess is disabled in the manifest: Remove-Module does not clean type data, so re-importing in the
# same session fails with "member already present" errors. Loading here with -ErrorAction SilentlyContinue
# silently skips already-registered members on subsequent imports.
Update-TypeData -AppendPath "$PSScriptRoot\Formats\Omnicit.PIM.Types.ps1xml" -ErrorAction SilentlyContinue

# Formats are loaded natively via FormatsToProcess in the manifest. All format targets are
# Omnicit.PIM.* custom types — no Az-native type overrides remain, so the AppendPath precedence
# issue with Az.Resources no longer applies.
