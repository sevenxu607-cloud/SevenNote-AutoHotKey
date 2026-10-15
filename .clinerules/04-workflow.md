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
$tmp = "$env:TEMP\_syn_check.ahk"
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

## 提交信息

简体中文短句，说清"做了什么"，**不加** `feat:` / `fix:` 等英文前缀。
参考既有提交：`添加了终端快捷呼出隐藏功能`、`autohotkey位置配置修改`。
