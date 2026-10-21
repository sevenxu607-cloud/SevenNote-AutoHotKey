#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  GlassPaint —— 原生窗口的玻璃背衬（Capability）
; ═══════════════════════════════════════════════════════════════════════════
;  纯能力，守 .clinerules/02 的 Capability 契约：
;    · 只收 hwnd / 颜色字符串 / 数字，**不读 Config、不读 State、不发事件**；
;    · 不认识 ThemeService 与 glass.css —— 它只回答「这扇窗能不能玻璃化」。
;
;  ⚠ 先把技术边界说清楚：**AHK 原生窗拿不到 CSS 的 backdrop-filter**。
;    · Win11 的 DWM 背板只作用于窗口**非客户区**（标题栏 / 边框）；
;    · Win10 的 accent policy 要求客户区不被不透明背景覆盖，而 AHK 没法在
;      不破坏控件的前提下做到（Gui.BackColor 恒为不透明刷子）。
;    所以这个能力提供的是**玻璃背衬 + 圆角 + 冰边**，**不承诺客户区模糊**。
;    客户区的“玻璃感”来自深色分层（win / panel / codeBg 三档 + 1px 冰边），
;    那部分由调用方用 UiPaint 上色，不是本能力的职责。
;
;  降级链（逐级 try，任何一级成功即停）：
;    ① Win11 22H2+  DWMWA_SYSTEMBACKDROP_TYPE(38) = DWMSBT_TRANSIENTWINDOW(3)
;    ② Win11 21H2   undocumented DWMWA_MICA_EFFECT(1029) = 1
;    ③ Win10 1803+  SetWindowCompositionAttribute + ACCENT_ENABLE_ACRYLICBLURBEHIND(4)
;    ④ Win10 RTM    SetWindowCompositionAttribute + ACCENT_ENABLE_BLURBEHIND(3)
;    ⑤ 全失败        solid —— 客户区靠主题纯色，一样读得清
;
;  ⚠ acrylic(4) 在 Win10 1803~1903 拖动窗口有已知卡顿 —— Win11 走 ① 到不了 ③；
;    Win10 上不硬上 acrylic 也没关系，退 ④ 的 blur 观感差别很小。
;  ⚠ SetWindowCompositionAttribute 在 Win7 不存在：先 GetProcAddress 探，
;    探不到直接返回，别让 DllCall 抛「找不到函数」被 OnError 记成日志噪音。
;  ⚠ 只对**顶层窗口**有效；对 Edit / Button 这类子控件调了没有效果。
class GlassPaint {
    ; ─── 圆角（Win11）：DWMWA_WINDOW_CORNER_PREFERENCE(33) ────────────────
    ; 2 = DWMWCP_ROUND，0 = DWMWCP_DEFAULT（切回 flat 时撤销用）。
    ; Win10 上属性不存在，DllCall 返回非 0、静默失败 —— 不必写版本判断。
    static Rounded(hwnd, enable := true) {
        if !hwnd || !DllCall("user32\IsWindow", "ptr", hwnd, "int")
            return false
        v := Buffer(4, 0)
        NumPut("int", enable ? 2 : 0, v, 0)
        return !DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd
            , "int", 33, "ptr", v, "int", 4, "int")
    }

    ; ─── 玻璃背衬 ─────────────────────────────────────────────────────────
    ; tintHex 只给 Win10 的 accent 用（GradientColor）；Win11 的背板由系统
    ; 按桌面壁纸取色，不吃这个参数。alpha 是 accent 那层色的不透明度。
    ; ⚠ 缺省 0x50（31%）：原来 0xB4（70%）时染色层几乎盖住模糊，Win10 上看着
    ;   就是一块不透明的深色板 —— 这是「窗口厚重」的原生侧来源。要更透往 0x38 走，
    ;   但低于 ~0x28 后标题栏上的浅色小字开始吃力（Win11 走背板、不受此值影响）。
    static Apply(hwnd, tintHex := "000000", alpha := 0x50) {
        if !hwnd || !DllCall("user32\IsWindow", "ptr", hwnd, "int")
            return {ok: false, mode: "none", reason: "窗口无效"}

        if this._Backdrop(hwnd, 3)
            return {ok: true, mode: "backdrop"}

        if this._Mica(hwnd)
            return {ok: true, mode: "mica"}

        m := this._Accent(hwnd, tintHex, alpha)
        if m
            return {ok: true, mode: m}

        return {ok: false, mode: "solid", reason: "系统不支持玻璃背衬"}
    }

    ; ─── 撤掉背板（切回 flat / 窗口复用时调）───────────────────────────────
    ; 失败无所谓 —— 调用点通常紧接着改 BackColor 或销毁窗口。
    static Clear(hwnd) {
        if !hwnd || !DllCall("user32\IsWindow", "ptr", hwnd, "int")
            return false
        v := Buffer(4, 0)
        NumPut("int", 1, v, 0)          ; DWMSBT_NONE
        try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", 38
            , "ptr", v, "int", 4, "int")
        v2 := Buffer(4, 0)
        NumPut("int", 0, v2, 0)
        try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", 1029
            , "ptr", v2, "int", 4, "int")
        ; 圆角一起还原：否则从玻璃主题切回米黄，窗口还是圆角（flat 原本是直角）
        this.Rounded(hwnd, false)
        return true
    }

    ; ─── 内部：三级尝试 ───────────────────────────────────────────────────

    static _Backdrop(hwnd, type) {
        v := Buffer(4, 0)
        NumPut("int", type, v, 0)
        return !DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd
            , "int", 38, "ptr", v, "int", 4, "int")
    }

    static _Mica(hwnd) {
        v := Buffer(4, 0)
        NumPut("int", 1, v, 0)
        return !DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd
            , "int", 1029, "ptr", v, "int", 4, "int")
    }

    static _Accent(hwnd, tintHex, alpha) {
        ; 函数指针只探一次，存静态字段（探不到就是 0，之后每次直接返回）
        static pSet := 0
        if !pSet {
            hmod := DllCall("GetModuleHandleW", "wstr", "user32", "ptr")
            pSet := hmod ? DllCall("GetProcAddress", "ptr", hmod
                , "astr", "SetWindowCompositionAttribute", "ptr") : 0
        }
        if !pSet
            return ""

        ; accent 的 GradientColor 是 0xAABBGGRR（alpha 在最前），与 COLORREF 同字节序
        abgr := ((alpha & 0xFF) << 24) | this._Bgr(tintHex)
        for state in [4, 3] {
            ap := Buffer(16, 0)
            NumPut("int", state, ap, 0)        ; AccentState
            NumPut("int", 2, ap, 4)            ; AccentFlags：四边都画
            NumPut("uint", abgr, ap, 8)        ; GradientColor
            NumPut("int", 0, ap, 12)           ; AnimationId
            d := Buffer(16, 0)
            NumPut("int", 19, d, 0)            ; WCA_ACCENT_POLICY
            NumPut("ptr", ap.Ptr, d, A_PtrSize)
            NumPut("uint", 16, d, A_PtrSize + 8)
            if DllCall(pSet, "ptr", hwnd, "ptr", d)
                return (state = 4) ? "acrylic" : "blur"
        }
        return ""
    }

    ; "RRGGBB" → COLORREF（0x00BBGGRR）。Win32 的颜色是**反着**存的。
    static _Bgr(hex) {
        if (StrLen(hex) < 6)
            return 0
        r := Integer("0x" . SubStr(hex, 1, 2))
        g := Integer("0x" . SubStr(hex, 3, 2))
        b := Integer("0x" . SubStr(hex, 5, 2))
        return (b << 16) | (g << 8) | r
    }
}
