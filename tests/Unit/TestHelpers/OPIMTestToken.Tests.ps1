# Known-answer suite for the token fixture helper (tests/Unit/TestHelpers/OPIMTestToken.ps1).
# It decodes the payload the helper builds; it reaches no module code and no transport.

BeforeAll {
    Remove-Module Omnicit.PIM -Force -ErrorAction SilentlyContinue
    Import-Module Omnicit.PIM -Force
    . "$PSScriptRoot/OPIMTransportTripwire.ps1"
    Install-OPIMTransportTripwire
    . "$PSScriptRoot/OPIMTestToken.ps1"

    # The payload segment of a token, decoded the way a JWT reader decodes it.
    function Get-TestTokenPayload {
        param(
            [Parameter(Mandatory)]
            [string]$Token
        )
        $Segment = $Token.Split('.')[1].Replace('-', '+').Replace('_', '/')
        $Segment = $Segment.PadRight($Segment.Length + ((4 - ($Segment.Length % 4)) % 4), '=')
        [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Segment)) | ConvertFrom-Json
    }
}

AfterAll {
    try { Assert-OPIMTransportTripwire } finally { Uninstall-OPIMTransportTripwire }
}

Describe 'New-OPIMTestAccessToken' {
    It 'builds header.payload.signature with the NOT-A-REAL-TOKEN signature segment' {
        $Parts = (New-OPIMTestAccessToken).Split('.')
        $Parts.Count | Should -Be 3
        $Parts[2] | Should -BeExactly 'NOT-A-REAL-TOKEN'
    }

    It 'defaults the tid claim to the all-ones placeholder and the oid claim to the all-zeros placeholder' {
        $Payload = Get-TestTokenPayload -Token (New-OPIMTestAccessToken)
        $Payload.tid | Should -Be '11111111-1111-1111-1111-111111111111'
        $Payload.oid | Should -Be '00000000-0000-0000-0000-000000000000'
    }

    It 'writes -TenantId into the tid claim and the issuer' {
        $Payload = Get-TestTokenPayload -Token (New-OPIMTestAccessToken -TenantId '22222222-2222-2222-2222-222222222222')
        $Payload.tid | Should -Be '22222222-2222-2222-2222-222222222222'
        $Payload.iss | Should -Be 'https://sts.windows.net/22222222-2222-2222-2222-222222222222/'
    }

    It 'writes -ObjectId into the oid claim and leaves the tenant alone' {
        $Payload = Get-TestTokenPayload -Token (New-OPIMTestAccessToken -ObjectId '33333333-3333-3333-3333-333333333333')
        $Payload.oid | Should -Be '33333333-3333-3333-3333-333333333333'
        $Payload.tid | Should -Be '11111111-1111-1111-1111-111111111111'
    }

    It 'leaves the oid claim out with -NoObjectId and keeps the tid claim' {
        $Payload = Get-TestTokenPayload -Token (New-OPIMTestAccessToken -NoObjectId)
        $Payload.PSObject.Properties.Name | Should -Not -Contain 'oid'
        $Payload.tid | Should -Be '11111111-1111-1111-1111-111111111111'
    }

    It 'leaves the tid claim out with -NoTenant and keeps the oid claim' {
        $Payload = Get-TestTokenPayload -Token (New-OPIMTestAccessToken -NoTenant)
        $Payload.PSObject.Properties.Name | Should -Not -Contain 'tid'
        $Payload.oid | Should -Be '00000000-0000-0000-0000-000000000000'
    }

    It 'leaves both claims out with -NoTenant and -NoObjectId together' {
        $Payload = Get-TestTokenPayload -Token (New-OPIMTestAccessToken -NoTenant -NoObjectId)
        $Payload.PSObject.Properties.Name | Should -Not -Contain 'tid'
        $Payload.PSObject.Properties.Name | Should -Not -Contain 'oid'
        $Payload.upn | Should -Be 'user@contoso.com'
    }
}
