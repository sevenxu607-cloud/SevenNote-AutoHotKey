#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  CapsLockFeature —— CapsLock 层（H/J/K/L = 方向键）
;  Phase 4 从组合根搬入 modules/KeysInput/。
;  静态热键 Alt+Shift+C 由 KeysInputModule.GetHotkeys() 声明；
;  本层自己的 CapsLock / HJKL 是动态热键，开关时经 HotkeyRouter 加 / 卸。
; ═══════════════════════════════════════════════════════════════════════════

class CapsLockFeature {
    static _enabled := false
    static _loading := false

    static Enable() {
        if this._enabled
            return
        ; 动态热键统一走 Router：它负责上下文复位与失败兜底，不把裸 Hotkey()
        ; 散落在 Feature 里。任何一条失败只记日志，不让整层启动失败。
        HotkeyRouter.Add("CapsLock", (*) => 0)
        HotkeyRouter.Add("CapsLock & h", (*) => Send("{Left}"))
        HotkeyRouter.Add("CapsLock & j", (*) => Send("{Down}"))
        HotkeyRouter.Add("CapsLock & k", (*) => Send("{Up}"))
        HotkeyRouter.Add("CapsLock & l", (*) => Send("{Right}"))
        this._enabled := true
        if !this._loading
            this.SaveToConfig()
    }

    static Disable() {
        if !this._enabled
            return
        HotkeyRouter.Remove("CapsLock")
        HotkeyRouter.Remove("CapsLock & h")
        HotkeyRouter.Remove("CapsLock & j")
        HotkeyRouter.Remove("CapsLock & k")
        HotkeyRouter.Remove("CapsLock & l")
        this._enabled := false
        if !this._loading
            this.SaveToConfig()
    }

    static Toggle() {
        if this._enabled {
            this.Disable()
            EventBus.Emit("CapsLock.Toggled"
                , {msg: "✗ 键盘映射已关闭", state: false})
        } else {
            this.Enable()
            EventBus.Emit("CapsLock.Toggled"
                , {msg: "✓ 键盘映射已开启", state: true})
        }
    }

    static SaveToConfig() {
        ConfigService.Write("Input", "CapsLockMap", this._enabled ? 1 : 0)
    }

    static LoadFromConfig() {
        this._loading := true
        v := ConfigService.ReadInt("Input", "CapsLockMap", 0)
        if (v = 1)
            this.Enable()
        else
            this.Disable()
        this._loading := false
    }
}
