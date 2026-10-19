#Requires AutoHotkey v2.0
; ======================================================================
;  SaveFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class SaveFeature {
    static Init() {
        EventBus.On("Window.BeforeHide", (*) => SaveFeature.Save())
        ; 别的 Feature 需要「先把当前这篇落盘」时发这个事件 —— Feature 之间不互相调用
        EventBus.On("Save.Requested", (*) => SaveFeature.Save())
    }

    static Save() {
        Critical(1)
        try {
            date := State.GetDate()
            if (date = "")
                date := FormatTime(, "yyyy-MM-dd")
            hwnd := State.GetEd()

            ; 空笔记不落盘（含删除已有文件）
            if EditorService.IsEmptyNote(hwnd, date) {
                rtfPath := NoteStoreService.FindRtf(date)
                mdPath := NoteStoreService.FindMd(date)
                if (rtfPath != "" && FileExist(rtfPath))
                    try FileDelete(rtfPath)
                if (mdPath != "" && FileExist(mdPath))
                    try FileDelete(mdPath)
                Critical(0)
                return
            }

            ; 先查后存（保留带标签的文件名）
            rtfPath := NoteStoreService.FindRtf(date)
            if (rtfPath = "")
                rtfPath := NoteStoreService.DefaultRtfPath(date)

            mdPath := NoteStoreService.FindMd(date)
            if (mdPath = "")
                mdPath := NoteStoreService.DefaultMdPath(date)

            tempRtf := NoteStoreService.TempDir() . "\pandoc-src.rtf"
            NoteStoreService.EnsureDir(NoteStoreService.TempDir())

            ; 主 RTF（936 GBK）
            ok := EditorService.SaveRTFToFile(hwnd, rtfPath, 936)
            if !ok {
                NoteStoreService.WriteFile(mdPath
                    , EditorService.GetText(hwnd), "UTF-8")
                EventBus.Emit("Error.Occurred", {msg: "保存失败：RTF 落盘失败"})
                Critical(0)
                return
            }

            ; Pandoc 转换（v1.9：IsAvailable 已加大小检查）
            if PandocService.IsAvailable() {
                EditorService.SaveRTFToFile(hwnd, tempRtf, 65001)
                PandocService.Convert(tempRtf, mdPath, date)
                if FileExist(tempRtf)
                    try FileDelete(tempRtf)
            } else {
                NoteStoreService.WriteFile(mdPath
                    , EditorService.GetText(hwnd), "UTF-8")
            }
            EventBus.Emit("Save.Completed", {time: FormatTime(, "HH:mm")})
        } catch as e {
            EventBus.Emit("Error.Occurred", {msg: "保存失败：" . e.Message})
        }
        Critical(0)
    }
}
