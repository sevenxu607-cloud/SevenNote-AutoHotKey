#Requires AutoHotkey v2.0
; ======================================================================
;  DateSwitchFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class DateSwitchFeature {
    static Switch(offset) {
        EventBus.Emit("Save.Requested")   ; 切走之前先把当前这篇落盘

        curDate := State.GetDate()
        if (curDate = "")
            return false

        ymd := StrReplace(curDate, "-", "")
        target := DateAdd(ymd, offset, "Days")
        targetStr := FormatTime(target, "yyyy-MM-dd")

        ; 换文档由 LoadFeature 统一负责（v2.9）：编辑器不再由 AHK 直接灌字，
        ; 这边只管算日期、发事件。
        State.ResetCaret()
        if !LoadFeature.LoadDate(targetStr)
            return false
        EventBus.Emit("Date.Switched", {date: targetStr})
        return true
    }
}
