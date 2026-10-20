# 平台能力（WorkBench/Capabilities）

> 平台能力是**跨模块复用、但不认识任何业务**的纯能力。
> 它不读 `Config` / `State`，不发 `EventBus` 事件，不调用 `LogError`，
> 也不 `#Include` 任何 `modules/*` 文件；失败时返回结构体，由调用方决定怎么处理。

---

## 1. 目录

```text
src/WorkBench/
├─ Kernel/                     骨架：生命周期 / 状态 / 事件 / 配置（冻结）
├─ Capabilities/               平台能力：纯能力，无业务、无时间、无理由
│  ├─ Placement/
│  │  ├─ RectMath.ahk          纯几何：堆叠方案、外框换算、角点、相交
│  │  ├─ WindowProbe.ahk       窗口 / 工作区事实查询
│  │  └─ PlacementExecutor.ahk 唯一搬窗口出口
│  ├─ Graphics/
│  │  └─ BackdropService.ahk   背景图图层 + 位图合成
│  └─ Shell/
│     └─ ExplorerProbe.ahk     按真实路径找资源管理器窗口
├─ Coordinator/                跨模块协调：读业务上下文、发事件、算几何
│  └─ PeerCoordinator.ahk
├─ ModuleRegistry.ahk
├─ HotkeyRouter.ahk
├─ WorkBenchUI.ahk
└─ WorkBench.ahk               组合根：装配 5 个模块
```

`Coordinator/` **不并进** `Capabilities/`：协调器必须读 `Config`、订阅 / 发布事件，
按定义就不是纯能力。目录名保留 `Coordinator`，避免无收益的重命名。

---

## 2. 四条硬边界

1. **不反向依赖**
   `Capabilities` 只能调用 Win32 / AHK 内置函数与同层能力；不得 `#Include` 或引用
   `modules/*`、`EventBus`、业务 `Config` / `State`、`LogError`。
2. **只收数据，不收业务对象**
   需要窗口就收 `hwnd`，需要尺寸就收数字 / `Rect`；不要传 `Gui` 之外的业务类，
   也不要让能力去 `State.GetEd()` 找目标。
3. **失败返回结构体**
   统一返回 `{ok: true}` / `{ok: false, reason, error?}`；不弹框、不写业务日志、
   不抛未捕获异常。调用方负责回退与记录。
4. **单位写清楚**
   `RectMath` / `WindowProbe` / `PlacementExecutor` 的坐标与尺寸**一律物理像素**，
   与 `WinGetPos` / `WinMove` 同单位。
   `BackdropService.Render(x,y,w,h)` 是唯一例外：它直接喂 `GuiControl.Move`，
   入参沿用 AHK 的**逻辑单位**；内部再用 `GetWindowRect` 读回物理尺寸来合成位图。

---

## 3. 数据契约

### Rect

```ahk
{x: 0, y: 0, w: 0, h: 0}
```

左上角坐标 + 宽高，物理像素。`w` / `h` 必须大于 0 才能进入几何计算。

### Frame

```ahk
{l: 0, t: 0, r: 0, b: 0}
```

窗口外框比「可见边界」多出来的不可见调整边框（含 DWM 阴影）。
`l` / `t` 通常为负，`r` / `b` 通常为正。由 `WindowProbe.InvisibleFrame` 实测，
不在能力层写死。

### WorkArea

```ahk
{x: 0, y: 0, w: 1920, h: 1040}
```

显示器工作区（已扣掉任务栏），物理像素。

### MoveData

```ahk
{hwnd: 0, x: 0, y: 0, w: 0, h: 0}
```

`PeerCoordinator` 通过 `Launcher.Move` / `SevenNote.Move` 广播的载荷，
也是 `PlacementExecutor.Move` 认的形状。

### Result

```ahk
{ok: true}
{ok: false, reason: "no-fit"}
{ok: false, reason: "render-failed", error: "..."}
```

`reason` 是稳定、可供调用方分支的短字符串；`error` 只用于附带底层异常文本。

---

## 4. API

### 4.1 `RectMath`（纯几何）

```ahk
RectMath.PlanStack(peerRect, workArea, noteFrame, peerFrame, opts)
```

`opts = {gap, margin, minW, minH}`，全部物理像素。

返回：

```ahk
{ok: false, reason: "bad-peer-rect" | "bad-work-area" | "bad-opts" | "no-fit"}

{ok: true,
 note:     {x, y, w, h, frame},   ; 笔记窗口可见边界
 noteRect: {x, y, w, h},          ; WinMove 用的物理外框
 peer:     "",                    ; 伙伴不需要移动
 peerRect: {hwnd, x, y, w, h}}    ; 原样带回

{ok: true,
 note:     {x, y, w, h, frame},
 noteRect: {x, y, w, h},
 peer:     {hwnd, x, y},          ; 伙伴需要下移
 peerRect: {hwnd, x, y, w, h}}
```

