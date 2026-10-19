#Requires AutoHotkey v2.0
; WorkBench/Kernel/State.ahk
; Moved from SevenNote.ahk (Phase 1). Implementation unchanged.

class State {
    static _guiObj := ""
    static _edHwnd := 0
    static _statObj := ""
    static _loadedDate := ""
    static _caretMin := -1
    static _caretMax := -1

    static _hiddenX := ""
    static _hiddenY := ""
    static _hiddenW := ""
    static _hiddenH := ""

    static _dateCtrl := ""
    static _msgCtrl := ""
    static _themeLabel := ""
    static _tagCtrl := ""
    static _searchVisible := false   ; 搜索条是否展开（编辑区矩形要按它算）

    static GetGui() => this._guiObj
    ; 供 #HotIf 等表达式安全取主窗口句柄：GUI 尚未创建时返回 0
    ; （否则 "".Hwnd 会抛 "String has no property named Hwnd"）
    static GetGuiHwnd() => IsObject(this._guiObj) ? this._guiObj.Hwnd : 0
    static SetGui(g) {
        this._guiObj := g
        ; ⚠ 当前没有订阅者：这是「窗口就绪」扩展点，不是漏掉的接线（骨架层冻结，只加不改）
        EventBus.Emit("Gui.Ready", g)
    }

    static GetEd() => this._edHwnd
    static SetEd(hwnd) {
        this._edHwnd := hwnd
        ; ⚠ 同上：暂无订阅者，保留作「编辑区就绪」扩展点
        EventBus.Emit("Editor.Ready", hwnd)
    }

    static GetStat() => this._statObj
    static SetStat(s) => this._statObj := s

    static GetDateCtrl() => this._dateCtrl
    static SetDateCtrl(c) => this._dateCtrl := c
    static GetMsgCtrl() => this._msgCtrl
    static SetMsgCtrl(c) => this._msgCtrl := c
    static GetThemeLabel() => this._themeLabel
    static SetThemeLabel(c) => this._themeLabel := c
    static GetTagCtrl() => this._tagCtrl
    static SetTagCtrl(c) => this._tagCtrl := c

    static GetSearchVisible() => this._searchVisible
    static SetSearchVisible(v) => this._searchVisible := v

    static GetDate() => this._loadedDate
    static SetDate(d) {
        old := this._loadedDate
        this._loadedDate := d
        EventBus.Emit("Date.Changed", {old: old, new: d})
    }

    static GetCaret() => {min: this._caretMin, max: this._caretMax}
    static SetCaret(min, max) {
        this._caretMin := min
        this._caretMax := max
    }
    static HasCaret() => this._caretMin >= 0
    static ResetCaret() {
        this._caretMin := -1
        this._caretMax := -1
    }

    static GetHiddenRect() => {
        x: this._hiddenX, y: this._hiddenY,
        w: this._hiddenW, h: this._hiddenH
    }
    static SetHiddenRect(x, y, w, h) {
        this._hiddenX := x
        this._hiddenY := y
        this._hiddenW := w
        this._hiddenH := h
    }
    static HasHiddenRect() => (this._hiddenX != "")
    static ClearHiddenRect() {
        this._hiddenX := ""
        this._hiddenY := ""
        this._hiddenW := ""
        this._hiddenH := ""
    }
}
