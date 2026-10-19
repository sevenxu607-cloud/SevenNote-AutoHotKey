#Requires AutoHotkey v2.0
; ======================================================================
;  AutoSaveFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class AutoSaveFeature {
    static Init(intervalMs := 120000) {
        SetTimer(() => AutoSaveFeature.Tick(), intervalMs)
    }
    ; ⚠ 最小化窗口的 IsWindowVisible 仍是 1（见 README「六个必须守住的点」）——
    ;   只看它就成了「窗口缩在任务栏里也每 2 分钟存一次盘」，故必须再排掉 IsIconic。
    static Tick() {
        g := State.GetGui()
        if !IsObject(g)
            return
        hwnd := g.Hwnd
        if DllCall("IsIconic", "ptr", hwnd, "int")
            return
        if DllCall("IsWindowVisible", "ptr", hwnd, "int")
            EventBus.Emit("Save.Requested")
    }
}
