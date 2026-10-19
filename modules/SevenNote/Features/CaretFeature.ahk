#Requires AutoHotkey v2.0
; ======================================================================
;  CaretFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class CaretFeature {
    static Init() {
        EventBus.On("Window.BeforeHide", (*) => CaretFeature.Save())
        EventBus.On("Window.Shown", (*) => CaretFeature.Restore())
    }
    static Save() {
        sel := EditorService.GetSel(State.GetEd())
        State.SetCaret(sel.min, sel.max)
    }
    static Restore() {
        hwnd := State.GetEd()
        totalLen := SendMessage(0x000E, 0, 0, hwnd)
        if !State.HasCaret() {
            EditorService.MoveCaretToEnd(hwnd)
            return
        }
        caret := State.GetCaret()
        selMin := Min(caret.min, totalLen)
        selMax := Min(caret.max, totalLen)
        if (selMin < 0)
            selMin := 0
        if (selMax < 0)
            selMax := 0
        EditorService.SetSel(hwnd, selMin, selMax)
    }
}
