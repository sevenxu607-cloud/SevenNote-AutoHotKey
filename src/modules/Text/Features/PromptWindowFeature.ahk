#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  PromptWindowFeature —— 提示词库主窗口（模块：Text）
; ═══════════════════════════════════════════════════════════════════════════
; 职责：建窗（首次呼出时懒建）/ Toggle / 列表填充 / 检索过滤 / Enter 进编辑。
; 不碰磁盘 —— 读写全归 PromptStoreService；不碰编辑窗 —— Enter 交给 PromptEditFeature。
;
; 交互（用户 2026-10-20 定调）：
;   单击        → 只选中，既不复制也不编辑
;   Enter       → 进入编辑窗口（改标题 / 分类 / 正文）
;   双击        → 直接复制到剪贴板 + 窗口立即收起（复制是高频动作：一发拿到就走）
;   Esc         → 隐藏
;
; 配色：读**平台主题**（ThemeService.Palette()）并订阅 Theme.Changed 跟着换。
; 主题在 v2.9 上收到 WorkBench\Services 之后是平台服务、不是「别的模块」——
; 所以 Feature 读它不违反「Feature 之间零调用」。
; （第一版写死米黄的注释留在这里作历史：那时主题还在笔记模块里，
;   跨模块取色确实只能靠 EventBus 载荷带色值。）

class PromptWindowFeature {
    ; ─── 色板映射（语义 → 用在哪）─────────────────────────────────────────
    ;   win     窗口底
    ;   codeBg  列表 / 搜索框底
    ;           ⚠ 不用 edBg：纯米黄 / 星空 / 金克斯三套主题里 win == edBg，
    ;             列表会和窗口糊成一片、看不出边界。codeBg 恒比 edBg 偏 8–12 档。
    ;   text    正文
    ;   dim     状态行
    ; ⚠ 别再写死颜色 —— 换主题时整窗要跟着变，写死就成了"一块不听话的米黄"。

    ; 首屏落点：工作区右上角，右边距 Config.PlaceRight，顶边下移 120 物理像素
    static PlaceTop := 120

    static _gui := ""
    static _lv := ""
    static _search := ""
    static _btn := ""
    static _status := ""

    static _all := []      ; 磁盘上的全部条目（未过滤）
    static _items := []    ; 当前列表里显示的行，下标 = ListView 行号
    static _placed := false
    static _statusTimer := ""   ; 「已保存 / 已删除」提示的回落定时器（闭包引用）
    static _tipTimer := ""      ; 复制后收窗时那条 ToolTip 的清除定时器（闭包引用）

    ; ═══ 显隐 ═══

    ; 窗口句柄；未建 / 已被销毁都返回 0
    static Hwnd() {
        if !IsObject(this._gui)
            return 0
        try return this._gui.Hwnd
        catch
            return 0
    }

    ; 是否真的「看得见」。⚠ 最小化窗口的 IsWindowVisible 仍是 1，必须同时排掉 IsIconic
    static IsShowing() {
        hwnd := this.Hwnd()
        if !hwnd
            return false
        return !!DllCall("IsWindowVisible", "ptr", hwnd, "int")
            && !DllCall("IsIconic", "ptr", hwnd, "int")
    }

    static Toggle() {
        if this.IsShowing()
            this.Hide()
        else
            this.Show()
    }

    static Show() {
        ; 点标题栏 X 或外部原因把窗口销毁了 → 重建（位置重新落一次）
        if !this.Hwnd() {
            this._gui := ""
            this._placed := false
            this._Build()
        }

        ; 每次呼出都重扫：文件可能在程序外被改（用户在 VS Code / 资源管理器里改）
        this.Reload(true)

        if !this._placed {
            ; 先 Show("Hide") 再量尺寸 / 摆位置，最后一次性露面 ——
            ; 直接 Show 会先在默认落点露一下再跳走（见 .clinerules/03「先 Show 再 WinMove」）
            this._gui.Show("Hide")
            this._PlaceFirstTime()
            this._placed := true
            this._gui.Show()
        } else {
            this._gui.Show()
        }

        try WinActivate("ahk_id " . this.Hwnd())
        try this._search.Focus()
    }

    static Hide() {
        if IsObject(this._gui)
            try this._gui.Hide()
    }

    ; ═══ 列表 ═══

    static Reload(force := false) {
        if !IsObject(this._lv)
            return
        this._all := PromptStoreService.LoadAll(force)
        this._ApplyFilter()
    }

