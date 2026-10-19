#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  WindowProbe —— 窗口与工作区查询（平台能力层）
; ═══════════════════════════════════════════════════════════════════════════
; 只回答「窗口在哪 / 在不在 / 可不可摆」这类事实问题：
;   · 不读 Config / State，不发事件，不搬窗口；
;   · 返回值一律是**物理像素**；
;   · 隐藏窗口的读取由调用方用 allowHidden 明确指定，不把「必须先开
;     DetectHiddenWindows」的隐含约定留给上层。

class WindowProbe {
    ; 可摆放：窗口存在、可见、且没有最小化。
    ; ⚠ 最小化窗口的 IsWindowVisible 仍是 1，必须连同 IsIconic 一起排除。
    static IsPlaceable(hwnd) {
        if !hwnd
            return false
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(false)
        try {
            return !!WinExist("ahk_id " . hwnd)
                && !DllCall("IsIconic", "ptr", hwnd, "int")
        } finally {
            DetectHiddenWindows(detectOld)
        }
    }

    ; 读窗口物理外框；读不到（窗口没了 / 尺寸无效）返回 ""。
    ; allowHidden 缺省 true，兼容「Show("Hide") 之后量尺寸」的老用法。
    static RectOf(hwnd, allowHidden := true) {
        if !hwnd
            return ""
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(allowHidden)
        try {
            if !WinExist("ahk_id " . hwnd)
                return ""
            WinGetPos(&x, &y, &w, &h, "ahk_id " . hwnd)
        } catch {
            return ""
        } finally {
            DetectHiddenWindows(detectOld)
        }
        if (w > 0 && h > 0)
            return {x: x, y: y, w: w, h: h}
        return ""
    }

    ; 窗口矩形比「可见边界」多出来的那圈不可见调整边框（含 DWM 阴影）。
    ; 返回 {l, t, r, b} = 各自的「矩形边 − 可见边」，左 / 上通常为负。
    ; 拿不到 DWM 信息或窗口矩形时一律返回全 0，当作没有不可见边框。
    static InvisibleFrame(hwnd) {
        if !hwnd
            return {l: 0, t: 0, r: 0, b: 0}

        buf := Buffer(16, 0)
        try
            DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 9, "ptr", buf, "uint", 16)
        catch
            return {l: 0, t: 0, r: 0, b: 0}

        rect := this.RectOf(hwnd, true)
        if !IsObject(rect)
            return {l: 0, t: 0, r: 0, b: 0}

        vx := NumGet(buf, 0, "int"), vy := NumGet(buf, 4, "int")
        vr := NumGet(buf, 8, "int"), vb := NumGet(buf, 12, "int")
        return {l: rect.x - vx, t: rect.y - vy
            , r: (rect.x + rect.w) - vr, b: (rect.y + rect.h) - vb}
    }

    ; 矩形中心点所在的显示器工作区；找不到就回落到主屏。
    ; 返回 {x, y, w, h}，与 RectMath 的 WorkArea 约定一致。
    static WorkAreaFor(rect) {
        if !this._ValidRect(rect)
            return ""
        cx := rect.x + rect.w // 2
        cy := rect.y + rect.h // 2
        monIdx := 1
        loop MonitorGetCount() {
            MonitorGet(A_Index, &mL, &mT, &mR, &mB)
            if (cx >= mL && cx < mR && cy >= mT && cy < mB) {
                monIdx := A_Index
                break
            }
        }
        return this.PrimaryWorkArea(monIdx)
    }

    ; 指定显示器的工作区（缺省主屏）。
    static PrimaryWorkArea(monIdx := 0) {
        if !monIdx
            monIdx := MonitorGetPrimary()
        MonitorGetWorkArea(monIdx, &wkLeft, &wkTop, &wkRight, &wkBottom)
        return {x: wkLeft, y: wkTop
            , w: wkRight - wkLeft, h: wkBottom - wkTop}
    }

    ; 矩形是否与某个显示器工作区相交。
    ; 最小化窗口的坐标是 -32000 一类的停放位（会按 DPI 缩放成 -21333 等），
    ; 而它的 WS_VISIBLE 仍为真，只靠可见性判断拦不住。
    static IsUsableRect(x, y, w, h) {
        ; 数值守卫：State 里未初始化的记忆值是空字符串，
        ; 而 AHK v2 的 <= 遇到空字符串会抛「Expected a Number」
        if !(IsNumber(x) && IsNumber(y) && IsNumber(w) && IsNumber(h))
            return false
        if (w <= 0 || h <= 0)
            return false
        loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &wkLeft, &wkTop, &wkRight, &wkBottom)
            if (x < wkRight && y < wkBottom && x + w > wkLeft && y + h > wkTop)
                return true
        }
        return false
    }

    static _ValidRect(rect) {
        return IsObject(rect)
            && rect.HasProp("x") && rect.HasProp("y")
            && rect.HasProp("w") && rect.HasProp("h")
            && IsNumber(rect.x) && IsNumber(rect.y)
            && IsNumber(rect.w) && IsNumber(rect.h)
            && rect.w > 0 && rect.h > 0
    }
}
