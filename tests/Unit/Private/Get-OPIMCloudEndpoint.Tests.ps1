BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMCloudEndpoint' {
    Context 'When a known cloud is asked for' {
        It 'returns the <Environment> row of the table' -ForEach @(
            @{ Environment = 'Global'; GraphEnvironment = 'Global'; GraphServiceRoot = 'https://graph.microsoft.com/v1.0'; ArmHost = 'https://management.azure.com'; AuthorityHost = 'https://login.microsoftonline.com/' }
            @{ Environment = 'USGov'; GraphEnvironment = 'USGov'; GraphServiceRoot = 'https://graph.microsoft.us/v1.0'; ArmHost = 'https://management.usgovcloudapi.net'; AuthorityHost = 'https://login.microsoftonline.us/' }
            @{ Environment = 'USGovDoD'; GraphEnvironment = 'USGovDoD'; GraphServiceRoot = 'https://dod-graph.microsoft.us/v1.0'; ArmHost = 'https://management.usgovcloudapi.net'; AuthorityHost = 'https://login.microsoftonline.us/' }
            @{ Environment = 'China'; GraphEnvironment = 'China'; GraphServiceRoot = 'https://microsoftgraph.chinacloudapi.cn/v1.0'; ArmHost = 'https://management.chinacloudapi.cn'; AuthorityHost = 'https://login.chinacloudapi.cn/' }
        ) {
            $Row = InModuleScope Omnicit.PIM -Parameters @{ Name = $Environment } { param($Name) Get-OPIMCloudEndpoint -Environment $Name }
            $Row.Environment | Should -BeExactly $Environment
            $Row.GraphEnvironment | Should -BeExactly $GraphEnvironment
            $Row.GraphServiceRoot | Should -BeExactly $GraphServiceRoot
            $Row.ArmHost | Should -BeExactly $ArmHost
            $Row.AuthorityHost | Should -BeExactly $AuthorityHost
            # ArmResource and GraphResource are the hosts with a trailing slash (EntraRBAC's strings).
            $Row.ArmResource | Should -BeExactly ($ArmHost + '/')
            $Row.GraphResource | Should -BeExactly (($GraphServiceRoot -replace '/v1\.0$', '') + '/')
        }

        It 'returns exactly the seven string properties, in order, for <Name>' -ForEach @(
            @{ Name = 'Global' }, @{ Name = 'USGov' }, @{ Name = 'USGovDoD' }, @{ Name = 'China' }
        ) {
            $Row = InModuleScope Omnicit.PIM -Parameters @{ Name = $Name } { param($Name) Get-OPIMCloudEndpoint -Environment $Name }
            $Properties = @($Row.PSObject.Properties)
            $Properties.Count | Should -Be 7
            ($Properties.Name -join ',') | Should -BeExactly 'Environment,GraphResource,GraphEnvironment,GraphServiceRoot,ArmResource,ArmHost,AuthorityHost'
            foreach ($Property in $Properties) {
                $Property.Value | Should -BeOfType [string] -Because "$($Property.Name) is a string"
                $Property.Value | Should -Not -BeNullOrEmpty -Because "$($Property.Name) is filled in"
            }
        }

        It 'returns the Global row without -Environment' {
            $Row = InModuleScope Omnicit.PIM { Get-OPIMCloudEndpoint }
            $Explicit = InModuleScope Omnicit.PIM { Get-OPIMCloudEndpoint -Environment 'Global' }
            $Row.Environment | Should -BeExactly 'Global'
            foreach ($Name in @('Environment', 'GraphResource', 'GraphEnvironment', 'GraphServiceRoot', 'ArmResource', 'ArmHost', 'AuthorityHost')) {
                $Row.$Name | Should -BeExactly $Explicit.$Name
            }
        }

        It 'reads <Typed> in any letter case and returns the canonical name <Canonical>' -ForEach @(
            @{ Typed = 'usgov'; Canonical = 'USGov' }
            @{ Typed = 'CHINA'; Canonical = 'China' }
            @{ Typed = 'usgovdod'; Canonical = 'USGovDoD' }
            @{ Typed = 'GLOBAL'; Canonical = 'Global' }
        ) {
            $Row = InModuleScope Omnicit.PIM -Parameters @{ Name = $Typed } { param($Name) Get-OPIMCloudEndpoint -Environment $Name }
            $CanonicalRow = InModuleScope Omnicit.PIM -Parameters @{ Name = $Canonical } { param($Name) Get-OPIMCloudEndpoint -Environment $Name }
            $Row.Environment | Should -BeExactly $Canonical
            $Row.GraphServiceRoot | Should -BeExactly $CanonicalRow.GraphServiceRoot
            $Row.AuthorityHost | Should -BeExactly $CanonicalRow.AuthorityHost
            $Row.ArmHost | Should -BeExactly $CanonicalRow.ArmHost
        }

        It 'keeps the Global row byte-identical to the literals it replaces' {
            $Row = InModuleScope Omnicit.PIM { Get-OPIMCloudEndpoint -Environment 'Global' }
            # The MSAL authority prefix and the ARM resource the module sent before the table existed.
            ($Row.AuthorityHost + 'contoso.onmicrosoft.com') | Should -BeExactly 'https://login.microsoftonline.com/contoso.onmicrosoft.com'
            $Row.ArmHost | Should -BeExactly 'https://management.azure.com'
            ([uri]$Row.GraphServiceRoot).Host | Should -BeExactly 'graph.microsoft.com'
        }

        It 'reads and writes no module state' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; Environment = 'China' }
                $script:_OPIMMsalApp = $null
                try {
                    $Row = Get-OPIMCloudEndpoint -Environment 'USGov'
                    $Row.Environment | Should -BeExactly 'USGov'
                    $script:_OPIMAuthState.Environment | Should -BeExactly 'China'
                    $script:_OPIMAuthState.TenantId | Should -BeExactly 'contoso.onmicrosoft.com'
                    $script:_OPIMAuthState.Count | Should -Be 2
                    $script:_OPIMMsalApp | Should -BeNullOrEmpty
                } finally {
                    $script:_OPIMAuthState = $null
                }
            }
        }
    }

    Context 'When the cloud is unknown' {
        It 'throws for <Name> instead of returning the Global row' -ForEach @(
            @{ Name = 'Germany' }, @{ Name = 'GCC' }, @{ Name = '' }, @{ Name = 'Global ' }
        ) {
            { InModuleScope Omnicit.PIM -Parameters @{ Name = $Name } { param($Name) Get-OPIMCloudEndpoint -Environment $Name } } |
                Should -Throw -ExpectedMessage "*'$Name'*"
        }

        It 'tells the maintainer to add a row first, for <Name>' -ForEach @(
            @{ Name = 'Germany' }, @{ Name = '' }
        ) {
            { InModuleScope Omnicit.PIM -Parameters @{ Name = $Name } { param($Name) Get-OPIMCloudEndpoint -Environment $Name } } |
                Should -Throw -ExpectedMessage '*Add a row to source/Private/Get-OPIMCloudEndpoint.ps1 before adding the cloud to an -Environment ValidateSet*'
        }
    }

    Context 'When a public command takes -Environment' {
        # Drift guard: every -Environment ValidateSet names exactly the clouds the table answers, so a
        # fifth row, or a fifth name in a ValidateSet, fails here until both are changed together.
        BeforeAll {
            $script:CloudEndpointSourcePath = Join-Path $PSScriptRoot '../../../source/Private/Get-OPIMCloudEndpoint.ps1'
        }

        It 'gives <Command> a ValidateSet of exactly the four clouds of the table' -ForEach @(
            @{ Command = 'Connect-OPIM' }
            @{ Command = 'Enable-OPIMMyRole' }
            @{ Command = 'Disable-OPIMMyRole' }
            @{ Command = 'Install-OPIMConfiguration' }
            @{ Command = 'Set-OPIMConfiguration' }
            @{ Command = 'Initialize-OPIMAuth' }
        ) {
            $Facts = InModuleScope Omnicit.PIM -Parameters @{ Name = $Command } {
                param($Name)
                $Found = Get-Command -Name $Name -CommandType Function -ErrorAction SilentlyContinue
                $HasParameter = [bool]($Found -and $Found.Parameters.ContainsKey('Environment'))
                $Sets = @()
                if ($HasParameter) {
                    $Sets = @($Found.Parameters['Environment'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })
                }
                [string[]]$Values = @()
                if ($Sets.Count -eq 1) { $Values = [string[]]@($Sets[0].ValidValues) }
                [Array]::Sort($Values, [System.StringComparer]::Ordinal)
                # Every value must resolve to a row of the table under its own, canonical name.
                $Resolved = foreach ($Value in $Values) {
                    try { (Get-OPIMCloudEndpoint -Environment $Value).Environment } catch { "<$Value does not resolve>" }
                }
                [PSCustomObject]@{
                    Found        = [bool]$Found
                    HasParameter = $HasParameter
                    SetCount     = $Sets.Count
                    Values       = $Values -join ','
                    Resolved     = @($Resolved) -join ','
                }
            }
            $Facts.Found | Should -BeTrue -Because "$Command is a function of the module"
            $Facts.HasParameter | Should -BeTrue -Because "$Command has no -Environment parameter"
            $Facts.SetCount | Should -Be 1 -Because "$Command carries exactly one ValidateSet on -Environment"
            $Facts.Values | Should -BeExactly 'China,Global,USGov,USGovDoD'
            $Facts.Resolved | Should -BeExactly 'China,Global,USGov,USGovDoD'
        }

        It 'answers exactly the clouds its switch names (read from the source AST)' {
            $Tokens = $null
            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Resolve-Path -LiteralPath $script:CloudEndpointSourcePath).Path, [ref]$Tokens, [ref]$Errors)
            $Errors | Should -BeNullOrEmpty
            $Switches = @($Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.SwitchStatementAst] }, $true))
            $Switches.Count | Should -Be 1 -Because 'the table is one switch'
            $Names = foreach ($Clause in $Switches[0].Clauses) {
                $Condition = $Clause.Item1
                if ($Condition -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    $Condition.Value
                } else {
                    "<not a constant: $($Condition.Extent.Text)>"
                }
            }
            [string[]]$Sorted = @($Names)
            [Array]::Sort($Sorted, [System.StringComparer]::Ordinal)
            ($Sorted -join ',') | Should -BeExactly 'China,Global,USGov,USGovDoD'
        }

        It 'matches the name exactly and ends its switch in a default that throws (read from the source AST)' {
            $Tokens = $null
            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Resolve-Path -LiteralPath $script:CloudEndpointSourcePath).Path, [ref]$Tokens, [ref]$Errors)
            $Errors | Should -BeNullOrEmpty
            $Switches = @($Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.SwitchStatementAst] }, $true))
            $Switches.Count | Should -Be 1
            $Switch = $Switches[0]
            $Switch.Condition.Extent.Text | Should -BeExactly '$Environment'
            # No -Wildcard, -Regex, -File or -CaseSensitive: a plain, case-insensitive, exact match.
            [string]$Switch.Flags | Should -BeExactly 'None'
            $Switch.Default | Should -Not -BeNullOrEmpty -Because 'an unknown cloud needs a default clause'
            $Throws = @($Switch.Default.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.ThrowStatementAst] }, $true))
            $Throws.Count | Should -Be 1 -Because 'the default clause throws and returns nothing'
        }
    }
}
