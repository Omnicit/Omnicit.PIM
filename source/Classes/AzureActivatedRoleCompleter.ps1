using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Management.Automation
using namespace System.Management.Automation.Language

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Write-Host used intentionally in completer for error visibility')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Result is used in return statement')]
class AzureActivatedRoleCompleter : IArgumentCompleter {
    [IEnumerable[CompletionResult]] CompleteArgument(
        [string] $CommandName,
        [string] $ParameterName,
        [string] $WordToComplete,
        [CommandAst] $CommandAst,
        [IDictionary] $FakeBoundParameters
    ) {
        $ErrorActionPreference = 'Stop'
        try {
            Write-Progress -Id 51806 -Activity 'Get Activated Azure Roles' -Status 'Fetching from Azure' -PercentComplete 1
            [List[CompletionResult]]$Result = & ([scriptblock]::Create('Get-OPIMAzureRole -Activated')) | ForEach-Object {
                "'{0} -> {1} ({2})'" -f $PSItem.RoleDefinitionDisplayName, $PSItem.ScopeDisplayName, $PSItem.Name
            } | Where-Object {
                if (-not $wordToComplete) { return $true }
                $PSItem.replace("'", '') -like "$($wordToComplete.replace("'",''))*"
            }
            Write-Progress -Id 51806 -Activity 'Get Activated Azure Roles' -Completed
            return $Result
        } catch {
            Write-Host ''
            Write-Host -Fore Red "Completer Error: $PSItem"
            return $null
        }
    }
}
