Describe 'Get-MyId' {
    BeforeAll {
        Import-Module Omnicit.PIM -Force
    }
    AfterAll {
        Remove-Module Omnicit.PIM -ErrorAction SilentlyContinue
    }

    Context 'When not connected to Microsoft Graph' {
        It 'throws an informative error' {
            InModuleScope Omnicit.PIM {
                $SCRIPT:_MyIDCache = $null
                Mock Get-MgContext { return $null }
                { Get-MyId } | Should -Throw '*not connected to Microsoft Graph*'
            }
        }
    }

    Context 'When connected and the user id is not yet cached (cache miss)' {
        It 'calls Invoke-MgGraphRequest against v1.0/me' {
            InModuleScope Omnicit.PIM {
                $SCRIPT:_MyIDCache = $null
                Mock Get-MgContext { [PSCustomObject]@{ Account = 'jane@contoso.com' } }
                Mock Invoke-MgGraphRequest {
                    @{ userPrincipalName = 'jane@contoso.com'; id = '00000000-0000-0000-0000-000000000001' }
                } -ParameterFilter { $Uri -eq 'v1.0/me' }

                Get-MyId
                Should -Invoke Invoke-MgGraphRequest -Times 1 -Scope It
            }
        }

        It 'returns a Guid matching the API response' {
            InModuleScope Omnicit.PIM {
                $SCRIPT:_MyIDCache = $null
                Mock Get-MgContext { [PSCustomObject]@{ Account = 'jane@contoso.com' } }
                Mock Invoke-MgGraphRequest {
                    @{ userPrincipalName = 'jane@contoso.com'; id = '00000000-0000-0000-0000-000000000001' }
                } -ParameterFilter { $Uri -eq 'v1.0/me' }

                $result = Get-MyId
                $result | Should -BeOfType [Guid]
                $result.ToString() | Should -Be '00000000-0000-0000-0000-000000000001'
            }
        }
    }

    Context 'When the user id is already in the cache (cache hit)' {
        It 'returns the cached Guid without calling Invoke-MgGraphRequest' {
            InModuleScope Omnicit.PIM {
                $SCRIPT:_MyIDCache = [System.Collections.Generic.Dictionary[String, Guid]]::new()
                $SCRIPT:_MyIDCache.Add('jane@contoso.com', [Guid]'00000000-0000-0000-0000-000000000002')
                Mock Get-MgContext { [PSCustomObject]@{ Account = 'jane@contoso.com' } }
                Mock Invoke-MgGraphRequest { }

                $result = Get-MyId
                $result.ToString() | Should -Be '00000000-0000-0000-0000-000000000002'
                Should -Invoke Invoke-MgGraphRequest -Times 0 -Scope It
            }
        }
    }

    Context 'When an explicit user is provided that is already cached' {
        It 'skips Get-MgContext and returns the cached Guid' {
            InModuleScope Omnicit.PIM {
                $SCRIPT:_MyIDCache = [System.Collections.Generic.Dictionary[String, Guid]]::new()
                $SCRIPT:_MyIDCache.Add('explicit@contoso.com', [Guid]'00000000-0000-0000-0000-000000000003')
                Mock Get-MgContext { }
                Mock Invoke-MgGraphRequest { }

                $result = Get-MyId -user 'explicit@contoso.com'
                $result.ToString() | Should -Be '00000000-0000-0000-0000-000000000003'
                Should -Invoke Get-MgContext -Times 0 -Scope It
                Should -Invoke Invoke-MgGraphRequest -Times 0 -Scope It
            }
        }
    }

    Context 'When the API response UPN does not match the Graph context account' {
        It 'throws with a descriptive message' {
            InModuleScope Omnicit.PIM {
                $SCRIPT:_MyIDCache = $null
                Mock Get-MgContext { [PSCustomObject]@{ Account = 'jane@contoso.com' } }
                Mock Invoke-MgGraphRequest {
                    @{ userPrincipalName = 'imposter@contoso.com'; id = '00000000-0000-0000-0000-000000000004' }
                } -ParameterFilter { $Uri -eq 'v1.0/me' }

                { Get-MyId } | Should -Throw '*userPrincipalName in the response does not match*'
            }
        }
    }
}
