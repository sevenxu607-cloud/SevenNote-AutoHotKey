#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  WorkBench —— 平台组合根（Phase 3b）
; ═══════════════════════════════════════════════════════════════════════════
; 只做平台级装配：登记模块、初始化事件协调器与界面占位。
; 各模块自己的 Feature 生命周期仍由 Module.Init() 负责，平台不越层调用。
class WorkBench {
    static _initialized := false

    static Init() {
        if this._initialized
            return
        this._initialized := true

        ; 模块登记只放「模块类」——它们统一带 Id / Name / Init() / GetHotkeys()。
        ; ⚠ 加模块只改这里（一行 #Include 在上面）+ 一行 Register，组合根不动：
        ;   启动 / 热键 / 兜底都由 ModuleRegistry.InitAll() / StartAll() / HotkeyRouter 遍历。
        ModuleRegistry.Register(SevenNoteModule)
        ModuleRegistry.Register(LauncherModule)
        ModuleRegistry.Register(KeysInputModule)
        ModuleRegistry.Register(TextModule)
        ModuleRegistry.Register(FoldersModule)

        ; Phase 3b：先挂上 Launcher.Opened / SevenNote.WindowReady 的监听。
        PeerCoordinator.Init()
        WorkBenchUI.Init()
    }

    ; ─── 平台级热键：工作台面板 + 保存退出 ───
    ; Alt+S 由平台负责打开面板（帮助 + 各模块设置）；Alt+Shift+Z 只广播 Save.Requested，
    ; 真正落盘仍由 SevenNote 的 SaveFeature 订阅处理 —— 平台不直接调用模块内部 Feature。
    static GetHotkeys() {
        return [
            {ctx: "global", key: "!s", group: "平台", line: "   Alt+S            工作台面板（帮助 + 设置）"
                , fn: (*) => WorkBenchUI.ShowHelp()},
            {ctx: "global", key: "!+z", group: "平台", line: "   Alt+Shift+Z      保存并退出"
                , fn: (*) => (EventBus.Emit("Save.Requested"), ExitApp())}
        ]
    }

    static GetMetadata() {
        return {name: "平台", desc: "工作台", order: 0, hotkeys: this.GetHotkeys()}
    }
}
