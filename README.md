# Codex 内置浏览器固定延迟治理指南（Windows 通用部署参考）

版本：1.2 · 更新日期：2026-09-09 · 适用对象：在其他 Windows 电脑部署或向其他使用者交付本方案。

**本次有效操作：从专用快捷方式给 Codex 桌面进程传入代理相关变量，再通过原有运行时路径覆盖入口，启动一个只补齐代理环境的 MCP 包装程序。重启后，连续页面读取从约 21 秒降到 18–67 毫秒，截图降到 58 毫秒。**

本指南提供可迁移的排查、部署、验收和回滚步骤，适用于在其他电脑复现同类故障时参考。方案已在下述环境中验证，但每台目标电脑都需要独立验收。先确认故障与本机参数，再部署；用户名、运行时版本目录、代理端口和完整配置不能跨电脑直接照搬。

## 1. 适用范围与准备

适用现象：内置浏览器能显示页面，但 Codex 的 DOM 读取、点击或截图经常出现近似固定的几十秒等待，甚至工具超时；刷新或重新绑定偶尔恢复，随后又变慢。

本次验证环境：Windows x64；Codex 安装包 26.901.6511.0；生成的浏览器运行配置标识 26.901.51231；本地 HTTP 代理 127.0.0.1:56666。两个版本编号来自不同组件，不能仅因编号不同认定版本错误。

目标电脑需先确认：

| 检查项 | 操作与判定 |
| --- | --- |
| 系统 | 此附件包装程序针对 Windows x64；macOS、Linux、ARM64 不直接套用 |
| 故障 | 先测连续三次页面读取和一次截图；本来就正常则不部署 |
| 代理 | 确认本地 HTTP 或支持 HTTP 的混合端口；不能把 SOCKS 专用端口直接填为 HTTP 代理 |
| PowerShell | 以下部署命令使用 PowerShell 7；原脚本使用 Environment、ArgumentList 等 API，不能默认用 Windows PowerShell 5.1 |
| 当前 Codex 实现 | 需仍提供 NODE_REPL_NODE_PATH，并采用本次识别的 CODEX_NODE_REPL_PATH 入口；版本变化时由 Codex 只读核对当前实现 |
| 文件位置 | 用当前用户可读写的固定本地目录，不要在临时下载目录或压缩包内直接运行 |

只在上述条件吻合时继续。若出现的是安装文件丢失、ACL 设置失败、登录失效或网页网络故障，按第 9 节分开诊断。

## 2. 本次查到了什么

### 2.1 手动写入的配置没有稳定保留

曾在 `[mcp_servers.node_repl.env]` 追加四项变量，但重启后对应项消失。本机安装实现显示，桌面启动时使用 `config/batchWrite` 和 `mergeStrategy: replace` 重新生成托管 MCP 配置，也会重写插件的生成配置。

因此，反复粘贴相同配置或者直接改插件缓存，没有形成可靠的持久化方案。本次没有采集用户按保存按钮的瞬间，不能倒推用户当时一定保存或未保存。

### 2.2 只给桌面程序设置代理仍不够

第一版专用启动脚本让桌面进程收到四项变量。重启后，固定延迟仍在。随后只读核对实际进程环境，发现：

| 进程层 | HTTP_PROXY / HTTPS_PROXY |
| --- | --- |
| 桌面进程与 app-server | 有 |
| MCP 启动层 launch.mjs 与原版 node_repl 主进程 | 缺失 |
| 下层 kernel / trusted Node | 已有 |

所以不能简单说“整个浏览器都没走代理”；实际发现的是 **MCP 启动层的环境传递缺口**。

### 2.3 最终补齐启动层，并用真实浏览器验收

本机安装实现提供 `CODEX_NODE_REPL_PATH` 入口。启动脚本通过它选择 `node-repl-proxy.exe`；包装程序补齐两个代理变量，再原样启动自带的 `node_repl.exe`。

