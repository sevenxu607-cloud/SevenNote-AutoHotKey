#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()

; ═══════════════════════════════════════════════════════════════════════════
;  【警告策略 —— 改默认动作，别再让警告拦住程序】
;  AHK v2 对「未赋值变量」（VarUnset）默认既开警告、动作又是 **MsgBox** ——
;  一弹就停摆：模态框挡在屏幕上、热键全无反应，只能手动杀进程。
;  项目在 v2 迁移期连踩三次（`JSON.Stringify` / `Gui` 当变量名 / 空串比较），
;  每次症状都是「Alt+Z 没反应」，排查还得先枚举 #32770 读正文。
;  这里把动作改成 OutputDebug —— VS Code 的 AHK++ 调试器里照样看得到，
;  但不再拦路。未赋值变量的根本预防手段仍是「变量名写长一点」（guiHwnd / idxMap），
;  见 .clinerules/03。
; ═══════════════════════════════════════════════════════════════════════════
#Warn VarUnset, OutputDebug

; ═══════════════════════════════════════════════════════════════════════════
;  SevenNote —— v2.4.3
;  本地单文件速记工具。RichEdit 富文本编辑 + 双 RTF 存储 + Markdown 输出。
;  ⚠ 版本号以 Config.Version 为准（显示在 Alt+H 帮助窗口底部），改这里要一并改它。
;
;  【版本摘要】完整变更日志在 README「变更日志」表，这里只留一行一条的骨架。
;    v2.4.3  一轮「去重与仓库卫生」：① 新增 Service `PeerLayoutService` —— 终端 / DeepSeek
;            两处各自留底的「右下角落点公式 + 可摆性闸 + 矩形读取」收拢成一份（原先改
;            一处要记着同步另一处；实测两版摆位逐项一致）；② 删掉全局覆盖键
;            [Appearance] BackdropImage / BackdropOpacity（它会盖掉所有带 bg 的主题）
;            —— 图的路径与浓淡只写在主题自己的 bg / bgAlpha 上；③ StatFeature.Tick
;            补窗口可见性守卫；④ 加 .gitignore，演示测试产物出库。
;    v2.4.2  补齐运行时兜底与三处实测到的浪费：① 注册 OnError —— 未捕获异常写
;            _error.log（开发版落项目根 .logs\，编译版落 AppData）并**继续跑**，
;            不再弹模态框停摆；
;            同时把 VarUnset 警告动作改成 OutputDebug（同上，不再拦路）。
;            ② pandoc 可用性探测缓存（原先每次保存都 RunWait 起一个 200MB 进程）、
;            ConfigService 加进程内读缓存（GetVault 在保存链路上就要读 6 次盘）。
;            ③ ListAllTags 冒泡 O(n²) 换内置 Sort；SetTimer 回调统一过一遍
;            「窗口还在不在」守卫（照 AutoSaveFeature.Tick 的写法）
;    v2.4.1  修复连按 Alt+C / Alt+X 弹模态框卡死（异步复核去摆一个已隐藏的窗口）；
;            终端宽度与另外两个窗口统一，目标宽定 772（实测 Edge 会吸附 --window-size 的宽度）
;    v2.4    主题表精简 8 → 5 套并做一次性旧下标迁移（[Appearance] ThemeSchema）；
;            时间戳改为手动 Ctrl+T 插入（不再自动加）
;    v2.3    修背景图主题拉伸时编辑区文字闪烁（_ScheduleRender 抖动合并 + _RenderNow 同矩形跳过）；
;            编辑区滚动条随主题明暗；金克斯按「保留明暗 + 主体完整」重烘（-CropW 0.72 → 1.00）
;    v2.2    主题扩到 8 套，末尾两套为**背景图主题**（星空 / 金克斯，都是「暗图 + 亮字」，
;            裁剪与色调全烘进图片，运行时 bgAlpha 保持 0）；沉淀出 tools\rebake-backdrop.ps1
;    v2.1    伴生窗口适配只在首次跑一次（与笔记原来待的地方相撞才摆位，随后冻结，归用户自己管）
;    v2.0    Alt+X 呼出 / 隐藏 DeepSeek 网页；Alt+C 的窗口适配泛化成 Peer.* 通用契约
;    v1.9    修 pandoc 打包 0KB 问题；PandocService 加文件有效性校验（> 1MB）
;    v1.8    状态栏日期后显示星期（📅 2026-09-20 周日）
;    v1.7    assets 统一收纳到 _assets/日期/；切日期 / 跳转 / 启动加载后光标到开头 + 视口到顶
;
;  【用户旅程编号】组合根热键区与各 Feature 头部都用这套编号标注归属 ——
;    ① 唤起与关闭    Alt+Z 呼出 / 隐藏
;    ② 输入与编辑    粘贴 / 行编辑 / 缩进 / 撤销 / 输入增强
;    ③ 保存与持久化  加载 / 保存 / 自动保存 / 时间戳
;    ④ 查看与浏览    搜索 / 字数 / 光标记忆
;    ⑤ 组织与管理    日期切换 / 搜索跳转 / 标签 / 返回当天
;    ⚠ 全局热键只覆盖 ①②⑤；③④ 是编辑器内热键（见 WorkBench/HotkeyRouter.ahk），
;      所以在全局那一段里编号看起来是跳着的（② 之后直接 ⑤），那是正常的。
;
;  【整体架构 —— 四层 + 组合根】
;    FEATURE 功能层（21 项，按用户旅程排列）→ SERVICE 服务层（8 项，纯能力）
;     → KERNEL 骨架层（4 项：生命周期 / 状态 / 事件 / 配置）
;     → 表示层 StatusBar → 组合根（装配 + 启动，在文件末尾）
;    Kernel 实现在 WorkBench/Kernel/；SevenNote 的 7 个 Service、StatusBar、
;    18 个 Feature 与模块生命周期在 modules/SevenNote/。
;    本文件只保留组合根：首次引导、模块装配、热键表、帮助窗口与启动提示。
;
;  【依赖方向】Feature → Service → Kernel → OS（严禁反向）
;
;  【核心技术决策】
;    1. EM_STREAMOUT/EM_STREAMIN 直读直写 RTF
;    2. Pandoc 转换 RTF → Markdown
;    3. 双 RTF 输出（936 + 65001）
;    4. 系统默认 Ctrl+V
;    5. 空笔记不落盘
;    6. 先查后存
;    7. 标签写文件名
;    8. 路径分离
;    9. assets 统一收纳（v1.7）
;   10. pandoc 文件大小检查（v1.9）
;   11. 伴生窗口适配走 Peer.* 通用契约（v2.0）—— 发布方只广播三个事件，
;       摆位 / 记忆 / 失败兜底全在 WindowFeature 里，见 README「添加呼出外部窗口的功能」
;   12. 背景图主题只是 Themes 数组里的普通成员（v2.2）—— 切到铺图、切走撤图，没有全局开关
;   13. 编辑区滚动条与标题栏跟着主题明暗走（v2.3）
;
;  【已知坑点】全文见 .clinerules/03-ahk-v2.md（那里是单一事实源），这里只列最常踩的：
;    · AHK v2 内置函数名不能做变量名（Clear/log/min/max/Indent）；
;      ⚠ **Gui 也不能** —— 它是内置类名，`gui := WinExist(...)` 直接报错
;    · AHK v2 的 < > 是数值比较，字符串比较用 StrCompare
;    · AHK v2 的 <= / >= 遇空字符串会抛错，数值比较前先 IsNumber() 守卫
;    · EM_SETSEL/EM_GETSEL 用 DllCall 4 参数版本
;    · FINDTEXTEXW 读偏移 16/20（chrgText）
;    · 32 位编译导致 RichEdit 字符格式异常——必须 64 位
;    · FileInstall 必须一行，源路径不存在会打包 0KB 空文件（v1.9）
;    · 最小化窗口的 IsWindowVisible 仍是 1 —— 判断「在显示」要 IsWindowVisible && !IsIconic
;    · WinMove / WinGetPos 默认忽略隐藏窗口，对隐藏窗口直接抛 "Target window not found"；
;      **凡在异步定时器回调里碰窗口，先过一道闸**（DetectHiddenWindows(false) + WinExist + !IsIconic）
;    · 先 Show 再 WinMove 会让窗口「飘一下」：定位要在隐藏状态下做完（Show("Hide") → 摆好 → Show）
;    · 启动终端别传 Run 的 "Hide"：隐藏启动会绕过 Windows Terminal 委派，终端退回
;      conhost 默认（120x50 = 1488x1256、#012456 蓝底），拿不到 WT profile 的星空背景
;
;  依赖：pandoc.exe（软依赖，未安装则 MD 降级为纯文本）
; ═══════════════════════════════════════════════════════════════════════════


