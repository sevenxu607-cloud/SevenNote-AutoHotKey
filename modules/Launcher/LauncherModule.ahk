#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  LauncherModule —— 外部程序模块生命周期
;  Phase 3 从组合根拆出：持有 PowerShell / DeepSeek 两个 Feature，
;  热键定义也归模块所有，注册仍由 WorkBench/HotkeyRouter 统一完成。
; ═══════════════════════════════════════════════════════════════════════════

class LauncherModule {
    static Id := "Launcher"
    static Name := "外部程序"

    static Init() {
        ; Feature 只保留查找 / 摆位 / 显示能力；热键不再由 Feature 自己注册。
        ; 伙伴窗口的事件订阅仍在 SevenNote 的 WindowFeature 里（Peer.* 契约）。
        PowerShellFeature.Init()
        DeepSeekFeature.Init()
    }

    ; 由主脚本的 HotkeyTable() 并入同一张表 —— 注册与 Alt+H 帮助共用一份数据。
    static GetHotkeys() {
        return [
            {ctx: "global", key: "!c", group: "输入增强"
                , line: "   Alt+C            唤出 / 隐藏 PowerShell（笔记自动让位）"
                , fn: (*) => PowerShellFeature.Toggle()},
            {ctx: "global", key: "!x", group: "输入增强"
                , line: "   Alt+X            呼出 / 隐藏 DeepSeek 网页（笔记自动让位）"
                , fn: (*) => DeepSeekFeature.Toggle()}
        ]
    }
}