```text
专用桌面快捷方式
  → Start-CodexBrowserProxy.ps1
  → Codex 桌面进程（代理变量、开关、allowlist、运行时覆盖路径）
  → 生成的 MCP / CUA 配置选择包装程序
  → node-repl-proxy.exe（补齐 HTTP_PROXY、HTTPS_PROXY）
  → 原版 node_repl.exe
  → 浏览器控制
```

包装程序继承原 MCP 标准输入、输出及错误句柄，不改写协议；原版程序仍负责工具与沙箱。Windows Job 只管理包装程序新建的子进程树。没有改安装包、全局环境、系统代理、证书或安全策略。

环境缺口已被直接观察；补齐后实际延迟消失。但尚无内部计时日志证明某一个 Statsig/遥测请求是所有历史超时的唯一根因。截图中的网络开关方案是排查线索，不是可通用于所有机器的根因结论。

## 3. 部署资料与交付内容

将完整的 `Codex-浏览器治理参考包.zip` 复制到目标电脑，解压后按本指南操作。分享给其他使用者时也应交付完整参考包。包内：

| 文件 | 用途 |
| --- | --- |
| README.md | 本指南，包含部署、验收、回滚及交给 Codex 的提示词 |
| original/Start-CodexBrowserProxy.ps1 | 已验收方案的脱敏启动脚本；使用前必须适配目标电脑的路径和端口 |
| original/NodeReplProxyLauncher.cs | 已验收的包装程序源码；端口不同需修改并重新编译 |
| original/node-repl-proxy.exe | 已验收的 x64 程序，内部固定使用 56666；其他端口不能直接复用 |
| SHA256SUMS.txt | 随包文件校验值；编辑后的文件校验值自然会变化 |

目标电脑使用自己的安装、配置和登录状态。迁移仅需参考包内的治理资料，不复制来源电脑的整份 `.codex`、`config.toml`、浏览器资料、账号凭据或桌面快捷方式。

## 4. 目标电脑部署步骤

### 步骤一：先保存基线

让目标电脑上的 Codex 在当前任务内置浏览器中打开一个能够访问的网页。保留同一标签页，记录：连续三次 DOM 读取、一次截图、一次可恢复点击的实际耗时与错误原文。核实页面内容确实加载完成。

记录当前 Codex 版本、代理软件名称与端口，以及配置是否会在启动后重新生成。若当前浏览器正常，不必为了预防而加上这套包装。

### 步骤二：核实代理端口

在代理软件设置页找到 HTTP/混合端口，记为自己的实际端口。基线环境中的 56666 不是通用默认值。

下面示例中的 7890 也只是示例，执行前改为实际值：

```powershell
$taskProxyPort = 7890
Test-NetConnection -ComputerName 127.0.0.1 -Port $taskProxyPort
curl.exe --proxy "http://127.0.0.1:$taskProxyPort" --connect-timeout 5 --max-time 15 -I https://example.com
```

TCP 成功仅证明端口在监听，不能证明 HTTP 代理可用。HTTPS 还要能完成代理 CONNECT 和后续 TLS/HTTP 访问。若本机 curl 出现证书或凭据错误，保留错误并分开诊断，不能直接判定代理失效，更不能把跳过证书验证当作治理步骤。

`HTTPS_PROXY` 的值仍可为 `http://127.0.0.1:端口`：这里描述的是连接到 HTTP 代理的方式，HTTPS 目标通过该代理建立隧道。

### 步骤三：准备固定目录和原件副本

以下示例假设你已经完整解压参考包，并在 **PowerShell 7** 中进入含 README.md 的目录：

```powershell
$PSVersionTable.PSVersion
$taskSourceDir = (Get-Location).Path
$taskRepairDir = Join-Path $env:LOCALAPPDATA 'CodexBrowserProxy'
if (Test-Path -LiteralPath $taskRepairDir) {
    throw '目标目录已经存在，请先检查已有治理文件，不要直接覆盖。'
}
New-Item -ItemType Directory -Path $taskRepairDir | Out-Null
Copy-Item -LiteralPath (Join-Path $taskSourceDir 'original\Start-CodexBrowserProxy.ps1') -Destination $taskRepairDir
Copy-Item -LiteralPath (Join-Path $taskSourceDir 'original\NodeReplProxyLauncher.cs') -Destination $taskRepairDir
```

