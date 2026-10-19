#Requires AutoHotkey v2.0
; ======================================================================
;  ThemeFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class ThemeFeature {
    static Next() => ThemeService.Next()
    static LoadFromConfig() => ThemeService.LoadFromConfig()
}
