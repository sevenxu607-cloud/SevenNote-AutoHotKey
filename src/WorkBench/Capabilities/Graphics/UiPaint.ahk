#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  UiPaint —— Win32 染色原语（Capability）
; ═══════════════════════════════════════════════════════════════════════════
;  纯能力，守 .clinerules/02 的 Capability 契约：
;    · 只收 hwnd / 颜色字符串 / 布尔，**不读 Config、不读 State、不发事件**；
;    · 不认识 ThemeService —— 主题是业务策略，这里只认「给我一个颜色」。
;
;  为什么这些要单独抽出来：它们是「GUI 上色」的平台知识，跨模块复用（笔记的
;  日期对话框 / 提示词的列表 / 启动提示都要），而且都靠 DllCall + Windows 消息，
;  散在 Feature 里既容易写错、也没法统一改。
;
;  ⚠ 深色主题下的 Edit / ComboBox 还需要 WM_CTLCOLOREDIT（要 OnMessage 全局分发
;    + CreateSolidBrush/DeleteObject 成对管理）。那是 P2 单独做的一块，届时加
;    EditColors() / ComboColors() 到这里 —— 不要半成品地只改背景不改文字
;    （白底黑字 → 深底黑字，比不改还糟）。
class UiPaint {
    ; ─── 窗口标题栏 ───────────────────────────────────────────────────────
    ; 深色主题连标题栏一起变深 —— Windows 默认画白标题栏，压在深色窗口上很扎眼。
    ;
    ; ① immersive dark mode：属性号随版本变，Win10 1903+ / Win11 用 20，1809 用 19；
    ;    先试 20，DllCall 返回非 0（不支持）再退到 19。
    ; ② 整块染色（Win11 build 22000+ 才有 35 / 36 / 34 三个属性）：
    ;      35 = CAPTION_COLOR  标题栏底色，取 win
    ;      36 = TEXT_COLOR     标题文字色，取 text —— 深底配亮字、浅底配深字，自动成对
    ;      34 = BORDER_COLOR   外框，与标题栏同色
    ;    颜色是 COLORREF（0x00BBGGRR），正好复用 Bgr()。
    ; ⚠ Win10 上这三个属性不存在，DllCall 直接返回非 0 —— 静默丢掉、系统配色照旧，
    ;   所以不必写版本判断（上面那段 immersive dark mode 已经兜住了深浅）。
    static TitleBar(hwnd, winHex, textHex) {
        if !hwnd
            return false

        dark := this.IsDark(winHex) ? 1 : 0
        v := Buffer(4, 0)
        NumPut("int", dark, v, 0)
        try {
            for attr in [20, 19] {
                if !DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd
                    , "int", attr, "ptr", v, "int", 4, "int")
                    break
            }
        }

        for it in [[35, winHex], [36, textHex], [34, winHex]] {
            cv := Buffer(4, 0)
            NumPut("uint", this.Bgr(it[2]), cv, 0)
            try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd
                , "int", it[1], "ptr", cv, "int", 4, "int")
        }
        return true
    }

    ; ─── 滚动条 / 原生控件主题 ────────────────────────────────────────────
    ; 滚动条画在**非客户区**、由系统主题上色 —— 深色主题下它仍是一条亮白，
    ; 压在暗底上格外扎眼（浅色主题下则相反：深色滚动条同样突兀）。
    ; 把窗口主题交给 DarkMode_Explorer / Explorer 即随之明暗，其余观感分毫不动。
    ; ⚠ 走 DllCall 而不是内置的 SetWindowTheme()：第三参恒为 0（不重置子控件主题），
    ;   这里写全参数最省心。老系统上没有 DarkMode_Explorer，DllCall 静默失败、
    ;   退回系统配色 —— 不必写版本判断。
    static WindowTheme(hwnd, dark) {
        if !hwnd
            return false
        theme := dark ? "DarkMode_Explorer" : "Explorer"
        try DllCall("uxtheme\SetWindowTheme", "ptr", hwnd, "wstr", theme, "ptr", 0)
        return true
    }

    ; ─── ListView 底色 ────────────────────────────────────────────────────
    ; ListView **不吃** Gui.BackColor，必须整块走 Windows 消息单独上色。
    ;   0x1001 LVM_SETBKCOLOR        控件底
    ;   0x1024 LVM_SETTEXTCOLOR      正文
    ;   0x1025 LVM_SETTEXTBKCOLOR    文字底（必须与控件底一致，否则行间夹白条）
    ;   0x1036 LVM_SETEXTENDEDLISTVIEWSTYLE + LVS_EX_DOUBLEBUFFER：
    ;          每敲一个字就整表重填，不双缓冲会看到闪白。
    static ListView(hwnd, bgHex, fgHex) {
        if !hwnd
            return false
        bg := this.Bgr(bgHex)
        fg := this.Bgr(fgHex)
        try {
            SendMessage(0x1001, 0, bg, "ahk_id " . hwnd)
            SendMessage(0x1024, 0, fg, "ahk_id " . hwnd)
            SendMessage(0x1025, 0, bg, "ahk_id " . hwnd)
            SendMessage(0x1036, 0x00010000, 0x00010000, "ahk_id " . hwnd)
        }
        return true
    }

    ; ─── 颜色工具 ─────────────────────────────────────────────────────────

    ; "RRGGBB" → COLORREF（0x00BBGGRR）：Win32 的颜色是**反着**存的
    static Bgr(hex) {
        r := Integer("0x" . SubStr(hex, 1, 2))
        g := Integer("0x" . SubStr(hex, 3, 2))
        b := Integer("0x" . SubStr(hex, 5, 2))
        return (b << 16) | (g << 8) | r
    }

    ; 加权亮度 < 128 = 深色。与 ThemeService.IsDark / 前端 ahk.ts 的 luminance() 同式。
    static IsDark(hex) {
        r := Integer("0x" . SubStr(hex, 1, 2))
        g := Integer("0x" . SubStr(hex, 3, 2))
        b := Integer("0x" . SubStr(hex, 5, 2))
        return (0.299 * r + 0.587 * g + 0.114 * b) < 128
    }
}
