using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Management.Automation
using namespace System.Management.Automation.Language

class GroupEligibleCompleter : IArgumentCompleter {
    [IEnumerable[CompletionResult]] CompleteArgument(
        [string] $CommandName,
        [string] $ParameterName,
        [string] $WordToComplete,
        [CommandAst] $CommandAst,
        [IDictionary] $FakeBoundParameters
    ) {
        $ErrorActionPreference = 'Stop'
        try {
            Write-Progress -Id 51806 -Activity 'Get Eligible PIM Groups' -Status 'Fetching from Azure' -PercentComplete 1
            [List[CompletionResult]]$Result = Get-OPIMEntraIDGroup | ForEach-Object {
                "'{0} - {1} ({2})'" -f $PSItem.group.displayName, $PSItem.accessId, $PSItem.id
            } | Where-Object {
                if (-not $wordToComplete) { return $true }
                $PSItem.replace("'", '') -like "$($wordToComplete.replace("'",''))*"
            }
            Write-Progress -Id 51806 -Activity 'Get Eligible PIM Groups' -Completed
            return $Result
        } catch {
            Write-Host ''
            Write-Host -Fore Red "Completer Error: $PSItem"
            return $null
        }
    }
}