; ═══════════════════════════════════════════════════════════════════════════
;  KERNEL 骨架层 —— 实现见 WorkBench/Kernel/
; ═══════════════════════════════════════════════════════════════════════════

#Include WorkBench\Kernel\Config.ahk
#Include WorkBench\Kernel\ConfigService.ahk
#Include WorkBench\Kernel\EventBus.ahk
#Include WorkBench\Kernel\State.ahk
#Include WorkBench\ModuleRegistry.ahk
#Include WorkBench\HotkeyRouter.ahk
#Include WorkBench\WorkBenchUI.ahk
#Include WorkBench\Coordinator\PeerCoordinator.ahk

; ═══════════════════════════════════════════════════════════════════════════
;  SERVICE 服务层
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Services\EditorService.ahk


#Include modules\SevenNote\Services\ClipboardService.ahk


#Include modules\SevenNote\Services\NoteStoreService.ahk


#Include modules\SevenNote\Services\PandocService.ahk


#Include modules\SevenNote\Services\ThemeService.ahk


#Include modules\SevenNote\Services\FontService.ahk


#Include modules\SevenNote\Services\BackdropService.ahk

; ─── PeerLayoutService：伴生窗口的落点与可摆性（纯几何 + 窗口状态查询）───
; 终端（Alt+C）与 DeepSeek（Alt+X）必须摆到**同一处**：右缘贴工作区右缘（离缘
; Config.PlaceRight）、底边贴工作区底、宽度同为 [Paths] DeepSeekW。这份「同列同宽」
; 的算式原本在两个 Feature 里各留一份（Feature 之间不许互相调用），改一处就得记着
; 改另一处。它不属于任何单个 Feature、是纯计算与纯查询，故上收到 Service 层。
class PeerLayoutService {
    ; 隐藏 / 最小化的窗口一律当「不能摆」，调用方直接 return。
    ; ⚠ AHK v2 默认忽略隐藏窗口 —— 对 WinHide 过的窗口做 WinGetPos / WinMove 会抛
    ;   "Target window not found"，而调用方里有一支是异步 SetTimer 复核，等它跑起来时
    ;   用户很可能已经按热键把窗口收起了（实测弹模态框、整个脚本卡死，之后 Alt+X /
    ;   Alt+C 全无反应）。最小化态也别动：位置停在 -32000 停放位，量到的尺寸是垃圾值。
    static IsPlaceable(hwnd) {
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(false)
        try {
            return !!WinExist("ahk_id " . hwnd) && !DllCall("IsIconic", "ptr", hwnd, "int")
        } finally {
            DetectHiddenWindows(detectOld)
        }
    }

    ; 目标尺寸（物理像素）。默认 772x1020 —— 772 不是「照 WT profile 推算」的，而是
    ; **实测 Edge 自己会稳定停住的外框宽**（请求 513 逻辑像素落到 772），终端也按同一
    ; 宽度摆，于是 Alt+C 与 Alt+X 两种堆叠布局的左 / 右 / 底三条边全齐。
    ; ⚠ 为什么不写 770：Edge 把内容区尺寸套到窗口外框上时会再补一圈调整边框，WinMove
    ;   摆到 770 后它自己又套回 772 —— 跟它抢只会来回弹，尺寸复核每轮都判「不符」。
    ; ⚠ 实测过：直接砍 --window-size 的宽度请求值没用，Edge 会把宽度吸附到自己的值
    ;   （请求 506 / 512 逻辑都落在 773）。换机器 / 换缩放若要重定：先 WinGetPos 量一次
    ;   外框，再改这里的默认值；也可在 _config.ini 的 [Paths] DeepSeekW / DeepSeekH 覆盖。
    static TargetW() {
        v := ConfigService.ReadInt("Paths", "DeepSeekW", 0)
        return v > 0 ? v : 772
    }

    static TargetH() {
        v := ConfigService.ReadInt("Paths", "DeepSeekH", 0)
        return v > 0 ? v : 1020
    }

    ; 右下角对齐的落点：右侧贴工作区右缘（离缘 Config.PlaceRight）、底边贴工作区底。
    ; 返回 {x, y}；尺寸由调用方决定（终端只改宽，高度仍归 Windows Terminal 的 profile）。
    ; ⚠ 全程 WinMove（物理像素），别混用 Gui.Move（它收逻辑单位、还会再乘一次 DPI）。
    static CornerRect(w, h) {
        MonitorGetWorkArea(MonitorGetPrimary(), &wkLeft, &wkTop, &wkRight, &wkBottom)
        x := wkRight - w - Config.PlaceRight
        y := wkBottom - h
        ; 兜底：工作区比窗口还小时别落到屏幕外
        if (x < wkLeft + 10)
            x := wkLeft + 10
        if (y < wkTop + 10)
            y := wkTop + 10
        return {x: x, y: y}
    }

    ; 读伴生窗口此刻的**真实**外框矩形，供 Peer.Placed 广播（笔记窗口据此避让）。
    ; ⚠ 读之前要开 DetectHiddenWindows —— 伙伴刚 WinShow 出来，隐藏态下 WinGetPos 会抛错。
    ; 窗口已不在 / 尺寸为 0 时返回 ""（调用方用 IsObject 判断）。
    static RectOf(hwnd) {
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            if !WinExist("ahk_id " . hwnd)
                return ""
            WinGetPos(&x, &y, &w, &h, "ahk_id " . hwnd)
        } finally {
            DetectHiddenWindows(detectOld)
        }
        if (w > 0 && h > 0)
            return {x: x, y: y, w: w, h: h}
        return ""
    }
}


; ═══════════════════════════════════════════════════════════════════════════
;  表示层组件

; ═══════════════════════════════════════════════════════════════════════════

; ─── StatusBar：状态栏 ───
#Include modules\SevenNote\StatusBar.ahk
; ═══════════════════════════════════════════════════════════════════════════
;  FEATURE 功能层 —— 用户要做什么
;
;  按用户旅程排序：
;   ① 唤起与关闭    Alt+Z 呼出/隐藏
;   ② 输入与编辑    粘贴 / 行编辑 / 缩进 / 撤销 / 输入增强
;   ③ 保存与持久化  加载 / 保存 / 自动保存 / 时间戳
;   ④ 查看与浏览    搜索 / 字数 / 光标记忆
;   ⑤ 组织与管理    日期切换 / 搜索跳转 / 标签 / 返回当天
;   横切·美观       主题 / 字体 / 字号
; ═══════════════════════════════════════════════════════════════════════════


