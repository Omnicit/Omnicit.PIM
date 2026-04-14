using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Management.Automation
using namespace System.Management.Automation.Language

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
            [List[CompletionResult]]$Result = & ([scriptblock]::Create('Get-OPIMDirectoryRole -Activated')) | ForEach-Object {
                $Scope = if ($PSItem.directoryScopeId -ne '/') {
                    "-> $($PSItem.directoryScope.displayName) "
                }
                "'{0} $Scope({1})'" -f $PSItem.roleDefinition.displayName, $PSItem.id
            } | Where-Object {
                if (-not $wordToComplete) { return $true }
                $PSItem.replace("'", '') -like "$($wordToComplete.replace("'",''))*"
            }
            Write-Progress -Id 51806 -Activity 'Get Activated Directory Roles' -Completed
            return $Result
        } catch {
            Write-Host ''
            Write-Host -Fore Red "Completer Error: $PSItem"
            return $null
        }
    }
}
