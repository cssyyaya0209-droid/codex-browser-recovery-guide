#Requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$taskCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $taskCompiler -PathType Leaf)) { throw 'The .NET Framework x64 C# compiler was not found.' }
$taskOutput = Join-Path $PSScriptRoot 'node-repl-proxy.exe'
& $taskCompiler /nologo /target:exe /platform:x64 /optimize+ "/out:$taskOutput" (Join-Path $PSScriptRoot 'src\NodeReplProxyLauncher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Build failed. Do not replace a running MCP executable.' }
Write-Output 'PASS: wrapper compiled. Configure proxy.txt, then run Start-CodexBrowserProxy.ps1 -CheckOnly.'
