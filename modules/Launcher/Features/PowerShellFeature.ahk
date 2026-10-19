#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  PowerShellFeature —— Alt+C 呼出 PowerShell
;  Phase 3 从 SevenNote.ahk 原样搬入；热键交由 LauncherModule.GetHotkeys()。
; ═══════════════════════════════════════════════════════════════════════════

; ─── 参考实现：Alt+C 呼出终端 ───
; 本 Feature 是「伴生窗口适配」契约（Peer.Preparing / Peer.Placed / Peer.Failed）的示范用法。
; 要接入别的外部窗口（资源管理器 / Obsidian / 浏览器…），照这四步抄即可：
;   ① 确定能起来之后，先广播 Peer.Preparing —— 让笔记窗口退场
;   ② 启动外部程序（⚠ 别传 Run 的 "Hide"，理由见 _LaunchPowerShell）
;   ③ 轮询到它的窗口后 WinShow / WinActivate，再用 _BroadcastRect 广播 Peer.Placed
;   ④ 任何一步失败（Run 抛错、等满超时）都要广播 Peer.Failed，把笔记窗口还回来
; 逐条说明与必须守住的点见 README「开发指南 → 添加呼出外部窗口的功能」。
class PowerShellFeature {
    static _initialized := false
    static _powershellPath := A_WinDir . "\System32\WindowsPowerShell\v1.0\powershell.exe"
    static _windowTitle := "SevenNote PowerShell"

    static Init() {
        if (this._initialized)
            return
        ; 热键由 LauncherModule.GetHotkeys() 交给 HotkeyRouter；Feature 不再自注册。
        this._initialized := true
    }

    static Toggle() {
        hwnd := this._FindPowerShellHwnd()
        if (hwnd = 0) {
            this._LaunchPowerShell()
            return
        }

        ; ⚠ 必须同时看「可见」：WinHide 之后 GetForegroundWindow 仍指着那个隐藏窗口
        ;   （本机实测 1.2s 后依然如此），只看 WinActive 会判定成「在前台 → 再藏一次」，
        ;   于是按了没反应、再也呼不出来。DeepSeekFeature.Toggle 是同一处。
        if (this._IsVisible(hwnd) && WinActive("ahk_id " . hwnd)) {
            WinHide("ahk_id " . hwnd)
            return
        }

        this._ShowAndFocus(hwnd)
    }

    ; 窗口此刻是否真的在屏幕上（WinHide 过 = false）。
    ; ⚠ 别用 IsIconic 组合来判断这里的「在显示」—— 那是判断最小化的写法：
    ;   本窗口只会被 WinHide 藏起来，不会被最小化，看 IsWindowVisible 一个就够。
    static _IsVisible(hwnd) => !!DllCall("IsWindowVisible", "ptr", hwnd, "int")

