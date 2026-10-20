# 02 · 架构约定（分层 + 组合根）

## 铁律

```
┌─────────────────────────────────────────────────────┐
│ FEATURE  功能层（21 项，按用户旅程排列）             │
│  · Feature 之间零调用，通过 EventBus 通信            │
│  · 可插拔：删除任一 Feature 不影响其他               │
├─────────────────────────────────────────────────────┤
│ SERVICE  服务层（业务策略，可读 Config / State）      │
│  · 被多个 Feature 共用                               │
├─────────────────────────────────────────────────────┤
│ CAPABILITY 平台能力（WorkBench/Capabilities/）        │
│  · 纯能力：不读 Config / State，不发 EventBus         │
│  · 只收 hwnd / 数字 / Rect，失败返回 {ok, reason}     │
│  · 不认识 modules/*，不调用 LogError                  │
├─────────────────────────────────────────────────────┤
│ KERNEL   骨架层（生命周期 / 状态 / 事件 / 配置）      │
│  · 冻结，只加不改                                    │
└─────────────────────────────────────────────────────┘

依赖方向：
  Feature / Module → Service → Kernel → OS
  Feature / Module → Capability → OS
  Coordinator → Capability + Config + EventBus
严禁反向：Capability 不得引用 modules/*、EventBus、业务 Config / State。

Kernel 唯一的「回头出口」是**注入**：`EventBus` 不认识 `LogError` / `Config`，订阅者出错时
调的是组合根塞进来的 `_sink`（`EventBus.SetErrorSink(LogError)`；没注入则退回 `OutputDebug`）。
将来 Kernel 里任何需要「向上报告」的场合都照此办理 —— **不要在 Kernel 里直接写 `LogError(...)`**。
⚠ 调用属性里存的函数**必须先取到局部变量**：`sink := this._sink` 再 `sink(msg)`；AHK v2 的
`obj.prop(args)` 走方法查找、不会调用属性里的 `Func`（实测抛 `Too many parameters passed to function`，
且会被包裹它的 `try` 吞掉），详见 `03-ahk-v2` 的踩坑表。
```

`Coordinator/` 是跨模块协调（读业务上下文、发事件、算几何），**不属于** Capability；
`PeerCoordinator` 保留在 `Coordinator/`，只把纯算式委托给 `RectMath` / `WindowProbe`。

## 源码目录

运行代码统一收在 **`src/`**：

- 根 `SevenWork.ahk` 只是启动器，`#Include src\SevenWork.ahk`；
- 组合根在 `src/SevenWork.ahk`，平台层在 `src/WorkBench/`，
  模块在 `src/modules/<模块名>/`；
- 平台能力在 `src/WorkBench/Capabilities/<领域>/`（当前 `Placement/` 与 `Graphics/`）；
  跨模块协调在 `src/WorkBench/Coordinator/`；
- `src/SevenWork.ahk` 内部的 `#Include WorkBench\...` / `modules\...` 是相对路径，
  以**该文件所在目录**为基准，别改成从项目根起算。
- 正常双击根启动器时 `A_ScriptDir` 仍是项目根，开发版 `.logs\` 不变；直接运行
  `src\SevenWork.ahk`（调试 / 探针）时 `.logs\` 会落到 `src\`，见 `.clinerules/04`。

## 改动原则

1. **不动 Kernel；业务规则只加 Feature，纯平台能力只加 Capability。**
2. Feature 之间**零调用**，一律通过 `EventBus.Emit` 通信。
3. 可插拔：删除任一 Feature 不得影响其他 Feature。
4. 依赖方向**严禁反向**（Kernel 不许调 Service，Service 不许调 Feature，
   Capability 不许调 modules / EventBus / 业务 Config / State）。
5. **能力层只收数据**：hwnd、数字、`Rect`；失败返回 `{ok:false, reason}`，
   由 Feature / Module 决定回退与日志。详细契约见 `docs/CAPABILITIES.md`。

## 加新模块的标准步骤（两处）

模块 = 计算机能力面上的一个占位（有窗口 = 容器，无窗口 = 加速器）。
新建 `src/modules/<名字>/<名字>Module.ahk` 后，**改两处**：

```ahk
#Include modules\<名字>\<名字>Module.ahk   ; ① src\SevenWork.ahk 的 #Include 区
ModuleRegistry.Register(<名字>Module)      ; ② WorkBench.Init() 内
```

模块自己的 `Services/` / `Features/` 也要在**自己那一块** `#Include`（照 Text / Folders 的写法：
Service 行、Feature 行、Module 行，**模块类必须最后引入**）。除此之外组合根不动 ——
启动 / 热键 / 兜底全由 `ModuleRegistry` 与 `HotkeyRouter` 遍历。

