#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  SevenNoteModule —— 笔记模块生命周期
;  GUI 创建 / OnSize / Feature 挂载 / 启动，Phase 2 从组合根原样搬入，行为未改。
; ═══════════════════════════════════════════════════════════════════════════

class SevenNoteModule {
    static Id := "SevenNote"
    static Name := "笔记"

    ; 创建主窗口 + 挂载 Feature（原组合根 3901-3997）
    static Init() {
        ; ─── 创建主窗口 ───
        g := Gui(, Config.AppName)
        ; +E0x02000000 = WS_EX_COMPOSITED：整个窗口走「离屏双缓冲」重绘。
        ; 编辑区（RichEdit）自己不带双缓冲，滚动时它会先把客户区擦一遍再画文字，那一帧的空档
        ; 就是「上下滑动时略微频闪」的来源。开了合成重绘，父子控件的绘制顺序由系统统一保证，
        ; 滚动不再闪（代价是重绘走离屏缓冲，拖动窗口时 CPU 略高，肉眼无感）。
        g.Opt("+AlwaysOnTop +Resize +MinSize450x300 +E0x02000000")
        g.SetFont("s14", "楷体")
        g.BackColor := "FFF8E7"

        ; ─── 顶部控件：字数 + 标签 + 主题标签 ───
        stat := g.AddText("x8 y8 w60 h20 Left", "0 字")
        stat.SetFont("s10 c9CA3AF", "楷体")

        tagCtrl := g.AddText("x72 y8 w190 h20 Left cA89880", "")
        tagCtrl.SetFont("s10", "楷体")

        themeLabel := g.AddText("x266 y8 w176 h20 Right", "")
        themeLabel.SetFont("s10 c3D2B1F", "楷体")

        ; ─── RichEdit 编辑区 ───
        ed := g.AddCustom("ClassRichEdit50W x8 y32 w434 h440 +0x201004")
        SendMessage(0x0443, 0, 0xE7F8FF, ed.Hwnd)
        ed.SetFont("s14 c3D2B1F", "楷体")
        SendMessage(0x0453, 100, 0, ed.Hwnd)

        ; ─── 搜索条控件（初始隐藏）───
        searchBarBg := g.AddText("x8 y32 w220 h32 Background" . SearchFeature.BAR_BG, "")
        searchBarBg.SetFont("s1", "楷体")
        searchBarBg.Visible := false

        searchIcon := g.AddText("x12 y38 w22 h20 Background" . SearchFeature.BAR_BG . " c" . SearchFeature.BAR_DIM, "🔍")
        searchIcon.SetFont("s11", "楷体")
        searchIcon.Visible := false

        searchEdit := g.AddEdit("x36 y36 w130 h24 Background" . SearchFeature.EDIT_BG . " c" . SearchFeature.EDIT_TEXT, "")
        searchEdit.SetFont("s12", "楷体")
        searchEdit.Visible := false

        searchCount := g.AddText("x170 y39 w44 h20 Background" . SearchFeature.BAR_BG . " c" . SearchFeature.BAR_DIM . " Left", "")
        searchCount.SetFont("s10", "楷体")
        searchCount.Visible := false

        ; ─── 底部控件：日期 + 提示 ───
        dateCtrl := g.AddText("x8 y520 w180 h22 Left cA89880", "")
        dateCtrl.SetFont("s10", "楷体")

        msgCtrl := g.AddText("x162 y520 w280 h22 Right cA89880", "")
        msgCtrl.SetFont("s10", "楷体")

        ; ─── 注册到 State ───
        State.SetGui(g)
        State.SetEd(ed.Hwnd)
        State.SetStat(stat)
        State.SetDateCtrl(dateCtrl)
        State.SetMsgCtrl(msgCtrl)
        State.SetThemeLabel(themeLabel)
        State.SetTagCtrl(tagCtrl)

        ; ─── 窗口事件 ───
        g.OnEvent("Close", (*) => (g.Hide(), true))
        g.OnEvent("Size", (guiObj, mm, w, h) => SevenNoteModule.OnSize(guiObj, mm, w, h))

        ; ═══ 挂载 Feature ═══
        ; 最先挂 —— 它订阅「外部窗口（PowerShell / DeepSeek）要出现了」，
        ; 得赶在第一次 Alt+C / Alt+X 之前注册好
        WindowFeature.Init()
        StatusBar.Init(dateCtrl, tagCtrl, msgCtrl)
        SearchFeature.Init(searchBarBg, searchIcon, searchEdit, searchCount, stat, themeLabel, ed)
        AutoSaveFeature.Init(Config.AutoSaveInterval)
        SaveFeature.Init()
        CaretFeature.Init()
        StatFeature.Init(Config.StatInterval)
        DateJumpFeature.Init()
        BackdropFeature.Init(g)
    }

    static OnSize(guiObj, MinMax, Width, Height) {
        ; 最小化时 Width/Height 是图标尺寸（实测约 158x26），
        ; 控件按它算会得到负尺寸，直接跳过
        if (MinMax = -1)
            return
        try State.GetStat().Move(8, 8, 60, 20)
        try State.GetTagCtrl().Move(72, 8, 190, 20)
        try State.GetThemeLabel().Move(Width - 184, 8, 176, 20)
        SearchFeature.Layout(Width, Height)
        edCtrl := GuiCtrlFromHwnd(State.GetEd())
        if SearchFeature.IsVisible() {
            try edCtrl.Move(8, 72, Width - 16, Height - 110)
        } else {
            try edCtrl.Move(8, 32, Width - 16, Height - 70)
        }
        try State.GetDateCtrl().Move(8, Height - 30, 180, 22)
        try State.GetMsgCtrl().Move(Width - 288, Height - 30, 280, 22)
        ; 背景图跟着编辑区一起缩放（未开启时内部直接返回，无额外开销）
        BackdropFeature.Layout(Width, Height)
    }

    static Start() {
        ; ═══ 启动 ═══
        LoadFeature.Load()
        StatusBar.RefreshTag()

        ThemeFeature.LoadFromConfig()
        FontFeature.LoadFromConfig()
        ; CapsLock 配置由 KeysInputModule.Start() 恢复（Phase 4：模块各管各的状态）。
        ; 背景图不必在这里初始化：ThemeService.Apply 会 Emit "Theme.Changed"，
        ; 而 BackdropFeature 在 Init 时就挂上了这个事件 —— 启动与换主题都自动重铺。
    }

    ; 笔记模块负责 editor / search 两个上下文；Router 不再引用模块内部类
    static GetContexts() {
        return {
            editor: (*) => WinActive("ahk_id " . State.GetGuiHwnd()) && !SearchFeature.IsVisible(),
            search: (*) => WinActive("ahk_id " . State.GetGuiHwnd()) && SearchFeature.IsVisible()
        }
    }
}