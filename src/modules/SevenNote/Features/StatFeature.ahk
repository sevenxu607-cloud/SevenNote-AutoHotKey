#Requires AutoHotkey v2.0
; ======================================================================
;  StatFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class StatFeature {
    static _lastLen := -1
    static Init(intervalMs := 150) {
        SetTimer(() => StatFeature.Tick(), intervalMs)
    }
    ; ⚠ 常驻计时器（默认 150ms）：窗口收起 / 最小化时不必刷新字数 —— 隐藏态照跑
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
            ; 实测（120 行文本 + 大量空行，末尾删 120 字）：
            ;   nMax 5082 → 4746、nPos 4363 → 4027 **当场**变对（滑块立即变短）；
            ;   而 EM_GETSCROLLPOS 的 y 仍停在 4368 —— 滞后 341px，闲置 500ms 也不自愈。
            ;   EM_GETLINECOUNT / EM_GETFIRSTVISIBLELINE / WM_VSCROLL(SB_ENDSCROLL)
            ;   实测**全部无效**，只有 EM_SETSCROLLPOS 能把行布局拉回来。
            ; ⚠ 间隔取 150ms（Config.StatInterval）：巡检免费（1000 次 GetScrollInfo = 0ms），
            ;   贵的是真脱节时那一次重排（2.4ms/次）。500ms 时画面「慢半拍再猛跳」，
            ;   50ms 那版逐帧重排、画面抽搐。EN_CHANGE 掩码在本项目的 RichEdit50W 上
            ;   设不上（EM_SETEVENTMASK 读回恒 0x0，WM_COMMAND 一次都不来），只能轮询。
            ; 首次调用（_lastLen = -1）不触发。
            if (this._lastLen >= 0 && len < this._lastLen)
                EditorService.SyncScrollAfterShrink(hwnd)
            this._lastLen := len
            stat.Value := len . " 字"
        }
    }
}
