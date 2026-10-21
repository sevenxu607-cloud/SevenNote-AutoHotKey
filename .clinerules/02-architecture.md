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
- 平台能力在 `src/WorkBench/Capabilities/<领域>/`（当前 `Placement/` / `Graphics/` / `Shell/` / `Document/`）；
  跨模块协调在 `src/WorkBench/Coordinator/`；
- `src/SevenWork.ahk` 内部的 `#Include WorkBench\...` / `modules\...` 是相对路径，
  以**该文件所在目录**为基准，别改成从项目根起算。
- 工作树根有 `_dev.flag` 时是**开发身份**（`Config.IsDev`），`.logs\` 落该工作树根；
  直接运行 `src\SevenWork.ahk`（调试 / 探针）时落 `src\.logs\`，见 `.clinerules/04`。
  主目录（日用、无 flag）不写 `.logs\`，日志随配置落 `%AppData%\SevenWork\`。

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

`src\WorkBench\Services\ThemeService.ahk` 的 `Themes` 数组加一行（**追加到末尾**）：

```ahk
{name: "暗夜黑", win: "1E1E1E", edBg: "252526", text: "D4D4D4", dim: "808080"},
```

加完 `Alt+T` 自动循环到新主题，无需改别处。**只给 4 个基色**（`win` / `edBg` / `text` /
`dim`）就够 —— `accent` / `border` / `panel` / `codeBg` 由 `Palette()` 按明暗派生；
要覆盖就在条目里自带同名字段。派生只写一处，前端 `--sw-*` 与 AHK 窗口拿的是同一份结果。

⚠ **主题表目前只有「纯米黄」一套**（护眼绿 / 纸白 / 星空 / 金克斯暂时下线）。只有一套时
`ThemeService.Next()` 是**空操作**：不写配置、不发 `Theme.Changed`；表里有第二套就自动恢复。
老配置的下标由 `_MigrateIndex()` 一次性归 1 并写回（`[Appearance] ThemeSchema=3`）。

### 带背景图的主题

> ⚠ **当前暂缓**：主题表里没有带 `bg` 的条目（星空 / 金克斯已下线），铺图机制
> （`BackdropService` / `BackdropFeature`）代码仍在。要接回来就按本节加一条 —— 别只在表里
> 塞 `bg` 而不管前端：`bg` / `bgAlpha` / `bgFit` 已推到前端，前端消费仍在打磨。

多一组可选字段：`bg`（图片绝对路径）、`bgAlpha`（压暗遮罩 0–100）、`bgFit`（可选，缺省 `cover`）。

```ahk
{name: "金克斯", win: "0B1624", edBg: "0B1624", text: "EAF2FF", dim: "93AACB"
    , bg: "D:\Pictures\jinx.png", bgAlpha: 0, bgFit: "cover"}
```

**必须守住的几点**（完整配方与实测账见 [`docs/THEME-IMAGES.md`](../docs/THEME-IMAGES.md)，
最短路线见 [`05-theme-image.md`](05-theme-image.md)）：

- **`bg` / `bgAlpha` 成对**：`BackdropFeature._Sync()` 见 `bg` 就读 `t.bgAlpha`，缺了抛「属性不存在」；
  `bgFit` 可选（`HasProp` 守卫），只有 `cover` / `contain` 两个值。
- **竖版 / 人物图先裁再铺，别用 `contain`**：按编辑区比例 0.917 裁好再 cover；`contain` 会缩进中间、两侧留底色。
- **`contain` 必须铺底色**：留边否则露出 GDI 未初始化位图（花屏）；`_Compose` 的 `FillRect` 只在 contain 分支执行。
- **`edBg` 兼两用**（遮罩色 + contain 留边色），必须与图的明暗同档。
- **配色从图取**（`tools\pick-theme-colors.ps1`，`win` = 均色 × 0.55）：暗图配近白字、亮图配深字。
  判据 WCAG 4.5:1 —— **亮字要背景 ≤ 118，深字要 ≥ 128**。
- **绝不为配深字整体提亮暗图**（那是把原图洗白）；动明暗只在 V 空间等比缩放 —— 混白会砍掉近一半饱和度。
- **烘图三步一步别省**：按 0.917 裁 → 缩到 2400 宽 + V 空间色调 → 成品尺寸 unsharp（`rebake-backdrop.ps1` 全包）。
  改脚本里的 C# 逻辑记得递增类名（见 `04-workflow`）。
- **只能追加到数组末尾**（`ThemeIndex` 存下标）；前一条结尾补 `},` —— 漏逗号报 `Unexpected "{"`，方案 A 预检查不出。
- **标题栏自动跟主题色**：`UiPaint.TitleBar` 按 `win` 亮度 < 128 决定 dark mode，Win11 用
  `DWMWA_CAPTION_COLOR` 染色（Win10 上 DllCall 静默失败、退回系统配色，不必判断版本）。
- **拉伸时文字「时隐时无」= 铺图时机**：`_ScheduleRender()`（`SetTimer -80` 合并抖动）+ `_RenderNow()`
  （同矩形跳过，真重铺才 `RedrawWindow`）；`_Apply` 走 `_RenderNow(true)` 绕防抖。
- **图与浓淡写在主题自己的 `bg` / `bgAlpha` 上**（v2.4.3 起删掉了全局覆盖键 `[Appearance] BackdropImage`）。