; ═══════════════════════════════════════════════════════════════════════════
;  ① 唤起与关闭
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Features\WindowFeature.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  ② 输入与编辑
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Features\PasteFeature.ahk


#Include modules\SevenNote\Features\LineEditFeature.ahk


#Include modules\SevenNote\Features\UndoFeature.ahk


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
        Hotkey("!c", (*) => this.Toggle(), "On")
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

; ─── Alt+X 呼出 DeepSeek 网页端 ───
; 「伴生窗口适配」契约（Peer.Preparing / Peer.Placed / Peer.Failed）的第二个使用者 ——
; 与 PowerShellFeature 同一套玩法，只把「终端」换成浏览器窗口。
; 三条广播的语义、时序、失败兜底完全一致；接入步骤见 README「开发指南」。
;
; 有三处与终端不同，值得记下：
;   ① **窗口怎么认**：终端能靠标题（"SevenNote PowerShell"）认，浏览器不能 ——
;      本机日常 Edge 里也开着 DeepSeek 网页，标题一样含 "DeepSeek"，靠标题一认就错。
;      这里改用「专用 profile → 独立进程树」的办法：窗口按 PID 认。
;   ② **尺寸与位置要自己给**：终端由 Windows Terminal 的 profile 决定落点（本机 744x1020），
;      浏览器却每次都落在 Chromium 的默认点。这里按目标尺寸摆到「和终端同一处」——
;      右侧贴工作区右缘、底边贴工作区底，于是两种伙伴产出的堆叠效果一模一样。
;   ③ **换了窗口模式就得退掉老实例**：Chromium 单实例复用会让「最先那次启动」的窗口
;      类型一直沿用到该进程结束 —— 老实例还活着时，改了命令行也照旧开出旧模式窗口。
;      详见 _RetireLegacyInstance() 与 _FindBrowserHwnd() 开头的模式校验。
class DeepSeekFeature {
    static _initialized := false
    static _url := "https://chat.deepseek.com/"

    ; 专用浏览器 profile —— 与用户日常浏览器**完全隔离**。两条理由：
    ;   ① 不往用户的收藏夹 / 历史 / 扩展里掺东西；
    ;   ② 独立 user-data-dir 会让 Chromium 起一条独立进程树，窗口才能被唯一定位。
    ; ⚠ 代价：首次要用它登录一次 DeepSeek，之后 profile 会记住。
    static _profileDir := Config.AppDataDir . "\_deepseek-profile"
    ; PID 落盘，好在「笔记程序重启」后认回已有窗口 —— 内存缓存随进程丢，文件不丢。
    static _pidFile := Config.AppDataDir . "\_deepseek.pid"

    ; 本文件启动过的实例属于哪种窗口 —— 也要落盘，理由见 _RetireLegacyInstance()：
    ; Chromium 单实例复用会让老进程继续提供它那种窗口，换了命令行也白换。
    static _windowMode := "window"
    static _modeFile := Config.AppDataDir . "\_deepseek.mode"

    static _hwnd := 0   ; 进程内缓存，省掉每次读文件

    static Init() {
        if (this._initialized)
            return
        Hotkey("!x", (*) => this.Toggle(), "On")
        this._initialized := true
    }

    static Toggle() {
        hwnd := this._FindBrowserHwnd()
        if (hwnd = 0) {
            this._Launch()
            return
        }

        ; ⚠ 必须同时看「可见」：WinHide 之后 GetForegroundWindow 仍指着那个隐藏窗口
        ;   （本机实测 1.2s 后依然如此），只看 WinActive 会判定成「在前台 → 再藏一次」，
        ;   于是按了没反应、再也呼不出来。
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

    ; 认回自己的窗口，两级兜底：进程内缓存 → PID 文件 → 没有（那就重新拉起）
    static _FindBrowserHwnd() {
        ; ⚠ 模式校验必须放在最前：老版本（--app 时代）留下的实例还活着时，认回它只会
        ;   得到应用窗口（无标签栏）。宁可当成「没有窗口」，让 Toggle() 转去 _Launch()
        ;   把老实例退掉、按新模式重开。
        if (this._ReadMode() != this._windowMode)
            return 0
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            if (this._hwnd && WinExist("ahk_id " . this._hwnd)
                && WinGetClass("ahk_id " . this._hwnd) = "Chrome_WidgetWin_1")
                return this._hwnd
            this._hwnd := 0

            pid := this._ReadPid()
            if (pid > 0) {
                hwnd := this._TopWindowOf(pid, true)
                if hwnd {
                    this._hwnd := hwnd
                    return hwnd
                }
            }
        } finally {
            DetectHiddenWindows(detectOld)
        }
        return 0
    }

    ; 取某进程「属于我们的那扇窗」。
    ; Chromium 一个实例会带一串窗口：Chrome_WidgetWin_0 的辅助窗、IME、
    ; Base_PowerMessageWindow…（本机实测一个实例 5 个），界面本身是 Chrome_WidgetWin_1。
    ;
    ; ⚠ 不能只看 class + 可见：`fallback` 那一支是必须的。窗口被 WinHide 藏着时它
    ;   依然是我们自己那扇窗 —— 重启程序后靠 pid 文件认回隐藏窗口就是此场景；
    ;   若要求可见，会认不回、于是又拉起一个新窗口，越按越多。
    ; ⚠ 可见性只用来「挑」：一个进程可能同时有多个 Chrome_WidgetWin_1（本机实测同一个
    ;   实例里两个），优先拿可见的那个，都没可见才退回第一个。
    static _TopWindowOf(pid, relax := false) {
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        fallback := 0        ; 第一扇「不可见」的候选（认回被藏起来的窗口用）
        visibleAny := 0      ; 第一扇「可见」的候选（尺寸对不上时的退路）
        tw := PeerLayoutService.TargetW(), th := PeerLayoutService.TargetH()
        try {
            for h in WinGetList("ahk_exe " . this._ExeName()) {
                if (WinGetPID("ahk_id " . h) != pid)
                    continue
                if (WinGetClass("ahk_id " . h) != "Chrome_WidgetWin_1")
                    continue
                if !DllCall("IsWindowVisible", "ptr", h, "int") {
                    if !fallback
                        fallback := h
                    continue
                }
                ; 同一个 profile 可能同时开着好几扇窗（用户在窗口里又开了窗、或 Edge 恢复了
                ; 上次的窗口 —— 实测第二次带 --new-window 启动后同 PID 下有 3 扇），
                ; 于是「第一个可见的」未必是我们摆过的那扇，认哪扇全看枚举顺序。
                ; 我们的窗口由 _CheckSize 反复校正成目标尺寸，用户手开的通常对不上 ——
                ; 用尺寸把它挑出来。
                ; ⚠ 尺寸是异步校正的：刚启动那一刻还没摆到位，所以这里只是「优先」，
                ;   没命中就退回第一个可见窗口，绝不会因为量不准而认不回窗口。
                WinGetPos(, , &aw, &ah, "ahk_id " . h)
                if (aw = tw && ah = th)
                    return h
                if !visibleAny
                    visibleAny := h
            }
        } finally {
            DetectHiddenWindows(detectOld)
        }
        if (visibleAny != 0)
            return visibleAny
        return relax ? fallback : 0
    }