模块类约定：`static Id` / `static Name` / `static Init()`（必填），
`GetHotkeys()` / `GetContexts()` / `GetMetadata()` / `GetSettingsSpec()`（可选）。

`GetMetadata()` 返回 `{name, desc, order, hotkeys}` —— `Alt+S` 面板左列的名字、排序、
以及该页的热键清单都从这来；不实现会退回「用 `Id` 当名字、`order = 100`」。

热键上下文**由模块自己声明**（`GetContexts()` 返回 `{名字: 表达式}`），不要再改 `HotkeyRouter` ——
v2.6 起它遍历各模块报上来的名字来注册。⚠ 声明了却没人提供实现的 ctx，它的热键**一条都不注册**
并写 `_error.log`；让它退回 `HotIf()` 更糟 —— 那就把 `Esc` / `Enter` 变成全系统热键了。

- `Init()` 只做「内部就绪」——订阅事件、准备 Feature，**不碰窗口**；
- `Start()`（可选）做「对外可见」——加载内容、恢复配置，**必须晚于热键注册**
  （否则窗口先露面、热键还没就位，按 `Alt+Z` 会「没反应」）。

组合根不再逐个手写模块名：`ModuleRegistry.InitAll()` → `HotkeyRouter.RegisterAll()` →
`ModuleRegistry.StartAll()`。某个模块 `Init` 抛错只记 `_error.log` 并在 `_failed` 里留名
（**它的热键不注册**），其余模块照常启动 —— 失败不带走别人。

### 面板布局：侧栏 / 内容区

`WorkBenchUI` 是**唯一的平台界面**，结构照通用控制面板（VS Code 设置 / Windows 设置）来。
面板 940x700，分三块底色：**侧栏**（`F2E8D2`，x0 w232 整高）、**内容底**（`FFF8E7`）、
**底部操作栏**（`F2E8D2`，y648 起，与侧栏同色 —— 左边一条竖带 + 底下一条横带，把内容框住）：

```
┌ 侧栏 x0 w232 ─────┐  ┌ 内容区 x256 w668 ───────────────────┐
│ 导航              │  │ 全部热键                            │  ← 页眉 s12 bold
│ ┌────────────────┐│  │ 所有模块的热键汇总 · 按分组排列      │  ← 副标题 s9 灰
│ │≡ 全部热键    42││  │ ┌──────────────────────────────────┐│
│ │ 笔记          27││  │ │【分组】热键清单（只读可滚动）      ││
│ │ 键位           1││  │ │                                  ││
│ │ 外部程序       2││  │ └──────────────────────────────────┘│
│ │ 文件夹         3││  │ 状态行                SevenWork v2.7 │
│ │ 文本           7││  │ 设置标题 / 说明                     │
│ └────────────────┘│  │ Alt+1 → [__________] [浏览…]        │
│ 5 个模块 · 共42条 │  │ ─────────────────────── [ 保存设置 ] │  ← 底栏 y648
└───────────────────┘  └─────────────────────────────────────┘
```

- **标题分两级**：页眉（`s12 bold`，模块名 / 「全部热键」）+ 副标题（`s9` 灰，模块 `desc`）。
  别挤回一行 —— 一行里两种字号层级就没了。正文里**不重复**模块名与描述。
- **`≡ 全部热键` 是视图，其余是模块** —— 靠 `≡` 前缀 + 第二列的「本页热键条数」区分。
  视图的条数含**平台级**热键（`Alt+S` / `Alt+T` 等），所以比各模块之和多；页脚用同一口径，
  别一处写 40、另一处写 42。
- 导航两列：名称 / 条数（`ModifyCol(2, "40 Right")`），去掉表头（`-Hdr`）；
  页面只有一两个字时，第二列是唯一能告诉用户「这页有多少内容」的信息。
- **顺序 = `order` 升序，同 `order` 按 `Id` 字典序**（`_BeforeItem`）——
  别让它取决于 `Map` 的遍历顺序，那会在加模块时悄悄变。
- 模块 `Init` 失败**仍占一行并标 `(失败)`**，点进去写明「热键未注册、修复后重启」。
  让失败的模块从列表里消失，等于让用户以为模块没了。
