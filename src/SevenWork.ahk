#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()

; ═══════════════════════════════════════════════════════════════════════════
;  【警告策略 —— 改默认动作，别再让警告拦住程序】
;  AHK v2 对「未赋值变量」（VarUnset）默认既开警告、动作又是 **MsgBox** ——
;  一弹就停摆：模态框挡在屏幕上、热键全无反应，只能手动杀进程。
;  项目在 v2 迁移期连踩三次（`JSON.Stringify` / `Gui` 当变量名 / 空串比较），
;  每次症状都是「Alt+Z 没反应」，排查还得先枚举 #32770 读正文。
;  这里把动作改成 OutputDebug —— VS Code 的 AHK++ 调试器里照样看得到，
;  但不再拦路。未赋值变量的根本预防手段仍是「变量名写长一点」（guiHwnd / idxMap），
;  见 .clinerules/03。
; ═══════════════════════════════════════════════════════════════════════════
#Warn VarUnset, OutputDebug

; ═══════════════════════════════════════════════════════════════════════════
;  SevenWork —— v2.4.3
;  本地单文件速记工具。RichEdit 富文本编辑 + 双 RTF 存储 + Markdown 输出。
;  ⚠ 版本号以 Config.Version 为准（显示在 Alt+S 帮助窗口底部），改这里要一并改它。
;
;  【版本摘要】完整变更日志在 README「变更日志」表，这里只留一行一条的骨架。
;    v2.4.3  一轮「去重与仓库卫生」：① 新增 Service `PeerLayoutService` —— 终端 / DeepSeek
;            两处各自留底的「右下角落点公式 + 可摆性闸 + 矩形读取」收拢成一份（原先改
;            一处要记着同步另一处；实测两版摆位逐项一致）；② 删掉全局覆盖键
;            [Appearance] BackdropImage / BackdropOpacity（它会盖掉所有带 bg 的主题）
;            —— 图的路径与浓淡只写在主题自己的 bg / bgAlpha 上；③ StatFeature.Tick
;            补窗口可见性守卫；④ 加 .gitignore，演示测试产物出库。
;    v2.4.2  补齐运行时兜底与三处实测到的浪费：① 注册 OnError —— 未捕获异常写
;            _error.log（开发版落项目根 .logs\，编译版落 AppData）并**继续跑**，
;            不再弹模态框停摆；
;            同时把 VarUnset 警告动作改成 OutputDebug（同上，不再拦路）。
;            ② pandoc 可用性探测缓存（原先每次保存都 RunWait 起一个 200MB 进程）、
;            ConfigService 加进程内读缓存（GetVault 在保存链路上就要读 6 次盘）。
;            ③ ListAllTags 冒泡 O(n²) 换内置 Sort；SetTimer 回调统一过一遍
;            「窗口还在不在」守卫（照 AutoSaveFeature.Tick 的写法）
;    v2.4.1  修复连按 Alt+C / Alt+X 弹模态框卡死（异步复核去摆一个已隐藏的窗口）；
;            终端宽度与另外两个窗口统一，目标宽定 772（实测 Edge 会吸附 --window-size 的宽度）
;    v2.4    主题表精简 8 → 5 套并做一次性旧下标迁移（[Appearance] ThemeSchema）；
;            时间戳改为手动 Ctrl+T 插入（不再自动加）
;    v2.3    修背景图主题拉伸时编辑区文字闪烁（_ScheduleRender 抖动合并 + _RenderNow 同矩形跳过）；
;            编辑区滚动条随主题明暗；金克斯按「保留明暗 + 主体完整」重烘（-CropW 0.72 → 1.00）
;    v2.2    主题扩到 8 套，末尾两套为**背景图主题**（星空 / 金克斯，都是「暗图 + 亮字」，
;            裁剪与色调全烘进图片，运行时 bgAlpha 保持 0）；沉淀出 tools\rebake-backdrop.ps1
;    v2.1    伴生窗口适配只在首次跑一次（与笔记原来待的地方相撞才摆位，随后冻结，归用户自己管）
;    v2.0    Alt+X 呼出 / 隐藏 DeepSeek 网页；Alt+C 的窗口适配泛化成 Peer.* 通用契约
;    v1.9    修 pandoc 打包 0KB 问题；PandocService 加文件有效性校验（> 1MB）
;    v1.8    状态栏日期后显示星期（📅 2026-09-20 周日）
;    v1.7    assets 统一收纳到 _assets/日期/；切日期 / 跳转 / 启动加载后光标到开头 + 视口到顶
;
;  【用户旅程编号】组合根启动区与各模块 GetHotkeys / Feature 头部都用这套编号标注归属 ——
;    ① 唤起与关闭    Alt+Z 呼出 / 隐藏
;    ② 输入与编辑    粘贴 / 行编辑 / 缩进 / 撤销 / 输入增强
;    ③ 保存与持久化  加载 / 保存 / 自动保存 / 时间戳
;    ④ 查看与浏览    搜索 / 字数 / 光标记忆
;    ⑤ 组织与管理    日期切换 / 搜索跳转 / 标签 / 返回当天
;    ⚠ 全局热键只覆盖 ①②⑤；③④ 是编辑器内热键（见 src/WorkBench/HotkeyRouter.ahk），
;      所以在全局那一段里编号看起来是跳着的（② 之后直接 ⑤），那是正常的。
;
;  【整体架构 —— 四层 + 组合根】
;    FEATURE 功能层（21 项，按用户旅程排列）→ SERVICE 服务层（8 项，纯能力）
;     → KERNEL 骨架层（4 项：生命周期 / 状态 / 事件 / 配置）
;     → 表示层 StatusBar → 组合根（装配 + 启动，在文件末尾）
;    Kernel 实现在 src/WorkBench/Kernel/；SevenNote 模块的 7 个 Service、StatusBar、
;    18 个 Feature 与模块生命周期在 src/modules/SevenNote/。
;    本文件只保留组合根：首次引导、模块装配、启动提示；热键注册与帮助窗口已分别归
;    src/WorkBench/HotkeyRouter.ahk 与 src/WorkBench/WorkBenchUI.ahk。
;
;  【依赖方向】Feature → Service → Kernel → OS（严禁反向）
;
;  【核心技术决策】
;    1. EM_STREAMOUT/EM_STREAMIN 直读直写 RTF
;    2. Pandoc 转换 RTF → Markdown
;    3. 双 RTF 输出（936 + 65001）
;    4. 系统默认 Ctrl+V
;    5. 空笔记不落盘
;    6. 先查后存
;    7. 标签写文件名
;    8. 路径分离
;    9. assets 统一收纳（v1.7）
;   10. pandoc 文件大小检查（v1.9）
;   11. 伴生窗口适配走 Launcher.* / SevenNote.Move 事件 —— 发布方只广播生命周期，
;       摆位 / 记忆 / 失败兜底在 WindowFeature 与 PeerCoordinator 里，见 README「添加呼出外部窗口的功能」
;   12. 背景图主题只是 Themes 数组里的普通成员（v2.2）—— 切到铺图、切走撤图，没有全局开关
;   13. 编辑区滚动条与标题栏跟着主题明暗走（v2.3）
;
;  【已知坑点】全文见 .clinerules/03-ahk-v2.md（那里是单一事实源），这里只列最常踩的：
;    · AHK v2 内置函数名不能做变量名（Clear/log/min/max/Indent）；
;      ⚠ **Gui 也不能** —— 它是内置类名，`gui := WinExist(...)` 直接报错
;    · AHK v2 的 < > 是数值比较，字符串比较用 StrCompare
;    · AHK v2 的 <= / >= 遇空字符串会抛错，数值比较前先 IsNumber() 守卫
;    · EM_SETSEL/EM_GETSEL 用 DllCall 4 参数版本
;    · FINDTEXTEXW 读偏移 16/20（chrgText）
;    · 32 位编译导致 RichEdit 字符格式异常——必须 64 位
;    · FileInstall 必须一行，源路径不存在会打包 0KB 空文件（v1.9）
;    · 最小化窗口的 IsWindowVisible 仍是 1 —— 判断「在显示」要 IsWindowVisible && !IsIconic
;    · WinMove / WinGetPos 默认忽略隐藏窗口，对隐藏窗口直接抛 "Target window not found"；
;      **凡在异步定时器回调里碰窗口，先过一道闸**（DetectHiddenWindows(false) + WinExist + !IsIconic）
;    · 先 Show 再 WinMove 会让窗口「飘一下」：定位要在隐藏状态下做完（Show("Hide") → 摆好 → Show）
;    · 启动终端别传 Run 的 "Hide"：隐藏启动会绕过 Windows Terminal 委派，终端退回
;      conhost 默认（120x50 = 1488x1256、#012456 蓝底），拿不到 WT profile 的星空背景
;
;  依赖：pandoc.exe（软依赖，未安装则 MD 降级为纯文本）
; ═══════════════════════════════════════════════════════════════════════════


