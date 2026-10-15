# 04 · 验证与工作流

## 改完必须验证

**不要只靠"读代码觉得没问题"就宣称改好了。** 改完 `.ahk` 必须用真实解释器跑一次语法检查。

### 语法检查（本项目已实测有效）

⚠️ **`/validate` 不可用** —— 本机 AHK v2.0.27 不识别该参数。别用。

实测症状：AHK 会把 `/validate` 当成脚本路径去找，找不到就**弹出模态错误框**
（标题是脚本名，正文形如 `Error: Invalid assignment.`），进程**卡住不退出**，
窗口一直挡在屏幕上，只能手动杀进程收拾。

正确做法：**复制源码 + 注入 `ExitApp()` + `/ErrorStdOut`**。

```powershell
$exe = 'D:\02-Apps\AutoHotkey\v2\AutoHotkey64.exe'
$src = 'd:\03-PersonalFiles\02-GitHubFiles\SevenNote-AutoHotKey\SevenNote.ahk'
$L   = Get-Content -LiteralPath $src -Encoding UTF8
$tmp = "$env:TEMP\SevenNoteDev\_syn_check.ahk"
New-Item -ItemType Directory -Force -Path (Split-Path $tmp) | Out-Null
# 保留 #Requires 行，紧跟 ExitApp()，让脚本解析完立刻退出、不产生运行时副作用
Set-Content -LiteralPath $tmp -Value (@('#Requires AutoHotkey v2.0','ExitApp()') + $L[1..($L.Count-1)]) -Encoding UTF8
& $exe /ErrorStdOut $tmp
"退出码 = $LASTEXITCODE"     # 0 = 语法通过；非 0 = 有语法错误，stderr 会给出行号
```

**实测基准**：`SevenNote.ahk`（2365 行）退出码 `0`；故意写坏的脚本退出码 `2`，
并打印 `(3) : Invalid assignment`。

> 原理：AHK v2 在**加载时完整解析整个文件**。所以在开头注入 `ExitApp()`
> 既不会跳过语法检查，也不会触发建窗 / 写文件等副作用。

## 端到端演示测试

`tests\run_user_journey_demo.ps1` —— 沙箱隔离，**不碰真实 AppData / Vault**：

- 沙箱位置：`%TEMP%\SevenNoteJourneyTests\<runId>\`（内含 AppData / Vault / `_config.ini`）
- 参数：`-AutoHotkeyPath`、`-PaceMs`、`-TypeDelayMs`、`-SpeedMode`
- 产物：`results.tsv`、`trace.log`、`user-journey-report.html`
- 内置防冲突：若已有隔离演示在运行，会直接报错拒绝（避免向歧义窗口发送输入）

## 临时脚本放哪（别污染「问题」面板）

调试验证用的脚本、截图、中间产物**不要直接丢在 `%TEMP%` 根目录** —— VS Code
（AHK++ / PowerShell 扩展）会把那里的文件纳入诊断，「问题」面板会被一堆一次性脚本的
告警刷屏（实测：`_grab.ahk`、`_sstest.ahk`、`_gdicmp.ps1` 三个临时文件的 5 条告警把
真问题全盖住了）。而且文件删掉后诊断仍是**陈旧缓存**，必须 `Developer: Reload Window`
才消失。

- 统一放 `%TEMP%\SevenNoteDev\`，**用完立刻整目录删掉**：

  ```powershell
  Remove-Item "$env:TEMP\SevenNoteDev" -Recurse -Force -ErrorAction SilentlyContinue
  ```

- 同理别把中间产物（截图、diff 图、日志）留在 `%TEMP%` 根部。
- 更别写进仓库目录 —— `.ahk` / `.ps1` 会进 `git status`，也会被 AHK++ 语法检查扫到。

## 给 PowerShell 写脚本时的编码坑

`powershell.exe`（5.1）**按系统 ANSI（本机 GBK）读取无 BOM 的 `.ps1`**。用 UTF-8 无 BOM
写含中文的脚本，中文会变乱码；GBK 双字节解码还会**吃掉紧跟其后的 ASCII 字符** ——
实测引号被吞，报 `字符串缺少终止符`，让人以为是语法写错。

- 脚本内容**全用 ASCII**（注释、输出消息、字符串一律英文）；
- 必须含中文时存成 **UTF-8 带 BOM**；
- 中文路径别硬写在脚本里，用通配符取：

  ```powershell
  # 路径的目录名本身是中文也没关系，通配符里不含中文即可
  $src = (Get-ChildItem -Path 'D:\00-SevenFiles\Pictures\*\*\*\2026-10-14_*.png' | Select-Object -First 1).FullName
  ```

## 提交信息

简体中文短句，说清"做了什么"，**不加** `feat:` / `fix:` 等英文前缀。
参考既有提交：`添加了终端快捷呼出隐藏功能`、`autohotkey位置配置修改`。
