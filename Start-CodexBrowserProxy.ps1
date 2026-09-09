#Requires -Version 7.0
[CmdletBinding()]
param([switch]$CheckOnly, [string]$AppPath, [string]$NodePath)

$ErrorActionPreference = 'Stop'
$taskWrapper = Join-Path $PSScriptRoot 'node-repl-proxy.exe'
$taskConfig = Join-Path $PSScriptRoot 'proxy.txt'
$taskLogDir = Join-Path $PSScriptRoot 'logs'

function Read-ProxyAddress {
    if (-not (Test-Path -LiteralPath $taskConfig -PathType Leaf)) { throw 'Copy proxy.example.txt to proxy.txt and enter your local HTTP proxy URL.' }
    $taskValue = [IO.File]::ReadAllText($taskConfig).Trim()
    $taskUri = $null
    if ([string]::IsNullOrWhiteSpace($taskValue) -or $taskValue -match '[\r\n \t]' -or
        -not [Uri]::TryCreate($taskValue, [UriKind]::Absolute, [ref]$taskUri) -or
        $taskUri.Scheme -ne 'http' -or -not $taskUri.IsLoopback -or $taskUri.UserInfo -or
        $taskUri.AbsolutePath -ne '/' -or $taskUri.Query -or $taskUri.Fragment -or $taskUri.Port -lt 1) {
        throw 'proxy.txt must contain one local HTTP proxy URL with a valid port, without credentials or a path.'
    }
    return $taskValue
}

function Resolve-App {
    if ($AppPath) { $taskCandidate = $AppPath }
    else {
        $taskPackage = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
        if ($null -eq $taskPackage) { throw 'Codex was not found. Pass -AppPath with its actual executable path.' }
        $taskCandidate = Join-Path $taskPackage.InstallLocation 'app\ChatGPT.exe'
    }
    if (-not (Test-Path -LiteralPath $taskCandidate -PathType Leaf)) { throw 'Codex executable was not found. Check -AppPath.' }
    return (Resolve-Path -LiteralPath $taskCandidate).Path
}

function Resolve-ProbeNode {
    if ($NodePath) { $taskCandidates = @($NodePath) }
    else {
        $taskRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node'
        $taskCandidates = @(Get-ChildItem -LiteralPath $taskRoot -Filter node.exe -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.DirectoryName 'node_repl.exe') -PathType Leaf } |
            Select-Object -ExpandProperty FullName)
        if ($taskCandidates.Count -ne 1) { throw 'Cannot uniquely select the bundled Node runtime. Pass -NodePath from the current NODE_REPL_NODE_PATH setting.' }
    }
    if (-not (Test-Path -LiteralPath $taskCandidates[0] -PathType Leaf)) { throw 'Node executable was not found.' }
    return (Resolve-Path -LiteralPath $taskCandidates[0]).Path
}

function New-ProxyProcessInfo([string]$Executable) {
    $taskInfo = [Diagnostics.ProcessStartInfo]::new()
    $taskInfo.FileName = $Executable
    $taskInfo.UseShellExecute = $false
    $taskInfo.WorkingDirectory = $PSScriptRoot
    $taskNames = @($taskInfo.Environment['NODE_REPL_UNTRUSTED_ENV_ALLOWLIST'] -split ',' |
        ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $taskNames += @('BROWSER_USE_DISABLE_AMBIENT_NETWORK', 'HTTP_PROXY', 'HTTPS_PROXY')
    $taskInfo.Environment['BROWSER_USE_DISABLE_AMBIENT_NETWORK'] = '1'
    $taskInfo.Environment['NODE_REPL_UNTRUSTED_ENV_ALLOWLIST'] = ($taskNames | Select-Object -Unique) -join ','
    $taskInfo.Environment['HTTP_PROXY'] = $taskProxyAddress
    $taskInfo.Environment['HTTPS_PROXY'] = $taskProxyAddress
    # Runtime override observed in the validated desktop version; recheck after updates.
    $taskInfo.Environment['CODEX_NODE_REPL_PATH'] = $taskWrapper
    return $taskInfo
}

function Write-LocalStatus([string]$Name, $Value) {
    try {
        New-Item -ItemType Directory -Path $taskLogDir -Force | Out-Null
        $Value | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskLogDir $Name) -Encoding utf8
    } catch { Write-Warning 'Local diagnostic log could not be written.' }
}

