# Test helper -- NOT a Pester file (no *.Tests.ps1 suffix, so Pester discovery ignores it).
#
# THE TRANSPORT TRIPWIRE. No unit test may reach a tenant or the network. Every unit test file
# installs, in its root BeforeAll and AFTER Import-Module, a replacement for each command through
# which module code reaches the transport, and checks and removes them in its root AfterAll.
# tests/QA/testhygiene.tests.ps1 proves every file does. Ported from Omnicit.EntraRBAC.
#
# Record AND throw: a throw alone is not enough, since the module's own catch blocks turn it into a
# WriteError, a verbose line or nothing at all (Invoke-OPIMArmRequest turns an Invoke-WebRequest
# failure into a record of its own, ArmTransportError). The record is what the AfterAll check reads.
# It holds parameter NAMES only -- never a value, which may be a secret or a token.
#
# The five Az.Accounts and the four Az.Resources commands stay on the list although module code no
# longer calls them: Az.Resources is still a declared dependency, and a call that came back would be
# refused here, until the Az modules leave the dependencies (Sprint 2 step 1b).
#
# Three forms, measured 2026-10-06 (Microsoft.Graph.Authentication 2.36.0, Az.Accounts 5.5.3,
# Az.Resources 9.0.3) and, for AzAuth's Get-AzToken, 2026-10-09 (AzAuth 2.9.0, a compiled cmdlet
# without IDynamicParameters):
#   Cmdlet         A global function built from the cmdlet's metadata. A function outranks a cmdlet,
#                  and a Pester Mock -ModuleName (an alias in the module scope) outranks both.
#                  AzAuth is not a dependency of Omnicit.PIM yet, so the definition builder imports
#                  it first (it runs inside the root BeforeAll, where an import is allowed).
#   DynamicCmdlet  The Az.Accounts cmdlets implement IDynamicParameters. A Pester mock of a function
#                  cannot evaluate a dynamicparam block, so the replacement carries the parameters
#                  GetDynamicParameters() returns as STATIC parameters -- otherwise a call such as
#                  Update-AzConfig -EnableLoginByWam fails to bind before the record is written.
#                  The dynamic parameter set depends on the Az.Accounts version: CI's PSResourceGet
#                  resolved 5.3.3 (2026-10-06), where four of the five cmdlets return none, and the
#                  replacement materializes whatever the loaded version returns.
#   ModuleFunction The Az.Resources commands are functions. A global replacement would shadow the
#                  imported function and its removal brings it back only through module autoloading,
#                  so this replacement lives in Omnicit.PIM's module scope instead.
# And for ForEach-Object -Parallel runspaces, where no global function or mock reaches: a generated
# stand-in Microsoft.Graph.Authentication module at the front of PSModulePath, recording into
# AppDomain data that every runspace in the process shares.
#
# Not a source/ check and not a build step, on purpose: a check in source/ would publish a test
# switch to the Gallery, and a build step would not cover a single Invoke-Pester run.