    static _ReadPid() {
        try {
            v := Trim(FileRead(this._pidFile, "UTF-8"))
            return IsNumber(v) ? Integer(v) : 0
        } catch {
            return 0
        }
    }

    static _WritePid(pid) {
        try {
            FileDelete(this._pidFile)
        } catch {
        }
        try {
            FileAppend(pid, this._pidFile, "UTF-8")
        } catch {
        }
    }

    static _ReadMode() {
        try
            return Trim(FileRead(this._modeFile, "UTF-8"))
        catch
            return ""
    }

    static _WriteMode(mode) {
        try {
            FileDelete(this._modeFile)
        } catch {
        }
        try {
            FileAppend(mode, this._modeFile, "UTF-8")
        } catch {
        }
    }

    ; 退掉「窗口模式不对」的残留实例，让本次 --new-window 真正生效。
    ;
    ; 背景：Chromium 是**单实例**的 —— 只要那个 profile 进程还活着，后到的命令行就只被
    ; 当成「在已有实例里开个地址」，窗口类型仍由**最先那次启动**决定。实测从 --app 时代
    ; 升级上来后，那个进程一直活着（用户只是关了窗口、没退进程），于是改了命令行也照旧
    ; 开出应用窗口 —— 认窗逻辑再对，窗口类型还是错的。
    ;
    ; 判据用落盘的 _modeFile：写的是 "window" 就说明实例是本版启动的，直接放行；文件
    ; 缺失或内容不符 = 老版本留下的实例，退掉重开。所以这是**升级路径上的一次性清理**，
    ; 正常运行时一次都不会动手。
    static _RetireLegacyInstance() {
        if (this._ReadMode() = this._windowMode)
            return
        pids := this._ProfilePids()
        if (pids.Length) {
            ; 先礼后兵：先对有窗口的那个发 WM_CLOSE，让 Chromium 正常收尾（会话与标签都保住）。
            pid := this._ReadPid()
            if (pid && ProcessExist(pid)) {
                hwnd := this._TopWindowOf(pid, true)
                if (hwnd)
                    try WinClose("ahk_id " . hwnd)
            }
            deadline := A_TickCount + 1200
            while (A_TickCount < deadline && this._AnyAlive(pids))
                Sleep(60)
            for p in pids {
                if (ProcessExist(p))
                    try ProcessClose(p)
            }
            ; 等它们把 profile 的锁放掉，否则紧接着那次启动会被判成「已有实例」又并进去。
            Sleep(300)
        }
        this._WriteMode(this._windowMode)
    }

    ; 占用专用 profile 的全部活进程。
    ;
    ; ⚠ 不能只信 _deepseek.pid：它可能落后（上次没认回窗口就没写）或指向已退出的进程（PID
    ;   还可能被复用给别人），那样都会漏掉真正占着 profile 的那个实例 —— 它一活着，本次
    ;   启动就注定被并进去、窗口模式照旧。所以再按命令行里的 profile 路径全库筛一遍。
    ;   WMI 拿不到（异常 / 被策略挡住）时退回「只认 pid 文件那一个」，功能不因此失效。
    static _ProfilePids() {
        out := []
        seen := Map()
        pid := this._ReadPid()
        ; ⚠ 校验进程名：PID 会被复用，光看「存在」可能杀到不相干的程序。
        if (pid && ProcessExist(pid) && ProcessGetName(pid) = this._ExeName()) {
            seen[pid] := true
            out.Push(pid)
        }
        try {
            wmi := ComObjGet("winmgmts:")
            q := "SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name='"
                . this._ExeName() . "'"
            for proc in wmi.ExecQuery(q) {
                cmd := proc.CommandLine
                if (IsObject(cmd) || cmd = "")       ; 跨权限的进程读不到命令行，跳过
                    continue
                if !InStr(cmd, this._profileDir)     ; 认 profile 路径，不认进程名
                    continue
                p := proc.ProcessId + 0
                if seen.Has(p)
                    continue
                seen[p] := true
                out.Push(p)
            }
        } catch {
        }
        return out
    }

    static _AnyAlive(pids) {
        for p in pids {
            if (ProcessExist(p))
                return true
        }
        return false
    }

    static _Launch() {
        exe := this._BrowserPath()
        if (exe = "") {
            MsgBox("未找到可用的 Chromium 系浏览器（Edge / Chrome）。`n"
                . "可在 _config.ini 的 [Paths] BrowserPath 指定浏览器路径。"
                , "SevenNote", "Icon!")
            return
        }

        ; 确定要启动了，才让笔记窗口退场 —— 上面那条早退分支不能白收一次。
        EventBus.Emit("Peer.Preparing")

        ; ⚠ 升级路径上的一次性清理：老实例（--app 时代的进程）还活着就先退掉它，
        ;   否则本次 --new-window 会被 Chromium 的单实例复用吃掉，照旧开出应用窗口。
        this._RetireLegacyInstance()

        ; 启动前先记下现有的同族 PID，之后「新出现的那个」就是我们的 ——
        ; 专用 profile 保证了它必定是条新进程树，不会并进用户自己的浏览器里。
        before := this._PidSnapshot()

        try {
            ; ⚠ --window-size 收的是**逻辑像素**（DIP），而 WinMove / WinGetPos 认物理像素。
            ;   本机 150% 缩放（A_ScreenDPI = 144）下传 513x680，实际得到 772x1020 —— 正合目标。
            ;   换个缩放比例就得跟着变，所以按 A_ScreenDPI 反算，别写死。
            ; ⚠ 宽度再减 2：Edge 把内容区尺寸套到窗口外框时会替自己补两像素调整边框 ——
            ;   本机实测请求 770（物理）时外框落在 772，而终端是 770，两者左右边缘就差这
            ;   2px。请求值先扣掉它，外框才与终端严格等宽（高度实测不差，不用减）。
            ;   真机上若换版本后仍差，以 WinGetPos 量到的**外框**为准调这个常量 ——
            ;   别去猜那圈边框算几像素（随系统版本与缩放而变）。
            w := (PeerLayoutService.TargetW() - 2) * 96 // A_ScreenDPI
            h := PeerLayoutService.TargetH() * 96 // A_ScreenDPI
            ; --new-window：开一扇**普通浏览器窗口**（有标签栏与完整工具栏），窗口内可直接浏览网页。
            ;       早先走 --app=<url> 开「应用窗口」求桌面应用观感，实测不划算 —— Edge 155 起
            ;       app 窗口照样自带地址栏（UIA 查到 view_1017「地址和搜索栏」），却没有标签栏：
            ;       既不像应用，也算不上好用的浏览器。改普通窗口后能自己开新标签 / 前进后退。
            ;       ⚠ 认窗逻辑不受影响：仍是「专用 profile → 独立进程树 → 按 PID 认窗」，
            ;       普通窗口的 class 同样是 Chrome_WidgetWin_1，`_TopWindowOf` 照样认得出。
            ;       标题归页面管（形如 "DeepSeek - Microsoft Edge"），别拿标题找它。
            ; --user-data-dir：独立 profile（理由见类头）。
            ; --no-first-run / --no-default-browser-check：跳过首次运行的欢迎页与
            ;       「是否设为默认浏览器」的询问 —— 新 profile 每次都问，很烦。
            cmd := '"' . exe . '" --new-window ' . this._url
                . ' --user-data-dir="' . this._profileDir . '"'
                . ' --window-size=' . w . ',' . h
                . ' --no-first-run --no-default-browser-check'
            Run(cmd)
        } catch as err {
            MsgBox("启动浏览器失败：`n" . err.Message, "SevenNote", "Icon!")
            EventBus.Emit("Peer.Failed")
            return
        }

        ; 浏览器冷启动比终端快（本机实测起进程 ~0.1s、窗口到位 ~0.9s），但仍要轮询：
        ; 抢在窗口出现前 WinShow 会报「窗口不存在」。
        deadline := A_TickCount + 15000
        relaxAt := A_TickCount + 3000      ; 3 秒后仍没找到，就连「还没显示」的窗口也算（放宽）
        ; 上一轮认过的 profile 进程。Chromium 是**单实例**的：若它还活着（用户只关了窗口、
        ; 没退进程 —— 普通窗口模式下这是常态），这次启动根本不会产生新进程，
        ; `_NewPidsSince` 永远为空，只认新 PID 就会一路超时弹「找不到窗口」。
        knownPid := this._ReadPid()
        while (A_TickCount < deadline) {
            relax := A_TickCount >= relaxAt
            for pid in this._NewPidsSince(before) {
                hwnd := this._TopWindowOf(pid, relax)
                if (hwnd != 0) {
                    this._WritePid(pid)
                    this._hwnd := hwnd
                    this._ShowAndFocus(hwnd)
                    return
                }
            }
            ; 老进程仍在 → 它多半只是新开了扇窗（--new-window 保证了这一点），按老 PID 认。
            ; ⚠ 只在「认回」这一支放宽：平时要求窗口可见，免得把别处残留的隐藏窗当成目标。
            if (knownPid && ProcessExist(knownPid)) {
                hwnd := this._TopWindowOf(knownPid, relax)
                if (hwnd != 0) {
                    this._hwnd := hwnd
                    this._ShowAndFocus(hwnd)
                    return
                }
            }
            Sleep(20)
        }

        MsgBox("浏览器已启动，但未能找到它的窗口。", "SevenNote", "Icon!")
        EventBus.Emit("Peer.Failed")
    }

