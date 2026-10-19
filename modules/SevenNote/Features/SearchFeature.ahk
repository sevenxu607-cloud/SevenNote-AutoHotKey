#Requires AutoHotkey v2.0
; ======================================================================
;  SearchFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class SearchFeature {
    static BAR_BG := "E8D8B8"
    static EDIT_BG := "FFF8E7"
    static EDIT_TEXT := "3D2B1F"
    static BAR_DIM := "9C8060"
    static BAR_W := 220

    static _barBg := ""
    static _icon := ""
    static _edit := ""
    static _count := ""
    static _stat := ""
    static _themeLabel := ""
    static _edCtrl := ""

    static _visible := false
    static _lastKeyword := ""
    ; 正文长度 —— 缓存的第二把锁（见 _DoSearch）：关键字没变但正文变了，旧偏移同样作废
    static _lastLen := -1
    static _matches := []
    static _current := 0

    static Init(barBg, icon, edit, count, statCtrl, themeLabelCtrl, edCtrl) {
        this._barBg := barBg
        this._icon := icon
        this._edit := edit
        this._count := count
        this._stat := statCtrl
        this._themeLabel := themeLabelCtrl
        this._edCtrl := edCtrl
        this._SetVisible(false)
        ; 搜索条配色跟着主题走：否则「星空」底下会横插一块浅米黄
        this._ApplyColors()
        EventBus.On("Theme.Changed", (*) => this._ApplyColors())
        ; 换日期 = 换了一篇正文，照旧正文算出来的匹配偏移全部作废
        EventBus.On("Date.Changed", (*) => this._ResetMatches())
    }

    ; 丢掉匹配缓存：关键字一起忘掉，逼下一次搜索重算。
    ; ⚠ 不清会出事 —— 关键字没变就复用 _matches 里的旧字符偏移，
    ;   而正文可能已经换了（切日期 / 手动编辑），SetSel 会选到错误位置。
    static _ResetMatches() {
        this._lastKeyword := ""
        this._lastLen := -1
        this._matches := []
        this._current := 0
    }

    static IsVisible() => this._visible

    static Show() {
        if this._visible
            return
        ; 每次打开都丢掉上次的缓存：搜索条关着的时候正文是能改的
        this._ResetMatches()
        this._visible := true
        State.SetSearchVisible(true)
        this._SetVisible(true)

        g := State.GetGui()
        if g {
            WinGetClientPos(&cx, &cy, &w, &h, "ahk_id " . g.Hwnd)
            try this._edCtrl.Move(8, 72, w - 16, h - 110)
        }

        hwndEd := this._edCtrl.Hwnd
        minBuf := Buffer(4, 0)
        maxBuf := Buffer(4, 0)
        DllCall("SendMessage"
            , "ptr", hwndEd
            , "uint", 0x00B0
            , "ptr", minBuf.Ptr
            , "ptr", maxBuf.Ptr)
        curMax := NumGet(maxBuf, 0, "uint")
        DllCall("SendMessage"
            , "ptr", hwndEd
            , "uint", 0x00B1
            , "ptr", curMax
            , "ptr", curMax)

        this._edit.Focus()
        DllCall("SendMessage"
            , "ptr", this._edit.Hwnd
            , "uint", 0x00B1
            , "ptr", 0
            , "ptr", 0x7FFFFFFF)
    }

    static Hide() {
        if !this._visible
            return
        this._visible := false
        State.SetSearchVisible(false)
        this._SetVisible(false)

        g := State.GetGui()
        if g {
            WinGetClientPos(&cx, &cy, &w, &h, "ahk_id " . g.Hwnd)
            try this._edCtrl.Move(8, 32, w - 16, h - 70)
        }

        hwndEd := this._edCtrl.Hwnd
        minBuf := Buffer(4, 0)
        maxBuf := Buffer(4, 0)
        DllCall("SendMessage"
            , "ptr", hwndEd
            , "uint", 0x00B0
            , "ptr", minBuf.Ptr
            , "ptr", maxBuf.Ptr)
        savedMax := NumGet(maxBuf, 0, "uint")
        DllCall("SetFocus", "ptr", hwndEd)
        DllCall("SendMessage"
            , "ptr", hwndEd
            , "uint", 0x00B1
            , "ptr", savedMax
            , "ptr", savedMax)
    }

    static Toggle() {
        if this._visible
            this.Hide()
        else
            this.Show()
    }

    static _SetVisible(v) {
        try this._barBg.Visible := v
        try this._icon.Visible := v
        try this._edit.Visible := v
        try this._count.Visible := v
    }

    ; ─── 配色：跟着当前主题走 ───
    ; 搜索条底色要比编辑区深一档才分得出来（深色主题下方向相反），所以统一用
    ; 「主题编辑区底色 + 25% 次级文字色」混出来，浅色 / 深色两边都自然。
    static _ApplyColors() {
        t := ThemeService.Themes[ThemeService.GetCurrent()]
        if !IsObject(t)
            return
        barBg := this._Mix(t.edBg, t.dim, 25)
        for ctrl in [this._barBg, this._icon, this._count]
            try ctrl.Opt("Background" . barBg)
        try this._icon.Opt("c" . t.dim)
        try this._count.Opt("c" . t.dim)
        try this._edit.Opt("Background" . t.edBg . " c" . t.text)
    }

    ; 两个十六进制 RGB 之间线性插值，pct = 第二个色的百分比（0-100）
    static _Mix(hexA, hexB, pct) {
        out := ""
        loop 3 {
            i := (A_Index - 1) * 2
            a := Integer("0x" . SubStr(hexA, i + 1, 2))
            b := Integer("0x" . SubStr(hexB, i + 1, 2))
            out .= Format("{:02X}", Round(a + (b - a) * pct / 100))
        }
        return out
    }

    static Layout(winWidth, winHeight) {
        try this._barBg.Move(8, 32, this.BAR_W, 32)
        try this._icon.Move(12, 38, 22, 20)
        try this._edit.Move(36, 36, 130, 24)
        try this._count.Move(170, 39, 44, 20)
    }

    static Next() => this._DoSearch("down")
    static Prev() => this._DoSearch("up")

    static _DoSearch(direction) {
        hwndEd := State.GetEd()
        kw := this._edit.Value
        if (kw = "") {
            this._ResetMatches()
            this._count.Value := ""
            return
        }

        ; 缓存复用条件：关键字没变**且**正文长度没变。
        ; ⚠ 搜索条开着时编辑器热键被 #HotIf 挡掉，但鼠标点进编辑区照样能打字 ——
        ;   那时关键字不变而正文已变，复用旧偏移会让下面 SetSel 选到错误位置。
        ;   用「正文长度」当脏标记：字数一变长度必变，代价一次 WM_GETTEXTLENGTH（O(1)）。
        ;   已知残留：等长替换（改掉一个字符而不改字数）测不出来，属罕见边缘。
        lenNow := EditorService.GetLength(hwndEd)
        if (kw != this._lastKeyword || lenNow != this._lastLen) {
            this._lastKeyword := kw
            this._lastLen := lenNow
            this._matches := []
            pos := 0
            while (true) {
                r := EditorService.FindTextEx(hwndEd, kw, pos, "down")
                if (r = -1)
                    break
                this._matches.Push(r)
                pos := r.end
            }
            this._current := 0
        }

        if (this._matches.Length = 0) {
            this._count.Value := "未找到"
            return
        }

        if (direction = "down") {
            this._current++
            if (this._current > this._matches.Length)
                this._current := 1
        } else {
            this._current--
            if (this._current < 1)
                this._current := this._matches.Length
        }

        m := this._matches[this._current]

        DllCall("SetFocus", "ptr", hwndEd)
        DllCall("SendMessage"
            , "ptr", hwndEd
            , "uint", 0x00B1
            , "ptr", m.start
            , "ptr", m.end)

        lineIdx := SendMessage(0x00C9, m.start, 0, hwndEd)
        EditorService.ScrollToLineFixed(hwndEd, lineIdx)

        ; 焦点还给搜索框 —— 延迟 300ms 是因为刚把焦点交给编辑区选词，抢太早会丢选中。
        ; ⚠ 走守卫：这 300ms 内用户可能已经 Esc 关掉搜索条、或收起整个窗口，
        ;   那时直接 Focus() 会抛异常，而 SetTimer 回调没有外层 try（弹框停摆）。
        SetTimer(() => this._RefocusSearchBox(), -300)

        this._count.Value := this._current . "/" . this._matches.Length
    }

    ; 把焦点还给搜索框。搜索条已隐藏或尚未初始化就不动 ——
    ; 免得把焦点塞给一个看不见的控件（那会把焦点赶到别处去）。
    static _RefocusSearchBox() {
        if !this._visible || !this._edit
            return
        try this._edit.Focus()
    }
}
