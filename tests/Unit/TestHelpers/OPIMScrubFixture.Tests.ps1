# Known-answer suite for the failed-request fixture helper (tests/Unit/TestHelpers/OPIMScrubFixture.ps1).
# It reads the objects the helper builds; it reaches no module code and no transport.

BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
    . "$PSScriptRoot/OPIMScrubFixture.ps1"
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'New-ScrubFixture' {
    Context 'When the request is built' {
        It 'carries an Authorization header whose value ends in NOT-A-REAL-TOKEN for the <Shape> token shape' -ForEach @(
            @{ Shape = 'Plain' }
            @{ Shape = 'Jwt' }
        ) {
            $Fixture = New-ScrubFixture -TokenShape $Shape
            $Fixture.Request.Headers.Contains('Authorization') | Should -BeTrue
            @($Fixture.Request.Headers.GetValues('Authorization'))[0] | Should -BeLike '*NOT-A-REAL-TOKEN'
        }

        It 'builds the Plain shape as Bearer, forty x characters and NOT-A-REAL-TOKEN, and uses it when no shape is given' {
            $Default = New-ScrubFixture
            $Plain = New-ScrubFixture -TokenShape Plain
            @($Default.Request.Headers.GetValues('Authorization'))[0] | Should -MatchExactly '^Bearer x{40}NOT-A-REAL-TOKEN$'
            @($Plain.Request.Headers.GetValues('Authorization'))[0] | Should -MatchExactly '^Bearer x{40}NOT-A-REAL-TOKEN$'
        }

        It 'builds the Jwt shape as Bearer, eyJ, twenty A characters, a dot and NOT-A-REAL-TOKEN' {
            $Fixture = New-ScrubFixture -TokenShape Jwt
            $Value = @($Fixture.Request.Headers.GetValues('Authorization'))[0]
            $Value | Should -BeLike 'Bearer eyJ*'
            $Value | Should -MatchExactly '^Bearer eyJA{20}\.NOT-A-REAL-TOKEN$'
        }

        It 'rejects a token shape that is neither Plain nor Jwt' {
            { New-ScrubFixture -TokenShape 'Opaque' } | Should -Throw
        }

        It 'uses https://graph.microsoft.com/v1.0/me as the request uri when -Uri is not given' {
            $Fixture = New-ScrubFixture
            $Fixture.Request.RequestUri.AbsoluteUri | Should -Be 'https://graph.microsoft.com/v1.0/me'
        }

        It 'uses -Uri as the request uri' {
            $Fixture = New-ScrubFixture -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilitySchedules'
            $Fixture.Request.RequestUri.AbsoluteUri | Should -Be 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilitySchedules'
        }

        It 'builds a new request on every call' {
            $First = New-ScrubFixture
            $Second = New-ScrubFixture
            [object]::ReferenceEquals($First.Request, $Second.Request) | Should -BeFalse
        }
    }

    Context 'When the response is built' {
        It 'points the response RequestMessage at the same request object' {
            $Fixture = New-ScrubFixture
            [object]::ReferenceEquals($Fixture.Exception.Response.RequestMessage, $Fixture.Request) | Should -BeTrue
        }

        It 'returns an HttpResponseException' {
            $Fixture = New-ScrubFixture
            $Fixture.Exception | Should -BeOfType ([Microsoft.PowerShell.Commands.HttpResponseException])
        }

        It 'gives the response the status 403 when -Status is not given' {
            $Fixture = New-ScrubFixture
            [int]$Fixture.Exception.Response.StatusCode | Should -Be 403
        }

        It 'gives the response the status of -Status' {
            $Fixture = New-ScrubFixture -Status 429
            [int]$Fixture.Exception.Response.StatusCode | Should -Be 429
        }

        It 'puts the Authorization_RequestDenied error body in the response when -Content is not given' {
            $Fixture = New-ScrubFixture
            $Body = $Fixture.Exception.Response.Content.ReadAsStringAsync().Result
            $Body | Should -Be '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges."}}'
        }

        It 'puts -Content in the response body' {
            $Fixture = New-ScrubFixture -Content '{"error":{"code":"TooManyRequests","message":"Too many requests."}}'
            $Body = $Fixture.Exception.Response.Content.ReadAsStringAsync().Result
            $Body | Should -Be '{"error":{"code":"TooManyRequests","message":"Too many requests."}}'
        }

        It 'adds no Retry-After header when -RetryAfter is not given' {
            $Fixture = New-ScrubFixture
            $Fixture.Exception.Response.Headers.Contains('Retry-After') | Should -BeFalse
        }

        It 'adds a Retry-After header with the value of -RetryAfter' {
            $Fixture = New-ScrubFixture -RetryAfter '7'
            $Fixture.Exception.Response.Headers.Contains('Retry-After') | Should -BeTrue
            @($Fixture.Exception.Response.Headers.GetValues('Retry-After'))[0] | Should -Be '7'
        }
    }

    Context 'When the record is built' {
        It 'builds the record with the id HttpFail and the category InvalidOperation' {
            $Fixture = New-ScrubFixture
            $Fixture.Record | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $Fixture.Record.FullyQualifiedErrorId | Should -Be 'HttpFail'
            $Fixture.Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
        }

        It 'makes the request the target of the record' {
            $Fixture = New-ScrubFixture
            [object]::ReferenceEquals($Fixture.Record.TargetObject, $Fixture.Request) | Should -BeTrue
        }

        It 'wraps the returned exception in the record' {
            $Fixture = New-ScrubFixture
            [object]::ReferenceEquals($Fixture.Record.Exception, $Fixture.Exception) | Should -BeTrue
        }
    }
}
