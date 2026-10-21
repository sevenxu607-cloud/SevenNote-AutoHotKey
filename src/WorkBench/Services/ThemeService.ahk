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
    static Themes := [
        ; ⚠ 主题表在 v2.4 精简过一次（8 套 → 5 套）：删掉天空蓝 / 薄荷绿 / 高雅灰，
        ;   留下「纯米黄 / 护眼绿」两套浅色底 + 「纸白」中性白 + 「星空 / 金克斯」两套图主题。
        ;   被删的各有替代：薄荷绿 → 护眼绿，天空蓝 / 高雅灰 → 纸白。
        ; ⚠ 删主题会让**其后所有元素的下标往前挪**，而配置里存的正是下标 —— 老用户会被
        ;   换成另一套主题，甚至越界兜底。故 _MigrateIndex() 里留了一次性下标迁移。
        {name: "纯米黄", win: "FFF8E7", edBg: "FFF8E7", text: "3D2B1F", dim: "A89880"},
        {name: "护眼绿", win: "CCE8CF", edBg: "E0F0E3", text: "2D4A30", dim: "6B8E6E"},
        {name: "纸白",   win: "FAFAFA", edBg: "FFFFFF", text: "333333", dim: "999999"},
        ; ⚠ 带背景图的主题：bg 是图片路径，bgAlpha 是把图压暗的遮罩不透明度（0-100）。
        ;   这套配色取自那张星空图（实测全图均色 #181C25、平均亮度仅 28）：win / edBg 都
        ;   贴着图的暗部走（亮度 ≈15），编辑区内外浑然一体，没有色块割裂感。
        ;   bgAlpha = 0 表示不压暗：Windows Terminal 用的就是同一张图、backgroundImageOpacity
        ;     设成 1（完全不压暗），这里对齐它 —— 星云保持原样、最亮也最清楚。
        ;   ⚠ 不压暗之后前景色必须够亮：文字取近白、次级文字也抬到浅灰蓝，
        ;     否则压在星云亮部（亮度约 60-130）上会发灰读不清。
        ;   图片缺失时自动降级成纯深色底（edBg），浅色文字照样读得清。
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
        ; ⚠ 烘焙由 tools\rebake-backdrop.ps1 一次跑完（三步：按 0.917 裁 → 缩到 2400 宽
        ;   + V 空间等比缩放 → 成品尺寸 unsharp），三代参数与实测账见
        ;   docs/THEME-IMAGES.md；这里只记结论：**当前成品 = 三代**
        ;   （-CropW 1.00 / -Knee 138 -HiMax 200），别照抄一代 / 二代的旧参数。
        ; ⚠ 素材是 5897x8719 的高清原图「金克斯竖版.png」，别退回去用 2000x2300 的
        ;   「金克斯竖版02.png」—— 那张缩到编辑区只剩 3 倍余量，锐化后更容易发糊。
        {name: "金克斯", win: "0B1624", edBg: "0B1624", text: "EAF2FF", dim: "93AACB"
            , bg: "D:\00-SevenFiles\Pictures\04-素材库\壁纸\动漫\金克斯主题.png"
            , bgAlpha: 0
            , bgFit: "cover"}
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

    ; ─── 旧下标迁移（v2.4 精简主题表：8 套 → 5 套）───
    ; 主题表删掉 3 套之后，配置里存的老下标语义全变了 —— 本机实测老配置是 ThemeIndex=8
    ; （金克斯），而新表只有 5 套：不迁移就**越界**，被下面那句兜底成「纯米黄」，
    ; 等于把用户的主题悄悄换掉。按下表把被删主题映到最相近的保留主题：
    ;     旧 1 米黄 → 1    旧 2 护眼绿 → 2    旧 3 天空蓝 → 3 纸白
    ;     旧 4 薄荷绿 → 2  旧 5 高雅灰 → 3    旧 6 纸白 → 3
    ;     旧 7 星空 → 4    旧 8 金克斯 → 5
    ; ⚠ 迁移**只能做一次**：同一个数字在新旧语义下含义不同（新表 4 = 星空、旧表 4 =
    ;   薄荷绿），再映射一遍会把用户刚选的主题又改掉。故用 [Appearance] ThemeSchema=2
    ;   打标记；并且**必须把新下标写回配置** —— 否则下次启动又拿旧值去走越界兜底，
    ;   迁移成了摆设。
    static _MigrateIndex(idx) {
        if (ConfigService.ReadInt("Appearance", "ThemeSchema", 1) >= 2)
            return idx
        idxMap := [1, 2, 3, 2, 3, 3, 4, 5]
        newIdx := (idx >= 1 && idx <= idxMap.Length) ? idxMap[idx] : idx
        ConfigService.Write("Appearance", "ThemeIndex", newIdx)
        ConfigService.Write("Appearance", "ThemeSchema", 2)
        return newIdx
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
