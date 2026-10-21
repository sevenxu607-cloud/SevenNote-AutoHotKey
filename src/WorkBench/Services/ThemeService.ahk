#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  ThemeService —— 工作台主题（平台服务）
; ═══════════════════════════════════════════════════════════════════════════
;  v2.9 从 modules\SevenNote\Services\ 上收到平台。主题不是笔记的私事：
;  提示词库 / 日期对话框 / 启动提示都该跟着它走 —— 控制面板（Alt+S）是
;  **刻意的例外**，它有自己一套配色，不订阅 Theme.Changed。
;
;  职责只有三件：
;    ① 持有主题表与当前下标（[Appearance] ThemeIndex 持久化）
;    ② 把 4 个基色派生成窗口要用的**语义色板**（Palette）
;    ③ 换主题时广播 Theme.Changed —— 谁窗口开着谁自己重绘
;
;  ⚠ 它**不碰任何窗口**。从前 Apply() 开局就是 `if !g || !hwndEd return`，
;    而 WebView2 时代 State.GetEd() 恒为 0 → 那句守卫让整个 Apply 直接返回，
;    连 SaveToConfig 都不执行（v2.9 迁移时漏掉的回归：主题永远停在主题 1）。
;    现在上色由窗口自己读 Palette()，平台只回答「当前是哪一套」。
;
;  ⚠ 语义名与前端 web/src/style.css 的 --sw-* 一一对应，派生公式两边一致
;    （见 _Shift / _Mix）：网页里的米黄与 AHK 窗口的米黄必须是同一个米黄。
;
;  加新主题：Themes **末尾追加**一行（ThemeIndex 存的是数组下标，插中间会顶掉
;  老用户当前的主题），并且前一条结尾补 `},` —— 漏逗号报 Unexpected "{"，
;  方案 A 的预检查不出来。
;  带图的主题 bg / bgAlpha 必须成对（bgFit 可选，cover / contain）；
;  完整烘焙配方见 docs/THEME-IMAGES.md。
class ThemeService {
    ; ⚠ 主题表**现在只留「纯米黄」一套**：护眼绿 / 纸白 / 星空 / 金克斯
    ;   全部暂时下线 —— 背景图主题的铺法（bg / bgAlpha / bgFit + 前端消费）还在打磨，
    ;   留着半成品比不留更糟（切换能切、切过去是一块纯底色）。历史版本见 git。
    ;
    ;   接回来时**只追加到末尾**，别插到前面：ThemeIndex 存的是下标。
    ;   条目的字段照旧：win / edBg / text / dim 四个基色，其余由 Palette() 派生；
    ;   带图的再补 bg + bgAlpha（成对，bgFit 可选）—— 配方见 docs/THEME-IMAGES.md。
    static Themes := [
        {name: "纯米黄", win: "FFF8E7", edBg: "FFF8E7", text: "3D2B1F", dim: "A89880"}
    ]

    static _current := 1
    static _loading := false

    ; ─── 查询 ─────────────────────────────────────────────────────────────

    static GetCurrent() => this._current
    static GetName() => this.Themes[this._current].name

    ; ─── 语义色板 ─────────────────────────────────────────────────────────
    ; 与前端 --sw-* 同名同义：
    ;   win    窗口底        ← --sw-bg-alt      （标题栏 / 面板底色）
    ;   edBg   内容底        ← --sw-bg          （正文 / 列表底）
    ;   text   正文          ← --sw-fg
    ;   dim    次要文字      ← --sw-dim
    ;   accent 强调色        ← --sw-accent      主题可自带，缺省按明暗取
    ;   border 分隔线        ← --sw-border      派生：win 往 text 偏 18%
    ;   panel  区域底        ← 无（面板例外不用它）派生：win 再偏一档
    ;   codeBg 代码块 / 列表底 ← --sw-code-bg   派生：与 ahk.ts 的 shift 同式
    ;
    ; ⚠ panel 的偏移量不是随手取的：原工作台面板正是 FFF8E7 → F2E8D2（≈ -13），
    ;   而 .clinerules/02 实测「只差一档几乎看不出分区」—— 这里取 14，比原来还深一点。
    static Palette(idx := 0) {
        t := this.Themes[idx ? idx : this._current]
        dark := this.IsDark(t.win)

        p := {
            name: t.name, dark: dark,
            win: t.win, edBg: t.edBg, text: t.text, dim: t.dim,
            accent: t.HasProp("accent") ? t.accent : (dark ? "7FB4D8" : "4A7C9E"),
            border: this._Mix(t.win, t.text, 0.18),
            panel:  this._Shift(t.win, dark ? 14 : -14),
            codeBg: this._Shift(t.edBg, dark ? 12 : -8),
            bg:     t.HasProp("bg") ? t.bg : "",
            bgAlpha: t.HasProp("bgAlpha") ? t.bgAlpha : 0,
            bgFit:  t.HasProp("bgFit") ? t.bgFit : "cover"
        }
        return p
    }

    ; ─── 换主题 ───────────────────────────────────────────────────────────

