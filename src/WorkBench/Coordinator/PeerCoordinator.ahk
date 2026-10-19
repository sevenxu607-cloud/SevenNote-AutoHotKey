#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  PeerCoordinator —— 伙伴窗口布局协调（Phase 3b）
; ═══════════════════════════════════════════════════════════════════════════
; 平台层只算几何，不搬窗口：
;   · 订阅 Launcher.Opened / SevenNote.WindowReady，记录双方最近一次落位；
;   · 提供 PlanStack() 给 WindowFeature 计算「笔记在上、伙伴在下」的堆叠落点；
;   · 真实布局发生时广播 SevenNote.Move / Launcher.Move（Phase 5 再接订阅者）。
; 旧的 Peer.Preparing / Peer.Placed / Peer.Failed 契约与 WindowFeature 的
; 让位 / 冻结状态机暂时原样保留 —— 本阶段不拿已验证的窗口行为冒险。

class PeerCoordinator {
    static _initialized := false
    static _lastNote := ""
    static _lastPeer := ""

    static Init() {
        if this._initialized
            return
        this._initialized := true
        EventBus.On("Launcher.Opened", (data) => this._OnLauncherOpened(data))
        EventBus.On("SevenNote.WindowReady", (data) => this._OnNoteReady(data))
    }

    static GetLastNote() => this._lastNote
    static GetLastPeer() => this._lastPeer

    static _OnLauncherOpened(data) {
        this._lastPeer := data
    }

    static _OnNoteReady(data) {
        this._lastNote := data
    }

    ; ─── 几何：与 WindowFeature 原先的 _StackWithPeer 算式逐项一致 ───
    ; 返回：
    ;   {ok: false, reason}
    ;   {ok: true, note: {x,y,w,h,frame}, noteRect: {x,y,w,h},
    ;    peer: "" 或 {hwnd,x,y}, peerRect: {hwnd,x,y,w,h}}
    ; note 是「可见边界」，noteRect 是 WinMove 认的物理外框；peer 非空表示
    ; 伙伴需要下移（方案二），peerRect 是下移后的矩形。
    static PlanStack(noteHwnd, peerRect, publish := false) {
        if !noteHwnd || !IsObject(peerRect)
            return {ok: false, reason: "bad-input"}
        if !(peerRect.HasProp("x") && peerRect.HasProp("y")
            && peerRect.HasProp("w") && peerRect.HasProp("h"))
            return {ok: false, reason: "bad-peer-rect"}
        if !(IsNumber(peerRect.x) && IsNumber(peerRect.y)
            && IsNumber(peerRect.w) && IsNumber(peerRect.h))
            return {ok: false, reason: "bad-peer-rect"}
        if (peerRect.w <= 0 || peerRect.h <= 0)
            return {ok: false, reason: "bad-peer-rect"}

        pr := {hwnd: peerRect.HasProp("hwnd") ? peerRect.hwnd : 0
            , x: peerRect.x, y: peerRect.y, w: peerRect.w, h: peerRect.h}

        ; 工作区取伴生窗口所在的那块显示器 —— 它可能被放到副屏上
        monIdx := 1
        cx := pr.x + pr.w // 2, cy := pr.y + pr.h // 2
        loop MonitorGetCount() {
            MonitorGet(A_Index, &mL, &mT, &mR, &mB)
            if (cx >= mL && cx < mR && cy >= mT && cy < mB) {
                monIdx := A_Index
                break
            }
        }
        MonitorGetWorkArea(monIdx, &wkLeft, &wkTop, &wkRight, &wkBottom)

        gap := Config.DockGap, margin := Config.DockMargin
        ; 最小尺寸：Config 里是逻辑单位，乘 DPI 比才是 WinMove 认的物理像素
        ; （+MinSize450x300 → 本机 150% 缩放下的 675x450）
        minW := 450 * A_ScreenDPI // 96
        minH := 300 * A_ScreenDPI // 96

        ; 摆位置一律按「可见边界」算 —— 直接拿 WinGetPos 的矩形去拼，
        ; 肉眼看会多出上窗那 9px 的不可见底边框（12 的缝看着像 21），显得松散。
        pFrame := this._InvisibleFrame(pr.hwnd)
        nFrame := this._InvisibleFrame(noteHwnd)
        peerVisL := pr.x - pFrame.l, peerVisT := pr.y - pFrame.t
        peerVisR := pr.x + pr.w - pFrame.r, peerVisB := pr.y + pr.h - pFrame.b

        ; 笔记窗口的可见目标：左边与伙伴对齐、同宽、顶边贴工作区顶、底边在伙伴上方留 gap
        noteVisL := peerVisL
        noteVisW := peerVisR - peerVisL
        noteVisT := wkTop + margin

        ; 方案一：伴生窗口原地不动，笔记窗口填它上方的空间
        note := this._NotePlan(noteVisL, noteVisT, noteVisW
            , peerVisT - gap - noteVisT, nFrame, minW, minH)
        if IsObject(note) {
            plan := {ok: true, note: note, noteRect: this._Physical(note)
                , peer: "", peerRect: pr}
            if publish
                this._PublishMoves(noteHwnd, plan)
            return plan
        }

        ; 方案二：伴生窗口已经顶到屏幕上方了 —— 把它下移到底边贴工作区底，
        ; 尺寸（宽高）原样保留，只挪位置
        newPeerVisT := (wkBottom - margin) - (peerVisB - peerVisT)
        note := this._NotePlan(noteVisL, noteVisT, noteVisW
            , newPeerVisT - gap - noteVisT, nFrame, minW, minH)
        if IsObject(note) {
            newPeerY := newPeerVisT + pFrame.t
            plan := {ok: true, note: note, noteRect: this._Physical(note)
                , peer: {hwnd: pr.hwnd, x: pr.x, y: newPeerY}
                , peerRect: {hwnd: pr.hwnd, x: pr.x, y: newPeerY, w: pr.w, h: pr.h}}
            if publish
                this._PublishMoves(noteHwnd, plan)
            return plan
        }

        return {ok: false, reason: "no-fit"}
    }

