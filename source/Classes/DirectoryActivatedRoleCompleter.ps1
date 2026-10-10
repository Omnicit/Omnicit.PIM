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
            # -WarningAction SilentlyContinue: a scope that cannot be read is a warning of the listing,
            # which tab completion must not print into the prompt.
            $Listed = @(& ([scriptblock]::Create('Get-OPIMDirectoryRole -Activated -WarningAction SilentlyContinue')))
            [List[CompletionResult]]$Result = @(
                Get-OPIMCompletionText -Pillar Directory -InputObject $Listed -WordToComplete $WordToComplete `
                    -FakeBoundParameters $FakeBoundParameters -CommandName $CommandName
            )
            Write-Progress -Id 51806 -Activity 'Get Activated Directory Roles' -Completed
            return $Result
        } catch {
            # A failed listing's record can point at the request whose Authorization header carries the bearer token; scrub it first, as every catch on a transport path does.
            Remove-OPIMErrorRecord -Record $PSItem
            Write-Host ''
            Write-Host -Fore Red "Completer Error: $PSItem"
            return $null
        }
    }
}
