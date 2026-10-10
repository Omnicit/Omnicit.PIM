BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMTenantMapEnvironment' {
    Context 'When the entry names no cloud' {
        It 'returns Global for <Name>' -ForEach @(
            @{ Name = 'an entry in the old string form'; Entry = 'aaaaaaaa-0000-0000-0000-00000000000a' }
            @{ Name = 'a table without the key'; Entry = @{ TenantId = '00000000-0000-0000-0000-000000000001' } }
            @{ Name = 'an ordered table without the key'; Entry = [ordered]@{ TenantId = '00000000-0000-0000-0000-000000000001' } }
            @{ Name = 'an empty Environment'; Entry = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Environment = '' } }
            @{ Name = 'an Environment of white space'; Entry = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Environment = '  ' } }
            @{ Name = 'a null Environment'; Entry = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Environment = $null } }
            @{ Name = 'a null entry'; Entry = $null }
        ) {
            $Cloud = InModuleScope Omnicit.PIM -Parameters @{ Entry = $Entry } {
                param($Entry)
                Get-OPIMTenantMapEnvironment -Entry $Entry -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            }
            $Cloud | Should -BeExactly 'Global'
        }

        It 'does not ask the cloud table for an entry that names no cloud' {
            Mock -ModuleName Omnicit.PIM Get-OPIMCloudEndpoint { throw 'the cloud table must not be asked' }
            $Cloud = InModuleScope Omnicit.PIM {
                Get-OPIMTenantMapEnvironment -Entry @{ TenantId = '00000000-0000-0000-0000-000000000001' } -TenantAlias 'contoso'
            }
            $Cloud | Should -BeExactly 'Global'
            Should -Invoke -ModuleName Omnicit.PIM Get-OPIMCloudEndpoint -Times 0 -Scope It
        }
    }

    Context 'When the entry names a known cloud' {
        # Review focus 1: a cloud written by hand in another letter case is read case-insensitively and
        # answered under its canonical name.
        It 'returns <Canonical> for a stored <Stored>' -ForEach @(
            @{ Stored = 'USGov'; Canonical = 'USGov' }
            @{ Stored = 'usgov'; Canonical = 'USGov' }
            @{ Stored = 'CHINA'; Canonical = 'China' }
            @{ Stored = 'usgovdod'; Canonical = 'USGovDoD' }
            @{ Stored = 'USGOVDOD'; Canonical = 'USGovDoD' }
            @{ Stored = 'Global'; Canonical = 'Global' }
            @{ Stored = 'GLOBAL'; Canonical = 'Global' }
        ) {
            $Cloud = InModuleScope Omnicit.PIM -Parameters @{ Stored = $Stored } {
                param($Stored)
                Get-OPIMTenantMapEnvironment -Entry @{ TenantId = '00000000-0000-0000-0000-000000000001'; Environment = $Stored } -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1'
            }
            $Cloud | Should -BeExactly $Canonical
        }

        It 'reads the cloud of an ordered table' {
            $Cloud = InModuleScope Omnicit.PIM {
                Get-OPIMTenantMapEnvironment -Entry ([ordered]@{ TenantId = '00000000-0000-0000-0000-000000000001'; Environment = 'china' }) -TenantAlias 'contoso'
            }
            $Cloud | Should -BeExactly 'China'
        }

        It 'returns a string, not a table of the cloud' {
            $Cloud = InModuleScope Omnicit.PIM {
                Get-OPIMTenantMapEnvironment -Entry @{ Environment = 'USGov' } -TenantAlias 'contoso'
            }
            $Cloud | Should -BeOfType [string]
        }

        It 'declares a string as its output' {
            $OutputType = InModuleScope Omnicit.PIM { (Get-Command Get-OPIMTenantMapEnvironment).OutputType.Type.FullName }
            $OutputType | Should -BeExactly 'System.String'
        }
    }

    Context 'When the entry names a cloud the module does not know' {
        BeforeAll {
            # Everything the error is made of is read in the module and handed out as plain values, since a
            # module's types are not visible here and the record must be caught where it is thrown.
            $script:Facts = InModuleScope Omnicit.PIM {
                $Result = $null
                $Threw = $false
                $Record = $null
                try {
                    $Result = Get-OPIMTenantMapEnvironment -Entry @{ TenantId = '00000000-0000-0000-0000-000000000001'; Environment = 'Germany' } `
                        -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction Stop
                } catch {
                    $Threw = $true
                    $Record = $PSItem
                }
                [PSCustomObject]@{
                    Threw         = $Threw
                    Result        = $Result
                    Id            = [string]$Record.FullyQualifiedErrorId
                    Category      = [string]$Record.CategoryInfo.Category
                    Target        = $Record.TargetObject
                    ExceptionType = $Record.Exception.GetType().FullName
                    Message       = $Record.Exception.Message
                }
            }
        }

        It 'throws an error with no error id for an unknown cloud' {
            $script:Facts.Threw | Should -BeTrue
            # An id-less record is named after the command that threw it, and carries nothing else.
            $script:Facts.Id | Should -BeExactly 'Get-OPIMTenantMapEnvironment'
        }

        It 'throws a terminating error of the category InvalidArgument with the alias as its target' {
            $script:Facts.Category | Should -BeExactly 'InvalidArgument'
            $script:Facts.Target | Should -BeExactly 'contoso'
            $script:Facts.ExceptionType | Should -BeExactly 'System.ArgumentException'
        }

        It 'names the alias, the path, the value and the four clouds, and says nothing was signed in' {
            $script:Facts.Message | Should -BeExactly ("Tenant alias 'contoso' in 'TestDrive:\TenantMap.psd1' names the cloud 'Germany', which Omnicit.PIM does not know, " +
                'so nothing was signed in. Use Global, USGov, USGovDoD or China, for example with ' +
                'Set-OPIMConfiguration -TenantAlias contoso -Environment USGov.')
        }

        It 'never returns Global for an unknown cloud' {
            $script:Facts.Threw | Should -BeTrue
            $script:Facts.Result | Should -BeNullOrEmpty
        }

        It 'refuses <Stored> as unknown, and never as Global or as a known cloud' -ForEach @(
            @{ Stored = 'GCC' }
            @{ Stored = 'Global ' }
            @{ Stored = ' USGov' }
            @{ Stored = 'US Gov' }
            @{ Stored = 'USGov,China' }
        ) {
            $Outcome = InModuleScope Omnicit.PIM -Parameters @{ Stored = $Stored } {
                param($Stored)
                try {
                    $Value = Get-OPIMTenantMapEnvironment -Entry @{ Environment = $Stored } -TenantAlias 'contoso' -TenantMapPath 'TestDrive:\TenantMap.psd1' -ErrorAction Stop
                    "returned $Value"
                } catch {
                    "threw $($PSItem.Exception.Message)"
                }
            }
            $Outcome | Should -BeLike "threw Tenant alias 'contoso' in 'TestDrive:\TenantMap.psd1' names the cloud '$Stored', which Omnicit.PIM does not know*"
        }

        It 'says the tenant map instead of a path when no path was given' {
            $Message = InModuleScope Omnicit.PIM {
                try {
                    Get-OPIMTenantMapEnvironment -Entry @{ Environment = 'Germany' } -TenantAlias 'contoso' -ErrorAction Stop
                } catch {
                    $PSItem.Exception.Message
                }
            }
            $Message | Should -BeLike "Tenant alias 'contoso' in the tenant map names the cloud 'Germany'*"
        }

        It 'reads as the command that writes it when that command passes it on' {
            # The shape the callers use: catch the terminating record and write it with their own
            # $PSCmdlet.WriteError. Measured: the empty id is then the caller's name.
            $Written = InModuleScope Omnicit.PIM {
                function Test-OPIMCaller {
                    [CmdletBinding()]
                    param()
                    try {
                        Get-OPIMTenantMapEnvironment -Entry @{ Environment = 'Germany' } -TenantAlias 'contoso' -ErrorAction Stop
                    } catch {
                        $PSCmdlet.WriteError($PSItem)
                    }
                }
                $Errs = $null
                Test-OPIMCaller -ErrorVariable Errs -ErrorAction SilentlyContinue
                [string]$Errs[-1].FullyQualifiedErrorId
            }
            $Written | Should -BeExactly 'Test-OPIMCaller'
        }
    }

    Context 'When it runs' {
        It 'reads and writes no module state' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; Environment = 'China' }
                try {
                    $Cloud = Get-OPIMTenantMapEnvironment -Entry @{ Environment = 'USGov' } -TenantAlias 'contoso'
                    $Cloud | Should -BeExactly 'USGov'
                    $script:_OPIMAuthState.Environment | Should -BeExactly 'China'
                    $script:_OPIMAuthState.Count | Should -Be 2
                } finally {
                    $script:_OPIMAuthState = $null
                }
            }
        }
    }
}
