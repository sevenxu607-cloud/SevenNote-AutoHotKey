#Requires AutoHotkey v2.0
; ======================================================================
;  BackdropFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

; ─── BackdropFeature：带背景图的主题（星空）───
; 背景图不是「全局贴一张」，而是主题自带的属性：ThemeService.Themes 里带 bg 字段的
; 主题（目前只有「星空」）才铺图，切到别的主题自动撤掉、回到纯底色。
; 文字浮在图上、图铺满整个编辑区（终端式，非相框式）。
class BackdropFeature {
    static _lastW := 0
    static _lastH := 0
    static _applied := false  ; 当前是否已铺图（启动期窗口尺寸是 0，此时为 false）
    static _bgPath := ""      ; 当前主题生效的背景图路径（空 = 该主题没有背景图）
    static _bgAlpha := 60     ; 当前生效的遮罩不透明度（0-100）

    static _pending := false  ; 已排入一次延迟铺图（防抖合并中）
    static _doneX := 0        ; 上一次真正铺图用的矩形：同尺寸的 WM_SIZE 直接跳过
    static _doneY := 0
    static _doneW := 0
    static _doneH := 0

    ; ⚠ 必须与 SevenNoteModule.OnSize 里 ed.Move 的矩形完全一致，否则图层会与编辑区错位
    static _Rect(winW, winH) {
        if State.GetSearchVisible()
            return {x: 8, y: 72, w: winW - 16, h: winH - 110}
        return {x: 8, y: 32, w: winW - 16, h: winH - 70}
    }

    static Init(g) {
        BackdropService.Attach(g)
        ; 换主题 = 换背景图：带 bg 的主题铺图，其余撤图。没有开关 —— 想关就切主题，
        ; 这也正是「往 Themes 里加一行就是一套新主题」的原设计。
        EventBus.On("Theme.Changed", (*) => this.Refresh())
    }

    ; 按当前主题刷新「图路径 + 遮罩色 + 不透明度」缓存 —— 图只认主题自带的 bg / bgAlpha。
    ; ⚠ 原先还有一对全局覆盖键（[Appearance] BackdropImage / BackdropOpacity），已删：
    ;   它是「全局覆盖」，一旦写上会盖掉**所有**带 bg 的主题（多套图主题并存时没法定制
    ;   各自的浓淡）；换图 / 调压暗的正确做法就是改主题自己的 bg / bgAlpha，重烘走
    ;   tools\rebake-backdrop.ps1。
    static _Sync() {
        t := ThemeService.Themes[ThemeService.GetCurrent()]
        hasBg := (IsObject(t) && t.HasProp("bg"))

        this._bgPath := hasBg ? t.bg : ""
        BackdropService.SetImage(this._bgPath)

        ; 没图的主题给 60：那是「图缺失时铺底色」用的遮罩不透明度
        this._bgAlpha := hasBg ? t.bgAlpha : 60

        ; 缩放模式：主题写了 bgFit 就按它来（竖版人物图得用 contain，否则上下会被裁掉），
        ; 没写的（含「星空」等老主题）一律 cover —— 铺图行为分毫不变。
        BackdropService.SetFit(hasBg && t.HasProp("bgFit") ? t.bgFit : "cover")

        ; 遮罩色取主题编辑区底色，图的色调就跟着主题走（图缺失时它就是那块纯底色）
        BackdropService.SetMask(hasBg ? t.edBg : "", this._bgAlpha)
    }

    static Refresh() {
        this._Sync()
        this._Apply()
    }

    ; 窗口尺寸变化：记下尺寸，已铺图则按新尺寸重铺
    static Layout(winW, winH) {
        this._lastW := winW
        this._lastH := winH
        ; 启动时窗口尚未 Show，尺寸仍是 0，此时不铺；首次拿到有效尺寸后补一次，
        ; 否则图会一直不出来。
        if !this._applied {
            if (this._bgPath != "" && BackdropService.HasImage())
                this._Apply()
            return
        }
        ; ⚠ 拉伸窗口时 WM_SIZE 每秒触发几十次，而每次都重做整张合成 —— 2400 宽的图
        ;   逐级对折 + HALFTONE 缩放本机要几十毫秒，绘制队列被塞满，编辑区文字跟着
        ;   反复重画，看上去就是「文字时隐时无」。这里改成防抖：先记下尺寸，停手
        ;   80ms 后才铺一次；拖动过程中背景停在上一帧，不再与文字抢绘制。
        this._ScheduleRender()
    }