; ═══════════════════════════════════════════════════════════════════════════
;  KERNEL 骨架层 —— 实现见 src/WorkBench/Kernel/
; ═══════════════════════════════════════════════════════════════════════════

#Include WorkBench\Kernel\Config.ahk
#Include WorkBench\Kernel\ConfigService.ahk
#Include WorkBench\Kernel\EventBus.ahk
#Include WorkBench\Kernel\State.ahk
#Include WorkBench\ModuleRegistry.ahk
#Include WorkBench\HotkeyRouter.ahk
#Include WorkBench\WorkBenchUI.ahk

; ═══════════════════════════════════════════════════════════════════════════
;  CAPABILITY 平台能力层 —— 纯平台能力，不认识业务模块
;  只收数字 / hwnd / Gui，返回结构体；不读 Config / State，不发事件。
; ═══════════════════════════════════════════════════════════════════════════

#Include WorkBench\Capabilities\Placement\RectMath.ahk
#Include WorkBench\Capabilities\Placement\WindowProbe.ahk
#Include WorkBench\Capabilities\Placement\PlacementExecutor.ahk
#Include WorkBench\Capabilities\Graphics\BackdropService.ahk

; ═══════════════════════════════════════════════════════════════════════════
;  COORDINATION 跨模块协调 —— 读业务状态、发事件、算几何后交给能力层
; ═══════════════════════════════════════════════════════════════════════════

