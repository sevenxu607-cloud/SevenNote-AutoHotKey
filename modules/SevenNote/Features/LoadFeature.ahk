#Requires AutoHotkey v2.0
; ======================================================================
;  LoadFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class LoadFeature {
    static Load() {
        date := FormatTime(, "yyyy-MM-dd")
        State.SetDate(date)
        hwnd := State.GetEd()
        rtfPath := NoteStoreService.FindRtf(date)
        if (rtfPath = "") {
            EditorService.SetText(hwnd, EditorService.EmptyNoteHeader(date))
            return
        }
        EditorService.LoadRTFFromFile(hwnd, rtfPath)
    }
}