    ; 当前同族进程的 PID 集合（含只有隐藏窗口的宿主进程）
    static _PidSnapshot() {
        s := Map()
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            for h in WinGetList("ahk_exe " . this._ExeName())
                try s[WinGetPID("ahk_id " . h)] := true
        } finally {
            DetectHiddenWindows(detectOld)
        }
        return s
    }

    ; 启动后「新出现、且已经有窗口」的全部 pid。
    ;
    ; ⚠ 返回**全集**而不是「第一个」，这是本功能的关键：用户自己的浏览器一直在跑，
    ;   随时会冒出新的渲染进程（它们没有 Chrome_WidgetWin_1 窗，永远匹配不上）。
    ;   只返回第一个的话，一旦它排在真正那个前面，就会整段超时卡死到「找不到窗口」——
    ;   本机实测：新进程 22072 挡住真正的 23064，连卡 8 秒。全集逐个过就没有这个问题。
    static _NewPidsSince(before) {
        out := []
        for pid, _ in this._PidSnapshot() {
            if !before.Has(pid)
                out.Push(pid)
        }
        return out
    }

    static _ShowAndFocus(hwnd) {
        ; 让笔记窗口先退场 —— 它接下来要换位置换尺寸，这一整段不该被看见。
        ; 理由详见 WindowFeature._CollapseForPeer。重复发是无害的：已收起时那次会跳过。
        ; ⚠ 这条广播管的是笔记窗口，不是浏览器：浏览器的露面时机由它自己的宿主掌握。
        EventBus.Emit("Peer.Preparing")
        WinShow("ahk_id " . hwnd)
        ; ⚠ WinShow 之后必须再 WinRestore：Chromium 的窗口被 WinHide 藏起来后会把自己
        ;   标记成「最小化」—— 本机实测再按 Alt+X 呼出时 iconic=1、rect 停在
        ;   -32000,-32000 237x39 的停放位，而 WinShow 不解除最小化，于是「窗口没回来」。
        WinRestore("ahk_id " . hwnd)
        WinActivate("ahk_id " . hwnd)
        try {
            WinSetAlwaysOnTop("On", "ahk_id " . hwnd)
        }
        ; 浏览器自己不记位置，每次都在 Chromium 的默认点，所以摆到「和终端同一处」。
        this._PlaceLikeTerminal(hwnd)
        ; 把实际落点广播出去，由笔记窗口（WindowFeature）据此避让 —— 谁被动谁适配。
        this._BroadcastRect(hwnd)

        ; 广播是同步的（EventBus 直接循环调用 handler），所以上一行返回时笔记窗口已经
        ; 露面了 —— 而 Show() 末尾会激活窗口自身，把前台从刚呼出的浏览器手里夺走。
        ; 按 Alt+X 是要用 DeepSeek，这里还回去。
        WinActivate("ahk_id " . hwnd)
    }

    ; 摆到「和 PowerShell 终端同一处」：右侧贴工作区右缘（离缘 Config.PlaceRight）、
    ; 底边贴工作区底。「可摆性闸」与落点算式都在 PeerLayoutService 里。
    ; ⚠ 全程 WinMove（物理像素），别混用 Gui.Move（它收逻辑单位、还会再乘一次 DPI）。
    static _PlaceLikeTerminal(hwnd) {
        this._PlaceTarget(hwnd)
        this._WatchSize(hwnd, 0)
    }

    ; 按目标尺寸摆到「和终端同一处」（右侧贴工作区右缘、底边贴工作区底）。
    ; 终端那边只挪位置、尺寸归 Windows Terminal 的 profile，这边位置尺寸一起定。
    static _PlaceTarget(hwnd) {
        ; ⚠ 隐藏 / 最小化的窗口一律不摆 —— 本函数有两个调用来源，其中 _CheckSize 是
        ;   **异步定时器**（350 / 950 / 1550 / 2150ms），等它跑起来时用户很可能已经
        ;   连按一次 Alt+X 把窗口藏了。闸的实现与实测账见 PeerLayoutService.IsPlaceable。
        if !PeerLayoutService.IsPlaceable(hwnd)
            return
        w := PeerLayoutService.TargetW(), h := PeerLayoutService.TargetH()
        rect := PeerLayoutService.CornerRect(w, h)
        WinMove(rect.x, rect.y, w, h, "ahk_id " . hwnd)
    }

    ; ─── 尺寸复核：Edge 会在窗口露面之后重新套用它自己的 --window-size ───
    ; ⚠ `--window-size` 说的是**内容区**，Edge 套到窗口外框上还要再补一圈调整边框 ——
    ;   本机实测请求 770 的外框最后落在 768，而终端恰是 770x1020：两个伙伴左右边缘
    ;   错开两个像素，就是「终端和 DeepSeek 没对齐」。
    ;   实测（probe：WinMove 到 770 后每 500ms 量一次）证明它**不是**持续校正 ——
    ;   稳定窗口上 770 一直保持。它会重新套用，是在窗口被 show/restore **之后**；
    ;   而那个时刻晚于第一次 350ms 复核，只核一次必然漏掉。故在 350 / 950 / 1550 /
    ;   2150ms 四处各核一次，量到与目标不符就按目标重摆。单次开销只是一次 WinGetPos。
    ;   ⚠ 不去猜那圈边框有几像素（随系统版本与缩放变），也不跟 Edge 抢时序 ——
    ;     只事后核对，以实际外框为准。
    static _WatchSize(hwnd, round) {
        if (round > 3)
            return
        delay := (round = 0) ? 350 : 600
        SetTimer(() => this._CheckSize(hwnd, round), -delay)
    }

    static _CheckSize(hwnd, round) {
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            if !WinExist("ahk_id " . hwnd)
                return
            ; 窗口已被用户藏起来（连按两次 Alt+X）= 用户不想看见它，别再管它的尺寸：
            ; 直接返回，也不再排下一轮复核 —— 否则会反复去重摆一个看不见的窗口，
            ; 而 WinMove 对隐藏窗口会抛 "Target window not found"（实测卡死脚本）。
            if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
                return
            ; 最小化的窗口量不出尺寸（读数是停放位的垃圾值），别据此重摆
            if DllCall("IsIconic", "ptr", hwnd, "int")
                return
            WinGetPos(, , &aw, &ah, "ahk_id " . hwnd)
        } finally {
            DetectHiddenWindows(detectOld)
        }
        if (aw != PeerLayoutService.TargetW() || ah != PeerLayoutService.TargetH())
            this._PlaceTarget(hwnd)
        this._WatchSize(hwnd, round + 1)
    }

    ; 广播伙伴窗口此刻的实际位置与尺寸，供笔记窗口让位（Peer.Placed 契约）。
    ; 读矩形的细节见 PeerLayoutService.RectOf。
    static _BroadcastRect(hwnd) {
        rect := PeerLayoutService.RectOf(hwnd)
        if !IsObject(rect)
            return
        EventBus.Emit("Peer.Placed", {hwnd: hwnd, x: rect.x, y: rect.y, w: rect.w, h: rect.h})
    }

    ; 浏览器：优先 _config.ini 指定；否则按 Edge → Chrome 顺序探测（Windows 自带 Edge，
    ; 命中率最高）。只要是 Chromium 系（支持 --new-window / --user-data-dir）都能用。
    static _BrowserPath() {
        p := ConfigService.Read("Paths", "BrowserPath")
        if (p != "" && FileExist(p))
            return p
        for candidate in [
            A_ProgramFiles . "\Microsoft\Edge\Application\msedge.exe",
            EnvGet("ProgramFiles(x86)") . "\Microsoft\Edge\Application\msedge.exe",
            A_ProgramFiles . "\Google\Chrome\Application\chrome.exe",
            EnvGet("ProgramFiles(x86)") . "\Google\Chrome\Application\chrome.exe",
            EnvGet("LOCALAPPDATA") . "\Google\Chrome\Application\chrome.exe",
        ] {
            if FileExist(candidate)
                return candidate
        }
        return ""
    }

    ; 进程名（WinGetList 的 ahk_exe 参数用）—— 跟着上面选中的浏览器走，
    ; 免得用户把 BrowserPath 改成 Chrome 后这里还在找 msedge.exe。
    static _ExeName() {
        p := this._BrowserPath()
        if (p = "")
            return "msedge.exe"
        SplitPath(p, &name)
        return name
    }
}



