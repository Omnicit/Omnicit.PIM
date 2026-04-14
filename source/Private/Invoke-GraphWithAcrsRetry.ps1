function Invoke-GraphWithAcrsRetry {
    <#
    .SYNOPSIS
    Sends a Graph POST request and retries with a claims-challenge token when ACRS validation fails.

    .DESCRIPTION
    Wraps Invoke-MgGraphRequest for PIM activation POST requests. When the Graph API returns
    RoleAssignmentRequestAcrsValidationFailed (Conditional Access authentication context), this
    function extracts the claims challenge from the error, acquires a new token via MSAL
    AcquireTokenInteractive with WithClaims, and retries the request using Invoke-RestMethod.

    MSAL types are loaded in a separate Assembly Load Context by the Graph SDK, so all MSAL
    calls are made through reflection. The first ACRS retry in a session opens a browser for
    interactive authentication to satisfy the Conditional Access policy.

    .PARAMETER Uri
    The Graph API endpoint URI (e.g. 'v1.0/identityGovernance/privilegedAccess/group/assignmentScheduleRequests').

    .PARAMETER Body
    The request body hashtable to send as JSON.

    .PARAMETER ErrorRecord
    When provided, the original ErrorRecord from a failed Invoke-MgGraphRequest call. The function
    inspects this for the ACRS claims challenge. If it contains an ACRS error, the retry flow runs.
    If this parameter is omitted, the function makes the initial call itself.

    .EXAMPLE
    Invoke-GraphWithAcrsRetry -Uri 'v1.0/roleManagement/directory/roleAssignmentScheduleRequests' -Body $Request

    Sends a POST request to the Graph PIM endpoint. If the call fails with an ACRS claims challenge,
    the function automatically acquires a new token via interactive authentication and retries.

    .OUTPUTS
    The Graph API response hashtable on success, or $null if the retry also fails (error written
    to the caller's $PSCmdlet).
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [hashtable]$Body,

        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    # If no pre-existing error, make the initial call.
    if (-not $ErrorRecord) {
        try {
            return Invoke-MgGraphRequest -Method POST -Uri $Uri -Body $Body -Verbose:$false -ErrorAction Stop
        } catch {
            # Remove the raw error record immediately; its TargetObject (HttpRequestMessage)
            # contains the Authorization header with the bearer token in plain text.
            $null = $Error.Remove($PSItem)
            $ErrorRecord = $PSItem
        }
    }

    # Parse the Graph error to see if it's an ACRS claims challenge.
    $Err = Convert-GraphHttpException $ErrorRecord
    $AllMsgs = "$($Err.FullyQualifiedErrorId) $($Err.Exception.Message) $($ErrorRecord.Exception.Message)"

    if ($AllMsgs -notmatch 'RoleAssignmentRequestAcrsValidationFailed') {
        # Not an ACRS error — return the converted error for the caller to handle.
        return @{ _AcrsError = $false; _ErrorRecord = $Err; _AllMsgs = $AllMsgs }
    }

    # --- ACRS claims challenge detected — attempt retry with MSAL ---
    Write-Verbose 'ACRS claims challenge detected. Acquiring a new token with claims via interactive authentication...'

    # Extract the claims JSON from the error message.
    $ClaimsJson = $null
    $RawMsg = $Err.Exception.Message
    if (-not $RawMsg) { $RawMsg = $ErrorRecord.Exception.Message }

    if ($RawMsg -match '[&?]claims=([^&\s]+)') {
        $ClaimsJson = [System.Web.HttpUtility]::UrlDecode($Matches[1])
    } elseif ($RawMsg -match '\{.*"acrs".*\}') {
        $ClaimsJson = $Matches[0]
    }

    if (-not $ClaimsJson) {
        # Cannot extract claims — return the original error.
        return @{ _AcrsError = $true; _ErrorRecord = $Err; _AllMsgs = $AllMsgs; _NoClaimsExtracted = $true }
    }

    # Locate the MSAL assembly loaded by the Graph SDK (lives in a separate ALC).
    $MsalAssembly = [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.FullName -like 'Microsoft.Identity.Client, Version=4*' } |
        Select-Object -First 1

    if (-not $MsalAssembly) {
        return @{ _AcrsError = $true; _ErrorRecord = $Err; _AllMsgs = $AllMsgs; _NoMsal = $true }
    }

    # Build a PublicClientApplication via reflection (types are in a different ALC).
    $Ctx = Get-MgContext
    $BuilderType = $MsalAssembly.GetType('Microsoft.Identity.Client.PublicClientApplicationBuilder')
    $AbstractType = $BuilderType.BaseType

    $Builder = $BuilderType.GetMethod('Create', [Type[]]@([string])).Invoke($null, @($Ctx.ClientId))
    $Builder = $AbstractType.GetMethod('WithAuthority', [Type[]]@([string], [bool])).Invoke(
        $Builder, @("https://login.microsoftonline.com/$($Ctx.TenantId)", $true))
    $Builder = $AbstractType.GetMethod('WithRedirectUri', [Type[]]@([string])).Invoke(
        $Builder, @('http://localhost'))
    $MsalApp = $BuilderType.GetMethod('Build').Invoke($Builder, @())

    if (-not $MsalApp) {
        return @{ _AcrsError = $true; _ErrorRecord = $Err; _AllMsgs = $AllMsgs; _MsalBuildFailed = $true }
    }

    # AcquireTokenInteractive with claims — opens browser for step-up authentication.
    $GraphScopes = [string[]]@('https://graph.microsoft.com/.default')
    $AcquireMethod = $MsalApp.GetType().GetMethod(
        'AcquireTokenInteractive',
        [Type[]]@([System.Collections.Generic.IEnumerable[string]]))
    $TokenBuilder = $AcquireMethod.Invoke($MsalApp, @(, $GraphScopes))

    $WithClaimsMethod = $TokenBuilder.GetType().GetMethod('WithClaims', [Type[]]@([string]))
    if (-not $WithClaimsMethod) {
        return @{ _AcrsError = $true; _ErrorRecord = $Err; _AllMsgs = $AllMsgs; _NoWithClaims = $true }
    }

    $TokenBuilder = $WithClaimsMethod.Invoke($TokenBuilder, @($ClaimsJson))

    $AuthResult = try {
        $TokenBuilder.ExecuteAsync().GetAwaiter().GetResult()
    } catch {
        $null
    }

    if (-not $AuthResult -or -not $AuthResult.AccessToken) {
        return @{ _AcrsError = $true; _ErrorRecord = $Err; _AllMsgs = $AllMsgs; _TokenFailed = $true }
    }

    Write-Verbose 'Token acquired with claims challenge. Retrying the PIM activation request...'

    # Retry the POST with the new token using Invoke-RestMethod (bypasses Graph SDK auth).
    $FullUri = if ($Uri -match '^https://') { $Uri } else { "https://graph.microsoft.com/$Uri" }
    $Headers = @{ Authorization = "Bearer $($AuthResult.AccessToken)" }
    $JsonBody = $Body | ConvertTo-Json -Depth 10 -Compress

    try {
        $RetryResponse = Invoke-RestMethod -Method POST -Uri $FullUri -Headers $Headers -Body $JsonBody -ContentType 'application/json' -ErrorAction Stop
        # Convert PSCustomObject to hashtable for compatibility with Invoke-MgGraphRequest callers
        # (downstream code uses index notation like $Response['group'] = ...).
        $Ht = @{}
        $RetryResponse.PSObject.Properties | ForEach-Object { $Ht[$_.Name] = $_.Value }
        return $Ht
    } catch {
        # Retry also failed — surface the retry error as a normal (non-ACRS) error.
        $RetryErr = Convert-GraphHttpException $PSItem
        return @{ _AcrsError = $false; _ErrorRecord = $RetryErr; _AllMsgs = "$($RetryErr.FullyQualifiedErrorId) $($RetryErr.Exception.Message)" }
    }
}
