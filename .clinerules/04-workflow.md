# 04 · 验证与工作流

## 改完必须验证

**不要只靠"读代码觉得没问题"就宣称改好了。** 改完 `.ahk` 必须用真实解释器跑一次语法检查。

### 语法检查

⚠️ **`/validate` 不可用** —— 本机 AHK v2.0.27 不识别该参数。别用。

实测症状：AHK 会把 `/validate` 当成脚本路径去找，找不到就**弹出模态错误框**
（标题是脚本名，正文形如 `Error: Invalid assignment.`），进程**卡住不退出**，
窗口一直挡在屏幕上，只能手动杀进程收拾。

#### 方案 A（预检，有盲区）：注入 `ExitApp()`

```powershell
$exe = 'D:\02-Apps\AutoHotkey\v2\AutoHotkey64.exe'
$src = 'd:\03-PersonalFiles\02-GitHubFiles\SevenNote-AutoHotKey\SevenNote.ahk'
$L   = Get-Content -LiteralPath $src -Encoding UTF8
$tmp = "$env:TEMP\SevenNoteDev\_syn_check.ahk"
New-Item -ItemType Directory -Force -Path (Split-Path $tmp) | Out-Null
Set-Content -LiteralPath $tmp -Value (@('#Requires AutoHotkey v2.0','ExitApp()') + $L[1..($L.Count-1)]) -Encoding UTF8
& $exe /ErrorStdOut $tmp
"退出码 = $LASTEXITCODE"     # 0 = 通过
```

**实测基准**：`SevenNote.ahk` 退出码 `0`；故意写坏的赋值语句退出码 `2`，
并打印 `(3) : Invalid assignment`。

> ⚠ **但它有盲区，别只靠它。** 实测踩到：往 `ThemeService.Themes` 数组追加主题时漏了元素间
> 的逗号，这个预检**退出码照样是 `0`**，而真机启动立刻报
> `SevenNote.ahk (946) : ==> Unexpected "{"`。
>
> 原因：`ExitApp()` 在第 2 行，AHK v2 **并非**「加载时完整解析整个文件」——
> auto-execute 段跑到 `ExitApp()` 就退出了，**后面那些 class 定义根本没被解析**。
> 所以这个预检能抓「auto-execute 段及其之前」的错误，**抓不到 class 体内的**。

#### 方案 B（真机验证，必做）：直接启动 + 抓 stderr

改完必须用这个兜底 —— 它就是方案 A 漏掉的那一半：

```powershell
$exe = 'D:\02-Apps\AutoHotkey\v2\AutoHotkey64.exe'
$script = 'd:\03-PersonalFiles\02-GitHubFiles\SevenNote-AutoHotKey\SevenNote.ahk'
$se = "$env:TEMP\SevenNoteDev\_run_err.txt"
Remove-Item $se -Force -ErrorAction SilentlyContinue
Start-Process -FilePath $exe -ArgumentList @('/ErrorStdOut', "`"$script`"") `
    -RedirectStandardError $se | Out-Null
