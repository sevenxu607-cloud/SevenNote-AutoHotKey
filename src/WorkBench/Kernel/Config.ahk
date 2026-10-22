#Requires AutoHotkey v2.0
; WorkBench/Kernel/Config.ahk
; Moved from SevenNote.ahk (Phase 1). Implementation unchanged.

class Config {
    static AppName := "SevenWork"
    static Version := "2.14"

    ; ═══ 落点：一个目录、一份配置、一处日志（v2.14 起取消「开发身份」）═══
    ; 曾经用工作树根的 `_dev.flag` 区分开发 / 日用：开发走 `SevenWork-Dev` 配置、
    ; 日志落工作树 `.logs\`。代价是**两个工作树、两条分支、两份配置、两处日志**，
    ; 而源码本来就零差异 —— 管理成本远大于「隔离」带来的收益，故整套取消。
    ; 现在无论从哪个入口、哪个目录启动，都是同一份 `_config.ini`、同一个日志文件。
    ; ⚠ 代价：探针脚本也读写这份**生产配置**。跑探针前先自己备份 `_config.ini`；
    ;   探针本身不该写配置，真写坏了就靠备份还原。
    static AppDataDir => A_AppData . "\SevenWork"
    static ConfigPath => this.AppDataDir . "\_config.ini"
    static PandocPath := A_AppData . "\SevenWork\pandoc.exe"

    ; 报错日志跟配置放一起。不落工作树 `.logs\` 的理由：
    ;   ① 项目目录可能在同步盘 / 只读位置，写不进去就丢日志；
    ;   ② 「日志在哪」只该有一个答案 —— 少一个分支就少一次「翻了半天没找着」。
    ; ⚠ 用 `=>` 简写属性而不是 `:=`：A_AppData 在取值时才求值。
    static LogDir => this.AppDataDir
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