function Get-OPIMTransportTripwireName {
    <#
    .SYNOPSIS
    The sixteen commands through which module code reaches, or once reached, a tenant or the network,
    with the module that owns the real command and the form of its replacement.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()
    $Graph = 'Microsoft.Graph.Authentication'
    [ordered]@{
        'Invoke-MgGraphRequest'                = [pscustomobject]@{ Module = $Graph; Form = 'Cmdlet' }
        'Connect-MgGraph'                      = [pscustomobject]@{ Module = $Graph; Form = 'Cmdlet' }
        'Disconnect-MgGraph'                   = [pscustomobject]@{ Module = $Graph; Form = 'Cmdlet' }
        'Get-MgContext'                        = [pscustomobject]@{ Module = $Graph; Form = 'Cmdlet' }
        'Get-AzToken'                          = [pscustomobject]@{ Module = 'AzAuth'; Form = 'Cmdlet' }
        'Connect-AzAccount'                    = [pscustomobject]@{ Module = 'Az.Accounts'; Form = 'DynamicCmdlet' }
        'Disconnect-AzAccount'                 = [pscustomobject]@{ Module = 'Az.Accounts'; Form = 'DynamicCmdlet' }
        'Get-AzContext'                        = [pscustomobject]@{ Module = 'Az.Accounts'; Form = 'DynamicCmdlet' }
        'Get-AzAccessToken'                    = [pscustomobject]@{ Module = 'Az.Accounts'; Form = 'DynamicCmdlet' }
        'Update-AzConfig'                      = [pscustomobject]@{ Module = 'Az.Accounts'; Form = 'DynamicCmdlet' }
        'Get-AzRoleEligibilitySchedule'        = [pscustomobject]@{ Module = 'Az.Resources'; Form = 'ModuleFunction' }
        'Get-AzRoleAssignmentScheduleInstance' = [pscustomobject]@{ Module = 'Az.Resources'; Form = 'ModuleFunction' }
        'Get-AzRoleAssignmentScheduleRequest'  = [pscustomobject]@{ Module = 'Az.Resources'; Form = 'ModuleFunction' }
        'New-AzRoleAssignmentScheduleRequest'  = [pscustomobject]@{ Module = 'Az.Resources'; Form = 'ModuleFunction' }
        'Invoke-WebRequest'                    = [pscustomobject]@{ Module = 'Microsoft.PowerShell.Utility'; Form = 'Cmdlet' }
        'Invoke-RestMethod'                    = [pscustomobject]@{ Module = 'Microsoft.PowerShell.Utility'; Form = 'Cmdlet' }
    }
}

function Test-OPIMTransportTripwireFunction {
    <#
    .SYNOPSIS
    True when Command is a function carrying the tripwire marker.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [object]$Command
    )
    ($Command -is [System.Management.Automation.FunctionInfo]) -and
    $Command.ScriptBlock.ToString().Contains('OPIM-TRANSPORT-TRIPWIRE')
}

