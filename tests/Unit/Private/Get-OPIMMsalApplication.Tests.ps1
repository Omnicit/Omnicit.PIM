BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Get-OPIMMsalApplication' {
    Context 'When a cached app exists for the same tenant' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $FakeApp = [PSCustomObject]@{ _FakeId = 'app-001' }
                $script:_OPIMMsalApp = $FakeApp
                $script:_OPIMMsalAppTenantId = 'contoso.onmicrosoft.com'
                # Every Get-MgContext mock in this file throws (R3, held by tests/QA/testhygiene.tests.ps1):
                # past Get-MgContext, Get-OPIMMsalApplication builds a real MSAL application.
                Mock Get-MgContext { throw [System.InvalidOperationException]::new('OPIM test stop: Get-OPIMMsalApplication reached its build path') }
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMMsalApp = $null
                $script:_OPIMMsalAppTenantId = $null
            }
        }

        It 'returns the cached app without rebuilding' {
            InModuleScope Omnicit.PIM {
                $Result = Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com'
                [object]::ReferenceEquals($Result, $script:_OPIMMsalApp) | Should -Be $true
            }
        }

        It 'does not call Get-MgContext when cache is valid' {
            InModuleScope Omnicit.PIM {
                Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com'
                Should -Invoke Get-MgContext -Times 0 -Scope It
            }
        }
    }

    Context 'When a cached app exists but for a different tenant' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $FakeApp = [PSCustomObject]@{ _FakeId = 'app-fabrikam' }
                $script:_OPIMMsalApp = $FakeApp
                $script:_OPIMMsalAppTenantId = 'fabrikam.onmicrosoft.com'
                Mock Get-MgContext { throw [System.InvalidOperationException]::new('OPIM test stop: Get-OPIMMsalApplication reached its build path') }
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMMsalApp = $null
                $script:_OPIMMsalAppTenantId = $null
            }
        }

        It 'attempts to rebuild the app (calls Get-MgContext to load assemblies)' {
            InModuleScope Omnicit.PIM {
                # The sentinel proves the cache-hit path was NOT taken and that the call stopped
                # at Get-MgContext, before the MSAL build; the cache is left exactly as it was.
                $Before = $script:_OPIMMsalApp
                $Message = try { Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com'; 'RETURNED' } catch { $_.Exception.Message }
                $Message | Should -BeExactly 'OPIM test stop: Get-OPIMMsalApplication reached its build path'
                Should -Invoke Get-MgContext -Times 1 -Exactly -Scope It
                [object]::ReferenceEquals($script:_OPIMMsalApp, $Before) | Should -BeTrue
                $script:_OPIMMsalApp._FakeId | Should -Be 'app-fabrikam'
                $script:_OPIMMsalAppTenantId | Should -Be 'fabrikam.onmicrosoft.com'
            }
        }
    }

    Context 'When no cache exists' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMMsalApp = $null
                $script:_OPIMMsalAppTenantId = $null
                Mock Get-MgContext { throw [System.InvalidOperationException]::new('OPIM test stop: Get-OPIMMsalApplication reached its build path') }
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMMsalApp = $null
                $script:_OPIMMsalAppTenantId = $null
            }
        }

        It 'calls Get-MgContext to force-load the MSAL assembly' {
            InModuleScope Omnicit.PIM {
                $Message = try { Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com'; 'RETURNED' } catch { $_.Exception.Message }
                $Message | Should -BeExactly 'OPIM test stop: Get-OPIMMsalApplication reached its build path'
                Should -Invoke Get-MgContext -Times 1 -Exactly -Scope It
                $null -eq $script:_OPIMMsalApp | Should -BeTrue -Because 'the call stopped before the MSAL build, so nothing was cached'
                $null -eq $script:_OPIMMsalAppTenantId | Should -BeTrue
            }
        }
    }

    Context 'When the cached app was built for a cloud (OPIM-29)' {
        # A11. The cache is keyed on the tenant AND the cloud: an app built for one cloud holds the token
        # cache of that cloud's authority, so it is never handed to a request for another cloud. A
        # cache written before the cloud was recorded ($null) is Global, the only cloud there was.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Get-MgContext { throw [System.InvalidOperationException]::new('OPIM test stop: Get-OPIMMsalApplication reached its build path') }
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM {
                $script:_OPIMMsalApp = [PSCustomObject]@{ _FakeId = 'app-usgov' }
                $script:_OPIMMsalAppTenantId = 'contoso.onmicrosoft.com'
                $script:_OPIMMsalAppEnvironment = 'USGov'
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMMsalApp = $null
                $script:_OPIMMsalAppTenantId = $null
                $script:_OPIMMsalAppEnvironment = $null
            }
        }

        It 'returns the cached app only for the same tenant and the same cloud' {
            InModuleScope Omnicit.PIM {
                $Before = $script:_OPIMMsalApp
                $Same = Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com' -Environment USGov
                [object]::ReferenceEquals($Same, $Before) | Should -BeTrue
                Should -Invoke Get-MgContext -Times 0 -Scope It

                # The same tenant in another cloud is another application: the call reaches the build path.
                $Message = try { Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com' -Environment Global; 'RETURNED' } catch { $_.Exception.Message }
                $Message | Should -BeExactly 'OPIM test stop: Get-OPIMMsalApplication reached its build path'
                Should -Invoke Get-MgContext -Times 1 -Exactly -Scope It
                # The stop came before the build, so the cache is exactly what it was.
                [object]::ReferenceEquals($script:_OPIMMsalApp, $Before) | Should -BeTrue
                $script:_OPIMMsalAppEnvironment | Should -BeExactly 'USGov'
            }
        }

        It 'rebuilds for another tenant in the same cloud' {
            InModuleScope Omnicit.PIM {
                $Message = try { Get-OPIMMsalApplication -TenantId 'fabrikam.onmicrosoft.com' -Environment USGov; 'RETURNED' } catch { $_.Exception.Message }
                $Message | Should -BeExactly 'OPIM test stop: Get-OPIMMsalApplication reached its build path'
                Should -Invoke Get-MgContext -Times 1 -Exactly -Scope It
            }
        }

        It 'reads the cloud name in any letter case' {
            InModuleScope Omnicit.PIM {
                $Before = $script:_OPIMMsalApp
                $Same = Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com' -Environment usgov
                [object]::ReferenceEquals($Same, $Before) | Should -BeTrue
                Should -Invoke Get-MgContext -Times 0 -Scope It
            }
        }

        It 'returns the cached app for a cache written before the cloud was recorded, in the Global cloud' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMMsalAppEnvironment = $null
                $Before = $script:_OPIMMsalApp
                $Named = Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com' -Environment Global
                [object]::ReferenceEquals($Named, $Before) | Should -BeTrue
                $Default = Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com'
                [object]::ReferenceEquals($Default, $Before) | Should -BeTrue
                Should -Invoke Get-MgContext -Times 0 -Scope It
            }
        }

        It 'does not return a cache written before the cloud was recorded for a sovereign cloud' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMMsalAppEnvironment = $null
                $Message = try { Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com' -Environment China; 'RETURNED' } catch { $_.Exception.Message }
                $Message | Should -BeExactly 'OPIM test stop: Get-OPIMMsalApplication reached its build path'
                Should -Invoke Get-MgContext -Times 1 -Exactly -Scope It
            }
        }

        It 'refuses an unknown cloud before it reads the cache or Get-MgContext' {
            InModuleScope Omnicit.PIM {
                $Message = try { Get-OPIMMsalApplication -TenantId 'contoso.onmicrosoft.com' -Environment Germany; 'RETURNED' } catch { $_.Exception.Message }
                $Message | Should -Match "no endpoint table entry for the cloud 'Germany'"
                $Message | Should -Not -BeExactly 'RETURNED'
                Should -Invoke Get-MgContext -Times 0 -Scope It
            }
        }
    }

    Context 'Its source' {
        # The authority and the cloud of the cache sit past the Get-MgContext call, on the build path that
        # reflects into a real MSAL client, which no unit test may reach (CLAUDE.md, Testing Conventions).
        # They are therefore held by their shape in the AST.
        BeforeAll {
            $Ast = InModuleScope Omnicit.PIM { (Get-Command Get-OPIMMsalApplication).ScriptBlock.Ast }
            $Assignments = @($Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))
        }

        It 'builds the authority from the table''s AuthorityHost, never from a literal' {
            $Authority = @($Assignments | Where-Object { $_.Left.Extent.Text -match '^(\[string\])?\$Authority$' })
            $Authority.Count | Should -Be 1 -Because 'the walk must find the one assignment to $Authority; a walk that finds none would pass vacuously'
            $Members = @($Authority[0].Right.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.MemberExpressionAst] -and $Node.Extent.Text -eq '$Endpoint.AuthorityHost'
                    }, $true))
            $Members.Count | Should -Be 1 -Because 'the authority host comes from the cloud table'
            $Strings = @($Ast.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                        $Node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
                    }, $true))
            $Strings.Count | Should -BeGreaterThan 0 -Because 'the walk must reach the function''s strings'
            @($Strings | Where-Object { $_.Extent.Text -match 'login\.|microsoftonline|chinacloudapi' }) | Should -BeNullOrEmpty
        }

        It 'resolves the cloud through the table before it reads the cache' {
            $EndpointCall = @($Assignments | Where-Object {
                    $_.Left.Extent.Text -eq '$Endpoint' -and $_.Right.Extent.Text -match '^Get-OPIMCloudEndpoint\s+-Environment\s+\$Environment$'
                })
            $EndpointCall.Count | Should -Be 1
            $CacheCheck = @($Ast.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.IfStatementAst] -and
                        $Node.Clauses[0].Item1.Extent.Text -match '_OPIMMsalAppTenantId'
                    }, $true))
            $CacheCheck.Count | Should -Be 1
            $CacheCheck[0].Clauses[0].Item1.Extent.Text | Should -Match '_OPIMMsalAppTenantId -eq \$TenantId'
            $CacheCheck[0].Clauses[0].Item1.Extent.Text | Should -Match '\$CachedEnvironment -eq \$Endpoint\.Environment'
            $EndpointCall[0].Extent.StartOffset | Should -BeLessThan $CacheCheck[0].Extent.StartOffset
        }

        It 'records the cloud of the app it built, after the build' {
            $Recorded = @($Assignments | Where-Object { $_.Left.Extent.Text -eq '$script:_OPIMMsalAppEnvironment' })
            $Recorded.Count | Should -Be 1
            $Recorded[0].Right.Extent.Text | Should -Be '$Endpoint.Environment'
            $Built = @($Assignments | Where-Object { $_.Left.Extent.Text -eq '$script:_OPIMMsalApp' })
            $Built.Count | Should -Be 1
            $Recorded[0].Extent.StartOffset | Should -BeGreaterThan $Built[0].Extent.StartOffset -Because 'the cloud is recorded only for an app that was built'
        }
    }
}
