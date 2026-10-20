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
;   双击        → 直接复制到剪贴板，**不**进编辑（复制是高频动作，一发就走）
;   Esc         → 隐藏
;
; 配色：**第一版写死米黄**，不订阅 Theme.Changed。
; 后续「界面美观优化」阶段再接主题（届时需要 ThemeService 在载荷里带上色值，
; 现在只有 {name, idx}，跨模块取色会违反「Feature 之间零调用」）。

class PromptWindowFeature {
    ; ─── 米黄配色（与帮助窗口 / 笔记窗口同族，都是 #FFF8E7 一系）───
    static BgColor    := "FFF8E7"   ; 窗口底
    static PanelColor := "FDF3D9"   ; 列表底（比窗口底稍深，层次分明）
    static TextColor  := "3D2B1F"   ; 正文（与笔记编辑区同色）
    static DimColor   := "8A7458"   ; 次要文字

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

    ; 复制某一行的正文到剪贴板
    static _CopyRow(row) {
        it := this._items[row]
        try {
            A_Clipboard := it.text
        } catch {
            ; 剪贴板被别的进程占着（远程桌面 / 剪贴板管理器会这样）
            this._UpdateStatus("复制失败：剪贴板被占用")
            return
        }
        ; 走 Notify：4 秒后状态行自己回到默认提示，不会让「已复制」一直挂着
        this.Notify("已复制「" . it.title . "」")
    }

    ; 新建按钮 / Ctrl+N
    static NewPrompt() {
        PromptEditFeature.Open("")
    }

    ; ═══ 建窗（首次呼出时才建，启动时不多一个隐藏窗口）═══

    static _Build() {
        g := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", Config.AppName . " · 提示词库")
        g.BackColor := this.BgColor
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
        this._status.SetFont("s10 c" . this.DimColor, "楷体")

        ; 点标题栏 X = 隐藏。若 AHK 仍按默认销毁窗口，Hwnd() 会返回 0，
        ; 下次 Show() 自动重建（位置重落一次），不会留下「按了没反应」的死窗口。
        g.OnEvent("Close", (*) => this.Hide())

        this._gui := g

        ; 列宽：分类 110 / 标题 180 / 摘要 270 —— 合计 560，留 20 给纵向滚动条
        this._lv.ModifyCol(1, 110)
        this._lv.ModifyCol(2, 180)
        this._lv.ModifyCol(3, 270)

        this._PaintList()
    }

    ; 列表配色：ListView 不吃 Gui.BackColor，必须走 Windows 消息单独上色
    static _PaintList() {
        hwnd := 0
        try hwnd := this._lv.Hwnd
        if !hwnd
            return
        bg := this._Bgr(this.PanelColor)
        fg := this._Bgr(this.TextColor)
        try {
            ; LVM_SETBKCOLOR / LVM_SETTEXTCOLOR / LVM_SETTEXTBKCOLOR
            SendMessage(0x1001, 0, bg, "ahk_id " . hwnd)
            SendMessage(0x1024, 0, fg, "ahk_id " . hwnd)
            SendMessage(0x1025, 0, bg, "ahk_id " . hwnd)
            ; LVM_SETEXTENDEDLISTVIEWSTYLE + LVS_EX_DOUBLEBUFFER：
            ; 每敲一个字就整表重填，不双缓冲会看到闪白
            SendMessage(0x1036, 0x00010000, 0x00010000, "ahk_id " . hwnd)
        }
    }

    ; "RRGGBB" → COLORREF（0x00BBGGRR）：Win32 的颜色是**反着**存的
    static _Bgr(hex) {
        r := Integer("0x" . SubStr(hex, 1, 2))
        g := Integer("0x" . SubStr(hex, 3, 2))
        b := Integer("0x" . SubStr(hex, 5, 2))
        return (b << 16) | (g << 8) | r
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
