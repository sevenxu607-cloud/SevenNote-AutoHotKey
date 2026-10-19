#Requires AutoHotkey v2.0
; ======================================================================
;  UndoFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class UndoFeature {
    static Undo() => EditorService.Undo(State.GetEd())
    static Redo() => EditorService.Redo(State.GetEd())
}