    ; 可见目标是否满足最小尺寸；不满足返回空串，交给下一个方案。
    static _NotePlan(visL, visT, visW, visH, frame, minW, minH) {
        if (visH < minH || visW + frame.r - frame.l < minW)
            return ""
        return {x: visL, y: visT, w: visW, h: visH, frame: frame}
    }

    ; 可见边界 → WinMove 认的外框矩形。
    static _Physical(note) {
        return {x: note.x + note.frame.l
            , y: note.y + note.frame.t
            , w: Max(note.w + note.frame.r - note.frame.l, 1)
            , h: Max(note.h + note.frame.b - note.frame.t, 1)}
    }

    ; 真实布局发生时广播（Phase 5 之前暂无订阅者；先固定事件载荷的形状）。
    static _PublishMoves(noteHwnd, plan) {
        EventBus.Emit("SevenNote.Move", {hwnd: noteHwnd
            , x: plan.noteRect.x, y: plan.noteRect.y
            , w: plan.noteRect.w, h: plan.noteRect.h})
        if IsObject(plan.peer)
            EventBus.Emit("Launcher.Move", {hwnd: plan.peer.hwnd
                , x: plan.peer.x, y: plan.peer.y
                , w: plan.peerRect.w, h: plan.peerRect.h})
    }

    ; 窗口矩形比「可见边界」多出来的那圈不可见调整边框（含 DWM 阴影）。
    ; 返回 {l, t, r, b} = 各自的「矩形边 − 可见边」，左 / 上通常为负。
    ; ⚠ 本机（150% 缩放）实测：左 −9、上 0、右 9、下 9；25% 缩放或旧系统上可能不同，
    ;   所以这里每次都实测，不写死。
    ; ⚠ 调用方可能正处在 Show("Hide") 之后 —— WinGetPos 默认忽略隐藏窗口，
    ;   这里自己开 DetectHiddenWindows，别把「必须先开」的隐含约定留给调用方。
    static _InvisibleFrame(hwnd) {
        if !hwnd
            return {l: 0, t: 0, r: 0, b: 0}

        buf := Buffer(16, 0)
        try
            DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 9, "ptr", buf, "uint", 16)
        catch
            return {l: 0, t: 0, r: 0, b: 0}   ; 拿不到就当作没有不可见边框

        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            WinGetPos(&rx, &ry, &rw, &rh, "ahk_id " . hwnd)
        } catch {
            return {l: 0, t: 0, r: 0, b: 0}
        } finally {
            DetectHiddenWindows(detectOld)
        }
        vx := NumGet(buf, 0, "int"), vy := NumGet(buf, 4, "int")
        vr := NumGet(buf, 8, "int"), vb := NumGet(buf, 12, "int")
        return {l: rx - vx, t: ry - vy, r: (rx + rw) - vr, b: (ry + rh) - vb}
    }
}
