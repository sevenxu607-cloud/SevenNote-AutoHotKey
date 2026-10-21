#Requires AutoHotkey v2.0
; ======================================================================
;  FontService
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

; ─── FontService：字体应用 ───
class FontService {
    static Fonts := ["楷体", "华文行楷", "华文新魏", "方正舒体"
        , "仿宋", "微软雅黑", "黑体"]
    static Sizes := [12, 14, 16, 18, 20]

    static _curFont := 1
    static _curSize := 2
    static _loading := false

    static GetName() => this.Fonts[this._curFont]
    static GetSize() => this.Sizes[this._curSize]

    static NextFont() {
        this._curFont++
        if (this._curFont > this.Fonts.Length)
            this._curFont := 1
        this.Apply()
    }

    static BiggerSize() {
        if (this._curSize < this.Sizes.Length) {
            this._curSize++
            this.Apply()
        }
    }

    static SmallerSize() {
        if (this._curSize > 1) {
            this._curSize--
            this.Apply()
        }
    }

    static Apply() {
        hwndEd := State.GetEd()
        if !hwndEd
            return

        t := ThemeService.Themes[ThemeService.GetCurrent()]

        cf := Buffer(92, 0)
        NumPut("uint", 92, cf, 0)
        NumPut("uint", 0x40000000 | 0x20000000 | 0x80000000 | 0x08000000, cf, 4)
        NumPut("int", this.GetSize() * 20, cf, 12)
        NumPut("uint", ThemeService.RGBtoBGR(t.text), cf, 20)
        NumPut("uchar", 134, cf, 24)
        StrPut(this.GetName(), cf.Ptr + 26, "UTF-16")
        SendMessage(0x0444, 4, cf.Ptr, hwndEd)

        for ctrl in [State.GetStat(), State.GetDateCtrl()
            , State.GetMsgCtrl(), State.GetThemeLabel()] {
            try ctrl.SetFont("c" . t.dim . " s" . (this.GetSize() - 4), this.GetName())
        }
        try State.GetThemeLabel().SetFont("c" . t.text . " s10", this.GetName())
        try State.GetTagCtrl().SetFont("c" . t.dim . " s10", this.GetName())

        try State.GetThemeLabel().Value := ThemeService._BuildLabel()

        if !this._loading
            this.SaveToConfig()

        EventBus.Emit("Font.Changed", {name: this.GetName(), size: this.GetSize()})

        SendMessage(0x00B1, -1, -1, hwndEd)
        SendMessage(0x00B7, 0, 0, hwndEd)
    }

    static SaveToConfig() {
        ConfigService.Write("Appearance", "FontIndex", this._curFont)
        ConfigService.Write("Appearance", "FontSizeIndex", this._curSize)
    }

    static LoadFromConfig() {
        this._loading := true
        fi := ConfigService.ReadInt("Appearance", "FontIndex", 1)
        if (fi < 1 || fi > this.Fonts.Length)
            fi := 1
        this._curFont := fi
        si := ConfigService.ReadInt("Appearance", "FontSizeIndex", 2)
        if (si < 1 || si > this.Sizes.Length)
            si := 2
        this._curSize := si
        this.Apply()
        this._loading := false
    }
}