    static _FindPowerShellHwnd() {
        detectHidden := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            ids := WinGetList(this._windowTitle)
            return ids.Length ? ids[1] : 0
        } finally {
            DetectHiddenWindows(detectHidden = "On")
        }
    }

    static _ShowAndFocus(hwnd) {
        ; 让笔记窗口先退场 —— 它接下来要换位置换尺寸，这一整段不该被看见。理由详见
        ; WindowFeature._CollapseForPeer。重复发是无害的：窗口已经收起时那次调用会跳过。
        ; ⚠ 这条广播管的是笔记窗口，不是终端：终端的露面时机由它自己的宿主掌握
        ;   （为什么不能靠 Run 的 "Hide" 去藏它，见 _LaunchPowerShell）。
        EventBus.Emit("Peer.Preparing")

        WinShow("ahk_id " . hwnd)
        ; ⚠ WinShow 之后必须再 WinRestore：窗口被 WinHide 藏起来后，宿主可能把自己
        ;   标记成「最小化」，而 WinShow 不解除最小化，用户看到的就是「窗口没回来」。
        ;   浏览器（Chromium）实测必现，终端留着这行也无害 —— 兜底就该一直有。
        WinRestore("ahk_id " . hwnd)
        WinActivate("ahk_id " . hwnd)
        try {
            WinSetAlwaysOnTop("On", "ahk_id " . hwnd)
        }
        this._PlaceLikeDeepSeek(hwnd)

        ; 把实际落点广播出去，由笔记窗口（WindowFeature）据此避让 —— 谁被动谁适配。
        this._BroadcastRect(hwnd)

        ; 广播是同步的（EventBus 直接循环调用 handler），所以上一行返回时笔记窗口已经
        ; 露面了 —— 而 Show() 末尾会激活窗口自身，把前台从刚呼出的终端手里夺走。
        ; 按 Alt+C 是要用终端，这里还回去。
        WinActivate("ahk_id " . hwnd)
    }

    ; 摆到「和 DeepSeek 窗口同一处」：右侧贴工作区右缘（离缘 Config.PlaceRight）、
    ; 底边贴工作区底。「可摆性闸」与落点算式都在 PeerLayoutService 里 ——
    ; 终端与 DeepSeek 共用同一份，不必再两处同步。
    ;
    ; 为什么需要这一步：终端的落点由 Windows Terminal 的 initialPosition 决定，
    ; 那份值是用户当年按「有任务栏」设的。本机实测 —— 终端 1803,540（底边 1560，
    ; 离工作区底 40px），而 DeepSeek 按公式落在 1801,580（底边贴 1600，任务栏已
    ; 改为自动隐藏），两个伙伴高度不齐、堆叠观感不一致。对齐后两者落在同一处。
    ;
    ; ⚠ 宽度也一起对齐（理由见方法内注释）：只挪位置的话，终端 profile 的 744 与
    ;   DeepSeek 的 770 都按右缘摆，左缘就差 26px、堆叠处露出一条底色。高度仍归 profile。
    ; ⚠ 全程 WinMove（物理像素），别混用 Gui.Move（它收逻辑单位、还会再乘一次 DPI）。
    static _PlaceLikeDeepSeek(hwnd) {
        ; ⚠ 隐藏 / 最小化的窗口一律不碰 —— 闸的实现与实测账见 PeerLayoutService.IsPlaceable。
        if !PeerLayoutService.IsPlaceable(hwnd)
            return
        WinGetPos(, , &w, &h, "ahk_id " . hwnd)
        if (w <= 0 || h <= 0)
            return

        ; 宽度改用与 DeepSeek / 笔记窗口**同一个**目标宽，不再用终端自己的宽。
        ; ⚠ 实测（本机）：终端 profile 是 744x1020，DeepSeek 目标是 772x1020；两边都按
        ;   「右缘贴屏幕」摆，于是右缘齐（2545）、**左缘差 26px**（终端可见 1810..2536 /
        ;   DeepSeek 可见 1784..2538），堆叠处左边露出一条底色 —— 看起来就是「终端比
        ;   其他两个窄一点、缺口在左边」。宽度统一后左 / 右 / 底三条边全齐。
        ;   只改宽，高度仍归 Windows Terminal 的 profile。
        tw := PeerLayoutService.TargetW()
        rect := PeerLayoutService.CornerRect(tw, h)
        WinMove(rect.x, rect.y, tw, , "ahk_id " . hwnd)
    }

    ; 广播伴生窗口此刻的实际位置与尺寸，供笔记窗口让位（Peer.Placed 契约）。
    ; 读矩形的细节（隐藏态要开 DetectHiddenWindows）见 PeerLayoutService.RectOf。
    static _BroadcastRect(hwnd) {
        rect := PeerLayoutService.RectOf(hwnd)
        if !IsObject(rect)
            return
        EventBus.Emit("Peer.Placed", {hwnd: hwnd, x: rect.x, y: rect.y, w: rect.w, h: rect.h})
    }

    ; 启动目录：默认 D 盘根目录，可在 _config.ini 的 [Paths] PowerShellStartDir 覆盖
    ; 若目标目录不存在（如无 D 盘），依次回退到用户主目录、A_MyDocuments，避免启动失败
    ; 注：AHK v2 没有 A_UserProfile 内置变量，用户主目录需取自 USERPROFILE 环境变量
    static _StartDir() {
        dir := ConfigService.Read("Paths", "PowerShellStartDir")
        if (dir = "")
            dir := "D:\"
        if !DirExist(dir)
            dir := EnvGet("USERPROFILE")
        if !DirExist(dir)
            dir := A_MyDocuments
        return dir
    }

    static _LaunchPowerShell() {
        if !FileExist(this._powershellPath) {
            MsgBox("未检测到 Windows PowerShell，无法使用 Alt+C 启动。", "SevenNote", "Icon!")
            return
        }

        ; 确定要启动了，才让笔记窗口退场 —— 上面那条早退分支不能白收一次。
        EventBus.Emit("Peer.Preparing")

        try {
            command := "$Host.UI.RawUI.WindowTitle = '" . this._windowTitle . "'"
            ; ⚠ Run 的第三个参数只能留空，绝不能传 "Hide"。
            ;
            ; 本机 HKCU:\Console\%%Startup 里 DelegateTerminal = {00000000}「让 Windows 决定」，
            ; 实际落到 Windows Terminal：正常启动时 conhost 会把控制台交接给它，于是终端是
            ; 你配好的那个 —— Windows PowerShell profile、星空背景图、One Half Dark。
            ; 但 **隐藏着启动，这次交接就不会发生**，终端退回由 conhost 自己承载，顶着注册表
            ; 默认值出现：WindowSize = 120x50（实测 1488x1256）、conhost 的级联落点、
            ; 配色变成 powershell.exe 子键里的 ColorTable05 = #012456 经典蓝。
            ; 症状就是「终端背景失灵、位置大小不对」。
            ;
            ; 实测（AHK 探针，同样两条命令各启动一次、取窗口家族差集）：
            ;   Run(cmd, dir)          → CASCADIA_HOSTING_WINDOW_CLASS（Windows Terminal）
            ;   Run(cmd, dir, "Hide")  → ConsoleWindowClass（conhost）
            ;
            ; 代价：终端会带着「Windows PowerShell」旧标题先露一脸，等 PowerShell 进程把标题
            ; 设好、我们再轮询到它才归位。这一步的观感只能由 Windows Terminal 自己承载 ——
            ; 藏窗口绕过它，等于把整台终端换掉。
            Run('"' . this._powershellPath . '" -NoLogo -NoExit -Command "' . command . '"', this._StartDir())
        } catch as err {
            MsgBox("启动 PowerShell 失败：`n" . err.Message, "SevenNote", "Icon!")
            EventBus.Emit("Peer.Failed")
            return
        }

        ; 轮询要密：终端进程起来约 0.7s，每一档的等待都会叠进「按了没反应」的那段空白。
        deadline := A_TickCount + 15000
        while (A_TickCount < deadline) {
            hwnd := this._FindPowerShellHwnd()
            if (hwnd != 0) {
                this._ShowAndFocus(hwnd)
                return
            }
            Sleep(20)
        }

        hwnd := this._FindPowerShellHwnd()
        if (hwnd != 0) {
            this._ShowAndFocus(hwnd)
        } else {
            MsgBox("PowerShell 已启动，但未能找到它的窗口。", "SevenNote", "Icon!")
            EventBus.Emit("Peer.Failed")
        }
    }
}
