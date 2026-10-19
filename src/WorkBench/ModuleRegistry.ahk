#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  ModuleRegistry —— 模块登记与查找（Phase 1 占位）
; ═══════════════════════════════════════════════════════════════════════════
; 模块是类对象，约定带 static Id / Name / Init() / GetHotkeys() / GetContexts()。
; Phase 3b 起由 WorkBench.Init() 在启动时登记；后续模块照同一方式接入。

class ModuleRegistry {
    static modules := Map()

    static Register(module) {
        this.modules[module.Id] := module
    }

    static Unregister(id) {
        if this.modules.Has(id)
            this.modules.Delete(id)
    }

    static Get(id) => this.modules.Has(id) ? this.modules[id] : ""

    static All() => this.modules
}