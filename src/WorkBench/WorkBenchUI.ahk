#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  WorkBenchUI —— 平台级界面（Phase 5：统一帮助）
; ═══════════════════════════════════════════════════════════════════════════
; 平台只拥有「怎么显示帮助」；帮助里有哪些热键由各模块 GetMetadata() 提供。
; Alt+S 的注册在 WorkBench.GetHotkeys()，帮助窗口的 Esc 由本类自注册 / 注销。

class WorkBenchUI {
    ; 帮助窗口标题固定，Esc 的 HotIfWinActive 上下文也用它
    static _HelpTitle() => Config.AppName . " · 快捷键"

    static _helpGui := ""
    static _escRegistered := false

    ; 首选项：平台组永远排第一；其余沿用改造前的 8 组顺序。
    ; 模块新增的组若不在表里，会按首次出现顺序追加到末尾 —— 不用改这里。
    static _GroupOrder := ["平台", "窗口", "外观", "输入增强", "搜索", "文本", "保存"
        , "日期与标签", "编辑", "分段"]

    static Init() {
        ; 帮助窗口按需创建；这里不建 GUI，避免启动时多一个窗口
    }

    ; ─── Alt+S：同标题窗口已存在就激活，否则新建 ───
    static ShowHelp() {
        title := this._HelpTitle()
        if WinExist(title . " ahk_class AutoHotkeyGUI") {
            WinActivate(title . " ahk_class AutoHotkeyGUI")
            return
        }

        help := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", title)
        help.SetFont("s11", "楷体")
        help.BackColor := "FFF8E7"
        help.AddText("x20 y15 w400", this.BuildHotkeyHelpText())

        ; 标题栏关闭也要注销 Esc；窗口本身的销毁交给默认 Close 行为
        help.OnEvent("Close", (*) => this._OnHelpClosed())

        help.Show("w440 h920")
        this._helpGui := help

        ; Esc 不进模块热键表：只在帮助窗口激活时生效，关闭时立刻注销
        registered := true
        HotIfWinActive(title)
        try
            Hotkey("Esc", (*) => this._CloseHelp(), "On")
        catch as e {
            registered := false
            LogError("帮助窗口 Esc 注册失败：" . e.Message)
        }
        HotIf()
        this._escRegistered := registered
    }

    ; ─── 帮助正文：平台 + 各模块 GetMetadata() 聚合 ───
    static BuildHotkeyHelpText() {
        entries := this._CollectEntries()
        text := ""
        for groupName in this._OrderedGroups(entries) {
            text .= "【" . groupName . "】`n"
            for entry in entries {
                if (entry.group != groupName)
                    continue
                text .= entry.hk.line . "`n"
                if entry.hk.HasProp("note")
                    text .= entry.hk.note . "`n"
            }
            text .= "`n"
        }
        return text
            . "—————————————————————————`n"
            . "   " . Config.AppName . " v" . Config.Version . "`n"
            . "   当前笔记目录：`n"
            . "   " . Config.GetVault() . "`n"
            . "   按 ESC 或点关闭按钮关闭"
    }

    ; 收集平台热键 + 各模块元数据里的热键，按模块 order 稳定排序。
    ; 平台 order = 0；SevenNote / KeysInput / Launcher 的 order 由模块自己声明。
    static _CollectEntries() {
        entries := []
        seq := 0
        for hk in WorkBench.GetHotkeys() {
            entries.Push({order: 0, seq: seq, group: this._GroupOf(hk), hk: hk})
            seq += 1
        }

        for id, module in ModuleRegistry.All() {
            meta := this._MetadataOf(module)
            order := meta.HasProp("order") ? meta.order : 100
            if !meta.HasProp("hotkeys")
                continue
            for hk in meta.hotkeys {
                entries.Push({order: order, seq: seq, group: this._GroupOf(hk), hk: hk})
                seq += 1
            }
        }

        ; AHK v2.0 的 Array 没有 Sort 方法；条目最多几十条，插入排序足够且稳定。
        i := 1
        while i <= entries.Length {
            j := i
            while j > 1 && this._Before(entries[j], entries[j - 1]) {
                tmp := entries[j]
                entries[j] := entries[j - 1]
                entries[j - 1] := tmp
                j -= 1
            }
            i += 1
        }

        ; 同一 ctx + key 只保留第一次出现的那条（平台优先），防止新加模块
        ; 把平台热键又声明一遍时帮助里出现两行。
        result := []
        seenKeys := Map()
        for entry in entries {
            ctxName := entry.hk.HasProp("ctx") ? entry.hk.ctx : ""
            keyName := entry.hk.HasProp("key") ? entry.hk.key : ""
            uniq := ctxName . "|" . keyName
            if seenKeys.Has(uniq)
                continue
            seenKeys[uniq] := true
            result.Push(entry)
        }
        return result
    }

    static _Before(a, b) {
        if (a.order != b.order)
            return a.order < b.order
        return a.seq < b.seq
    }

    static _MetadataOf(module) {
        if module.HasMethod("GetMetadata")
            return module.GetMetadata()
        ; 兼容还没实现 GetMetadata 的模块：只提供 GetHotkeys 也能出现在帮助里。
        hotkeys := module.HasMethod("GetHotkeys") ? module.GetHotkeys() : []
        return {name: module.Id, desc: "", order: 100, hotkeys: hotkeys}
    }

    static _GroupOf(hk) => hk.HasProp("group") ? hk.group : "其他"

    static _OrderedGroups(entries) {
        groups := []
        seen := Map()
        for groupName in this._GroupOrder {
            if this._HasGroup(entries, groupName) {
                groups.Push(groupName)
                seen[groupName] := true
            }
        }
        ; 新模块自带的组：没在首选项里就按出现顺序追加
        for entry in entries {
            if !seen.Has(entry.group) {
                groups.Push(entry.group)
                seen[entry.group] := true
            }
        }
        return groups
    }

    static _HasGroup(entries, groupName) {
        for entry in entries {
            if (entry.group = groupName)
                return true
        }
        return false
    }

    ; ─── 关闭 / 注销 ───
    static _CloseHelp() {
        this._UnregisterEsc()
        guiObj := this._helpGui
        this._helpGui := ""
        if IsObject(guiObj)
            try guiObj.Destroy()
    }

    ; 标题栏关闭：只清 Esc 与句柄，窗口由 Gui 默认 Close 行为销毁
    static _OnHelpClosed() {
        this._UnregisterEsc()
        this._helpGui := ""
    }

    static _UnregisterEsc() {
        if !this._escRegistered
            return
        this._escRegistered := false
        try {
            HotIfWinActive(this._HelpTitle())
            Hotkey("Esc", "Off")
        } catch as e {
            LogError("帮助窗口 Esc 注销失败：" . e.Message)
        }
        HotIf()
    }
}