- **切页只有一条路径 `_GoToRow(row)`**：鼠标点 / 键盘上下 / `Panel.OpenRequested` 定位全走它。
  ⚠ 它先写 `_currentModule` 再 `_lv.Modify(...)` —— `Modify` 会**同步**触发 `ItemSelect`，
  先写好状态 `_OnSelect` 就直接返回，不会渲染两遍。
- 几何常量集中在类顶：`_Right`(256) / `_RightW`(668) / `_specY`(548) / `_specRowH`(34)。
  ⚠ `_Right` = 侧栏宽 232 + 空隙 24；改侧栏宽度**必须同步改 `_Right`**，否则右列压到侧栏上。
- **分区靠底色，不靠线**：
  - **别画 1px 竖分隔线** —— `x224 w1` 那条在 150% DPI 下被 `ListView` 自身的凹陷边框吞掉，
    换 `D8CDB0` 也一样看不见（删掉之前实测过）。
  - **别用 `BackgroundTrans` 的 Text** —— 透明 Text 每次重绘都要下面的控件先擦一遍，
    尺寸一变就留残影。侧栏里的 `导航` / 页脚、设置字段的标签，一律把背景**写成侧栏色**
    （`BackgroundF2E8D2`）而不是透明。
  - 侧栏色比窗口底**深两档**（`FFF8E7` → `F2E8D2`）：只差一档实测几乎看不出分区。
- **底部操作栏 `y648`**：底带从 `x232` 铺到窗口右边，保存按钮（`y656`）嵌在里面。
  没有它，按钮就「浮在空气里」，尤其没有设置字段的页、页尾一大片空白收不住。
  ⚠ 它是**后建**的 Text，只会盖住 `y648` 以下 —— 设置字段最后一行到 642，不会被压住；
  再加第 4 个字段前先确认 `548 + 4x34 + 26 < 648`。

### 模块设置：`GetSettingsSpec()`

模块想让用户在 `Alt+S` 面板里调参数，就实现它并返回**数据描述**，而不是控件：

```ahk
static GetSettingsSpec() {
    return {
        title:  "文件夹槽位",
        hint:   "热键固定，指向哪个目录可以随时换；留空表示该槽位未启用。",
        fields: [{key: "Slot1", label: "Alt+1 →", kind: "folder"
            , value: FolderSlotService.Get(1)}],
        apply:  (values) => FolderSlotService.SaveAll(values)
    }
}
```

- 平台只认 `{label, kind, value}` 三个字段，**不认识任何业务名词**（「槽位」是 Folders 自己的词）；
  `kind` 目前支持 `"folder"`（输入框 + `DirSelect`，带 `BIF_NEWDIALOGSTYLE` 地址栏）与
  `"text"`（缺省）；
- 字段还可以给**可选的 `placeholder`** —— 空输入框里的灰字提示（`EM_SETCUEBANNER`）。
  只显示、**不进 `Value`**：不填直接保存写进去的仍是空串；
- `apply` 收到**按声明顺序排好的值数组**，由模块自己落盘并返回 `true` / `false`；
- 保存成功后平台会重画本页 —— 模块可以在 `apply` 里把值规整成最终形态（去尾斜杠 / 空串归一）；
- 切页时平台**销毁上一页的控件再重建**，模块只管给出当前值，不用管生命周期；
  ⚠ 销毁走 `DllCall("DestroyWindow")`（`_KillCtrl`）—— **AHK v2 的 `Gui.Control` 没有
  `Destroy()` 方法**，写成 `ctrl.Destroy()` 会被 `try` 静默吞掉，表现为「切到没有设置的页，
  上一页的字段还挂着」。详见 `03-ahk-v2` 的踩坑表。
- 保存按钮自带三段反馈（`保存设置` → `保存中…` → `✓ 已保存`），模块不用自己造；
- ⚠ 平台调用 `apply` 时先取局部变量再调（`fn := spec.apply` → `fn(values)`）：
  AHK v2 的 `obj.prop(args)` 走方法查找，属性里存的 `Func` 不会被调用（见 `03-ahk-v2`）。
- ⚠ **`GetMetadata()` 必须给 `name`**：拿不到就退回用 `Id`（英文），面板左列会冒出
  `Text` 这种与其它中文条目格格不入的名字。`desc` 统一成「一句话功能 · 主热键」。

## 加新功能的标准步骤

0. 先判断是不是**跨模块复用的纯平台能力**：是 → 放 `WorkBench/Capabilities/<领域>/`，
   返回结构化结果；不是 → 继续下面。
