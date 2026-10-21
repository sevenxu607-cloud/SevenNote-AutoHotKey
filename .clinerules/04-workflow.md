# 04 · 验证与工作流

## 改完必须验证

**不要只靠「读代码觉得没问题」就宣称改好了。** 改完 `.ahk` 必须用真实解释器跑一次。

### 先验编码与换行

源码 **UTF-8 无 BOM**；`.gitattributes` 规定 `*.ahk` **CRLF**、`*.md` **LF**。有些编辑器整文件写回会把 CRLF 统一成 LF（实测一次就把 `src\SevenWork.ahk` 全转成裸 LF，`git diff` 整文件变色）。**判换行只认字节**：

```powershell
$b=[System.IO.File]::ReadAllBytes($f); $crlf=0;$cr=0;$lf=0
for($i=0;$i -lt $b.Length;$i++){
    if($b[$i] -eq 13 -and $i+1 -lt $b.Length -and $b[$i+1] -eq 10){ $crlf++;$i++ }
    elseif($b[$i] -eq 13){ $cr++ } elseif($b[$i] -eq 10){ $lf++ }
}
```

期望 `crlf>0, cr=0, lf=0`；`BOM` 看头三字节是否 `EF BB BF`。转回 CRLF 且无 BOM：

```powershell
$t = $t -replace "`r`n","`n"; $t = $t -replace "`n","`r`n"
[System.IO.File]::WriteAllText($src, $t, [System.Text.UTF8Encoding]::new($false))
```

