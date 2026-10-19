#Requires AutoHotkey v2.0
; ======================================================================
;  ThemeService
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

; ─── ThemeService：主题应用 ───
class ThemeService {
    static Themes := [
        ; ⚠ 主题表在 v2.4 精简过一次（8 套 → 5 套）：删掉天空蓝 / 薄荷绿 / 高雅灰，
        ;   留下「纯米黄 / 护眼绿」两套浅色底 + 「纸白」中性白 + 「星空 / 金克斯」两套图主题。
        ;   被删的各有替代：薄荷绿 → 护眼绿，天空蓝 / 高雅灰 → 纸白。
        ; ⚠ 删主题会让**其后所有元素的下标往前挪**，而配置里存的正是下标 —— 老用户会被
        ;   换成另一套主题，甚至越界兜底。故 _MigrateIndex() 里留了一次性下标迁移。
        ;   加主题仍应**追加到数组末尾**（同样是为了不动已有下标）。
        {name: "纯米黄", win: "FFF8E7", edBg: "FFF8E7", text: "3D2B1F", dim: "A89880"},
        {name: "护眼绿", win: "CCE8CF", edBg: "E0F0E3", text: "2D4A30", dim: "6B8E6E"},
        {name: "纸白",   win: "FAFAFA", edBg: "FFFFFF", text: "333333", dim: "999999"},
        ; ⚠ 带背景图的主题：bg 是图片路径，bgAlpha 是把图压暗的遮罩不透明度（0-100）。
        ;   这套配色取自那张星空图（实测全图均色 #181C25、平均亮度仅 28）：win / edBg 都
        ;   贴着图的暗部走（亮度 ≈15），编辑区内外浑然一体，没有色块割裂感。
        ;   bgAlpha = 0 表示不压暗：Windows Terminal 用的就是同一张图、backgroundImageOpacity
        ;     设成 1（完全不压暗），这里对齐它 —— 星云保持原样、最亮也最清楚。
        ;     想压暗就改这里的 bgAlpha（值越大越暗）。
        ;   ⚠ 不压暗之后前景色必须够亮：文字取近白、次级文字也抬到浅灰蓝，
        ;     否则压在星云亮部（亮度约 60-130）上会发灰读不清。
        ;   图片缺失时自动降级成纯深色底（edBg），浅色文字照样读得清。
        ;   不想改源码就换图：改这条目里的 bg（换图后要重启程序才生效）。
        {name: "星空", win: "0D0F14", edBg: "0D0F14", text: "F5F9FF", dim: "9FAABC"
            , bg: "D:\00-SevenFiles\Pictures\04-素材库\壁纸\星空\2026-10-14_星空-灰色2.png"
            , bgAlpha: 0},

        ; ⚠ 竖版人物图和横版漫射图是两种铺法 —— 但**别拿 contain 兜竖图**：
        ;   · 星空是漫射横图，cover 裁掉左右各 45% 也看不出；
        ;   · 竖版人物图（0.676）塞进编辑区（0.917）若走 contain，两侧会留出
        ;     一大条 edBg 底色、人物缩在中间。正解是**先按编辑区比例裁好再铺**：
        ;     烘出来的图本身就是 0.917，cover 即铺满、一个细节不浪费。
        ; ⚠ 这套是「暗图 + 亮字」，和「星空」同族 —— 别被"人物图得提亮"带偏：
        ;   源图是 5897x8719 的高清原图，全图均亮度只有 **75**，本来就满足「亮字」的
        ;   WCAG 4.5:1 那条线（背景 ≤ 118），**根本不需要提亮**。上一版为了迁就深色字
        ;   把它抬到均亮 170，整张图当场像蒙了层灰 —— 提亮不等于"更清晰"，是把原图洗白。
        ;   现在这条路反过来：暗部一个像素都不动，只把压在文字下面的**最亮部分**滚降。
        ; ⚠ 烘焙由 tools\rebake-backdrop.ps1 一次跑完，输入只有那张高清原图：
        ;   ① 裁：**取满原图宽**（-CropX 0.00 -CropW 1.00 -CropY 0.00）= 主体按原图大小，
        ;      不做放大特写。这是 v2.3 重烘时定下的构图；
        ;   ② 缩：2400x2617（0.917，与编辑区严格同比例，SS_BITMAP 不再重采样）；
        ;   ③ 色调：**在 V（明度）上等比缩放**，绝不混色 ——
        ;        V ≤ 138 原样不动，V > 138 线性滚降到 200。只动亮部（脸 / 手 / 白墙），
        ;      暗部一像素不改，饱和度一丝不掉。
        ;   ④ unsharp 半径 4 强度 0.9（在**成品尺寸**上做，不是源图尺寸）。
        ;   还想再暗/再亮：优先改 -Knee / -HiMax 重烘（运行时遮罩会减饱和，别当常法）。
        ; ⚠⚠ 这套图烘过**三代**，别照抄旧账：
        ;     一代  -CropW 0.72 / -Knee 116 -HiMax 152  ← 大特写（脸顶到框）、亮部压得太狠，已废
        ;     二代  -CropW 0.85                          ← 过渡档，已废
        ;     三代  -CropW 1.00 / -Knee 138 -HiMax 200  ← **当前成品就是这一版**
        ;   旧成品备份还在图片目录里，可作旁证：金克斯主题_bak_crop85.png、
        ;   金克斯主题_bak_knee116.png（文件名里的 knee116 正是一代参数）。
        ;   三代实测账（同一裁剪区对比）：亮部 p95 ≈141 → **177**（原图 214）、
        ;   最彩 5% 像素饱和度 42.2% → **44.1%**（一丝不掉）、全图均亮度 83.9 → **79.6**
        ;   —— 代价只是暗档略降，观感仍是原图本身。
        ; ⚠ 素材是 5897x8719 的高清原图「金克斯竖版.png」，别退回去用 2000x2300 的
        ;   「金克斯竖版02.png」—— 那张缩到编辑区只剩 3 倍余量，锐化后更容易发糊。
        ; ⚠ 配色全在图里（图是冷调，B > R）：win / edBg = 0B1624（比图的暗部再蓝一档，
        ;   深色标题栏随之自动打开），text = EAF2FF、dim = 93AACB —— 亮字压深底，
        ;   对比度 16:1 / 7.6:1，都远超 4.5:1。
        {name: "金克斯", win: "0B1624", edBg: "0B1624", text: "EAF2FF", dim: "93AACB"
            , bg: "D:\00-SevenFiles\Pictures\04-素材库\壁纸\动漫\金克斯主题.png"
            , bgAlpha: 0
            , bgFit: "cover"}
    ]

