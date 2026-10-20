#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════════
;  WorkBenchUI —— 平台级界面（Phase 7：帮助 → 工作台管控面板）
; ═══════════════════════════════════════════════════════════════════════════
; 平台只负责「怎么摆」，摆什么由各模块自己声明：
;   GetMetadata()      → 模块名 / 描述 / 热键（面板里每一页的热键都从这来）
;   GetSettingsSpec()  → 可选，返回 {title, hint, fields, apply}
;                        平台只认 {label, kind, value} 三个字段，**不认识任何业务概念**
;                        （比如「文件夹槽位」是 Folders 模块自己的词，平台并不知道）
;
; 布局（参考常见控制面板：左导航 / 右内容，一行只说明一件事）：
;   左列  导航 —— 第一行「≡ 全部热键」是**视图**（老 Alt+S 的内容，按旧分组排列），
;         下面是各**模块**，按 GetMetadata().order 排；第二列是每页的热键条数。
;         底部一行统计（N 个模块 · M 条热键）。
;   右列  页眉（我在哪一页）→ 热键清单 → 状态行 + 版本 → 设置区（没声明的模块只显示热键）。
;
; ⚠ 加模块不用改本文件：新模块出现在左列靠 ModuleRegistry.All()，
;   设置区靠 GetSettingsSpec() 的有无自动出现 / 消失。
; ⚠ Alt+S 的注册在 WorkBench.GetHotkeys()；面板的 Esc 由本类自注册 / 注销。

class WorkBenchUI {
    ; 面板标题固定，Esc 的 HotIfWinActive 上下文也用它
    static _PanelTitle() => Config.AppName . " · 工作台"

    static _gui := ""
    static _escRegistered := false

    ; ─── 控件句柄（关窗时置空，防悬空引用）───
    static _lv := ""            ; 左列：导航（名称 + 条数 两列）
    static _foot := ""          ; 左列页脚：模块数 / 热键总数
    static _head := ""          ; 右列页眉：这一页是什么（模块名 / 全部热键）
    static _sub := ""           ; 右列副标题：一句话说明（模块 desc）
    static _hkEdit := ""        ; 右列：热键清单（只读、可滚动）
    static _status := ""        ; 状态行：保存结果
    static _specTitle := ""     ; 设置区标题
    static _specHint := ""      ; 设置区说明
    static _saveBtn := ""       ; 保存按钮（没有设置可存时禁用）

    ; ─── 当前渲染状态 ───
    static _currentModule := ""
    static _rowToId := ""       ; ListView 行号 → 模块 Id
    static _specRows := []      ; [{field, ctrl, browse}]
    static _specApply := ""
    static _saveTimer := ""     ; 保存按钮「✓ 已保存」的复原定时器（闭包存字段才停得掉）
    static _lastBrowse := ""    ; 上次浏览到的目录：连配三个槽位时不用每次重新点下去

    ; ─── 列表第一项：所有热键按旧分组排列（就是老 Alt+S 的样子）───
    static OverviewId := "__overview"

    ; ─── 布局常量（逻辑单位）───
    ; 面板 940x700；右列的 x / 宽都从这里推出来，改版只动这几行。
    ;   侧栏  x0   宽 232（独立底色）
    ;   导航  x16  宽 200  → 216（嵌在侧栏里，左右各留 16）
    ;   右列  x256 宽 668  → 924（= 940 - 16）
    static _Right := 256
    static _RightW := 668

    ; 设置字段区的起始 y 与行高（逻辑单位）。改布局只动这两个数。
    static _specY := 548
    static _specRowH := 34

    ; 首选项：平台组永远排第一；其余沿用改造前的顺序。
    ; 模块新增的组若不在表里，会按首次出现顺序追加到末尾 —— 不用改这里。
    static _GroupOrder := ["平台", "窗口", "外观", "输入增强", "搜索", "文本", "文件夹"
        , "保存", "日期与标签", "编辑", "分段"]

    ; ─── 初始化：只订阅事件，不建窗口 ───
    ; 「某个槽位没配好」这类请求由模块发事件进来（模块不认识平台类），
    ; 平台负责把面板开到对应的页 —— 这是 Feature → EventBus → 平台 的解耦写法。
    static Init() {
        EventBus.On("Panel.OpenRequested", (data) => this._OnOpenRequested(data))
    }

    ; ─── Alt+S：已开着就激活，否则新建 ───
    static ShowHelp() {
        title := this._PanelTitle()
        if WinExist(title . " ahk_class AutoHotkeyGUI") {
            WinActivate(title . " ahk_class AutoHotkeyGUI")
            return
        }
        this._Build()
        this._escRegistered := this._RegisterEsc()
    }