1. 在 FEATURE 层新增一个 class
2. 在所属模块的 `GetHotkeys()` 里加热键（平台级热键归 `WorkBench.GetHotkeys()`；
   `HotkeyRouter` 注册与 `Alt+S` 帮助共用这份数据）
3. 通过 `EventBus.Emit` 通知结果

参考实现（README「开发指南」原文）：

```ahk
class ExportFeature {
    static ExportHtml() {
        hwnd := State.GetEd()
        rtfPath := NoteStoreService.RtfPath(State.GetDate())
        htmlPath := NoteStoreService.TempDir() . "\export.html"
        cmd := '"' . Config.PandocPath . '" "' . rtfPath . '" -o "' . htmlPath . '"'
        RunWait(A_ComSpec . ' /c "' . cmd . '"', , "Hide")
        Run(htmlPath)
    }
}
```

在模块的 `GetHotkeys()` 里加一行即可（`{ctx, key, group, line, fn}`）—— 不需要改任何其他
Feature，也不需要改组合根或帮助函数。

## 加新主题

`ThemeService.Themes` 数组加一行：

```ahk
{name: "暗夜黑", win: "1E1E1E", edBg: "252526", text: "D4D4D4", dim: "808080"},
```

加完 `Alt+T` 自动循环到新主题，无需改别处。

### 带背景图的主题

多一组可选字段：`bg`（图片绝对路径）、`bgAlpha`（压暗遮罩 0-100）、
`bgFit`（缩放模式，可选，缺省 `"cover"`）。

```ahk
{name: "极光", win: "0D0F14", edBg: "0D0F14", text: "F5F9FF", dim: "9FAABC"
    , bg: "D:\Pictures\your-wall.png"
    , bgAlpha: 0}
```

竖版 / 人物图**别加 `bgFit: "contain"`，改成烘焙时按编辑区比例裁好**（编辑区实测 0.917）。
下面的「金克斯」是**暗图 + 亮字**的完整一套（裁剪与亮部滚降都烘进图片，`bgAlpha` 保持 0）：

```ahk
{name: "金克斯", win: "0B1624", edBg: "0B1624", text: "EAF2FF", dim: "93AACB"
    , bg: "D:\Pictures\jinx.png"
    , bgAlpha: 0
    , bgFit: "cover"}
```

- **`bg` / `bgAlpha` 必须成对**：`BackdropFeature._Sync()` 见 `bg` 就读 `t.bgAlpha`，
  缺了会抛「属性不存在」。
- **`bgFit` 是可选字段**：`BackdropFeature._Sync()` 用 `t.HasProp("bgFit")` 守卫，
  不写就走 `cover`（老主题含星空行为不变）。只有 `"cover"` / `"contain"` 两个值。
- **竖版人物图走「先裁再铺」，不用 contain**：编辑区 0.917、竖图常见 0.676 —— contain 会把
  人物缩进中间、两侧留一大条底色。用 `rebake-backdrop.ps1` 的 `-CropX / -CropW / -CropY`
  裁成 0.917 再铺 cover，人物就占满整块、一个细节不浪费。
- **`contain` 必须铺底色**：留边会露 GDI 未初始化的位图内存（花屏/黑块）。
  `_Compose` 内置 `FillRect` 铺 `_maskColor`，**只在 contain 分支执行**，cover 不受影响。
- **追加元素别漏逗号**：前一条结尾要补 `},`。漏了 AHK 报 `Unexpected "{"` 并弹错误框
  （标题是脚本名），窗口再也出不来。**注入 `ExitApp()` 的语法预检查不出这种错**，见 04-workflow。
- **只能追加到数组末尾**：`ThemeIndex` 存下标，插中间会顶掉老用户当前的主题。
- **配色从图取**，用 `tools\pick-theme-colors.ps1`（`win` = 图均色 × 0.55；
  星空主题即均色 `#171C25` → `#0D0F14`）。均色偏哪个色相，`win` 就往那儿再偏一档
  （金克斯冷调 → `#0B1624`），文字带同一色相（`#EAF2FF` 是偏蓝的白，不是纯白）。
- **`edBg` 兼两用，必须和图的明暗同档**：它既是遮罩色（`SetMask`）又是 `contain` 留边色。
  暗图配暗 `edBg`、亮图配亮 `edBg` —— 差得远整张图就发灰、留边像贴了张纸条。
