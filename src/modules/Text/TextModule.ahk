#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  TextModule —— 文本模块（数据面 · 片段库）
; ═══════════════════════════════════════════════════════════════════════════
; 与 SevenNote 的分工：
;   SevenNote  日期为轴、一天一篇、长文连续记录（时间流）
;   Text       分类 + 标题为轴、无时间线、可复用片段（片段库）
;
; 本模块的第一个（也是当前唯一一个）功能：**提示词工程**。
; 数据落在 `<Vault>\_prompts\`，目录即分类、文件名即标题、文件全文即正文，
; 外部可直接用 VS Code / Obsidian 编辑，也能用 git 备份（详见 PromptStoreService）。
;
; 生命周期（照平台的 Init → RegisterAll → Start 三段式）：
;   Init()      建数据目录、播种三个顶层分类；**不建窗口**
;   Start()     无对外可见动作 → 不实现（窗口在首次 Alt+P 时才懒建）
;   GetContexts 两个上下文：主窗口在 prompt 列表操作、编辑窗口在写正文

class TextModule {
    static Id := "Text"
    static Name := "文本"

    static _initialized := false

    static Init() {
        if this._initialized
            return
        this._initialized := true
        ; 只碰磁盘：`_prompts\` + 首次运行播种 Chat / Code / Work。
        ; 放在 Init 里而不是 Start：这是「内部就绪」，不涉及任何窗口。
        PromptStoreService.EnsureRoot()
    }

    ; ─── 上下文 ───
    ; ⚠ 这两个函数会被 HotkeyRouter 表驱动地注册（ctx 名 → 本次会话注册哪些热键）。
    ;   窗口还没建时 Hwnd() 返回 0，WinActive("ahk_id 0") 只是 false，不报错。
    static GetContexts() {
        return {
            prompts:     (*) => WinActive("ahk_id " . PromptWindowFeature.Hwnd()),
            promptsEdit: (*) => WinActive("ahk_id " . PromptEditFeature.Hwnd())
        }
    }

    ; ─── 热键 ───
    static GetHotkeys() {
        return [
            {ctx: "global", key: "!p", group: "文本"
                , line: "   Alt+P            呼出 / 隐藏提示词库"
                , fn: (*) => PromptWindowFeature.Toggle()},

            {ctx: "prompts", key: "Esc", group: "文本"
                , line: "   Esc              关闭提示词库"
                , fn: (*) => PromptWindowFeature.Hide()},
            {ctx: "prompts", key: "Enter", group: "文本"
                , line: "   Enter            复制选中的提示词"
                , fn: (*) => PromptWindowFeature.CopySelected()},
            {ctx: "prompts", key: "^n", group: "文本"
                , line: "   Ctrl+N           新建提示词"
                , fn: (*) => PromptWindowFeature.NewPrompt()},
            {ctx: "prompts", key: "F5", group: "文本"
                , line: "   F5               重新扫描提示词目录"
                , fn: (*) => PromptWindowFeature.Reload(true)},

            {ctx: "promptsEdit", key: "Esc", group: "文本"
                , line: "   Esc              取消编辑（不保存）"
                , fn: (*) => PromptEditFeature.Hide()},
            {ctx: "promptsEdit", key: "^s", group: "文本"
                , line: "   Ctrl+S           保存提示词"
                , fn: (*) => PromptEditFeature.Save()}
        ]
    }

    ; 帮助窗口（Alt+S）用：order 决定模块在帮助里的先后（平台 0 / 笔记 20 / …）
    static GetMetadata() {
        return {order: 40, hotkeys: this.GetHotkeys()}
    }
}
