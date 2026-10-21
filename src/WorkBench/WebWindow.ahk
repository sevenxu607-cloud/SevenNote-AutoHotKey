#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  WebWindow —— 平台界面骨架：一个「装着 WebView2 的窗口」该有的全部动作
; ═══════════════════════════════════════════════════════════════════════════
;  v2.9 把 Alt+S 面板搬进 WebView2，v2.10 把这份生命周期抽出来并搬了提示词库；
;  编辑窗 / 日期跳转 / 启动提示沿用同一套。这几个窗口的**生命周期**完全一样：
;    建窗 → 隐藏态定位 → 露面 → 挂 WebView2 → 注册 Esc → 收起 / 再打开 → 换主题
;  差别只在「多大、停在哪、装哪个页面、提供哪些宿主方法」。所以把生命周期收在这里，
;  各窗口只留自己的那点业务 —— 否则同一份「隐藏态定位 + 露面后挂载」要抄好几遍，
;  而它俩正是踩过最多坑的地方（见 .clinerules/03）。
;
;  用法（每个窗口一个实例；Feature 自己 static 存着）：
;
;    win := WebWindow({
;        title:    Config.AppName . " · 提示词库"
;      , w: 620, h: 520                     ; 逻辑单位，缺省 520x480
;      , view:   "prompts"                  ; → /index.html?view=prompts
;      , dataDir: "prompts"                 ; → %LOCALAPPDATA%\SevenWork\WebView2-prompts
;      , handlers: PromptHostHandlers       ; 函数，调用后返回 hostObjects 方法表
;      , place:  "topright"                 ; center（缺省）/ topright / ""（不动）
;      , esc:    () => PromptWindowFeature.Hide()
;    })
;    win.Open() / win.Close() / win.IsOpen() / win.Hwnd() / win.ApplyTheme()
;
;  ⚠ 每个窗口的 **dataDir 必须不同**：同一个 user data folder 建不出第二个
;    CoreWebView2Environment（Chromium 的 profile 锁），而失败发生在 await() 里 ——
;    表现只是「窗口一片纯底色」。
; ═══════════════════════════════════════════════════════════════════════════

class WebWindow {
    ; ⚠ 字段名**不能与任何方法同名**（AHK v2 的属性名不区分大小写，也和方法共用
    ;   同一个命名空间）：这里原来叫 `_place`，与下面的私有方法 `_Place()` 撞车，
    ;   `this._place := x` 就被解析成「给方法赋值」→ 抛 "Property is read-only."，
    ;   而它发生在 __New 里，表现成「按 Alt+S 没反应、_error.log 只有一行 read-only」。
    ;   另一条同源的坑：字段也不能声明在类体里（类体变量是静态的）。
    ;   所以一律在 __New 里赋初值，且名字与方法错开（`_placeMode` vs `_Place()`）。
    __New(opts := "") {
        this._title    := this._Opt(opts, "title", "SevenWork")
        this._w        := this._Opt(opts, "w", 520)
        this._h        := this._Opt(opts, "h", 480)
        this._view     := this._Opt(opts, "view", "")
        this._dataDir  := this._Opt(opts, "dataDir", "")
        this._handlers := this._Opt(opts, "handlers", "")
        this._escFn    := this._Opt(opts, "esc", "")
        this._placeMode := this._Opt(opts, "place", "center")
        this._placeTop := this._Opt(opts, "placeTop", 120)
        this._onReady  := this._Opt(opts, "onReady", "")

        ; 运行时状态
        this._gui := ""
        this._hwnd := 0
        this._mounted := false
        this._escRegistered := false
    }

    ; opts 是普通对象（字面量）；缺字段 / 空串一律退回缺省值 —— 调用方少写一项不至于报错
    _Opt(opts, key, def) {
        if !IsObject(opts) || !opts.HasProp(key)
            return def
        v := opts.%key%
        return (v = "") ? def : v
    }

    ; ─── 对外 ─────────────────────────────────────────────────────────

    Hwnd() => this._hwnd

    IsOpen() {
        return IsObject(this._gui) && this._hwnd
            && DllCall("user32\IsWindow", "ptr", this._hwnd, "int")
    }

    ; 开着就直接露 + 补一次 Resize；没建 / 已被销毁就整座建起来
    Open() {
        if this.IsOpen()
            this.Activate()
        else
            this._Build()
    }

    Close() {
        if !this.IsOpen()
            return
        try this._gui.Hide()
        this._UnregisterEsc()
    }

    Toggle() {
        if this.IsOpen()
            this.Close()
        else
            this.Open()
    }

