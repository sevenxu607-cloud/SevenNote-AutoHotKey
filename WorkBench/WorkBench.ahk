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
        ModuleRegistry.Register(SevenNoteModule)
        ModuleRegistry.Register(LauncherModule)

        ; Phase 3b：先挂上 Launcher.Opened / SevenNote.WindowReady 的监听。
        PeerCoordinator.Init()
        WorkBenchUI.Init()
    }
}