原件保留在解压目录，工作副本放在固定目录。后续命令使用同一个 PowerShell 7 窗口中的 `$taskRepairDir`。

### 步骤四：查出目标电脑的两个真实程序路径

查看安装信息：

```powershell
Get-AppxPackage -Name OpenAI.Codex |
    Select-Object Name, Version, InstallLocation
```

本次安装形态的桌面可执行文件是 `InstallLocation\app\ChatGPT.exe`。如目标电脑的安装形态不同，按实际进程路径确认，不沿用基线环境的版本号。

Node 路径优先取目标电脑当前生成的 MCP 环境中的 `NODE_REPL_NODE_PATH`。只查看有关段落，不整份输出带凭据的配置。默认安装目录也可列举候选：

```powershell
$taskRuntimeRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node'
Get-ChildItem -LiteralPath $taskRuntimeRoot -Filter node.exe -Recurse -File |
    Select-Object FullName
```

有多个版本时，以当前配置或实际运行版本为准，不随便选择第一个。对应 `node.exe` 同目录下应有原版 `node_repl.exe`。本附件包装程序会校验它位于当前用户 LocalAppData 下的该运行时目录；不符合时需重新适配并验证，不能删除校验来强行通过。

### 步骤五：适配工作副本

打开固定目录里的 `Start-CodexBrowserProxy.ps1`，修改下面两个变量的值，保留单引号包裹 Windows 路径：

```powershell
$taskRecordedApp = '目标电脑实际的完整 ChatGPT.exe 路径'
$taskNode = '目标电脑当前运行时的完整 node.exe 路径'
```

**不要把上面两行占位文字直接当成可用路径。** `$taskWrapper` 已通过 `$PSScriptRoot` 指向同目录包装程序，不需要填写来源电脑的目录。

将工作副本两份源码中的所有 `56666` 改为已核实的实际端口。可以使用以下命令，先修改首行的示例端口：

```powershell
$taskProxyPort = 7890  # 改为代理软件的实际 HTTP/混合端口
if ($taskProxyPort -lt 1 -or $taskProxyPort -gt 65535) { throw '端口无效' }
foreach ($taskName in @('Start-CodexBrowserProxy.ps1', 'NodeReplProxyLauncher.cs')) {
    $taskFile = Join-Path $taskRepairDir $taskName
    $taskText = [IO.File]::ReadAllText($taskFile)
    [IO.File]::WriteAllText($taskFile, $taskText.Replace('56666', [string]$taskProxyPort), [Text.UTF8Encoding]::new($false))
}
```

这一步同步更新了脚本代理地址、端口探测、提示文本，以及 C# 的两个代理变量和日志。此替换适用于从原件准备的副本；以后换端口时应针对上一次实际端口修改。

确认有效环境仍为：

```text
BROWSER_USE_DISABLE_AMBIENT_NETWORK=1
NODE_REPL_UNTRUSTED_ENV_ALLOWLIST=原有项目加上 BROWSER_USE_DISABLE_AMBIENT_NETWORK,HTTP_PROXY,HTTPS_PROXY
HTTP_PROXY=http://127.0.0.1:实际端口
HTTPS_PROXY=http://127.0.0.1:实际端口
CODEX_NODE_REPL_PATH=固定目录\node-repl-proxy.exe
```

脚本自动合并 allowlist，保留目标电脑原有条目。native pipe、CODEX_HOME 和 NODE_REPL_NODE_PATH 等值必须来自当前电脑，不能从基线环境复制。

### 步骤六：编译并做启动预检查

本次使用 Windows 自带的 .NET Framework 64 位编译器：