    ; 按关键词重建列表。空关键词 = 全部。
    ; 匹配**标题与分类**（不搜正文 —— 提示词通常短，标题能命中就够，且快得多）。
    static _ApplyFilter() {
        if !IsObject(this._lv)
            return
        kw := ""
        try kw := Trim(this._search.Value)

        this._lv.Opt("-Redraw")
        this._lv.Delete()
        this._items := []
        for it in this._all {
            if (kw != "" && !InStr(it.title, kw) && !InStr(it.category, kw))
                continue
            this._items.Push(it)
            this._lv.Add(, it.category, it.title, it.summary)
        }
        this._lv.Opt("+Redraw")

        if (this._items.Length > 0)
            this._lv.Modify(1, "Select Focus Vis")
        this._UpdateStatus()
    }

    ; 保存 / 删除之后把列表定位到那一条上，省得用户自己找
    static FocusPath(path) {
        if !IsObject(this._lv) || path = ""
            return
        for i, it in this._items {
            if (it.path != path)
                continue
            this._lv.Modify(i, "Select Focus Vis")
            return
        }
    }

    static _UpdateStatus(msg := "") {
        if !IsObject(this._status)
            return
        n := this._items.Length
        tail := n . " 条 · Enter 编辑 · 双击复制 · Esc 关闭"
        this._status.Value := (msg = "" ? "" : msg . "　·　") . tail
    }

    ; 给用户一次「操作成功」的确认（保存 / 删除之后），4 秒后自动回到默认提示。
    ; ⚠ 用箭头函数 + 保存引用：AHK v2.0.27 的 SetTimer 不接受类静态方法的函数对象
    ;   （报 "Invalid callback function"），而箭头函数每次是新对象、SetTimer 认不出
    ;   是同一个 —— 所以要留着引用，连续调用时先把上一个停掉。
    static Notify(msg) {
        this._UpdateStatus(msg)
        this._StopStatusTimer()
        timerFn := () => this._ClearStatus()
        this._statusTimer := timerFn
        SetTimer(timerFn, -4000)
    }

    static _StopStatusTimer() {
        timerFn := this._statusTimer
        this._statusTimer := ""
        if IsObject(timerFn)
            try SetTimer(timerFn, 0)
    }

    static _ClearStatus(*) {
        this._UpdateStatus()
    }

    ; ═══ 动作 ═══

    ; Enter：进入编辑窗口。没选中时取「有焦点的那一行」（列表刚打开时就是它）。
    static EditSelected() {
        row := this._SelectedRow()
        if !row {
            this._UpdateStatus("没有选中项")
            return
        }
        PromptEditFeature.Open(this._items[row])
    }

    ; 双击某行 → 直接复制，**不**进编辑（用户 2026-10-20 定调：
    ; 复制是高频动作，双击一发就拿到；想改内容才按 Enter）。
    ; ⚠ 双击必然伴随两次单击，而单击已经把该行选中了，所以这里的 row 与
    ;   _SelectedRow() 一致；双击表头下方空白处时 row = 0，退回按选中行处理。
    static _OnItemActivate(row) {
        if (!row || row > this._items.Length)
            row := this._SelectedRow()
        if !row
            return
        this._CopyRow(row)
    }

    ; 当前选中的行号；没选中返回 0。
    ; ⚠ GetNext() 只认「选中」，GetNext(0, "F") 认「有焦点」—— 键盘移过后两者可能
    ;   不同，选中优先（用户点了哪行就是哪行）。
    static _SelectedRow() {
        if !IsObject(this._lv)
            return 0
        row := 0
        try row := this._lv.GetNext()
        if !row
            try row := this._lv.GetNext(0, "F")
        if (!row || row > this._items.Length)
            return 0
        return row
    }

    ; 复制某一行的正文到剪贴板，**成功即收窗**。
    ; 用户 2026-10-20 定调：双击 → 窗口消失 → 直接 Ctrl+V，这才叫「快速启用」。
    ; 所以状态行那句「已复制」在这里没用（窗口已经藏了、看不见），改用 ToolTip
    ; 在鼠标旁闪 1.2 秒给个确认；失败的提示留在窗口里并**不**收窗 —— 收了就看不到了。
    static _CopyRow(row) {
        it := this._items[row]
        try {
            A_Clipboard := it.text
        } catch {
            ; 剪贴板被别的进程占着（远程桌面 / 剪贴板管理器会这样）
            this._UpdateStatus("复制失败：剪贴板被占用")
            return
        }
        this.Hide()
        this._Tip("已复制「" . it.title . "」")
    }

    ; 轻量确认：窗口已收，状态行看不到，就在鼠标旁闪一下
    static _Tip(msg) {
        try ToolTip(msg)
        this._StopTipTimer()
        timerFn := () => this._ClearTip()
        this._tipTimer := timerFn
        SetTimer(timerFn, -1200)
    }

    static _StopTipTimer() {
        timerFn := this._tipTimer
        this._tipTimer := ""
        if IsObject(timerFn)
            try SetTimer(timerFn, 0)
    }

    static _ClearTip(*) {
        this._tipTimer := ""        ; 自然触发后也要放掉引用，别让字段一直攥着闭包
        try ToolTip()
    }

