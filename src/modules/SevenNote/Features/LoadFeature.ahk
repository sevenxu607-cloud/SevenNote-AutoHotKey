#Requires AutoHotkey v2.0
; ======================================================================
;  LoadFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class LoadFeature {
    static Load() {
        this.LoadDate(FormatTime(, "yyyy-MM-dd"))
    }

    ; 切日期 / 跳转都走这里。调用方负责先发 Save.Requested 把当前这篇落盘 ——
    ; Feature 之间不互相调用，这里不替别人做决定。
    static LoadDate(date) {
        State.SetDate(date)
        return this.Push(date)
    }

    ; 把某一天的正文推进 Milkdown。
    ;
    ; ⚠ 必须等编辑器就绪：首次呼出时 WebView2 还在加载 Vite 产物，
    ;   window.__swnote 尚且不存在，setMarkdown 会静默落空（画面停在演示内容）。
    ;   App.vue 里虽然也有 pendingMd 兜底，但那要等 @ready 才补灌 ——
    ;   切日期时编辑器早就 ready 了，走的不是那条路，所以这里得自己等。
    static Push(date) {
        if !WebHostService.WaitFor("window.__swnote && typeof window.__swnote.setMarkdown === 'function'", 8000) {
            LogError("编辑器未就绪，未能载入 " . date)
            return false
        }
        md := this.ReadNote(date)
        r := WebHostService.Eval("window.__swnote.setMarkdown(" . JsText.Escape(md) . ")")
        if !r.ok {
            LogError("载入 " . date . " 失败：" . r.reason)
            return false
        }
        return true
    }

    ; 读一天的笔记正文。没有文件就给带日期的空笔记头。
    static ReadNote(date) {
        path := NoteStoreService.FindMd(date)
        if (path != "" && FileExist(path)) {
            try
                return FileRead(path, "UTF-8")
            catch
                LogError("读取失败：" . path)
        }
        return NoteStoreService.EmptyNoteHeader(date)
    }
}

