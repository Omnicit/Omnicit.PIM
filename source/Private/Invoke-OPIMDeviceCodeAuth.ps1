function Invoke-OPIMDeviceCodeAuth {
    <#
    .SYNOPSIS
    Acquires a Microsoft Graph token with the MSAL device code flow and writes the sign-in message
    to the Information stream.

    .DESCRIPTION
    Calls AcquireTokenWithDeviceCode on the MSAL public client application that
    Get-OPIMMsalApplication built. The MSAL types live in the Graph SDK's AssemblyLoadContext, so
    the method is found by name and parameter shape, as Initialize-OPIMAuth finds the others.

    MSAL hands the device code to a callback on a thread-pool thread, where a PowerShell script
    block has no runspace and fails. The callback is therefore compiled from an expression tree and
    only queues the result. This function drains the queue on its own thread and writes the message
    that carries the code and the sign-in address -- and nothing else of the result -- to the
    Information stream with the tag OPIMDeviceCode, shown to the user whatever the information
    preference is. A harness reads the tag from the stream with 6>&1.

    With a claims challenge, WithClaims is chained on the same device code builder, so an ACRS
    step-up in device code mode is a device code sign-in too. A failed flow, an expired code
    included, is the terminating error DeviceCodeAuthFailed. Stopping the command cancels the flow.

    .PARAMETER MsalApp
    The MSAL public client application returned by Get-OPIMMsalApplication.

    .PARAMETER Scopes
    The Microsoft Graph scopes to request: the fixed list that Initialize-OPIMAuth passes.

    .PARAMETER ClaimsChallenge
    The decoded JSON claims challenge of an ACRS step-up. When given, WithClaims is chained on the
    device code builder.

    .PARAMETER PollMilliseconds
    How long to wait between two looks at the queue and the flow, in milliseconds. Defaults to 250.

    .OUTPUTS
    The MSAL AuthenticationResult (opaque object via reflection).

    .EXAMPLE
    $AuthResult = Invoke-OPIMDeviceCodeAuth -MsalApp (Get-OPIMMsalApplication -TenantId $TenantId) -Scopes $GraphScopes

    Signs in with a device code and returns the MSAL result.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [object]$MsalApp,

        [Parameter(Mandatory)]
        [string[]]$Scopes,

        [string]$ClaimsChallenge,

        [ValidateRange(10, 5000)]
        [int]$PollMilliseconds = 250
    )

    # AcquireTokenWithDeviceCode(IEnumerable<string>, Func<DeviceCodeResult, Task>), found by name
    # and parameter shape: its parameter types come from the Graph SDK's AssemblyLoadContext.
    $DeviceCodeMethod = $MsalApp.GetType().GetMethods() |
        Where-Object {
            $_.Name -eq 'AcquireTokenWithDeviceCode' -and
            ($DeviceCodeParams = $_.GetParameters()) -and
            $DeviceCodeParams.Count -eq 2 -and
            $DeviceCodeParams[0].ParameterType.Name -eq 'IEnumerable`1' -and
            $DeviceCodeParams[1].ParameterType.Name -eq 'Func`2'
        } | Select-Object -First 1

    if (-not $DeviceCodeMethod) {
        Write-CmdletError `
            -Message ([System.Exception]::new(
                'Device code authentication failed: the MSAL application has no AcquireTokenWithDeviceCode method. ' +
                'Ensure Microsoft.Graph.Authentication >= 2.36.0 is installed.')) `
            -ErrorId 'DeviceCodeAuthFailed' `
            -Category NotInstalled `
            -Cmdlet $PSCmdlet `
            -Terminating
    }

    # MSAL calls the callback on a thread-pool thread, where a script block has no runspace and
    # fails. A delegate compiled from an expression tree runs on any thread: it only queues the
    # DeviceCodeResult, and this thread writes the message. The result type is read from the
    # method itself, so it is the type of the Graph SDK's load context.
    $CallbackType = $DeviceCodeMethod.GetParameters()[1].ParameterType
    $ResultType   = $CallbackType.GetGenericArguments()[0]
    $Queue        = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    $Expression   = [System.Linq.Expressions.Expression]
    $ResultParam  = $Expression::Parameter($ResultType, 'deviceCodeResult')
    $EnqueueCall  = $Expression::Call(
        $Expression::Constant($Queue),
        $Queue.GetType().GetMethod('Enqueue'),
        $Expression::Convert($ResultParam, [object]))
    $Completed    = $Expression::Property($null, [System.Threading.Tasks.Task].GetProperty('CompletedTask'))
    $Callback     = $Expression::Lambda(
        $CallbackType,
        $Expression::Block($EnqueueCall, $Completed),
        [System.Linq.Expressions.ParameterExpression[]]@($ResultParam)).Compile()

    # Writes each queued message. Only Message is written: the result also carries the device_code
    # itself, which polls for the token.
    $WriteQueuedMessages = {
        $Pending = $null
        while ($Queue.TryDequeue([ref]$Pending)) {
            Write-Information -MessageData ([string]$Pending.Message) -Tags 'OPIMDeviceCode' -InformationAction Continue
        }
    }

    $DeviceCodeArgs    = [object[]]::new(2)
    $DeviceCodeArgs[0] = $Scopes
    $DeviceCodeArgs[1] = $Callback
    $Builder = $DeviceCodeMethod.Invoke($MsalApp, $DeviceCodeArgs)

    # An ACRS step-up in device code mode chains the claims on the same builder.
    if ($ClaimsChallenge) {
        $WithClaimsMethod = $Builder.GetType().GetMethod('WithClaims', [Type[]]@([string]))
        if (-not $WithClaimsMethod) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    'MSAL WithClaims method not found. Cannot satisfy the ACRS claims challenge. ' +
                    'Ensure Microsoft.Graph.Authentication >= 2.36.0 is installed.')) `
                -ErrorId 'MsalWithClaimsNotFound' `
                -Category NotInstalled `
                -Cmdlet $PSCmdlet `
                -Terminating
        }
        $Builder = $WithClaimsMethod.Invoke($Builder, @($ClaimsChallenge))
        Write-Verbose '[Invoke-OPIMDeviceCodeAuth] ACRS claims challenge chained on the device code request.'
    }

    $AuthResult   = $null
    $FlowTask     = $null
    $Cancellation = [System.Threading.CancellationTokenSource]::new()
    try {
        try {
            $FlowTask = $Builder.ExecuteAsync($Cancellation.Token)
            while (-not $FlowTask.IsCompleted) {
                & $WriteQueuedMessages
                $null = [System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]@($FlowTask), $PollMilliseconds)
            }
            # The callback can queue the message just before the flow completes.
            & $WriteQueuedMessages
            $AuthResult = $FlowTask.GetAwaiter().GetResult()
        } catch {
            # Name the cause, not the reflection call that surfaced it.
            $Cause = $PSItem.Exception
            if ($Cause -is [System.Management.Automation.MethodInvocationException] -and $Cause.InnerException) {
                $Cause = $Cause.InnerException
            }
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Device code authentication failed: $($Cause.Message) " +
                    'A device code expires after about 15 minutes; run the command again for a new code.')) `
                -InnerException $Cause `
                -ErrorId 'DeviceCodeAuthFailed' `
                -Category AuthenticationError `
                -Cmdlet $PSCmdlet `
                -Terminating
        }
    } finally {
        # Stopping the command leaves the flow polling the token endpoint; cancel it.
        if ($FlowTask -and -not $FlowTask.IsCompleted) {
            $Cancellation.Cancel()
        }
        $Cancellation.Dispose()
    }

    return $AuthResult
}
