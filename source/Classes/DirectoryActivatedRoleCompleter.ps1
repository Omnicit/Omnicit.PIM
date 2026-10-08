using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Management.Automation
using namespace System.Management.Automation.Language

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Write-Host used intentionally in completer for error visibility')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Result is used in return statement')]
class DirectoryActivatedRoleCompleter : IArgumentCompleter {
    [IEnumerable[CompletionResult]] CompleteArgument(
        [string] $CommandName,
        [string] $ParameterName,
        [string] $WordToComplete,
        [CommandAst] $CommandAst,
        [IDictionary] $FakeBoundParameters
    ) {
        $ErrorActionPreference = 'Stop'
        try {
            Write-Progress -Id 51806 -Activity 'Get Activated Directory Roles' -Status 'Fetching from Azure' -PercentComplete 1
            $Listed = @(& ([scriptblock]::Create('Get-OPIMDirectoryRole -Activated')))
            [List[CompletionResult]]$Result = @(
                Get-OPIMCompletionText -Pillar Directory -InputObject $Listed -WordToComplete $WordToComplete `
                    -FakeBoundParameters $FakeBoundParameters -CommandName $CommandName
            )
            Write-Progress -Id 51806 -Activity 'Get Activated Directory Roles' -Completed
            return $Result
        } catch {
            Write-Host ''
            Write-Host -Fore Red "Completer Error: $PSItem"
            return $null
        }
    }
}