Start-Sleep -Seconds 6
Get-Content $se          # 空 = 没有运行时/语法错误
Get-Process -Name AutoHotkey64 | Stop-Process -Force   # 收工，别留实例
```

⚠️ **两种错误形态要分清**：

| 现象 | 含义 | 怎么查 |
| --- | --- | --- |
| stderr **有内容** | 有语法/运行时错误，AHK 已退出 | 直接读 stderr，给出行号 |
| stderr **为空**、但多出一个标题是**脚本名**（`SevenNote.ahk`）的窗口 | 弹了模态错误框，进程**卡着不退**，`ExitApp` 也没用 | 见下方「错误框抓法」 |

⚠️ **窗口没出来 ≠ 出错**。`SevenNote` 的窗口**启动时不显示**——
`g.Show()` 只在 `WindowFeature.Show()`（`!z` 热键）路径里由 `_PlaceWindow` 调用。
所以启动后枚举窗口会看到 `AutoHotkeyGUI / title=SevenNote / vis=False / 0x0 at 0,0`，
那是**正常**的。要看到窗口得先发一次 `Alt+Z`：

```powershell
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('%z')
```

**错误框抓法**（stderr 为空却卡着时）：

```powershell
# AHK 报错框的类名是 #32770、标题是脚本名；正文在 Static 子控件里，
# 跨进程 GetWindowText 读不到 —— 用本机 AHK 的 WinGetText 最省事
DetectHiddenWindows true
Loop {
    hwnd := WinExist("ahk_class #32770")
    if !hwnd
        break
    MsgBox WinGetText("ahk_id " . hwnd)   ; 或写文件后读
}
```

> 更快的路子：**改完直接按方案 B 跑一遍**。它同时覆盖 auto-execute 段和全部 class 定义，
> 是唯一能证明「程序真能起来」的检查。方案 A 只当写代码中途的快速预检。

## 端到端演示测试

`tests\run_user_journey_demo.ps1` —— 沙箱隔离，**不碰真实 AppData / Vault**：

- 沙箱位置：`%TEMP%\SevenNoteJourneyTests\<runId>\`（内含 AppData / Vault / `_config.ini`）
- 参数：`-AutoHotkeyPath`、`-PaceMs`、`-TypeDelayMs`、`-SpeedMode`
- 产物：`results.tsv`、`trace.log`、`user-journey-report.html`
- 内置防冲突：若已有隔离演示在运行，会直接报错拒绝（避免向歧义窗口发送输入）

## 看主题效果时的窗口截图坑

验证背景图主题**别只看成品图**，要**在真窗口里看文字压上去的效果**。实测三个坑：

| 坑 | 现象 | 绕法 |
| --- | --- | --- |
| `PrintWindow` 抓不全 | 窗口一大（实测 1361x1084），右半边全是空白，**文字和背景同时断在同一列** —— 那是截图边界，**不是应用 bug**（474 宽的小窗口抓得完整） | 用 **900 宽以内**的窗口抓，或改用 `CopyFromScreen`（截屏前先确认窗口没被别的窗口压住） |
| **最小化窗口的 `IsWindowVisible` 仍是 `1`** | 以为窗口显示着，`GetWindowRect` 却返回 `-21333,-21333`（150% DPI 下的最小化停放位），抓出来只有 158x26 | 先 `IsIconic()` 判断、再 `ShowWindow(hwnd, 9)` 恢复；`GetWindowRect` 拿到负数坐标就一律当没显示 |
| 一条 PowerShell 里塞「`SendKeys` + 截屏 + 杀进程」会被**防病毒拦** | 整条命令一行都不执行，报 `ScriptContainedMaliciousContent` | **拆成多条**：类型定义 / 发热键 / 截屏各自一条 |

**回写、重铺这类改动的验收公式**：连打 N 次 `SetWindowPos` + 前后各截一张图逐字节比对。

```powershell
# 0x0004 = SWP_NOZORDER；打一串不同尺寸，测总耗时
for ($i = 1; $i -le 40; $i++) {
    [PW7]::SetWindowPos($h, [IntPtr]::Zero, $x, $y, ($w + ($i % 9) * 7), ($hgt + ($i % 11) * 9), 0x0004)
}
```

- 每次 **几毫秒**（实测 40 次共 392ms）说明合成被合并了；秒级说明还在逐帧重铺。
- 打完把尺寸**调回原值**再截第二张 —— 两张 PNG **字节数完全相同**（1302123 = 1302123）
  就是逐像素一致，即「文字没丢、图没错位」。

> **判构图和明暗请直接读成品 PNG。** 成品图就是铺进编辑区的内容（`bgAlpha = 0` 时无遮罩、
> 无裁切），比隔着截图猜准得多；截图只用来看「文字压在图上读不读得清」。

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

**怎么清陈旧诊断**：文件删了、「问题」面板还挂着它的告警时 ——

1. 先关掉那个文件的标签页（若 VS Code 里还开着）；
2. `Ctrl+Shift+P` → 输入 `Developer: Reload Window` 回车。

诊断只存在于扩展宿主进程的内存里，磁盘上**没有**缓存文件可删，所以别去翻
`%APPDATA%\Code\` 找 —— 重载窗口是刷新它的方式（实测：`%TEMP%\_gdicmp.ps1`
早已删除，面板里那 3 条告警仍旧挂着，与磁盘状态无关）。

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

## PowerShell 持久会话的坑（Add-Type 会沿用旧编译类型）

命令是在**同一个持久 `powershell.exe` 会话**里跑的。用 `Add-Type` 定义 C# 辅助类时，
第二次运行会抛「类型名称 `X` 已存在」，并且**静默沿用第一次编译的那个类型** ——
你改了 C# 逻辑，脚本还在跑旧代码，**而输出看起来完全正常**。

实测（给主题烘图那个脚本）：改完提亮曲线后重跑，输出与旧公式**逐像素完全一致**；
只有拿源图某个点手算「预期值 vs 实际值」比对才暴露 —— 实际值精确等于**旧公式**的结果。

对策：

- `Add-Type` 外面套 `if (-not ("Name" -as [type])) { ... }`，让重复运行不再报错；
- **改了 C# 逻辑就递增类名**（`X` → `X2`），强制重新编译；
- 验收别只看图、只看统计 —— **取一个已知输入算预期输出，再读实际输出比对**。

⚠️ 同一次响应里「编辑文件 + 运行脚本」**不保证先编辑后运行**（实测编辑器调用与命令
并行执行，脚本跑到的是**编辑前**的版本）。要跑改过的脚本，**先发编辑，下一轮再运行**。

## 提交信息

简体中文短句，说清"做了什么"，**不加** `feat:` / `fix:` 等英文前缀。
参考既有提交：`添加了终端快捷呼出隐藏功能`、`autohotkey位置配置修改`。
