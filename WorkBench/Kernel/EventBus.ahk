#Requires AutoHotkey v2.0
; WorkBench/Kernel/EventBus.ahk
; Moved from SevenNote.ahk (Phase 1). Implementation unchanged.

class EventBus {
    static handlers := Map()

    static On(event, fn) {
        if !this.handlers.Has(event)
            this.handlers[event] := []
        this.handlers[event].Push(fn)
    }

    static Emit(event, data := "") {
        if !this.handlers.Has(event)
            return
        for fn in this.handlers[event]
            try fn(data)
    }
}