try {
    $taskProxyAddress = Read-ProxyAddress
    if (-not (Test-Path -LiteralPath $taskWrapper -PathType Leaf)) { throw 'Build the wrapper with Build.ps1 first.' }
    $taskWrapperValue = & $taskWrapper --check-config
    if ($LASTEXITCODE -ne 0 -or $taskWrapperValue -cne $taskProxyAddress) { throw 'Launcher and wrapper configuration do not match.' }
    $taskApp = Resolve-App
    $taskProxyUri = [Uri]$taskProxyAddress
    $taskSocket = [Net.Sockets.TcpClient]::new()
    try {
        $taskConnect = $taskSocket.ConnectAsync($taskProxyUri.DnsSafeHost, $taskProxyUri.Port)
        if (-not $taskConnect.Wait(3000)) { throw 'The local proxy port did not respond. Check proxy.txt and start your proxy application.' }
        $taskConnect.GetAwaiter().GetResult()
    } finally { $taskSocket.Dispose() }

    if ($CheckOnly) {
        $taskProbeInfo = New-ProxyProcessInfo (Resolve-ProbeNode)
        $taskProbeInfo.CreateNoWindow = $true
        $taskProbeInfo.RedirectStandardOutput = $true
        $taskProbeInfo.RedirectStandardError = $true
        $taskProbeInfo.ArgumentList.Add('-e')
        $taskProbeInfo.ArgumentList.Add('const keys=["BROWSER_USE_DISABLE_AMBIENT_NETWORK","NODE_REPL_UNTRUSTED_ENV_ALLOWLIST","HTTP_PROXY","HTTPS_PROXY","CODEX_NODE_REPL_PATH"];console.log(JSON.stringify(Object.fromEntries(keys.map(k=>[k,process.env[k]??null]))));')
        $taskProbe = [Diagnostics.Process]::Start($taskProbeInfo)
        try {
            $taskOutput = $taskProbe.StandardOutput.ReadToEndAsync()
            $taskError = $taskProbe.StandardError.ReadToEndAsync()
            if (-not $taskProbe.WaitForExit(15000)) { $taskProbe.Kill($true); throw 'Environment probe timed out.' }
            if ($taskProbe.ExitCode -ne 0) { throw 'Environment probe failed.' }
            $taskObserved = $taskOutput.GetAwaiter().GetResult() | ConvertFrom-Json
            if ($taskObserved.HTTP_PROXY -cne $taskProxyAddress -or $taskObserved.HTTPS_PROXY -cne $taskProxyAddress -or
                $taskObserved.BROWSER_USE_DISABLE_AMBIENT_NETWORK -ne '1' -or $taskObserved.CODEX_NODE_REPL_PATH -cne $taskWrapper) {
                throw 'Child environment did not match the configuration.'
            }
            foreach ($taskName in @('BROWSER_USE_DISABLE_AMBIENT_NETWORK', 'HTTP_PROXY', 'HTTPS_PROXY')) {
                if ($taskName -notin ($taskObserved.NODE_REPL_UNTRUSTED_ENV_ALLOWLIST -split ',')) { throw 'Child environment allowlist is incomplete.' }
            }
        } finally { $taskProbe.Dispose() }
        Write-LocalStatus 'precheck.json' ([ordered]@{time=(Get-Date).ToString('o');configAgreement=$true;proxyPortReachable=$true;childEnvironmentVerified=$true;browserVerified=$false})
        Write-Output 'PASS: shared config, proxy port, and child environment verified. No Codex process was started or stopped.'
        return
    }

    $taskProcessName = [IO.Path]::GetFileNameWithoutExtension($taskApp)
    $taskExisting = @(Get-Process -Name $taskProcessName -ErrorAction SilentlyContinue | Where-Object {
        (-not $_.Path) -or ($_.Path -eq $taskApp) -or ($_.Path -like '*\OpenAI.Codex_*\app\ChatGPT.exe')
    })
    if ($taskExisting.Count -gt 0) { throw 'Codex is still running. Save your work and fully exit it before using this launcher.' }
    $taskChild = [Diagnostics.Process]::Start((New-ProxyProcessInfo $taskApp))
    Write-LocalStatus 'launch.json' ([ordered]@{time=(Get-Date).ToString('o');processId=$taskChild.Id;configAgreement=$true;browserVerified=$false})
} catch {
    if (-not $CheckOnly) {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Codex browser proxy launcher')
    }
    throw
}