#Include WorkBench\Coordinator\PeerCoordinator.ahk
#Include WorkBench\WorkBench.ahk

; ═══════════════════════════════════════════════════════════════════════════
;  SERVICE 服务层
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Services\EditorService.ahk


#Include modules\SevenNote\Services\ClipboardService.ahk


#Include modules\SevenNote\Services\NoteStoreService.ahk


#Include modules\SevenNote\Services\PandocService.ahk


#Include modules\SevenNote\Services\ThemeService.ahk


#Include modules\SevenNote\Services\FontService.ahk


; BackdropService 已上收到 WorkBench\Capabilities\Graphics\（见上方 CAPABILITY 层）
#Include modules\Launcher\Services\PeerLayoutService.ahk

; ═══════════════════════════════════════════════════════════════════════════
;  表示层组件

; ═══════════════════════════════════════════════════════════════════════════

; ─── StatusBar：状态栏 ───
#Include modules\SevenNote\StatusBar.ahk
; ═══════════════════════════════════════════════════════════════════════════
;  FEATURE 功能层 —— 用户要做什么
;
;  按用户旅程排序：
;   ① 唤起与关闭    Alt+Z 呼出/隐藏
;   ② 输入与编辑    粘贴 / 行编辑 / 缩进 / 撤销 / 输入增强
;   ③ 保存与持久化  加载 / 保存 / 自动保存 / 时间戳
;   ④ 查看与浏览    搜索 / 字数 / 光标记忆
;   ⑤ 组织与管理    日期切换 / 搜索跳转 / 标签 / 返回当天
;   横切·美观       主题 / 字体 / 字号
; ═══════════════════════════════════════════════════════════════════════════


