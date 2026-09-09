# 路径选择、验收与回滚

## 无法自动找到程序

在 PowerShell 7 中查询安装位置：

```powershell
Get-AppxPackage -Name OpenAI.Codex | Select-Object Name, Version, InstallLocation
Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node') -Filter node.exe -Recurse -File | Select-Object FullName
```

标准安装的桌面程序位于 `InstallLocation\app\ChatGPT.exe`。多个 Node 候选时，按当前 MCP 配置中的 NODE_REPL_NODE_PATH 选择，不按目录排序猜测。只读取有关键，不分享完整配置。

使用实际路径替换占位文字，再预检查：

```powershell
.\Start-CodexBrowserProxy.ps1 -CheckOnly -AppPath '实际的 ChatGPT.exe 完整路径' -NodePath '当前 node.exe 完整路径'
```

`-NodePath` 仅用于预检查，不覆盖真实 MCP 运行时；包装程序启动时使用 Codex 提供的 NODE_REPL_NODE_PATH。如果实际启动也需要 `-AppPath`，将该参数加到专用快捷方式参数末尾，并用引号包裹路径。不要把自定义路径写进要分享的脚本。

## 如何判断配置生效

1. `logs/launch.json` 的时间对应新启动。
2. 开始浏览器工具调用后，有新的 `logs/proxy-runtime-*.txt`。
3. 当前生成配置中的 node_repl command 和 CUA 的运行时路径指向本目录包装程序；键名随版本改变时先核对实现。
4. 实际浏览器按 README 验收通过。

`precheck.json` 中 browserVerified 为 false 表示该检查没有执行真实浏览器。后续的浏览器结果应另写报告，不修改这条日志冒充验收。

## 常见问题

| 现象 | 处理 |
| --- | --- |
| 提示配置缺失或地址无效 | 创建 proxy.txt；把 PORT 换成实际端口，确保只有一行 |
| 端口不可达 | 确认代理软件运行，端口为 HTTP/混合协议；TCP 成功本身不证明 HTTPS 代理正常 |
| 启动器与包装程序配置不一致 | 检查是否混用了不同版本文件；从同一参考包重新部署 |
| 多个 Node 运行时 | 预检查时用 -NodePath 指定当前有效版本 |
| Codex 仍在运行 | 保存任务并完全退出，然后使用专用快捷方式 |
| 仍有固定几十秒等待 | 记录实际 MCP 层指定环境及调用时序，不能把 CheckOnly 当作修复证明 |
| ACL、缺少运行时文件或控制内核退出 | 分开诊断安装与初始化问题，不以修改安全策略绕过 |
| 只有网页导航慢 | 诊断目标站点和网络，区别正常加载与控制命令等待 |
| 网页能读取但没有数据 | 检查账号、筛选与仓库权限，不等同于浏览器通道失败 |

## 从旧版迁移

将新版解压到新的固定目录，在新目录创建 proxy.txt 并预检查。不要把旧的 original/ 文件复制到新版，也不要覆盖正在运行的 EXE。保存任务并退出 Codex 后，更新专用快捷方式的脚本路径和工作目录，再启动验收。旧目录保留到确认新版可用。

## 回滚

正常退出专用入口启动的 Codex，从原来的 Codex 图标启动。核对当前 MCP 路径恢复原版后，可移除专用快捷方式；确认没有进程使用包装程序再清理目录。该方案不写全局环境或系统代理，无需为它改注册表。

如果另行手工设置过全局变量或其他启动器，则需单独检查；仅换回原图标不一定撤销那些独立改动。

## 分享时排除什么

分享发布 ZIP 即可。不要附带 proxy.txt、logs/、快捷方式、浏览器资料或完整 Codex 配置。哈希不是个人信息，仅用于验证下载完整性；可按需查看 SHA256SUMS.txt。
