#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  HotkeyRouter —— 热键注册的唯一入口
; ═══════════════════════════════════════════════════════════════════════════
; Phase 1 包住原 RegisterHotkeys()；Phase 2 起 contexts 由
; SevenNoteModule.GetContexts() 提供，Router 不再直接引用 SearchFeature。
; Phase 4 起提供 Add / Remove：模块的层内热键（CapsLock / HJKL）动态加卸。

class HotkeyRouter {
    static _contexts := {}
    static _dynamic := Map()

    ; Phase 5：静态热键不再由组合根拼表 —— 平台取 WorkBench.GetHotkeys()，
    ; 各模块取 GetHotkeys()，上下文取各模块 GetContexts()，Router 只负责注册。
    static RegisterAll() {
        contexts := {}
        table := []

        for hk in WorkBench.GetHotkeys()
            table.Push(hk)

        for id, module in ModuleRegistry.All() {
            ; 启动失败的模块：热键不注册（按了只会复现同一个错），失败原因已在 InitAll 里记过
            if ModuleRegistry.IsFailed(id)
                continue
            if module.HasMethod("GetContexts") {
                moduleContexts := module.GetContexts()
                for name in moduleContexts.OwnProps()
                    contexts.%name% := moduleContexts.%name%
            }
            if module.HasMethod("GetHotkeys") {
                for hk in module.GetHotkeys()
                    table.Push(hk)
            }
        }

        this._contexts := contexts

        ; 同一 ctx + key 只注册一次（平台先收集，所以平台热键优先）；
        ; 模块误把平台热键再声明一遍时，不会在注册阶段悄悄盖掉平台回调。
        staticTable := []
        seenKeys := Map()
        for hk in table {
            uniq := hk.ctx . "|" . hk.key
            if seenKeys.Has(uniq) {
                LogError("热键重复声明，已忽略：" . uniq)
                continue
            }
            seenKeys[uniq] := true
            staticTable.Push(hk)
        }

        ; 注册顺序 = 全局 → 编辑器内 → 搜索栏（与改造前三个 #HotIf 块的先后一致）。
        ; 全局变体（无上下文）的优先级天然最低，所以「先建全局」不会抢上下文变体的命中。
        for ctxName in ["global", "editor", "search"] {
            this._ApplyContext(ctxName)
            for hk in staticTable {
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
                if IsObject(this._contexts) && this._contexts.HasProp("editor")
                    HotIf(this._contexts.editor)
                else
                    HotIf()
            case "search":
                if IsObject(this._contexts) && this._contexts.HasProp("search")
                    HotIf(this._contexts.search)
                else
                    HotIf()
            default:
                if IsObject(ctx)
                    HotIf(ctx)
                else
                    HotIf()
        }
    }
}