    ; 新建按钮 / Ctrl+N
    static NewPrompt() {
        PromptEditFeature.Open("")
    }

    ; ═══ 建窗（首次呼出时才建，启动时不多一个隐藏窗口）═══

    static _Build() {
        ; 建窗时就按当期主题上色；之后按 Alt+T 走 OnThemeChanged() 重刷。
        p := ThemeService.Palette()

        g := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", Config.AppName . " · 提示词库")
        g.BackColor := p.win
        g.SetFont("s11", "楷体")

        ; 第一版固定尺寸（620x520 逻辑）：不做 Resize。
        ; 理由见 .clinerules/03「别混用 Gui.Move 和 WinMove」—— Size 事件给的宽高单位
        ; 与控件坐标单位要先验证一遍，第一版没必要为「可拉伸」付这个风险。
        this._search := g.AddEdit("x10 y10 w496 h26")
        this._search.OnEvent("Change", (*) => this._ApplyFilter())

        this._btn := g.AddButton("x516 y10 w84 h26", "新建")
        this._btn.OnEvent("Click", (*) => this.NewPrompt())

        this._lv := g.AddListView("x10 y46 w580 h400 -Multi Grid", ["分类", "标题", "摘要"])
        this._lv.SetFont("s10", "楷体")
        this._lv.OnEvent("DoubleClick", (ctrl, row) => this._OnItemActivate(row))

        this._status := g.AddText("x10 y456 w580 h20", "")
        this._status.SetFont("s10 c" . p.dim, "楷体")

        ; 点标题栏 X = 隐藏。若 AHK 仍按默认销毁窗口，Hwnd() 会返回 0，
        ; 下次 Show() 自动重建（位置重落一次），不会留下「按了没反应」的死窗口。
        g.OnEvent("Close", (*) => this.Hide())

        this._gui := g

        ; 标题栏 / 滚动条 / 原生控件跟着主题明暗
        ; （Win11 连标题栏一起染；Win10 没有那几个属性，静默退回系统色 —— 见 UiPaint）
        UiPaint.TitleBar(g.Hwnd, p.win, p.text)
        UiPaint.WindowTheme(g.Hwnd, p.dark)
        ; 搜索框：Edit 不吃 BackColor，必须走 WM_CTLCOLOREDIT 登记
        UiPaint.EditColors(this._search.Hwnd, p.codeBg, p.text)

        ; 列宽：分类 110 / 标题 180 / 摘要 270 —— 合计 560，留 20 给纵向滚动条
        this._lv.ModifyCol(1, 110)
        this._lv.ModifyCol(2, 180)
        this._lv.ModifyCol(3, 270)

        this._PaintList(p)
    }

    ; 换主题（Alt+T）：整窗重刷。
    ; 窗口没建 / 已被销毁就直接返回 —— 下次 Show() 重建时会读当期色板，不差这一次。
    static OnThemeChanged() {
        hwnd := this.Hwnd()
        if !hwnd
            return
        p := ThemeService.Palette()
        try this._gui.BackColor := p.win
        try this._status.SetFont("s10 c" . p.dim, "楷体")
        this._PaintList(p)
        UiPaint.TitleBar(hwnd, p.win, p.text)
        UiPaint.WindowTheme(hwnd, p.dark)
        try UiPaint.EditColors(this._search.Hwnd, p.codeBg, p.text)
    }

    ; 列表配色：ListView 不吃 Gui.BackColor，走 Windows 消息单独上色（见 UiPaint.ListView）
    static _PaintList(p := 0) {
        p := IsObject(p) ? p : ThemeService.Palette()
        hwnd := 0
        try hwnd := this._lv.Hwnd
        if !hwnd
            return
        UiPaint.ListView(hwnd, p.codeBg, p.text)
    }

    ; 首次落位：隐藏态下量尺寸 → 摆到工作区右上角 → 交给调用方 Show()
    static _PlaceFirstTime() {
        hwnd := this.Hwnd()
        if !hwnd
            return

        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            x := 0, y := 0, w := 0, h := 0
            prevW := -1, prevH := -1
            ; 刚 Show("Hide") 的窗口尺寸要几轮才稳定（控件按 DPI 放大是异步的）
            loop 40 {
                try WinGetPos(&x, &y, &w, &h, "ahk_id " . hwnd)
                if (w = prevW && h = prevH && w > 0)
                    break
                prevW := w, prevH := h
                Sleep 5
            }
            if (w <= 0 || h <= 0)
                return

            wa := WindowProbe.PrimaryWorkArea()
            pos := RectMath.TopRightRect(wa, w, h, Config.PlaceRight, this.PlaceTop)
            if IsObject(pos)
                try WinMove(pos.x, pos.y, , , "ahk_id " . hwnd)
        } finally {
            DetectHiddenWindows(detectOld)
        }
    }
}