    ; 已经藏着的时候再呼出：Show + 激活 + 补一次 Fill。
    ; ⚠ Fill 必须补：Chromium 子窗口在父窗口隐藏期间尺寸停滞，回来后会是一块
    ;   旧尺寸的画面（右侧留一条底色）。
    Activate() {
        try {
            this._gui.Show()
            WinActivate("ahk_id " . this._hwnd)
            WebHostService.Resize(this._hwnd)
            this._Reveal()
        } catch as e {
            LogError(this._title . " 激活失败：" . e.Message)
        }
    }

    ; 呼出粒子（冰晶迸发）。所有 Web 窗口共用一个入口 ——
    ; 从前只有笔记窗在自己的 Shown 事件里喊，面板 / 提示词窗一直没有粒子。
    ; ⚠ 页面还没挂好时 Eval 返回 {ok:false}，前端那句 `__swfx &&` 会短路，
    ;   不报错也不写日志 —— 首次打开没看见粒子是正常现象。
    ; ⚠ 与笔记窗自己的 reveal() 撞上无害：burst() 重复调用只打断上一次。
    _Reveal() {
        if !this._mounted || !this.IsOpen()
            return
        WebHostService.Eval("window.__swfx&&window.__swfx.reveal()", this._hwnd)
    }

    ; 换主题：只换窗口底色 + 把 --sw-* 推给页面，**不重建**。
    ; 这样当前停在哪一页、输入框里的字都保持不变（原生控件版只能关掉重开）。
    ApplyTheme() {
        if !this.IsOpen()
            return
        p := ThemeService.Palette()
        try this._gui.BackColor := p.win
        UiPaint.WindowTheme(this._hwnd, p.dark)
        ; ⚠ 顺序：先立背板、再决定标题栏染不染。mica/acrylic 生效时染色会把
        ;   背板盖成一块实色（见 UiPaint.TitleBar 的 caption 说明）。
        m := UiPaint.Glass(this._hwnd, p.style, p.win)
        UiPaint.TitleBar(this._hwnd, p.win, p.text, !(IsObject(m) && m.ok))
        ; 页面没起来时 Eval 返回 {ok:false}，忽略即可 —— 页面 onMounted 还会
        ; 再 getTheme 一次，不会留旧色。
        if this._mounted
            WebHostService.Eval("window.__sevenwork&&window.__sevenwork.applyTheme("
                . ThemeJson() . ")", this._hwnd)
    }

    ; ─── 建窗口 ───────────────────────────────────────────────────────

    _Build() {
        p := ThemeService.Palette()

        ; ⚠ 不加 +AlwaysOnTop：窗口一置顶，DirSelect 之类的系统对话框会被压在
        ;   下面看不见（它是独立的顶层窗口，owner 置顶时它也跟着被盖）。
        g := Gui("-MinimizeBox -MaximizeBox", this._title)
        g.SetFont("s10", "Microsoft YaHei UI")
        g.BackColor := p.win
        ; 非客户区（标题栏 / 边框）的玻璃背衬 —— 客户区整个交给 WebView2。
        ; ⚠ 背板成功时不染标题栏底色，否则 Win11 的亚克力被实色盖掉。
        UiPaint.WindowTheme(g.Hwnd, p.dark)
        m := UiPaint.Glass(g.Hwnd, p.style, p.win)
        UiPaint.TitleBar(g.Hwnd, p.win, p.text, !(IsObject(m) && m.ok))

        this._gui := g
        this._hwnd := g.Hwnd

        ; 点 × 只藏不销毁 —— WebView2 重建要 300ms 上下，而这些窗口都是随手呼出的
        g.OnEvent("Close", (*) => this.Close())

        ; 隐藏态完成定位再露面：先 Show 再 WinMove 会「飘一下」（.clinerules/03）
        g.Show("w" . this._w . " h" . this._h . " Hide")
        this._Place()
        g.Show()

        this._escRegistered := this._RegisterEsc()

        ; ⚠ 挂载放在**露面之后**：隐藏态挂 WebView2 时 Chromium 会留在 SW_HIDE，
        ;   父窗口再显示也不回来（表现为「窗口出来了、内容区一片纯底色」）。
        ;   代价是首帧多等 ~300ms，由 Mount 的 bgColor 兜住（不闪白）。
        this._Mount()

        fn := this._onReady
        if IsObject(fn)
            try fn(this)

        ; 首次露面也补一次粒子：导航是异步的，等 700ms 再喊（早喊会被 && 吞掉）。
        SetTimer((*) => this._Reveal(), -700)
    }

