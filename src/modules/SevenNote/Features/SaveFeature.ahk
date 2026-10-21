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

    ; 落盘：从编辑器取 Markdown → 写 .md。
    ;
    ; v2.9 起 **Markdown 是母版**，RTF 退出保存路径（原文只在 `ExportFeature` 类
    ; 的导出链上还用它，本仓库已无）。所以这里不再碰 RichEdit、不再调 Pandoc。
    ;
    ; ⚠ 不进 Critical(1)：Take() 里是 ExecuteScriptAsync().await()，页面正忙时
    ;   要等几百 ms；而 Critical 期间热键线程停摆，用户会感觉「按什么都有延迟」。
    static Save() {
        try {
            date := State.GetDate()
            if (date = "")
                date := FormatTime(, "yyyy-MM-dd")

            md := this.Take()
            if (md = "") {
                ; 编辑器还没就绪（首次呼出、页面重载中）—— 宁可这次不写，
                ; 也不能拿空串覆盖掉用户已有的一天。
                return
            }

            ; 空笔记不落盘，且顺手清掉当天已有的 .md（与旧版语义一致）
            if NoteStoreService.IsEmptyNote(md, date) {
                mdPath := NoteStoreService.FindMd(date)
                if (mdPath != "" && FileExist(mdPath))
                    try FileDelete(mdPath)
                return
            }

            ; 先查后存（保留带标签的文件名）
            mdPath := NoteStoreService.FindMd(date)
            if (mdPath = "")
                mdPath := NoteStoreService.DefaultMdPath(date)

            ; ⚠ 内容没变就一个字节都不写。
            ;   Milkdown 序列化会把 CRLF 规范成 LF、把 Obsidian 的冗余转义 `\#`
            ;   还原成 `#`（实测最长一篇 11813 → 11151 字符，差额 = 567 个 CR + 95 处转义）。
            ;   语义等价，但「打开看一眼历史笔记」不该改写它的文件。
            if FileExist(mdPath) {
                try {
                    if (FileRead(mdPath, "UTF-8") = md) {
                        EventBus.Emit("Save.Completed"
                            , {time: FormatTime(, "HH:mm"), unchanged: true})
                        return
                    }
                }
            }

            if NoteStoreService.WriteFile(mdPath, md, "UTF-8")
                EventBus.Emit("Save.Completed", {time: FormatTime(, "HH:mm")})
            else
                EventBus.Emit("Error.Occurred", {msg: "保存失败：无法写入 " . mdPath})
        } catch as e {
            EventBus.Emit("Error.Occurred", {msg: "保存失败：" . e.Message})
        }
    }

    ; 取编辑器里的存储态 Markdown；取不到返回空串（调用方据此跳过这次保存）。
    static Take() {
        if !WebHostService.IsReady()
            return ""
        r := WebHostService.Eval("(()=>{try{const m=window.__swnote.getMarkdown();"
            . "return (typeof m==='string')?m:''}catch(e){return ''}})()")
        if !r.ok
            return ""
        return JsText.Unquote(r.value)
    }
}

