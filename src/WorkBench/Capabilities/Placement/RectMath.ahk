#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  RectMath —— 纯几何能力（平台能力层）
; ═══════════════════════════════════════════════════════════════════════════
; 只接收数字与矩形，不读 Config / State / 屏幕，不发事件，不搬窗口。
; 所有坐标与尺寸一律是**物理像素**，与 WinGetPos / WinMove 同一单位。
;
; 矩形约定：
;   Rect      {x, y, w, h}                 x / y 为左上角
;   Frame     {l, t, r, b}                 外框比可见边界多出来的那圈不可见边框
;   WorkArea  {x, y, w, h}                 显示器工作区
;
; 这里不判断「窗口在不在 / 可不可见 / 在哪个屏」—— 那些归 WindowProbe。
; 需要窗口上下文的调用方先量好，再把数字交给这里。

class RectMath {
    ; ─── 堆叠方案：笔记在上、伙伴在下 ───
    ; 入参：
    ;   peerRect   伙伴窗口的物理外框（可带 hwnd，原样带进结果）
    ;   workArea   伙伴所在显示器的工作区
    ;   noteFrame  笔记窗口的不可见边框
    ;   peerFrame  伙伴窗口的不可见边框
    ;   opts       {gap, margin, minW, minH}，全部物理像素
    ;
    ; 返回：
    ;   {ok: false, reason}
    ;   {ok: true, note: {x,y,w,h,frame}, noteRect: {x,y,w,h},
    ;    peer: "" 或 {hwnd,x,y}, peerRect: {hwnd,x,y,w,h}}
    ;
    ; note 是「可见边界」，noteRect 是 WinMove 认的物理外框；peer 非空表示
    ; 伙伴需要下移（方案二），peerRect 是下移后的矩形。
    static PlanStack(peerRect, workArea, noteFrame, peerFrame, opts) {
        if !this._ValidRect(peerRect)
            return {ok: false, reason: "bad-peer-rect"}
        if !this._ValidRect(workArea)
            return {ok: false, reason: "bad-work-area"}
        if !this._ValidOpts(opts)
            return {ok: false, reason: "bad-opts"}

        pr := {hwnd: peerRect.HasProp("hwnd") ? peerRect.hwnd : 0
            , x: peerRect.x, y: peerRect.y, w: peerRect.w, h: peerRect.h}
        nf := this._Frame(noteFrame)
        pf := this._Frame(peerFrame)

        ; 摆位置一律按「可见边界」算 —— 直接拿 WinGetPos 的矩形去拼，
        ; 肉眼看会多出上窗那 9px 的不可见底边框（12 的缝看着像 21），显得松散。
        peerVisL := pr.x - pf.l, peerVisT := pr.y - pf.t
        peerVisR := pr.x + pr.w - pf.r, peerVisB := pr.y + pr.h - pf.b

        ; 笔记窗口的可见目标：左边与伙伴对齐、同宽、顶边贴工作区顶、底边在伙伴上方留 gap
        noteVisL := peerVisL
        noteVisW := peerVisR - peerVisL
        noteVisT := workArea.y + opts.margin

        ; 方案一：伴生窗口原地不动，笔记窗口填它上方的空间
        note := this._NotePlan(noteVisL, noteVisT, noteVisW
            , peerVisT - opts.gap - noteVisT, nf, opts.minW, opts.minH)
        if IsObject(note) {
            return {ok: true, note: note, noteRect: this.Physical(note)
                , peer: "", peerRect: pr}
        }

        ; 方案二：伴生窗口已经顶到屏幕上方了 —— 把它下移到底边贴工作区底，
        ; 尺寸（宽高）原样保留，只挪位置
        newPeerVisT := (workArea.y + workArea.h - opts.margin) - (peerVisB - peerVisT)
        note := this._NotePlan(noteVisL, noteVisT, noteVisW
            , newPeerVisT - opts.gap - noteVisT, nf, opts.minW, opts.minH)
        if IsObject(note) {
            newPeerY := newPeerVisT + pf.t
            return {ok: true, note: note, noteRect: this.Physical(note)
                , peer: {hwnd: pr.hwnd, x: pr.x, y: newPeerY}
                , peerRect: {hwnd: pr.hwnd, x: pr.x, y: newPeerY, w: pr.w, h: pr.h}}
        }

        return {ok: false, reason: "no-fit"}
    }

    ; 可见边界 → WinMove 认的外框矩形。
    static Physical(note) {
        return {x: note.x + note.frame.l
            , y: note.y + note.frame.t
            , w: Max(note.w + note.frame.r - note.frame.l, 1)
            , h: Max(note.h + note.frame.b - note.frame.t, 1)}
    }

    ; 两个矩形是否相交 —— 即「有没有一块地方同时被两个窗口占着」。
    static Overlaps(a, b) {
        return (a.x < b.x + b.w && a.x + a.w > b.x
            && a.y < b.y + b.h && a.y + a.h > b.y)
    }

    ; 贴工作区右下角；offsetRight / offsetBottom 为物理像素边距。
    ; 左上角贴边时留 10px 兜底，避免负坐标或压住屏幕边缘。
    static CornerRect(workArea, w, h, offsetRight := 0, offsetBottom := 0) {
        if !this._ValidRect(workArea)
            return ""
        if !(IsNumber(w) && IsNumber(h) && w > 0 && h > 0)
            return ""
        x := workArea.x + workArea.w - w - offsetRight
        y := workArea.y + workArea.h - h - offsetBottom
        if (x < workArea.x + 10)
            x := workArea.x + 10
        if (y < workArea.y + 10)
            y := workArea.y + 10
        return {x: x, y: y}
    }

    ; 可见目标是否满足最小尺寸；不满足返回空串，交给下一个方案。
    static _NotePlan(visL, visT, visW, visH, frame, minW, minH) {
        if (visH < minH || visW + frame.r - frame.l < minW)
            return ""
        return {x: visL, y: visT, w: visW, h: visH, frame: frame}
    }

    static _Frame(frame) {
        if !IsObject(frame)
            return {l: 0, t: 0, r: 0, b: 0}
        return {l: this._Num(frame, "l"), t: this._Num(frame, "t")
            , r: this._Num(frame, "r"), b: this._Num(frame, "b")}
    }

    static _Num(obj, name) {
        return (obj.HasProp(name) && IsNumber(obj.%name%)) ? obj.%name% : 0
    }

    static _ValidRect(rect) {
        return IsObject(rect)
            && rect.HasProp("x") && rect.HasProp("y")
            && rect.HasProp("w") && rect.HasProp("h")
            && IsNumber(rect.x) && IsNumber(rect.y)
            && IsNumber(rect.w) && IsNumber(rect.h)
            && rect.w > 0 && rect.h > 0
    }

    static _ValidOpts(opts) {
        return IsObject(opts)
            && opts.HasProp("gap") && IsNumber(opts.gap)
            && opts.HasProp("margin") && IsNumber(opts.margin)
            && opts.HasProp("minW") && IsNumber(opts.minW)
            && opts.HasProp("minH") && IsNumber(opts.minH)
            && opts.minW > 0 && opts.minH > 0
    }
}
