# TypesToProcess is disabled in the manifest: Remove-Module does not clean type data, so re-importing in the
# same session fails with "member already present" errors. Loading here with -ErrorAction SilentlyContinue
# silently skips already-registered members on subsequent imports.
Update-TypeData -AppendPath "$PSScriptRoot\Formats\Omnicit.PIM.Types.ps1xml" -ErrorAction SilentlyContinue

# Formats are loaded natively via FormatsToProcess in the manifest. All format targets are
# Omnicit.PIM.* custom types — no Az-native type overrides remain, so the AppendPath precedence
# issue with Az.Resources no longer applies.