; ═══════════════════════════════════════════════════════════════════════════
;  ① 唤起与关闭
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Features\WindowFeature.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  ② 输入与编辑
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Features\PasteFeature.ahk


#Include modules\SevenNote\Features\LineEditFeature.ahk


#Include modules\SevenNote\Features\UndoFeature.ahk


; CapsLockFeature 归 src\modules\KeysInput\（Phase 4），见下方 MODULE 模块层。


; ═══════════════════════════════════════════════════════════════════════════
;  ③ 保存与持久化
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Features\LoadFeature.ahk


#Include modules\SevenNote\Features\SaveFeature.ahk


#Include modules\SevenNote\Features\AutoSaveFeature.ahk


; ⚠ 时间戳**一律手动**（v2.4 起）：只在用户按下 Ctrl+T 时插入，程序任何时候都不自作主张。
;   原先的两条自动路径已删除 ——
;     · 启动时 CheckAndAppend()：无戳就塞一个；
;     · 切日期时同一函数：距上一戳 ≥ Config.TimestampInterval（60 分钟）再补一个。
;   它们会在用户只想随手记两笔时也往笔记里加时间戳，还得靠「保存前剥掉空戳」来兜底。
;   现在连带 StripIfEmpty 一起去掉：用户手动加的戳就是他想要的，程序不擅自删。
;   想恢复自动：在组合根按需调 TimestampFeature.Append()，或把 CheckAndAppend 加回来。
#Include modules\SevenNote\Features\TimestampFeature.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  ④ 查看与浏览
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Features\SearchFeature.ahk


#Include modules\SevenNote\Features\StatFeature.ahk


#Include modules\SevenNote\Features\CaretFeature.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  ⑤ 组织与管理
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Features\DateSwitchFeature.ahk


#Include modules\SevenNote\Features\DateJumpFeature.ahk


#Include modules\SevenNote\Features\TitleFeature.ahk


#Include modules\SevenNote\Features\GoTodayFeature.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  横切 · 美观
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Features\ThemeFeature.ahk


#Include modules\SevenNote\Features\FontFeature.ahk


; ─── BackdropFeature：带背景图的主题（星空）───
; 背景图不是「全局贴一张」，而是主题自带的属性：ThemeService.Themes 里带 bg 字段的
; 主题（目前只有「星空」）才铺图，切到别的主题自动撤掉、回到纯底色。
; 文字浮在图上、图铺满整个编辑区（终端式，非相框式）。
#Include modules\SevenNote\Features\BackdropFeature.ahk
#Include modules\SevenNote\SevenNoteModule.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  MODULE 模块层 · Launcher（Phase 3a：外部程序呼出）
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\Launcher\Features\PowerShellFeature.ahk
#Include modules\Launcher\Features\DeepSeekFeature.ahk
#Include modules\Launcher\LauncherModule.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  MODULE 模块层 · KeysInput（Phase 4：键位增强）
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\KeysInput\Features\CapsLockFeature.ahk
#Include modules\KeysInput\KeysInputModule.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  组合根 —— 装配 + 启动
; ═══════════════════════════════════════════════════════════════════════════

; ═══ 全局异常兜底 ═══
; AHK v2 对未捕获异常默认是**弹模态框**：框一弹脚本就停摆（热键全无反应、框还挂在
; 屏幕上），只能手动杀进程 —— 项目在 v2 迁移期踩过三次（见 .clinerules/03）。
; 这里改成「写日志 + 继续跑」：单个 Feature 出错不该拖垮整个程序。
; 注册点放在这里（而不是文件更早处）是因为 LogError 要先建日志目录
; （开发版项目根 .logs\、编译版 %AppData%\SevenWork\），
; 而其中的 AppData 目录就在下面几行才建。
OnError(OnScriptError)

; AHK 的异常回调。返回 **1** = 已处理，不弹默认错误框（返回 0 就会弹）。
; ⚠ 回调自身绝不能抛异常 —— 会递归回到这里，所以全程 try，见 LogError。
OnScriptError(err, mode) {
    stack := err.HasProp("Stack") ? err.Stack : ""
    LogError(mode . "  " . err.Message
        . "`n      文件  " . err.File . "   行  " . err.Line
        . (Trim(stack) != ""
            ? "`n      调用栈：`n      " . StrReplace(Trim(stack, "`n"), "`n", "`n      ")
            : ""))
    return 1
}