    ; 摆位：center    = 主屏工作区居中偏上（不写死坐标，换显示器 / 改分辨率都不用改代码）
    ;       topright  = 工作区右上角，右边距 Config.PlaceRight、顶边下移 _placeTop
    ;       其它      = 交给窗口系统
    _Place() {
        if (this._placeMode != "center" && this._placeMode != "topright")
            return
        rect := WindowProbe.PrimaryWorkArea()
        if !IsObject(rect)
            return

        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)   ; Show("Hide") 过的窗口 WinGetPos 读不到
        try {
            x := 0, y := 0, w := 0, h := 0
            ; 刚 Show("Hide") 的窗口尺寸要几轮才稳定（控件按 DPI 放大是异步的）
            prevW := -1, prevH := -1
            loop 40 {
                try WinGetPos(&x, &y, &w, &h, "ahk_id " . this._hwnd)
                if (w = prevW && h = prevH && w > 0)
                    break
                prevW := w, prevH := h
                Sleep 5
            }
            if (w <= 0 || h <= 0)
                return

            if (this._placeMode = "topright") {
                pos := RectMath.TopRightRect(rect, w, h, Config.PlaceRight, this._placeTop)
                if IsObject(pos)
                    WinMove(pos.x, pos.y, , , "ahk_id " . this._hwnd)
            } else {
                ; ⚠ WinMove 收**物理像素**，与 WinGetPos 同单位；别用 Gui.Move —— 那会再乘一次 DPI。
                WinMove(rect.x + (rect.w - w) // 2, rect.y + (rect.h - h) // 3
                    , , , "ahk_id " . this._hwnd)
            }
        } catch as e {
            LogError(this._title . " 摆位失败：" . e.Message)
        } finally {
            DetectHiddenWindows(detectOld)
        }
    }

    ; ─── 挂 WebView2 ───────────────────────────────────────────────────

    _Mount() {
        dist := WebHostService.DistDir()
        if (dist = "") {
            LogError(this._title . " 挂载失败：找不到前端产物目录（web\dist，先跑 npm run build）")
            return
        }

        p := ThemeService.Palette()
        ; ⚠ dataDir 必须逐窗不同，理由见文件头。
        ; ⚠ 首帧色是 AARRGGBB（COREWEBVIEW2_COLOR），不是 Win32 的 COLORREF，
        ;   别套 RGBtoBGR（那会把 R/B 反过来）。
        r := WebHostService.Mount(this._hwnd, dist, "app.local"
            , 0xFF000000 | Integer("0x" . p.edBg)
            , EnvGet("LOCALAPPDATA") . "\SevenWork\WebView2-" . this._dataDir)
        if !r.ok {
            LogError(this._title . " WebView2 挂载失败：" . r.reason)
            return
        }

        ; ⚠ hostObjects 按 WebView 实例注册：每个窗口有自己的一张表，不能指望
        ;   别的窗口绑过的 "ahk" 在这边也在。
        fn := this._handlers
        if IsObject(fn)
            WebHostService.Bind("ahk", fn(), this._hwnd)

        url := "/index.html" . (this._view = "" ? "" : "?view=" . this._view)
        n := WebHostService.Navigate(url, this._hwnd)
        if !n.ok {
            LogError(this._title . " 导航失败：" . n.reason)
            return
        }
        this._mounted := true
        ; 可见态挂载本来就该有尺寸，但 Fill 一次更保险（子窗口刚建出来是 0×0）
        WebHostService.Resize(this._hwnd)
    }

    ; ─── Esc：只在这个窗口激活时生效 ────────────────────────────────────
    ; 不进模块热键表：这是窗口自己的键，藏起来时立刻注销。
    ; ⚠ 必须用 HotIfWinActive 钩子、**不能**靠 Gui 的 Escape 事件 ——
    ;   键盘焦点在 WebView2 子窗口里，Gui 收不到那个事件。
    ; ⚠ 回调要包成**变参**箭头函数 `(*) => …`：Hotkey 会往回调里塞热键名，
    ;   零参闭包（`() => …`）直接报 `Invalid callback function`。
    ; ⚠ 注册失败要记日志 —— 声明了却没人实现的键表现为「按了没反应」。
    _RegisterEsc() {
        userFn := this._escFn
        if IsObject(userFn)
            cb := (*) => userFn()
        else
            cb := (*) => this.Close()
        HotIfWinActive(this._title)
        try
            Hotkey("Esc", cb, "On")
        catch as e {
            LogError(this._title . " Esc 注册失败：" . e.Message)
            HotIf()
            return false
        }
        HotIf()
        return true
    }

    _UnregisterEsc() {
        if !this._escRegistered
            return
        this._escRegistered := false
        try {
            HotIfWinActive(this._title)
            Hotkey("Esc", "Off")
        } catch as e {
            LogError(this._title . " Esc 注销失败：" . e.Message)
        }
        HotIf()
    }
}