语义与旧 `PeerCoordinator.PlanStack` 逐项一致：

1. 方案一：伙伴原地不动，笔记填伙伴上方；
2. 方案二：伙伴已贴顶、上方放不下，则伙伴下移到底边贴工作区底，笔记仍在上；
3. 都放不下 → `{ok:false, reason:"no-fit"}`。

其它纯函数：

| 方法 | 作用 |
| --- | --- |
| `RectMath.Physical(note)` | 可见边界 → `WinMove` 认的物理外框 |
| `RectMath.Overlaps(a, b)` | 两个矩形是否相交 |
| `RectMath.CornerRect(workArea, w, h, offsetRight := 0, offsetBottom := 0)` | 贴右下角的落点 |

> `RectMath` 不判断窗口在不在、可不可见、在哪个屏 —— 那些是 `WindowProbe` 的事。

### 4.2 `WindowProbe`（窗口事实）

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `IsPlaceable(hwnd)` | `bool` | 存在 + 可见 + 未最小化；隐藏 / 最小化一律 `false` |
| `RectOf(hwnd, allowHidden := true)` | `Rect` 或 `""` | 读物理外框；默认允许隐藏窗口 |
| `InvisibleFrame(hwnd)` | `Frame` | DWM 可见边界与外框的差；拿不到时全 0 |
| `WorkAreaFor(rect)` | `WorkArea` 或 `""` | 按矩形中心点找显示器，找不到回落主屏 |
| `PrimaryWorkArea(monIdx := 0)` | `WorkArea` | 指定显示器工作区；0 = 主屏 |
| `IsUsableRect(x, y, w, h)` | `bool` | 是否与任一显示器工作区相交；过滤最小化停放位 |

`RectOf` 内部自行开关 `DetectHiddenWindows` 并恢复原值，不把全局可见性语义留给调用方。

### 4.3 `PlacementExecutor`（唯一搬窗口出口）

```ahk
PlacementExecutor.Move(hwnd, rect, allowHidden := false)
```

- `allowHidden = false`：先过 `WindowProbe.IsPlaceable`，隐藏 / 最小化窗口直接返回
  `{ok:false, reason:"not-placeable"}`；
- `allowHidden = true`：用于 `Show("Hide")` 之后的笔记窗口，但仍拒绝最小化窗口；
- 成功返回 `{ok:true}`。

失败 `reason`：`bad-input` / `bad-rect` / `not-placeable` / `not-found` /
`minimized` / `move-failed`。

`Launcher.Move` / `SevenNote.Move` 这两条**事件驱动的搬窗口**都从这里走，模块层不再各写一套
`DetectHiddenWindows` + `WinMove`。Feature 自己的首次落点（终端 / DeepSeek / 笔记窗口）
仍由各自 Feature 负责，因为它们各自带生命周期判断。

### 4.4 `BackdropService`（背景图）

```ahk
BackdropService.Attach(g, targetHwnd)
```

在 `g` 上创建承载背景图的 `Static`，并压到 `targetHwnd` 之下。
`targetHwnd` 由 Feature 传入（通常是编辑区），能力层不查 `State`。
返回 `{ok:true}` / `{ok:false, reason:"bad-target" | "attach-failed"}`。

```ahk
BackdropService.SetImage(path)
BackdropService.SetFit("cover" | "contain")
BackdropService.SetMask(hexRGB, alphaPercent)
BackdropService.SetVisible(on)
BackdropService.HasImage()
```

```ahk
BackdropService.Render(x, y, w, h)
```

`x/y/w/h` 是 `GuiControl.Move` 的逻辑单位；内部从 `GetWindowRect` 读回物理像素再合成。
返回 `{ok:true}` / `{ok:false, reason}`。`reason` 包括：

`not-attached` / `bad-size` / `no-image` / `load-failed` /
`ctrl-size-failed` / `compose-failed` / `render-failed`

> **Feature 的失败责任**：`BackdropFeature._Apply` 只有在 `Render().ok` 为真时才把编辑区
> 设为 `WS_EX_TRANSPARENT`；失败时恢复不透明、隐藏图层、清掉尺寸记忆，退回主题纯色。
> 绝不能留下「编辑区透明 + 没有图」的组合。

### 4.5 `ExplorerProbe`（资源管理器窗口）

```ahk
ExplorerProbe.ListWindows()          ; → [{hwnd, path}, ...]
ExplorerProbe.FindFor(path)          ; → hwnd；找不到为 0
ExplorerProbe.IsExplorerWindow(hwnd) ; → bool
ExplorerProbe.SamePath(a, b)         ; → bool
ExplorerProbe.NormalizePath(path)    ; → 归一化后的路径串
```

