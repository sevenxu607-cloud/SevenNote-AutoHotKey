#Requires AutoHotkey v2.0
; ======================================================================
;  GoTodayFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class GoTodayFeature {
    static Go() {
        today := FormatTime(, "yyyy-MM-dd")
        if (State.GetDate() = today) {
            EventBus.Emit("Error.Occurred", {msg: "已经是今天"})
            return
        }
        EventBus.Emit("Date.JumpRequested", {date: today})
    }
}
