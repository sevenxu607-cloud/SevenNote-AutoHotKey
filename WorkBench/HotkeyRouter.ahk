#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  HotkeyRouter —— 热键注册的唯一入口
; ═══════════════════════════════════════════════════════════════════════════
; Phase 1 先包住原 RegisterHotkeys()：输入仍是 HotkeyTable() 的数组，
; ctx 仍沿用 global / editor / search，注册结果与改造前逐条一致。
; Phase 2 起 ctx 表达式改由 SevenNoteModule.GetContexts() 提供，
; Router 不再直接引用 SearchFeature。

class HotkeyRouter {
    static RegisterAll(table) {
        ; 注册顺序 = 全局 → 编辑器内 → 搜索栏（与改造前三个 #HotIf 块的先后一致）。
        ; 全局变体（无上下文）的优先级天然最低，所以「先建全局」不会抢上下文变体的命中。
        for ctxName in ["global", "editor", "search"] {
            switch ctxName {
                case "global":
                    HotIf()
                case "editor":
                    HotIf((*) => WinActive("ahk_id " . State.GetGuiHwnd()) && !SearchFeature.IsVisible())
                case "search":
                    HotIf((*) => WinActive("ahk_id " . State.GetGuiHwnd()) && SearchFeature.IsVisible())
            }
            for hk in table {
                if (hk.key = "" || hk.ctx != ctxName)
                    continue
                try
                    Hotkey(hk.key, hk.fn, "On")
                catch as e
                    LogError("热键注册失败：" . hk.key . " —— " . e.Message)
            }
        }
        HotIf()   ; 复位：别把上下文漏给后面动态注册的热键
    }
}