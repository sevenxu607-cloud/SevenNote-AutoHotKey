#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  SevenNoteModule —— 笔记模块生命周期
;  v2.9 起编辑区是 WebView2 + Milkdown：AHK 只负责建窗口、挂宿主、注册热键，
;  内容与界面全在 web/ 里。Init → 热键 → Start 的顺序未变。
; ═══════════════════════════════════════════════════════════════════════════

class SevenNoteModule {
    static Id := "SevenNote"
    static Name := "笔记"
    ; 笔记模块自己的显示名（标题栏用）。工作台叫 SevenWork（Config.AppName），
    ; 而 Alt+Z 呼出的是**笔记窗口** —— 标题用模块名才与目录 / 模块 Id / 事件名自洽。
    ; 平台级界面（Alt+S 帮助、启动提示、报错框）仍用 Config.AppName。
    static Title := "SevenNote"

    ; WebView2 是否已挂上（OnSize 据此决定要不要 Fill —— 没挂上时 Fill 会抛错）
    static _mounted := false

    ; 创建主窗口 + 挂载 Feature（原组合根 3901-3997）
    static Init() {
        ; ─── 创建主窗口 ───
        g := Gui(, this.Title)
        ; +E0x02000000 = WS_EX_COMPOSITED 已不需要：整个客户区交给 WebView2，
        ; 合成由 Chromium 自己做，没有 RichEdit 那种「先擦后画」的频闪。
        g.Opt("+AlwaysOnTop +Resize +MinSize450x300")
        ; 首帧底色：Chromium 起来前不铺东西会露白。取当前主题的窗底色同档。
        g.SetFont("s14", "楷体")
        g.BackColor := ThemeService.Themes[ThemeService.GetCurrent()].win

        ; ─── 客户区整个交给 WebView2 ───
        ; 字数 / 标签 / 主题名 / 日期 / 提示原本是 6 个 Text 控件，现在全在页面里
        ; （前端拿到 markdown 自己算字数、自己显示日期）。AHK 侧不再持有任何子控件 ——
        ; 少一层「AHK 控件 vs 页面元素」的双份状态，就不会出现两边不一致。

        ; ─── 注册到 State ───
        State.SetGui(g)
        ; RichEdit 退场：State.GetEd() 从此恒为 0。
        ; 骨架层冻结，setter 保留（别的模块仍可调用，只是拿不到控件）。
        State.SetEd(0)

        ; ─── 窗口事件 ───
        g.OnEvent("Close", (*) => (g.Hide(), true))
        g.OnEvent("Size", (guiObj, mm, w, h) => SevenNoteModule.OnSize(guiObj, mm, w, h))

        ; ═══ 挂载 Feature ═══
        ; v2.9 起只剩四件：窗口 / 保存 / 自动保存 / 日期跳转。
        ; 搜索、撤销、行编辑、纯文本粘贴、光标记忆、字数、背景图全部由页面接管 ——
        ; 它们本来就是「编辑器内部」的事，从前借着 RichEdit 的 SendMessage 硬做；
        ; 现在 Milkdown 自己就是编辑器，前端一套 keymap 就够。
        WindowFeature.Init()
        SaveFeature.Init()
        AutoSaveFeature.Init(Config.AutoSaveInterval)
        DateJumpFeature.Init()

        ; 每次露面后补一次 Fill：Chromium 子窗口的尺寸只在父窗口可见时才有意义，
        ; 而 Mount 发生在隐藏态（见 _Mount）。不补的话窗口出来了、编辑区仍是 0×0 ——
        ; 画面一片纯底色，看起来像「WebView2 根本没显示」。
        EventBus.On("Window.Shown", (*) => SevenNoteModule._AfterShown())
    }

    static _AfterShown() {
        if this._mounted
            WebHostService.Resize()
    }

    ; ─── 启动：挂 WebView2 → 载入当天 ───
    ; ⚠ 必须晚于热键注册（Router 先 RegisterAll 再 StartAll），否则用户按 Alt+Z
    ;   时窗口先露面、热键还没就位，表现成「按了没反应」。
    static Start() {
        if !this._Mount()
            return
        ; ⚠ 不在 Start() 里同步等编辑器：WaitFor 最长 8 秒，会把整个启动流程卡住
        ;   （StartAll 是同步遍历，别的模块得陪着等）。排到后台，热键先就位。
        SetTimer(() => SevenNoteModule._FirstLoad(), -50)
    }

    static _FirstLoad() {
        try LoadFeature.Load()
        catch as e
            LogError("首次载入失败：" . e.Message)
    }

