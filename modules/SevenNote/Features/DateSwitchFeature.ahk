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

        State.SetDate(targetStr)
        State.ResetCaret()

        hwnd := State.GetEd()
        rtfPath := NoteStoreService.FindRtf(targetStr)
        if (rtfPath = "") {
            EditorService.SetText(hwnd, EditorService.EmptyNoteHeader(targetStr))
        } else {
            EditorService.LoadRTFFromFile(hwnd, rtfPath)
        }
        EditorService.EmptyUndo(hwnd)
        EventBus.Emit("Date.Switched", {date: targetStr})
        return true
    }
}