    ; 把 80ms 内的连续尺寸变化合并成一次铺图（拖窗口时每秒几十次 WM_SIZE 只干一次活）
    static _ScheduleRender() {
        if this._pending
            return
        this._pending := true
        SetTimer(() => this._RenderNow(), -80)
    }

    ; 真正铺图。矩形与上次相同就不重做合成（同尺寸的 WM_SIZE 是空转）。
    ; force = true 用于换主题 —— 那时尺寸可能没变，但图换了，必须重铺。
    static _RenderNow(force := false) {
        this._pending := false
        rect := this._Rect(this._lastW, this._lastH)
        if (!force && (rect.x = this._doneX) && (rect.y = this._doneY)
            && (rect.w = this._doneW) && (rect.h = this._doneH))
            return
        if BackdropService.Render(rect.x, rect.y, rect.w, rect.h) {
            this._doneX := rect.x, this._doneY := rect.y
            this._doneW := rect.w, this._doneH := rect.h
            ; 位图刚换过，而编辑区是 WS_EX_TRANSPARENT（自己不画背景），面上留着的
            ; 还是上一帧的文字 —— 让它重画一次，免得拉伸后出现「文字缺一块」。
            ; 不带 UPDATENOW：走正常消息队列，别在拖动时同步阻塞。
            try DllCall("RedrawWindow", "ptr", State.GetEd(), "ptr", 0, "ptr", 0
                , "uint", 0x0001 | 0x0004)      ; INVALIDATE | ERASE
        }
    }

    ; 按 _bgPath 决定铺图还是撤图：主题没带 bg、图片不存在、窗口还没尺寸 —— 三种都走撤图。
    static _Apply() {
        hwndEd := State.GetEd()
        if !hwndEd
            return
        useIt := this._applied := (this._bgPath != "" && BackdropService.HasImage()
            && this._lastW > 1 && this._lastH > 1)

        if useIt {
            BackdropService.SetVisible(true)
            this._RenderNow(true)          ; 换主题 / 首次铺图：立即铺，不走 80ms 防抖
            ; 图铺好之后再开透明，避免出现「编辑区已不画背景、图还没画」的空窗
            this._SetEdTransparent(hwndEd, true)   ; WS_EX_TRANSPARENT
        } else {
            ; 先恢复不透明再撤图，顺序反过来会闪一下白底
            this._SetEdTransparent(hwndEd, false)
            BackdropService.SetVisible(false)
            ; 撤图后清掉尺寸记忆，同尺寸再切回图主题时才会真的重铺
            this._doneW := 0, this._doneH := 0
        }

        try DllCall("RedrawWindow", "ptr", hwndEd, "ptr", 0, "ptr", 0
            , "uint", 0x0001 | 0x0004 | 0x0100)   ; INVALIDATE | ERASE | UPDATENOW
    }

    ; ─── 编辑区的「透明」扩展样式（WS_EX_TRANSPARENT = 0x20）开关 ───
    ; ⚠ 不能用 AHK 的 WinSetExStyle —— 窗口**最小化**时它必抛「(6) 句柄无效。」：
    ;   实测最小化窗口上 SetWindowLongPtr 把样式**真写进去了**（读回 EXSTYLE 确实变了），
    ;   却把 ERROR_INVALID_HANDLE 留在 LastError，而 AHK 据「返回 0（旧样式为 0）+ LastError≠0」
    ;   判成失败。!t 又是全局热键（不在 #HotIf 内），窗口最小化着照样能切主题 ——
    ;   于是「最小化状态下从无图主题切到带图主题」就是一次崩溃：模态错误框一弹、脚本停摆。
    ;   改走 DllCall 直接写，**只认读回的样式、不看 LastError**，最小化下照设不误。
    ;   顺带也不再需要 DetectHiddenWindows(true)：这条路不经过 AHK 的窗口查找，不会把
    ;   全局可见性语义永久改成 true（原来那行只开不还原，是另一处隐患）。
    static _SetEdTransparent(hwndEd, on) {
        ; 32 位没有 SetWindowLongPtr，退回 SetWindowLong（本机要求 64 位运行，这里只为不抛错）
        get := (A_PtrSize = 8) ? "GetWindowLongPtr" : "GetWindowLong"
        set := (A_PtrSize = 8) ? "SetWindowLongPtr" : "SetWindowLong"
        ex := DllCall(get, "ptr", hwndEd, "int", -20, "ptr")   ; GWL_EXSTYLE
        want := on ? (ex | 0x20) : (ex & ~0x20)
        if (want = ex)
            return
        DllCall(set, "ptr", hwndEd, "int", -20, "ptr", want, "ptr")
    }
}
