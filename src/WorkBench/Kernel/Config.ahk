#Requires AutoHotkey v2.0
; WorkBench/Kernel/Config.ahk
; Moved from SevenNote.ahk (Phase 1). Implementation unchanged.

class Config {
    static AppName := "SevenWork"
    static Version := "2.8"

    ; ═══ 身份判据：`_dev.flag`（目录即身份，与分支无关）═══
    ; 项目根存在 `_dev.flag` = 开发身份；主目录（日用）不放它。
    ; 该文件在 .gitignore 里、是**未跟踪**的本地标记 —— 因此 main 与 dev 两条分支的
    ; 源码完全一致，合并零冲突；身份由「从哪个工作树启动」决定，重启也不会跑错。
    ; 编译版永远算生产：exe 旁边误放 flag 也不该读测试配置。
    ; ⚠ 两个 FileExist 覆盖两种入口：根启动器（A_ScriptDir = 树根）与
    ;   `src\SevenWork.ahk`（调试 / 探针时 = `src\`）。
    ; ⚠ 用 `=>` 简写属性：A_ScriptDir / A_IsCompiled 在取值时才求值，
    ;   不在类加载期赌内置变量是否已就绪。
    static IsDev => !A_IsCompiled
        && (FileExist(A_ScriptDir . "\_dev.flag") || FileExist(A_ScriptDir . "\..\_dev.flag"))
    ; 配置目录与 pandoc 目录**故意不同**，不是笔误：
    ;   · _config.ini 是使用者状态（主题 / 字体 / Vault 路径），按身份隔离 ——
    ;     开发走 SevenWork-Dev（测试库），日用 / 编译版走 SevenWork（真实笔记库），
    ;     两边各改各的，互不覆盖。
    ;   · pandoc.exe 是 100+MB 的内嵌可执行文件，跨身份共用一份，不随配置目录搬家。
    static AppDataDir => this.IsDev
        ? A_AppData . "\SevenWork-Dev"
        : A_AppData . "\SevenWork"
    static ConfigPath => this.AppDataDir . "\_config.ini"
    static PandocPath := A_AppData . "\SevenWork\pandoc.exe"

    ; 报错日志落点：开发身份写**当前工作树根 `.logs\`**（翻起来不用到处找；
    ; 从 `src\SevenWork.ahk` 跑探针时落在 `src\.logs\`）；日用 / 编译版跟配置落 AppData
    ; —— exe 可能在桌面 / U 盘 / Program Files，那里要么往用户目录里扔文件，
    ; 要么根本没写权限。
    ; ⚠ 用 `=>` 简写属性而不是 `:=`：A_ScriptDir 在取值时才求值。
    ; ⚠ 这两个身份别塞进上面的声明里 —— 它们依赖运行时内置变量。
    static LogDir => this.IsDev
        ? A_ScriptDir . "\.logs"
        : A_AppData . "\SevenWork"
    static LogPath => this.LogDir . "\_error.log"

    static GetVault() {
        v := ConfigService.Read("Paths", "Vault")
        if (v = "")
            return A_MyDocuments . "\SevenWork"
        return v
    }
    static SetVault(path) => ConfigService.Write("Paths", "Vault", path)

    ; 提示词库根目录（Text 模块的数据面）。
    ; 默认挂在 Vault 下的 `_prompts\` —— 数据跟着笔记库走，备份 / 迁移只有一处。
    ; 想让它独立（单独同步、放别的盘）就在 _config.ini 写 `[Paths] PromptsDir=...`，
    ; 非空即覆盖。留这个口子是为了「不逼用户把两类数据绑死」，默认则零配置。
    static GetPromptsDir() {
        d := ConfigService.Read("Paths", "PromptsDir")
        if (d = "")
            return this.GetVault() . "\_prompts"
        return d
    }

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