    static _current := 1
    static _loading := false

    static GetCurrent() => this._current
    static GetName() => this.Themes[this._current].name

    static Next() {
        this._current++
        if (this._current > this.Themes.Length)
            this._current := 1
        this.Apply(this._current)
    }

    static Apply(idx) {
        this._current := idx
        t := this.Themes[idx]
        g := State.GetGui()
        hwndEd := State.GetEd()
        if !g || !hwndEd
            return

        g.BackColor := t.win
        SendMessage(0x0443, 0, this._RGBtoBGR(t.edBg), hwndEd)

        cf := Buffer(92, 0)
        NumPut("uint", 92, cf, 0)
        NumPut("uint", 0x40000000 | 0x20000000 | 0x80000000 | 0x08000000, cf, 4)
        NumPut("int", FontService.GetSize() * 20, cf, 12)
        NumPut("uint", this._RGBtoBGR(t.text), cf, 20)
        NumPut("uchar", 134, cf, 24)
        StrPut(FontService.GetName(), cf.Ptr + 26, "UTF-16")
        SendMessage(0x0444, 4, cf.Ptr, hwndEd)

        ; ⚠ 字号必须与 FontService.Apply 取同一档（size-4）：两处覆盖的是同一批控件，
        ;   一处写死 s10、一处写 size-4，Alt+T 与 Alt+± 就会互相顶掉对方的字号。
        for ctrl in [State.GetStat(), State.GetDateCtrl()
            , State.GetMsgCtrl(), State.GetThemeLabel()] {
            try ctrl.SetFont("c" . t.dim . " s" . (FontService.GetSize() - 4), FontService.GetName())
        }
        try State.GetThemeLabel().SetFont("c" . t.text . " s10", FontService.GetName())
        try State.GetTagCtrl().SetFont("c" . t.dim . " s10", FontService.GetName())

        try State.GetThemeLabel().Value := this._BuildLabel()

        ; 深色主题连标题栏一起变深 —— Windows 默认画白标题栏，压在深色窗口上很扎眼
        this._SetDarkTitleBar(t)

        ; 编辑区滚动条一并跟主题：它画在**非客户区**、由系统主题上色，深色主题下会留下
        ; 一条亮白竖条，压在暗底上格外突兀
        this._SetScrollBarTheme(hwndEd, this._IsDarkHex(t.win))

        if !this._loading
            this.SaveToConfig()

        EventBus.Emit("Theme.Changed", {name: t.name, idx: this._current})
    }

    ; 标题栏深浅跟着主题底色走：按亮度判断，深色主题开 immersive dark mode、浅色主题关掉。
    ; ⚠ 属性号随 Windows 版本变：Win10 1903+ / Win11 用 20，Win10 1809 用 19；
    ;   先试 20，DllCall 返回非 0（不支持该属性）再退到 19。
    static _SetDarkTitleBar(t) {
        hwnd := State.GetGuiHwnd()
        if !hwnd
            return
        dark := this._IsDarkHex(t.win) ? 1 : 0

        v := Buffer(4, 0)
        NumPut("int", dark, v, 0)
        try {
            for attr in [20, 19] {
                if !DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd
                    , "int", attr, "ptr", v, "int", 4, "int")
                    break
            }
        }

