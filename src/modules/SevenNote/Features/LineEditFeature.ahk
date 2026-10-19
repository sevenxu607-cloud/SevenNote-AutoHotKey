#Requires AutoHotkey v2.0
; ======================================================================
;  LineEditFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class LineEditFeature {
    static DeleteLine() => EditorService.DeleteCurrentLine(State.GetEd())
    static DuplicateLine() => EditorService.DuplicateCurrentLine(State.GetEd())
    static MoveUp() => EditorService.MoveLineUp(State.GetEd())
    static MoveDown() => EditorService.MoveLineDown(State.GetEd())
    static Indent() {
        EditorService.DoIndent(State.GetEd())
        EventBus.Emit("Line.Indented")
    }
    static Outdent() {
        EditorService.DoOutdent(State.GetEd())
        EventBus.Emit("Line.Outdented")
    }
}