- **先量图，再决定动不动它**（判据是 WCAG 4.5:1）：

  | 图的情况 | 字色 | 图怎么处理 |
  | --- | --- | --- |
  | 均亮 ≤ 90、亮区零星 | 近白（`#F5F9FF` / `#EAF2FF`） | **什么都不做** —— 原图直出 |
  | 亮区成片（脸、灯、白墙） | 近白 | 只**滚降亮部**：`V > Knee` 线性压到 `HiMax` |
  | 均亮 ≥ 130（真亮图） | 取自图色相的深色（`#12172B`） | 抬亮到背景 ≥ 128，或直接用亮图 |

  实测两条线：亮字要求背景 **≤ 118**，深字要求 **≥ 128**。
- **⚠ 绝不要为了配深字而整体提亮暗图**：那正是「金克斯」翻过一次车的地方 —— 抬到均亮 170
  后整图"蒙了层灰"、与原图完全不像。**提亮 ≠ 清晰，它是把原图洗白。**
- **动明暗只能在 V（明度）上等比缩放，绝不混色**：混白是加法，会把饱和度砍掉近一半
  （实测最彩 5% 像素 45.8% → 26%）；等比缩放（`c' = c × V'/V`）下 `S = 1 - min/max` 不变，
  饱和度一丝不掉（同一次对照里混白那路掉到 26%，等比缩放这路 45.8% → 45.1%）。别指望运行时
  遮罩替代它 —— 遮罩按色混合，同样减饱和。
- **烘图三步一步都别省**：按编辑区比例裁（`-CropX/-CropW/-CropY`）→ 缩到 2400 宽 + V 空间
  色调（`-Lift` 提暗部 / `-Knee`+`-HiMax` 压亮部，**默认全关 = 原图直出**）→ 在**成品尺寸**上
  unsharp（默认 `-SharpenRadius 4`，**不随缩放比换算** —— 因为它作用在成品像素上，
  等效于相对源图把半径放大了 `源图宽 ÷ 成品宽` 倍）。都由 `tools\rebake-backdrop.ps1` 跑完；
  改里面的 C# 逻辑记得**递增类名**，见 04-workflow。
- **判据要用「网格 p90 / 亮区占比」，别用均色**：均色会骗人。12x12 网格的 p90 能把成片亮块
  钉到具体行列（金克斯的亮块集中在脸/手那一带和右侧白墙），据此决定裁哪块、`Knee` 定在哪。
  验收看两条：成品「亮部 p95」应明显低于原图，而**饱和度一丝不掉**、均亮度只小幅下移
  （当前成品 `-Knee 138 -HiMax 200`：p95 141 → **177**（原图 214）、饱和 42.2% → **44.1%**、
  均亮度 83.9 → 79.6）。
- **标题栏自动跟主题色**：`ThemeService._SetDarkTitleBar` 先按 `win` 加权亮度 < 128 决定
  immersive dark mode，再用 Win11（build 22000+）的 `DWMWA_CAPTION_COLOR / TEXT_COLOR /
  BORDER_COLOR`(35/36/34) 把标题栏底色 / 标题文字 / 外框染成 `win` / `text` / `win`。
  Win10 上后三个属性不存在，`DllCall` 静默失败、退回系统配色 —— 不必写版本判断。
  实测 Win11 26200 上标题栏像素精确等于主题 `win`（`#0B1624`）。
- **编辑区文字随窗口拉伸「时隐时无」＝ 铺图时机问题**：背景层是兄弟 Static、编辑区带
  `WS_EX_TRANSPARENT`，背景层每重画一次文字就被作废一次；`WM_SIZE` 拖动时每秒几十次，
  而每帧重铺一次 2400px 源图（HALFTONE 多级对折，几十毫秒）会灌满绘制队列。`BackdropFeature`
  用 `_ScheduleRender()`（`SetTimer -80` 合并抖动）+ `_RenderNow()`（同矩形直接跳过，真重铺过
  才 `RedrawWindow(ed, INVALIDATE|ERASE)`）解决；`_Apply` 走 `_RenderNow(true)` 绕过防抖。
  实测 1361x1084 连打 40 次 resize 共 392ms、前后截图逐像素一致。
- **图与浓淡都写在主题自己的 `bg` / `bgAlpha` 上**（v2.4.3 起删掉了那对全局覆盖键
  `[Appearance] BackdropImage` / `BackdropOpacity`）—— 多套图主题才能各调各的。

完整步骤、图片规格与压暗三法见 README「开发指南 → 添加带背景图的主题」。
