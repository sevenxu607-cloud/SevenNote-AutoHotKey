# SevenWork 工作台化改造计划

> 状态：设计定稿，Phase 1 进行中
> 最后更新：2026-10-19
> 目标：把单文件 `SevenNote.ahk` 拆成「平台 + 三个同级模块」，平台管生命周期 / 热键路由 / 帮助，
> 模块各自持有 Service 与 Feature；模块之间零调用，跨模块只走 EventBus。

---

## 0. 命名与目录

| 层级 | 名字 |
| --- | --- |
| 项目 / 主脚本 | **`SevenWork`** / `SevenWork.ahk` |
| 工作台层 | **`WorkBench/`** |
| 笔记模块 | **`SevenNote`** |
| 外部程序模块 | **`Launcher`** |
| 键位模块 | **`KeysInput`** |

```
SevenWork/
├── SevenWork.ahk              # 组合根：只装配 + 注册模块
├── WorkBench/
│   ├── Kernel/                # Config / ConfigService / EventBus / State
│   ├── ModuleRegistry.ahk
│   ├── HotkeyRouter.ahk
│   ├── WorkBenchUI.ahk
│   └── Coordinator/PeerCoordinator.ahk
└── modules/
    ├── SevenNote/
    ├── Launcher/
    └── KeysInput/
```

> 改名（脚本名 / `AppName` / AppData / 仓库名）统一放到 Phase 6，不和拆模块同时做。

---

## 1. 模块归属表

| 归属 | 内容 |
| --- | --- |
| `WorkBench/Kernel` | `Config`、`ConfigService`、`EventBus`、`State` |
| `WorkBench` | `ModuleRegistry`、`HotkeyRouter`、`WorkBenchUI`、`PeerCoordinator` |
| `SevenNote` | 7 个 Service + `StatusBar` + 18 个 Feature |
| `Launcher` | `PeerLayoutService`、`PowerShellFeature`、`DeepSeekFeature` |
| `KeysInput` | `CapsLockFeature` |

**SevenNote 的 7 个 Service**：`EditorService`、`ClipboardService`、`NoteStoreService`、
`PandocService`、`ThemeService`、`FontService`、`BackdropService`。

**SevenNote 的 18 个 Feature**：`WindowFeature`、`PasteFeature`、`LineEditFeature`、
`UndoFeature`、`LoadFeature`、`SaveFeature`、`AutoSaveFeature`、`TimestampFeature`、
`SearchFeature`、`StatFeature`、`CaretFeature`、`DateSwitchFeature`、`DateJumpFeature`、
`TitleFeature`、`GoTodayFeature`、`ThemeFeature`、`FontFeature`、`BackdropFeature`。

**平台函数**（当前在顶层，不属任何模块）：

| 现函数 | 去处 |
| --- | --- |
| `HotkeyTable()` / `RegisterHotkeys()` | `WorkBench/HotkeyRouter.ahk` |
| `ShowHelp()` / `BuildHotkeyHelpText()` | `WorkBench/WorkBenchUI.ahk` |
| `ShowStartupTip()` / `EnsureVaultConfigured()` | 平台启动段 |
| `LogError()` / `OnScriptError()` | `WorkBench/Kernel`（日志兜底） |

---

## 2. 启动顺序表

| 序 | 步骤 | 说明 |
| --- | --- | --- |
| 1 | `Config` 静态初始化 | `AppDataDir` / `ConfigPath` / `AppName` |
| 2 | `ConfigService.Init(Config.ConfigPath)` | 清空读缓存、写默认值 |
| 3 | `EnsureVaultConfigured()` + `DirCreate` | 首次运行选笔记目录 |
| 4 | `WorkBench.Init()` | 注册 Kernel、创建 Registry / Router / UI 占位 |
| 5 | `ModuleRegistry.Register(SevenNote, Launcher, KeysInput)` | 只登记，不初始化 |
| 6 | `SevenNoteModule.Init()` | GUI、`State.Set*`、`StatusBar`、18 个 Feature |
| 7 | `LauncherModule.Init()` | 伙伴窗口、`PeerLayoutService` |
| 8 | `KeysInputModule.Init()` | CapsLock 状态 |
| 9 | `HotkeyRouter.RegisterAll()` | 静态表 + 各模块 `GetHotkeys()` |
| 10 | `LoadFeature.Load()` + 主题 / 字体 / CapsLock 配置 | 恢复上次状态 |
| 11 | `ShowStartupTip()` | 启动提示 |

**模块内部顺序**：`SevenNoteModule.Init()` 里先 `WindowFeature.Init()`（它订阅伙伴窗口事件），
再 `StatusBar.Init()`、`SearchFeature.Init()`、其余 Feature；最后 `BackdropFeature.Init(g)`。
`LauncherModule.Init()` 必须在 `SevenNoteModule.Init()` 之后，确保伙伴窗口出现时笔记窗口已就绪。