function New-OPIMTransportTripwireDefinition {
    <#
    .SYNOPSIS
    Builds the text of each replacement from the real command's metadata, after checking that the
    command still has the form measured for it.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()
    $Definitions = [ordered]@{}
    $Names = Get-OPIMTransportTripwireName
    foreach ($Name in @($Names.Keys)) {
        $Spec = $Names[$Name]
        # Load-bearing only when module autoloading is off: with it on, the Get-Command below loads
        # AzAuth from PSModulePath by itself.
        if ($Spec.Module -eq 'AzAuth' -and -not (Get-Module -Name AzAuth)) {
            Import-Module -Name AzAuth -ErrorAction Stop
        }
        $Found = @(Get-Command -Name $Name -Module $Spec.Module -ErrorAction SilentlyContinue | Where-Object {
                $_.CommandType -in 'Cmdlet', 'Function' -and -not (Test-OPIMTransportTripwireFunction -Command $_)
            })
        if ($Found.Count -ne 1) {
            throw ('Transport tripwire: expected exactly one real command named {0} in {1}, found {2}. Import Omnicit.PIM first.' -f $Name, $Spec.Module, $Found.Count)
        }
        $Command = $Found[0]

        $Dynamic = $null
        $FormHolds = $false
        if ($Spec.Form -eq 'Cmdlet') {
            $FormHolds = ($Command -is [System.Management.Automation.CmdletInfo]) -and
            -not [System.Management.Automation.IDynamicParameters].IsAssignableFrom($Command.ImplementingType)
        } elseif ($Spec.Form -eq 'DynamicCmdlet') {
            if (($Command -is [System.Management.Automation.CmdletInfo]) -and
                [System.Management.Automation.IDynamicParameters].IsAssignableFrom($Command.ImplementingType)) {
                try {
                    $Dynamic = ([System.Management.Automation.IDynamicParameters][Activator]::CreateInstance($Command.ImplementingType)).GetDynamicParameters()
                } catch {
                    $Dynamic = $null
                }
                $FormHolds = $Dynamic -is [System.Management.Automation.RuntimeDefinedParameterDictionary]
            }
        } elseif ($Spec.Form -eq 'ModuleFunction') {
            if ($Command -is [System.Management.Automation.FunctionInfo]) {
                $Ast = $Command.ScriptBlock.Ast
                if ($Ast -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $Ast = $Ast.Body }
                $FormHolds = $null -eq $Ast.DynamicParamBlock
            }
        }
        if (-not $FormHolds) {
            throw ('Transport tripwire: {0} is no longer a {1} (the form measured on 2026-10-06; found a {2}), so its replacement cannot be built that way. Measure again before extending the tripwire.' -f $Name, $Spec.Form, $Command.CommandType)
        }

        $Metadata = [System.Management.Automation.CommandMetadata]::new($Command)
        if ($Spec.Form -eq 'DynamicCmdlet') {
            foreach ($P in $Dynamic.Values) {
                if ($Metadata.Parameters.ContainsKey($P.Name)) { continue }
                $Metadata.Parameters.Add($P.Name, [System.Management.Automation.ParameterMetadata]::new($P.Name, $P.ParameterType))
            }
        }
        $Binding = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Metadata)
        $ParamBlock = [System.Management.Automation.ProxyCommand]::GetParamBlock($Metadata)

        $Text = @"
$Binding
param($ParamBlock)
end {
    # OPIM-TRANSPORT-TRIPWIRE
    `$Caller = @(Get-PSCallStack)[1]
    if (`$null -ne `$global:OPIMTransportTripwireHits) {
        `$null = `$global:OPIMTransportTripwireHits.Add([pscustomobject]@{
                Command    = '$Name'
                Caller     = if (`$Caller) { ('{0}:{1}' -f `$Caller.ScriptName, `$Caller.ScriptLineNumber) } else { '' }
                Parameters = (@(`$PSBoundParameters.Keys) -join ',')
            })
    }
    throw [System.InvalidOperationException]::new('OPIM transport tripwire: a unit test reached the real $Name. Mock it, or the module function that calls it, with Mock -ModuleName Omnicit.PIM.')
}
"@

        $ParallelText = $null
        if ($Spec.Module -eq 'Microsoft.Graph.Authentication') {
            $ParallelText = @"
$Binding
param($ParamBlock)
end {
    # OPIM-TRANSPORT-TRIPWIRE
    `$Caller = @(Get-PSCallStack)[1]
    `$Record = [pscustomobject]@{
        Command    = '$Name'
        Caller     = if (`$Caller) { ('{0}:{1}' -f `$Caller.ScriptName, `$Caller.ScriptLineNumber) } else { '-Parallel runspace' }
        Parameters = (@(`$PSBoundParameters.Keys) -join ',')
    }
    `$StandIn = [System.AppDomain]::CurrentDomain.GetData('OPIMTransportTripwire.StandIn')
    if (`$null -ne `$StandIn -and `$StandIn.ContainsKey('$Name')) {
        `$Calls = [System.AppDomain]::CurrentDomain.GetData('OPIMTransportTripwire.StandInCalls')
        if (`$null -ne `$Calls) { `$Calls.Enqueue(`$Record) }
        return `$StandIn['$Name']
    }
    `$Hits = [System.AppDomain]::CurrentDomain.GetData('OPIMTransportTripwire.ParallelHits')
    if (`$null -ne `$Hits) { `$Hits.Enqueue(`$Record) }
    throw [System.InvalidOperationException]::new('OPIM transport tripwire: a -Parallel runspace reached the real $Name. Register a stand-in with Register-OPIMParallelTransportStandIn.')
}
"@
        }

        $Definitions[$Name] = [pscustomobject]@{
            Name         = $Name
            Module       = $Spec.Module
            Form         = $Spec.Form
            Text         = $Text
            ParallelText = $ParallelText
        }
    }
    $Definitions
}