```powershell
$taskCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $taskCompiler)) { throw '未找到本次使用的编译器，需要先适配构建环境' }
& $taskCompiler /nologo /target:exe /platform:x64 /optimize+ "/out:$taskRepairDir\node-repl-proxy.exe" "$taskRepairDir\NodeReplProxyLauncher.cs"
if ($LASTEXITCODE -ne 0) { throw '包装程序编译失败，不继续启动' }
& (Join-Path $taskRepairDir 'Start-CodexBrowserProxy.ps1') -CheckOnly
```

预检查通过应显示 `PASS`，并生成 `proxy-launcher-precheck.json`。它只检查程序存在、端口可达、测试 Node 子进程收到五项指定变量；**不会启动或停止 Codex，也不等于真实 MCP 或浏览器已修复。**

基线方案还完成了独立 MCP initialize、指定进程环境和退出清理验证；迁移时若修改包装逻辑而不仅是端口，应由 Codex 补做同等验证。不要把包装程序作为普通 GUI 程序双击：它依赖 MCP 客户端提供的标准流及运行环境。

若脚本被本机策略拦截，应记录具体策略并按本机允许的方式执行；本方案不要求永久放宽执行策略。

### 步骤七：创建专用桌面快捷方式

在同一个 PowerShell 7 窗口中执行：

```powershell
$taskPwshPath = Join-Path $PSHOME 'pwsh.exe'
if (-not (Test-Path -LiteralPath $taskPwshPath)) { throw '请使用 PowerShell 7 执行' }
$taskDesktop = [Environment]::GetFolderPath('Desktop')
$taskShortcutPath = Join-Path $taskDesktop 'Codex 浏览器代理.lnk'
if (Test-Path -LiteralPath $taskShortcutPath) { throw '同名快捷方式已存在，先检查再决定是否更新' }
$taskShell = New-Object -ComObject WScript.Shell
$taskShortcut = $taskShell.CreateShortcut($taskShortcutPath)
$taskShortcut.TargetPath = $taskPwshPath
$taskShortcut.Arguments = '-NoProfile -WindowStyle Hidden -File "' + (Join-Path $taskRepairDir 'Start-CodexBrowserProxy.ps1') + '"'
$taskShortcut.WorkingDirectory = $taskRepairDir
$taskShortcut.Save()
```

不替换原有 Codex 图标，保留它用于回滚。

### 步骤八：完成准备后，只重启一次

保存当前任务，完全退出 Codex；保持代理软件运行；从新建的“Codex 浏览器代理”快捷方式打开 Codex。不要同时点击旧入口。只关窗口未退出后台进程可能仍会继承旧环境。

脚本检测到旧 Codex 仍在运行时会拒绝启动并提示原因，不会强制终止任务。必须等本轮修改和预检查完成，再进行这一次重启；不要以连续重启代替诊断。

## 5. 重启后怎么确认真正生效

依次检查三层证据，不能只看截图或者一个 `PASS`：

1. **启动入口**：固定目录中 `proxy-launcher-status.json` 的时间应为刚才启动时间，`mcpWrapper` 应指向目标电脑的固定目录，`proxy` 应为目标电脑的实际端口。
2. **MCP 入口**：开始一次浏览器工具调用后应出现新的 `proxy-runtime-进程号.txt`。生成配置中 `mcp_servers.node_repl.command` 和 CUA 的 `CUA_REPL_NODE_REPL_PATH` 应指向同一个包装程序。不同版本可能变更结构；不符合时先核对实现，不直接改插件缓存。
3. **真实控制**：按第 6 节完成浏览器验收。启动日志中的 `browserRuntimeVerified: false` 是脚本的检查边界，不会因后续浏览器通过而自动改为 true。浏览器结论记录在独立验收报告里，不手动改日志冒充通过。

仅凭 config.toml 里没有 HTTP_PROXY 不能判定实际原版进程没有代理：包装程序在启动时补齐。若仍有固定等待，再针对实际 MCP 进程检查这几个变量，不能输出整个进程环境或其他凭据。

