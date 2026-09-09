# Codex 内置浏览器延迟治理参考

Windows 通用参考包 · v2.0

适用于这样的情况：页面已经显示，但 Codex 的读取、点击或截图反复等待几十秒。此方案针对已观察到的 MCP 代理环境传递问题；网页打不开、登录失效或安装损坏需要另行排查。

**代理地址只配置一次。** 启动脚本和包装程序共同读取 `proxy.txt`，换端口无需改源码或重新编译。包中不包含任何使用者的实际代理配置。

## 使用条件

- Windows x64、PowerShell 7，以及已安装的 Codex 桌面应用。
- 本机已有可用的 HTTP 代理或支持 HTTP 的混合代理端口。
- 当前 Codex 版本仍支持本文所用的运行时入口。已验证版本及限制见 [技术说明](docs/TECHNICAL-NOTES.md)。

## 快速开始

### 1. 解压到固定目录

从仓库下载 `Codex-浏览器治理参考包.zip`，完整解压到当前用户可读写的固定目录。在该目录打开 **PowerShell 7**。不要在压缩包内部运行。

### 2. 填写自己的代理地址

```powershell
if (-not (Test-Path -LiteralPath .\proxy.txt)) {
    Copy-Item -LiteralPath .\proxy.example.txt -Destination .\proxy.txt
}
notepad.exe .\proxy.txt
```

文件只保留一行：

```text
http://127.0.0.1:PORT
```

将 `PORT` 替换为代理软件设置中的实际 **HTTP/混合端口**。模板中的 `PORT` 必须修改。当前版本仅支持不带账号密码的本地 HTTP 代理；SOCKS 专用端口不能直接填入。

`127.0.0.1` 是通用的本机回环地址。`HTTPS_PROXY` 同样使用这条 HTTP 代理地址，由代理为 HTTPS 网站建立连接。

### 3. 执行预检查

参考包已附编译程序，通常直接执行：

```powershell
.\Start-CodexBrowserProxy.ps1 -CheckOnly
```

看到 `PASS` 表示：双方配置一致、代理端口可达、测试子进程收到所需环境。**这还不代表真实浏览器已修复。** 代理软件本身也应能正常代理 HTTPS 网站。

脚本尝试自动定位 Codex 和自带 Node。若安装位置不同或存在多个运行时，按 [路径选择与其他问题](docs/TROUBLESHOOTING.md) 指定本机真实路径。

如果需要从源码构建，先执行 `.\Build.ps1`，再预检查。更换代理地址不需要构建。

### 4. 创建快捷方式并启动

在同一 PowerShell 7 窗口执行以下命令。若已有同名快捷方式，先检查它的目标，不直接覆盖。

```powershell
$taskDir = (Get-Location).Path
$taskLinkPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex 浏览器代理.lnk'
if (Test-Path -LiteralPath $taskLinkPath) { throw '同名快捷方式已存在，请先检查。' }
$taskShell = New-Object -ComObject WScript.Shell
$taskLink = $taskShell.CreateShortcut($taskLinkPath)
$taskLink.TargetPath = Join-Path $PSHOME 'pwsh.exe'
$taskLink.Arguments = '-NoProfile -WindowStyle Hidden -File "' + (Join-Path $taskDir 'Start-CodexBrowserProxy.ps1') + '"'
$taskLink.WorkingDirectory = $taskDir
$taskLink.Save()
```

保存任务，完全退出 Codex，保持代理软件运行，再使用“Codex 浏览器代理”快捷方式启动。脚本发现旧 Codex 仍运行时会提示退出，不会强制终止任务。原来的 Codex 快捷方式保留用于回滚。

### 5. 验证效果

让 Codex 使用当前任务的内置浏览器执行：

1. 打开一个可访问的网页，确认正文完成加载。
2. 同一标签页连续读取三次页面内容，记录耗时。
3. 截图一次，核对图像与正文一致。
4. 打开一个菜单、读取变化，再关闭并核对恢复。
5. 如果此前标签页绑定会超时，再复测该入口。

内容正确、操作成功且原先固定等待不再出现，才算该电脑通过。不要把一次成功或其他电脑的测试结果当作本机验收。

## 后续使用与回滚

- 继续用专用快捷方式启动，保留解压目录和本地配置。
- 更换端口：只改 `proxy.txt`，重新预检查，然后完全退出并重启 Codex。
- Codex 升级后重新验收；运行时入口变化时可能需要适配。
- 停用方案：保存任务并退出 Codex，从原来的快捷方式启动。确认包装程序不再使用后，可移除专用快捷方式和参考包目录。
- 从旧参考包升级：解压新版到新目录、填写配置并预检查，再更新专用快捷方式指向新版；不要覆盖正在运行的 EXE。详见 [故障排查](docs/TROUBLESHOOTING.md)。

## 文件说明

| 文件 | 用途 |
| --- | --- |
| proxy.example.txt | 可分享的配置模板；复制为本地 proxy.txt 后填写 |
| Start-CodexBrowserProxy.ps1 | 启动与预检查 |
| node-repl-proxy.exe | 读取同一配置的 MCP 包装程序 |
| src/NodeReplProxyLauncher.cs | 包装程序源码 |
| Build.ps1 | 可选的源码构建入口 |
| docs/ | 技术依据、故障排查和版本验证说明 |
| SHA256SUMS.txt | 可选的下载完整性校验 |

`proxy.txt` 和 `logs/` 是本地文件，已加入 `.gitignore`，发布 ZIP 不包含它们。分享时使用仓库提供的参考包，不把配置完成后的整个目录重新压缩上传。

## 交给 Codex 的提示词

> 请根据此参考包处理本机内置浏览器的固定延迟。先记录三次页面读取和一次截图的基线，核对代理协议、当前安装和运行时入口是否适用。使用本机参数配置 proxy.txt，完成预检查后再安排一次完整退出重启。重启后核对入口并验证读取、截图、可恢复点击及原先失败的绑定入口，给出前后对照。不修改全局网络、安装包或安全策略，不输出或上传我的本地配置、凭据与完整运行日志。