function Get-OPIMTransportTripwireResolutionProblem {
    <#
    .SYNOPSIS
    Returns one problem per transport name that does not resolve to its replacement from the module
    scope, where module code resolves it. Private to this helper.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $Module = Get-Module -Name Omnicit.PIM | Select-Object -First 1
    if (-not $Module) {
        'Omnicit.PIM is not imported, so the module scope cannot be checked'
        return
    }
    foreach ($Name in @((Get-OPIMTransportTripwireName).Keys)) {
        $Resolved = & $Module { param($N) Get-Command -Name $N -CommandType Function -ErrorAction Ignore } $Name
        if (-not (Test-OPIMTransportTripwireFunction -Command $Resolved)) {
            '{0} no longer resolves to the tripwire from the module scope' -f $Name
        }
    }
}

function Remove-OPIMTransportTripwireRunspaceForm {
    <#
    .SYNOPSIS
    Removes the -Parallel runspace form: its PSModulePath entries, its temp directories, a stand-in
    module loaded in this runspace, and the AppDomain data. Private to this helper.
    #>
    [CmdletBinding()]
    param()
    $Prefix = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'OPIMTransportTripwire-'
    $Kept = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in @($env:PSModulePath -split [System.IO.Path]::PathSeparator)) {
        if ([string]::IsNullOrEmpty($Entry)) { continue }
        if ($Entry.StartsWith($Prefix, [System.StringComparison]::Ordinal)) {
            if ([System.IO.Directory]::Exists($Entry)) {
                [System.IO.Directory]::Delete($Entry, $true)
            }
            continue
        }
        $Kept.Add($Entry)
    }
    $env:PSModulePath = $Kept -join [System.IO.Path]::PathSeparator
    # Measured: a by-name Import-Module Microsoft.Graph.Authentication in THIS runspace loads the
    # stand-in beside the real module while the root is first on PSModulePath.
    Get-Module -Name Microsoft.Graph.Authentication |
        Where-Object { $_.ModuleBase -like (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'OPIMTransportTripwire-*') } |
        Remove-Module -Force
    foreach ($Key in 'OPIMTransportTripwire.ParallelHits', 'OPIMTransportTripwire.StandIn', 'OPIMTransportTripwire.StandInCalls') {
        [System.AppDomain]::CurrentDomain.SetData($Key, $null)
    }
}

