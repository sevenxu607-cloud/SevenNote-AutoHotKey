#Requires AutoHotkey v2.0
; ======================================================================
;  TimestampFeature.ahk
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

; ⚠ 时间戳**一律手动**（v2.4 起）：只在用户按下 Ctrl+T 时插入，程序任何时候都不自作主张。
;   原先的两条自动路径已删除 ——
;     · 启动时 CheckAndAppend()：无戳就塞一个；
;     · 切日期时同一函数：距上一戳 ≥ Config.TimestampInterval（60 分钟）再补一个。
;   它们会在用户只想随手记两笔时也往笔记里加时间戳，还得靠「保存前剥掉空戳」来兜底。
;   现在连带 StripIfEmpty 一起去掉：用户手动加的戳就是他想要的，程序不擅自删。
;   想恢复自动：在组合根按需调 TimestampFeature.Append()，或把 CheckAndAppend 加回来。
class TimestampFeature {
    static Append() {
        hwnd := State.GetEd()
        EditorService.AppendTimestamp(hwnd)
        EventBus.Emit("Timestamp.Appended")
    }

    static Separator() {
        hwnd := State.GetEd()
        EditorService.InsertSeparator(hwnd)
        EventBus.Emit("Separator.Inserted")
    }

    static Heading() {
        hwnd := State.GetEd()
        EditorService.InsertHeading(hwnd)
        EventBus.Emit("Heading.Inserted")
    }
}