class CapsLockFeature {
    static _enabled := false
    static _loading := false

    static Enable() {
        if this._enabled
            return
        Hotkey("CapsLock", (*) => 0, "On")
        Hotkey("CapsLock & h", (*) => Send("{Left}"), "On")
        Hotkey("CapsLock & j", (*) => Send("{Down}"), "On")
        Hotkey("CapsLock & k", (*) => Send("{Up}"), "On")
        Hotkey("CapsLock & l", (*) => Send("{Right}"), "On")
        this._enabled := true
        if !this._loading
            this.SaveToConfig()
    }

    static Disable() {
        if !this._enabled
            return
        Hotkey("CapsLock", "Off")
        Hotkey("CapsLock & h", "Off")
        Hotkey("CapsLock & j", "Off")
        Hotkey("CapsLock & k", "Off")
        Hotkey("CapsLock & l", "Off")
        this._enabled := false
        if !this._loading
            this.SaveToConfig()
    }

    static Toggle() {
        if this._enabled {
            this.Disable()
            EventBus.Emit("CapsLock.Toggled"
                , {msg: "✗ 键盘映射已关闭", state: false})
        } else {
            this.Enable()
            EventBus.Emit("CapsLock.Toggled"
                , {msg: "✓ 键盘映射已开启", state: true})
        }
    }

    static SaveToConfig() {
        ConfigService.Write("Input", "CapsLockMap", this._enabled ? 1 : 0)
    }

    static LoadFromConfig() {
        this._loading := true
        v := ConfigService.ReadInt("Input", "CapsLockMap", 0)
        if (v = 1)
            this.Enable()
        else
            this.Disable()
        this._loading := false
    }
}


; ═══════════════════════════════════════════════════════════════════════════
;  ③ 保存与持久化
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Features\LoadFeature.ahk


#Include modules\SevenNote\Features\SaveFeature.ahk


#Include modules\SevenNote\Features\AutoSaveFeature.ahk


; ⚠ 时间戳**一律手动**（v2.4 起）：只在用户按下 Ctrl+T 时插入，程序任何时候都不自作主张。
;   原先的两条自动路径已删除 ——
;     · 启动时 CheckAndAppend()：无戳就塞一个；
;     · 切日期时同一函数：距上一戳 ≥ Config.TimestampInterval（60 分钟）再补一个。
;   它们会在用户只想随手记两笔时也往笔记里加时间戳，还得靠「保存前剥掉空戳」来兜底。
;   现在连带 StripIfEmpty 一起去掉：用户手动加的戳就是他想要的，程序不擅自删。
;   想恢复自动：在组合根按需调 TimestampFeature.Append()，或把 CheckAndAppend 加回来。
#Include modules\SevenNote\Features\TimestampFeature.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  ④ 查看与浏览
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Features\SearchFeature.ahk


#Include modules\SevenNote\Features\StatFeature.ahk


#Include modules\SevenNote\Features\CaretFeature.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  ⑤ 组织与管理
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Features\DateSwitchFeature.ahk


#Include modules\SevenNote\Features\DateJumpFeature.ahk


#Include modules\SevenNote\Features\TitleFeature.ahk


#Include modules\SevenNote\Features\GoTodayFeature.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  横切 · 美观
; ═══════════════════════════════════════════════════════════════════════════

#Include modules\SevenNote\Features\ThemeFeature.ahk


#Include modules\SevenNote\Features\FontFeature.ahk


; ─── BackdropFeature：带背景图的主题（星空）───
; 背景图不是「全局贴一张」，而是主题自带的属性：ThemeService.Themes 里带 bg 字段的
; 主题（目前只有「星空」）才铺图，切到别的主题自动撤掉、回到纯底色。
; 文字浮在图上、图铺满整个编辑区（终端式，非相框式）。
#Include modules\SevenNote\Features\BackdropFeature.ahk
#Include modules\SevenNote\SevenNoteModule.ahk


; ═══════════════════════════════════════════════════════════════════════════
;  组合根 —— 装配 + 启动
; ═══════════════════════════════════════════════════════════════════════════

; ═══ 全局异常兜底 ═══
; AHK v2 对未捕获异常默认是**弹模态框**：框一弹脚本就停摆（热键全无反应、框还挂在
; 屏幕上），只能手动杀进程 —— 项目在 v2 迁移期踩过三次（见 .clinerules/03）。
; 这里改成「写日志 + 继续跑」：单个 Feature 出错不该拖垮整个程序。
; 注册点放在这里（而不是文件更早处）是因为 LogError 要先建日志目录
; （开发版项目根 .logs\、编译版 %AppData%\SevenNote-Dev\），
; 而其中的 AppData 目录就在下面几行才建。
OnError(OnScriptError)