function Install-OPIMTransportTripwire {
    <#
    .SYNOPSIS
    Installs every replacement and the -Parallel runspace form, and starts empty hit lists. Call it
    after Import-Module.
    #>
    [CmdletBinding()]
    param()
    $Module = Get-Module -Name Omnicit.PIM | Select-Object -First 1
    if (-not $Module) {
        throw 'Transport tripwire: import Omnicit.PIM before Install-OPIMTransportTripwire.'
    }
    Remove-OPIMTransportTripwireRunspaceForm

    $Definitions = New-OPIMTransportTripwireDefinition
    $global:OPIMTransportTripwireHits = [System.Collections.Generic.List[object]]::new()
    $global:OPIMTransportTripwireDefinitions = $Definitions
    foreach ($Definition in $Definitions.Values) {
        if ($Definition.Form -eq 'ModuleFunction') {
            & $Module { param($N, $T) Set-Item -Path ('function:script:' + $N) -Value ([scriptblock]::Create($T)) } $Definition.Name $Definition.Text
        } else {
            Set-Item -Path ('function:global:' + $Definition.Name) -Value ([scriptblock]::Create($Definition.Text))
        }
    }

    # The -Parallel runspace form: a stand-in Microsoft.Graph.Authentication first on PSModulePath.
    $Root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('OPIMTransportTripwire-' + [guid]::NewGuid().ToString('N'))
    $ModuleDirectory = Join-Path -Path $Root -ChildPath 'Microsoft.Graph.Authentication'
    $null = [System.IO.Directory]::CreateDirectory($ModuleDirectory)
    $Builder = [System.Text.StringBuilder]::new()
    $StandInNames = [System.Collections.Generic.List[string]]::new()
    foreach ($Definition in $Definitions.Values) {
        if ($null -eq $Definition.ParallelText) { continue }
        $null = $Builder.Append(('function {0} {{' -f $Definition.Name)).Append("`n").Append($Definition.ParallelText).Append("`n}`n`n")
        $StandInNames.Add($Definition.Name)
    }
    $null = $Builder.Append('Export-ModuleMember -Function ').Append(($StandInNames -join ', ')).Append("`n")
    $Path = Join-Path -Path $ModuleDirectory -ChildPath 'Microsoft.Graph.Authentication.psm1'
    [System.IO.File]::WriteAllText($Path, $Builder.ToString(), [System.Text.UTF8Encoding]::new($false))
    $env:PSModulePath = $Root + [System.IO.Path]::PathSeparator + $env:PSModulePath
    $global:OPIMTransportTripwireRunspaceRoot = $Root
    [System.AppDomain]::CurrentDomain.SetData('OPIMTransportTripwire.ParallelHits', [System.Collections.Concurrent.ConcurrentQueue[object]]::new())
    [System.AppDomain]::CurrentDomain.SetData('OPIMTransportTripwire.StandIn', [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new())
    [System.AppDomain]::CurrentDomain.SetData('OPIMTransportTripwire.StandInCalls', [System.Collections.Concurrent.ConcurrentQueue[object]]::new())

    $Problems = @(Get-OPIMTransportTripwireResolutionProblem)
    if ($Problems.Count -gt 0) {
        throw ('Transport tripwire: installation did not take: {0}' -f ($Problems -join '; '))
    }
}

function Assert-OPIMTransportTripwire {
    <#
    .SYNOPSIS
    Throws when a unit test reached the transport, in this runspace or in a -Parallel one, or when a
    replacement or the runspace form is no longer in place.
    #>
    [CmdletBinding()]
    param()
    $Problems = [System.Collections.Generic.List[string]]::new()
    foreach ($Hit in @($global:OPIMTransportTripwireHits)) {
        if ($null -eq $Hit) { continue }
        $Problems.Add(('reached {0} from {1} (parameters: {2})' -f $Hit.Command, $Hit.Caller, $Hit.Parameters))
    }
    $ParallelHits = [System.AppDomain]::CurrentDomain.GetData('OPIMTransportTripwire.ParallelHits')
    if ($null -ne $ParallelHits) {
        foreach ($Hit in @($ParallelHits.ToArray())) {
            $Problems.Add(('reached {0} in a -Parallel runspace from {1} (parameters: {2})' -f $Hit.Command, $Hit.Caller, $Hit.Parameters))
        }
    }
    foreach ($Problem in @(Get-OPIMTransportTripwireResolutionProblem)) {
        $Problems.Add($Problem)
    }
    $Root = $global:OPIMTransportTripwireRunspaceRoot
    $First = @($env:PSModulePath -split [System.IO.Path]::PathSeparator)[0]
    $Psm1 = if ($Root) {
        Join-Path -Path (Join-Path -Path $Root -ChildPath 'Microsoft.Graph.Authentication') -ChildPath 'Microsoft.Graph.Authentication.psm1'
    } else {
        $null
    }
    if ([string]::IsNullOrEmpty($Root) -or -not [System.IO.File]::Exists($Psm1) -or -not [string]::Equals($First, $Root, [System.StringComparison]::Ordinal)) {
        $Problems.Add('the -Parallel runspace form is no longer first on PSModulePath')
    }
    if ($Problems.Count -gt 0) {
        throw ('OPIM transport tripwire: {0}' -f ($Problems -join '; '))
    }
}

function Uninstall-OPIMTransportTripwire {
    <#
    .SYNOPSIS
    Removes every replacement and the runspace form, and clears the globals.
    #>
    [CmdletBinding()]
    param()
    # Remove-Item honours no scope qualifier on the function: drive: 'function:global:X' removes
    # nothing and raises no error, with or without -Force (measured in Omnicit.EntraRBAC 2026-10-05,
    # PowerShell 7.6). An unqualified path removes the NEAREST definition up the scope chain, which
    # from here is the global replacement and from inside the module the module-scope one -- so a
    # name is removed only while its nearest definition IS a replacement. That guard is what stops
    # the module-scope removal from deleting the REAL Az.Resources function, which is the nearest
    # definition there once the replacement is gone. The check below then reads from here AND from
    # the module's scope, so a replacement left behind is reported, not silently kept.
    $Names = @((Get-OPIMTransportTripwireName).Keys)
    $Module = Get-Module -Name Omnicit.PIM | Select-Object -First 1
    foreach ($Name in $Names) {
        if (Test-OPIMTransportTripwireFunction -Command (Get-Command -Name $Name -CommandType Function -ErrorAction Ignore)) {
            Remove-Item -Path ('function:' + $Name) -ErrorAction SilentlyContinue
        }
        if ($Module) {
            & $Module {
                param($N)
                $F = Get-Command -Name $N -CommandType Function -ErrorAction Ignore
                if (($F -is [System.Management.Automation.FunctionInfo]) -and $F.ScriptBlock.ToString().Contains('OPIM-TRANSPORT-TRIPWIRE')) {
                    Remove-Item -Path ('function:' + $N) -ErrorAction SilentlyContinue
                }
            } $Name
        }
    }
    Remove-OPIMTransportTripwireRunspaceForm
    $global:OPIMTransportTripwireHits = $null
    $global:OPIMTransportTripwireDefinitions = $null
    $global:OPIMTransportTripwireRunspaceRoot = $null

    $Left = [System.Collections.Generic.List[string]]::new()
    foreach ($Name in $Names) {
        $Here = Test-OPIMTransportTripwireFunction -Command (Get-Command -Name $Name -CommandType Function -ErrorAction Ignore)
        $InModule = $Module -and (Test-OPIMTransportTripwireFunction -Command (& $Module { param($N) Get-Command -Name $N -CommandType Function -ErrorAction Ignore } $Name))
        if ($Here -or $InModule) { $Left.Add($Name) }
    }
    $Prefix = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'OPIMTransportTripwire-'
    foreach ($Entry in @($env:PSModulePath -split [System.IO.Path]::PathSeparator)) {
        if (-not [string]::IsNullOrEmpty($Entry) -and $Entry.StartsWith($Prefix, [System.StringComparison]::Ordinal)) {
            $Left.Add(('PSModulePath entry {0}' -f $Entry))
        }
    }
    if ($Left.Count -gt 0) {
        throw ('OPIM transport tripwire: still defined after uninstall: {0}' -f ($Left -join ', '))
    }
}

function Register-OPIMParallelTransportStandIn {
    <#
    .SYNOPSIS
    Makes the -Parallel runspace stand-in for one Graph command return Response, and record the call
    as a stand-in call instead of a hit. This is the mock for a -Parallel runspace.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Invoke-MgGraphRequest', 'Connect-MgGraph', 'Disconnect-MgGraph', 'Get-MgContext')]
        [string]$Name,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Response
    )
    $StandIn = [System.AppDomain]::CurrentDomain.GetData('OPIMTransportTripwire.StandIn')
    if ($null -eq $StandIn) {
        throw 'OPIM transport tripwire: Install-OPIMTransportTripwire first.'
    }
    $StandIn[$Name] = $Response
}

function Get-OPIMParallelTransportStandInCall {
    <#
    .SYNOPSIS
    Returns the calls the -Parallel runspace stand-ins served, as records of Command, Caller and
    Parameters (parameter names only).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    $Calls = [System.AppDomain]::CurrentDomain.GetData('OPIMTransportTripwire.StandInCalls')
    if ($null -eq $Calls) {
        throw 'OPIM transport tripwire: Install-OPIMTransportTripwire first.'
    }
    @($Calls.ToArray())
}

function Unregister-OPIMParallelTransportStandIn {
    <#
    .SYNOPSIS
    Removes every registered stand-in response and drains the stand-in call records.
    #>
    [CmdletBinding()]
    param()
    $StandIn = [System.AppDomain]::CurrentDomain.GetData('OPIMTransportTripwire.StandIn')
    $Calls = [System.AppDomain]::CurrentDomain.GetData('OPIMTransportTripwire.StandInCalls')
    if ($null -eq $StandIn -or $null -eq $Calls) {
        throw 'OPIM transport tripwire: Install-OPIMTransportTripwire first.'
    }
    $StandIn.Clear()
    $Calls.Clear()
}
