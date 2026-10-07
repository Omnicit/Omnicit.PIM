BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/../TestHelpers/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire

    # A failed Graph read as the SDK leaves it: a request message carrying an Authorization header,
    # the response pointing back at it, and an HttpResponseException holding the response. The
    # token is built at runtime and says what it is, so no token-shaped literal sits in this file.
    function New-ScrubFixture {
        param([int]$Status = 403)
        $Token = 'Bearer ' + ('x' * 40) + 'NOT-A-REAL-TOKEN'
        $Request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, 'https://graph.microsoft.com/v1.0/me')
        $null = $Request.Headers.TryAddWithoutValidation('Authorization', $Token)
        $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Status)
        $Response.RequestMessage = $Request
        $Response.Content = [System.Net.Http.StringContent]::new('{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges."}}')
        $Exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Response status code does not indicate success.', $Response)
        [pscustomobject]@{
            Request   = $Request
            Exception = $Exception
            Record    = [System.Management.Automation.ErrorRecord]::new($Exception, 'HttpFail', 'InvalidOperation', $Request)
        }
    }
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'Remove-OPIMErrorRecord' {
    Context "When the record's target is the request message" {
        BeforeAll {
            $F = New-ScrubFixture
        }

        It 'removes the Authorization header from the request message' {
            $F.Request.Headers.Contains('Authorization') | Should -BeTrue -Because 'the fixture must carry the header, or the scrub below proves nothing'
            InModuleScope Omnicit.PIM -ArgumentList $F.Record {
                param($Record)
                Remove-OPIMErrorRecord -Record $Record
            }
            $F.Request.Headers.Contains('Authorization') | Should -BeFalse
        }
    }

    Context "When the request is reachable only through the exception's response" {
        BeforeAll {
            $F = New-ScrubFixture
            $Record = [System.Management.Automation.ErrorRecord]::new($F.Exception, 'HttpFail', 'InvalidOperation', $null)
        }

        It 'removes the Authorization header reached through Exception.Response.RequestMessage' {
            $Record.TargetObject | Should -BeNullOrEmpty -Because 'the request must be reachable only through the exception'
            $F.Request.Headers.Contains('Authorization') | Should -BeTrue
            InModuleScope Omnicit.PIM -ArgumentList $Record {
                param($Record)
                Remove-OPIMErrorRecord -Record $Record
            }
            $F.Request.Headers.Contains('Authorization') | Should -BeFalse
        }
    }

    Context "When the request sits behind an AggregateException's second inner exception" {
        BeforeAll {
            $F = New-ScrubFixture
            $Aggregate = [System.AggregateException]::new([System.Exception]::new('first'), $F.Exception)
            $Record = [System.Management.Automation.ErrorRecord]::new($Aggregate, 'HttpFail', 'InvalidOperation', $null)
        }

        It 'removes the header reached through InnerExceptions' {
            [object]::ReferenceEquals($Aggregate.InnerException, $F.Exception) | Should -BeFalse -Because 'the transport failure must sit at index 1, out of reach of .InnerException'
            $F.Request.Headers.Contains('Authorization') | Should -BeTrue
            InModuleScope Omnicit.PIM -ArgumentList $Record {
                param($Record)
                Remove-OPIMErrorRecord -Record $Record
            }
            $F.Request.Headers.Contains('Authorization') | Should -BeFalse
        }
    }

    Context "When the record is in the caller's error list" {
        BeforeEach {
            $F = New-ScrubFixture
            # A different record over the SAME exception: what the engine stores in $global:Error
            # is not the instance a catch block binds to $PSItem, but the exception is shared.
            $Stored = [System.Management.Automation.ErrorRecord]::new($F.Exception, 'HttpFail', 'InvalidOperation', $F.Request)
            $Unrelated = [System.Management.Automation.ErrorRecord]::new(
                [Microsoft.PowerShell.Commands.HttpResponseException]::new($F.Exception.Message, [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Forbidden)),
                'HttpFail', 'InvalidOperation', $null)
            # The unrelated record sits FIRST, so a match on message text would remove it instead.
            $global:Error.Insert(0, $Stored)
            $global:Error.Insert(0, $Unrelated)
        }

        AfterEach {
            foreach ($Entry in @($Stored, $Unrelated)) {
                for ($Index = $global:Error.Count - 1; $Index -ge 0; $Index--) {
                    if ([object]::ReferenceEquals($global:Error[$Index], $Entry)) { $global:Error.RemoveAt($Index) }
                }
            }
        }

        It 'removes the entry whose Exception is the same object' {
            [object]::ReferenceEquals($Stored, $F.Record) | Should -BeFalse -Because 'the stored entry must be a different record instance, or this is a reference-equality test'
            InModuleScope Omnicit.PIM -ArgumentList $F.Record {
                param($Record)
                Remove-OPIMErrorRecord -Record $Record
            }
            @($global:Error | Where-Object { [object]::ReferenceEquals($_, $Stored) }).Count | Should -Be 0
        }

        It 'leaves an unrelated record with the same message in place' {
            $Unrelated.Exception.Message | Should -Be $F.Exception.Message -Because 'the unrelated record must share the message text, or this proves nothing about message equality'
            InModuleScope Omnicit.PIM -ArgumentList $F.Record {
                param($Record)
                Remove-OPIMErrorRecord -Record $Record
            }
            @($global:Error | Where-Object { [object]::ReferenceEquals($_, $Unrelated) }).Count | Should -Be 1
        }
    }

    Context 'When the record is null' {
        It 'returns without output' {
            InModuleScope Omnicit.PIM {
                @(Remove-OPIMErrorRecord -Record $null).Count | Should -Be 0
            }
        }
    }

    Context 'When a property read throws' {
        BeforeEach {
            # Two shapes. A Response ScriptProperty whose getter throws, as the TargetObject: on
            # PowerShell 7.6 member access swallows a getter's exception and reads $null, so that
            # shape alone never reaches a guard. And an exception whose InnerExceptions member
            # throws when the walk enumerates it, which is a throw the walk really meets; the
            # request on the exception's response must still be scrubbed after it.
            $F = New-ScrubFixture
            $Target = [pscustomobject]@{ Name = 'shape that throws' }
            $Target | Add-Member -MemberType ScriptProperty -Name Response -Value { throw [System.InvalidOperationException]::new('property read failed') }
            $Throwing = [System.Linq.Enumerable]::Select([object[]]@(1), [Func[object, object]] { param($Item) throw [System.InvalidOperationException]::new('enumeration failed') })
            $F.Exception | Add-Member -NotePropertyName InnerExceptions -NotePropertyValue $Throwing
            $Record = [System.Management.Automation.ErrorRecord]::new($F.Exception, 'HttpFail', 'InvalidOperation', $Target)
        }

        It 'does not throw' {
            { foreach ($Item in @($F.Exception.PSObject.Properties['InnerExceptions'].Value)) { $Item } } |
                Should -Throw -ExpectedMessage 'enumeration failed' -Because 'the fixture member must throw when enumerated, or the guard is never exercised'
            InModuleScope Omnicit.PIM -ArgumentList $Record {
                param($Record)
                { Remove-OPIMErrorRecord -Record $Record } | Should -Not -Throw
                @(Remove-OPIMErrorRecord -Record $Record).Count | Should -Be 0
            }
        }

        It 'clears the header the walk reaches after the throw' {
            $F.Request.Headers.Contains('Authorization') | Should -BeTrue
            InModuleScope Omnicit.PIM -ArgumentList $Record {
                param($Record)
                Remove-OPIMErrorRecord -Record $Record
            }
            $F.Request.Headers.Contains('Authorization') | Should -BeFalse -Because 'a throw on one member must not end the walk before the request is scrubbed'
        }
    }
}