; AHK 的异常回调。返回 **1** = 已处理，不弹默认错误框（返回 0 就会弹）。
; ⚠ 回调自身绝不能抛异常 —— 会递归回到这里，所以全程 try，见 LogError。
OnScriptError(err, mode) {
    stack := err.HasProp("Stack") ? err.Stack : ""
    LogError(mode . "  " . err.Message
        . "`n      文件  " . err.File . "   行  " . err.Line
        . (Trim(stack) != ""
            ? "`n      调用栈：`n      " . StrReplace(Trim(stack, "`n"), "`n", "`n      ")
            : ""))
    return 1
}

; 追加一条到日志（落点见 Config.LogPath：开发版 .logs\_error.log，
; 编译版 %AppData%\SevenNote-Dev\_error.log）。
; 超 512 KB 就轮转（删掉重来）—— 日志只用来事后定位，不归档。
LogError(msg) {
    entry := "── " . FormatTime(, "yyyy-MM-dd HH:mm:ss") . " ──`r`n" . msg . "`r`n`r`n"
    try {
        logPath := Config.LogPath
        DirCreate(Config.LogDir)      ; 启动极早期出错时，这个目录可能还没建
        if (FileExist(logPath) && FileGetSize(logPath) > 524288)
            FileDelete(logPath)
        FileAppend(entry, logPath, "UTF-8")
    } catch {
        ; 项目目录只读 / 被占用时退回 AppData —— 日志丢一次就白查了
        try {
            fallbackDir := A_AppData . "\SevenNote-Dev"
            DirCreate(fallbackDir)
            FileAppend(entry, fallbackDir . "\_error.log", "UTF-8")
        }
    }
}

; ═══ 确保 AppData 目录存在 ═══
DirCreate(Config.AppDataDir)

; ═══ 打包 pandoc.exe（v1.9 修复）═══
; 【关键修复】
;   · FileInstall 必须一行，不能折行（否则 Ahk2Exe 可能打包空文件）
;   · 第二参数用展开的表达式，不用类属性
;   · 释放前先删旧文件（避免 0KB 坏文件阻塞后续释放）
;   · 只在文件不存在或 < 1MB 时才释放
; ⚠ 编译前把下面的源路径改成你本机 pandoc.exe 的实际路径
; ⚠ 编译时务必确认源文件是 100+ MB 的 x86_64 版 pandoc
if !FileExist(A_AppData . "\SevenNote\pandoc.exe") || FileGetSize(A_AppData . "\SevenNote\pandoc.exe") < 1048576 {
    try FileDelete(A_AppData . "\SevenNote\pandoc.exe")
    FileInstall "C:\Users\Seven\AppData\Local\Pandoc\pandoc.exe", A_AppData . "\SevenNote\pandoc.exe", 1
}

; ═══ 加载 RichEdit 控件库 ═══
DllCall("LoadLibrary", "str", "msftedit.dll", "ptr")

; ═══ 配置服务初始化 ═══
ConfigService.Init(Config.ConfigPath)
ConfigService.SetDefault("Appearance", "ThemeIndex", "1")
; 主题表「结构版本」：主题表精简 / 重排过就 +1，ThemeService._MigrateIndex 据此只跑一次下标迁移
ConfigService.SetDefault("Appearance", "ThemeSchema", "1")
ConfigService.SetDefault("Appearance", "FontIndex", "1")
ConfigService.SetDefault("Appearance", "FontSizeIndex", "2")
; 背景图不再有全局键：图与浓淡都写在主题自己的 bg / bgAlpha 上（见 ThemeService.Themes）
ConfigService.SetDefault("Input", "CapsLockMap", "0")
ConfigService.SetDefault("Paths", "Vault", "")

; ═══ 首次运行：引导用户选择笔记目录 ═══
EnsureVaultConfigured()

; ═══ 确保笔记目录存在 ═══
DirCreate(Config.GetVault())

; ═══ 笔记模块（Phase 2：GUI 与 Feature 挂载已搬入 modules/SevenNote）═══
SevenNoteModule.Init()

; ═══ 热键（数据驱动：注册与帮助共用同一张表）═══
HotkeyRouter.RegisterAll(HotkeyTable(), SevenNoteModule.GetContexts())

; ═══ 启动 ═══
SevenNoteModule.Start()

ShowStartupTip()


; ═══════════════════════════════════════════════════════════════════════════
;  首次运行引导
; ═══════════════════════════════════════════════════════════════════════════

EnsureVaultConfigured() {
    vault := ConfigService.Read("Paths", "Vault")
    if (vault != "" && DirExist(vault))
        return

    defaultPath := A_MyDocuments . "\SevenNote"
    if (vault != "")
        defaultPath := vault

    selected := DirSelect(defaultPath, 0
        , Config.AppName . " 首次运行`n`n请选择笔记存储目录：")
    if (selected = "")
        selected := defaultPath

    DirCreate(selected)
    Config.SetVault(selected)
}


; ═══════════════════════════════════════════════════════════════════════════
;  启动提示
; ═══════════════════════════════════════════════════════════════════════════

ShowStartupTip() {
    tip := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "提示")
    tip.SetFont("s14", "楷体")
    tip.BackColor := "E4E9EE"
    tip.AddText("x20 y20 w200 Center c3D5166", Config.AppName . " 已启动！Alt+Z 呼出")
    tipY := A_ScreenHeight * 0.65
    tip.Show("w240 h80 y" . tipY)
    ; ⚠ 1.5 秒内用户可能自己把这扇提示窗关掉 —— 再 Destroy() 一次会抛异常，
    ;   而 SetTimer 回调没有外层 try，异常即弹模态框（见 .clinerules/03）。
    SetTimer(() => DestroyTipWindow(tip), -1500)
}

; 关掉启动提示。已经关过就算了 —— 这正是 try 的用途。
DestroyTipWindow(tip) {
    try tip.Destroy()
}