; 追加一条到日志（落点见 Config.LogPath：开发版 .logs\_error.log，
; 编译版 %AppData%\SevenWork\_error.log）。
; 超 512 KB 就轮转（删掉重来）—— 日志只用来事后定位，不归档。
LogError(msg) {
    entry := "── " . FormatTime(, "yyyy-MM-dd HH:mm:ss") . " ──`r`n" . msg . "`r`n`r`n"
    try {
        logPath := Config.LogPath
        DirCreate(Config.LogDir)      ; 启动极早期出错时，这个目录可能还没建
        if (FileExist(logPath) && FileGetSize(logPath) > 524288)
            FileDelete(logPath)
        FileAppend(entry, logPath, "UTF-8")
    } catch {
        ; 项目目录只读 / 被占用时退回 AppData —— 日志丢一次就白查了
        try {
            fallbackDir := Config.AppDataDir
            DirCreate(fallbackDir)
            FileAppend(entry, fallbackDir . "\_error.log", "UTF-8")
        }
    }
}

; ═══ Phase 6：旧版数据迁移 ═══
; 新路径已有同名项时一律跳过；旧目录原样保留，确认新配置可用后再由用户删除。
; 复制失败不阻断启动 —— 新目录会退回默认配置 / 重新创建 profile。
MigrateLegacyAppData() {
    oldDir := A_AppData . "\SevenNote-Dev"
    if !DirExist(oldDir)
        return

    oldConfig := oldDir . "\_config.ini"
    if !FileExist(Config.ConfigPath) && FileExist(oldConfig)
        try FileCopy(oldConfig, Config.ConfigPath, false)

    ; DeepSeek profile 是独立 Edge 用户目录（约 950MB），只在目标不存在时整目录复制
    oldProfile := oldDir . "\_deepseek-profile"
    newProfile := Config.AppDataDir . "\_deepseek-profile"
    if !DirExist(newProfile) && DirExist(oldProfile)
        try DirCopy(oldProfile, newProfile, false)

    ; 模式是小文件；pid 指向旧进程，绝不复制
    oldMode := oldDir . "\_deepseek.mode"
    newMode := Config.AppDataDir . "\_deepseek.mode"
    if !FileExist(newMode) && FileExist(oldMode)
        try FileCopy(oldMode, newMode, false)

    ; pandoc 也是跨版本共用的独立目录；旧文件存在就不必重新解包
    oldPandoc := A_AppData . "\SevenNote\pandoc.exe"
    if !FileExist(Config.PandocPath) && FileExist(oldPandoc)
        try FileCopy(oldPandoc, Config.PandocPath, false)
}

; ═══ 确保 AppData 目录存在 ═══
DirCreate(Config.AppDataDir)

; ═══ Phase 6：迁移旧版 SevenNote-Dev 数据 ═══
; 只在新路径缺失时复制，旧目录保留；DeepSeek profile 约 950MB，
; 首次升级启动会多花几秒，之后各路径已存在就直接跳过。
MigrateLegacyAppData()

; ═══ 打包 pandoc.exe（v1.9 修复）═══
; 【关键修复】
;   · FileInstall 必须一行，不能折行（否则 Ahk2Exe 可能打包空文件）
;   · 第二参数用展开的表达式，不用类属性
;   · 释放前先删旧文件（避免 0KB 坏文件阻塞后续释放）
;   · 只在文件不存在或 < 1MB 时才释放
; ⚠ 编译前把下面的源路径改成你本机 pandoc.exe 的实际路径
; ⚠ 编译时务必确认源文件是 100+ MB 的 x86_64 版 pandoc
if !FileExist(Config.PandocPath) || FileGetSize(Config.PandocPath) < 1048576 {
    try FileDelete(Config.PandocPath)
    FileInstall "C:\Users\Seven\AppData\Local\Pandoc\pandoc.exe", A_AppData . "\SevenWork\pandoc.exe", 1
}

