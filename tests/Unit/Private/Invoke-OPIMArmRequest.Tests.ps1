BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OPIMTestToken.ps1"

    # The session's tenant and account, and another of each. Digit- and letter-repeat placeholders:
    # none is a version-4 id.
    $SessionTenant = '22222222-2222-2222-2222-222222222222'
    $OtherTenant = '33333333-3333-3333-3333-333333333333'
    $SessionAccount = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $OtherAccount = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'

    # The root-scope eligibility listing: '' is the prefix of the scope '/'.
    $ListPath = '/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01'

    # An ARM token as Initialize-OPIMAuth keeps it: a SecureString of a NOT-A-REAL-TOKEN fixture.
    function script:New-ArmTestToken {
        param(
            [string]$TenantId = '22222222-2222-2222-2222-222222222222',
            [string]$ObjectId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        )
        [System.Net.NetworkCredential]::new('', (New-OPIMTestAccessToken -TenantId $TenantId -ObjectId $ObjectId)).SecurePassword
    }

    # The auth state of a module sign-in with an ARM token for the session's tenant and account.
    function script:New-ArmTestState {
        param([AllowNull()]$ArmToken = (New-ArmTestToken))
        @{
            TenantId         = 'contoso.onmicrosoft.com'
            TokenTenantId    = '22222222-2222-2222-2222-222222222222'
            ObjectId         = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            ArmToken         = $ArmToken
            ArmTokenExpiry   = [DateTime]::UtcNow.AddHours(1)
            ArmTokenTenantId = '22222222-2222-2222-2222-222222222222'
            ArmTokenObjectId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            ArmResourceUrl   = 'https://management.azure.com'
        }
    }

    function script:Set-ArmTestState {
        param([AllowNull()]$State)
        & (Get-Module Omnicit.PIM) { param($S) $script:_OPIMAuthState = $S } $State
    }

    # Replaces the state's ARM token, as a refresh or another sign-in in the process would.
    function script:Set-ArmTestToken {
        param([string]$TenantId, [string]$ObjectId)
        $Token = New-ArmTestToken -TenantId $TenantId -ObjectId $ObjectId
        & (Get-Module Omnicit.PIM) { param($T) $script:_OPIMAuthState['ArmToken'] = $T } $Token
    }

    # Latches the innermost frame of the named command on the current call stack, as Lock-OPIMSignIn
    # latches the command that called Initialize-OPIMAuth. The 401 refresh calls Initialize-OPIMAuth
    # from Invoke-OPIMArmWithRefresh, so a refused refresh latches that frame. A Pester mock body runs
    # several frames further in than that caller, so a mock of Initialize-OPIMAuth cannot call
    # Lock-OPIMSignIn itself.
    function script:Lock-NamedFrame {
        param([Parameter(Mandatory)][string]$Name)
        $Frame = @(Get-PSCallStack | Where-Object { $null -ne $_.InvocationInfo -and $_.InvocationInfo.MyCommand.Name -eq $Name })[0]
        if ($null -eq $Frame) { throw "Lock-NamedFrame: no frame of '$Name' is on the call stack." }
        & (Get-Module Omnicit.PIM) {
            param($Invocation)
            if ($null -eq $script:_OPIMSignInLatch) {
                $script:_OPIMSignInLatch = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
            }
            $script:_OPIMSignInLatch.AddOrUpdate($Invocation, $true)
        } $Frame.InvocationInfo
    }

    # Runs a script in Omnicit.PIM's scope in a nested pipeline of this runspace and returns what it
    # wrote, and the ids of the records it added to $global:Error. Pester runs every It inside a try,
    # and while any try is up the call stack a throw always propagates; a nested pipeline has none
    # above it, so it shows what a caller outside any try receives: under -ErrorAction
    # SilentlyContinue a function carries on past its own throw, and a throw inside a catch resumes
    # after that try. The mocks stay in force, since the nested pipeline shares this runspace and the
    # module's session state. SilentlyContinue keeps a record off the error stream, not out of
    # $global:Error, which is read from its newest entry back to the entry that was newest before
    # the run (by reference, so a full $Error list still reads right). The nested script starts from
    # $ErrorActionPreference = 'Continue', a console's default, so the GLOBAL preference of a
    # shell: pwsh step (Stop) does not reach it.
    function script:Invoke-OutsideAnyTry {
        param([Parameter(Mandatory)][string]$Script)
        $Marker = if ($global:Error.Count -gt 0) { $global:Error[0] } else { $null }
        $Shell = [powershell]::Create([System.Management.Automation.RunspaceMode]::CurrentRunspace)
        try {
            $null = $Shell.AddScript('param($Module) & $Module { $ErrorActionPreference = ''Continue''; ' + $Script + '}').AddArgument((Get-Module Omnicit.PIM))
            $Output = $Shell.Invoke()
            $Added = foreach ($Record in @($global:Error)) {
                if ($null -ne $Marker -and [object]::ReferenceEquals($Record, $Marker)) { break }
                $Record
            }
            [pscustomobject]@{
                Output   = @($Output | Where-Object { $null -ne $_ })
                ErrorIds = @($Added | ForEach-Object { [string]$_.FullyQualifiedErrorId })
            }
        } finally {
            $Shell.Dispose()
        }
    }
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Invoke-OPIMArmRequest' {
    BeforeAll {
        # Never a real sign-in and never a real wait: every test that reaches either overrides these.
        Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth {}
        Mock -ModuleName Omnicit.PIM Start-Sleep {}
    }
    BeforeEach {
        Set-ArmTestState -State (New-ArmTestState)
        InModuleScope Omnicit.PIM { $script:_OPIMSignInLatch = $null }
    }
    AfterAll {
        InModuleScope Omnicit.PIM {
            $script:_OPIMAuthState = $null
            $script:_OPIMSignInLatch = $null
        }
    }

    Context 'When the request succeeds' {
        It 'returns the parsed JSON body' {
            InModuleScope Omnicit.PIM {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"/subscriptions/22222222-2222-2222-2222-222222222222"}]}' }
                }
                $Result = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01'
                @($Result.value)[0].id | Should -BeExactly '/subscriptions/22222222-2222-2222-2222-222222222222'
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Method -eq 'GET' -and
                    $Uri.OriginalString -ceq 'https://management.azure.com/subscriptions?api-version=2022-12-01' -and
                    $SkipHttpErrorCheck -eq $true
                }
            }
        }

        It 'hands the session''s own SecureString to -Token with -Authentication Bearer, and sets no Authorization header' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMTestSentToken = $null
                Mock Invoke-WebRequest {
                    $script:_OPIMTestSentToken = $Token
                    [PSCustomObject]@{ StatusCode = 200; Content = '{}' }
                }
                $null = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01'
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Authentication -eq 'Bearer' -and
                    $Token -is [securestring] -and
                    $null -eq $Headers
                }
                # The very object the state holds: the module never made a plaintext copy to send.
                [object]::ReferenceEquals($script:_OPIMTestSentToken, $script:_OPIMAuthState['ArmToken']) | Should -BeTrue
                $script:_OPIMTestSentToken = $null
            }
        }

        It 'serializes -Body to a JSON payload with the json content type' {
            InModuleScope Omnicit.PIM {
                Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 201; Content = '{"id":"x"}' } }
                $null = Invoke-OPIMArmRequest -Method PUT -Path '/x?api-version=2020-10-01' -Body @{ properties = @{ principalId = 'p1'; scheduleInfo = @{ expiration = @{ type = 'AfterDuration' } } } }
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Method -eq 'PUT' -and
                    ($Body | ConvertFrom-Json).properties.principalId -eq 'p1' -and
                    ($Body | ConvertFrom-Json).properties.scheduleInfo.expiration.type -eq 'AfterDuration' -and
                    $ContentType -eq 'application/json'
                }
            }
        }

        It 'sends no body and no content type without -Body' {
            InModuleScope Omnicit.PIM {
                Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }
                $null = Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01'
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $null -eq $Body -and -not $ContentType
                }
            }
        }

        It 'returns $null for an empty 204 response' {
            InModuleScope Omnicit.PIM {
                Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 204; Content = '' } }
                Invoke-OPIMArmRequest -Method DELETE -Path '/x?api-version=2020-10-01' | Should -BeNullOrEmpty
            }
        }

        It 'requests the root scope without a double slash (<Name>)' -ForEach @(
            @{ Name = 'a resource url without a trailing slash'; Url = 'https://management.azure.com' }
            @{ Name = 'a resource url with a trailing slash'; Url = 'https://management.azure.com/' }
        ) {
            $State = New-ArmTestState
            $State.ArmResourceUrl = $Url
            Set-ArmTestState -State $State
            InModuleScope Omnicit.PIM -Parameters @{ ListPath = $ListPath } {
                param($ListPath)
                Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[]}' } }
                $null = Invoke-OPIMArmRequest -Path $ListPath
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Uri.OriginalString -ceq 'https://management.azure.com/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01'
                }
            }
        }

        It 'sends to the session''s ArmResourceUrl' {
            $State = New-ArmTestState
            $State.ArmResourceUrl = 'https://management.contoso.com/'
            Set-ArmTestState -State $State
            InModuleScope Omnicit.PIM {
                Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }
                $null = Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01'
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Uri.OriginalString -ceq 'https://management.contoso.com/x?api-version=2020-10-01'
                }
            }
        }

        It 'sends to https://management.azure.com when the state records no ArmResourceUrl (<Name>)' -ForEach @(
            @{ Name = 'no key'; Remove = $true; Url = $null }
            @{ Name = 'a null value'; Remove = $false; Url = $null }
            @{ Name = 'an empty value'; Remove = $false; Url = '' }
        ) {
            $State = New-ArmTestState
            if ($Remove) { $State.Remove('ArmResourceUrl') } else { $State.ArmResourceUrl = $Url }
            Set-ArmTestState -State $State
            InModuleScope Omnicit.PIM {
                Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }
                $null = Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01'
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Uri.OriginalString -ceq 'https://management.azure.com/x?api-version=2020-10-01'
                }
            }
        }
    }

    Context 'When Azure Resource Manager answers with an error' {
        It 'throws a converted ErrorRecord on a non-2xx response' {
            InModuleScope Omnicit.PIM {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}' }
                }
                $Caught = $null
                try { $null = Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01' } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeExactly 'AuthorizationFailed'
                $Caught.Exception.Message | Should -BeExactly 'AuthorizationFailed: denied'
                $Caught.TargetObject | Should -BeExactly '/x?api-version=2020-10-01'
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly -Scope It
            }
        }

        It 'throws ArmTransportError for an error answer without an ARM error code' {
            InModuleScope Omnicit.PIM {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ StatusCode = 502; Content = '<html><body>Bad Gateway</body></html>' }
                }
                $Caught = $null
                try { $null = Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01' } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeExactly 'ArmTransportError'
                $Caught.Exception.Message | Should -BeExactly 'HTTP 502: Azure Resource Manager returned no error code.'
            }
        }

        It 'still converts a non-2xx response that carries headers' {
            InModuleScope Omnicit.PIM {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{
                        StatusCode = 403
                        Content    = '{"error":{"code":"AuthorizationFailed","message":"denied"}}'
                        Headers    = @{ 'x-ms-request-id' = @('r1'); 'Authorization' = @('Bearer NOT-A-REAL-TOKEN') }
                    }
                }
                { Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01' } | Should -Throw -ErrorId 'AuthorizationFailed'
            }
        }

        It 'wraps a transport-level exception as ArmTransportError without chaining or leaving the raw record' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMTestTransportException = [System.Exception]::new('No such host is known.')
                Mock Invoke-WebRequest { throw $script:_OPIMTestTransportException }

                $Caught = $null
                try {
                    $null = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01'
                } catch {
                    Remove-OPIMErrorRecord -Record $PSItem
                    $Caught = $PSItem
                }

                $Caught.FullyQualifiedErrorId | Should -BeExactly 'ArmTransportError'
                $Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::ConnectionError)
                $Caught.TargetObject | Should -BeExactly '/subscriptions?api-version=2022-12-01'
                $Caught.Exception.Message | Should -BeExactly 'Azure Resource Manager request failed before a response was received: No such host is known.'
                $Caught.Exception.InnerException | Should -BeNullOrEmpty
                @($global:Error | Where-Object { [object]::ReferenceEquals($PSItem.Exception, $script:_OPIMTestTransportException) }) |
                    Should -BeNullOrEmpty
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly -Scope It
                $script:_OPIMTestTransportException = $null
            }
        }
    }

    Context 'When Azure Resource Manager rejects the token (401)' {
        It 'refreshes with Initialize-OPIMAuth -IncludeARM -ForceRefresh and retries once' {
            InModuleScope Omnicit.PIM {
                $script:ArmCallCount = 0
                Mock Initialize-OPIMAuth {}
                Mock Invoke-WebRequest {
                    $script:ArmCallCount++
                    if ($script:ArmCallCount -eq 1) { [PSCustomObject]@{ StatusCode = 401; Content = '' } }
                    else { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":["after-refresh"]}' } }
                }
                $Result = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01'
                @($Result.value) | Should -Be @('after-refresh')
                Should -Invoke Invoke-WebRequest -Times 2 -Exactly -Scope It
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It
                # Exactly the two switches: no -TenantId, so the refresh keeps the session's tenant.
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter {
                    $IncludeARM -and $ForceRefresh -and
                    (@($PesterBoundParameters.Keys | Sort-Object) -join ',') -eq 'ForceRefresh,IncludeARM'
                }
            }
        }

        It 'converts a second 401 after the retry instead of looping' {
            InModuleScope Omnicit.PIM {
                Mock Initialize-OPIMAuth {}
                Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 401; Content = '' } }
                $Caught = $null
                try { $null = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeExactly 'ArmTransportError'
                $Caught.Exception.Message | Should -BeExactly 'HTTP 401: Azure Resource Manager returned no error code.'
                Should -Invoke Invoke-WebRequest -Times 2 -Exactly -Scope It
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It
            }
        }

        It 'still refreshes and retries once on 401 when the response carries headers' {
            InModuleScope Omnicit.PIM {
                Mock Initialize-OPIMAuth {}
                $script:ArmCallCount = 0
                Mock Invoke-WebRequest {
                    $script:ArmCallCount++
                    if ($script:ArmCallCount -eq 1) {
                        [PSCustomObject]@{ StatusCode = 401; Content = ''; Headers = @{ 'x-ms-request-id' = @('r1') } }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[]}'; Headers = @{ 'x-ms-request-id' = @('r2') } }
                    }
                }
                $null = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01'
                Should -Invoke Invoke-WebRequest -Times 2 -Exactly -Scope It
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ForceRefresh -and $IncludeARM }
            }
        }

        It 'does not refresh when the session state is gone by the time the 401 arrives' {
            InModuleScope Omnicit.PIM {
                Mock Initialize-OPIMAuth {}
                Mock Invoke-WebRequest {
                    $script:_OPIMAuthState = $null
                    [PSCustomObject]@{ StatusCode = 401; Content = '{"error":{"code":"InvalidAuthenticationToken","message":"expired"}}' }
                }
                { Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01' } | Should -Throw -ErrorId 'InvalidAuthenticationToken'
                Should -Invoke Initialize-OPIMAuth -Times 0 -Scope It
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly -Scope It
            }
        }
    }

    Context 'When -All reads several pages' {
        It 'aggregates the pages of nextLink, requesting each next page by its path and query' {
            InModuleScope Omnicit.PIM {
                $script:ArmCallCount = 0
                Mock Invoke-WebRequest {
                    $script:ArmCallCount++
                    if ($script:ArmCallCount -eq 1) {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"a"}],"nextLink":"https://management.azure.com/subscriptions?api-version=2022-12-01&$skipToken=t1"}' }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"b"}]}' }
                    }
                }
                $Result = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' -All
                @($Result.value.id) | Should -Be @('a', 'b')
                , $Result.value | Should -BeOfType ([object[]])
                Should -Invoke Invoke-WebRequest -Times 2 -Exactly -Scope It
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Uri.OriginalString -ceq 'https://management.azure.com/subscriptions?api-version=2022-12-01&$skipToken=t1'
                }
            }
        }

        It 'follows @nextLink' {
            InModuleScope Omnicit.PIM {
                $script:ArmCallCount = 0
                Mock Invoke-WebRequest {
                    $script:ArmCallCount++
                    if ($script:ArmCallCount -eq 1) {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"mg1"}],"@nextLink":"https://management.azure.com/providers/Microsoft.Management/managementGroups?api-version=2020-05-01&$skiptoken=t2"}' }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"mg2"}],"@nextLink":null}' }
                    }
                }
                $Result = Invoke-OPIMArmRequest -Path '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -All
                @($Result.value.id) | Should -Be @('mg1', 'mg2')
                Should -Invoke Invoke-WebRequest -Times 2 -Exactly -Scope It
            }
        }

        It 'requests a next link on the session''s ARM host by its path and query, skip token included (<Name>)' -ForEach @(
            @{ Name = 'the same host'; Link = 'https://management.azure.com/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01&$skiptoken=abc%3D%3D' }
            @{ Name = 'the host in other letter case'; Link = 'https://MANAGEMENT.azure.com/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01&$skiptoken=abc%3D%3D' }
            @{ Name = 'the default https port'; Link = 'https://management.azure.com:443/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01&$skiptoken=abc%3D%3D' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Link = $Link; ListPath = $ListPath } {
                param($Link, $ListPath)
                $script:_OPIMTestLink = $Link
                $script:ArmCallCount = 0
                Mock Invoke-WebRequest {
                    $script:ArmCallCount++
                    if ($script:ArmCallCount -eq 1) {
                        [PSCustomObject]@{ StatusCode = 200; Content = (@{ value = @(@{ id = 'a' }); nextLink = $script:_OPIMTestLink } | ConvertTo-Json -Compress) }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"b"}]}' }
                    }
                }
                $Result = Invoke-OPIMArmRequest -Path $ListPath -All
                @($Result.value.id) | Should -Be @('a', 'b')
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly -Scope It -ParameterFilter {
                    $Uri.OriginalString -ceq 'https://management.azure.com/providers/Microsoft.Authorization/roleEligibilitySchedules?$filter=asTarget()&api-version=2020-10-01&$skiptoken=abc%3D%3D'
                }
                $script:_OPIMTestLink = $null
            }
        }

        It 'throws the converted error of a later page, naming the caller''s path, and returns no partial list' {
            InModuleScope Omnicit.PIM {
                $script:ArmCallCount = 0
                Mock Invoke-WebRequest {
                    $script:ArmCallCount++
                    if ($script:ArmCallCount -eq 1) {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"a"}],"nextLink":"https://management.azure.com/subscriptions?api-version=2022-12-01&$skipToken=t1"}' }
                    } else {
                        [PSCustomObject]@{ StatusCode = 500; Content = '{"error":{"code":"InternalServerError","message":"boom"}}' }
                    }
                }
                $Result = $null
                $Caught = $null
                try { $Result = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' -All } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeExactly 'InternalServerError'
                # The caller's path, never the next link, which can carry a skip token.
                $Caught.TargetObject | Should -BeExactly '/subscriptions?api-version=2022-12-01'
                $Result | Should -BeNullOrEmpty
            }
        }

        It 'refreshes and retries once when a PAGE fetch 401s' {
            InModuleScope Omnicit.PIM {
                Mock Initialize-OPIMAuth {}
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    switch ($script:Call) {
                        1 { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"a"}],"nextLink":"https://management.azure.com/subs?api-version=2022-12-01&$skip=1"}' } }
                        2 { [PSCustomObject]@{ StatusCode = 401; Content = '{"error":{"code":"ExpiredAuthenticationToken"}}' } }
                        default { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"b"}]}' } }
                    }
                }
                $Result = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' -All
                @($Result.value.id) | Should -Be @('a', 'b')
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ForceRefresh -and $IncludeARM }
                Should -Invoke Invoke-WebRequest -Times 3 -Exactly -Scope It
            }
        }

        It 'budgets exactly one refresh across a two-page 401 walk, not one refresh per page' {
            InModuleScope Omnicit.PIM {
                # Counted in the mock body as well: the counter proves the body ran at all.
                $script:RefreshCount = 0
                Mock Initialize-OPIMAuth { $script:RefreshCount++ }
                # Page 1 OK (nextLink), page 2 401 once then OK (nextLink), page 3 401 again. The single
                # per-call refresh budget was already spent recovering page 2, so page 3's 401 is NOT
                # retried -- it converts to a thrown error instead of a second refresh.
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    switch ($script:Call) {
                        1 { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"a"}],"nextLink":"https://management.azure.com/subs?api-version=2022-12-01&$skip=1"}' } }
                        2 { [PSCustomObject]@{ StatusCode = 401; Content = '{"error":{"code":"ExpiredAuthenticationToken"}}' } }
                        3 { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"b"}],"nextLink":"https://management.azure.com/subs?api-version=2022-12-01&$skip=2"}' } }
                        default { [PSCustomObject]@{ StatusCode = 401; Content = '{"error":{"code":"ExpiredAuthenticationToken"}}' } }
                    }
                }
                { Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' -All } |
                    Should -Throw -ErrorId 'ExpiredAuthenticationToken'
                $script:RefreshCount | Should -Be 1
                Should -Invoke Initialize-OPIMAuth -Times 1 -Exactly -Scope It
                Should -Invoke Invoke-WebRequest -Times 4 -Exactly -Scope It
            }
        }

        It 'still aggregates pages when every page carries headers' {
            InModuleScope Omnicit.PIM {
                $script:ArmCallCount = 0
                Mock Invoke-WebRequest {
                    $script:ArmCallCount++
                    if ($script:ArmCallCount -eq 1) {
                        [PSCustomObject]@{
                            StatusCode = 200
                            Content    = '{"value":[{"id":"a"}],"nextLink":"https://management.azure.com/subscriptions?api-version=2022-12-01&$skipToken=t1"}'
                            Headers    = @{ 'x-ms-request-id' = @('r1') }
                        }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"b"}]}'; Headers = @{ 'x-ms-request-id' = @('r2') } }
                    }
                }
                $Result = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' -All
                @($Result.value).Count | Should -Be 2
            }
        }
    }

    Context 'When a next link leaves the session''s ARM host (Review Focus 4)' {
        # A next link is followed only when it is an absolute https URI on the session's ARM host. Any
        # other would carry the session's ARM token elsewhere: it is never sent, the call throws a
        # terminating error with no error id (category SecurityError), and nothing is returned. The
        # mock answers page n with the item id n and the n-th link of $script:_OPIMTestLinks, and
        # records every URI it is asked for.
        BeforeAll {
            InModuleScope Omnicit.PIM {
                Mock Invoke-WebRequest {
                    $script:_OPIMTestSent.Add($Uri.OriginalString)
                    $Index = $script:_OPIMTestSent.Count
                    $Page = [ordered]@{ value = @(@{ id = [string]$Index }) }
                    if ($Index -le @($script:_OPIMTestLinks).Count -and $script:_OPIMTestLinks[$Index - 1]) {
                        $Page['nextLink'] = $script:_OPIMTestLinks[$Index - 1]
                    }
                    [PSCustomObject]@{ StatusCode = 200; Content = ($Page | ConvertTo-Json -Compress -Depth 5) }
                }
            }
        }
        BeforeEach {
            InModuleScope Omnicit.PIM {
                $script:_OPIMTestSent = [System.Collections.Generic.List[string]]::new()
                $script:_OPIMTestLinks = @()
            }
        }
        AfterAll {
            InModuleScope Omnicit.PIM {
                $script:_OPIMTestSent = $null
                $script:_OPIMTestLinks = $null
            }
        }

        It 'refuses <Name> and sends nothing for it' -ForEach @(
            @{ Name = 'a link to another host'; Link = 'https://evil.example.com/providers/x?$skiptoken=2' }
            @{ Name = 'a link over http'; Link = 'http://management.azure.com/providers/x?$skiptoken=2' }
            @{ Name = 'a relative link'; Link = '/providers/x?$skiptoken=2' }
            @{ Name = 'a scheme-relative link'; Link = '//evil.example.com/providers/x?$skiptoken=2' }
            @{ Name = 'a link on a host that starts with the right name'; Link = 'https://management.azure.com.evil.example.com/providers/x?$skiptoken=2' }
            @{ Name = 'a link whose user info names the right host'; Link = 'https://management.azure.com@evil.example.com/providers/x?$skiptoken=2' }
            @{ Name = 'a link with another scheme'; Link = 'ftp://management.azure.com/providers/x?$skiptoken=2' }
            @{ Name = 'a link that is no URI'; Link = 'not a uri $skiptoken=2' }
        ) {
            InModuleScope Omnicit.PIM -Parameters @{ Link = $Link } {
                param($Link)
                $script:_OPIMTestLinks = @($Link)
                $Result = $null
                $Caught = $null
                try { $Result = Invoke-OPIMArmRequest -Path '/providers/x?api-version=2020-10-01' -All } catch { $Caught = $PSItem }
                $Caught | Should -Not -BeNullOrEmpty -Because 'a link that is not followed leaves the list incomplete'
                $Caught.Exception.Message | Should -BeExactly 'Page 2: Azure Resource Manager returned a next link that is not an https link on the session''s Azure Resource Manager host, so it was not followed and the list is incomplete.'
                $Caught.Exception.Message | Should -Not -Match 'evil|example|skiptoken|://|\.com'
                $Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::SecurityError)
                # No error id: the record's id is only the name of the command that raised it.
                $Caught.FullyQualifiedErrorId | Should -BeExactly 'Invoke-OPIMArmRequest'
                $Caught.TargetObject | Should -BeNullOrEmpty
                $Result | Should -BeNullOrEmpty
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly -Scope It
                @($script:_OPIMTestSent) | Should -Be @('https://management.azure.com/providers/x?api-version=2020-10-01')
            }
        }

        It 'numbers the page that would have been read' {
            InModuleScope Omnicit.PIM {
                $script:_OPIMTestLinks = @(
                    'https://management.azure.com/providers/x?api-version=2020-10-01&$skiptoken=2'
                    'https://evil.example.com/providers/x?$skiptoken=3'
                )
                $Caught = $null
                try { $null = Invoke-OPIMArmRequest -Path '/providers/x?api-version=2020-10-01' -All } catch { $Caught = $PSItem }
                $Caught.Exception.Message | Should -BeLike 'Page 3: Azure Resource Manager returned a next link that is not an https link*'
                Should -Invoke Invoke-WebRequest -Times 2 -Exactly -Scope It
            }
        }

        It 'follows a link on the session''s own ArmResourceUrl host and refuses one on management.azure.com' {
            $State = New-ArmTestState
            $State.ArmResourceUrl = 'https://management.contoso.com'
            Set-ArmTestState -State $State
            InModuleScope Omnicit.PIM {
                $script:_OPIMTestLinks = @(
                    'https://management.contoso.com/providers/x?api-version=2020-10-01&$skiptoken=2'
                    'https://management.azure.com/providers/x?api-version=2020-10-01&$skiptoken=3'
                )
                $Caught = $null
                try { $null = Invoke-OPIMArmRequest -Path '/providers/x?api-version=2020-10-01' -All } catch { $Caught = $PSItem }
                $Caught.Exception.Message | Should -BeLike 'Page 3: *'
                @($script:_OPIMTestSent) | Should -Be @(
                    'https://management.contoso.com/providers/x?api-version=2020-10-01'
                    'https://management.contoso.com/providers/x?api-version=2020-10-01&$skiptoken=2'
                )
            }
        }

        It 'returns nothing outside any try when a next link leaves the host' {
            InModuleScope Omnicit.PIM { $script:_OPIMTestLinks = @('https://evil.example.com/providers/x?$skiptoken=2') }
            $Run = Invoke-OutsideAnyTry -Script '$R = Invoke-OPIMArmRequest -Path ''/providers/x?api-version=2020-10-01'' -All -ErrorAction SilentlyContinue; $R'
            $Run.Output.Count | Should -Be 0
            $Run.ErrorIds | Should -Be @('Invoke-OPIMArmRequest')
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 1 -Exactly -Scope It
        }

        It 'writes neither the link nor its host to the verbose stream' {
            InModuleScope Omnicit.PIM { $script:_OPIMTestLinks = @('https://evil.example.com/providers/x?$skiptoken=2') }
            $Run = Invoke-OutsideAnyTry -Script 'Invoke-OPIMArmRequest -Path ''/providers/x?api-version=2020-10-01'' -All -ErrorAction SilentlyContinue -Verbose 4>&1'
            $Records = @($Run.Output | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
            $Records.Count | Should -BeGreaterOrEqual 1 -Because 'the page that was read is still reported'
            $Text = ($Records | ForEach-Object { $_.Message }) -join "`n"
            $Text | Should -Match '\[Invoke-OPIMArmRequest\] GET /providers/x'
            $Text | Should -Not -Match 'evil|example|skiptoken|api-version'
        }
    }

    Context 'When the verbose stream is written' {
        It 'names the method and the path without its query string' {
            InModuleScope Omnicit.PIM -Parameters @{ ListPath = $ListPath } {
                param($ListPath)
                Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[]}' } }
                $Verbose = (Invoke-OPIMArmRequest -Method GET -Path $ListPath -Verbose 4>&1) |
                    Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
                @($Verbose.Message) | Should -Be @('[Invoke-OPIMArmRequest] GET /providers/Microsoft.Authorization/roleEligibilitySchedules')
            }
        }

        It 'never writes the request body or a token to the verbose stream' {
            InModuleScope Omnicit.PIM {
                Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }
                $Verbose = (Invoke-OPIMArmRequest -Method PUT -Path '/x?api-version=2020-10-01' -Body @{ secretish = 'do-not-log-me' } -Verbose 4>&1) |
                    Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
                $Text = $Verbose.Message -join "`n"
                # Control: the verbose stream is not empty, so the negatives below are not vacuous.
                $Text | Should -Match '\[Invoke-OPIMArmRequest\] PUT /x'
                $Text | Should -Not -Match 'do-not-log-me'
                $Text | Should -Not -Match 'NOT-A-REAL-TOKEN'
                $Text | Should -Not -Match '(?i)bearer'
            }
        }

        It 'emits one line per page when paging, without the skip token' {
            InModuleScope Omnicit.PIM {
                $script:ArmCallCount = 0
                Mock Invoke-WebRequest {
                    $script:ArmCallCount++
                    if ($script:ArmCallCount -eq 1) {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[1],"nextLink":"https://management.azure.com/next?api-version=2022-12-01&$skiptoken=secret-skip"}' }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[2]}' }
                    }
                }
                $Verbose = (Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' -All -Verbose 4>&1) |
                    Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
                @($Verbose.Message) | Should -Be @('[Invoke-OPIMArmRequest] GET /subscriptions', '[Invoke-OPIMArmRequest] GET /next')
            }
        }

        It 'never writes header material to the verbose stream' {
            InModuleScope Omnicit.PIM {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{
                        StatusCode = 200
                        Content    = '{}'
                        Headers    = @{
                            'Authorization'               = @('Bearer NOT-A-REAL-TOKEN-super-secret')
                            'x-ms-request-id'             = @('44444444-4444-4444-4444-444444444444')
                            'client-request-id'           = @('55555555-5555-5555-5555-555555555555')
                            'x-ms-correlation-request-id' = @('66666666-6666-6666-6666-666666666666')
                        }
                    }
                }
                $Verbose = (Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01' -Verbose 4>&1) |
                    Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
                $Text = $Verbose.Message -join "`n"
                $Text | Should -Match '\[Invoke-OPIMArmRequest\] GET /x'
                $Text | Should -Not -Match '(?i)bearer'
                $Text | Should -Not -Match '44444444-4444-4444-4444-444444444444'
                $Text | Should -Not -Match '55555555-5555-5555-5555-555555555555'
                $Text | Should -Not -Match '66666666-6666-6666-6666-666666666666'
            }
        }
    }

    Context 'When Azure Resource Manager throttles (A5)' {
        It 'retries a 429 and honours Retry-After in seconds' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    if ($script:Call -eq 1) {
                        [PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests"}}'; Headers = @{ 'Retry-After' = @('60') } }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"a"}]}'; Headers = @{} }
                    }
                }
                $Result = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01'
                @($Result.value)[0].id | Should -Be 'a'
                Should -Invoke Invoke-WebRequest -Times 2 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 60 }
            }
        }

        It 'carries the response headers through the normalization to the status logic' {
            InModuleScope Omnicit.PIM {
                # The header survived exactly when a 429 whose Retry-After says 7 produces a 7-second
                # wait; without the Headers property on the normalized shape the wait would be the
                # exponential fallback of 1 s.
                Mock Start-Sleep {}
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    if ($script:Call -eq 1) {
                        [PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests","message":"slow down"}}'; Headers = @{ 'Retry-After' = @('7') } }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[]}'; Headers = @{} }
                    }
                }
                $null = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01'
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 7 }
            }
        }

        It 'reads Retry-After case-insensitively' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    if ($script:Call -eq 1) {
                        [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'retry-after' = @('11') } }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                    }
                }
                $null = Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01'
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 11 }
            }
        }

        It 'reads Retry-After from a header dictionary as Invoke-WebRequest returns it' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    if ($script:Call -eq 1) {
                        $Headers = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.IEnumerable[string]]]::new()
                        $Headers['Retry-After'] = [string[]]@('13')
                        [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = $Headers }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                    }
                }
                $null = Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01'
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 13 }
            }
        }

        It 'honours an HTTP-date Retry-After rather than reading it as zero seconds' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                $script:_OPIMTestHttpDate = [DateTime]::UtcNow.AddSeconds(45).ToString('R')
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    if ($script:Call -eq 1) {
                        [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @($script:_OPIMTestHttpDate) } }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                    }
                }
                $null = Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01'
                # A ~45 s date, allowing for clock drift and rounding across the call.
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -ge 40 -and $Seconds -le 46 }
                $script:_OPIMTestHttpDate = $null
            }
        }

        It 'clamps an HTTP-date Retry-After that is already past up to one second' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                $script:_OPIMTestHttpDate = [DateTime]::UtcNow.AddMinutes(-10).ToString('R')
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    if ($script:Call -eq 1) {
                        [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @($script:_OPIMTestHttpDate) } }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                    }
                }
                $null = Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01'
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 1 }
                $script:_OPIMTestHttpDate = $null
            }
        }

        It 'falls back to exponential backoff when a 429 carries no Retry-After' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    if ($script:Call -le 2) {
                        [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{} }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                    }
                }
                $null = Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01'
                # 2^0 = 1, then 2^1 = 2.
                Should -Invoke Start-Sleep -Times 2 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 1 }
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 2 }
            }
        }

        It 'falls back to exponential backoff when Retry-After cannot be parsed, never to zero' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    if ($script:Call -eq 1) {
                        [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('not-a-number') } }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                    }
                }
                $null = Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01'
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 1 }
                Should -Invoke Start-Sleep -Times 0 -Scope It -ParameterFilter { $Seconds -le 0 }
            }
        }

        It 'clamps a single wait to 120 seconds' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    if ($script:Call -eq 1) {
                        [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('100000') } }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                    }
                }
                $null = Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01'
                # The unfiltered total first: the filtered assertions alone could not see a second
                # sleep at some other value.
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 120 }
                Should -Invoke Start-Sleep -Times 0 -Scope It -ParameterFilter { $Seconds -gt 120 }
            }
        }

        It 'clamps a Retry-After of 0 up to one second so the budget is always spent' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    if ($script:Call -eq 1) {
                        [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('0') } }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                    }
                }
                $null = Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01'
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 1 }
            }
        }

        It 'retries a 503 that carries Retry-After' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    if ($script:Call -eq 1) {
                        [PSCustomObject]@{ StatusCode = 503; Content = '{}'; Headers = @{ 'Retry-After' = @('5') } }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{"ok":true}'; Headers = @{} }
                    }
                }
                $Result = Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01'
                $Result.ok | Should -BeTrue
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 5 }
                Should -Invoke Invoke-WebRequest -Times 2 -Exactly -Scope It
            }
        }

        It 'does NOT retry a 503 with no Retry-After' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ StatusCode = 503; Content = '{"error":{"code":"ServiceUnavailable","message":"down"}}'; Headers = @{} }
                }
                { Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01' } | Should -Throw -ErrorId 'ServiceUnavailable'
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 0 -Scope It
            }
        }

        It 'does not retry an ordinary failure such as 403, even with a Retry-After' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}'; Headers = @{ 'Retry-After' = @('30') } }
                }
                { Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01' } | Should -Throw -ErrorId 'AuthorizationFailed'
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly -Scope It
                Should -Invoke Start-Sleep -Times 0 -Scope It
            }
        }

        It 'gives up when the per-REQUEST wait budget cannot cover the next wait' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                # 120 s per wait (clamped from 300). 300 s of budget buys exactly two waits; the third
                # request's 120 s wait does not fit in the 60 s left, so the loop gives up.
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests"}}'; Headers = @{ 'Retry-After' = @('300') } }
                }
                { Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01' } | Should -Throw -ErrorId 'TooManyRequests'
                Should -Invoke Start-Sleep -Times 2 -Exactly -Scope It
                Should -Invoke Invoke-WebRequest -Times 3 -Exactly -Scope It
            }
        }

        It 'spends the per-REQUEST budget to its last second' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                # Three waits of 100 s spend exactly 300 s; the fourth answer asks for 1 s, which no
                # longer fits. A budget one second larger would take it, one second smaller would
                # refuse the third.
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    $Wait = if ($script:Call -le 3) { '100' } else { '1' }
                    [PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests"}}'; Headers = @{ 'Retry-After' = @($Wait) } }
                }
                { Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01' } | Should -Throw -ErrorId 'TooManyRequests'
                Should -Invoke Start-Sleep -Times 3 -Exactly -Scope It
                Should -Invoke Invoke-WebRequest -Times 4 -Exactly -Scope It
            }
        }

        It 'names the per-REQUEST budget in the give-up verbose line' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests"}}'; Headers = @{ 'Retry-After' = @('300') } }
                }
                # Streamed into a List: the call ends by throwing, so "$Records = <expr>" would never
                # complete and would leave $Records empty.
                $Records = [System.Collections.Generic.List[object]]::new()
                try { Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01' -Verbose 4>&1 | ForEach-Object { $Records.Add($PSItem) } }
                catch { Remove-OPIMErrorRecord -Record $PSItem }
                $Text = (@($Records | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Message) -join "`n"
                # Control first, so the give-up assertion cannot pass on an empty capture.
                $Text | Should -Match 'Throttled'
                $Text | Should -Match 'per-REQUEST budget remain\. Giving up\.'
            }
        }

        It 'stops at the hard cap of 10 retries when Retry-After stays small' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests"}}'; Headers = @{ 'Retry-After' = @('1') } }
                }
                $Records = [System.Collections.Generic.List[object]]::new()
                try { Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01' -Verbose 4>&1 | ForEach-Object { $Records.Add($PSItem) } }
                catch { $Caught = $PSItem; Remove-OPIMErrorRecord -Record $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeExactly 'TooManyRequests'
                # 10 waits of 1 s spend only 10 s of the 300 s budget: the cap is what binds.
                Should -Invoke Start-Sleep -Times 10 -Exactly -Scope It
                Should -Invoke Invoke-WebRequest -Times 11 -Exactly -Scope It
                $Text = (@($Records | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Message) -join "`n"
                $Text | Should -Match 'Reached the hard cap of 10 throttle retries'
            }
        }

        It 'backs off on the -All paging path too' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    switch ($script:Call) {
                        1 { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"a"}],"nextLink":"https://management.azure.com/subs?api-version=2022-12-01&$skip=1"}'; Headers = @{} } }
                        2 { [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('9') } } }
                        default { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"b"}]}'; Headers = @{} } }
                    }
                }
                $Result = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' -All
                @($Result.value.id) | Should -Be @('a', 'b')
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter { $Seconds -eq 9 }
            }
        }

        It 'gives each PAGE its own per-request budget while sharing the per-call deadline' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                # Two pages, each throttled twice for 120 s (240 s each). One per-request budget of
                # 300 s shared by both pages would refuse page 2's waits; a budget per page allows them.
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    switch ($script:Call) {
                        { $_ -in 1, 2 } { [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('120') } } }
                        3 { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"a"}],"nextLink":"https://management.azure.com/subs?api-version=2022-12-01&$skip=1"}'; Headers = @{} } }
                        { $_ -in 4, 5 } { [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('120') } } }
                        default { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"b"}]}'; Headers = @{} } }
                    }
                }
                $Result = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' -All
                @($Result.value.id) | Should -Be @('a', 'b')
                Should -Invoke Start-Sleep -Times 4 -Exactly -Scope It -ParameterFilter { $Seconds -eq 120 }
            }
        }

        It 'enforces the per-CALL deadline across pages and never returns a truncated collection' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                # Each page is throttled once for 120 s and then answers with the next link. The 900 s
                # per-CALL deadline fits 7 waits (840 s); the 8th does not, so the whole call fails --
                # it must THROW, not return the pages already read.
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    # Hang guard: a deadline that no longer binds fails here instead of paging forever.
                    if ($script:Call -gt 40) { throw 'hang guard: the per-CALL deadline did not end the walk' }
                    if ($script:Call % 2 -eq 1) {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"p"}],"nextLink":"https://management.azure.com/subs?api-version=2022-12-01&$skip=1"}'; Headers = @{} }
                    } else {
                        [PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests"}}'; Headers = @{ 'Retry-After' = @('120') } }
                    }
                }
                $Result = $null
                $Caught = $null
                try { $Result = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' -All } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -BeExactly 'TooManyRequests'
                $Result | Should -BeNullOrEmpty
                Should -Invoke Start-Sleep -Times 7 -Exactly -Scope It
            }
        }

        It 'names the per-CALL deadline in the give-up verbose line' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    # Hang guard: a deadline that no longer binds fails here instead of paging forever.
                    if ($script:Call -gt 40) { throw 'hang guard: the per-CALL deadline did not end the walk' }
                    if ($script:Call % 2 -eq 1) {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"p"}],"nextLink":"https://management.azure.com/subs?api-version=2022-12-01&$skip=1"}'; Headers = @{} }
                    } else {
                        [PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests"}}'; Headers = @{ 'Retry-After' = @('120') } }
                    }
                }
                $Records = [System.Collections.Generic.List[object]]::new()
                try { Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' -All -Verbose 4>&1 | ForEach-Object { $Records.Add($PSItem) } }
                catch { Remove-OPIMErrorRecord -Record $PSItem }
                $Text = (@($Records | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Message) -join "`n"
                # Only the give-up line ends with "Giving up."; an ordinary retry line names both budgets.
                $Text | Should -Match 'per-CALL budget remain\. Giving up\.'
            }
        }

        It 'emits one verbose line per retry naming the delay, the attempt and the value source' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    if ($script:Call -eq 1) {
                        [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('30') } }
                    } elseif ($script:Call -eq 2) {
                        [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{} }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                    }
                }
                $Verbose = (Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01' -Verbose 4>&1) |
                    Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
                $Lines = @($Verbose.Message | Where-Object { $_ -match 'Throttled' })
                $Lines.Count | Should -Be 2
                $Lines[0] | Should -Match 'Waiting 30 s \(server-directed\) before retry 1'
                # Attempt 1 already spent, so the fallback exponent is 2^1 = 2.
                $Lines[1] | Should -Match 'Waiting 2 s \(exponential fallback\) before retry 2'
            }
        }

        It 'never writes header material to the verbose stream while backing off' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    if ($script:Call -eq 1) {
                        [PSCustomObject]@{
                            StatusCode = 429
                            Content    = '{}'
                            Headers    = @{
                                'Retry-After'                                 = @('3')
                                'Authorization'                               = @('Bearer NOT-A-REAL-TOKEN-super-secret')
                                'x-ms-request-id'                             = @('44444444-4444-4444-4444-444444444444')
                                'client-request-id'                           = @('55555555-5555-5555-5555-555555555555')
                                'x-ms-ratelimit-remaining-subscription-reads' = @('11999')
                            }
                        }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                    }
                }
                $Verbose = (Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01' -Verbose 4>&1) |
                    Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
                $Text = $Verbose.Message -join "`n"
                # Control first: the backoff did run, so the negatives below are not vacuous.
                $Text | Should -Match 'Waiting 3 s'
                $Text | Should -Not -Match '(?i)bearer'
                $Text | Should -Not -Match '44444444-4444-4444-4444-444444444444'
                $Text | Should -Not -Match '55555555-5555-5555-5555-555555555555'
                $Text | Should -Not -Match 'x-ms-ratelimit'
                $Text | Should -Not -Match '11999'
            }
        }

        It 'does not let a throttled response consume the 401 refresh budget' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                $script:RefreshCount = 0
                Mock Initialize-OPIMAuth { $script:RefreshCount++ }
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    if ($script:Call -le 3) {
                        [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('2') } }
                    } elseif ($script:Call -eq 4) {
                        [PSCustomObject]@{ StatusCode = 401; Content = '{}'; Headers = @{} }
                    } else {
                        [PSCustomObject]@{ StatusCode = 200; Content = '{"ok":true}'; Headers = @{} }
                    }
                }
                # Three throttles, then a 401 that the unspent refresh budget still recovers.
                (Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01').ok | Should -BeTrue
                $script:RefreshCount | Should -Be 1
                Should -Invoke Start-Sleep -Times 3 -Exactly -Scope It
                Should -Invoke Invoke-WebRequest -Times 5 -Exactly -Scope It
            }
        }

        It 'still allows exactly one 401 refresh after a throttle, and does not compound the two loops' {
            InModuleScope Omnicit.PIM {
                Mock Start-Sleep {}
                $script:RefreshCount = 0
                Mock Initialize-OPIMAuth { $script:RefreshCount++ }
                # 429 -> retry -> 401 -> refresh -> 401 again (budget spent) -> converts and throws.
                $script:Call = 0
                Mock Invoke-WebRequest {
                    $script:Call++
                    if ($script:Call -eq 1) {
                        [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('2') } }
                    } else {
                        [PSCustomObject]@{ StatusCode = 401; Content = '{"error":{"code":"ExpiredAuthenticationToken"}}'; Headers = @{} }
                    }
                }
                { Invoke-OPIMArmRequest -Path '/x?api-version=2020-10-01' } | Should -Throw -ErrorId 'ExpiredAuthenticationToken'
                $script:RefreshCount | Should -Be 1
                Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It
                # 1 (429) + 1 (401) + 1 (retry after refresh) = 3. Bounded.
                Should -Invoke Invoke-WebRequest -Times 3 -Exactly -Scope It
            }
        }
    }

    Context 'When the session holds no ARM token' {
        BeforeAll {
            $NoTokenMessage = 'No Azure Resource Manager request was sent: the module''s session holds no Azure Resource Manager token. Run Connect-OPIM -IncludeARM to sign in to Azure, and run the command again.'
        }

        It 'refuses a session with <Name> before any request, with ArmTokenAcquisitionFailed' -ForEach @(
            @{ Name = 'no auth state'; Shape = 'NoState' }
            @{ Name = 'a state that is not a dictionary'; Shape = 'NotDictionary' }
            @{ Name = 'no ArmToken key'; Shape = 'NoKey' }
            @{ Name = 'a null ArmToken'; Shape = 'Null' }
            @{ Name = 'an empty SecureString'; Shape = 'Empty' }
            @{ Name = 'an ArmToken that is not a SecureString'; Shape = 'String' }
        ) {
            $State = switch ($Shape) {
                'NoState' { $null }
                'NotDictionary' { [pscustomobject](New-ArmTestState) }
                'NoKey' { $S = New-ArmTestState; $S.Remove('ArmToken'); $S }
                'Null' { New-ArmTestState -ArmToken $null }
                'Empty' { New-ArmTestState -ArmToken ([securestring]::new()) }
                'String' { New-ArmTestState -ArmToken (New-OPIMTestAccessToken -TenantId $SessionTenant -ObjectId $SessionAccount) }
            }
            Set-ArmTestState -State $State
            $Caught = InModuleScope Omnicit.PIM {
                Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }
                try { $null = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $PSItem }
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 0 -Scope It
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'ArmTokenAcquisitionFailed'
            $Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
            $Caught.TargetObject | Should -BeExactly '/subscriptions?api-version=2022-12-01'
            $Caught.Exception.Message | Should -BeExactly $NoTokenMessage
        }

        It 'reads SignInRefused, not ArmTokenAcquisitionFailed, for a latched command without a token (the gate comes first)' {
            $State = New-ArmTestState
            $State.Remove('ArmToken')
            Set-ArmTestState -State $State
            $Caught = InModuleScope Omnicit.PIM {
                Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }
                function Initialize-StandIn { $null = Lock-OPIMSignIn }
                function Invoke-RefusedCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                    $Caught = $null
                    try { $null = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $Caught = $PSItem }
                    $Caught
                }
                Invoke-RefusedCommand
            }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 0 -Scope It
            $Caught.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
            $Caught.TargetObject | Should -BeExactly 'Invoke-RefusedCommand'
        }

        It 'sends one request, then refuses the 401 retry, when the refresh leaves the session without an ARM token' {
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 401; Content = '{}' } }
            # A refresh that succeeds but leaves no ARM token behind: the retry has nothing to send.
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth { & (Get-Module Omnicit.PIM) { $script:_OPIMAuthState.Remove('ArmToken') } }
            $Caught = InModuleScope Omnicit.PIM {
                try { $null = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $PSItem }
            }
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ForceRefresh -and $IncludeARM }
            # The rejected first request only: the retry is never sent.
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 1 -Exactly -Scope It
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'ArmTokenAcquisitionFailed'
        }
    }

    Context 'When the ARM gate refuses a request (OPIM-08, A3, EntraRBAC A19)' {
        # Get-OPIMArmRefusal stands before every request: the first attempt, the 401 retry and every
        # page. A latched command is SignInRefused; an ARM token for another tenant is TenantMismatch,
        # for another account AccountMismatch. A refused request is never sent.
        It 'refuses a request made for a latched command with SignInRefused, sending nothing' {
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }
            $Caught = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { $null = Lock-OPIMSignIn }
                function Invoke-RefusedCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                    $Caught = $null
                    try { $null = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $Caught = $PSItem }
                    $Caught
                }
                Invoke-RefusedCommand
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
            $Caught.CategoryInfo.Category | Should -Be 'AuthenticationError'
            $Caught.TargetObject | Should -BeExactly 'Invoke-RefusedCommand'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 0 -Scope It
        }

        It 'refuses a request a latched command makes through a nested command whose own sign-in succeeded' {
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }
            $Caught = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { Lock-OPIMSignIn }
                function Invoke-NestedCommand {
                    [CmdletBinding()]
                    param()
                    $Own = Initialize-StandIn
                    Unlock-OPIMSignIn -Invocation $Own
                    $Caught = $null
                    try { $null = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $Caught = $PSItem }
                    $Caught
                }
                function Invoke-RefusedCommand {
                    [CmdletBinding()]
                    param()
                    $null = Initialize-StandIn
                    Invoke-NestedCommand
                }
                Invoke-RefusedCommand
            }
            $Caught.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
            $Caught.TargetObject | Should -BeExactly 'Invoke-RefusedCommand'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 0 -Scope It
        }

        It 'sends the request when the latch table was never created' {
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{"id":"sent"}' } }
            $Result = InModuleScope Omnicit.PIM {
                Remove-Variable -Scope Script -Name _OPIMSignInLatch -ErrorAction Ignore
                Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01'
            }
            $Result.id | Should -Be 'sent'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 1 -Exactly -Scope It
        }

        It 'sends the request when the table holds only a command that is not on the call stack' {
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{"id":"sent"}' } }
            $R = InModuleScope Omnicit.PIM {
                function Initialize-StandIn { Lock-OPIMSignIn }
                function Invoke-RefusedCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                }
                function Invoke-LaterCommand {
                    [CmdletBinding()]
                    param()
                    Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01'
                }
                # Held here, so the weak table cannot drop the entry before the call below.
                $Other = Invoke-RefusedCommand
                $Value = $null
                $Held = $script:_OPIMSignInLatch.TryGetValue($Other, [ref]$Value)
                @{ Held = $Held; Result = (Invoke-LaterCommand) }
            }
            # Not vacuous: the table holds the other command while the later one sends.
            $R.Held | Should -BeTrue
            $R.Result.id | Should -Be 'sent'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 1 -Exactly -Scope It
        }

        It 'reads no claims of the ARM token for a refused request' {
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }
            $R = InModuleScope Omnicit.PIM {
                Mock Get-OPIMTokenTenantId { '22222222-2222-2222-2222-222222222222' }
                Mock Get-OPIMTokenObjectId { 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' }
                function Initialize-StandIn { $null = Lock-OPIMSignIn }
                function Invoke-RefusedCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                    $Caught = $null
                    try { $null = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $Caught = $PSItem }
                    $Caught
                }
                function Invoke-OpenCommand {
                    [CmdletBinding()]
                    param()
                    $null = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01'
                }
                $Caught = Invoke-RefusedCommand
                Should -Invoke Get-OPIMTokenTenantId -Times 0 -Scope It
                Should -Invoke Get-OPIMTokenObjectId -Times 0 -Scope It
                Invoke-OpenCommand
                # Not vacuous: the same state's token is read once for a request that is sent.
                Should -Invoke Get-OPIMTokenTenantId -Times 1 -Exactly -Scope It
                Should -Invoke Get-OPIMTokenObjectId -Times 1 -Exactly -Scope It
                $Caught
            }
            $R.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 1 -Exactly -Scope It
        }

        It 'refuses <Kind> on the first attempt and sends nothing' -ForEach @(
            @{ Kind = 'TenantMismatch'; What = 'tenant'; TenantId = '33333333-3333-3333-3333-333333333333'; ObjectId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' }
            @{ Kind = 'AccountMismatch'; What = 'account'; TenantId = '22222222-2222-2222-2222-222222222222'; ObjectId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' }
        ) {
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }
            Set-ArmTestToken -TenantId $TenantId -ObjectId $ObjectId
            $Caught = InModuleScope Omnicit.PIM {
                try { $null = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $PSItem }
            }
            $Caught.FullyQualifiedErrorId | Should -BeExactly $Kind
            $Caught.TargetObject | Should -BeExactly $SessionTenant
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 0 -Scope It
        }

        It 'refuses a blank token with TenantMismatch, since its tenant cannot be read, and sends nothing' {
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }
            Set-ArmTestState -State (New-ArmTestState -ArmToken ([System.Net.NetworkCredential]::new('', '   ').SecurePassword))
            $Caught = InModuleScope Omnicit.PIM {
                try { $null = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $PSItem }
            }
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch'
            $Caught.Exception.Message | Should -BeLike 'The tenant of the Azure Resource Manager token could not be read*'
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 0 -Scope It
        }

        It 'refuses the retry after a 401 refresh with SignInRefused when the refresh leaves the wrapper latched' {
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 401; Content = '{}' } }
            # The refresh's sign-in is refused: Initialize-OPIMAuth latches its caller, and that caller
            # carries on past the refusal when no try is active up the call stack.
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth { Lock-NamedFrame -Name 'Invoke-OPIMArmWithRefresh' }
            $Caught = InModuleScope Omnicit.PIM {
                try { $null = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $PSItem }
            }
            $Caught.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
            $Caught.TargetObject | Should -BeExactly 'Invoke-OPIMArmWithRefresh'
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It -ParameterFilter { $ForceRefresh -and $IncludeARM }
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 1 -Exactly -Scope It
        }

        It 'refuses the retry after a 401 refresh with <Kind> when the refresh brings a token for another <What>' -ForEach @(
            @{ Kind = 'TenantMismatch'; What = 'tenant'; TenantId = '33333333-3333-3333-3333-333333333333'; ObjectId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' }
            @{ Kind = 'AccountMismatch'; What = 'account'; TenantId = '22222222-2222-2222-2222-222222222222'; ObjectId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' }
        ) {
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 401; Content = '{}' } }
            Mock -ModuleName Omnicit.PIM Initialize-OPIMAuth { Set-ArmTestToken -TenantId $TenantId -ObjectId $ObjectId }
            $Caught = InModuleScope Omnicit.PIM {
                try { $null = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $PSItem }
            }
            $Caught.FullyQualifiedErrorId | Should -BeExactly $Kind
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It
            # The rejected first request only: the retry is never sent.
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 1 -Exactly -Scope It
        }

        It 'refuses page 2 with <Kind> and returns no partial list' -ForEach @(
            @{ Kind = 'SignInRefused'; TenantId = $null; ObjectId = $null }
            @{ Kind = 'TenantMismatch'; What = 'tenant'; TenantId = '33333333-3333-3333-3333-333333333333'; ObjectId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' }
            @{ Kind = 'AccountMismatch'; What = 'account'; TenantId = '22222222-2222-2222-2222-222222222222'; ObjectId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' }
        ) {
            # Page 1 is answered, and while it is answered the session changes the way the case names:
            # the command is latched, or the ARM token is replaced by one for another tenant or account.
            # A page 2 that got through would end the list, so a missing gate fails instead of looping.
            InModuleScope Omnicit.PIM { $script:_OPIMTestCalls = 0 }
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest {
                $Count = & (Get-Module Omnicit.PIM) { $script:_OPIMTestCalls++; $script:_OPIMTestCalls }
                if ($Count -gt 1) { return [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"b"}]}' } }
                if ($Kind -eq 'SignInRefused') { Lock-NamedFrame -Name 'Invoke-OPIMArmRequest' }
                else { Set-ArmTestToken -TenantId $TenantId -ObjectId $ObjectId }
                [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"a"}],"nextLink":"https://management.azure.com/subscriptions?api-version=2022-12-01&$skipToken=t1"}' }
            }
            $R = InModuleScope Omnicit.PIM {
                $Result = $null
                $Caught = $null
                try { $Result = Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' -All } catch { $Caught = $PSItem }
                @{ Result = $Result; Caught = $Caught }
            }
            $R.Caught.FullyQualifiedErrorId | Should -BeLike "$Kind*"
            $R.Result | Should -BeNullOrEmpty
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 1 -Exactly -Scope It
        }
    }

    Context 'When no try stands up the call stack (Review Focus 3)' {
        # Under -ErrorAction SilentlyContinue with no try up the call stack a function carries on past
        # its own throw, and a throw inside a catch resumes after that try (Invoke-OutsideAnyTry). Every
        # throw of the wrapper is followed by a return, so nothing is sent after it and nothing is
        # returned. Each test counts the sends, reads what came back and the ids the run left in
        # $global:Error. A mock body that runs in the nested pipeline calls no helper of this file:
        # the file's script scope is not on that pipeline's scope chain, so state is kept in the
        # module's scope instead.
        It 'a request that gets no response leaves ArmTransportError as the only record, and returns nothing' {
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest { throw [System.Exception]::new('No such host is known.') }
            $Run = Invoke-OutsideAnyTry -Script '$R = Invoke-OPIMArmRequest -Path ''/subscriptions?api-version=2022-12-01'' -ErrorAction SilentlyContinue; $R'
            $Run.Output.Count | Should -Be 0
            $Run.ErrorIds | Should -Be @('ArmTransportError')
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 1 -Exactly -Scope It
        }

        It 'a non-2xx answer ends the call without handing back its error body as data' {
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest {
                [PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}'; Headers = @{} }
            }
            $Run = Invoke-OutsideAnyTry -Script '$R = Invoke-OPIMArmRequest -Path ''/subscriptions?api-version=2022-12-01'' -ErrorAction SilentlyContinue; $R'
            $Run.Output.Count | Should -Be 0
            $Run.ErrorIds | Should -Be @('AuthorizationFailed')
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 1 -Exactly -Scope It
        }

        It 'a non-2xx later page ends the paged read without the partial collection' {
            InModuleScope Omnicit.PIM { $script:_OPIMTestCalls = 0 }
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest {
                $Count = & (Get-Module Omnicit.PIM) { $script:_OPIMTestCalls++; $script:_OPIMTestCalls }
                if ($Count -eq 1) {
                    return [pscustomobject]@{
                        StatusCode = 200; Headers = @{}
                        Content    = '{"value":["a","b"],"nextLink":"https://management.azure.com/subscriptions?api-version=2022-12-01&$skiptoken=p2"}'
                    }
                }
                [pscustomobject]@{ StatusCode = 500; Content = '{"error":{"code":"InternalServerError","message":"boom"}}'; Headers = @{} }
            }
            $Run = Invoke-OutsideAnyTry -Script '$R = Invoke-OPIMArmRequest -Path ''/subscriptions?api-version=2022-12-01'' -All -ErrorAction SilentlyContinue; $R'
            # Nothing on the success channel: two items must never read as the whole collection.
            $Run.Output.Count | Should -Be 0
            $Run.ErrorIds | Should -Be @('InternalServerError')
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 2 -Exactly -Scope It
        }

        It 'a later page that gets no response leaves ArmTransportError as the only record, and returns nothing' {
            InModuleScope Omnicit.PIM { $script:_OPIMTestCalls = 0 }
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest {
                $Count = & (Get-Module Omnicit.PIM) { $script:_OPIMTestCalls++; $script:_OPIMTestCalls }
                if ($Count -eq 1) {
                    return [pscustomobject]@{
                        StatusCode = 200; Headers = @{}
                        Content    = '{"value":["a","b"],"nextLink":"https://management.azure.com/subscriptions?api-version=2022-12-01&$skiptoken=p2"}'
                    }
                }
                throw [System.Exception]::new('The response ended prematurely.')
            }
            $Run = Invoke-OutsideAnyTry -Script '$R = Invoke-OPIMArmRequest -Path ''/subscriptions?api-version=2022-12-01'' -All -ErrorAction SilentlyContinue; $R'
            $Run.Output.Count | Should -Be 0
            $Run.ErrorIds | Should -Be @('ArmTransportError')
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 2 -Exactly -Scope It
        }

        It 'a latched command sends nothing and returns nothing' {
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":["sent"]}' } }
            $Run = Invoke-OutsideAnyTry -Script @'
function Initialize-StandIn { $null = Lock-OPIMSignIn }
function Invoke-RefusedCommand {
    [CmdletBinding()]
    param()
    Initialize-StandIn
    Invoke-OPIMArmRequest -Path '/subscriptions?api-version=2022-12-01' -ErrorAction SilentlyContinue
}
$R = Invoke-RefusedCommand
$R
'@
            $Run.Output.Count | Should -Be 0
            $Run.ErrorIds | Should -Be @('SignInRefused')
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 0 -Scope It
        }

        It 'a token for another <What> sends nothing and returns nothing' -ForEach @(
            @{ Kind = 'TenantMismatch'; What = 'tenant'; TenantId = '33333333-3333-3333-3333-333333333333'; ObjectId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' }
            @{ Kind = 'AccountMismatch'; What = 'account'; TenantId = '22222222-2222-2222-2222-222222222222'; ObjectId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' }
        ) {
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":["sent"]}' } }
            Set-ArmTestToken -TenantId $TenantId -ObjectId $ObjectId
            $Run = Invoke-OutsideAnyTry -Script '$R = Invoke-OPIMArmRequest -Path ''/subscriptions?api-version=2022-12-01'' -ErrorAction SilentlyContinue; $R'
            $Run.Output.Count | Should -Be 0
            $Run.ErrorIds | Should -Be @($Kind)
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 0 -Scope It
        }

        It 'a refused refresh sends no retry and returns nothing' {
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 401; Content = '{}'; Headers = @{} } }
            InModuleScope Omnicit.PIM {
                # Lock-NamedFrame inline, in the module's scope: the refused refresh latches its caller.
                Mock Initialize-OPIMAuth {
                    $Frame = @(Get-PSCallStack | Where-Object { $null -ne $_.InvocationInfo -and $_.InvocationInfo.MyCommand.Name -eq 'Invoke-OPIMArmWithRefresh' })[0]
                    if ($null -eq $script:_OPIMSignInLatch) {
                        $script:_OPIMSignInLatch = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
                    }
                    $script:_OPIMSignInLatch.AddOrUpdate($Frame.InvocationInfo, $true)
                }
            }
            $Run = Invoke-OutsideAnyTry -Script '$R = Invoke-OPIMArmRequest -Path ''/subscriptions?api-version=2022-12-01'' -ErrorAction SilentlyContinue; $R'
            $Run.Output.Count | Should -Be 0
            $Run.ErrorIds | Should -Be @('SignInRefused')
            Should -Invoke -ModuleName Omnicit.PIM Initialize-OPIMAuth -Times 1 -Exactly -Scope It
            # One request, the rejected one: the retry after the refused refresh never goes out.
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 1 -Exactly -Scope It
        }

        It 'a session with <Name> sends no request and leaves ArmTokenAcquisitionFailed as the only record' -ForEach @(
            @{ Name = 'no ArmToken key'; Shape = 'NoKey' }
            @{ Name = 'an empty ArmToken'; Shape = 'Empty' }
            @{ Name = 'no auth state at all'; Shape = 'NoState' }
        ) {
            $State = switch ($Shape) {
                'NoKey' { $S = New-ArmTestState; $S.Remove('ArmToken'); $S }
                'Empty' { New-ArmTestState -ArmToken ([securestring]::new()) }
                'NoState' { $null }
            }
            Set-ArmTestState -State $State
            Mock -ModuleName Omnicit.PIM Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":["sent"]}' } }
            $Run = Invoke-OutsideAnyTry -Script '$R = Invoke-OPIMArmRequest -Path ''/subscriptions?api-version=2022-12-01'' -ErrorAction SilentlyContinue; $R'
            $Run.Output.Count | Should -Be 0
            $Run.ErrorIds | Should -Be @('ArmTokenAcquisitionFailed')
            Should -Invoke -ModuleName Omnicit.PIM Invoke-WebRequest -Times 0 -Scope It
        }
    }
}