    ; ═══ 建窗 ═══
    static _Build() {
        ; ⚠ 不加 +AlwaysOnTop：面板一置顶，「选择文件夹」对话框就会被压在下面看不见
        ;   （它是独立的顶层窗口，owner 置顶时它也会跟着被盖）。配置面板没有置顶的必要 ——
        ;   再按一次 Alt+S 会 WinActivate 把它提到最前。
        g := Gui("-MinimizeBox -MaximizeBox", this._PanelTitle())
        g.SetFont("s10", "楷体")
        g.BackColor := "FFF8E7"

        ; ══ 左：侧栏 ══
        ; 先铺一块整高的底衬当「侧栏」，再往上面放控件 —— 控件按创建顺序层叠，
        ; 先建的在最底层。左侧不再是「一条孤零零的白列表浮在米色底上」，
        ; 而是有独立底色的一块区域（Windows 设置 / VS Code 都这么做）。
        ; ⚠ 侧栏里的 Text 一律把背景**写实**（BackgroundF2E8D2）而不是 BackgroundTrans：
        ;   透明 Text 每次重绘都要下面的控件先擦一遍，尺寸一变就留残影。
        ; 底色比窗口底（FFF8E7）深两档 —— 差一档实测几乎看不出分区。
        g.AddText("x0 y0 w232 h700 BackgroundF2E8D2", "")
        navTitle := g.AddText("x16 y16 w200 h18 c8A7F66 BackgroundF2E8D2", "导航")
        navTitle.SetFont("s9 bold")

        ; 两列：名称 / 本页热键条数。去掉表头（-Hdr）—— 导航不需要「名称 | 条数」
        ; 这种表头，两列只是让每一行多带一个可读的信息（这页有多少内容）。
        ; 「全部热键」是**视图**、下面的是**模块**，靠 ≡ 前缀 + 条数一眼区分。
        lv := g.AddListView("x16 y40 w200 h594 -Multi -Hdr", ["名称", "条数"])
        lv.ModifyCol(1, 148)
        lv.ModifyCol(2, "40 Right")

        ; 页脚：模块数 / 热键总数（控制面板惯例：导航底部给一行统计）
        foot := g.AddText("x16 y640 w200 h18 c8A7F66 BackgroundF2E8D2", "")
        foot.SetFont("s9")

        ; ══ 右：内容区 ══
        ; 标题分两级：页眉回答「我在哪一页」，副标题回答「这一页是干什么的」。
        ; 拆成两行而不是挤在一行里 —— 一行里模块名和描述字号不同、层级也就没了。
        head := g.AddText("x256 y14 w668 h26 c3D5166", "")
        head.SetFont("s12 bold")
        sub := g.AddText("x256 y44 w668 h18 c8A7F66", "")
        sub.SetFont("s9")

        ; 热键清单。用**只读 Edit** 而不是 Text —— Text 不能滚动、也选不中，
        ; 热键一多（笔记 27 条）就顶出窗口，正是「一坨看不清」的老毛病。
        hk := g.AddEdit("x256 y70 w668 h378 ReadOnly VScroll", "")
        hk.SetFont("s10", "Consolas")

        ; 状态行：保存 / 浏览的结果。**加粗 + 变色** —— 这是面板里唯一一处
        ; 「按钮到底有没有生效」的反馈，弱了就等于没反馈（原生按钮没有按下动画）。
        st := g.AddText("x256 y458 w520 h22 c7A6A50", "")
        st.SetFont("s10 bold")

        ; 右下角版本号：切到任何一页都看得到
        ver := g.AddText("x800 y460 w124 h20 cA8A08A Right", Config.AppName . " v" . Config.Version)
        ver.SetFont("s9")

        ; 设置区：标题 + 说明 +（字段在 _BuildSpec 里动态建）
        stTitle := g.AddText("x256 y486 w668 h24 c3D5166", "")
        stTitle.SetFont("s11 bold")
        stHint := g.AddText("x256 y510 w668 h32 c7A6A50", "")

        ; 底部操作栏：与侧栏同色的一条底带，从侧栏右沿铺到窗口右边，保存按钮嵌在里面。
        ; 没有它，按钮就「浮在空气里」—— 尤其没有设置字段的页，页尾一大片空白收不住。
        ; y648 起：设置字段最后一行到 642，不会被这条带盖住。
        g.AddText("x232 y648 w708 h52 BackgroundF2E8D2", "")

        ; 保存按钮：默认禁用（该页没有设置可存）。启用时加粗，让「这页能保存」一眼可见。
        saveBtn := g.AddButton("x808 y656 w116 h28", "保存设置")
        saveBtn.SetFont("s10 bold")
        saveBtn.Enabled := false

        ; 事件。ListView 的事件名是 ItemSelect（AHK v2 实测：Change 会抛
        ; "Parameter #1 of Gui.Control.Prototype.OnEvent is invalid"）。
        lv.OnEvent("ItemSelect", (*) => this._OnSelect())
        saveBtn.OnEvent("Click", (*) => this._SaveSpec())
        ; ⚠ 方法名是 _OnHelpClosed —— 这里曾误写成 _OnClosed（类里没这个方法），
        ;   点标题栏 × 时抛「没有这个方法」，句柄没清，下次 Alt+S 拿到悬空引用。
        g.OnEvent("Close", (*) => this._OnHelpClosed())

        this._gui := g
        this._lv := lv
        this._foot := foot
        this._head := head
        this._sub := sub
        this._hkEdit := hk
        this._status := st
        this._specTitle := stTitle
        this._specHint := stHint
        this._saveBtn := saveBtn

        ; ⚠ 定位在隐藏状态下做完再露面：先 Show 再 WinMove 会让窗口在默认落点
        ;   「飘一下」才跳到目标位置（.clinerules/03 实测 +31ms 出现、+219ms 才到位）。
        ; 内容也在露面**之前**填好 —— 否则第一帧是空列表 + 空右栏，看着像没加载出来。
        g.Show("w940 h700 Hide")
        this._PopulateList()
        this._CenterOnScreen()
        g.Show()
    }

