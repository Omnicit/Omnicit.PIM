Describe 'Initialize-OPIMAuth' {
    BeforeAll {
        Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When auth state is already cached for the same tenant with a valid token' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = $null
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $true
                }
                Mock Get-OPIMMsalApplication {}
                Mock Connect-MgGraph {}
                Mock Connect-AzAccount {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'returns without acquiring a new token (idempotent)' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com'
                Should -Invoke Get-OPIMMsalApplication -Times 0 -Scope It
            }
        }

        It 'does not call Connect-MgGraph' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com'
                Should -Invoke Connect-MgGraph -Times 0 -Scope It
            }
        }
    }

    Context 'When auth state is expired' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $FakeAccount = [PSCustomObject]@{ Username = 'user@contoso.com' }
                $FakeResult  = [PSCustomObject]@{
                    AccessToken = 'fake-graph-token'
                    ExpiresOn   = [DateTimeOffset]::UtcNow.AddHours(1)
                    Account     = $FakeAccount
                }
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = $FakeAccount
                    GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(-1)  # expired
                    ClaimsSatisfied  = $true
                }

                # Build a fake MSAL app that returns fake tokens via reflection-like mocks
                $FakeSilentBuilder = [PSCustomObject]@{}
                Add-Member -InputObject $FakeSilentBuilder -MemberType ScriptMethod -Name 'WithAccount'      -Value { return $this }
                Add-Member -InputObject $FakeSilentBuilder -MemberType ScriptMethod -Name 'WithForceRefresh' -Value { return $this }
                Add-Member -InputObject $FakeSilentBuilder -MemberType ScriptMethod -Name 'ExecuteAsync'     -Value { return $using:FakeResult }

                $FakeMsalApp = [PSCustomObject]@{}
                Add-Member -InputObject $FakeMsalApp -MemberType ScriptMethod -Name 'AcquireTokenSilent' -Value {
                    param($Scopes, $Account)
                    return $using:FakeSilentBuilder
                }

                Mock Get-OPIMMsalApplication { return $FakeMsalApp }
                Mock Connect-MgGraph {}
                Mock Connect-AzAccount {}
                Mock ConvertTo-SecureString { return [System.Security.SecureString]::new() }
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'calls Get-OPIMMsalApplication to get a fresh token' {
            InModuleScope Omnicit.PIM {
                # AcquireTokenSilent will throw in unit test context (PSCustomObject GetMethods()
                # won't find MSAL methods); the function falls through to interactive which also
                # throws. We only verify that the MSAL app entry point was reached.
                try { Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' } catch {}
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Scope It
            }
        }
    }

    Context 'When no auth state exists (first use)' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = $null
                $FakeMsalApp = [PSCustomObject]@{}
                Add-Member -InputObject $FakeMsalApp -MemberType ScriptMethod -Name 'AcquireTokenSilent' -Value {
                    param($Scopes, $Account)
                    throw [System.Exception]::new('MsalUiRequiredException: UI required')
                }
                Mock Get-OPIMMsalApplication { return $FakeMsalApp }
                Mock Connect-MgGraph {}
                Mock Connect-AzAccount {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'calls Get-OPIMMsalApplication' {
            InModuleScope Omnicit.PIM {
                try { Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' } catch {}
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Scope It
            }
        }

        It 'uses organizations as default tenant when no TenantId given' {
            InModuleScope Omnicit.PIM {
                try { Initialize-OPIMAuth } catch {}
                Should -Invoke Get-OPIMMsalApplication -Times 1 -Scope It -ParameterFilter {
                    $TenantId -eq 'organizations'
                }
            }
        }
    }

    Context 'When -IncludeARM and Graph token is cached but Azure is not connected' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $false
                }
                Mock Get-AzContext { return $null }
                Mock Connect-AzAccount {}
                Mock Get-OPIMMsalApplication {}
                Mock Connect-MgGraph {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'calls Connect-AzAccount to establish Azure connection' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM
                Should -Invoke Connect-AzAccount -Times 1 -Scope It
            }
        }

        It 'does not call Get-OPIMMsalApplication when Graph token is still valid' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM
                Should -Invoke Get-OPIMMsalApplication -Times 0 -Scope It
            }
        }

        It 'passes -Tenant to Connect-AzAccount when tenant is not organizations' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM
                Should -Invoke Connect-AzAccount -Times 1 -Scope It -ParameterFilter {
                    $Tenant -eq 'contoso.onmicrosoft.com'
                }
            }
        }

        It 'does not pass -Tenant to Connect-AzAccount when tenant is organizations' {
            InModuleScope Omnicit.PIM {
                # Temporarily update state to match 'organizations' tenant
                $script:_OPIMAuthState.TenantId = 'organizations'
                Initialize-OPIMAuth -IncludeARM
                $script:_OPIMAuthState.TenantId = 'contoso.onmicrosoft.com'
                Should -Invoke Connect-AzAccount -Times 1 -Scope It -ParameterFilter {
                    -not $Tenant
                }
            }
        }
    }

    Context 'When -IncludeARM and both Graph token and Azure context are already valid' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $FakeAzCtx = [PSCustomObject]@{
                    Tenant  = [PSCustomObject]@{ Id  = 'contoso.onmicrosoft.com' }
                    Account = [PSCustomObject]@{ Id  = 'user@contoso.com' }
                }
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $false
                }
                # Return value inlined — $FakeAzCtx is a local variable in the BeforeAll
                # scriptblock and is not accessible inside a mock body (late-binding scope).
                Mock Get-AzContext {
                    return [PSCustomObject]@{
                        Tenant  = [PSCustomObject]@{ Id  = 'contoso.onmicrosoft.com' }
                        Account = [PSCustomObject]@{ Id  = 'user@contoso.com' }
                    }
                }
                Mock Connect-AzAccount {}
                Mock Get-OPIMMsalApplication {}
                Mock Connect-MgGraph {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'returns early without calling Connect-AzAccount (fully idempotent)' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM
                Should -Invoke Connect-AzAccount -Times 0 -Scope It
            }
        }

        It 'does not call Get-OPIMMsalApplication when both Graph and Azure are cached' {
            InModuleScope Omnicit.PIM {
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM
                Should -Invoke Get-OPIMMsalApplication -Times 0 -Scope It
            }
        }
    }

    Context 'When -IncludeARM and Azure connection fails' {
        BeforeAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    Account          = [PSCustomObject]@{ Username = 'user@contoso.com' }
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ClaimsSatisfied  = $false
                }
                Mock Get-AzContext { return $null }
                Mock Connect-AzAccount { throw [System.Exception]::new('Azure auth failure') }
                Mock Get-OPIMMsalApplication {}
                Mock Connect-MgGraph {}
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM { $script:_OPIMAuthState = $null }
        }

        It 'writes a non-terminating error and does not throw' {
            InModuleScope Omnicit.PIM {
                $Errors = @()
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM `
                    -ErrorVariable Errors -ErrorAction SilentlyContinue
                $Errors.Count | Should -BeGreaterThan 0
            }
        }

        It 'includes AzureConnectFailed in the error id' {
            InModuleScope Omnicit.PIM {
                $Errors = @()
                Initialize-OPIMAuth -TenantId 'contoso.onmicrosoft.com' -IncludeARM `
                    -ErrorVariable Errors -ErrorAction SilentlyContinue
                # $Errors may contain an auto-created record from the raw throw in the mock
                # (added by PowerShell's error machinery before the catch block runs) plus
                # the WriteError record with 'AzureConnectFailed'. Search all collected errors.
                ($Errors | Where-Object { $_.FullyQualifiedErrorId -match 'AzureConnectFailed' }) |
                    Should -Not -BeNullOrEmpty
            }
        }
    }
}
