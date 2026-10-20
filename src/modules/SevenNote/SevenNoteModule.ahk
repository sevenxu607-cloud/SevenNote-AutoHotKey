#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  SevenNoteModule —— 笔记模块生命周期
;  GUI 创建 / OnSize / Feature 挂载 / 启动，Phase 2 从组合根原样搬入，行为未改。
; ═══════════════════════════════════════════════════════════════════════════

class SevenNoteModule {
    static Id := "SevenNote"
    static Name := "笔记"
    ; 笔记模块自己的显示名（标题栏用）。工作台叫 SevenWork（Config.AppName），
    ; 而 Alt+Z 呼出的是**笔记窗口** —— 标题用模块名才与目录 / 模块 Id / 事件名自洽。
    ; 平台级界面（Alt+S 帮助、启动提示、报错框）仍用 Config.AppName。
    static Title := "SevenNote"

    ; 创建主窗口 + 挂载 Feature（原组合根 3901-3997）
    static Init() {
        ; ─── 创建主窗口 ───
        g := Gui(, this.Title)
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

    ; ─── 笔记模块的热键（Phase 5：从组合根搬入）───
    ; 平台热键（Alt+S / Alt+Shift+Z）不在这里，见 WorkBench.GetHotkeys()。
    static GetHotkeys() {
        return [
            ; ── 【窗口】──
            {ctx: "global", key: "!z", group: "窗口", line: "   Alt+Z            呼出 / 隐藏"
                , fn: (*) => WindowFeature.Toggle()},

            ; ── 【外观】──
            {ctx: "global", key: "!t", group: "外观", line: "   Alt+T            切换主题（含带背景图的「星空 / 金克斯」）"
                , fn: (*) => ThemeFeature.Next()},
            {ctx: "global", key: "!+t", group: "外观", line: "   Shift+Alt+T      切换字体"
                , fn: (*) => FontFeature.NextFont()},
            {ctx: "global", key: "!=", group: "外观", line: "   Alt+=            调大字号"
                , fn: (*) => FontFeature.BiggerSize()},
            {ctx: "global", key: "!-", group: "外观", line: "   Alt+-            调小字号"
                , note: "                      （外观设置自动保存）"
                , fn: (*) => FontFeature.SmallerSize()},

            ; ── 【输入增强】──
            ; Alt+Shift+C 由 KeysInputModule.GetHotkeys() 提供；
            ; Alt+C / Alt+X 由 LauncherModule.GetHotkeys() 提供。

            ; ── 【搜索】──
            {ctx: "editor", key: "$^f", group: "搜索", line: "   Ctrl+F           打开搜索栏"
                , fn: (*) => SearchFeature.Show()},
            {ctx: "search", key: "Enter", group: "搜索", line: "   Enter            下一个匹配"
                , fn: (*) => SearchFeature.Next()},
            {ctx: "search", key: "+Enter", group: "搜索", line: "   Shift+Enter      上一个匹配"
                , fn: (*) => SearchFeature.Prev()},
            {ctx: "search", key: "Esc", group: "搜索", line: "   Esc              关闭搜索栏"
                , fn: (*) => SearchFeature.Hide()},

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
                , fn: (*) => TitleFeature.ShowDialog()},

            ; ── 【编辑】──
            {ctx: "editor", key: "$^z", group: "编辑", line: "   Ctrl+Z           撤销"
                , fn: (*) => UndoFeature.Undo()},
            {ctx: "editor", key: "$^+z", group: "编辑", line: "   Ctrl+Shift+Z     重做"
                , fn: (*) => UndoFeature.Redo()},
            {ctx: "editor", key: "$^y", group: "编辑", line: "   Ctrl+Y           删除当前行"
                , fn: (*) => LineEditFeature.DeleteLine()},
            {ctx: "editor", key: "$^d", group: "编辑", line: "   Ctrl+D           复制当前行到下方"
                , fn: (*) => LineEditFeature.DuplicateLine()},
            {ctx: "editor", key: "$^+Up", group: "编辑", line: "   Ctrl+Shift+↑     上移当前行"
                , fn: (*) => LineEditFeature.MoveUp()},
            {ctx: "editor", key: "$^+Down", group: "编辑", line: "   Ctrl+Shift+↓     下移当前行"
                , fn: (*) => LineEditFeature.MoveDown()},
            {ctx: "editor", key: "Tab", group: "编辑", line: "   Tab              增加缩进（4 空格）"
                , fn: (*) => LineEditFeature.Indent()},
            {ctx: "editor", key: "+Tab", group: "编辑", line: "   Shift+Tab        减少缩进"
                , fn: (*) => LineEditFeature.Outdent()},
            {ctx: "editor", key: "$^+v", group: "编辑", line: "   Ctrl+Shift+V     粘贴为纯文本"
                , fn: (*) => PasteFeature.PastePlain()},

            ; ── 【分段】──
            {ctx: "editor", key: "$^t", group: "分段", line: "   Ctrl+T           追加时间戳"
                , fn: (*) => TimestampFeature.Append()},
            {ctx: "editor", key: "$^h", group: "分段", line: "   Ctrl+H           插入动态分隔线"
                , fn: (*) => TimestampFeature.Separator()},
            {ctx: "editor", key: "$^+h", group: "分段", line: "   Ctrl+Shift+H     插入 ## 分段标题"
                , fn: (*) => TimestampFeature.Heading()}
        ]
    }

    static GetMetadata() {
        return {name: this.Name, desc: "笔记编辑与检索", order: 10
            , hotkeys: this.GetHotkeys()}
    }

    ; 笔记模块负责 editor / search 两个上下文；Router 不再引用模块内部类
    static GetContexts() {
        return {
            editor: (*) => WinActive("ahk_id " . State.GetGuiHwnd()) && !SearchFeature.IsVisible(),
            search: (*) => WinActive("ahk_id " . State.GetGuiHwnd()) && SearchFeature.IsVisible()
        }
    }
}