    ; 面板摆到主屏工作区居中偏上 —— 不写死坐标，换显示器 / 改分辨率都不用改代码。
    static _CenterOnScreen() {
        rect := WindowProbe.PrimaryWorkArea()
        if !IsObject(rect)
            return
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)   ; Show("Hide") 过的窗口 WinGetPos 读不到
        try {
            WinGetPos(, , &w, &h, "ahk_id " . this._gui.Hwnd)
            ; ⚠ WinMove 收**物理像素**，与 WinGetPos 同单位；别用 Gui.Move —— 那会再乘一次 DPI。
            WinMove(rect.x + (rect.w - w) // 2, rect.y + (rect.h - h) // 3
                , , , "ahk_id " . this._gui.Hwnd)
        } catch as e {
            LogError("面板摆位失败：" . e.Message)
        } finally {
            DetectHiddenWindows(detectOld)
        }
    }

    ; Esc 不进模块热键表：只在面板激活时生效，关闭时立刻注销。
    ; ⚠ 声明了却没人实现回调的热键会「按了没反应」，所以注册失败要记日志。
    static _RegisterEsc() {
        title := this._PanelTitle()
        HotIfWinActive(title)
        try
            Hotkey("Esc", (*) => this._CloseHelp(), "On")
        catch as e {
            LogError("面板 Esc 注册失败：" . e.Message)
            HotIf()
            return false
        }
        HotIf()
        return true
    }


    ; ─── 帮助正文：平台 + 各模块 GetMetadata() 聚合 ───
    static BuildHotkeyHelpText() {
        entries := this._CollectEntries()
        text := ""
        for groupName in this._OrderedGroups(entries) {
            text .= "【" . groupName . "】`n"
            for entry in entries {
                if (entry.group != groupName)
                    continue
                text .= entry.hk.line . "`n"
                if entry.hk.HasProp("note")
                    text .= entry.hk.note . "`n"
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

    ; 收集平台热键 + 各模块元数据里的热键，按模块 order 稳定排序。
    ; 平台 order = 0；SevenNote / KeysInput / Launcher 的 order 由模块自己声明。
    static _CollectEntries() {
        entries := []
        seq := 0
        for hk in WorkBench.GetHotkeys() {
            entries.Push({order: 0, seq: seq, group: this._GroupOf(hk), hk: hk})
            seq += 1
        }

        for id, module in ModuleRegistry.All() {
            meta := this._MetadataOf(module)
            order := meta.HasProp("order") ? meta.order : 100
            if !meta.HasProp("hotkeys")
                continue
            for hk in meta.hotkeys {
                entries.Push({order: order, seq: seq, group: this._GroupOf(hk), hk: hk})
                seq += 1
            }
        }

        ; AHK v2.0 的 Array 没有 Sort 方法；条目最多几十条，插入排序足够且稳定。
        i := 1
        while i <= entries.Length {
            j := i
            while j > 1 && this._Before(entries[j], entries[j - 1]) {
                tmp := entries[j]
                entries[j] := entries[j - 1]
                entries[j - 1] := tmp
                j -= 1
            }
            i += 1
        }

        ; 同一 ctx + key 只保留第一次出现的那条（平台优先），防止新加模块
        ; 把平台热键又声明一遍时帮助里出现两行。
        result := []
        seenKeys := Map()
        for entry in entries {
            ctxName := entry.hk.HasProp("ctx") ? entry.hk.ctx : ""
            keyName := entry.hk.HasProp("key") ? entry.hk.key : ""
            uniq := ctxName . "|" . keyName
            if seenKeys.Has(uniq)
                continue
            seenKeys[uniq] := true
            result.Push(entry)
        }
        return result
    }

    static _Before(a, b) {
        if (a.order != b.order)
            return a.order < b.order
        return a.seq < b.seq
    }

    static _MetadataOf(module) {
        if module.HasMethod("GetMetadata")
            return module.GetMetadata()
        ; 兼容还没实现 GetMetadata 的模块：只提供 GetHotkeys 也能出现在帮助里。
        hotkeys := module.HasMethod("GetHotkeys") ? module.GetHotkeys() : []
        return {name: module.Id, desc: "", order: 100, hotkeys: hotkeys}
    }

    static _GroupOf(hk) => hk.HasProp("group") ? hk.group : "其他"

    static _OrderedGroups(entries) {
        groups := []
        seen := Map()
        for groupName in this._GroupOrder {
            if this._HasGroup(entries, groupName) {
                groups.Push(groupName)
                seen[groupName] := true
            }
        }
        ; 新模块自带的组：没在首选项里就按出现顺序追加
        for entry in entries {
            if !seen.Has(entry.group) {
                groups.Push(entry.group)
                seen[entry.group] := true
            }
        }
        return groups
    }

    static _HasGroup(entries, groupName) {
        for entry in entries {
            if (entry.group = groupName)
                return true
        }
        return false
    }

    ; ═══════════════════════════════════════════════════════════════════════
    ;  面板 · 左列：导航
    ; ═══════════════════════════════════════════════════════════════════════

    static _PopulateList() {
        this._lv.Delete()
        this._rowToId := Map()

        ; ── 第 1 行：「全部热键」视图。用 ≡ 前缀和「条数」与模块行区分 ——
        ;    它是视图不是模块，但也要有入口，所以留在同一列里靠符号分辨。
        ;    ⚠ 这里的条数含**平台级**热键（Alt+S 等），所以会比下面各模块之和多一些；
        ;      页脚用同一个口径，避免「40 与 42 谁对」这种疑问。
        overviewCount := this._CollectEntries().Length
        this._lv.Add("", "≡ 全部热键", overviewCount)
        this._rowToId[1] := this.OverviewId

        ; ── 模块行：按 GetMetadata().order 排；同 order 时按 Id 字典序 ——
        ;    这样「谁在前」永远确定，不依赖 Map 的遍历顺序。
        items := []
        for id, module in ModuleRegistry.All() {
            meta := this._MetadataOf(module)
            name := meta.HasProp("name") ? meta.name : id
            ; 启动失败的模块依然占一行：让它消失只会让用户以为「模块没了」
            if ModuleRegistry.IsFailed(id)
                name .= "(失败)"
            items.Push({
                id:    id,
                name:  name,
                order: meta.HasProp("order") ? meta.order : 100,
                count: meta.HasProp("hotkeys") ? meta.hotkeys.Length : 0
            })
        }
        this._SortItems(items)

        row := 2
        for it in items {
            this._lv.Add("", it.name, it.count)
            this._rowToId[row] := it.id
            row += 1
        }

        this._foot.Value := items.Length . " 个模块 · 共 " . overviewCount . " 条热键"

        ; 默认停在「全部热键」。此时窗口还是隐藏的（Show("Hide") 之后、Show() 之前），
        ; Focus 可能不生效；失败也无妨，列表和右栏都已经就位。
        this._currentModule := ""
        this._GoToRow(1)
    }

    ; 插入排序（AHK v2.0 的 Array 没有 Sort）。模块只有几个，稳定 + 够快。
    static _SortItems(items) {
        i := 1
        while i <= items.Length {
            j := i
            while (j > 1 && this._BeforeItem(items[j], items[j - 1])) {
                tmp := items[j]
                items[j] := items[j - 1]
                items[j - 1] := tmp
                j -= 1
            }
            i += 1
        }
    }

    ; order 小的在前；order 相同时按 Id 字典序 —— 不让顺序取决于登记顺序。
    static _BeforeItem(a, b) {
        if (a.order != b.order)
            return a.order < b.order
        return StrCompare(a.id, b.id) < 0
    }

    ; 定位到某一行并渲染。**面板里只有这一条路径会切页** ——
    ; 鼠标点、键盘上下、模块请求定位，全走这里，不留第二套状态。
    static _GoToRow(row) {
        if !row || !IsObject(this._rowToId)
            return
        id := this._rowToId.Has(row) ? this._rowToId[row] : ""
        if (id = "")
            return
        ; ⚠ 先写 _currentModule 再 Modify：Modify 会同步触发 ItemSelect，
        ;   那时 _OnSelect 看到「已经是这一页」就直接返回，不会渲染两遍。
        this._currentModule := id
        try this._lv.Modify(row, "Select Focus Vis")
        this._RenderModule(id)
    }

    static _OnSelect(*) {
        row := this._lv.GetNext()
        if !row
            return
        id := this._rowToId.Has(row) ? this._rowToId[row] : ""
        if (id = "" || id = this._currentModule)
            return
        this._RenderModule(id)
    }

    ; 事件入口：模块说「打开面板并定位到我一页」。
    ; 模块层不认识平台类，所以走事件 —— 这是 Feature → EventBus → 平台 的解耦写法。
    static _OnOpenRequested(data) {
        target := (IsObject(data) && data.HasProp("moduleId")) ? data.moduleId : ""
        this.ShowHelp()
        if (target != "")
            this.SelectModule(target)
    }

    ; 按模块 Id 定位到对应页。找不到就停在当前页、不报错 ——
    ; 模块可能没登记（被删掉 / Init 失败），那种情况不该让面板打不开。
    static SelectModule(id) {
        if !IsObject(this._lv) || !IsObject(this._rowToId)
            return
        for row, rowId in this._rowToId {
            if (rowId = id)
                return this._GoToRow(row)
        }
    }

    ; ═══════════════════════════════════════════════════════════════════════
    ;  面板 · 右列：热键清单 + 设置区
    ; ═══════════════════════════════════════════════════════════════════════

    static _RenderModule(id) {
        ; 先清掉上一页的设置控件，否则切两次模块就叠一层，越切越乱
        this._ClearSpec()
        this._StopSaveTimer()
        this._currentModule := id
        this._SetStatus("")

        ; ── 全部热键：改造前的 Alt+S 内容，按旧分组排列 ──
        ; 设置区不留白 —— 空标题 + 空说明看着像没加载出来。
        if (id = this.OverviewId) {
            this._head.Value := "全部热键"
            this._sub.Value := "所有模块的热键汇总 · 按分组排列"
            this._hkEdit.Value := this.BuildHotkeyHelpText()
            this._specTitle.Value := "使用说明"
            this._specHint.Value := "左侧选中一个模块，右侧只显示它的热键；模块声明了设置，字段会出现在下方。"
            this._saveBtn.Enabled := false
            return
        }

        module := ModuleRegistry.Get(id)
        if !IsObject(module) {
            this._head.Value := "未知模块"
            this._sub.Value := "这个模块不在登记表里：" . id
            this._hkEdit.Value := "（这个模块不在登记表里：" . id . "）"
            this._specTitle.Value := ""
            this._specHint.Value := ""
            this._saveBtn.Enabled := false
            return
        }

        ; 页眉 = 「我在哪一页」，副标题 = 「这一页是干什么的」。
        ; 拆成两级而不是挤在一行里 —— 一行里模块名和描述字号不同、层级也就没了。
        meta := this._MetadataOf(module)
        name := meta.HasProp("name") ? meta.name : id
        desc := meta.HasProp("desc") ? meta.desc : ""
        this._head.Value := name
        this._sub.Value := desc

        ; 启动失败的模块：热键一条都没注册。别把它渲染成一个看起来正常的页，
        ; 那会让人以为「热键没生效」是面板的错。
        if ModuleRegistry.IsFailed(id) {
            this._sub.Value := "启动失败 · 热键未注册"
            this._hkEdit.Value := "（该模块启动失败，热键未注册。详情见 .logs\_error.log）"
            this._specTitle.Value := "该模块当前不可用"
            this._specHint.Value := "模块初始化时抛了异常，平台跳过它、其它模块不受影响。修复后重启程序即可。"
            this._saveBtn.Enabled := false
            return
        }

        this._hkEdit.Value := this._BuildModuleText(meta)

        spec := this._SpecOf(module)
        if !IsObject(spec) {
            ; 没声明设置的模块：说清楚「这里没得调、去哪儿调」，别留一片空白让人以为坏了
            this._specTitle.Value := "该模块没有可调设置"
            this._specHint.Value := "这个模块的参数是写死的（或者由它自己的窗口管）；上面的热键随时可用。"
            this._saveBtn.Enabled := false
            return
        }
        this._BuildSpec(spec)
    }

    ; 单个模块的热键清单。按 GetHotkeys() 的声明顺序排，**不再二次分组** ——
    ; 一个模块通常只占 1~2 个组，再分组只会把两行字拆成三块。
    ; ⚠ 这里不写模块名与描述 —— 页眉（_head）已经显示，重复一遍纯属噪声。
    static _BuildModuleText(meta) {
        hotkeys := meta.HasProp("hotkeys") ? meta.hotkeys : []
        if !hotkeys.Length
            return "（该模块没有热键）"

        text := ""
        for hk in hotkeys {
            text .= hk.HasProp("line") ? hk.line : ("   " . hk.key)
            text .= "`n"
            if hk.HasProp("note")
                text .= hk.note . "`n"
        }
        return text
    }

    ; 模块可选的设置声明。没实现 / 返回非对象 → 面板只显示热键。
    static _SpecOf(module) {
        if !module.HasMethod("GetSettingsSpec")
            return ""
        try spec := module.GetSettingsSpec()
        catch as e {
            LogError("读取模块设置失败：" . module.Id . " —— " . e.Message)
            return ""
        }
        return IsObject(spec) ? spec : ""
    }

    ; 按声明建控件。平台只认 kind（渲染方式），不知道字段的业务含义。
    static _BuildSpec(spec) {
        this._specTitle.Value := spec.HasProp("title") ? spec.title : "设置"
        this._specHint.Value := spec.HasProp("hint") ? spec.hint : ""

        fields := spec.HasProp("fields") ? spec.fields : []
        y := this._specY
        for field in fields {
            ; 标签用实色背景（继承 Gui 底色）而不是 BackgroundTrans —— 透明 Text 每次
            ; 重绘都靠底下控件先擦，尺寸一变就留残影；侧栏里同一个坑已经踩过。
            label := this._gui.AddText("x" . this._Right . " y" . y . " w120 h26", field.label)
            ctrl := this._gui.AddEdit("x" . (this._Right + 126) . " y" . y . " w430 h26", field.value)
            ; 路径用等宽字体：楷体下 "l" 和 "1"、"/" 和 "\" 几乎分不清。
            ctrl.SetFont("s10", "Consolas")

            ; 可选：模块自己给的灰色占位提示（EM_SETCUEBANNER）。
            ; 提示只是显示，**不进 Value** —— 用户不填直接保存，写进去的仍是空串。
            if field.HasProp("placeholder")
                this._SetCue(ctrl, field.placeholder)

            browse := ""
            kind := field.HasProp("kind") ? field.kind : "text"
            if (kind = "folder") {
                browse := this._gui.AddButton("x" . (this._Right + this._RightW - 80) . " y" . (y - 1) . " w80 h28", "浏览…")
                ; ⚠ 闭包不能直接捕获循环变量（v2 捕获的是同一个变量，全部指向最后一轮），
                ;   用工厂函数把当前控件当参数传进去。
                browse.OnEvent("Click", this._BrowseHandler(ctrl))
            }
            this._specRows.Push({field: field, label: label, ctrl: ctrl, browse: browse})
            y += this._specRowH
        }

        this._specApply := spec.HasProp("apply") ? spec.apply : ""
        this._saveBtn.Enabled := (this._specApply != "")
    }

    static _BrowseHandler(ctrl) {
        return (*) => this._BrowseInto(ctrl)
    }

    static _BrowseInto(ctrl) {
        cur := ""
        try cur := ctrl.Value

        ; ⚠ 第 2 参数 0x41 = BIF_RETURNONLYFSDIRS(0x1) | BIF_NEWDIALOGSTYLE(0x40)。
        ;   传 0（改造前的写法）拿到的是**老式**对话框：没有地址栏、不能粘贴路径、
        ;   不能把文件夹拖进来、没有「新建文件夹」—— 这正是「可浏览范围小」的真正原因。
        ;   换成新式对话框后，全盘任意位置都能直达，范围不再受起点限制。
        ; ⚠ 本机 v2.0.27 的 DirSelect 只收 **3 个参数**（StartingFolder / Options / Prompt），
        ;   没有「父窗口」这一位 —— 传第 4 个直接抛 Too many parameters passed to function。
        ;   所以对话框压在面板下面这件事只能靠「面板不置顶」解决（见 _Build）。
        this._SetStatus("正在选择文件夹…", "dim")
        selected := ""
        try selected := DirSelect(this._BrowseStart(cur), 0x41
            , "选择这个槽位要打开的文件夹（地址栏可直接粘贴路径）")
        catch as e {
            LogError("打开文件夹选择框失败：" . e.Message)
            this._SetStatus("打不开文件夹选择框：" . e.Message, "err")
            return
        }

        if (selected = "") {
            this._SetStatus("已取消，输入框保持原值", "dim")
            return          ; 用户取消：保持原值，不做任何改动
        }

        selected := this._NormalizePath(selected)
        ctrl.Value := selected
        this._lastBrowse := selected

        ; 光回填输入框，很多人会以为已经生效了 —— 明确说一句，并把焦点送到保存按钮。
        this._SetStatus("已选择，记得点右边的「保存设置」", "warn")
        if IsObject(this._saveBtn) && this._saveBtn.Enabled
            try this._saveBtn.Focus()
    }

    ; 浏览框从哪开始看（纯判断，不碰窗口）。
    ; 优先级：输入框里已填的 → 上次浏览到的 → D 盘（本机资料盘）→ 我的文档
    ; （我的文档通常就在 C:\Users\<你>\Documents）。
    ; ⚠ 只决定「从哪开始看」，不限制能去哪 —— 新式对话框可以在地址栏输任意路径。
    static _BrowseStart(cur) {
        for p in [cur, this._lastBrowse] {
            if (p != "" && DirExist(p))
                return p
        }
        if DirExist("D:\")
            return "D:\"
        return A_MyDocuments
    }

    ; 给输入框加灰色占位提示（EM_SETCUEBANNER）。
    ; ⚠ 用 DllCall 发消息，别用内置 SendMessage() —— 它的第 4 参数是 Control 不是
    ;   WinTitle，传错位会报 Target window not found（.clinerules/03 有记）。
    static _SetCue(ctrl, text) {
        static EM_SETCUEBANNER := 0x1501
        try DllCall("SendMessage", "ptr", ctrl.Hwnd, "uint", EM_SETCUEBANNER
            , "ptr", 1, "wstr", text)
        ; 老系统上失败也无所谓：提示是锦上添花，不能因为它挡了建面板
    }

    ; 去两端空白与末尾反斜杠；盘根（D:\）保留反斜杠。
    ; 与 FolderSlotService.Normalize / ExplorerProbe.NormalizePath 同一套规则。
    static _NormalizePath(path) {
        p := RTrim(Trim(path), "\")
        if RegExMatch(p, "^[A-Za-z]:$")
            p .= "\"
        return p
    }

    ; 状态行统一出口：颜色按语义分档。
    ; ⚠ 别处直接 `_status.Value := ...` 会让颜色停在上一次的状态上 ——
    ;   保存成功（绿字）之后再报错仍然是绿的，比不报还误导。
    static _SetStatus(text, kind := "dim") {
        if !IsObject(this._status)
            return
        color := "7A6A50"
        if (kind = "ok")
            color := "0A7A2B"
        else if (kind = "err")
            color := "B00020"
        else if (kind = "warn")
            color := "8A5A00"
        try this._status.Opt("c" . color)
        this._status.Value := text
    }

    ; 销毁上一页的设置控件（输入框 / 标签 / 浏览按钮）
    ; ⚠ AHK v2 的 `Gui.Control` **没有 `Destroy()` 方法** —— `Destroy()` 是 `Gui` 对象的方法。
    ;   写成 `ctrl.Destroy()` 会抛「方法不存在」，又被这里的 `try` 吞掉，静默失败：
    ;   表现为「从「文件夹」切到「文本」，三个 Alt+1/2/3 字段还挂在那儿、保存按钮仍是启用态」
    ;   （2026-10-21 实测：探针打出 rows=3 destroyedCtrl=0 才定位到）。
    ;   单个控件只能用 DestroyWindow 销毁 —— GUI 与调用方同线程，安全。
    static _ClearSpec() {
        for row in this._specRows {
            this._KillCtrl(row.ctrl)
            this._KillCtrl(row.label)
            this._KillCtrl(row.browse)
        }
        this._specRows := []
        this._specApply := ""
    }

    static _KillCtrl(ctrl) {
        if !IsObject(ctrl)
            return              ; browse 在非 folder 字段上是空串
        try DllCall("DestroyWindow", "ptr", ctrl.Hwnd)
    }

    ; 保存：按声明顺序把输入框的值交回模块，由模块自己决定怎么落盘。
    static _SaveSpec() {
        ; ⚠ 必须先取到局部变量：AHK v2 的 obj.prop(args) 走**方法查找**，
        ;   属性里存的 Func 不会被调用，会抛 "Too many parameters passed to function"
        ;   且容易被外层 try 吞掉（.clinerules/03 有记）。
        fn := this._specApply
        if !IsObject(fn) {
            this._SetStatus("该模块没有可保存的设置", "warn")
            return
        }

        values := []
        for row in this._specRows
            try values.Push(Trim(row.ctrl.Value))

        ; 即刻反馈：按下立刻变「保存中…」并禁用，出结果后亮成「✓ 已保存」。
        ; 原生按钮没有按下动画，不做这一步，点了就像没点。
        this._ShowSaveBusy("保存中…")

        try ok := fn(values)
        catch as e {
            LogError("保存模块设置失败：" . this._currentModule . " —— " . e.Message)
            this._SetStatus("保存失败：" . e.Message, "err")
            this._ShowSaveResult("✗ 失败")
            return
        }

        if !ok {
            this._SetStatus("保存失败：配置目录不可写（详见 _error.log）", "err")
            this._ShowSaveResult("✗ 失败")
            return
        }

        ; 保存后重画本页：模块可能在 apply 里把值规整过（去尾斜杠 / 空串归一），
        ; 不重画的话输入框里还是用户刚才乱写的样子。
        ; ⚠ _RenderModule 会清状态行，所以「已保存」这句必须写在它之后。
        id := this._currentModule
        this._RenderModule(id)
        this._SetStatus("✓ 已保存，下次按热键即生效", "ok")
        this._ShowSaveResult("✓ 已保存")
    }

    ; ─── 保存按钮的三段状态 ───
    ; 「保存设置」→「保存中…」→「✓ 已保存」→（1.2 秒后）「保存设置」。
    static _ShowSaveBusy(text) {
        this._StopSaveTimer()
        if !IsObject(this._saveBtn)
            return
        this._saveBtn.Text := text
        this._saveBtn.Enabled := false
    }

    static _ShowSaveResult(text) {
        this._ShowSaveBusy(text)
        if !IsObject(this._saveBtn)
            return
        ; 闭包必须存到字段：每次新建的箭头函数是新对象，SetTimer(fn, 0) 停不掉。
        this._saveTimer := () => this._ResetSaveButton()
        timerFn := this._saveTimer
        SetTimer(timerFn, -1200)
    }

    ; 定时器到点：面板可能已被用户关掉（Esc / 标题栏 ×），先过闸再碰控件。
    static _ResetSaveButton() {
        this._saveTimer := ""
        if !IsObject(this._saveBtn)
            return
        this._saveBtn.Text := "保存设置"
        this._saveBtn.Enabled := IsObject(this._specApply)
    }

    static _StopSaveTimer() {
        if (this._saveTimer = "")
            return
        timerFn := this._saveTimer
        this._saveTimer := ""
        try SetTimer(timerFn, 0)
    }

    ; ─── 关闭 / 注销 ───
    static _CloseHelp() {
        this._UnregisterEsc()
        this._ClearSpec()
        guiObj := this._gui
        this._ResetHandles()
        if IsObject(guiObj)
            try guiObj.Destroy()
    }

    ; 标题栏关闭：只清 Esc 与句柄，窗口由 Gui 默认 Close 行为销毁
    static _OnHelpClosed() {
        this._UnregisterEsc()
        this._ClearSpec()
        this._ResetHandles()
    }

    ; 所有控件句柄一起置空：窗口没了以后它们都是悬空引用，
    ; 留着下一个 `_status.Value := ...` 就会抛 "not an object"。
    static _ResetHandles() {
        this._StopSaveTimer()
        this._gui := ""
        this._lv := ""
        this._foot := ""
        this._head := ""
        this._sub := ""
        this._hkEdit := ""
        this._status := ""
        this._specTitle := ""
        this._specHint := ""
        this._saveBtn := ""
        this._rowToId := ""
        this._currentModule := ""
    }

    static _UnregisterEsc() {
        if !this._escRegistered
            return
        this._escRegistered := false
        try {
            HotIfWinActive(this._PanelTitle())
            Hotkey("Esc", "Off")
        } catch as e {
            LogError("面板 Esc 注销失败：" . e.Message)
        }
        HotIf()
    }
}