> 当前组合根（`SevenNote.ahk` 4090–4220）就是这张表的基线；Phase 2 只搬位置，不改先后。

---

## 3. 热键归属表

| 模块 | `ctx` | 热键 | 注册方式 |
| --- | --- | --- | --- |
| `WorkBench` | global | `Alt+H` 平台帮助 | 静态 |
| `WorkBench` | 帮助窗口 | `Esc` 关闭帮助 | `WorkBenchUI` 自注册 |
| `WorkBench` | global | `Alt+Shift+Z` 保存并退出 | 静态（协调 `Save` + `ExitApp`） |
| `SevenNote` | global | `Alt+Z` 呼出 / 隐藏 | 静态 |
| `SevenNote` | global | `Alt+T` / `Shift+Alt+T` / `Alt+=` / `Alt+-` | 静态 |
| `SevenNote` | editor / search | `Ctrl+F`；`Enter` / `Shift+Enter` / `Esc` | 静态 |
| `SevenNote` | editor | `Ctrl+S`、`Ctrl+Z`、`Ctrl+Shift+Z`、`Ctrl+Y`、`Ctrl+D`、`Ctrl+Shift+↑↓`、`Tab`、`Shift+Tab`、`Ctrl+Shift+V` | 静态 |
| `SevenNote` | global / editor | `Alt+↑↓`、`Alt+Home`、`Ctrl+G`、`Ctrl+Shift+T` | 静态 |
| `SevenNote` | editor | `Ctrl+T`、`Ctrl+H`、`Ctrl+Shift+H` | 静态 |
| `Launcher` | global | `Alt+C` / `Alt+X` 呼出伙伴窗口 | 动态：外部窗口存在时才挂 |
| `KeysInput` | global | `Alt+Shift+C` 切换 CapsLock 层 | 静态 |
| `KeysInput` | 全局（层内） | `CapsLock` / `CapsLock+H/J/K/L` | 动态：开关时 `Add` / `Remove` |

约定：

- **静态表** = 模块 `GetHotkeys()` 返回的数组；**动态** = 模块调 `HotkeyRouter.Add/Remove`；
- `ctx` 表达式由模块 `GetContexts()` 提供（`editor` / `search`），Router 只负责 `HotIf`；
- 帮助窗口的 `Esc` 不进模块表，由 `WorkBenchUI` 自己注册与注销；
- 注册顺序仍按 global → editor → search，最后 `HotIf()` 复位。

---

## 4. 模块接口与 Router

```
class SevenNoteModule {
    static Id := "SevenNote"
    static Name := "笔记"
    static Init()
    static GetHotkeys()   ; 数组：{ctx, key, group, line, note?, fn}
    static GetContexts()  ; Map: "editor" / "search" → 表达式
    static GetMetadata()  ; 帮助用：{name, desc, hotkeys}
    static Shutdown()
}
```

- AHK 没有接口，`ModuleRegistry` 用 `HasMethod` / `HasProp` 校验必需成员；
- `GetHotkeys()` 里的 `fn` **必须用 lambda 或 `.Bind(类对象)`** —— 探针实测裸引用
  `Probe.Toggle` 会报 `Missing a required parameter`（`this` 丢失）；
- `HotkeyRouter` API：`RegisterAll()`、`Add(key, fn, ctx)`、`Remove(key)`、
  `Refresh(module)`、`Reset()`；
- Router 不 import 任何模块内部类；模块只调 Router 的公开 API。

---

## 5. 改造阶段

### Phase 0 · 地基（已完成）

已完成：

- 命名定稿：`SevenWork` / `SevenWork.ahk` / `WorkBench/` / `SevenNote` / `Launcher` / `KeysInput`；
- 删除 `tests/`（提交 `c864226`），端到端测试待重构后按模块接口重建；
- 修正 `.clinerules/04` 关于 auto-execute 的错误表述；
- 四个探针通过：auto-execute 边界、静态方法 `this`、`#Include` 顺序、`Module.Init()` 生命周期；
- 本文档入库；Phase 1 的 `#Include` 清单与文件命名已定稿。

### Phase 1 · 平台骨架（行为不变）

已完成：

- 4 个 Kernel 类搬入 `WorkBench/Kernel/`，主脚本原位置改为 `#Include`（当前 4228 行）；
- 语法检查（Kernel 单独 + 主脚本 `#Include` 路径）与沙箱启动（`#SingleInstance Off`，
  `ShowStartupTip()` → `ExitApp()`）均通过：stderr 为空、`_error.log` 无新增。

待做：