    static Next() {
        ; 只有一套时 Alt+T 是**空操作**：不写配置、不发事件 ——
        ; 发了也只是让各窗口白重绘一遍（每次都要重建 brush），纯属折腾。
        if (this.Themes.Length <= 1)
            return this._current
        this.Apply(this._current >= this.Themes.Length ? 1 : this._current + 1)
        return this._current
    }

    ; 切换并广播。**不看窗口**：谁开着窗口谁订阅 Theme.Changed 自己重绘 ——
    ; 平台不知道有几个窗口，也不该知道（模块可插拔）。
    static Apply(idx) {
        if (idx < 1 || idx > this.Themes.Length)
            idx := 1
        this._current := idx

        if !this._loading
            this.SaveToConfig()

        p := this.Palette()
        EventBus.Emit("Theme.Changed", {name: p.name, idx: idx, dark: p.dark})
        return p
    }

    ; ─── 持久化 ───────────────────────────────────────────────────────────

    static SaveToConfig() {
        ConfigService.Write("Appearance", "ThemeIndex", this._current)
    }

    ; 启动时恢复。**只改状态、不广播**：调用点在 WorkBench.Init() 开头，
    ; 那时窗口一个都还没建，广播出去也没人接；而且模块 Init 正要读 GetCurrent()
    ; 来定主窗口底色与 WebView2 首帧色。
    static LoadFromConfig() {
        this._loading := true
        idx := ConfigService.ReadInt("Appearance", "ThemeIndex", 1)
        idx := this._MigrateIndex(idx)
        if (idx < 1 || idx > this.Themes.Length)
            idx := 1
        this._current := idx
        this._loading := false
        return idx
    }

    ; ─── 旧下标迁移 ───────────────────────────────────────────────────────
    ; 主题表被精简过两次，而配置里存的始终是**下标**：
    ;   schema 1 = 8 套（v2.4 之前）   schema 2 = 5 套（v2.4–v2.8）
    ;   schema 3 = 1 套（只留纯米黄，背景图主题等打磨完再接）
    ; 现在只有 1 套，所以**老配置的 1–8 一律归 1**，逐条映射已无意义。
    ; ⚠ 迁移只能做一次，并且**必须把新值写回配置** —— 否则每次启动都拿 ThemeIndex=5
    ;   去撞越界兜底，配置里永远躺着一个不存在的下标。
    static _MigrateIndex(idx) {
        if (ConfigService.ReadInt("Appearance", "ThemeSchema", 1) >= 3)
            return idx
        ConfigService.Write("Appearance", "ThemeIndex", 1)
        ConfigService.Write("Appearance", "ThemeSchema", 3)
        return 1
    }

    ; ─── 颜色工具 ─────────────────────────────────────────────────────────

    ; 「深色」判据：底色按加权亮度 < 128 即视为深色。标题栏 / 滚动条 / 派生态共用这一条，
    ; 前端 ahk.ts 的 luminance() 也用同一公式 —— 两边判出来的明暗必须一致。
    static IsDark(hex) {
        r  := Integer("0x" . SubStr(hex, 1, 2))
        g  := Integer("0x" . SubStr(hex, 3, 2))
        b  := Integer("0x" . SubStr(hex, 5, 2))
        return (0.299 * r + 0.587 * g + 0.114 * b) < 128
    }

    ; 整体加减同一档亮度（三个通道同量）—— 保色相，用于 panel / codeBg。
    ; 与 web/src/ahk.ts 的 shift(hex, delta) 逐字等价。
    static _Shift(hex, delta) {
        r := Integer("0x" . SubStr(hex, 1, 2)) + delta
        g := Integer("0x" . SubStr(hex, 3, 2)) + delta
        b := Integer("0x" . SubStr(hex, 5, 2)) + delta
        return Format("{:02X}{:02X}{:02X}", this._Clamp(r), this._Clamp(g), this._Clamp(b))
    }

    ; 两个颜色线性混合：t = 0 取 a，t = 1 取 b。用于 border（win 往 text 偏），
    ; 比单纯加减亮度好在**色相跟着正文走** —— 深棕字配深棕线、冷白字配冷灰线。
    static _Mix(a, b, t) {
        out := ""
        for i in [1, 3, 5] {
            av := Integer("0x" . SubStr(a, i, 2))
            bv := Integer("0x" . SubStr(b, i, 2))
            out .= Format("{:02X}", this._Clamp(Round(av + (bv - av) * t)))
        }
        return out
    }

    static _Clamp(v) => v < 0 ? 0 : (v > 255 ? 255 : v)

    ; ─── 状态栏文案 ───────────────────────────────────────────────────────

    ; 「主题名 · 字体名 12pt」—— 从前贴在工作区底部那条状态栏上，控件随 RichEdit 一起退场了；
    ; 保留它是因为 FontService 还在用（`try` 包着，控件不在时静默跳过）。
    static _BuildLabel() {
        return ThemeService.GetName()
            . " · " . FontService.GetName()
            . " " . FontService.GetSize() . "pt"
    }

    ; "RRGGBB" → COLORREF（0x00BBGGRR）：Win32 的颜色是**反着**存的
    static RGBtoBGR(hexRGB) {
        r := SubStr(hexRGB, 1, 2)
        g := SubStr(hexRGB, 3, 2)
        b := SubStr(hexRGB, 5, 2)
        return Integer("0x" . b . g . r)
    }
}
