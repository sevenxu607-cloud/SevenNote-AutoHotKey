#Requires AutoHotkey v2.0
; ======================================================================
;  StatFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class StatFeature {
    static _lastLen := -1
    static Init(intervalMs := 500) {
        SetTimer(() => StatFeature.Tick(), intervalMs)
    }
    ; ⚠ 500ms 一次的常驻计时器：窗口收起 / 最小化时不必刷新字数 —— 隐藏态照跑
    ;   SendMessage 读长度是纯白耗。守卫与 AutoSaveFeature.Tick 同一套：
    ;   最小化窗口的 IsWindowVisible 仍是 1，必须再排掉 IsIconic。
    static Tick() {
        stat := State.GetStat()
        if !stat
            return
        hwnd := State.GetEd()
        if !hwnd
            return
        if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
            return
        if DllCall("IsIconic", "ptr", hwnd, "int")
            return
        len := EditorService.GetLength(hwnd)
        if (len != this._lastLen) {
            ; 内容变短时 RichEdit 只重算 SCROLLINFO、不重算行布局也不重绘 ——
            ; 表现为画面停在删除前，得拖一下滚动条才闪回。
            ; ⚠ 这里是 500ms 一次的兜底：删完最多等半秒画面才跟手，肉眼「慢半拍」。
            ;   想更快得换触发方式，但 EN_CHANGE 在本项目的 RichEdit50W 上实测掩码
            ;   设不上（EM_SETEVENTMASK 读回恒为 0x0，WM_COMMAND 一次都不来），
            ;   50ms 轮询那一版在真机上出过问题，暂留在 %TEMP% 备份里不启用。
            ; 首次调用（_lastLen = -1）不触发。
            if (this._lastLen >= 0 && len < this._lastLen)
                EditorService.SyncScrollAfterShrink(hwnd)
            this._lastLen := len
            stat.Value := len . " 字"
        }
    }
}
