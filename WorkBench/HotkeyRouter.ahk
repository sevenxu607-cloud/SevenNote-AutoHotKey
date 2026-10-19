#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  HotkeyRouter —— 热键注册的唯一入口
; ═══════════════════════════════════════════════════════════════════════════
; Phase 1 包住原 RegisterHotkeys()；Phase 2 起 contexts 由
; SevenNoteModule.GetContexts() 提供，Router 不再直接引用 SearchFeature。
; Phase 4 起提供 Add / Remove：模块的层内热键（CapsLock / HJKL）动态加卸。

class HotkeyRouter {
    static _contexts := ""
    static _dynamic := Map()

    static RegisterAll(table, contexts) {
        this._contexts := contexts
        ; 注册顺序 = 全局 → 编辑器内 → 搜索栏（与改造前三个 #HotIf 块的先后一致）。
        ; 全局变体（无上下文）的优先级天然最低，所以「先建全局」不会抢上下文变体的命中。
        for ctxName in ["global", "editor", "search"] {
            this._ApplyContext(ctxName)
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

    ; 动态注册（Phase 4：CapsLock 层开关时调用）。
    ; 同 key 重复 Add 先卸再装，避免残留旧回调；失败只记日志，返回 false。
    static Add(key, fn, ctx := "global") {
        if this._dynamic.Has(key)
            this.Remove(key)
        try {
            this._ApplyContext(ctx)
            Hotkey(key, fn, "On")
            this._dynamic[key] := {fn: fn, ctx: ctx}
            return true
        } catch as e {
            LogError("动态热键注册失败：" . key . " —— " . e.Message)
            return false
        } finally {
            HotIf()
        }
    }

    static Remove(key) {
        if !this._dynamic.Has(key)
            return
        try {
            Hotkey(key, "Off")
        } catch as e {
            LogError("动态热键注销失败：" . key . " —— " . e.Message)
        }
        this._dynamic.Delete(key)
        HotIf()
    }

    ; 卸掉全部动态热键；供退出 / 重载路径使用，静态表不动。
    static Reset() {
        keys := []
        for key, entry in this._dynamic
            keys.Push(key)
        for key in keys
            this.Remove(key)
    }

    static _ApplyContext(ctx) {
        switch ctx {
            case "global":
                HotIf()
            case "editor":
                HotIf(this._contexts.editor)
            case "search":
                HotIf(this._contexts.search)
            default:
                if IsObject(ctx)
                    HotIf(ctx)
                else
                    HotIf()
        }
    }
}