- 新增 `ModuleRegistry` / `HotkeyRouter` / `WorkBenchUI` 占位 / `Coordinator` 占位；
- 主脚本只保留 `#Include` + 装配；`HotkeyRouter` 先包住现有 `HotkeyTable()`，
  **注册结果与 HEAD 完全一致**；
- 验收：启动、`Alt+Z`、`Alt+H`、全部热键、保存 / 主题与改造前一致；`_error.log` 为空。

### Phase 2 · SevenNote 模块化

- 搬 7 个 Service + `StatusBar` + 18 个 Feature 到 `modules/SevenNote/`；
- `SevenNoteModule.Init()` 接管 GUI 创建段（当前 4108–4188）；
- `OnSize` 改为经 `State.GetXxx()` / `GuiCtrlFromHwnd(State.GetEd())` 取控件；
  `search*` 由 `SearchFeature.Layout()` 管理；
- `GetHotkeys()` / `GetContexts()` 提供 Note 热键与 `editor` / `search` 上下文；
- 验收：笔记全部功能 + 主题 / 背景图 / 搜索 / 日期 / 标签 / 图片 / 自动保存；
  窗口拉伸时文字不闪。

### Phase 3 · Launcher 模块化

- `PeerLayoutService` + `PowerShellFeature` + `DeepSeekFeature` 搬入 `modules/Launcher/`；
- 抽 `WorkBench/Coordinator/PeerCoordinator.ahk`：订阅 `Launcher.Opened` /
  `SevenNote.WindowReady`，算完布局发 `SevenNote.Move` / `Launcher.Move`；
- `Alt+C` / `Alt+X` 从 Feature 自注册改为 `LauncherModule.GetHotkeys()`，由 Router 注册；
- 验收：终端 / 浏览器呼出 / 隐藏 / 切换、笔记让位、重启认回窗口。

### Phase 4 · KeysInput 模块化

- `CapsLockFeature` 搬入 `modules/KeysInput/`；
- `Alt+Shift+C` 进 `GetHotkeys()`；CapsLock 与 `H/J/K/L` 由模块在开关时
  `HotkeyRouter.Add/Remove`（动态）；
- 验收：层开关、`HJKL` 方向、`Esc` 退出、关层后无残留热键；**只能人工按键验证**
  （上下文热键无法用 `Send` 触发）。

### Phase 5 · WorkBenchUI 统一帮助

- `WorkBenchUI` 聚合各模块 `GetMetadata()`，替换 `ShowHelp()` / `BuildHotkeyHelpText()`；
- `Alt+H` 归平台；帮助窗口 `Esc` 由 UI 自注册 / 注销；
- 验收：三个模块热键齐全、平台级单独一组、新增模块自动出现、无重复条目。

### Phase 6 · 改名（最后做）

- 主脚本 `SevenWork.ahk`、`Config.AppName`、AppData / `ConfigPath`、日志兜底路径、
  README / docs / `.clinerules`、GitHub 仓库名；
- AppData 迁移：`SevenNote-Dev` → `SevenWork-Dev`，复制 `_config.ini`（Vault / 主题 / 字体）；
  DeepSeek profile 是否迁移由用户决定；
- 验收：旧配置可读、Vault 不变、日志写到新目录、全部热键不变、编译产物可运行；
- 风险：**不要与拆模块同批**；旧链接 301 但徽章 / Release 链接要同步。

---

## 6. 已验证事实与硬约束

| 探针 | 结果 | 对改造的影响 |
| --- | --- | --- |
| auto-execute | 函数定义、类定义、运行时 `Hotkey()` **都不结束**；热键 / 热字符串 / `#HotIf` 指令才结束 | 探针驱动仍插在 `ShowStartupTip()` 之后；Router 的 `HotIf()` 调用不会截断启动 |
| 静态方法 `this` | `Probe.Toggle` 裸引用 → `Missing a required parameter`；lambda / `.Bind()` → `this=yes` | `GetHotkeys()` 的 `fn` 必须 lambda 或 Bind |
| `#Include` 顺序 | 反序（consumer → cfg）仍能解析类静态引用；**顶层语句严格按 include 顺序** | `Config` 仍放最前；不要依赖反序 |
| `Module.Init()` | `Init()` + `GetHotkeys()` 返回 lambda 均正常（`this=yes`） | 生命周期接口可用 |
| `tests/` | 已删除（`c864226`） | E2E 待按模块接口重建 |

硬约束：

1. 不改 Kernel / Service 语义，只搬位置；Kernel 冻结、只加不改。
2. Feature 之间零调用；跨模块通信只走 `EventBus`。
3. 依赖方向 `Feature → Service → Kernel → OS`，严禁反向。
4. **一次只搬一个模块**，每一步都保持单文件可运行、可回退。
5. 改名最后做，不与结构改造同批。
6. 上下文热键只能人工按键验证；探针只证明「注册不抛错」。
