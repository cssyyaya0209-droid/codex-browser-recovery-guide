[CmdletBinding()]
param([switch]$CheckOnly)

$ErrorActionPreference = 'Stop'
$taskProxyAddress = 'http://127.0.0.1:56666'
$taskRecordedApp = 'C:\Program Files\WindowsApps\OpenAI.Codex_26.901.6511.0_x64__2p2nqsd0c76g0\app\ChatGPT.exe'
$taskNode = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node\<runtime-id>\bin\node.exe'
$taskStatusPath = Join-Path $PSScriptRoot 'proxy-launcher-status.json'
$taskWrapper = Join-Path $PSScriptRoot 'node-repl-proxy.exe'

function New-CodexProxyProcessInfo([string]$Executable) {
    $taskInfo = [Diagnostics.ProcessStartInfo]::new()
    $taskInfo.FileName = $Executable
    $taskInfo.UseShellExecute = $false
    $taskInfo.WorkingDirectory = $PSScriptRoot
    $taskAllowNames = @($taskInfo.Environment['NODE_REPL_UNTRUSTED_ENV_ALLOWLIST'] -split ',' |
        ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $taskAllowNames += @('BROWSER_USE_DISABLE_AMBIENT_NETWORK', 'HTTP_PROXY', 'HTTPS_PROXY')
    $taskInfo.Environment['BROWSER_USE_DISABLE_AMBIENT_NETWORK'] = '1'
    $taskInfo.Environment['NODE_REPL_UNTRUSTED_ENV_ALLOWLIST'] = ($taskAllowNames | Select-Object -Unique) -join ','
    $taskInfo.Environment['HTTP_PROXY'] = $taskProxyAddress
    $taskInfo.Environment['HTTPS_PROXY'] = $taskProxyAddress
    # Supported desktop runtime-path override; keeps generated MCP configuration aligned.
    $taskInfo.Environment['CODEX_NODE_REPL_PATH'] = $taskWrapper
    return $taskInfo
}

try {
    if (-not (Test-Path -LiteralPath $taskWrapper -PathType Leaf)) { throw 'The MCP proxy launcher is missing.' }
    $taskAppPath = $taskRecordedApp
    if (-not (Test-Path -LiteralPath $taskAppPath -PathType Leaf)) {
        $taskPackage = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
        if ($null -eq $taskPackage) { throw 'Codex installation was not found. Refresh this launcher after an app update.' }
        $taskAppPath = Join-Path $taskPackage.InstallLocation 'app\ChatGPT.exe'
        if (-not (Test-Path -LiteralPath $taskAppPath -PathType Leaf)) { throw 'Codex executable was not found.' }
    }

    $taskSocket = [Net.Sockets.TcpClient]::new()
    try {
        if (-not $taskSocket.ConnectAsync('127.0.0.1', 56666).Wait(3000)) {
            throw 'Local proxy port 56666 did not respond. Start the existing proxy application first.'
        }
    } finally { $taskSocket.Dispose() }

    if ($CheckOnly) {
        if (-not (Test-Path -LiteralPath $taskNode -PathType Leaf)) { throw 'The recorded Node runtime is missing.' }
        $taskProbeInfo = New-CodexProxyProcessInfo $taskNode
        $taskProbeInfo.CreateNoWindow = $true
        $taskProbeInfo.RedirectStandardOutput = $true
        $taskProbeInfo.RedirectStandardError = $true
        $taskProbeInfo.ArgumentList.Add('-e')
        $taskProbeInfo.ArgumentList.Add('const keys=["BROWSER_USE_DISABLE_AMBIENT_NETWORK","NODE_REPL_UNTRUSTED_ENV_ALLOWLIST","HTTP_PROXY","HTTPS_PROXY","CODEX_NODE_REPL_PATH"]; console.log(JSON.stringify(Object.fromEntries(keys.map(k=>[k,process.env[k]??null]))));')
        $taskProbe = [Diagnostics.Process]::Start($taskProbeInfo)
        $taskProbeOutput = $taskProbe.StandardOutput.ReadToEnd()
        $taskProbe.WaitForExit()
        if ($taskProbe.ExitCode -ne 0) { throw 'Environment probe failed.' }
        $taskObserved = $taskProbeOutput | ConvertFrom-Json
        if ($taskObserved.BROWSER_USE_DISABLE_AMBIENT_NETWORK -ne '1' -or
            $taskObserved.HTTP_PROXY -ne $taskProxyAddress -or
            $taskObserved.HTTPS_PROXY -ne $taskProxyAddress -or
            $taskObserved.CODEX_NODE_REPL_PATH -ne $taskWrapper) { throw 'Child environment did not match the requested values.' }
        foreach ($taskKey in @('BROWSER_USE_DISABLE_AMBIENT_NETWORK', 'HTTP_PROXY', 'HTTPS_PROXY')) {
            if ($taskKey -notin ($taskObserved.NODE_REPL_UNTRUSTED_ENV_ALLOWLIST -split ',')) {
                throw 'Child environment allowlist is incomplete.'
            }
        }
        [ordered]@{
            time = (Get-Date).ToString('o'); mode = 'check-only'; app = $taskAppPath
            proxyPortReachable = $true; childEnvironment = $taskObserved
            browserRuntimeVerified = $false
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'proxy-launcher-precheck.json') -Encoding utf8
        Write-Output 'PASS: app and MCP launcher exist, proxy port is reachable, and a child receives the proxy variables and runtime-path override. No Codex process was started or stopped.'
        return
    }

    $taskExisting = @(Get-Process -Name ChatGPT -ErrorAction SilentlyContinue | Where-Object {
        (-not $_.Path) -or ($_.Path -like '*\OpenAI.Codex_*\app\ChatGPT.exe')
    })
    if ($taskExisting.Count -gt 0) {
        throw 'Codex is still running. Fully exit it, then open this shortcut again. This launcher will not stop your tasks.'
    }
    $taskLaunchInfo = New-CodexProxyProcessInfo $taskAppPath
    $taskChild = [Diagnostics.Process]::Start($taskLaunchInfo)
    [ordered]@{
        time = (Get-Date).ToString('o'); mode = 'launch'; app = $taskAppPath
        processId = $taskChild.Id; proxy = $taskProxyAddress; mcpWrapper = $taskWrapper
        browserRuntimeVerified = $false
    } | ConvertTo-Json | Set-Content -LiteralPath $taskStatusPath -Encoding utf8
} catch {
    $taskErrorText = $_.Exception.Message
    if (-not $CheckOnly) {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($taskErrorText, 'Codex browser proxy launcher')
    }
    throw
}
