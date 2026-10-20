#Requires AutoHotkey v2.0
; WorkBench/Kernel/Config.ahk
; Moved from SevenNote.ahk (Phase 1). Implementation unchanged.

class Config {
    static AppName := "SevenWork"
    static Version := "2.4.5"

    ; ⚠ 配置目录与 pandoc 目录**故意不同**，不是笔误：
    ;   · _config.ini 是使用者状态（主题 / 字体 / Vault 路径），按版本隔离 ——
    ;     开发版走 SevenWork-Dev，发布版走 SevenWork，升级时不会互相覆盖配置。
    ;   · pandoc.exe 是 100+MB 的内嵌可执行文件，跨版本共用一份，不随配置目录搬家。
    ; ⚠ 用 `=>` 简写属性：A_IsCompiled 在取值时才求值，源码运行与编译版各走各的目录。
    static AppDataDir => A_IsCompiled
        ? A_AppData . "\SevenWork"
        : A_AppData . "\SevenWork-Dev"
    static ConfigPath => this.AppDataDir . "\_config.ini"
    static PandocPath := A_AppData . "\SevenWork\pandoc.exe"

    ; 报错日志落点：**开发版写项目根的 .logs\**，翻起来不用到处找；
    ; 编译版仍回 AppData —— exe 可能在桌面 / U 盘 / Program Files，那里
    ; 要么往用户目录里扔文件，要么根本没写权限。
    ; ⚠ 用 `=>` 简写属性而不是 `:=`：A_IsCompiled / A_ScriptDir 在取值时才求值，
    ;   不在类加载期赌内置变量是否已就绪。
    ; ⚠ 这两个身份别塞进上面的声明里 —— 它们依赖运行时内置变量。
    static LogDir => A_IsCompiled
        ? A_AppData . "\SevenWork"
        : A_ScriptDir . "\.logs"
    static LogPath => this.LogDir . "\_error.log"

    static GetVault() {
        v := ConfigService.Read("Paths", "Vault")
        if (v = "")
            return A_MyDocuments . "\SevenWork"
        return v
    }
    static SetVault(path) => ConfigService.Write("Paths", "Vault", path)

    ; 首次呼出时窗口距屏幕工作区右边 / 顶边的距离（物理像素）
    static PlaceRight := 15
    static PlaceTop := 264
    static AutoSaveInterval := 120000
    ; 字数 / 滚动同步的巡检间隔。**150ms 是实测出来的**（v2.4.4）：
    ;   · 巡检本身几乎免费 —— 1000 次 `GetScrollInfo` 实测 0ms；
    ;   · 真正花钱的只有「检测到脱节」后那一次 `EM_SETSCROLLPOS` 重排（小窗 2.4ms/次）；
    ;   · 500ms 时删掉一片空行，画面要等半秒才「啪」地跳一次 —— 用户报的「生硬」；
    ;   · 50ms 那版在真机上出过问题（删除过程中逐帧重排，画面抽搐）。
    ;   150ms 让删除过程中画面每 150ms 跟一次、删完立刻收尾，且不会逐帧重排。
    static StatInterval := 150
    ; 双窗并存（Alt+C 唤起 PowerShell / Alt+X 唤起 DeepSeek）时的「可见」间距（物理像素）：
    ; 两窗之间的缝、窗口到工作区顶/底的边距。
    ; ⚠ 这里算的是**肉眼看到**的距离 —— 按 DWM 的可见边界算，不含 Win11 的不可见调整边框。
    ;   本机实测 `WinGetPos` 的矩形比可见边界每边多 9px（左 −9 / 上 0 / 右 9 / 下 9），
    ;   若直接按矩形拼，设 12 的缝看上去会是 12 + 9 = 21。
    static DockGap := 6
    static DockMargin := 10
}
