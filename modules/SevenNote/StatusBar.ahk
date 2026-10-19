#Requires AutoHotkey v2.0
; ======================================================================
;  StatusBar
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

; ─── StatusBar：状态栏 ───
class StatusBar {
    static _dateCtrl := ""
    static _tagCtrl := ""
    static _msgCtrl := ""
    static _clearTimer := 0

    static Init(dateCtrl, tagCtrl, msgCtrl) {
        this._dateCtrl := dateCtrl
        this._tagCtrl := tagCtrl
        this._msgCtrl := msgCtrl
        this.SetMsg("就绪")

        EventBus.On("Date.Changed",       (d) => this.SetDate(d.new))
        EventBus.On("Date.Switched",      (d) => (
            this.SetMsg("→ 已切换到 " . d.date),
            this.RefreshTag()))
        EventBus.On("Save.Completed",     (d) => (
            this.SetMsg("✓ 已保存 " . d.time),
            this.RefreshTag()))
        EventBus.On("Timestamp.Appended", (*) => this.SetMsg("✓ 已追加时间戳"))
        EventBus.On("Separator.Inserted", (*) => this.SetMsg("✓ 已插入分隔线"))
        EventBus.On("Heading.Inserted",   (*) => this.SetMsg("✓ 已插入分段标题"))
        EventBus.On("Paste.Plain",        (*) => this.SetMsg("✓ 已粘贴纯文本"))
        EventBus.On("Theme.Changed",      (d) => this.SetMsg("✓ 主题：" . d.name))
        EventBus.On("Font.Changed",       (d) => this.SetMsg("✓ 字体：" . d.name . " " . d.size . "pt"))
        EventBus.On("Line.Indented",      (*) => this.SetMsg("✓ 已缩进"))
        EventBus.On("Line.Outdented",     (*) => this.SetMsg("✓ 已取消缩进"))
        EventBus.On("CapsLock.Toggled",   (d) => this.SetMsg(d.msg))
        EventBus.On("Title.Changed",      (d) => (
            this.SetTag(d.tag),
            this.SetMsg(d.tag = "" ? "✓ 标签已清除" : "✓ 标签：" . d.tag)))
        EventBus.On("Error.Occurred",     (d) => this.SetMsg("✗ " . d.msg))
    }

    ; v1.8：日期后拼接星期
    static SetDate(d) {
        if !this._dateCtrl
            return
        weekday := NoteStoreService.GetWeekday(d)
        this._dateCtrl.Value := "📅 " . d . " " . weekday
    }

    static SetTag(tag) {
        if !this._tagCtrl
            return
        if (tag = "")
            this._tagCtrl.Value := ""
        else
            this._tagCtrl.Value := "🏷 " . tag
    }

    static RefreshTag() {
        date := State.GetDate()
        if (date = "") {
            this.SetTag("")
            return
        }
        rtfPath := NoteStoreService.FindRtf(date)
        tag := (rtfPath != "")
            ? NoteStoreService.TagFromFileName(rtfPath) : ""
        this.SetTag(tag)
    }

    static SetMsg(msg) {
        if !this._msgCtrl
            return
        this._msgCtrl.Value := msg
        if this._clearTimer
            SetTimer(this._clearTimer, 0)
        ; ⚠ 回调里摸控件，得先过一道闸（见 .clinerules/03「异步定时器里操作窗口」）：
        ;   提示是 2 秒后才清的，这期间窗口可能已被收走甚至销毁（Alt+Shift+Z 退出），
        ;   那时 `_msgCtrl.Value` 会抛异常 —— 而 SetTimer 回调没有外层 try，
        ;   异常直接变成模态框，整个程序停摆。
        this._clearTimer := () => this._ClearMsg()
        SetTimer(this._clearTimer, -2000)
    }

    ; 清空提示栏。失败（控件已随窗口销毁）就让它失败 —— 这正是 try 的用途。
    static _ClearMsg() {
        try this._msgCtrl.Value := ""
    }
}
