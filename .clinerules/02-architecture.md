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