; ═══════════════════════════════════════════════════════════════════════════
;  热键表（注册 + 帮助的唯一数据源）
; ═══════════════════════════════════════════════════════════════════════════
; 每条热键只在这里定义一次：HotkeyRouter 用它注册，BuildHotkeyHelpText()
; 用它渲染 Alt+H 帮助 —— 改一条热键不必再去 ShowHelp 里手工同步那行文本。
;   ctx   : 注册上下文 —— "global" 全局 / "editor" 编辑器内 / "search" 搜索栏显示时
;   key   : AHK 热键字符串（$ 前缀 = 走钩子，照原样保留）；
;           留空表示该热键由 Feature 自己注册，本表只负责帮助文本
;   fn    : 触发时调用的回调（key 为空时不必写）
;   group : 帮助窗口里的分组（纯语义分类，与 ctx 无关）
;   line  : 帮助窗口里的那一行（含前导空格，逐字符照抄旧文本）
;   note  : 该行之后追加的说明行（可省略）
HotkeyTable() {
    return [
        ; ── 【窗口】──
        {ctx: "global", key: "!z", group: "窗口", line: "   Alt+Z            呼出 / 隐藏"
            , fn: (*) => WindowFeature.Toggle()},
        {ctx: "global", key: "!+z", group: "窗口", line: "   Alt+Shift+Z      保存并退出"
            , fn: (*) => (SaveFeature.Save(), ExitApp())},
        {ctx: "global", key: "!h", group: "窗口", line: "   Alt+H            显示本帮助"
            , fn: (*) => ShowHelp()},

        ; ── 【外观】──
        {ctx: "global", key: "!t", group: "外观", line: "   Alt+T            切换主题（含带背景图的「星空 / 金克斯」）"
            , fn: (*) => ThemeFeature.Next()},
        {ctx: "global", key: "!+t", group: "外观", line: "   Shift+Alt+T      切换字体"
            , fn: (*) => FontFeature.NextFont()},
        {ctx: "global", key: "!=", group: "外观", line: "   Alt+=            调大字号"
            , fn: (*) => FontFeature.BiggerSize()},
        {ctx: "global", key: "!-", group: "外观", line: "   Alt+-            调小字号"
            , note: "                      （外观设置自动保存）"
            , fn: (*) => FontFeature.SmallerSize()},

        ; ── 【输入增强】──
        {ctx: "global", key: "!+c", group: "输入增强", line: "   Alt+Shift+C      切换 CapsLock 键盘映射"
            , note: "                      （开启后 CapsLock+H/J/K/L = 方向键）"
            , fn: (*) => CapsLockFeature.Toggle()},
        ; 下面两条由 Feature 自己注册（外部窗口存在时才挂），本表只提供帮助文本：
        ;   Alt+C → PowerShellFeature（Init 里 Hotkey("!c")）
        ;   Alt+X → DeepSeekFeature   （Init 里 Hotkey("!x")）
        {ctx: "", key: "", group: "输入增强", line: "   Alt+C            唤出 / 隐藏 PowerShell（笔记自动让位）"},
        {ctx: "", key: "", group: "输入增强", line: "   Alt+X            呼出 / 隐藏 DeepSeek 网页（笔记自动让位）"},

        ; ── 【搜索】──
        {ctx: "editor", key: "$^f", group: "搜索", line: "   Ctrl+F           打开搜索栏"
            , fn: (*) => SearchFeature.Show()},
        {ctx: "search", key: "Enter", group: "搜索", line: "   Enter            下一个匹配"
            , fn: (*) => SearchFeature.Next()},
        {ctx: "search", key: "+Enter", group: "搜索", line: "   Shift+Enter      上一个匹配"
            , fn: (*) => SearchFeature.Prev()},
        {ctx: "search", key: "Esc", group: "搜索", line: "   Esc              关闭搜索栏"
            , fn: (*) => SearchFeature.Hide()},

        ; ── 【保存】──
        {ctx: "editor", key: "$^s", group: "保存", line: "   Ctrl+S           手动保存"
            , fn: (*) => SaveFeature.Save()},

        ; ── 【日期与标签】──
        {ctx: "global", key: "!Up", group: "日期与标签", line: "   Alt+↑            前一天"
            , fn: (*) => DateSwitchFeature.Switch(-1)},
        {ctx: "global", key: "!Down", group: "日期与标签", line: "   Alt+↓            后一天"
            , fn: (*) => DateSwitchFeature.Switch(1)},
        {ctx: "global", key: "!Home", group: "日期与标签", line: "   Alt+Home         回到今天"
            , fn: (*) => GoTodayFeature.Go()},
        {ctx: "editor", key: "$^g", group: "日期与标签", line: "   Ctrl+G           搜索跳转（日期 / 标签）"
            , fn: (*) => DateJumpFeature.ShowDialog()},
        {ctx: "editor", key: "$^+t", group: "日期与标签", line: "   Ctrl+Shift+T     为当前日期设置标签"
            , fn: (*) => TitleFeature.ShowDialog()},
        ; ── 【编辑】──
        {ctx: "editor", key: "$^z", group: "编辑", line: "   Ctrl+Z           撤销"
            , fn: (*) => UndoFeature.Undo()},
        {ctx: "editor", key: "$^+z", group: "编辑", line: "   Ctrl+Shift+Z     重做"
            , fn: (*) => UndoFeature.Redo()},
        {ctx: "editor", key: "$^y", group: "编辑", line: "   Ctrl+Y           删除当前行"
            , fn: (*) => LineEditFeature.DeleteLine()},
        {ctx: "editor", key: "$^d", group: "编辑", line: "   Ctrl+D           复制当前行到下方"
            , fn: (*) => LineEditFeature.DuplicateLine()},
        {ctx: "editor", key: "$^+Up", group: "编辑", line: "   Ctrl+Shift+↑     上移当前行"
            , fn: (*) => LineEditFeature.MoveUp()},
        {ctx: "editor", key: "$^+Down", group: "编辑", line: "   Ctrl+Shift+↓     下移当前行"
            , fn: (*) => LineEditFeature.MoveDown()},
        {ctx: "editor", key: "Tab", group: "编辑", line: "   Tab              增加缩进（4 空格）"
            , fn: (*) => LineEditFeature.Indent()},
        {ctx: "editor", key: "+Tab", group: "编辑", line: "   Shift+Tab        减少缩进"
            , fn: (*) => LineEditFeature.Outdent()},
        {ctx: "editor", key: "$^+v", group: "编辑", line: "   Ctrl+Shift+V     粘贴为纯文本"
            , fn: (*) => PasteFeature.PastePlain()},

        ; ── 【分段】──
        {ctx: "editor", key: "$^t", group: "分段", line: "   Ctrl+T           追加时间戳"
            , fn: (*) => TimestampFeature.Append()},
        {ctx: "editor", key: "$^h", group: "分段", line: "   Ctrl+H           插入分隔线"
            , fn: (*) => TimestampFeature.Separator()},
        {ctx: "editor", key: "$^+h", group: "分段", line: "   Ctrl+Shift+H     插入 ## 分段标题"
            , fn: (*) => TimestampFeature.Heading()}
    ]
}

; 注册由 WorkBench/HotkeyRouter.ahk 负责（Phase 1 起；本文件只保留热键表）。

; 帮助窗口正文 —— 按【组】走，组内按表序；组间空行，结尾附版本与笔记目录。
BuildHotkeyHelpText() {
    table := HotkeyTable()
    text := ""
    for g in ["窗口", "外观", "输入增强", "搜索", "保存", "日期与标签", "编辑", "分段"] {
        text .= "【" . g . "】`n"
        for hk in table {
            if (hk.group != g)
                continue
            text .= hk.line . "`n"
            if hk.HasProp("note")
                text .= hk.note . "`n"
        }
        text .= "`n"
    }
    return text
        . "—————————————————————————`n"
        . "   " . Config.AppName . " v" . Config.Version . "`n"
        . "   当前笔记目录：`n"
        . "   " . Config.GetVault() . "`n"
        . "   按 ESC 或点关闭按钮关闭"
}


; ═══════════════════════════════════════════════════════════════════════════
;  帮助窗口（Alt+H）
; ═══════════════════════════════════════════════════════════════════════════

ShowHelp() {
    if WinExist(Config.AppName . " · 快捷键 ahk_class AutoHotkeyGUI") {
        WinActivate(Config.AppName . " · 快捷键 ahk_class AutoHotkeyGUI")
        return
    }

    help := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop"
        , Config.AppName . " · 快捷键")
    help.SetFont("s11", "楷体")
    help.BackColor := "FFF8E7"

    text := BuildHotkeyHelpText()

    help.AddText("x20 y15 w400", text)
    help.Show("w440 h920")

    HotIfWinActive(Config.AppName . " · 快捷键")
    Hotkey("Esc", (*) => help.Destroy())
    HotIf()
}
