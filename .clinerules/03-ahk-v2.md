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
| AHK v2 的 `<` `>` 是数值比较 | 字符串比较用 `StrCompare` |
| AHK v2 的 `<=` / `>=` 遇**空字符串**会抛错 | 报 `Expected a Number but got an empty string`；数值比较前先 `IsNumber()` 守卫（`State` 未初始化的记忆值就是 `""`，实测踩到） |
| `EM_SETSEL` / `EM_GETSEL` 要用 DllCall | 内置 `SendMessage` 对 INT 参数有歧义 |
| `FINDTEXTEXW` 读偏移 16/20（chrgText） | 误读 0/4 会导致搜索只找到 1 个 |
| 32 位编译导致 RichEdit 字符格式异常 | **必须 64 位编译** |
| `FileInstall` 必须写在一行 | 折行会导致打包出 0KB 空文件 |
| `FileExist` 返回 `"A"` 不是 `true` | 断言需 `!!` 转换 |
| **最小化窗口的 `IsWindowVisible` 仍是 `1`** | 判断“窗口是否在显示”必须用 `IsWindowVisible && !IsIconic`。最小化窗口的 `WinGetPos` 会返回 `-32000` 一类**屏幕外停放位**（按 DPI 缩放显示为 `-21333` 等）；把这种坐标记下来再 `WinMove`，窗口就被永久搬到看不见的地方，`Alt+Z` 再也呼不出。**记录窗口位置前必须校验它落在某个屏幕工作区内**（`MonitorGetWorkArea`），并给 `WinRestore` 兜底 |
| **`WinMove` 收「物理像素」，而 `Config` 里的尺寸是「逻辑单位」** | 本机 150% 缩放（`A_ScreenDPI = 144`、`A_ScreenWidth = 2560`）下，`Gui` 控件坐标按 DPI 放大 1.5 倍，**窗口最小尺寸由控件固有尺寸决定**，`+MinSize450x300` 同样是逻辑值（物理 675x450）。把 `Config.WinW/WinH`（450/550）原样传给 `WinMove`：宽度撞上 `MinSize` 被拒绝、高度却通过，窗口被压矮（实测 `881` → `550`）。**尺寸交给 AHK 按 DPI 自行决定**（`WinMove` 的 `Width/Height` 留空即保持不变），位置则必须按 `WinGetPos` 读到的**实际**物理尺寸算——`A_ScreenWidth - Config.WinW - 220` 会让右边缘探出屏幕 27px。另注：同一份代码里 `g.Show("w450 h550")` 也压不住尺寸，仍会被控件撑到 697×881 |
