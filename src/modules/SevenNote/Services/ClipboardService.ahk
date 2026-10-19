#Requires AutoHotkey v2.0
; ======================================================================
;  ClipboardService
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class ClipboardService {
    static GetText() {
        try return A_Clipboard
        catch
            return ""
    }
}
