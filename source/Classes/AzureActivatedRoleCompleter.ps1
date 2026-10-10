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
            # -WarningAction SilentlyContinue: the Azure sign-in can warn (an AZURE_AUTHORITY_HOST that
            # names another authority), which tab completion must not print into the prompt.
            $Listed = @(& ([scriptblock]::Create('Get-OPIMAzureRole -Activated -WarningAction SilentlyContinue')))
            [List[CompletionResult]]$Result = @(
                Get-OPIMCompletionText -Pillar Azure -InputObject $Listed -WordToComplete $WordToComplete `
                    -FakeBoundParameters $FakeBoundParameters -CommandName $CommandName
            )
            Write-Progress -Id 51806 -Activity 'Get Activated Azure Roles' -Completed
            return $Result
        } catch {
            Write-Host ''
            Write-Host -Fore Red "Completer Error: $PSItem"
            return $null
        }
    }
}
