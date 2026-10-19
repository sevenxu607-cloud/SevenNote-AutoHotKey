#Requires AutoHotkey v2.0
; ======================================================================
;  FontFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class FontFeature {
    static NextFont() => FontService.NextFont()
    static BiggerSize() => FontService.BiggerSize()
    static SmallerSize() => FontService.SmallerSize()
    static LoadFromConfig() => FontService.LoadFromConfig()
}