## 6. 验收步骤和本次结果

让 Codex 使用当前任务的内置浏览器执行，先读取本机工具提供的 API 文档，不照搬历史浏览器编号或标签页编号：

1. 初始化当前控制会话，绑定或新建目标页。
2. 导航到正常可访问的网站，确认正文完成加载。
3. 同一标签页连续执行三次 DOM 读取，逐次记录耗时及正文证据。
4. 截取一次视口截图，核对其与 DOM 一致。
5. 做一次可恢复操作，例如打开账号菜单，读取变化，再关闭并验证恢复。
6. 如原问题包含 `cua.getTab` 超时，单独复测该入口及返回的 AX 树。
7. 把成功、失败、未执行分别记录；有失败时不补测凑“连续三次成功”。

已验证环境的前后对照（2026-09-09，仅供效果比较，不作为其他电脑的验收结果）：

| 项目 | 包装程序启用前 | 启用后重启 |
| --- | --- | --- |
| GitHub 导航 | 29.898 秒 | 9.031 秒 |
| DOM 第一次 | 1.374 秒 | 67 毫秒 |
| DOM 第二次 | 21.077 秒 | 35 毫秒 |
| DOM 第三次 | 21.077 秒 | 18 毫秒 |
| 视口截图 | 21.109 秒 | 58 毫秒 |
| 打开菜单 | 紧邻前轮未测 | 297 毫秒，读取变化正确 |
| 关闭菜单并读取 | 紧邻前轮未测 | 303 毫秒合计，恢复正确 |
| 原 getTab 入口 | 更早曾超时并重置 kernel | 404 毫秒，返回完整 AX |

基线验证的页面已登录，`owner:@me` 显示加载完成的空列表。空列表不是读取失败，也不证明账号所有可访问仓库都为零。没有验证仓库克隆。

目标电脑的验收重点是：内容正确、操作可恢复、固定等待不再出现，而不是强求每次恰好几十毫秒。页面首次导航仍有正常网络时间；一次成功也不能认定所有历史故障永久根治。

## 7. 日常使用和升级后处理

- 继续使用新快捷方式；保持已验证的本地代理端口可用。
- 固定目录是运行依赖，不能把它当成用完可删的临时资料。
- 代理端口改变：同步修改两份工作源码、重新编译、预检查，再完整重启验收；不要覆盖正在使用的程序。
- Codex 升级：桌面程序原路径失效时脚本会尝试查询当前安装包，但预检查用的 `$taskNode` 仍需核对；包装程序运行时使用当前 `NODE_REPL_NODE_PATH`，并校验目录。
- 若升级后不再使用该入口或运行时布局改变，重新核对实现。不要硬改生成配置来维持过期方案。
- 可在以后需要比较时，从原入口启动并做同样测量。如果新版原入口已正常，可以停用包装方案。

## 8. 回滚

1. 保存任务，完全退出通过专用入口启动的 Codex。
2. 从原来的 Codex 快捷方式打开，确认当前启动与 MCP 路径恢复原有方式。
3. 确认没有进程仍使用包装程序后，再决定是否删除专用快捷方式和工作副本；原始资料可保留。

本方案只在新建进程环境中设置变量，没有写系统或用户全局环境，也没有改系统代理。因此正常回滚不需要改注册表或系统网络设置。若你另行手工改过系统环境，需要单独核查那些改动，不能认为原图标一定清除了外部设置。

## 9. 仍失败时如何处理