按**真实路径**找资源管理器窗口：读 `Shell.Application.Windows` 的
`Document.Folder.Self.Path`，再与目标路径做归一化比对（去两端空白与末尾反斜杠、统一大小写；
盘根 `D:\` 保留反斜杠）。

窗口标题是**文件夹名**（`Documents`、`本地磁盘 (C:)`），重名与本地化都靠不住，所以不用它。

- 失败（COM 不可用 / 遍历中途出错）返回 `0` 或已收集到的部分数组，**不抛错**；
- 没有文件夹路径的壳窗口（「此电脑」/「快速访问」/ 桌面）会被跳过；
- ⚠ 被 `WinHide` 藏起来的窗口**仍然在集合里**（实测：隐藏后 `FindFor` 照常返回原 `hwnd`），
  而 `WinExist` 在 `DetectHiddenWindows(false)` 下会返回 `0` —— 判断「这个文件夹有没有开着的窗口」
  只能走本能力，不能靠 `WinExist`；
- 本能力**只查不动**：显示 / 隐藏 / 激活都由调用方负责（`FolderWindowFeature`）。

---

## 5. 不该放进 `Capabilities` 的东西

| 东西 | 原因 | 留在哪 |
| --- | --- | --- |
| `PeerCoordinator` | 读 `Config`、订阅 / 发布事件、保存最近落位 | `WorkBench/Coordinator/` |
| `PeerLayoutService` | 带 Launcher 策略（`TargetW/H`、`Config.PlaceRight`） | `modules/Launcher/Services/` |
| `BackdropFeature` | 决策该不该铺、失败怎么回退 | `modules/SevenNote/Features/` |
| 主题 / 字体 / 保存 | 业务规则、配置、用户旅程 | 对应 Feature / Service |
| `HotkeyRouter` | 应用级热键注册（上下文名由各模块 `GetContexts()` 提供） | `WorkBench/` |

`PeerLayoutService` 只把通用的 `IsPlaceable` / `RectOf` / `CornerRect` 内部委托给能力层；
`TargetW` / `TargetH` 与 `Config.PlaceRight` 仍由它自己解释。

---

## 6. 调用方向

```text
Feature / Module
      │
      ├──► Capability（RectMath / WindowProbe / PlacementExecutor / BackdropService）
      │         │
      │         └──► Win32 / AHK 内置
      │
      ├──► Service（业务策略）
      └──► Kernel（State / EventBus / Config）

Coordinator
      ├──► Capability
      ├──► Config
      └──► EventBus
```

- `Capability` **不反向**调用 `Feature` / `Service` / `Coordinator`；
- `Feature` 之间仍然零调用，跨模块通过 `EventBus`；
- `Capability` 层内部也不互相发事件；需要组合时由调用方按顺序调用。

---

## 7. 验证清单

改完能力层至少跑三条：

1. **纯几何对拍**：`RectMath.PlanStack` 覆盖
   伙伴在下 / 伙伴贴顶下移 / 放不下 / 副屏 / 100% 与 150% DPI 的最小尺寸；
2. **能力独立性**：`Capabilities` 目录内不得出现 `State.` / `Config.` /
   `EventBus.` / `LogError(` 的**调用**（注释里的说明不算）；
3. **真机启动**：根启动器 `SevenWork.ahk` 用 `/ErrorStdOut` 起来，
   `stderr` 为空、`_error.log` 无新增，再按 `Alt+Z` / `Alt+T` 看窗口与主题。

语法预检的 `ExitApp()` 注入**抓不到 class 体内错误**，必须再做真机启动；
具体命令见 `.clinerules/04-workflow.md`。

---

## 8. 当前边界说明

- `WorkBench.ahk` 仍硬编码模块清单（SevenNote / Launcher / KeysInput / Text / Folders），
  本轮不改成 `WorkBench.Init(modules)`；
- `HotkeyRouter` 的上下文**已改为表驱动**（加 Text 模块时一并做的）：注册哪些 ctx
  由各模块 `GetContexts()` 决定，Router 里不再有 `global` / `editor` / `search` 字面量。
  改之前新模块加上下文必须回来改 Router，漏改的后果是它的 `Esc` / `Enter` 一条都不注册；
  现在 `_ApplyContext` 按表查、`RegisterAll` 遍历 contexts 的键，新 ctx 自动生效。
  它仍属于应用级机制，不在能力层；
- `PeerCoordinator.GetLastNote/GetLastPeer` 暂无调用方，保留给探针与后续协调；
  若确认不需要，可单独删除，不影响能力层。