; ═══ 加载 RichEdit 控件库 ═══
DllCall("LoadLibrary", "str", "msftedit.dll", "ptr")

; ═══ 配置服务初始化 ═══
ConfigService.Init(Config.ConfigPath)
ConfigService.SetDefault("Appearance", "ThemeIndex", "1")
; 主题表「结构版本」：主题表精简 / 重排过就 +1，ThemeService._MigrateIndex 据此只跑一次下标迁移
ConfigService.SetDefault("Appearance", "ThemeSchema", "1")
ConfigService.SetDefault("Appearance", "FontIndex", "1")
ConfigService.SetDefault("Appearance", "FontSizeIndex", "2")
; 背景图不再有全局键：图与浓淡都写在主题自己的 bg / bgAlpha 上（见 ThemeService.Themes）
ConfigService.SetDefault("Input", "CapsLockMap", "0")
ConfigService.SetDefault("Paths", "Vault", "")

; ═══ 首次运行：引导用户选择笔记目录 ═══
EnsureVaultConfigured()

; ═══ 确保笔记目录存在 ═══
DirCreate(Config.GetVault())

; ═══ 工作台装配（Phase 3b：模块登记 + PeerCoordinator 订阅）═══
; 必须在模块 Init() 之前：订阅要赶在第一次 Alt+C / Alt+X 之前就位。
WorkBench.Init()

; ═══ 笔记模块（Phase 2：GUI 与 Feature 挂载已搬入 src/modules/SevenNote）═══
SevenNoteModule.Init()

; ═══ 外部程序模块（Phase 3：热键由 LauncherModule.GetHotkeys 提供）═══
LauncherModule.Init()

; ═══ 键位模块（Phase 4：CapsLock 层状态，热键由 KeysInputModule.GetHotkeys 提供）═══
KeysInputModule.Init()

; ═══ 热键（Router 聚合平台 + 各模块的 GetHotkeys）═══
HotkeyRouter.RegisterAll()

; ═══ 启动 ═══
SevenNoteModule.Start()
KeysInputModule.Start()

ShowStartupTip()


; ═══════════════════════════════════════════════════════════════════════════
;  首次运行引导
; ═══════════════════════════════════════════════════════════════════════════

EnsureVaultConfigured() {
    vault := ConfigService.Read("Paths", "Vault")
    if (vault != "" && DirExist(vault))
        return

    defaultPath := A_MyDocuments . "\SevenWork"
    if (vault != "")
        defaultPath := vault

    selected := DirSelect(defaultPath, 0
        , Config.AppName . " 首次运行`n`n请选择笔记存储目录：")
    if (selected = "")
        selected := defaultPath

    DirCreate(selected)
    Config.SetVault(selected)
}


; ═══════════════════════════════════════════════════════════════════════════
;  启动提示
; ═══════════════════════════════════════════════════════════════════════════

ShowStartupTip() {
    tip := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "提示")
    tip.SetFont("s14", "楷体")
    tip.BackColor := "E4E9EE"
    ; 平台级提示只指向平台级热键：Alt+S 打开帮助（里面才有模块热键 Alt+Z 等）。
    ; 文案实测 314 逻辑像素宽，控件取 w330、窗口取 w370 才能一行放完不被裁。
    tip.AddText("x20 y20 w330 Center c3D5166", Config.AppName . " 已启动！Alt+S 查看帮助")
    tipY := A_ScreenHeight * 0.65
    tip.Show("w370 h80 y" . tipY)
    ; ⚠ 1.5 秒内用户可能自己把这扇提示窗关掉 —— 再 Destroy() 一次会抛异常，
    ;   而 SetTimer 回调没有外层 try，异常即弹模态框（见 .clinerules/03）。
    SetTimer(() => DestroyTipWindow(tip), -1500)
}

; 关掉启动提示。已经关过就算了 —— 这正是 try 的用途。
DestroyTipWindow(tip) {
    try tip.Destroy()
}