    ; 把 WebView2 挂到主窗口上。
    ; ⚠ 全程在隐藏态完成（Show("Hide") → Mount → Navigate）：先 Show 再摆位会让
    ;   窗口在默认落点闪一下（实测 +31ms 出现在错误位置、+219ms 才跳过去）。
    static _Mount() {
        g := State.GetGui()
        try
            g.Show("Hide")
        catch as e {
            LogError("笔记窗口创建失败：" . e.Message)
            return false
        }

        dist := this._DistDir()
        if (dist = "") {
            LogError("前端产物不存在，先到 web\ 下 npm run build")
            return false
        }

        r := WebHostService.Mount(g.Hwnd, dist)
        if !r.ok {
            LogError("WebView2 挂载失败：" . r.reason)
            return false
        }

        ; 笔记图片在 vault 下，markdown 里写的是 ./_assets/<date>/x.png；
        ; 相对 app.local 会解析成 app.local/_assets/… → 404。把 vault 另挂一个主机，
        ; 前端显示时加前缀、存盘时剥掉（见 web/src/ahk.ts 的路径双态）。
        m := WebHostService.MapHost("vault.local", Config.GetVault())
        if !m.ok
            LogError("vault 映射失败：" . m.reason)

        WebHostService.Bind("ahk", NoteHostHandlers())

        n := WebHostService.Navigate("/index.html?view=note")
        if !n.ok {
            LogError("导航失败：" . n.reason)
            return false
        }
        this._mounted := true
        ; 隐藏态也铺一次：给 Chromium 一个初始尺寸，免得首次显示时先闪一帧空白。
        ; 真正的尺寸要等父窗口可见（Window.Shown → _AfterShown）。
        WebHostService.Resize()
        return true
    }

    ; 前端产物目录：开发态在 <repo>\web\dist（src\ 的同级）；
    ; 编译版与 exe 同级（打包时把 dist 一起放过去即可）。
    static _DistDir() {
        for p in [A_ScriptDir . "\..\web\dist", A_ScriptDir . "\web\dist"] {
            if DirExist(p)
                return p
        }
        return ""
    }

    static OnSize(guiObj, MinMax, Width, Height) {
        ; 最小化时 Width/Height 是图标尺寸（实测约 158x26），
        ; Fill() 会把 Chromium 压成一条，直接跳过
        if (MinMax = -1)
            return
        if this._mounted
            WebHostService.Resize()
    }

    ; 笔记模块的热键
    ; v2.9：27 条 → 7 条。编辑器内部的键（撤销 / 行编辑 / 缩进 / 纯文本粘贴 /
    ; 时间戳 / 分隔线 / 分段标题 / 搜索）统统交给页面 —— 那些操作都要看光标与选区，
    ; 前端一套 keymap 天然有上下文；AHK 这边从前只能对着 RichEdit SendMessage 猜。
    ; 平台热键（Alt+S / Alt+Shift+Z）不在这里，见 WorkBench.GetHotkeys()。
    static GetHotkeys() {
        return [
            ; ── 【窗口】──
            {ctx: "global", key: "!z", group: "窗口", line: "   Alt+Z            呼出 / 隐藏"
                , fn: (*) => WindowFeature.Toggle()},

            ; ── 【保存】──
            {ctx: "editor", key: "$^s", group: "保存", line: "   Ctrl+S           手动保存"
                , fn: (*) => SaveFeature.Save()},

            ; ── 【日期与标签】──
            {ctx: "global", key: "!Up", group: "日期与标签", line: "   Alt+↑            前一天"
                , fn: (*) => DateSwitchFeature.Switch(-1)},
            {ctx: "global", key: "!Down", group: "日期与标签", line: "   Alt+↓            后一天"
                , fn: (*) => DateSwitchFeature.Switch(1)},
            {ctx: "global", key: "!Home", group: "日期与标签", line: "   Alt+Home         回到今天"
                , fn: (*) => GoTodayFeature.Go()},
            {ctx: "editor", key: "$^g", group: "日期与标签", line: "   Ctrl+G           搜索跳转（日期 / 标签）"
                , fn: (*) => DateJumpFeature.ShowDialog()},
            {ctx: "editor", key: "$^+t", group: "日期与标签", line: "   Ctrl+Shift+T     为当前日期设置标签"
                , fn: (*) => TitleFeature.ShowDialog()}
        ]
    }

    static GetMetadata() {
        return {name: this.Name, desc: "笔记编辑与检索 · Alt+Z", order: 10
            , hotkeys: this.GetHotkeys()}
    }

    ; 只剩一个上下文：笔记窗口在前台。
    ; 搜索条退场后 editor / search 二选一收敛成一条 ——
    ; ⚠ 声明了却没人提供实现的 ctx，它的热键一条都不注册（见 .clinerules/02）。
    static GetContexts() {
        return {editor: (*) => WinActive("ahk_id " . State.GetGuiHwnd())}
    }
}