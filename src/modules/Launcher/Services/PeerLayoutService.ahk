#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  PeerLayoutService —— 伴生窗口的通用查询 + Launcher 策略
;  Phase 3 从 SevenNote.ahk 原样搬入；平台能力上收后，通用窗口状态 / 矩形查询
;  委托 WorkBench\Capabilities\Placement\WindowProbe，这里只保留 TargetW/H 与
;  Config.PlaceRight 这类 Launcher 自己的落点策略。
; ═══════════════════════════════════════════════════════════════════════════

; ─── PeerLayoutService：伴生窗口的落点与可摆性（策略 + 能力适配）───
; 终端（Alt+C）与 DeepSeek（Alt+X）必须摆到**同一处**：右缘贴工作区右缘（离缘
; Config.PlaceRight）、底边贴工作区底、宽度同为 [Paths] DeepSeekW。这份「同列同宽」
; 的算式原本在两个 Feature 里各留一份（Feature 之间不许互相调用），改一处就得记着
; 改另一处。通用几何 / 窗口查询已上收平台能力，本类只剩 Launcher 自己的策略参数。
class PeerLayoutService {
    ; 隐藏 / 最小化的窗口一律当「不能摆」，调用方直接 return。
    ; ⚠ AHK v2 默认忽略隐藏窗口 —— 对 WinHide 过的窗口做 WinGetPos / WinMove 会抛
    ;   "Target window not found"，而调用方里有一支是异步 SetTimer 复核，等它跑起来时
    ;   用户很可能已经按热键把窗口收起了（实测弹模态框、整个脚本卡死，之后 Alt+X /
    ;   Alt+C 全无反应）。最小化态也别动：位置停在 -32000 停放位，量到的尺寸是垃圾值。
    ; 具体闸的实现见 WindowProbe.IsPlaceable。
    static IsPlaceable(hwnd) => WindowProbe.IsPlaceable(hwnd)

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
        return RectMath.CornerRect(WindowProbe.PrimaryWorkArea(), w, h
            , Config.PlaceRight)
    }

    ; 读伴生窗口此刻的**真实**外框矩形，供 Launcher.Opened 广播（笔记窗口据此避让）。
    ; 隐藏态读取的细节见 WindowProbe.RectOf；窗口已不在 / 尺寸为 0 时返回 ""。
    static RectOf(hwnd) => WindowProbe.RectOf(hwnd, true)
}
