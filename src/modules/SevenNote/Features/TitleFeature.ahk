#Requires AutoHotkey v2.0
; ======================================================================
;  TitleFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

class TitleFeature {
    static ShowDialog() {
        date := State.GetDate()
        if (date = "")
            return

        mdPath := NoteStoreService.FindMd(date)
        currentTag := (mdPath != "")
            ? NoteStoreService.TagFromFileName(mdPath) : ""

        dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "日期标签")
        dlg.SetFont("s11", "Microsoft YaHei")
        dlg.BackColor := "FFF8E7"
        dlg.AddText("x14 y12 w340", "为 " . date . " 设置标签：")
        edit := dlg.AddEdit("x14 y38 w340 h26", currentTag)
        edit.SetFont("s11", "Microsoft YaHei")
        btnOk := dlg.AddButton("Default x14 y76 w100", "确定")
        btnClear := dlg.AddButton("x122 y76 w100", "清除")
        btnCancel := dlg.AddButton("x230 y76 w100", "取消")
        dlg.AddText("x14 y112 w340 c808080"
            , "示例：2026-09-19-机器学习`n标签会写进文件名，黑曜石里一眼可见")

        OnSubmit(*) {
            newTag := NoteStoreService.SanitizeTag(edit.Value)
            dlg.Destroy()
            TitleFeature._Apply(date, currentTag, newTag)
        }

        OnClear(*) {
            dlg.Destroy()
            if (currentTag != "")
                TitleFeature._Apply(date, currentTag, "")
        }

        btnOk.OnEvent("Click", OnSubmit)
        btnClear.OnEvent("Click", OnClear)
        btnCancel.OnEvent("Click", (*) => dlg.Destroy())
        dlg.OnEvent("Escape", (*) => dlg.Destroy())
        dlg.OnEvent("Close", (*) => dlg.Destroy())

        edit.Focus()
        dlg.Show("w380 h150")
    }

    static _Apply(date, oldTag, newTag) {
        if (oldTag = newTag)
            return
        EventBus.Emit("Save.Requested")
        if (newTag != "" && NoteStoreService.FindMd(date) = "") {
            EventBus.Emit("Error.Occurred"
                , {msg: "空笔记无法设标签，请先写内容"})
            return
        }
        if NoteStoreService.RenameWithTag(date, oldTag, newTag) {
            EventBus.Emit("Title.Changed"
                , {date: date, tag: newTag})
        } else {
            MsgBox("重命名失败，请检查文件是否被其他程序占用"
                , "错误", 48)
        }
    }
}