        ; 标题栏整块染成主题色（Win11 build 22000+ 才有 35 / 36 / 34 这三个属性）：
        ;   35 = CAPTION_COLOR  标题栏底色，取 win
        ;   36 = TEXT_COLOR     标题文字色，取 text —— 深底配亮字、浅底配深字，自动成对
        ;   34 = BORDER_COLOR   外框，与标题栏同色
        ;   颜色是 COLORREF（0x00BBGGRR），正好复用 _RGBtoBGR()。
        ; ⚠ Win10 上这三个属性不存在，DllCall 直接返回非 0 —— 静默丢掉、系统配色照旧，
        ;   所以不必写版本判断（上面那段 immersive dark mode 已经兜住了深浅）。
        for it in [[35, t.win], [36, t.text], [34, t.win]] {
            cv := Buffer(4, 0)
            NumPut("uint", this._RGBtoBGR(it[2]), cv, 0)
            try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd
                , "int", it[1], "ptr", cv, "int", 4, "int")
        }
    }

    ; 「深色」判据：底色按加权亮度 < 128 即视为深色。标题栏与滚动条共用这一条。
    static _IsDarkHex(hex) {
        r  := Integer("0x" . SubStr(hex, 1, 2))
        gg := Integer("0x" . SubStr(hex, 3, 2))
        b  := Integer("0x" . SubStr(hex, 5, 2))
        return (0.299 * r + 0.587 * gg + 0.114 * b) < 128
    }

    ; 编辑区的滚动条是**非客户区**、由系统主题上色 —— 深色主题下它仍是亮白一条，压在
    ; 暗底上格外扎眼（浅色主题下则相反：深色滚动条同样突兀）。把窗口主题交给
    ; DarkMode_Explorer / Explorer，滚动条即随之变暗或变亮，其余观感分毫不动。
    ; ⚠ 走 DllCall 而不是内置的 SetWindowTheme()：第三参恒为 0（不重置子控件主题），
    ;   这里写全参数最省心。
    ; ⚠ 老系统上没有 DarkMode_Explorer 这个主题，DllCall 静默失败、退回系统配色 ——
    ;   不必写版本判断。
    static _SetScrollBarTheme(hwndEd, dark) {
        if !hwndEd
            return
        theme := dark ? "DarkMode_Explorer" : "Explorer"
        try DllCall("uxtheme\SetWindowTheme", "ptr", hwndEd, "wstr", theme, "ptr", 0)
    }

    static SaveToConfig() {
        ConfigService.Write("Appearance", "ThemeIndex", this._current)
    }

    static LoadFromConfig() {
        this._loading := true
        idx := ConfigService.ReadInt("Appearance", "ThemeIndex", 1)
        idx := this._MigrateIndex(idx)
        if (idx < 1 || idx > this.Themes.Length)
            idx := 1
        this.Apply(idx)
        this._loading := false
    }

    ; ─── 旧下标迁移（v2.4 精简主题表：8 套 → 5 套）───
    ; 主题表删掉 3 套之后，配置里存的老下标语义全变了 —— 本机实测老配置是 ThemeIndex=8
    ; （金克斯），而新表只有 5 套：不迁移就**越界**，被下面那句兜底成「纯米黄」，
    ; 等于把用户的主题悄悄换掉。按下表把被删主题映到最相近的保留主题：
    ;     旧 1 米黄 → 1    旧 2 护眼绿 → 2    旧 3 天空蓝 → 3 纸白
    ;     旧 4 薄荷绿 → 2  旧 5 高雅灰 → 3    旧 6 纸白 → 3
    ;     旧 7 星空 → 4    旧 8 金克斯 → 5
    ; ⚠ 迁移**只能做一次**：同一个数字在新旧语义下含义不同（新表 4 = 星空、旧表 4 =
    ;   薄荷绿），再映射一遍会把用户刚选的主题又改掉。故用 [Appearance] ThemeSchema=2
    ;   打标记；并且**必须把新下标写回配置** —— Apply 在 _loading 期间不落盘，不写回的
    ;   话下次启动又拿旧值去走越界兜底，迁移成了摆设。
    static _MigrateIndex(idx) {
        if (ConfigService.ReadInt("Appearance", "ThemeSchema", 1) >= 2)
            return idx
        idxMap := [1, 2, 3, 2, 3, 3, 4, 5]
        newIdx := (idx >= 1 && idx <= idxMap.Length) ? idxMap[idx] : idx
        ConfigService.Write("Appearance", "ThemeIndex", newIdx)
        ConfigService.Write("Appearance", "ThemeSchema", 2)
        return newIdx
    }

    static _BuildLabel() {
        return ThemeService.GetName()
            . " · " . FontService.GetName()
            . " " . FontService.GetSize() . "pt"
    }

    static _RGBtoBGR(hexRGB) {
        r := SubStr(hexRGB, 1, 2)
        g := SubStr(hexRGB, 3, 2)
        b := SubStr(hexRGB, 5, 2)
        return Integer("0x" . b . g . r)
    }
}
