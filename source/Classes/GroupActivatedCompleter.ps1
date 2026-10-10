using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Management.Automation
using namespace System.Management.Automation.Language

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Write-Host used intentionally in completer for error visibility')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Result is used in return statement')]
class GroupActivatedCompleter : IArgumentCompleter {
    [IEnumerable[CompletionResult]] CompleteArgument(
        [string] $CommandName,
        [string] $ParameterName,
        [string] $WordToComplete,
        [CommandAst] $CommandAst,
        [IDictionary] $FakeBoundParameters
    ) {
        $ErrorActionPreference = 'Stop'
        try {
            # Scope 5b: the transports never wait out throttling while this flag is set, so a throttled
            # listing fails at once instead of holding the prompt. Set and cleared through
            # [scriptblock]::Create, as the listing is called, so both resolve in the same module.
            & ([scriptblock]::Create('Set-OPIMCompletionState -InProgress $true'))
            Write-Progress -Id 51806 -Activity 'Get Activated PIM Groups' -Status 'Fetching from Azure' -PercentComplete 1
            $Listed = @(& ([scriptblock]::Create('Get-OPIMEntraIDGroup -Activated')))
            [List[CompletionResult]]$Result = @(
                Get-OPIMCompletionText -Pillar Group -InputObject $Listed -WordToComplete $WordToComplete `
                    -FakeBoundParameters $FakeBoundParameters -CommandName $CommandName
            )
            Write-Progress -Id 51806 -Activity 'Get Activated PIM Groups' -Completed
            return $Result
        } catch {
            # A failed listing's record can point at the request whose Authorization header carries
            # the bearer token; scrub it first, as every catch on a transport path does.
            Remove-OPIMErrorRecord -Record $PSItem
            Write-Host ''
            Write-Host -Fore Red "Completer Error: $PSItem"
            return $null
        } finally {
            # Cleared on every path, a failed listing included, so a later ordinary command still
            # waits out throttling.
            & ([scriptblock]::Create('Set-OPIMCompletionState -InProgress $false'))
        }
    }
}
