# 03 · AutoHotkey v2 约定

## 版本与文件格式

- 每个脚本首行必须有 `#Requires AutoHotkey v2.0`。
- 本机解释器（64 位）：`D:\02-Apps\AutoHotkey\v2\AutoHotkey64.exe`
  （同值见 `.vscode/settings.json` → `AHK++.v2.file.interpreterPath`）
- 源码编码：**UTF-8 无 BOM**（`SevenNote.ahk` 实测首字节为 `23 52 65`，即 `#Re`）。
- 换行：`.gitattributes` 规定 `*.ahk` 用 **CRLF**、`*.md` 用 **LF**。
- **必须 64 位**运行/编译：32 位会导致 RichEdit 字符格式异常。

## v2 语法要点（v1 写法一律不用）

- 赋值用 `:=`；比较用 `=`（不区分大小写）/ `==`（区分大小写）。
- 变量不加 `%` 包裹；只有旧式命令的参数才需要 `%var%`。
- 函数调用必须带括号、字符串必须加引号：`MsgBox("hi")`。
- `#HotIf` 取代 v1 的 `#If`。

## 本项目踩过的坑（README / SevenNote.ahk 头注释原文）

| 坑 | 说明 |
| --- | --- |
| `Clear` / `log` / `min` / `max` / `Indent` 不能做变量名 | 它们是 AHK v2 内置函数名 |
| **`Gui` 也不能做变量名** | 它是内置**类**名（同类还有 `Object` / `Map` / `Array` / `Buffer` / `Func` / `File` / `Clipboard`）。实测 `gui := WinExist(...)` 直接报 `This Class cannot be used as an output variable. Specifically: Gui`；**没加 `/ErrorStdOut` 时会弹模态框并卡住不退出**，表现为平白多出一个 `AutoHotkey64` 进程。变量名写长一点最省事（`guiHwnd` / `idxMap`） |
| AHK v2 的 `<` `>` 是数值比较 | 字符串比较用 `StrCompare` |
| AHK v2 的 `<=` / `>=` 遇**空字符串**会抛错 | 报 `Expected a Number but got an empty string`；数值比较前先 `IsNumber()` 守卫（`State` 未初始化的记忆值就是 `""`，实测踩到） |
| `EM_SETSEL` / `EM_GETSEL` 要用 DllCall | 内置 `SendMessage` 对 INT 参数有歧义 |
| `FINDTEXTEXW` 读偏移 16/20（chrgText） | 误读 0/4 会导致搜索只找到 1 个 |
| 32 位编译导致 RichEdit 字符格式异常 | **必须 64 位编译** |
| `FileInstall` 必须写在一行 | 折行会导致打包出 0KB 空文件 |
| `FileExist` 返回 `"A"` 不是 `true` | 断言需 `!!` 转换 |
| **最小化窗口的 `IsWindowVisible` 仍是 `1`** | 判断“窗口是否在显示”必须用 `IsWindowVisible && !IsIconic`。最小化窗口的 `WinGetPos` 会返回 `-32000` 一类**屏幕外停放位**（按 DPI 缩放显示为 `-21333` 等）；把这种坐标记下来再 `WinMove`，窗口就被永久搬到看不见的地方，`Alt+Z` 再也呼不出。**记录窗口位置前必须校验它落在某个屏幕工作区内**（`MonitorGetWorkArea`），并给 `WinRestore` 兜底 |
| **`WinMove` 收「物理像素」，而 `Config` 里的尺寸是「逻辑单位」** | 本机 150% 缩放（`A_ScreenDPI = 144`、`A_ScreenWidth = 2560`、`A_ScreenHeight = 1600`）下，`Gui` 控件坐标按 DPI 放大 1.5 倍，**窗口最小尺寸由控件固有尺寸决定**，`+MinSize450x300` 同样是逻辑值（物理 675x450）。把 `Config.WinW/WinH`（450/550）原样传给 `WinMove`：宽度撞上 `MinSize` 被拒绝、高度却通过，窗口被压矮（实测 `881` → `550`）。**尺寸交给 AHK 按 DPI 自行决定**（`WinMove` 的 `Width/Height` 留空即保持不变），位置则必须按 `WinGetPos` 读到的**实际**物理尺寸算——`A_ScreenWidth - Config.WinW - 220` 会让右边缘探出屏幕 27px。另注：同一份代码里 `g.Show("w450 h550")` 也压不住尺寸，仍会被控件撑到 697×881。⚠ `Config.WinW` / `Config.WinH` 这两个字段已作为死字段删除（`tests\user_journey_driver.ahk` 曾因继续引用它们而启动失败，同步修掉了 `Show("… w" . Config.WinW …)`）—— 此处只记历史教训，别再引回这两个字段 |
| **别混用 `Gui.Move` 和 `WinMove` —— 前者收「逻辑单位」，后者收「物理像素」** | `g.Move()` 会**自动乘 DPI 比**（本机 1.5），`WinMove()` / `WinGetPos()` 一律物理像素。把 `WinGetPos` 读到的物理坐标喂给 `g.Move`，会被**二次放大**：实测 `g.Move(1629, 238)` 落到 `(2444, 357)`（1629×1.5≈2444、238×1.5=357），看起来像「Move 没生效」。**位置记忆这条链上必须全程 `WinMove`**，与 `WinGetPos` 配套 |
| **`Gui.Show("Hide")` 过的窗口，`WinGetPos` 读不到** | 用 `Show("Hide")` 建好但未显示的窗口，`WS_VISIBLE` 仍是 `0`，而 `WinGetPos` / `WinMove` **默认忽略隐藏窗口**（直接抛错）。要先 `DetectHiddenWindows(true)`；用完恢复原值（`A_DetectHiddenWindows`）免得改变其它代码的可见性语义。`BackdropFeature._Apply` 为同一个原因也开过它 |
| **异步定时器里操作窗口，窗口可能已经藏了** | AHK v2 的 `WinMove` / `WinGetPos` / `WinActivate` **默认忽略隐藏窗口**（对 `WinHide` 过的窗口抛 `Target window not found`），而 `SetTimer` 排下的复核回调跑起来时，用户很可能已经按热键把窗口收起。实测：`Alt+X` 呼出后排 350/950/1550/2150ms 四轮尺寸复核，用户在 350ms 内再按一次 → 回调里 `WinMove` 抛错 → 弹**模态框**、整个脚本卡死（热键全无反应，框还留在屏幕上）。**规则**：凡在异步回调里碰窗口，都先过一道闸 —— `DetectHiddenWindows(false)` + `WinExist` + `!DllCall("IsIconic", "ptr", hwnd, "int")`，不满足即 `return`；「窗口已被用户收起」这种判断还要**顺手停掉后续复核**（不再排下一轮 `SetTimer`），否则会反复重摆一个看不见的窗口 |
| **先 `Show` 再 `WinMove` 会让窗口「飘一下」** | `g.Show()` 先让窗口在 AHK 的默认落点露面，随后 `WinMove` 才把它挪到目标位置，中间那一帧是**可见**的（实测 `+31ms` 出现在 `(924,357)`，`+219ms` 才跳到 `(1629,238)`）。**定位要在隐藏状态下完成**：`Show("Hide")` → 量尺寸 / `WinMove` → 最后 `g.Show()` 一次性露面，实测从诞生起就只有一个位置 |
| **AHK v2 没有内置 `JSON` 对象** | `JSON.Stringify` 是 v2.1 alpha 才有的，v2.0.27 上会把它当**未赋值变量**。项目没写 `#Warn`，但 **v2 默认就开 `VarUnset` 警告且默认动作是弹模态框** —— 于是「Warning: This local variable appears to never be assigned a value. Specifically: JSON」直接卡死整个脚本，`Alt+Z` 全无反应，窗口标题是脚本名的 `#32770` 对话框挡住一切。**排查手段**：`DetectHiddenWindows(true)` 后枚举窗口找 `#32770`，再 `WinGetText` 读出正文 |