> ⚠ **正则里的反引号必须写在双引号字符串里。** 写成单引号 `'(?<!`r)`n'` 时 PowerShell 不做转义，
> 匹配的是字面「反引号 + n」：检测误报 `bareLF=9`（字节级其实是 0），照它去「修」会把 AHK 的
> `` `n `` 换成真换行、多行字符串当场报 `Missing """`，脚本起不来（2026-10-20 实测踩到）。

### 语法检查

⚠ **`/validate` 不可用** —— v2.0.27 不识别，会把它当成脚本路径去找，找不到就弹模态错误框、进程卡住不退出。

#### 方案 A（预检，有盲区）：注入 `ExitApp()`

```powershell
$exe = 'D:\02-Apps\AutoHotkey\v2\AutoHotkey64.exe'
$tree = 'D:\03-PersonalFiles\02-GitHubFiles\SevenWork-dev'   # 开发一律在 dev 工作树里验
$src  = "$tree\src\SevenWork.ahk"
$dir  = "$tree\src"   # 预检脚本必须与主脚本同目录，否则相对 #Include 找不到
$L   = [System.IO.File]::ReadAllLines($src)
$tmp = "$dir\_syn_check.ahk"
$out = @('#Requires AutoHotkey v2.0','ExitApp()') + $L[1..($L.Count-1)]
[System.IO.File]::WriteAllText($tmp, (($out -join "`r`n") + "`r`n"), [System.Text.UTF8Encoding]::new($false))
$se  = "$env:TEMP\SevenWorkDev\_syn_err.txt"
New-Item -ItemType Directory -Force -Path (Split-Path $se) | Out-Null
$r   = Start-Process -FilePath $exe -ArgumentList @('/ErrorStdOut', "`"$tmp`"") `
         -RedirectStandardError $se -Wait -PassThru
"退出码 = $($r.ExitCode)"     # 0 = 通过
Get-Content $se               # 空 = 没有语法错误
Remove-Item $tmp -Force
```

> ⚠ **别用 `& $exe ...` 判退出码** —— 它是 GUI 子系统程序，调用运算符不等它，`$LASTEXITCODE`
> 保留旧值（通常 `0`），看起来「一切通过」。用 `Start-Process -Wait -PassThru`。
> **每次用坏样本反向验证一次**：未闭合字符串（`x := "abc`）→ 退出码 `2`、stderr 打 `Missing """`。
> ⚠ 坏样本别用行尾 `x :=` —— AHK v2 支持行尾运算符续行，会与下一行拼成 `x := ExitApp()`，
> 语法合法、退出码 `0`，白费一轮排查。

> ⚠ **盲区：抓不到 class 体内的错误。** `ExitApp()` 在第 2 行，AHK **并非**加载时完整解析整个文件 ——
> auto-execute 跑到 `ExitApp()` 就退出，后面的 class 定义根本没被解析。实测往 `Themes` 数组追加主题时
> 漏了逗号，预检退出码 `0`，真机启动报 `src\SevenWork.ahk (946) : ==> Unexpected "{"`。

#### 方案 B（真机验证，必做）

改完必须用这个兜底 —— 它就是方案 A 漏掉的那一半：

```powershell
$exe = 'D:\02-Apps\AutoHotkey\v2\AutoHotkey64.exe'
$script = 'D:\03-PersonalFiles\02-GitHubFiles\SevenWork-dev\SevenWork.ahk'   # 根启动器
$se = "$env:TEMP\SevenWorkDev\_run_err.txt"
Remove-Item $se -Force -ErrorAction SilentlyContinue
Start-Process -FilePath $exe -ArgumentList @('/ErrorStdOut', "`"$script`"") `
    -RedirectStandardError $se | Out-Null
Start-Sleep -Seconds 6
Get-Content $se          # 空 = 没有运行时/语法错误
Get-Process -Name AutoHotkey64 | Stop-Process -Force   # 收工，别留实例
```

| 现象 | 含义 | 怎么查 |
| --- | --- | --- |
| stderr **有内容** | 有语法/运行时错误，AHK 已退出 | 直接读 stderr，有行号 |
| stderr **为空**、但多出一个标题是**脚本名**的窗口 | 弹了模态错误框，进程**卡着不退** | 见下方「错误框抓法」 |

⚠ **窗口没出来 ≠ 出错**：`SevenWork` 启动时不显示（`g.Show()` 只在 `WindowFeature.Show()` 里调）。
枚举会看到 `title=SevenWork / vis=False / 0x0 at 0,0`，那是**正常**的。要看到窗口先发一次 `Alt+Z`：
`Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('%z')`。

**错误框抓法**（AHK 报错框类名 `#32770`、标题是脚本名；正文在 Static 里，跨进程 `GetWindowText` 读不到）：

```ahk
DetectHiddenWindows true
Loop {
    hwnd := WinExist("ahk_class #32770")
    if !hwnd
        break
    MsgBox WinGetText("ahk_id " . hwnd)   ; 或写文件后读
}
```

> **改完直接按方案 B 跑一遍**是唯一能证明「程序真能起来」的检查；方案 A 只当写代码中途的快速预检。
> 端到端演示测试已移除（2026-10-19，为工作台化重构让路）；重构后按新模块结构重建。

## 单测一个 Service / Feature（探针脚本）

不必起真窗口：把主脚本读进内存、在 **auto-execute 段内**插一段驱动（直接调 `SomeService.Method()`、
结果写文件），最后 `ExitApp()`。

- **驱动插在 `ShowStartupTip()` 调用行之后**，别追加到文件末尾 —— 追加在末尾的驱动历史上曾整段
  不执行（`exit=0`、stderr 空、日志两边都没有），原因未完全定位，**别拿它赌**。
- AHK v2 里函数定义、类定义、运行时 `Hotkey()` 调用**都不结束** auto-execute；真正结束它的是
  **热键 / 热字符串 / `#HotIf` 指令**。

```powershell
# $src 指向 src\SevenWork.ahk，$dir 指向 src\ —— 探针必须与 #Include 同目录
$t   = [System.IO.File]::ReadAllText($src, [System.Text.Encoding]::UTF8)
$drv = 'ShowStartupTip()' + "`r`n" + 'LogError("PROBE ...")' + "`r`n" + 'ExitApp()'
$t2  = [regex]::Replace($t, '(?m)^ShowStartupTip\(\)\r?$', $drv, 1)   # 恰好 1 处
if ($t2 -eq $t) { throw 'anchor not found' }
[System.IO.File]::WriteAllText("$dir\_probe.ahk", $t2, [System.Text.UTF8Encoding]::new($false))
```

- 探针必须放 `src\`（与相对 `#Include` 同目录）；`A_ScriptDir` 是 `src\` 时日志落 `src\.logs\`。
- ⚠ **开发验证一律在 `SevenWork-dev` 工作树里做**：主目录没有 `_dev.flag`，跑探针就是「生产身份」——
  日志落 `%AppData%\SevenWork\`，还会读写生产的 `_config.ini`。
- 跑之前先 `Stop-Process` 掉已在运行的实例（两个实例抢热键，后起的注册失败、可能弹模态框）。
- **验证完立刻删掉** `src\_probe.ahk` 与 `src\.logs\`。

### 探针第一行别用裸 `FileDelete`

`FileDelete(不存在的路径)` 抛 `OSError`，而 `OnError` 之后**后续语句不再执行** —— 表现是
「日志没生成、`exit=0`、stderr 空」，极易误判成「脚本没启动」。用 `if FileExist(...)` 守卫，
或干脆只 `FileAppend`（会自己创建）；每步都 `FileAppend(步骤名, logp)`，卡在哪一步一眼看得到。

## ⚠ 上下文热键无法用 `Send` 验证（只能手按）

`HotIf(...)` / `#HotIf` 由**键盘钩子**实现，而钩子**忽略同一脚本 `Send` 的事件**（`SendLevel(1)` 也无效）：

| 热键类型 | 实现方式 | `Send` 能否触发 |
| --- | --- | --- |
| 无上下文的 `Hotkey()`（`Alt+Z` / `Alt+S`） | 系统 `RegisterHotKey` | **能** ✓ 用它验全局热键 |
| 有 `HotIf` 上下文 / `$` 前缀 | 键盘钩子 | **不能** ✗ |

**别据此判定「热键坏了」。** 只能：① `Hotkey()` 全部未抛错 → `_error.log` 为空；② 人工按键。
⚠ 连带假象：`Send("^f")` 命中上下文热键时会**等热键线程跑完**，探针看起来「卡住」——
判断真假卡直接调那个 action（实测 `SearchFeature.Show()` 16ms 返回）。
**断言「改造前后等价」**：把新注册的上下文表达式与旧 `#HotIf` 行逐字比对。

## 看主题效果时的窗口截图坑

验证背景图主题**别只看成品图**，要在真窗口里看文字压上去的效果：

| 坑 | 现象 | 绕法 |
| --- | --- | --- |
| `PrintWindow` 抓不全 | 窗口一大（1361x1084）右半边全空，文字与背景断在同一列 —— 那是截图边界、不是 bug | 用 **900 宽以内**的窗口抓，或 `CopyFromScreen` |
| 最小化窗口 `IsWindowVisible` 仍是 `1` | `GetWindowRect` 返回 `-21333,-21333`（150% 下的停放位），抓出来只有 158x26 | 先 `IsIconic()`、再 `ShowWindow(hwnd, 9)`；坐标是负数就当没显示 |
| 一条 PowerShell 里塞「`SendKeys` + 截屏 + 杀进程」 | 被防病毒拦，整条命令不执行（`ScriptContainedMaliciousContent`） | **拆成多条** |

**回写 / 重铺类改动的验收公式**：连打 N 次 `SetWindowPos` + 前后各截一张图逐字节比对。
每次几毫秒（实测 40 次共 392ms）说明合成被合并；秒级说明还在逐帧重铺。两张 PNG 字节数完全相同 = 逐像素一致。

> **判构图和明暗直接读成品 PNG**（`bgAlpha = 0` 时它就是铺进编辑区的内容）；截图只用来看文字读不读得清。

## 临时脚本放哪（别污染「问题」面板）

调试脚本 / 截图 / 中间产物**别丢在 `%TEMP%` 根目录** —— VS Code（AHK++ / PowerShell 扩展）会把它们
纳入诊断，「问题」面板被一次性脚本的告警刷屏，且删文件后诊断仍是**陈旧缓存**。

- 统一放 `%TEMP%\SevenWorkDev\`，用完整目录删：
  `Remove-Item "$env:TEMP\SevenWorkDev" -Recurse -Force -ErrorAction SilentlyContinue`；
- 别写进仓库目录（`.ahk` / `.ps1` 会进 `git status`，也会被 AHK++ 扫到）；
- 清陈旧诊断：关掉该文件标签页 → `Developer: Reload Window`（诊断只在扩展宿主内存里，磁盘上没有缓存可删）。

## 给 PowerShell 写脚本时的编码坑

`powershell.exe`（5.1）**按系统 ANSI（本机 GBK）读无 BOM 的 `.ps1`**，也按 ANSI 解码子进程输出的 UTF-8：

- 脚本内容**全用 ASCII**（注释、输出、字符串一律英文）；必须含中文时存成 **UTF-8 带 BOM**；
- 中文路径别硬写，用通配符取（`'D:\00-...\*\*\*\2026-10-14_*.png'`）；
- 别用 `git show x.ahk | Set-Content out.ahk` 搬源码 —— GBK 双字节解码会**吃掉紧跟的 ASCII 字符**
  （引号 / 括号），类体边界被破坏，报 `Not a valid method, class or property definition`。走
  `cmd /c "git ... > file"`。

## PowerShell 持久会话的坑（`Add-Type` 沿用旧编译类型）

命令跑在**同一个持久 `powershell.exe` 会话**里。`Add-Type` 第二次定义同名类型会抛「类型已存在」并
**静默沿用第一次编译的类型** —— 改了 C# 逻辑，脚本还在跑旧代码，**输出看起来完全正常**
（实测改完提亮曲线后重跑，输出与旧公式逐像素一致）。

- `Add-Type` 外套 `if (-not ("Name" -as [type])) { ... }`；
- **改了 C# 逻辑就递增类名**（`X` → `X2`）强制重编译；
- 验收别只看图：**取一个已知输入算预期输出，再读实际输出比对**。

⚠️ 同一次响应里「编辑文件 + 运行脚本」**不保证先编辑后运行**（实测编辑与命令并行，脚本跑到的是
编辑前的版本）。要跑改过的脚本，**先发编辑，下一轮再运行**。

## 提交信息

简体中文短句，说清「做了什么」，**不加** `feat:` / `fix:` 等英文前缀。
参考既有提交：`添加了终端快捷呼出隐藏功能`、`autohotkey位置配置修改`。