| 现象 | 下一步 |
| --- | --- |
| 代理端口不可达 | 检查代理软件是否运行、端口及协议是否正确；不继续启动 |
| 提示旧 Codex 仍运行 | 正常退出应用后使用新入口；不由脚本强杀当前任务 |
| 缺少 node.exe 或原版 node_repl.exe | 核对升级后的实际运行时路径；不能复制来源电脑的运行时目录代替本机安装 |
| 没有新包装日志或生成配置未选中包装程序 | 核对快捷方式、启动日志和当前版本的覆盖入口 |
| CheckOnly 成功，但真实工具仍约 21 秒 | 检查实际 MCP 层指定环境与调用时序；预检查不能代替真实验收 |
| 首次出现 apply deny-read ACLs / helper_unknown_error | 单独记录该初始化错误；本次曾轻量重试恢复，但未证明由代理修复。不要修改 ACL 或关闭沙箱 |
| 页面可见，但绑定入口超时并重置内核 | 记录原入口错误、耗时和重置；用当前工具允许的恢复方式重连，不能把换接口的成功说成原接口已修复 |
| 只有网页加载慢，DOM/截图很快 | 优先诊断站点与网络；区别正常导航耗时和控制命令固定等待 |
| 列表为空、登录失效或无仓库权限 | 分开处理账号、筛选及权限，与控制通道耗时分别验证 |

准备交给 Codex 的最小诊断信息：版本、实际代理端口、当前启动时间、配置中的相关键、包装日志、三次读取及截图耗时、原始错误。不要提交完整环境、cookie、token 或整份配置。

## 10. 可直接交给 Codex 的执行提示词

> 请读取我提供的《Codex 内置浏览器固定延迟治理指南》及随包源码，处理本机的同类问题。先测当前任务内置浏览器的连续三次 DOM 和一次截图，并只读核对本机 Codex 版本、代理 HTTP/混合端口、运行时路径及覆盖入口是否仍适用。不要操作个人 Chrome/Edge。若现象吻合，在固定用户目录准备适配后的启动脚本和 MCP 包装程序，保留原件与回滚入口，不修改安装包、全局网络或安全策略。完成编译和预检查后，再说明需要一次完整退出重启的原因；不要反复要求重启。重启后核对真实启动及包装日志，并复测三次 DOM、截图、可恢复点击和原绑定入口，形成前后对照报告。不要仅凭端口可达、预检查通过或页面截图就宣称修复；失败时明确卡在哪一步。参考包中的示例路径、端口和历史浏览器编号必须换成本机确认值；先确认本机兼容性，不把其他电脑的通过结果当成本机验收。

## 11. 资料依据和版本边界

本指南依据原始排查记录 MCP_PROXY_ENV_FIX.md、重启验收记录 MCP_PROXY_RESTART_ACCEPTANCE.md、启动脚本、包装源码、独立 MCP 验证结果及真实浏览器工具输出整理。本文已包含部署和验收所需信息，无需访问原始排查工作目录。交付时重新核对了源码和已验收二进制的校验值。

官方配置文档说明了通用 MCP 的 `command`、`env` 与 `env_vars` 含义：[OpenAI 配置参考](https://learn.chatgpt.com/docs/config-file/config-reference)。**本文有关托管配置重写和 CODEX_NODE_REPL_PATH 的结论来自本次本机安装实现；不把这一内部入口描述为官方承诺长期稳定的跨版本配置。**

原始 56666 包装程序 SHA-256：

```text
0CFF15FCE6ADDAFC3613959EEF97735EBD2290BA4B47945968693E3328574882
```

参考包中的脚本和源码以已验收基线为基础，启动脚本中的个人用户路径已改为本机环境变量与运行时占位符，属于需要按本机参数适配的部署参考，并非无需配置的一键安装器。跨电脑或跨使用者交付时，应完整保留本指南、适配说明、源码和校验值。每台目标电脑都须完成编译或程序核对、启动与真实浏览器验收，之后才能对该电脑给出“修复成功”的结论。


## 12. 分享前的隐私处理

发布包仅包含指南、经过脱敏的启动脚本、包装程序源码、已验收二进制及校验值。已移除启动脚本中的个人 Windows 用户目录；运行时版本使用占位符，部署前按第 4 节设置真实路径。包中不包含账号密码、邮箱、浏览器登录资料、原始诊断日志、截图或完整 Codex 配置。端口 56666 与回环地址 127.0.0.1 是基线配置参数，不是个人网络地址。文件校验值已重新生成。
