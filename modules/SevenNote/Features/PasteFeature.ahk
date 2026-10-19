#Requires AutoHotkey v2.0
; ======================================================================
;  PasteFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class PasteFeature {
    static PastePlain() {
        hwnd := State.GetEd()
        txt := ClipboardService.GetText()
        if (txt = "")
            return
        EditorService.InsertText(hwnd, txt)
        EventBus.Emit("Paste.Plain")
    }
}
