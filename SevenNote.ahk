#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()

; ═══════════════════════════════════════════════════════════════════════════
;  SevenNote —— v1.9
;  本地单文件速记工具。RichEdit 富文本编辑 + 双 RTF 存储 + Markdown 输出。
;
;  【v1.9 修复】
;    · FileInstall 强制一行 + 大小检查（修复 0KB 坏 pandoc 打包问题）
;    · PandocService.GetCmd / IsAvailable 加文件大小检查（> 1MB 才用）
;    · 组合根释放 pandoc 前先删旧文件（避免 0KB 坏文件阻塞）
;
;  【v1.8 保留】
;    · 状态栏日期后显示星期：📅 2026-09-20 周日
;
;  【v1.7 保留】
;    · assets 统一收纳到 _assets/日期/ 下
;    · 切日期 / 跳转 / 启动加载后，有内容的笔记光标到开头 + 视口到顶
;
;  【整体架构 —— 四层 + 组合根】
;    FEATURE 功能层 → SERVICE 服务层 → KERNEL 骨架层 → 表示层组件 → 组合根
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
;
;  【已知坑点】
;    · AHK v2 内置函数名不能做变量名（Clear/log/min/max/Indent）
;    · AHK v2 的 < > 是数值比较，字符串比较用 StrCompare
;    · EM_SETSEL/EM_GETSEL 用 DllCall 4 参数版本
;    · FINDTEXTEXW 读偏移 16/20（chrgText）
;    · 32 位编译导致 RichEdit 字符格式异常——必须 64 位
;    · FileInstall 必须一行，源路径不存在会打包 0KB 空文件（v1.9）
;    · 启动终端别传 Run 的 "Hide"：隐藏启动会绕过 Windows Terminal 委派，终端退回
;      conhost 默认（120x50 = 1488x1256、#012456 蓝底），拿不到 WT profile 的星空背景
;
;  依赖：pandoc.exe（软依赖，未安装则 MD 降级为纯文本）
; ═══════════════════════════════════════════════════════════════════════════


; ═══════════════════════════════════════════════════════════════════════════
;  KERNEL 骨架层
; ═══════════════════════════════════════════════════════════════════════════

class Config {
    static AppName := "SevenNote"
    static Version := "2.1.1"

    static AppDataDir := A_AppData . "\SevenNote-Dev"
    static ConfigPath := A_AppData . "\SevenNote-Dev\_config.ini"
    static PandocPath := A_AppData . "\SevenNote\pandoc.exe"

    static GetVault() {
        v := ConfigService.Read("Paths", "Vault")
        if (v = "")
            return A_MyDocuments . "\SevenNote"
        return v
    }
    static SetVault(path) => ConfigService.Write("Paths", "Vault", path)

    static WinW := 450
    static WinH := 550
    ; 首次呼出时窗口距屏幕工作区右边 / 顶边的距离（物理像素）
    static PlaceRight := 15
    static PlaceTop := 264
    static AutoSaveInterval := 120000
    static StatInterval := 500
    static TimestampInterval := 60
    ; 双窗并存（Alt+C 唤起 PowerShell / Alt+X 唤起 DeepSeek）时的「可见」间距（物理像素）：
    ; 两窗之间的缝、窗口到工作区顶/底的边距。
    ; ⚠ 这里算的是**肉眼看到**的距离 —— 按 DWM 的可见边界算，不含 Win11 的不可见调整边框。
    ;   本机实测 `WinGetPos` 的矩形比可见边界每边多 9px（左 −9 / 上 0 / 右 9 / 下 9），
    ;   若直接按矩形拼，设 12 的缝看上去会是 12 + 9 = 21。
    static DockGap := 6
    static DockMargin := 10
}


class ConfigService {
    static _path := ""
    static _defaults := Map()

    static Init(path) {
        this._path := path
    }

    static SetDefault(section, key, value) {
        this._defaults[section . "|" . key] := value
    }

    static Read(section, key) {
        if !this._path
            return ""
        try {
            val := IniRead(this._path, section, key, "")
        } catch {
            val := ""
        }
        if (val = "") {
            dk := section . "|" . key
            if this._defaults.Has(dk)
                return this._defaults[dk]
            return ""
        }
        return val
    }

    static ReadInt(section, key, default := 0) {
        v := this.Read(section, key)
        if (v = "")
            return default
        try return Integer(v)
        catch
            return default
    }

    static Write(section, key, value) {
        if !this._path
            return false
        try {
            IniWrite(value, this._path, section, key)
            return true
        } catch {
            return false
        }
    }
}


class EventBus {
    static handlers := Map()

    static On(event, fn) {
        if !this.handlers.Has(event)
            this.handlers[event] := []
        this.handlers[event].Push(fn)
    }

    static Emit(event, data := "") {
        if !this.handlers.Has(event)
            return
        for fn in this.handlers[event]
            try fn(data)
    }
}


class State {
    static _guiObj := ""
    static _edHwnd := 0
    static _statObj := ""
    static _loadedDate := ""
    static _caretMin := -1
    static _caretMax := -1

    static _hiddenX := ""
    static _hiddenY := ""
    static _hiddenW := ""
    static _hiddenH := ""

    static _dateCtrl := ""
    static _msgCtrl := ""
    static _themeLabel := ""
    static _tagCtrl := ""

    static GetGui() => this._guiObj
    ; 供 #HotIf 等表达式安全取主窗口句柄：GUI 尚未创建时返回 0
    ; （否则 "".Hwnd 会抛 "String has no property named Hwnd"）
    static GetGuiHwnd() => IsObject(this._guiObj) ? this._guiObj.Hwnd : 0
    static SetGui(g) {
        this._guiObj := g
        EventBus.Emit("Gui.Ready", g)
    }

    static GetEd() => this._edHwnd
    static SetEd(hwnd) {
        this._edHwnd := hwnd
        EventBus.Emit("Editor.Ready", hwnd)
    }

    static GetStat() => this._statObj
    static SetStat(s) => this._statObj := s

    static GetDateCtrl() => this._dateCtrl
    static SetDateCtrl(c) => this._dateCtrl := c
    static GetMsgCtrl() => this._msgCtrl
    static SetMsgCtrl(c) => this._msgCtrl := c
    static GetThemeLabel() => this._themeLabel
    static SetThemeLabel(c) => this._themeLabel := c
    static GetTagCtrl() => this._tagCtrl
    static SetTagCtrl(c) => this._tagCtrl := c

    static GetDate() => this._loadedDate
    static SetDate(d) {
        old := this._loadedDate
        this._loadedDate := d
        EventBus.Emit("Date.Changed", {old: old, new: d})
    }

    static GetCaret() => {min: this._caretMin, max: this._caretMax}
    static SetCaret(min, max) {
        this._caretMin := min
        this._caretMax := max
    }
    static HasCaret() => this._caretMin >= 0
    static ResetCaret() {
        this._caretMin := -1
        this._caretMax := -1
    }

    static GetHiddenRect() => {
        x: this._hiddenX, y: this._hiddenY,
        w: this._hiddenW, h: this._hiddenH
    }
    static SetHiddenRect(x, y, w, h) {
        this._hiddenX := x
        this._hiddenY := y
        this._hiddenW := w
        this._hiddenH := h
    }
    static HasHiddenRect() => (this._hiddenX != "")
    static ClearHiddenRect() {
        this._hiddenX := ""
        this._hiddenY := ""
        this._hiddenW := ""
        this._hiddenH := ""
    }
}


; ═══════════════════════════════════════════════════════════════════════════
;  SERVICE 服务层
; ═══════════════════════════════════════════════════════════════════════════

class EditorService {
    static CLOCK := Chr(0x1F550)
    static SEPARATOR := "--------------------"
    static INDENT_STR := "    "

    static NormalizeNL(s) {
        s := StrReplace(s, "`r`n", "`n")
        s := StrReplace(s, "`r", "`n")
        return s
    }

    static GetText(hwnd) {
        len := SendMessage(0x000E, 0, 0, hwnd)
        if (len = 0)
            return ""
        buf := Buffer((len + 1) * 2, 0)
        SendMessage(0x000D, len + 1, buf.Ptr, hwnd)
        return this.NormalizeNL(StrGet(buf, "UTF-16"))
    }

    static GetLength(hwnd) => SendMessage(0x000E, 0, 0, hwnd)

    static SetText(hwnd, text) {
        SendMessage(0x00B1, 0, -1, hwnd)
        SendMessage(0x00C2, 1, StrPtr(this.NormalizeNL(text)), hwnd)
        this.MoveCaretToEnd(hwnd)
    }

    static InsertText(hwnd, text) {
        SendMessage(0x00C2, 1, StrPtr(this.NormalizeNL(text)), hwnd)
    }

    static MoveCaretToEnd(hwnd) {
        len := SendMessage(0x000E, 0, 0, hwnd)
        SendMessage(0x00B1, len, len, hwnd)
    }

    ; ─── 光标到开头 + 视口到顶 ───（v1.7）
    static MoveCaretToStart(hwnd) {
        SendMessage(0x00B1, 0, 0, hwnd)
        firstVisible := SendMessage(0x00CE, 0, 0, hwnd)
        if (firstVisible > 0)
            SendMessage(0x00B6, 0, -firstVisible, hwnd)
    }

    static EmptyUndo(hwnd) => SendMessage(0x00C6, 0, 0, hwnd)

    static GetSel(hwnd) {
        bufMin := Buffer(4, 0)
        bufMax := Buffer(4, 0)
        DllCall("SendMessage", "ptr", hwnd, "uint", 0x00B0
            , "ptr", bufMin.Ptr, "ptr", bufMax.Ptr, "ptr")
        return {
            min: NumGet(bufMin, 0, "uint"),
            max: NumGet(bufMax, 0, "uint")
        }
    }

    static SetSel(hwnd, min, max) {
        SendMessage(0x00B1, min, max, hwnd)
    }

    static GetTextRange(hwnd, cpMin, cpMax) {
        len := cpMax - cpMin
        if (len <= 0)
            return ""
        buf := Buffer((len + 1) * 2, 0)
        tr := Buffer(16)
        NumPut("int", cpMin, tr, 0)
        NumPut("int", cpMax, tr, 4)
        NumPut("ptr", buf.Ptr, tr, 8)
        copied := SendMessage(0x044B, 0, tr, hwnd)
        return this.NormalizeNL(StrGet(buf, copied, "UTF-16"))
    }

    static GetLineRange(hwnd) {
        sel := this.GetSel(hwnd)
        cpMin := sel.min
        cpMax := sel.max
        startLine := SendMessage(0x00C9, cpMin, 0, hwnd)
        endLine := SendMessage(0x00C9, cpMax, 0, hwnd)
        if (cpMax > cpMin) {
            prevLine := SendMessage(0x00C9, cpMax - 1, 0, hwnd)
            if (prevLine < endLine)
                endLine := prevLine
        }
        lineStart := SendMessage(0x00BB, startLine, 0, hwnd)
        nextStart := SendMessage(0x00BB, endLine + 1, 0, hwnd)
        if (nextStart = -1)
            lineEnd := SendMessage(0x000E, 0, 0, hwnd)
        else
            lineEnd := nextStart
        return {start: lineStart, end: lineEnd
            , startLine: startLine, endLine: endLine}
    }

    static DeleteCurrentLine(hwnd) {
        range := this.GetLineRange(hwnd)
        if (range.start = range.end)
            return
        this.SetSel(hwnd, range.start, range.end)
        SendMessage(0x00C2, 1, StrPtr(""), hwnd)
    }

    static DuplicateCurrentLine(hwnd) {
        range := this.GetLineRange(hwnd)
        text := this.GetTextRange(hwnd, range.start, range.end)
        if (text = "")
            return
        hasNewline := RegExMatch(text, "\n$")
        insertText := hasNewline ? text : "`n" . text
        this.SetSel(hwnd, range.end, range.end)
        SendMessage(0x00C2, 1, StrPtr(insertText), hwnd)
        if hasNewline
            this.SetSel(hwnd, range.end, range.end + StrLen(insertText))
        else
            this.SetSel(hwnd, range.end + 1, range.end + StrLen(insertText))
    }

    static Undo(hwnd) => SendMessage(0x00C7, 0, 0, hwnd)
    static Redo(hwnd) => SendMessage(0x0454, 0, 0, hwnd)

    static SwapLines(hwnd, lineStart, lineMid, lineEnd) {
        first := this.GetTextRange(hwnd, lineStart, lineMid)
        second := this.GetTextRange(hwnd, lineMid, lineEnd)
        firstHasNL := RegExMatch(first, "\n$")
        secondHasNL := RegExMatch(second, "\n$")
        firstClean := RTrim(first, "`n")
        secondClean := RTrim(second, "`n")
        newFirst := secondClean
        newSecond := firstClean
        if firstHasNL
            newFirst .= "`n"
        if secondHasNL
            newSecond .= "`n"
        SendMessage(0x00B1, lineStart, lineEnd, hwnd)
        SendMessage(0x00C2, 1, StrPtr(newFirst . newSecond), hwnd)
    }

    static MoveLineUp(hwnd) {
        range := this.GetLineRange(hwnd)
        if (range.startLine = 0)
            return false
        prevStart := SendMessage(0x00BB, range.startLine - 1, 0, hwnd)
        lineStart := SendMessage(0x00BB, range.startLine, 0, hwnd)
        lineEnd := SendMessage(0x00BB, range.endLine + 1, 0, hwnd)
        if (lineEnd = -1)
            lineEnd := SendMessage(0x000E, 0, 0, hwnd)
        this.SwapLines(hwnd, prevStart, lineStart, lineEnd)
        newLineStart := SendMessage(0x00BB, range.startLine - 1, 0, hwnd)
        this.SetSel(hwnd, newLineStart, newLineStart)
        return true
    }

    static MoveLineDown(hwnd) {
        range := this.GetLineRange(hwnd)
        nextStart := SendMessage(0x00BB, range.endLine + 1, 0, hwnd)
        if (nextStart = -1)
            return false
        nextEnd := SendMessage(0x00BB, range.endLine + 2, 0, hwnd)
        if (nextEnd = -1)
            nextEnd := SendMessage(0x000E, 0, 0, hwnd)
        lineStart := SendMessage(0x00BB, range.startLine, 0, hwnd)
        this.SwapLines(hwnd, lineStart, nextStart, nextEnd)
        newLineStart := SendMessage(0x00BB, range.startLine + 1, 0, hwnd)
        this.SetSel(hwnd, newLineStart, newLineStart)
        return true
    }

    static DoIndent(hwnd) {
        sel := this.GetSel(hwnd)
        if (sel.min = sel.max) {
            SendMessage(0x00C2, 1, StrPtr(this.INDENT_STR), hwnd)
            return
        }
        range := this.GetLineRange(hwnd)
        positions := []
        line := range.endLine
        while (line >= range.startLine) {
            pos := SendMessage(0x00BB, line, 0, hwnd)
            if (pos = -1)
                break
            positions.Push(pos)
            line--
        }
        for pos in positions {
            this.SetSel(hwnd, pos, pos)
            SendMessage(0x00C2, 1, StrPtr(this.INDENT_STR), hwnd)
        }
        count := positions.Length
        indentLen := StrLen(this.INDENT_STR)
        newStart := range.start + indentLen
        newEnd := range.end + count * indentLen
        this.SetSel(hwnd, newStart, newEnd)
    }

    static DoOutdent(hwnd) {
        sel := this.GetSel(hwnd)
        range := this.GetLineRange(hwnd)
        firstLineRemoved := 0
        totalRemoved := 0
        line := range.endLine
        while (line >= range.startLine) {
            pos := SendMessage(0x00BB, line, 0, hwnd)
            if (pos = -1)
                break
            nextPos := SendMessage(0x00BB, line + 1, 0, hwnd)
            if (nextPos = -1)
                nextPos := SendMessage(0x000E, 0, 0, hwnd)
            lineText := this.GetTextRange(hwnd, pos, nextPos)
            removed := 0
            if (SubStr(lineText, 1, 4) = "    ")
                removed := 4
            else if (SubStr(lineText, 1, 1) = "`t")
                removed := 1
            if (removed > 0) {
                this.SetSel(hwnd, pos, pos + removed)
                SendMessage(0x00C2, 1, StrPtr(""), hwnd)
                totalRemoved += removed
                if (line = range.startLine)
                    firstLineRemoved := removed
            }
            line--
        }
        if (sel.min = sel.max) {
            newPos := sel.min - totalRemoved
            if (newPos < range.start)
                newPos := range.start
            this.SetSel(hwnd, newPos, newPos)
        } else {
            newStart := sel.min - firstLineRemoved
            if (newStart < range.start)
                newStart := range.start
            newEnd := sel.max - totalRemoved
            if (newEnd < newStart)
                newEnd := newStart
            this.SetSel(hwnd, newStart, newEnd)
        }
    }

    static FindLastTimestamp(hwnd) {
        text := this.GetText(hwnd)
        return this.FindLastTimestampInText(text)
    }

    static FindLastTimestampInText(text) {
        lastMin := -1
        p := 1
        while ((p := InStr(text, this.CLOCK,, p)) > 0) {
            rest := SubStr(text, p + 2)
            if RegExMatch(rest, "^\s*(\d{2}):(\d{2})", &m) {
                lastMin := m[1] * 60 + m[2]
            }
            p++
        }
        return lastMin
    }

    static DiffMinutes(nowMin, lastMin) {
        return Mod(nowMin - lastMin + 1440, 1440)
    }

    static AppendTimestamp(hwnd) {
        text := this.GetText(hwnd)
        trimmed := RTrim(text, "`t`r`n")
        if (StrLen(trimmed) < StrLen(text))
            this.SetText(hwnd, trimmed)
        this.MoveCaretToEnd(hwnd)
        now := FormatTime(, "HH:mm")
        this.InsertText(hwnd, "`n`n" . this.CLOCK . " " . now . "`n")
    }

    static StripEmptyTimestamp(hwnd) {
        text := this.GetText(hwnd)
        pattern := "\s*" . this.CLOCK . "\s+\d{2}:\d{2}\s*$"
        if RegExMatch(text, pattern, &m) {
            sel := this.GetSel(hwnd)
            firstVisible := SendMessage(0x00CE, 0, 0, hwnd)
            prefix := SubStr(text, 1, m.Pos - 1)
            delStart := StrLen(prefix)
            totalLen := SendMessage(0x000E, 0, 0, hwnd)
            this.SetSel(hwnd, delStart, totalLen)
            SendMessage(0x00C2, 1, StrPtr(""), hwnd)
            newLen := SendMessage(0x000E, 0, 0, hwnd)
            newMin := Min(sel.min, newLen)
            newMax := Min(sel.max, newLen)
            this.SetSel(hwnd, newMin, newMax)
            newFirst := SendMessage(0x00CE, 0, 0, hwnd)
            if (newFirst != firstVisible)
                SendMessage(0x00B6, 0, firstVisible - newFirst, hwnd)
            return true
        }
        return false
    }

    static InsertSeparator(hwnd) {
        sel := this.GetSel(hwnd)
        if (sel.min = 0) {
            this.InsertText(hwnd, this.SEPARATOR . "`n`n")
            return
        }
        prevChar := this.GetTextRange(hwnd, sel.min - 1, sel.min)
        if (prevChar = "`n")
            this.InsertText(hwnd, this.SEPARATOR . "`n`n")
        else
            this.InsertText(hwnd, "`n" . this.SEPARATOR . "`n`n")
    }

    static InsertHeading(hwnd) {
        sel := this.GetSel(hwnd)
        if (sel.min = 0) {
            this.InsertText(hwnd, "## 分段`n`n")
            return
        }
        prevChar := this.GetTextRange(hwnd, sel.min - 1, sel.min)
        if (prevChar = "`n")
            this.InsertText(hwnd, "## 分段`n`n")
        else
            this.InsertText(hwnd, "`n## 分段`n`n")
    }

    static FindTextEx(hwnd, keyword, startPos, direction) {
        if (keyword = "")
            return -1
        ftBuf := Buffer(32, 0)
        if (direction = "down") {
            NumPut("int", startPos, ftBuf, 0)
            NumPut("int", -1, ftBuf, 4)
            flags := 0x00000001
        } else {
            NumPut("int", -1, ftBuf, 0)
            NumPut("int", startPos, ftBuf, 4)
            flags := 0
        }
        strBuf := Buffer((StrLen(keyword) + 1) * 2, 0)
        StrPut(keyword, strBuf, "UTF-16")
        NumPut("ptr", strBuf.Ptr, ftBuf, 8)
        ret := SendMessage(0x047C, flags, ftBuf.Ptr, hwnd)
        if (ret = -1)
            return -1
        return {
            start: NumGet(ftBuf, 8 + A_PtrSize, "int"),
            end:   NumGet(ftBuf, 12 + A_PtrSize, "int")
        }
    }

    static ScrollToLineFixed(hwnd, targetLine) {
        rect := Buffer(16, 0)
        SendMessage(0x00B2, 0, rect.Ptr, hwnd)
        clientH := NumGet(rect, 12, "int") - NumGet(rect, 4, "int")
        lineHeight := 20
        visibleLines := clientH // lineHeight
        if (visibleLines < 3)
            visibleLines := 3
        targetPosition := visibleLines // 4
        targetFirst := targetLine - targetPosition
        if (targetFirst < 0)
            targetFirst := 0
        firstVisible := SendMessage(0x00CE, 0, 0, hwnd)
        delta := targetFirst - firstVisible
        if (delta != 0)
            SendMessage(0x00B6, 0, delta, hwnd)
    }

    static SaveRTFToFile(hwnd, filePath, codepage := 936) {
        file := FileOpen(filePath, "w", "CP1252")
        if !file
            return false
        global _streamFile
        _streamFile := file
        cb := CallbackCreate(StreamOutCallback, , 4)
        es := Buffer(A_PtrSize * 2 + 4, 0)
        NumPut("ptr", 0, es, 0)
        NumPut("uint", 0, es, A_PtrSize)
        NumPut("ptr", cb, es, A_PtrSize + 4)
        flags := 0x0002 | 0x0020 | (codepage << 16)
        result := SendMessage(0x044A, flags, es.Ptr, hwnd)
        CallbackFree(cb)
        file.Close()
        _streamFile := ""
        return result != 0
    }

    static LoadRTFFromFile(hwnd, filePath, moveCaretToStart := true) {
        if !FileExist(filePath)
            return false
        file := FileOpen(filePath, "r", "CP1252")
        if !file
            return false
        global _streamFile
        _streamFile := file
        cb := CallbackCreate(StreamInCallback, , 4)
        es := Buffer(A_PtrSize * 2 + 4, 0)
        NumPut("ptr", 0, es, 0)
        NumPut("uint", 0, es, A_PtrSize)
        NumPut("ptr", cb, es, A_PtrSize + 4)
        flags := 0x0002
        result := SendMessage(0x0449, flags, es.Ptr, hwnd)
        CallbackFree(cb)
        file.Close()
        _streamFile := ""
        SendMessage(0x0453, 100, 0, hwnd)

        totalLen := SendMessage(0x000E, 0, 0, hwnd)
        if (moveCaretToStart && totalLen > 0) {
            this.MoveCaretToStart(hwnd)
        } else {
            this.MoveCaretToEnd(hwnd)
        }
        return result != 0
    }

    static IsEmptyNote(hwnd, date) {
        text := this.GetText(hwnd)
        text := StrReplace(text, "# 📅 " . date . " 速记", "")
        text := RegExReplace(text
            , "\s*" . this.CLOCK . "\s+\d{2}:\d{2}\s*", "")
        text := RegExReplace(text, "\s+", "")
        return (text = "")
    }
}

StreamOutCallback(cookie, pbBuff, byteCount, pcb) {
    global _streamFile
    try {
        written := _streamFile.RawWrite(pbBuff, byteCount)
        NumPut("int", written, pcb, "int")
        return 0
    } catch {
        NumPut("int", 0, pcb, "int")
        return 1
    }
}

StreamInCallback(cookie, pbBuff, byteCount, pcb) {
    global _streamFile
    try {
        read := _streamFile.RawRead(pbBuff, byteCount)
        NumPut("int", read, pcb, "int")
        return 0
    } catch {
        NumPut("int", 0, pcb, "int")
        return 1
    }
}
; ═══════════════════════════════════════════════════════════════════════════
;  SERVICE 服务层（续）
; ═══════════════════════════════════════════════════════════════════════════

class ClipboardService {
    static GetText() {
        try return A_Clipboard
        catch
            return ""
    }
}


; ─── NoteStoreService：笔记仓库管理员 ───
class NoteStoreService {
    ; ─── 路径拼接 ───
    static RtfPath(date)    => Config.GetVault() . "\" . date . ".rtf"
    static MdPath(date)     => Config.GetVault() . "\" . date . ".md"

    ; assets 统一收纳到 _assets/日期/ 下（只按日期，不含标签）
    static AssetsDir(date)  => Config.GetVault() . "\_assets\" . date

    static TempDir()        => Config.GetVault() . "\_tmp"

    static EnsureDir(path) => DirCreate(path)

    static WriteFile(path, content, encoding := "UTF-8") {
        try {
            f := FileOpen(path, "w", encoding)
            f.Write(content)
            f.Close()
            return true
        } catch
            return false
    }

    ; ─── 默认路径（无标签时用）───
    static DefaultRtfPath(date) => Config.GetVault() . "\" . date . ".rtf"
    static DefaultMdPath(date)  => Config.GetVault() . "\" . date . ".md"

    ; ─── 按日期查找实际文件（可能带标签）───
    static FindRtf(date) {
        if (date = "")
            return ""
        Loop Files, Config.GetVault() . "\" . date . "*.rtf" {
            if (SubStr(A_LoopFileName, 1, 1) = "_")
                continue
            if (SubStr(A_LoopFileName, 1, 10) = date)
                return A_LoopFileFullPath
        }
        return ""
    }

    static FindMd(date) {
        if (date = "")
            return ""
        Loop Files, Config.GetVault() . "\" . date . "*.md" {
            if (SubStr(A_LoopFileName, 1, 1) = "_")
                continue
            if (SubStr(A_LoopFileName, 1, 10) = date)
                return A_LoopFileFullPath
        }
        return ""
    }

    ; ─── 日期 → 中文星期 ───（v1.8）
    ; FormatTime 返回字符串（"1"~"7"），必须用 +0 强制转数字
    static GetWeekday(date) {
        ymd := StrReplace(date, "-", "")
        wd := FormatTime(ymd, "WDay") + 0
        switch wd {
            case 1: return "周日"
            case 2: return "周一"
            case 3: return "周二"
            case 4: return "周三"
            case 5: return "周四"
            case 6: return "周五"
            case 7: return "周六"
        }
        return ""
    }

    ; ─── 清理标签中的非法字符 ───
    static SanitizeTag(tag) {
        tag := Trim(tag)
        tag := RegExReplace(tag, '[\\/:*?"<>|]', "_")
        tag := RegExReplace(tag, "\s+", " ")
        if (StrLen(tag) > 50)
            tag := SubStr(tag, 1, 50)
        return tag
    }

    ; ─── 从文件名提取标签 ───
    static TagFromFileName(fileNameOrPath) {
        name := ""
        SplitPath(fileNameOrPath, &name)
        name := RegExReplace(name, "\.\w+$", "")
        if (StrLen(name) <= 10)
            return ""
        if (SubStr(name, 11, 1) != "-")
            return ""
        return SubStr(name, 12)
    }

    ; ─── 枚举所有标签（扫 Vault 目录）───
    static ListAllTags() {
        result := []
        Loop Files, Config.GetVault() . "\*.md" {
            name := A_LoopFileName
            if (SubStr(name, 1, 1) = "_")
                continue
            if !RegExMatch(name, "^(\d{4}-\d{2}-\d{2})(?:-(.+))?\.md$", &m)
                continue
            date := m[1]
            tag := (m.Count >= 2 && m[2] != "") ? m[2] : ""
            result.Push({date: date, tag: tag})
        }
        ; 按日期倒序（字符串比较用 StrCompare）
        n := result.Length
        if (n > 1) {
            Loop n - 1 {
                i := A_Index
                Loop n - i {
                    j := A_Index
                    if (StrCompare(result[j].date, result[j+1].date) < 0) {
                        tmp := result[j]
                        result[j] := result[j+1]
                        result[j+1] := tmp
                    }
                }
            }
        }
        return result
    }

    ; ─── 重命名 .rtf / .md 两个文件 ───
    static RenameWithTag(date, oldTag, newTag) {
        oldPrefix := (oldTag = "") ? date : date . "-" . oldTag
        newPrefix := (newTag = "") ? date : date . "-" . newTag
        if (oldPrefix = newPrefix)
            return true

        for ext in ["rtf", "md"] {
            oldPath := Config.GetVault() . "\" . oldPrefix . "." . ext
            newPath := Config.GetVault() . "\" . newPrefix . "." . ext
            if FileExist(oldPath) {
                try FileMove(oldPath, newPath, false)
                catch
                    return false
            }
        }
        return true
    }
}


; ─── PandocService：RTF → Markdown ───
; 【v1.9 关键修复】
;   · GetCmd / IsAvailable 加文件大小检查（> 1MB 才用）
;   · 避免 0KB 坏 pandoc 阻塞系统 PATH 里的好 pandoc
class PandocService {
    ; ─── 判断 pandoc 文件是否"有效" ───（v1.9 新增）
    ; 有效定义：文件存在 且 大小 > 1MB（正常 pandoc 约 150-230MB）
    static _IsValidPandoc(path) {
        return FileExist(path) && FileGetSize(path) > 1048576
    }

    ; ─── 返回可用的 pandoc 命令 ───（v1.9 修复：加大小检查）
    ; 优先 %AppData%\SevenNote\pandoc.exe（必须有效）
    ; 否则退化到系统 PATH 里的 pandoc
    static GetCmd() {
        p := Config.PandocPath
        if this._IsValidPandoc(p)
            return '"' . p . '"'
        return "pandoc.exe"
    }

    ; ─── 检测 pandoc 是否可用 ───（v1.9 修复：加大小检查）
    static IsAvailable() {
        ; 优先 AppData 打包版（必须大小 > 1MB）
        p := Config.PandocPath
        if this._IsValidPandoc(p) {
            try {
                code := RunWait(A_ComSpec . ' /c "' . p
                    . '" --version >nul 2>&1', , "Hide")
                return code = 0
            } catch {
            }
        }
        ; 退化系统 PATH
        try {
            code := RunWait(A_ComSpec . " /c pandoc --version >nul 2>&1", , "Hide")
            return code = 0
        } catch {
            return false
        }
    }

    ; ─── 主流程：RTF → MD ───
    static Convert(srcRtfPath, mdPath, dateStr) {
        extractDir := NoteStoreService.TempDir() . "\media"
        assetsDir := NoteStoreService.AssetsDir(dateStr)

        if DirExist(extractDir)
            try DirDelete(extractDir, true)
        DirCreate(extractDir)
        NoteStoreService.EnsureDir(assetsDir)

        cmd := this.GetCmd() . ' -f rtf -t markdown --wrap=none'
            . ' --extract-media="' . extractDir . '"'
            . ' "' . srcRtfPath . '" -o "' . mdPath . '"'

        code := RunWait(A_ComSpec . ' /c "' . cmd . '"', , "Hide")
        if (code != 0)
            return false

        this._FixMarkdown(mdPath, dateStr, extractDir, assetsDir)

        if DirExist(extractDir)
            try DirDelete(extractDir, true)

        return true
    }

    ; ─── 后处理 Markdown ───
    ; 图片路径改为 ./_assets/日期/文件名
    static _FixMarkdown(mdPath, dateStr, extractDir, assetsDir) {
        if !FileExist(mdPath)
            return
        f := FileOpen(mdPath, "r", "UTF-8")
        content := f.Read()
        f.Close()

        pattern := '!\[.*?\]\([^)]*?[\\/]([^\\/()]+)\)(?:\{[^}]*\})?'
        content := RegExReplace(content, pattern
            , "![](" . "./_assets/" . dateStr . "/$1)")
        content := RegExReplace(content, "(!\[\]\([^)]+\))", "$1`n")
        content := RegExReplace(content, "\\\s*\r?\n", "`n")

        f := FileOpen(mdPath, "w", "UTF-8")
        f.Write(content)
        f.Close()

        if DirExist(extractDir) {
            Loop Files, extractDir . "\*.*" {
                try FileMove(A_LoopFileFullPath
                    , assetsDir . "\" . A_LoopFileName, true)
            }
        }
    }
}


; ─── ThemeService：主题应用 ───
class ThemeService {
    static Themes := [
        {name: "纯米黄", win: "FFF8E7", edBg: "FFF8E7", text: "3D2B1F", dim: "A89880"},
        {name: "护眼绿", win: "CCE8CF", edBg: "E0F0E3", text: "2D4A30", dim: "6B8E6E"},
        {name: "天空蓝", win: "EAF4FF", edBg: "DCEBFA", text: "1F3A5C", dim: "7A92AA"},
        {name: "薄荷绿", win: "E8F5F0", edBg: "DAEEE8", text: "1F4A3D", dim: "7A9E92"},
        {name: "高雅灰", win: "F0F0F0", edBg: "E8E8E8", text: "2A2A2A", dim: "808080"},
        {name: "纸白",   win: "FAFAFA", edBg: "FFFFFF", text: "333333", dim: "999999"},
        ; ⚠ 带背景图的主题：bg 是图片路径，bgAlpha 是把图压暗的遮罩不透明度（0-100）。
        ;   这套配色取自那张星空图（实测全图均色 #181C25、平均亮度仅 28）：win / edBg 都
        ;   贴着图的暗部走（亮度 ≈15），编辑区内外浑然一体，没有色块割裂感。
        ;   bgAlpha = 0 表示不压暗：Windows Terminal 用的就是同一张图、backgroundImageOpacity
        ;     设成 1（完全不压暗），这里对齐它 —— 星云保持原样、最亮也最清楚。
        ;     想压暗就在 _config.ini 写 BackdropOpacity=20（越小越亮），或改这里的 bgAlpha。
        ;   ⚠ 不压暗之后前景色必须够亮：文字取近白、次级文字也抬到浅灰蓝，
        ;     否则压在星云亮部（亮度约 60-130）上会发灰读不清。
        ;   图片缺失时自动降级成纯深色底（edBg），浅色文字照样读得清。
        ;   不想改源码就换图：在 _config.ini 的 [Appearance] 里写 BackdropImage / BackdropOpacity。
        {name: "星空", win: "0D0F14", edBg: "0D0F14", text: "F5F9FF", dim: "9FAABC"
            , bg: "D:\00-SevenFiles\Pictures\04-素材库\壁纸\星空\2026-10-14_星空-灰色2.png"
            , bgAlpha: 0},

        ; ⚠ 竖版人物图和横版漫射图是两种铺法 —— 但**别拿 contain 兜竖图**：
        ;   · 星空是漫射横图，cover 裁掉左右各 45% 也看不出；
        ;   · 竖版人物图（0.676）塞进编辑区（0.917）若走 contain，两侧会留出
        ;     一大条 edBg 底色、人物缩在中间。正解是**先按编辑区比例裁好再铺**：
        ;     裁剪框专挑人物（见下），图本身就是 0.917，cover 即铺满、一个细节不浪费。
        ; ⚠ 这套是「暗图 + 亮字」，和「星空」同族 —— 别被"人物图得提亮"带偏：
        ;   源图是 5897x8719 的高清原图，全图均亮度只有 **75**，本来就满足「亮字」的
        ;   WCAG 4.5:1 那条线（背景 ≤ 118），**根本不需要提亮**。上一版为了迁就深色字
        ;   把它抬到均亮 170，整张图当场像蒙了层灰 —— 提亮不等于"更清晰"，是把原图洗白。
        ;   现在这条路反过来：暗部一个像素都不动，只把压在文字下面的**最亮部分**滚降。
        ; ⚠ 烘焙由 tools\rebake-backdrop.ps1 一次跑完，输入只有那张高清原图：
        ;   ① 裁：crop x=0.10 / w=0.72 / y=0  (4246x4630) —— 专挑人物上半身，
        ;      顺手把原图右侧那片白墙亮雾裁出框外（留着它会在右下角把字吞掉）；
        ;   ② 缩：2400x2617（0.917，与编辑区严格同比例，SS_BITMAP 不再重采样）；
        ;   ③ 色调：**在 V（明度）上等比缩放**，绝不混色 ——
        ;        V ≤ 116 原样不动，V > 116 线性滚降到 152。
        ;      实测只动到 ~15% 的像素（脸、手、那点雾），全图均亮度 75.1 → 74.9，
        ;      最彩 5% 像素的饱和度 45.8% → 45.1%，而亮度 >118 的像素从 20.5% 降到
        ;      9.1% —— 那正是亮字要躲开的地方。
        ;   ④ unsharp 半径 4 强度 0.9（在**成品尺寸**上做，不是源图尺寸）。
        ;   还想再暗/再亮：优先改 Knee（BackdropOpacity 是运行时遮罩，会减饱和）。
        ; ⚠ 素材是 5897x8719 的高清原图「金克斯竖版.png」，别退回去用 2000x2300 的
        ;   「金克斯竖版02.png」—— 那张缩到编辑区只剩 3 倍余量，锐化后更容易发糊。
        ; ⚠ 配色全在图里（图是冷调，B > R）：win / edBg = 0B1624（比图的暗部再蓝一档，
        ;   深色标题栏随之自动打开），text = EAF2FF、dim = 93AACB —— 亮字压深底，
        ;   对比度 16:1 / 7.6:1，都远超 4.5:1。
        {name: "金克斯", win: "0B1624", edBg: "0B1624", text: "EAF2FF", dim: "93AACB"
            , bg: "D:\00-SevenFiles\Pictures\04-素材库\壁纸\动漫\金克斯主题.png"
            , bgAlpha: 0
            , bgFit: "cover"}
    ]

    static _current := 1
    static _loading := false

    static GetCurrent() => this._current
    static GetName() => this.Themes[this._current].name

    static Next() {
        this._current++
        if (this._current > this.Themes.Length)
            this._current := 1
        this.Apply(this._current)
    }

    static Apply(idx) {
        this._current := idx
        t := this.Themes[idx]
        g := State.GetGui()
        hwndEd := State.GetEd()
        if !g || !hwndEd
            return

        g.BackColor := t.win
        SendMessage(0x0443, 0, this._RGBtoBGR(t.edBg), hwndEd)

        cf := Buffer(92, 0)
        NumPut("uint", 92, cf, 0)
        NumPut("uint", 0x40000000 | 0x20000000 | 0x80000000 | 0x08000000, cf, 4)
        NumPut("int", FontService.GetSize() * 20, cf, 12)
        NumPut("uint", this._RGBtoBGR(t.text), cf, 20)
        NumPut("uchar", 134, cf, 24)
        StrPut(FontService.GetName(), cf.Ptr + 26, "UTF-16")
        SendMessage(0x0444, 4, cf.Ptr, hwndEd)

        for ctrl in [State.GetStat(), State.GetDateCtrl()
            , State.GetMsgCtrl(), State.GetThemeLabel()] {
            try ctrl.SetFont("c" . t.dim . " s10", FontService.GetName())
        }
        try State.GetThemeLabel().SetFont("c" . t.text . " s10", FontService.GetName())
        try State.GetTagCtrl().SetFont("c" . t.dim . " s10", FontService.GetName())

        try State.GetThemeLabel().Value := this._BuildLabel()

        ; 深色主题连标题栏一起变深 —— Windows 默认画白标题栏，压在深色窗口上很扎眼
        this._SetDarkTitleBar(t)

        if !this._loading
            this.SaveToConfig()

        EventBus.Emit("Theme.Changed", {name: t.name, idx: this._current})
    }

    ; 标题栏深浅跟着主题底色走：按亮度判断，深色主题开 immersive dark mode、浅色主题关掉。
    ; ⚠ 属性号随 Windows 版本变：Win10 1903+ / Win11 用 20，Win10 1809 用 19；
    ;   先试 20，DllCall 返回非 0（不支持该属性）再退到 19。
    static _SetDarkTitleBar(t) {
        hwnd := State.GetGuiHwnd()
        if !hwnd
            return
        r  := Integer("0x" . SubStr(t.win, 1, 2))
        gg := Integer("0x" . SubStr(t.win, 3, 2))
        b  := Integer("0x" . SubStr(t.win, 5, 2))
        dark := (0.299 * r + 0.587 * gg + 0.114 * b) < 128 ? 1 : 0

        v := Buffer(4, 0)
        NumPut("int", dark, v, 0)
        try {
            for attr in [20, 19] {
                if !DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd
                    , "int", attr, "ptr", v, "int", 4, "int")
                    break
            }
        }

        ; 标题栏整块染成主题色（Win11 build 22000+ 才有 35 / 36 / 34 这三个属性）：
        ;   35 = CAPTION_COLOR  标题栏底色，取 win
        ;   36 = TEXT_COLOR     标题文字色，取 text —— 深底配亮字、浅底配深字，自动成对
        ;   34 = BORDER_COLOR   外框，与标题栏同色
        ;   颜色是 COLORREF（0x00BBGGRR），正好复用 _RGBtoBGR()。
        ; ⚠ Win10 上这三个属性不存在，DllCall 直接返回非 0 —— 静默丢掉、系统配色照旧，
        ;   所以不必写版本判断（上面那段 immersive dark mode 已经兜住了深浅）。
        for it in [[35, t.win], [36, t.text], [34, t.win]] {
            cv := Buffer(4, 0)
            NumPut("uint", this._RGBtoBGR(it[2]), cv, 0)
            try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd
                , "int", it[1], "ptr", cv, "int", 4, "int")
        }
    }

    static SaveToConfig() {
        ConfigService.Write("Appearance", "ThemeIndex", this._current)
    }

    static LoadFromConfig() {
        this._loading := true
        idx := ConfigService.ReadInt("Appearance", "ThemeIndex", 1)
        if (idx < 1 || idx > this.Themes.Length)
            idx := 1
        this.Apply(idx)
        this._loading := false
    }

    static _BuildLabel() {
        return ThemeService.GetName()
            . " · " . FontService.GetName()
            . " " . FontService.GetSize() . "pt"
    }

    static _RGBtoBGR(hexRGB) {
        r := SubStr(hexRGB, 1, 2)
        g := SubStr(hexRGB, 3, 2)
        b := SubStr(hexRGB, 5, 2)
        return Integer("0x" . b . g . r)
    }
}


; ─── FontService：字体应用 ───
class FontService {
    static Fonts := ["楷体", "华文行楷", "华文新魏", "方正舒体"
        , "仿宋", "微软雅黑", "黑体"]
    static Sizes := [12, 14, 16, 18, 20]

    static _curFont := 1
    static _curSize := 2
    static _loading := false

    static GetName() => this.Fonts[this._curFont]
    static GetSize() => this.Sizes[this._curSize]

    static NextFont() {
        this._curFont++
        if (this._curFont > this.Fonts.Length)
            this._curFont := 1
        this.Apply()
    }

    static BiggerSize() {
        if (this._curSize < this.Sizes.Length) {
            this._curSize++
            this.Apply()
        }
    }

    static SmallerSize() {
        if (this._curSize > 1) {
            this._curSize--
            this.Apply()
        }
    }

    static Apply() {
        hwndEd := State.GetEd()
        if !hwndEd
            return

        t := ThemeService.Themes[ThemeService.GetCurrent()]

        cf := Buffer(92, 0)
        NumPut("uint", 92, cf, 0)
        NumPut("uint", 0x40000000 | 0x20000000 | 0x80000000 | 0x08000000, cf, 4)
        NumPut("int", this.GetSize() * 20, cf, 12)
        NumPut("uint", ThemeService._RGBtoBGR(t.text), cf, 20)
        NumPut("uchar", 134, cf, 24)
        StrPut(this.GetName(), cf.Ptr + 26, "UTF-16")
        SendMessage(0x0444, 4, cf.Ptr, hwndEd)

        for ctrl in [State.GetStat(), State.GetDateCtrl()
            , State.GetMsgCtrl(), State.GetThemeLabel()] {
            try ctrl.SetFont("c" . t.dim . " s" . (this.GetSize() - 4), this.GetName())
        }
        try State.GetThemeLabel().SetFont("c" . t.text . " s10", this.GetName())
        try State.GetTagCtrl().SetFont("c" . t.dim . " s10", this.GetName())

        try State.GetThemeLabel().Value := ThemeService._BuildLabel()

        if !this._loading
            this.SaveToConfig()

        EventBus.Emit("Font.Changed", {name: this.GetName(), size: this.GetSize()})

        SendMessage(0x00B1, -1, -1, hwndEd)
        SendMessage(0x00B7, 0, 0, hwndEd)
    }

    static SaveToConfig() {
        ConfigService.Write("Appearance", "FontIndex", this._curFont)
        ConfigService.Write("Appearance", "FontSizeIndex", this._curSize)
    }

    static LoadFromConfig() {
        this._loading := true
        fi := ConfigService.ReadInt("Appearance", "FontIndex", 1)
        if (fi < 1 || fi > this.Fonts.Length)
            fi := 1
        this._curFont := fi
        si := ConfigService.ReadInt("Appearance", "FontSizeIndex", 2)
        if (si < 1 || si > this.Sizes.Length)
            si := 2
        this._curSize := si
        this.Apply()
        this._loading := false
    }
}


; ─── BackdropService：背景图能力（位图合成 + 层级铺设）───
; 纯能力：不读配置、不管开关、不发事件，只负责「把一张图铺到编辑区背后的控件上」。
;
; 技术路线（全部由独立 spike 脚本实测确认，非推测）：
;   · RichEdit 无法真正透明 —— 给编辑区加 WS_EX_TRANSPARENT，让它绘制时跳过自身背景，
;     由 z-order 更低的同级兄弟控件（承载图片的 Static）先画出的图透上来；
;   · 父窗口绝不能加 WS_EX_COMPOSITED —— 双缓冲合成会吞掉 WS_EX_TRANSPARENT 子窗口
;     的文字（实测：只剩图、文字全丢）；
;   · 子类化 WM_ERASEBKGND 自绘也无效 —— 图会被 RichEdit 在 WM_PAINT 内重填背景盖掉；
;   · WS_EX_TRANSPARENT 实测不影响鼠标命中与键盘输入，真实滚轮滚动无残影，
;     被其他窗口遮挡再露出也能正常恢复。
;
; ⚠ 两个 API 细节：
;   · 扩展样式必须在 Show() 之前设置；
;   · 未显示过的 Gui 窗口 WS_VISIBLE = 0，WinSetExStyle 匹配不到，需 DetectHiddenWindows(true)。
class BackdropService {
    static _picCtrl := ""        ; 承载背景图的 Static 控件（带 SS_BITMAP）
    static _srcBmp := 0          ; 原图 HBITMAP（只解码一次，反复复用）
    static _srcW := 0
    static _srcH := 0
    static _imgPath := ""
    static _maskColor := "FFF8E7"   ; 遮罩色，十六进制 RGB（取主题编辑区底色）
    static _maskAlpha := 204        ; 遮罩不透明度 0-255（204 ≈ 80%）
    static _attached := false
    static _fit := "cover"       ; 缩放模式：cover = 等比裁剪铺满（默认）；contain = 整图缩放进内

    static IsAttached() => this._attached
    static GetPicCtrl() => this._picCtrl
    static HasImage() => (this._imgPath != "" && FileExist(this._imgPath))

    ; 遮罩色 + 不透明度（终端式做法的要点：把图压暗，前景文字才读得清）
    static SetMask(hexRGB, alphaPercent) {
        if (hexRGB != "")
            this._maskColor := hexRGB
        a := Round(255 * alphaPercent / 100)
        this._maskAlpha := (a < 0) ? 0 : ((a > 255) ? 255 : a)
    }

    ; 换图：清掉已解码的原图，下次 Render 时重新加载
    static SetImage(path) {
        if (path = this._imgPath)
            return
        this._ReleaseSource()
        this._imgPath := path
    }

    ; 缩放模式。缺省 cover —— 老主题（含「星空」）不写这个字段，行为分毫不变。
    static SetFit(mode) {
        this._fit := (mode = "contain") ? "contain" : "cover"
    }

    ; ─── 图层控件：创建后压到编辑区之下 ───
    ; 用 AddText + SS_BITMAP(0x0E) 而非 AddPicture：后者必须给文件路径，
    ; 而我们要往控件里灌内存位图（图 + 遮罩是合成出来的，不落盘）。
    static Attach(g) {
        if this._attached
            return true
        try {
            ; ⚠ 不能带 -Wrap：-Wrap 会清掉 0x0C 位，把 SS_BITMAP(0x0E) 打成 0x02(SS_RIGHT)
            pic := g.AddText("x8 y32 w434 h440 +0xE", "")
            pic.Visible := false
            ; 把 pic 插到编辑区之后 —— z-order 里「之后」即在更下层
            DllCall("SetWindowPos", "ptr", pic.Hwnd, "ptr", State.GetEd()
                , "int", 0, "int", 0, "int", 0, "int", 0
                , "uint", 0x0002 | 0x0001 | 0x0010)   ; NOMOVE | NOSIZE | NOACTIVATE
            this._picCtrl := pic
            this._attached := true
            return true
        } catch {
            return false
        }
    }

    static SetVisible(on) {
        if !this._picCtrl
            return
        try this._picCtrl.Visible := on
    }

    ; ─── 按目标矩形重新合成并铺上图 ───
    ; 尺寸交给调用方（Feature）用与编辑区 Move 完全相同的参数算，避免 DPI 单位混用。
    static Render(x, y, w, h) {
        if !this._attached || !this._picCtrl
            return false
        if (w <= 0 || h <= 0)
            return false
        if !this.LoadSource()
            return false

        this._picCtrl.Move(x, y, w, h)

        ; ⚠ 位图尺寸必须与控件的「物理像素尺寸」严格相等，SS_BITMAP 才会 1:1 贴图。
        ;   只要差 1px，它就改用 COLORONCOLOR（最近邻）把整张图重采样一遍 —— 画面
        ;   当场发糊，损失比换任何插值算法都大。而 w × A_ScreenDPI/96 只是估算：
        ;     · 非整数倍 DPI（125% / 175%）下 AHK 内部的换算与这里的舍入可能差 1px；
        ;     · A_ScreenDPI 只反映主屏 —— 窗口拖到另一块不同缩放的显示器上会整倍地错，
        ;       这正是「换个屏就糊」的根。
        ;   所以不猜：Move 完直接从 Win32 读回真实像素尺寸，所见即所得。
        pw := 0, ph := 0
        if !this._CtrlPixelSize(&pw, &ph)
            return false
        hbm := this._Compose(pw, ph)
        if !hbm
            return false

        ; STM_SETIMAGE(0x0172) / wParam = IMAGE_BITMAP(0)
        ; SS_BITMAP 控件会自行销毁上一张位图，这里不必手动 DeleteObject
        SendMessage(0x0172, 0, hbm, this._picCtrl.Hwnd)
        ; ⚠ SS_BITMAP 控件收到 STM_SETIMAGE 后会把自身尺寸改成「位图的像素尺寸」——
        ;   那是物理值、不走 DPI 缩放，会把上面那次 Move 的逻辑尺寸冲掉。实测 150%
        ;   缩放下图只盖住编辑区 1/1.5 的面积（控件 443x483，编辑区 665x725）。
        ;   位图灌完后按原逻辑尺寸再压一次，控件物理矩形即回到 pw×ph，与位图严丝合缝。
        this._picCtrl.Move(x, y, w, h)
        return true
    }

    ; ─── 读承载控件的真实物理像素尺寸 ───
    ; GetWindowRect 返回的永远是物理像素（进程已 DPI 感知），不经过 AHK 的逻辑换算。
    ; 因此它一并解决两件事：消掉「估算差 1px → 整图重采样」，以及让尺寸自动跟随
    ; 窗口所在的显示器缩放（副屏 100%、主屏 150% 也不会再糊）。
    static _CtrlPixelSize(&w, &h) {
        rc := Buffer(16, 0)
        if !DllCall("GetWindowRect", "ptr", this._picCtrl.Hwnd, "ptr", rc)
            return false
        w := NumGet(rc, 8, "int") - NumGet(rc, 0, "int")
        h := NumGet(rc, 12, "int") - NumGet(rc, 4, "int")
        return (w > 0 && h > 0)
    }

    ; ─── 解码原图（惰性，只做一次）───
    static LoadSource() {
        if this._srcBmp
            return true
        if !this.HasImage()
            return false
        try {
            bmp := LoadPicture(this._imgPath, "G")   ; G = 只要 HBITMAP，不要 Bitmap 对象
        } catch {
            return false
        }
        if !bmp
            return false

        ; BITMAP 结构：bmWidth 在偏移 4，bmHeight 在偏移 8
        info := Buffer(32, 0)
        if !DllCall("GetObject", "ptr", bmp, "int", 32, "ptr", info, "int")
            return false
        this._srcBmp := bmp
        this._srcW := NumGet(info, 4, "int")
        this._srcH := NumGet(info, 8, "int")
        return (this._srcW > 0 && this._srcH > 0)
    }

    static _ReleaseSource() {
        if this._srcBmp {
            try DllCall("DeleteObject", "ptr", this._srcBmp)
            this._srcBmp := 0
            this._srcW := 0
            this._srcH := 0
        }
    }

    ; ─── 合成：原图缩放到目标尺寸 + 叠一层半透明遮罩色 ───
    ; w/h 是**物理像素**，由 _CtrlPixelSize 从控件读回，不再自己按 A_ScreenDPI 估算 ——
    ; 位图与控件因此像素对齐，SS_BITMAP 不会再多拉伸一次，跨显示器缩放也自动跟随。
    static _Compose(w, h) {
        if (w < 1 || h < 1)
            return 0
        hdcScreen := DllCall("GetDC", "ptr", 0, "ptr")
        hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcScreen, "ptr")
        hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcScreen, "int", w, "int", h, "ptr")
        oldMem := DllCall("SelectObject", "ptr", hdcMem, "ptr", hbm, "ptr")

        ; ① 原图 → 目标尺寸，逐级对折（每级最多缩一半）。
        ;    等比缩放而非拉伸：3840x2400（16:10）硬塞进 665x725（0.92）会被压扁，
        ;    星云拉成竖条就"不清晰"了。两种铺法的比例都保持原样：
        ;      · cover（默认）：按 max 缩放系数放大到刚好盖满，再从中心裁出与目标同比例
        ;        的一块来画 —— 只裁不压。适合横版漫射图（星空 1.6 裁掉左右也看不出）。
        ;      · contain（bgFit 指定）：按 min 系数把整张图缩到能放进目标区，居中摆放 ——
        ;        一个像素都不裁。竖版人物图必须用它，否则 cover 会把上下裁掉、人物被切。
        ;
        ;    ⚠ 为什么不能一步缩到位：HALFTONE 本质是 box 采样，一次缩 5.8 倍等于源图上
        ;      每 5.8 个像素只留 1 个进结果，中间的亮度被直接丢掉 —— 星点被采成锯齿、
        ;      亮部起摩尔纹，这才是「不细腻」的大头（比换插值算法的影响还大）。
        ;      拆成每级 ≤2 倍，每级都先做一次平均，等效于多抽头低通滤波，纹理立刻干净。
        ;      放大时（源比目标小）不该分级，一级直出即可，免得白损一次插值。
        hdcSrc := DllCall("CreateCompatibleDC", "ptr", hdcScreen, "ptr")
        oldSrc := DllCall("SelectObject", "ptr", hdcSrc, "ptr", this._srcBmp, "ptr")

        ; 目标绘制矩形（物理像素）：cover 铺满整块，contain 缩进内、四周留底色。
        dstX := 0, dstY := 0, dstW := w, dstH := h

        if (this._fit = "contain") {
            ; contain：整张源图等比缩到能放进 w×h，居中摆放 —— 一个像素都不裁。
            k := (w / this._srcW < h / this._srcH) ? w / this._srcW : h / this._srcH
            dstW := Round(this._srcW * k)
            dstH := Round(this._srcH * k)
            dstX := (w - dstW) // 2
            dstY := (h - dstH) // 2

            ; ⚠ 留边会露出 CreateCompatibleBitmap 从未初始化过的内存（花屏 / 黑块），
            ;   必须先用遮罩色铺一层底。遮罩色就是主题的 edBg，留边与窗框同色、浑然一体。
            ;   cover 铺满整块用不着，也就不碰它 —— 老主题的画面分毫不变。
            hbr := DllCall("CreateSolidBrush", "uint", this._RGBtoBGR(this._maskColor), "ptr")
            if hbr {
                rc := Buffer(16, 0)
                NumPut("int", 0, rc, 0)
                NumPut("int", 0, rc, 4)
                NumPut("int", w, rc, 8)
                NumPut("int", h, rc, 12)
                DllCall("FillRect", "ptr", hdcMem, "ptr", rc, "ptr", hbr)
                DllCall("DeleteObject", "ptr", hbr)
            }

            cw := this._srcW           ; 源取整张
            ch := this._srcH
            cX := 0, cY := 0
        } else {
            ; cover：等比放大到刚好盖满，再从中心裁出与目标同比例的一块。
            k  := (w / this._srcW > h / this._srcH) ? w / this._srcW : h / this._srcH
            cw := Round(w / k)
            ch := Round(h / k)
            cX := Round((this._srcW - cw) / 2)
            cY := Round((this._srcH - ch) / 2)
        }

        curDC := hdcSrc
        curX  := cX
        curY  := cY
        curW  := cw
        curH  := ch
        mids  := []                ; 逐级产生的临时位图/DC，画完统一回收

        ; ⚠ 分级对折的判据和目标要用「图的落点尺寸」(dstW/dstH)，不是整块区域 ——
        ;   contain 时图只占中间一小块，用 w/h 会让分级提前收手、缩出来发糙。
        while (curW > dstW * 2 && curH > dstH * 2) {
            nw := Max(dstW, curW // 2)
            nh := Max(dstH, curH // 2)
            nb := DllCall("CreateCompatibleBitmap", "ptr", hdcScreen, "int", nw, "int", nh, "ptr")
            nd := DllCall("CreateCompatibleDC", "ptr", hdcScreen, "ptr")
            if !(nb && nd) {
                ; 分配失败就退回「上一级单步缩到位」：宁可略糙，也不能把图弄丢
                if nb
                    DllCall("DeleteObject", "ptr", nb)
                if nd
                    DllCall("DeleteDC", "ptr", nd)
                break
            }
            old := DllCall("SelectObject", "ptr", nd, "ptr", nb, "ptr")
            DllCall("SetStretchBltMode", "ptr", nd, "int", 4)      ; HALFTONE
            DllCall("SetBrushOrgEx", "ptr", nd, "int", 0, "int", 0, "ptr", 0)
            DllCall("StretchBlt", "ptr", nd, "int", 0, "int", 0, "int", nw, "int", nh
                , "ptr", curDC, "int", curX, "int", curY, "int", curW, "int", curH
                , "uint", 0x00CC0020)                              ; SRCCOPY
            mids.Push({dc: nd, bmp: nb, old: old})
            curDC := nd, curX := 0, curY := 0, curW := nw, curH := nh
        }

        DllCall("SetStretchBltMode", "ptr", hdcMem, "int", 4)      ; HALFTONE
        DllCall("SetBrushOrgEx", "ptr", hdcMem, "int", 0, "int", 0, "ptr", 0)
        DllCall("StretchBlt", "ptr", hdcMem, "int", dstX, "int", dstY, "int", dstW, "int", dstH
            , "ptr", curDC, "int", curX, "int", curY, "int", curW, "int", curH
            , "uint", 0x00CC0020)                                  ; SRCCOPY

        for m in mids {
            DllCall("SelectObject", "ptr", m.dc, "ptr", m.old)
            DllCall("DeleteDC", "ptr", m.dc)
            DllCall("DeleteObject", "ptr", m.bmp)
        }
        DllCall("SelectObject", "ptr", hdcSrc, "ptr", oldSrc)
        DllCall("DeleteDC", "ptr", hdcSrc)

        ; ② 半透明遮罩：用 1x1 的 32bpp DIB 源配合 AlphaBlend 整体合成，
        ;    避免逐像素遍历（840x600 有 50 万像素，逐像素在 AHK 里会明显卡顿）
        ;    ⚠ 两个坑（都实测踩过）：
        ;      · 源必须是 32bpp 且像素内嵌 alpha —— CreateCompatibleBitmap 造出的 DDB
        ;        没有 alpha 通道，AlphaBlend 会直接返回 0（失败）
        ;      · BLENDFUNCTION 是「按值传递」的 4 字节结构，必须打包成 uint 传，
        ;        传指针会导致 AlphaBlend 静默失败
        if (this._maskAlpha > 0) {
            bmih := Buffer(40, 0)
            NumPut("uint", 40, bmih, 0)      ; biSize
            NumPut("int", 1, bmih, 4)        ; biWidth
            NumPut("int", 1, bmih, 8)        ; biHeight
            NumPut("ushort", 1, bmih, 12)    ; biPlanes
            NumPut("ushort", 32, bmih, 14)   ; biBitCount
            NumPut("uint", 0, bmih, 16)      ; biCompression = BI_RGB
            NumPut("uint", 4, bmih, 20)      ; biSizeImage
            ppv := 0
            hbmSolid := DllCall("CreateDIBSection", "ptr", 0, "ptr", bmih, "uint", 0
                , "ptr*", &ppv, "ptr", 0, "uint", 0, "ptr")

            if (hbmSolid && ppv) {
                ; BGRA 单像素：遮罩色 + 不透明度
                NumPut("uint"
                    , (this._maskAlpha << 24) | this._RGBtoBGR(this._maskColor), ppv, 0)

                hdcSolid := DllCall("CreateCompatibleDC", "ptr", hdcScreen, "ptr")
                oldSolid := DllCall("SelectObject", "ptr", hdcSolid, "ptr", hbmSolid, "ptr")

                ; AC_SRC_OVER(0) | BlendFlags(0) | SourceConstantAlpha(255) | AC_SRC_ALPHA(1)
                ftn := (1 << 24) | (255 << 16)
                DllCall("msimg32\AlphaBlend", "ptr", hdcMem, "int", 0, "int", 0, "int", w, "int", h
                    , "ptr", hdcSolid, "int", 0, "int", 0, "int", 1, "int", 1, "uint", ftn)

                DllCall("SelectObject", "ptr", hdcSolid, "ptr", oldSolid)
                DllCall("DeleteDC", "ptr", hdcSolid)
            }
            if hbmSolid
                DllCall("DeleteObject", "ptr", hbmSolid)
        }

        DllCall("SelectObject", "ptr", hdcMem, "ptr", oldMem)
        DllCall("DeleteDC", "ptr", hdcMem)
        DllCall("ReleaseDC", "ptr", 0, "ptr", hdcScreen)
        return hbm
    }

    static _RGBtoBGR(hexRGB) {
        r := SubStr(hexRGB, 1, 2)
        g := SubStr(hexRGB, 3, 2)
        b := SubStr(hexRGB, 5, 2)
        return Integer("0x" . b . g . r)
    }
}


; ═══════════════════════════════════════════════════════════════════════════
;  表示层组件
; ═══════════════════════════════════════════════════════════════════════════

; ─── StatusBar：状态栏 ───
class StatusBar {
    static _dateCtrl := ""
    static _tagCtrl := ""
    static _msgCtrl := ""
    static _clearTimer := 0

    static Init(dateCtrl, tagCtrl, msgCtrl) {
        this._dateCtrl := dateCtrl
        this._tagCtrl := tagCtrl
        this._msgCtrl := msgCtrl
        this.SetMsg("就绪")

        EventBus.On("Date.Changed",       (d) => this.SetDate(d.new))
        EventBus.On("Date.Switched",      (d) => (
            this.SetMsg("→ 已切换到 " . d.date),
            this.RefreshTag()))
        EventBus.On("Save.Completed",     (d) => (
            this.SetMsg("✓ 已保存 " . d.time),
            this.RefreshTag()))
        EventBus.On("Timestamp.Appended", (*) => this.SetMsg("✓ 已追加时间戳"))
        EventBus.On("Separator.Inserted", (*) => this.SetMsg("✓ 已插入分隔线"))
        EventBus.On("Heading.Inserted",   (*) => this.SetMsg("✓ 已插入分段标题"))
        EventBus.On("Paste.Plain",        (*) => this.SetMsg("✓ 已粘贴纯文本"))
        EventBus.On("Theme.Changed",      (d) => this.SetMsg("✓ 主题：" . d.name))
        EventBus.On("Font.Changed",       (d) => this.SetMsg("✓ 字体：" . d.name . " " . d.size . "pt"))
        EventBus.On("Line.Indented",      (*) => this.SetMsg("✓ 已缩进"))
        EventBus.On("Line.Outdented",     (*) => this.SetMsg("✓ 已取消缩进"))
        EventBus.On("CapsLock.Toggled",   (d) => this.SetMsg(d.msg))
        EventBus.On("Title.Changed",      (d) => (
            this.SetTag(d.tag),
            this.SetMsg(d.tag = "" ? "✓ 标签已清除" : "✓ 标签：" . d.tag)))
        EventBus.On("Error.Occurred",     (d) => this.SetMsg("✗ " . d.msg))
    }

    ; v1.8：日期后拼接星期
    static SetDate(d) {
        if !this._dateCtrl
            return
        weekday := NoteStoreService.GetWeekday(d)
        this._dateCtrl.Value := "📅 " . d . " " . weekday
    }

    static SetTag(tag) {
        if !this._tagCtrl
            return
        if (tag = "")
            this._tagCtrl.Value := ""
        else
            this._tagCtrl.Value := "🏷 " . tag
    }

    static RefreshTag() {
        date := State.GetDate()
        if (date = "") {
            this.SetTag("")
            return
        }
        rtfPath := NoteStoreService.FindRtf(date)
        tag := (rtfPath != "")
            ? NoteStoreService.TagFromFileName(rtfPath) : ""
        this.SetTag(tag)
    }

    static SetMsg(msg) {
        if !this._msgCtrl
            return
        this._msgCtrl.Value := msg
        if this._clearTimer
            SetTimer(this._clearTimer, 0)
        this._clearTimer := () => (this._msgCtrl.Value := "")
        SetTimer(this._clearTimer, -2000)
    }
}
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

class WindowFeature {
    ; ═══ 伴生窗口适配（peer docking）═══
    ; 「呼出一个外部窗口 → 笔记窗口自动让位 / 堆叠」这套机制对所有 Feature 通用，
    ; 不限于终端 —— 以后要换成资源管理器、Obsidian、浏览器，照同一份契约做即可。
    ; 契约就三个事件，详见 README「开发指南 → 添加呼出外部窗口的功能」：
    ;   Peer.Preparing  外部窗口**即将露面**   → 笔记窗口先退场（别当着用户的面搬它）
    ;   Peer.Placed     已落位，带 {hwnd, x, y, w, h}（**真实**窗口矩形）→ 笔记窗口按它摆
    ;   Peer.Failed     最终没起来              → 把刚才退场的笔记窗口还回来
    ; 发布方只管广播这三条；订阅、摆放算法全在本类里，接入新窗口不用改它。
    ;
    ; ⚠ **只适配一次**：真正会动笔记窗口的只有「第一次」，适配完就置位 _docked，
    ;   此后三条事件一律不再碰它（语义与理由见 _docked 的注释）。所以上面那句
    ;   「先退场」也只发生在第一次 —— 过了那一回，伙伴再怎么呼出隐藏，笔记都纹丝不动。
    ;
    ; 伴生窗口的位置与尺寸（发布方摆好后广播过来）。
    ; 非对象 = 屏幕上没有伴生窗口，呼出时按记忆位置 / 默认落点走。
    static _peerRect := ""

    ; 当前窗口位置是不是「与伴生窗口上下堆叠」摆出来的。是的话收窗口时不覆盖位置记忆 ——
    ; 那份坐标和高度都是临时算的（见 _StackWithPeer），不该被当成用户摆的格局。
    static _stacked := false

    ; 堆叠前窗口的位置与尺寸。堆叠是临时布局，脱离（伴生窗口关掉）后要照这份底稿还原 ——
    ; 堆叠会把窗口压矮（实测 885 → 513），不还原的话单独显示时窗口就又扁又小。
    static _preStackRect := ""

    ; 是否已经为伴生窗口「适配过一次」。置位之后，Peer.* 三条事件一律不再碰笔记窗口 ——
    ; 这是本机制现在的核心语义：用顺了之后，笔记的尺寸位置就是用户自己的格局，
    ; 不该每次呼出终端 / DeepSeek 都被重算、重摆一遍。
    ;
    ; ⚠ 刻意**不落盘**。位置记忆（State._hiddenX 那一组）本来就是纯内存的，重启即丢、
    ;   笔记回到默认落点 —— 那时本来就需要重新落位一次。于是「重启程序 = 重新适配一次」
    ;   这个逃生门是自然存在的，不必额外加配置项，也不必往用户的 _config.ini 里写状态。
    static _docked := false

    ; ─── 挂载：订阅伴生窗口生命周期 ───
    ; 组合根在 PowerShellFeature.Init() 之前调用 —— 监听要在第一次 Alt+C 之前就位。
    static Init() {
        EventBus.On("Peer.Placed",    (rect) => this._OnPeerPlaced(rect))
        EventBus.On("Peer.Preparing", (*)    => this._CollapseForPeer())
        EventBus.On("Peer.Failed",    (*)    => this._RestoreAfterFailedPeer())
    }

    ; 伴生窗口马上要露面，先让笔记窗口退场。**只在第一次** —— 已经适配过的格局不再动。
    ;
    ; 收起来不是目的，是为了让随后的「适配」退化成一次纯粹的呼出：伙伴落位后
    ; _AdaptToPeer 会看到窗口并不在显示，于是走 Show() —— 而那条路径本来就是
    ; 「隐藏态下把位置尺寸算好、最后一次性露面」（见 _PlaceWindow）。不这么做的话，
    ; 就是当着用户的面把一个**已经显示**的窗口搬去堆叠位，平移与控件重排连在一起，
    ; 看着就是「飘一下」。
    ;
    ; 用 Hide() 而不是裸的 g.Hide()：Hide() 内含位置记忆（堆叠态下改用堆叠前的底稿），
    ; 与用户自己按 Alt+Z 收起完全同一条路。这份记忆随后正好被 _AdaptToPeer 拿来
    ; 判断「伙伴会不会压到笔记原来待的地方」。
    static _CollapseForPeer() {
        if this._docked
            return
        if !State.GetGuiHwnd()
            return
        if this.IsShowing()
            this.Hide()
    }

    ; 伴生窗口最终没起来（Run 抛错，或等满超时都找不到窗口）—— 刚才为它让位而收起的
    ; 窗口得还回来。少了这条兜底，用户按一次 Alt+C，屏幕上就什么都剩不下。
    ; 记忆里那份 _peerRect 若指向已消失的窗口，_StackWithPeer 开头有 alive
    ; 检查兜着，Show() 会自行回落到记忆位置 / 默认落点。
    static _RestoreAfterFailedPeer() {
        if !State.GetGuiHwnd()
            return
        if this.IsShowing()
            return
        this.Show()
    }

    ; 记下伴生窗口的位置，再让笔记窗口适配 —— 两步都要做：
    ; 少记一步（this._peerRect := rect）的话，_StackWithPeer 没有分区依据，
    ; 会直接退回记忆位置。
    static _OnPeerPlaced(rect) {
        this._peerRect := rect
        this._AdaptToPeer(rect)
    }

    ; 伴生窗口落位了 → 决定笔记窗口要不要动。三种情形：
    ;   ① 已经适配过       → 一个坐标都不改（_docked）
    ;   ② 伙伴没压到它身上 → 原样还回来，一个坐标都不改，然后固定下来
    ;   ③ 真压上了         → 按原设计适配一次，然后固定下来
    ;
    ; 「② 不冲突就不动」是这套机制现在的要害：笔记摆在左边、伙伴在右下，两者互不
    ; 妨碍 —— 那就谁也别动谁。改之前是无条件重算重摆，于是每次呼出都把用户自己
    ; 摆好的格局冲掉，笔记窗口次次跟着伙伴动。
    static _AdaptToPeer(rect) {
        if !State.GetGuiHwnd()
            return
        if this._docked
            return

        ghwnd := State.GetGuiHwnd()

        ; 笔记此刻多半已被 _CollapseForPeer 收走，位置取 Hide 时刚记下的那份 ——
        ; 那正是「笔记原来待的地方」，该拿它去比。万一它还显示着（订阅缺失，或将来
        ; 有别的来源广播 Peer.Placed），就现量一个。
        noteRect := State.HasHiddenRect()
            ? State.GetHiddenRect()
            : this._CurrentRect(ghwnd)

        if IsObject(noteRect) && IsObject(rect) && !this._RectsOverlap(noteRect, rect) {
            ; ── 不冲突：原样还回来，坐标尺寸一字不动 ──
            ; ⚠ 必须**先固定、再 Show**。Show 内部会走 _PlaceWindow → _StackWithPeer，
            ;   那时 _docked 已置位，于是它退回「记忆位置」= 刚 Hide 时记下的那份，
            ;   窗口正好回到原处。顺序反了就会在 Show 里被重新堆叠一次，白固定。
            this._FreezeDocked(ghwnd)
            if !this.IsShowing()
                this.Show()
            return
        }

        ; ── 冲突（或量不到笔记矩形，保守当作冲突）：按原设计适配一次 ──
        ; ⚠ 先收再摆：_StackWithPeer 要改位置改尺寸，这一整段不该被看见
        ;   （理由同 _CollapseForPeer）。若它已经收过，这次调用会跳过。
        if this.IsShowing()
            this.Hide()
        this.Show()
        ; 真摆成了才算「适配过一次」：没摆成（屏幕太矮等，_StackWithPeer 返回 false
        ; 让窗口退回了记忆位置）就不置位，留着以后还有机会再试。
        if this._stacked
            this._FreezeDocked(ghwnd)
    }

    ; 两个矩形是否相交 —— 即「有没有一块地方同时被两个窗口占着」。
    ; 两个入参都只用到 {x, y, w, h} 这四个字段，不关心别的。
    static _RectsOverlap(a, b) {
        return (a.x < b.x + b.w && a.x + a.w > b.x
            && a.y < b.y + b.h && a.y + a.h > b.y)
    }

    ; 窗口当前的矩形；窗口没了、或位置不可用（最小化停放位）时返回 ""。
    ; ⚠ 要开 DetectHiddenWindows：笔记可能正处在 Hide() 之后的状态，而 WinGetPos
    ;   默认忽略隐藏窗口、直接抛错。用完恢复原值，免得改变其它代码的可见性语义。
    static _CurrentRect(hwnd) {
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            WinGetPos(&x, &y, &w, &h, "ahk_id " . hwnd)
        } catch {
            ; 显式赋空：AHK v2 里未赋值的变量参与比较会触发 VarUnset 警告
            x := "", y := "", w := "", h := ""
        }
        DetectHiddenWindows(detectOld)
        if !this.IsUsableRect(x, y, w, h)
            return ""
        return {x: x, y: y, w: w, h: h}
    }

    ; 把这次适配的结果「转正」成用户格局，此后不再联动。三件事都要做，少一件都露馅：
    ;   ① 留下的矩形成为正式格局 —— 在这之前它是 _preStackRect 那份临时底稿；
    ;   ② 清掉堆叠态标记，_RememberPosition 从此走非堆叠分支，日后如实记录用户的拖动；
    ;   ③ 置位 _docked。
    ; ⚠ 只有窗口正显示着才量矩形：隐藏态下 State 里已经有 Hide() 记下的那份（就是
    ;   用户原来的位置），留着它才对 —— 那时量出来的也是同一个值，多此一举。
    static _FreezeDocked(ghwnd) {
        this._docked := true
        this._stacked := false
        this._preStackRect := ""
        if !this.IsShowing()
            return
        rect := this._CurrentRect(ghwnd)
        if IsObject(rect)
            State.SetHiddenRect(rect.x, rect.y, rect.w, rect.h)
    }

    ; ─── 入口：Alt+Z ───
    static Toggle() {
        if this.IsShowing()
            this.Hide()
        else
            this.Show()
    }

    ; 判断“当前是否正在显示”。
    ; 注意：最小化窗口的 WS_VISIBLE 仍是 1，必须连同 IsIconic 一起排除；
    ; 否则最小化状态下按 Alt+Z 会被误判成“正在显示”而执行隐藏，越按越找不着。
    static IsShowing() {
        hwnd := State.GetGuiHwnd()
        if !hwnd
            return false
        return DllCall("IsWindowVisible", "ptr", hwnd, "int")
            && !DllCall("IsIconic", "ptr", hwnd, "int")
    }

    ; ─── 收起：先广播、再记位置、最后隐藏 ───
    static Hide() {
        g := State.GetGui()
        EventBus.Emit("Window.BeforeHide")
        this._RememberPosition(g.Hwnd)
        g.Hide()
    }

    ; ─── 呼出：暂停重绘 → 定位 → 还原光标 → 恢复重绘 → 激活 ───
    static Show() {
        g := State.GetGui()
        hwnd := State.GetEd()
        ghwnd := g.Hwnd
        try {
            this._SuspendRedraw(hwnd)
            this._PlaceWindow(g, ghwnd)
            this._RestoreCaret(hwnd)
            this._ResumeRedraw(hwnd)
            DllCall("RedrawWindow", "ptr", hwnd, "ptr", 0, "ptr", 0
                , "uint", 0x0001 | 0x0100)
        } finally {
            try this._ResumeRedraw(hwnd)
        }
        WinActivate("ahk_id " . ghwnd)
        EventBus.Emit("Window.Shown")
    }

    ; ═══ 位置记忆与定位 ═══

    ; 记住当前窗口位置，供下次呼出还原。
    ; 只记屏幕内的有效位置；屏幕外坐标（最小化停放位、已拔掉的外接屏）一律丢弃
    ; 并清空记忆，让 Show() 回落到默认落点——否则窗口会被永久搬到看不见的地方。
    ;
    ; 若当前是按「与伴生窗口上下堆叠」摆出来的，位置和高度都是临时算的 —— 改用堆叠前的底稿，
    ; 不覆盖记忆；否则下次终端不在时，窗口会以那个被压矮的尺寸单独现身（实测 744x513）。
    static _RememberPosition(hwnd) {
        ; ⚠ 底稿**用完不丢**：堆叠态下隐藏只是「暂时收起来」，用户随时会 Alt+C 再摆回来，
        ;   那时仍要按同一份底稿记。真正作废是在下面的非堆叠分支 —— 那时窗口的位置
        ;   就是用户自己的格局，底稿已完成使命。
        if this._stacked {
            this._stacked := false
            pre := this._preStackRect
            if IsObject(pre) && this.IsUsableRect(pre.x, pre.y, pre.w, pre.h) {
                State.SetHiddenRect(pre.x, pre.y, pre.w, pre.h)
                return
            }
            State.ClearHiddenRect()
            return
        }
        ; 非堆叠态：当前坐标就是用户自己的格局 —— 正常记忆，并作废旧底稿
        this._preStackRect := ""
        try
            WinGetPos(&rectX, &rectY, &rectW, &rectH, "ahk_id " . hwnd)
        catch
            return
        if this.IsUsableRect(rectX, rectY, rectW, rectH)
            State.SetHiddenRect(rectX, rectY, rectW, rectH)
        else
            State.ClearHiddenRect()
    }

    ; 位置可用性：必须与某个显示器的工作区相交。
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

    ; 定位：坐标优先取记忆位置，不可用则回落默认落点。
    ;
    ; ⚠ 全程在「隐藏」状态下完成 —— 先 Show 再 Move 会让窗口先在 AHK 的默认落点露面，
    ;   约 190ms 后才跳到目标位置（实测 924,357 → 1629,238），视觉上就是「飘一下」。
    ;   Show("Hide") 先把窗口建好、让 OnSize 把控件布局跑完，位置算准了再一次性露面。
    ;
    ; ⚠ 尺寸不硬设 —— 本机 150% 缩放（A_ScreenDPI = 144）下 Gui 控件坐标会按 DPI 放大 1.5 倍，
    ;   窗口最小尺寸由控件固有尺寸决定（逻辑 +MinSize450x300 → 物理 675x450），
    ;   而 Config.WinW/WinH 是「逻辑单位」、WinMove 收「物理像素」。
    ;   实测把 450x550 直接传给 WinMove：宽被 675 的最小宽拒绝、高却通过了，窗口被压矮
    ;   （881 → 550）。故尺寸交给 AHK 按 DPI 自行决定。
    static _PlaceWindow(g, ghwnd) {
        ; 定位全程在隐藏状态下做：Show("Hide") 过的窗口 WS_VISIBLE 仍是 0，
        ; 而 WinGetPos 默认不认隐藏窗口（会直接抛错）—— 项目里 BackdropFeature 踩过同一个坑。
        ; 用完恢复原值，免得改变其它代码的可见性语义。
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            g.Show("Hide")

            ; 伴生窗口在屏幕上时按「同宽上下堆叠」摆放 —— 两个窗口拼成一列，界面规整。
            ; 摆不成（伙伴已被关掉、或屏幕塞不下两窗）才退回记忆位置 / 默认落点。
            if !this._StackWithPeer(ghwnd) {
                rect := State.GetHiddenRect()
                if State.HasHiddenRect() && this.IsUsableRect(rect.x, rect.y, rect.w, rect.h) {
                    ; ⚠ 必须用 WinMove 而非 g.Move：g.Move 收的是「逻辑单位」，会自动乘 DPI 比
                    ;   （本机 1.5）。而 rect 来自 WinGetPos，是「物理像素」——喂给 g.Move 会被
                    ;   二次放大（实测 1629,238 → 2444,357）。WinMove 与 WinGetPos 同一单位，配套。
                    WinMove(rect.x, rect.y, rect.w, rect.h, "ahk_id " . ghwnd)
                } else {
                    State.ClearHiddenRect()
                    this._MoveToDefault(g, ghwnd)
                }
            }
        } finally {
            DetectHiddenWindows(detectOld)
        }

        g.Show()
        WinRestore("ahk_id " . ghwnd)
    }

    ; 与伴生窗口上下堆叠成规整的一列：同宽、左边对齐、上下紧贴。
    ; 笔记窗口固定在伴生窗口上方，顶边贴工作区顶部，宽度跟着伴生窗口走。
    ;
    ; 伴生窗口若已在屏幕下半区（上方能容下笔记窗口）就原地不动；
    ; 若它贴着屏幕顶部、上方塞不下，就把它**下移**到底边贴工作区底 ——
    ; 只改位置、尺寸一字不动，腾出上半屏给笔记窗口。
    ; 两步都不成立（屏幕太矮、两窗叠起来放不下）才返回 false，交回记忆位置处置。
    ;
    ; ⚠ 这套算法假定「伙伴在下、笔记在上」。以后接入的窗口若更适合左右并排，
    ;   改的就是这里 —— 发布方一行不用动（见 README 同名小节）。
    ; 调用方需已开 DetectHiddenWindows（窗口可能还是 Show("Hide") 状态）。
    static _StackWithPeer(ghwnd) {
        pr := this._peerRect
        if !IsObject(pr)
            return false

        ; 已经适配过一次 → 格局已定，绝不再按伴生窗口的位置重算。
        ;   本方法有两条调用路径，这一条把两条都管住：
        ;     · _PlaceWindow —— Alt+Z 展开笔记时，于是走「记忆位置」= 用户自己的格局；
        ;     · _AdaptToPeer —— 伴生窗口落位时，那里另有 _docked 守卫，这里是双保险。
        ;   返回 false 让调用方回落到记忆位置，正是想要的：不动坐标。
        if this._docked
            return false

        ; 伴生窗口可能已经被关掉了 —— 那份坐标就没意义了，交回记忆位置 / 默认落点处置
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            alive := WinExist("ahk_id " . pr.hwnd)
        } finally {
            DetectHiddenWindows(detectOld)
        }
        if !alive
            return false

        ; 先把窗口尺寸量定型：Show("Hide") 之后控件固有尺寸要等 OnSize 跑完才反映到
        ; 外框上，这之后设的尺寸才不会被随后的布局盖回去
        nw := 0, nh := 0
        if !this._MeasureStable(ghwnd, &nw, &nh)
            return false

        ; 头一次堆叠时留个底 —— 堆叠会把窗口压矮，收窗口时要照这份原始位置尺寸还原。
        ; ⚠ 只在「还没有底稿」时留：底稿的语义是**用户自己的窗口格局**。
        ;   若每次堆叠都重留，就会把上一次堆叠后的压扁尺寸当作新旧稿 ——
        ;   「堆叠 → Alt+Z 收起 → Alt+Z 展开」一轮下来，实测 711x885 会被写成 744x533，
        ;   之后终端不在时窗口就再也回不到原来的大小。
        ;   底稿由 _RememberPosition 在**非堆叠态**隐藏时刷新（见那里的注释）。
        if !IsObject(this._preStackRect) {
            try {
                WinGetPos(&ox, &oy, &ow, &oh, "ahk_id " . ghwnd)
                this._preStackRect := {x: ox, y: oy, w: ow, h: oh}
            } catch
                this._preStackRect := ""
        }

        tx := pr.x, ty := pr.y, tw := pr.w, th := pr.h

        ; 工作区取伴生窗口所在的**那块**显示器 —— 它可能被放到副屏上
        monIdx := 1
        cx := tx + tw // 2, cy := ty + th // 2
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
        nFrame := this._InvisibleFrame(ghwnd)
        peerVisL := tx - pFrame.l, peerVisT := ty - pFrame.t
        peerVisR := tx + tw - pFrame.r, peerVisB := ty + th - pFrame.b

        ; 笔记窗口的可见目标：左边与伙伴对齐、同宽、顶边贴工作区顶、底边在伙伴上方留 gap
        noteVisL := peerVisL
        noteVisW := peerVisR - peerVisL
        noteVisT := wkTop + margin

        ; 方案一：伴生窗口原地不动，笔记窗口填它上方的空间
        noteVisB := peerVisT - gap
        if (noteVisB - noteVisT >= minH && noteVisW + nFrame.r - nFrame.l >= minW) {
            this._MoveToVisible(ghwnd, noteVisL, noteVisT, noteVisW, noteVisB - noteVisT, nFrame)
            this._stacked := true
            return true
        }

        ; 方案二：伴生窗口已经顶到屏幕上方了 —— 把它下移到底边贴工作区底，
        ; 尺寸（宽高）原样保留，只挪位置
        newPeerVisT := (wkBottom - margin) - (peerVisB - peerVisT)
        noteVisB := newPeerVisT - gap
        if (noteVisB - noteVisT >= minH && noteVisW + nFrame.r - nFrame.l >= minW) {
            newPeerY := newPeerVisT + pFrame.t
            WinMove(tx, newPeerY, , , "ahk_id " . pr.hwnd)   ; 宽高留空 = 保持不变
            ; 伴生窗口挪动后 rect 变了，同步记一份 —— 下次呼出不必再算
            this._peerRect := {hwnd: pr.hwnd, x: tx, y: newPeerY, w: tw, h: th}
            this._MoveToVisible(ghwnd, noteVisL, noteVisT, noteVisW, noteVisB - noteVisT, nFrame)
            this._stacked := true
            return true
        }

        return false
    }

    ; 按「可见边界」摆放窗口：传进来的是肉眼看到的矩形，
    ; 内部补上该窗口的不可见边框偏移再交给 WinMove（后者认的是含边框的矩形）。
    static _MoveToVisible(hwnd, visL, visT, visW, visH, frame) {
        rectW := Max(visW + frame.r - frame.l, 1)
        rectH := Max(visH + frame.b - frame.t, 1)
        WinMove(visL + frame.l, visT + frame.t, rectW, rectH, "ahk_id " . hwnd)
    }

    ; 窗口矩形比「可见边界」多出来的那圈不可见调整边框（含 DWM 阴影）。
    ; 返回 {l, t, r, b} = 各自的「矩形边 − 可见边」，左 / 上通常为负。
    ; ⚠ 本机（150% 缩放）实测：左 −9、上 0、右 9、下 9；25% 缩放或旧系统上可能不同，
    ;   所以这里每次都实测，不写死。
    static _InvisibleFrame(hwnd) {
        buf := Buffer(16, 0)
        try
            DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 9, "ptr", buf, "uint", 16)
        catch
            return {l: 0, t: 0, r: 0, b: 0}   ; 拿不到就当作没有不可见边框
        WinGetPos(&rx, &ry, &rw, &rh, "ahk_id " . hwnd)
        vx := NumGet(buf, 0, "int"), vy := NumGet(buf, 4, "int")
        vr := NumGet(buf, 8, "int"), vb := NumGet(buf, 12, "int")
        return {l: rx - vx, t: ry - vy, r: (rx + rw) - vr, b: (ry + rh) - vb}
    }

    ; 移到默认落点
    static _MoveToDefault(g, ghwnd) {
        w := 0, h := 0
        if !this._MeasureStable(ghwnd, &w, &h)
            return
        rect := this._DefaultRect(w, h)
        ; 同样用 WinMove（物理像素），只设位置不设尺寸 —— 尺寸交给 AHK 按 DPI 决定
        WinMove(rect.x, rect.y, , , "ahk_id " . ghwnd)
    }

    ; 等窗口尺寸稳定下来。Show 之后控件的固有尺寸要等 OnSize 跑完才反映到窗口外框上，
    ; 连续两次量到同一个值才认为定型。全程窗口不可见，多花几毫秒用户看不见。
    static _MeasureStable(hwnd, &w, &h) {
        prevW := -1, prevH := -1, same := 0
        loop 40 {
            try
                WinGetPos(&_, &_, &w, &h, "ahk_id " . hwnd)
            catch
                return false
            if (w > 0 && h > 0 && w = prevW && h = prevH) {
                if (++same >= 2)
                    return true
            } else {
                same := 0
            }
            prevW := w, prevH := h
            Sleep 5
        }
        return (w > 0 && h > 0)
    }

    ; 默认落点坐标：贴主屏工作区右上角 —— 右边距 Config.PlaceRight、顶边距 Config.PlaceTop。
    ;
    ; ⚠ 尺寸必须按窗口的「实际」值算 —— A_ScreenWidth 是物理像素，而窗口实际宽含 DPI
    ;   放大后的控件与边框（本机约 711），远大于逻辑值 Config.WinW = 450。
    ; ⚠ 用 MonitorGetWorkArea 而非 A_ScreenWidth / A_ScreenHeight：后者是全屏尺寸，
    ;   多屏时也只反映主屏。
    static _DefaultRect(winW, winH) {
        MonitorGetWorkArea(MonitorGetPrimary(), &wkLeft, &wkTop, &wkRight, &wkBottom)
        posX := wkRight - winW - Config.PlaceRight
        posY := wkTop + Config.PlaceTop
        ; 窗口比工作区还大（或边距过大）时兜底，免得落到负坐标、跑到屏幕外
        if (posX < wkLeft + 10)
            posX := wkLeft + 10
        if (posY < wkTop + 10)
            posY := wkTop + 10
        if (posY + winH > wkBottom)
            posY := wkBottom - winH - 10
        return {x: posX, y: posY}
    }

    ; ═══ 光标与重绘 ═══

    ; 还原光标：隐藏前记录的位置优先，没有记录就落到正文末尾
    static _RestoreCaret(hwnd) {
        if State.HasCaret() {
            caret := State.GetCaret()
            totalLen := SendMessage(0x000E, 0, 0, hwnd)
            EditorService.SetSel(hwnd, Min(caret.min, totalLen), Min(caret.max, totalLen))
        } else {
            EditorService.MoveCaretToEnd(hwnd)
        }
    }

    ; WM_SETREDRAW：批量改动期间关掉重绘，避免中间态闪烁
    static _SuspendRedraw(hwnd) => SendMessage(0x000B, 0, 0, hwnd)
    static _ResumeRedraw(hwnd) => SendMessage(0x000B, 1, 0, hwnd)
}


; ═══════════════════════════════════════════════════════════════════════════
;  ② 输入与编辑
; ═══════════════════════════════════════════════════════════════════════════

class PasteFeature {
    static PastePlain() {
        hwnd := State.GetEd()
        txt := ClipboardService.GetText()
        if (txt = "")
            return
        EditorService.InsertText(hwnd, txt)
        EventBus.Emit("Paste.Plain")
    }
}


class LineEditFeature {
    static DeleteLine() => EditorService.DeleteCurrentLine(State.GetEd())
    static DuplicateLine() => EditorService.DuplicateCurrentLine(State.GetEd())
    static MoveUp() => EditorService.MoveLineUp(State.GetEd())
    static MoveDown() => EditorService.MoveLineDown(State.GetEd())
    static Indent() {
        EditorService.DoIndent(State.GetEd())
        EventBus.Emit("Line.Indented")
    }
    static Outdent() {
        EditorService.DoOutdent(State.GetEd())
        EventBus.Emit("Line.Outdented")
    }
}


class UndoFeature {
    static Undo() => EditorService.Undo(State.GetEd())
    static Redo() => EditorService.Redo(State.GetEd())
}


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
    ; 底边贴工作区底。与 DeepSeekFeature._PlaceLikeTerminal 是同一份公式 ——
    ; Feature 之间不许互相调用，所以各留一份；两处要同步改。
    ;
    ; 为什么需要这一步：终端的落点由 Windows Terminal 的 initialPosition 决定，
    ; 那份值是用户当年按「有任务栏」设的。本机实测 —— 终端 1803,540（底边 1560，
    ; 离工作区底 40px），而 DeepSeek 按公式落在 1801,580（底边贴 1600，任务栏已
    ; 改为自动隐藏），两个伙伴高度不齐、堆叠观感不一致。对齐后两者落在同一处。
    ;
    ; ⚠ 只挪位置，**尺寸一个不动**：终端的尺寸归 Windows Terminal 的 profile 管
    ;   （本机 744x1020），夺过来会和用户自己的终端设置打架。
    ; ⚠ 全程 WinMove（物理像素），别混用 Gui.Move（它收逻辑单位、还会再乘一次 DPI）。
    static _PlaceLikeDeepSeek(hwnd) {
        WinGetPos(, , &w, &h, "ahk_id " . hwnd)
        if (w <= 0 || h <= 0)
            return

        MonitorGetWorkArea(MonitorGetPrimary(), &wkLeft, &wkTop, &wkRight, &wkBottom)
        x := wkRight - w - Config.PlaceRight
        y := wkBottom - h
        ; 兜底：工作区比窗口还小时别落到屏幕外
        if (x < wkLeft + 10)
            x := wkLeft + 10
        if (y < wkTop + 10)
            y := wkTop + 10
        WinMove(x, y, , , "ahk_id " . hwnd)
    }

    ; 广播伴生窗口此刻的实际位置与尺寸，供笔记窗口让位（Peer.Placed 契约）。
    ; ⚠ 读之前要开 DetectHiddenWindows —— 它刚 WinShow 出来，隐藏窗口 WinGetPos 会抛错。
    static _BroadcastRect(hwnd) {
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            if !WinExist("ahk_id " . hwnd)
                return
            WinGetPos(&x, &y, &w, &h, "ahk_id " . hwnd)
        } finally {
            DetectHiddenWindows(detectOld)
        }
        if (w > 0 && h > 0)
            EventBus.Emit("Peer.Placed", {hwnd: hwnd, x: x, y: y, w: w, h: h})
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
; 与 PowerShellFeature 同一套玩法，只把「终端」换成浏览器的 app 窗口。
; 三条广播的语义、时序、失败兜底完全一致；接入步骤见 README「开发指南」。
;
; 有两处与终端不同，值得记下：
;   ① **窗口怎么认**：终端能靠标题（"SevenNote PowerShell"）认，浏览器不能 ——
;      本机日常 Edge 里也开着 DeepSeek 网页，标题一样含 "DeepSeek"，靠标题一认就错。
;      这里改用「专用 profile → 独立进程树」的办法：窗口按 PID 认。
;   ② **尺寸与位置要自己给**：终端由 Windows Terminal 的 profile 决定落点（本机 744x1020），
;      浏览器却每次都落在 Chromium 的默认点。这里按目标尺寸摆到「和终端同一处」——
;      右侧贴工作区右缘、底边贴工作区底，于是两种伙伴产出的堆叠效果一模一样。
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
        fallback := 0
        try {
            for h in WinGetList("ahk_exe " . this._ExeName()) {
                if (WinGetPID("ahk_id " . h) != pid)
                    continue
                if (WinGetClass("ahk_id " . h) != "Chrome_WidgetWin_1")
                    continue
                if DllCall("IsWindowVisible", "ptr", h, "int")
                    return h
                if !fallback
                    fallback := h
            }
        } finally {
            DetectHiddenWindows(detectOld)
        }
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

        ; 启动前先记下现有的同族 PID，之后「新出现的那个」就是我们的 ——
        ; 专用 profile 保证了它必定是条新进程树，不会并进用户自己的浏览器里。
        before := this._PidSnapshot()

        try {
            ; ⚠ --window-size 收的是**逻辑像素**（DIP），而 WinMove / WinGetPos 认物理像素。
            ;   本机 150% 缩放（A_ScreenDPI = 144）下传 496x680，实际得到 744x1020 —— 正合目标。
            ;   换个缩放比例就得跟着变，所以按 A_ScreenDPI 反算，别写死。
            w := this._TargetW() * 96 // A_ScreenDPI
            h := this._TargetH() * 96 // A_ScreenDPI
            ; --app：独立的应用窗口（无标签栏），观感接近桌面应用，而不是「浏览器里多开了个标签」。
            ;       ⚠ 它有地址栏 —— 原以为「无地址栏」，实测 Edge 155 起 app 窗口就自带
            ;       （UIA 查到 view_1017「地址和搜索栏」，换全新 profile 启动也一样，是 Edge 的产品
            ;       行为，不是本项目的代码效果）。副作用挺好：这扇窗能直接输网址浏览其他网页，
            ;       当轻量浏览器用。若哪天 Edge 改回无地址栏而仍要导航，换 --new-window 即可。
            ;       app 窗口的标题归页面管（本机实测为 "DeepSeek"），所以别拿标题找它。
            ; --user-data-dir：独立 profile（理由见类头）。
            ; --no-first-run / --no-default-browser-check：跳过首次运行的欢迎页与
            ;       「是否设为默认浏览器」的询问 —— 新 profile 每次都问，很烦。
            cmd := '"' . exe . '" --app=' . this._url
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
    ; 底边贴工作区底。终端那边的同一份公式是 PowerShellFeature._PlaceLikeDeepSeek ——
    ; Feature 之间不许互相调用，所以各留一份；两处要同步改。
    ; ⚠ 全程 WinMove（物理像素），别混用 Gui.Move（它收逻辑单位、还会再乘一次 DPI）。
    static _PlaceLikeTerminal(hwnd) {
        w := this._TargetW(), h := this._TargetH()
        MonitorGetWorkArea(MonitorGetPrimary(), &wkLeft, &wkTop, &wkRight, &wkBottom)
        x := wkRight - w - Config.PlaceRight
        y := wkBottom - h
        ; 兜底：工作区比目标窗口还小时别落到屏幕外
        if (x < wkLeft + 10)
            x := wkLeft + 10
        if (y < wkTop + 10)
            y := wkTop + 10
        WinMove(x, y, w, h, "ahk_id " . hwnd)
    }

    ; 广播伙伴窗口此刻的实际位置与尺寸，供笔记窗口让位（Peer.Placed 契约）。
    ; 与 PowerShellFeature._BroadcastRect 是同一份逻辑 —— Feature 之间不许互相调用，
    ; 所以各留一份；两处要同步改。
    ; ⚠ 读之前要开 DetectHiddenWindows —— 窗口刚 WinShow 出来，隐藏态 WinGetPos 会抛错。
    static _BroadcastRect(hwnd) {
        detectOld := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            if !WinExist("ahk_id " . hwnd)
                return
            WinGetPos(&x, &y, &w, &h, "ahk_id " . hwnd)
        } finally {
            DetectHiddenWindows(detectOld)
        }
        if (w > 0 && h > 0)
            EventBus.Emit("Peer.Placed", {hwnd: hwnd, x: x, y: y, w: w, h: h})
    }

    ; 目标窗口尺寸（物理像素）。默认对齐本机 Windows Terminal profile 的 744x1020 ——
    ; 这样 Alt+C 与 Alt+X 两种堆叠布局观感完全一致。
    ; 换机器 / 换终端尺寸：在 _config.ini 的 [Paths] DeepSeekW / DeepSeekH 覆盖。
    static _TargetW() {
        v := ConfigService.ReadInt("Paths", "DeepSeekW", 0)
        return v > 0 ? v : 744
    }

    static _TargetH() {
        v := ConfigService.ReadInt("Paths", "DeepSeekH", 0)
        return v > 0 ? v : 1020
    }

    ; 浏览器：优先 _config.ini 指定；否则按 Edge → Chrome 顺序探测（Windows 自带 Edge，
    ; 命中率最高）。只要是 Chromium 系（支持 --app / --user-data-dir）都能用。
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

    static IsEnabled() => this._enabled

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

class LoadFeature {
    static Load() {
        date := FormatTime(, "yyyy-MM-dd")
        State.SetDate(date)
        hwnd := State.GetEd()
        rtfPath := NoteStoreService.FindRtf(date)
        if (rtfPath = "") {
            EditorService.SetText(hwnd, "# 📅 " . date . " 速记`n")
            return
        }
        EditorService.LoadRTFFromFile(hwnd, rtfPath)
    }
}


class SaveFeature {
    static Init() {
        EventBus.On("Window.BeforeHide", (*) => SaveFeature.Save())
    }

    static Save() {
        Critical(1)
        try {
            date := State.GetDate()
            if (date = "")
                date := FormatTime(, "yyyy-MM-dd")
            hwnd := State.GetEd()

            EventBus.Emit("Save.Before", {date: date})

            ; 空笔记不落盘（含删除已有文件）
            if EditorService.IsEmptyNote(hwnd, date) {
                rtfPath := NoteStoreService.FindRtf(date)
                mdPath := NoteStoreService.FindMd(date)
                if (rtfPath != "" && FileExist(rtfPath))
                    try FileDelete(rtfPath)
                if (mdPath != "" && FileExist(mdPath))
                    try FileDelete(mdPath)
                EventBus.Emit("Save.After", {date: date, ok: true})
                Critical(0)
                return
            }

            ; 先查后存（保留带标签的文件名）
            rtfPath := NoteStoreService.FindRtf(date)
            if (rtfPath = "")
                rtfPath := NoteStoreService.DefaultRtfPath(date)

            mdPath := NoteStoreService.FindMd(date)
            if (mdPath = "")
                mdPath := NoteStoreService.DefaultMdPath(date)

            tempRtf := NoteStoreService.TempDir() . "\pandoc-src.rtf"
            NoteStoreService.EnsureDir(NoteStoreService.TempDir())

            ; 主 RTF（936 GBK）
            ok := EditorService.SaveRTFToFile(hwnd, rtfPath, 936)
            if !ok {
                NoteStoreService.WriteFile(mdPath
                    , EditorService.GetText(hwnd), "UTF-8")
                EventBus.Emit("Save.After", {date: date, ok: false})
                Critical(0)
                return
            }

            ; Pandoc 转换（v1.9：IsAvailable 已加大小检查）
            if PandocService.IsAvailable() {
                EditorService.SaveRTFToFile(hwnd, tempRtf, 65001)
                PandocService.Convert(tempRtf, mdPath, date)
                if FileExist(tempRtf)
                    try FileDelete(tempRtf)
            } else {
                NoteStoreService.WriteFile(mdPath
                    , EditorService.GetText(hwnd), "UTF-8")
            }
            EventBus.Emit("Save.After", {date: date, ok: true})
            EventBus.Emit("Save.Completed", {time: FormatTime(, "HH:mm")})
        } catch as e {
            EventBus.Emit("Error.Occurred", {msg: "保存失败：" . e.Message})
        }
        Critical(0)
    }
}


class AutoSaveFeature {
    static Init(intervalMs := 120000) {
        SetTimer(() => AutoSaveFeature.Tick(), intervalMs)
    }
    static Tick() {
        g := State.GetGui()
        if DllCall("IsWindowVisible", "ptr", g.Hwnd, "int")
            SaveFeature.Save()
    }
}


class TimestampFeature {
    static Init() {
        EventBus.On("Save.Before",   (*) => TimestampFeature.StripIfEmpty())
        EventBus.On("Date.Switched", (*) => TimestampFeature.CheckAndAppend())
    }

    static CheckAndAppend() {
        hwnd := State.GetEd()
        lastMin := EditorService.FindLastTimestamp(hwnd)
        if (lastMin < 0) {
            EditorService.AppendTimestamp(hwnd)
            return true
        }
        nowMin := FormatTime(, "HH") * 60 + FormatTime(, "mm")
        diff := EditorService.DiffMinutes(nowMin, lastMin)
        if (diff >= Config.TimestampInterval) {
            EditorService.AppendTimestamp(hwnd)
            return true
        }
        return false
    }

    static StripIfEmpty() {
        hwnd := State.GetEd()
        return EditorService.StripEmptyTimestamp(hwnd)
    }

    static Append() {
        hwnd := State.GetEd()
        EditorService.AppendTimestamp(hwnd)
        EventBus.Emit("Timestamp.Appended")
    }

    static Separator() {
        hwnd := State.GetEd()
        EditorService.InsertSeparator(hwnd)
        EventBus.Emit("Separator.Inserted")
    }

    static Heading() {
        hwnd := State.GetEd()
        EditorService.InsertHeading(hwnd)
        EventBus.Emit("Heading.Inserted")
    }
}


; ═══════════════════════════════════════════════════════════════════════════
;  ④ 查看与浏览
; ═══════════════════════════════════════════════════════════════════════════

class SearchFeature {
    static BAR_BG := "E8D8B8"
    static EDIT_BG := "FFF8E7"
    static EDIT_TEXT := "3D2B1F"
    static BAR_DIM := "9C8060"
    static BAR_W := 220

    static _barBg := ""
    static _icon := ""
    static _edit := ""
    static _count := ""
    static _stat := ""
    static _themeLabel := ""
    static _edCtrl := ""

    static _visible := false
    static _lastKeyword := ""
    static _matches := []
    static _current := 0

    static Init(barBg, icon, edit, count, statCtrl, themeLabelCtrl, edCtrl) {
        this._barBg := barBg
        this._icon := icon
        this._edit := edit
        this._count := count
        this._stat := statCtrl
        this._themeLabel := themeLabelCtrl
        this._edCtrl := edCtrl
        this._SetVisible(false)
        ; 搜索条配色跟着主题走：否则「星空」底下会横插一块浅米黄
        this._ApplyColors()
        EventBus.On("Theme.Changed", (*) => this._ApplyColors())
    }

    static IsVisible() => this._visible

    static Show() {
        if this._visible
            return
        this._visible := true
        this._SetVisible(true)

        g := State.GetGui()
        if g {
            WinGetClientPos(&cx, &cy, &w, &h, "ahk_id " . g.Hwnd)
            try this._edCtrl.Move(8, 72, w - 16, h - 110)
        }

        hwndEd := this._edCtrl.Hwnd
        minBuf := Buffer(4, 0)
        maxBuf := Buffer(4, 0)
        DllCall("SendMessage"
            , "ptr", hwndEd
            , "uint", 0x00B0
            , "ptr", minBuf.Ptr
            , "ptr", maxBuf.Ptr)
        curMax := NumGet(maxBuf, 0, "uint")
        DllCall("SendMessage"
            , "ptr", hwndEd
            , "uint", 0x00B1
            , "ptr", curMax
            , "ptr", curMax)

        this._edit.Focus()
        DllCall("SendMessage"
            , "ptr", this._edit.Hwnd
            , "uint", 0x00B1
            , "ptr", 0
            , "ptr", 0x7FFFFFFF)
    }

    static Hide() {
        if !this._visible
            return
        this._visible := false
        this._SetVisible(false)

        g := State.GetGui()
        if g {
            WinGetClientPos(&cx, &cy, &w, &h, "ahk_id " . g.Hwnd)
            try this._edCtrl.Move(8, 32, w - 16, h - 70)
        }

        hwndEd := this._edCtrl.Hwnd
        minBuf := Buffer(4, 0)
        maxBuf := Buffer(4, 0)
        DllCall("SendMessage"
            , "ptr", hwndEd
            , "uint", 0x00B0
            , "ptr", minBuf.Ptr
            , "ptr", maxBuf.Ptr)
        savedMax := NumGet(maxBuf, 0, "uint")
        DllCall("SetFocus", "ptr", hwndEd)
        DllCall("SendMessage"
            , "ptr", hwndEd
            , "uint", 0x00B1
            , "ptr", savedMax
            , "ptr", savedMax)
    }

    static Toggle() {
        if this._visible
            this.Hide()
        else
            this.Show()
    }

    static _SetVisible(v) {
        try this._barBg.Visible := v
        try this._icon.Visible := v
        try this._edit.Visible := v
        try this._count.Visible := v
    }

    ; ─── 配色：跟着当前主题走 ───
    ; 搜索条底色要比编辑区深一档才分得出来（深色主题下方向相反），所以统一用
    ; 「主题编辑区底色 + 25% 次级文字色」混出来，浅色 / 深色两边都自然。
    static _ApplyColors() {
        t := ThemeService.Themes[ThemeService.GetCurrent()]
        if !IsObject(t)
            return
        barBg := this._Mix(t.edBg, t.dim, 25)
        for ctrl in [this._barBg, this._icon, this._count]
            try ctrl.Opt("Background" . barBg)
        try this._icon.Opt("c" . t.dim)
        try this._count.Opt("c" . t.dim)
        try this._edit.Opt("Background" . t.edBg . " c" . t.text)
    }

    ; 两个十六进制 RGB 之间线性插值，pct = 第二个色的百分比（0-100）
    static _Mix(hexA, hexB, pct) {
        out := ""
        loop 3 {
            i := (A_Index - 1) * 2
            a := Integer("0x" . SubStr(hexA, i + 1, 2))
            b := Integer("0x" . SubStr(hexB, i + 1, 2))
            out .= Format("{:02X}", Round(a + (b - a) * pct / 100))
        }
        return out
    }

    static Layout(winWidth, winHeight) {
        try this._barBg.Move(8, 32, this.BAR_W, 32)
        try this._icon.Move(12, 38, 22, 20)
        try this._edit.Move(36, 36, 130, 24)
        try this._count.Move(170, 39, 44, 20)
    }

    static Next() => this._DoSearch("down")
    static Prev() => this._DoSearch("up")

    static _DoSearch(direction) {
        hwndEd := State.GetEd()
        kw := this._edit.Value
        if (kw = "") {
            this._count.Value := ""
            return
        }

        if (kw != this._lastKeyword) {
            this._lastKeyword := kw
            this._matches := []
            pos := 0
            while (true) {
                r := EditorService.FindTextEx(hwndEd, kw, pos, "down")
                if (r = -1)
                    break
                this._matches.Push(r)
                pos := r.end
            }
            this._current := 0
        }

        if (this._matches.Length = 0) {
            this._count.Value := "未找到"
            return
        }

        if (direction = "down") {
            this._current++
            if (this._current > this._matches.Length)
                this._current := 1
        } else {
            this._current--
            if (this._current < 1)
                this._current := this._matches.Length
        }

        m := this._matches[this._current]

        DllCall("SetFocus", "ptr", hwndEd)
        DllCall("SendMessage"
            , "ptr", hwndEd
            , "uint", 0x00B1
            , "ptr", m.start
            , "ptr", m.end)

        lineIdx := SendMessage(0x00C9, m.start, 0, hwndEd)
        EditorService.ScrollToLineFixed(hwndEd, lineIdx)

        SetTimer(() => this._edit.Focus(), -300)

        this._count.Value := this._current . "/" . this._matches.Length
    }
}


class StatFeature {
    static _lastLen := -1
    static Init(intervalMs := 500) {
        SetTimer(() => StatFeature.Tick(), intervalMs)
    }
    static Tick() {
        stat := State.GetStat()
        if !stat
            return
        hwnd := State.GetEd()
        if !hwnd
            return
        len := EditorService.GetLength(hwnd)
        if (len != this._lastLen) {
            this._lastLen := len
            stat.Value := len . " 字"
        }
    }
}


class CaretFeature {
    static Init() {
        EventBus.On("Window.BeforeHide", (*) => CaretFeature.Save())
        EventBus.On("Window.Shown", (*) => CaretFeature.Restore())
    }
    static Save() {
        sel := EditorService.GetSel(State.GetEd())
        State.SetCaret(sel.min, sel.max)
    }
    static Restore() {
        hwnd := State.GetEd()
        totalLen := SendMessage(0x000E, 0, 0, hwnd)
        if !State.HasCaret() {
            EditorService.MoveCaretToEnd(hwnd)
            return
        }
        caret := State.GetCaret()
        selMin := Min(caret.min, totalLen)
        selMax := Min(caret.max, totalLen)
        if (selMin < 0)
            selMin := 0
        if (selMax < 0)
            selMax := 0
        EditorService.SetSel(hwnd, selMin, selMax)
    }
}


; ═══════════════════════════════════════════════════════════════════════════
;  ⑤ 组织与管理
; ═══════════════════════════════════════════════════════════════════════════

class DateSwitchFeature {
    static Switch(offset) {
        SaveFeature.Save()

        curDate := State.GetDate()
        if (curDate = "")
            return false

        ymd := StrReplace(curDate, "-", "")
        target := DateAdd(ymd, offset, "Days")
        targetStr := FormatTime(target, "yyyy-MM-dd")

        State.SetDate(targetStr)
        State.ResetCaret()

        hwnd := State.GetEd()
        rtfPath := NoteStoreService.FindRtf(targetStr)
        if (rtfPath = "") {
            EditorService.SetText(hwnd, "# 📅 " . targetStr . " 速记`n")
        } else {
            EditorService.LoadRTFFromFile(hwnd, rtfPath)
        }
        EditorService.EmptyUndo(hwnd)
        EventBus.Emit("Date.Switched", {date: targetStr})
        return true
    }
}


class DateJumpFeature {
    static ShowDialog() {
        winTitle := Config.AppName . " · 搜索跳转"
        if WinExist(winTitle . " ahk_class AutoHotkeyGUI") {
            WinActivate(winTitle . " ahk_class AutoHotkeyGUI")
            return
        }

        dlg := Gui("+Resize +AlwaysOnTop", winTitle)
        dlg.SetFont("s11", "Microsoft YaHei")
        dlg.BackColor := "FFF8E7"

        dlg.AddText("x14 y16 w60", "搜索：")
        searchEdit := dlg.AddEdit("x72 y12 w480 h26")
        searchEdit.SetFont("s11", "Microsoft YaHei")

        dlg.AddText("x14 y46 w560 c808080"
            , "支持模糊搜索：日期（2026-09）或标签（机器学习），空格分隔多条件")

        lv := dlg.AddListView("x14 y74 w538 h360", ["日期", "标签"])
        lv.ModifyCol(1, 130)
        lv.ModifyCol(2, 400)
        lv.SetFont("s10", "Microsoft YaHei")

        allItems := NoteStoreService.ListAllTags()

        ApplyFilter(keyword) {
            lv.Delete()
            if (keyword = "") {
                for item in allItems
                    lv.Add(, item.date, item.tag)
                return
            }
            words := StrSplit(keyword, " ")
            for item in allItems {
                matched := true
                for w in words {
                    w := Trim(w)
                    if (w = "")
                        continue
                    if !(InStr(item.date, w) || InStr(item.tag, w)) {
                        matched := false
                        break
                    }
                }
                if matched
                    lv.Add(, item.date, item.tag)
            }
        }

        searchEdit.OnEvent("Change", (*) => ApplyFilter(Trim(searchEdit.Value)))

        JumpToSelected(*) {
            row := lv.GetNext()
            if (row = 0)
                return
            dateStr := lv.GetText(row, 1)
            if (dateStr = "")
                return
            dlg.Destroy()
            DateJumpFeature.JumpTo(dateStr)
        }

        lv.OnEvent("DoubleClick", JumpToSelected)

        btnClose := dlg.AddButton("x472 y444 w80", "关闭")
        btnClose.OnEvent("Click", (*) => dlg.Destroy())

        HotIfWinActive(winTitle)
        Hotkey("Enter", (*) => JumpToSelected(), "On")
        Hotkey("NumpadEnter", (*) => JumpToSelected(), "On")
        Hotkey("Escape", (*) => dlg.Destroy(), "On")
        HotIf()
        dlg.OnEvent("Close", (*) => (
            HotIfWinActive(winTitle),
            Hotkey("Enter", "Off"),
            Hotkey("NumpadEnter", "Off"),
            Hotkey("Escape", "Off"),
            HotIf(),
            dlg.Destroy()
        ))

        ApplyFilter("")
        dlg.Show("w560 h485")
        searchEdit.Focus()
    }

    static JumpTo(dateStr) {
        SaveFeature.Save()
        State.SetDate(dateStr)
        State.ResetCaret()
        hwnd := State.GetEd()

        rtfPath := NoteStoreService.FindRtf(dateStr)
        if (rtfPath != "") {
            EditorService.LoadRTFFromFile(hwnd, rtfPath)
        } else {
            EditorService.SetText(hwnd, "# 📅 " . dateStr . " 速记`n")
        }
        EditorService.EmptyUndo(hwnd)
        EventBus.Emit("Date.Switched", {date: dateStr})
    }
}


class TitleFeature {
    static ShowDialog() {
        date := State.GetDate()
        if (date = "")
            return

        rtfPath := NoteStoreService.FindRtf(date)
        currentTag := (rtfPath != "")
            ? NoteStoreService.TagFromFileName(rtfPath) : ""

        dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "日期标签")
        dlg.SetFont("s11", "Microsoft YaHei")
        dlg.BackColor := "FFF8E7"
        dlg.AddText("x14 y12 w340", "为 " . date . " 设置标签：")
        edit := dlg.AddEdit("x14 y38 w340 h26", currentTag)
        edit.SetFont("s11", "Microsoft YaHei")
        btnOk := dlg.AddButton("Default x14 y76 w100", "确定")
        btnClear := dlg.AddButton("x122 y76 w100", "清除")
        btnCancel := dlg.AddButton("x230 y76 w100", "取消")
        dlg.AddText("x14 y112 w340 c808080"
            , "示例：2026-09-19-机器学习`n标签会写进文件名，黑曜石里一眼可见")

        OnSubmit(*) {
            newTag := NoteStoreService.SanitizeTag(edit.Value)
            dlg.Destroy()
            TitleFeature._Apply(date, currentTag, newTag)
        }

        OnClear(*) {
            dlg.Destroy()
            if (currentTag != "")
                TitleFeature._Apply(date, currentTag, "")
        }

        btnOk.OnEvent("Click", OnSubmit)
        btnClear.OnEvent("Click", OnClear)
        btnCancel.OnEvent("Click", (*) => dlg.Destroy())
        dlg.OnEvent("Escape", (*) => dlg.Destroy())
        dlg.OnEvent("Close", (*) => dlg.Destroy())

        edit.Focus()
        dlg.Show("w380 h150")
    }

    static _Apply(date, oldTag, newTag) {
        if (oldTag = newTag)
            return
        SaveFeature.Save()
        if (newTag != "" && NoteStoreService.FindRtf(date) = "") {
            EventBus.Emit("Error.Occurred"
                , {msg: "空笔记无法设标签，请先写内容"})
            return
        }
        if NoteStoreService.RenameWithTag(date, oldTag, newTag) {
            EventBus.Emit("Title.Changed"
                , {date: date, tag: newTag})
        } else {
            MsgBox("重命名失败，请检查文件是否被其他程序占用"
                , "错误", 48)
        }
    }
}


class GoTodayFeature {
    static Go() {
        today := FormatTime(, "yyyy-MM-dd")
        if (State.GetDate() = today) {
            EventBus.Emit("Error.Occurred", {msg: "已经是今天"})
            return
        }
        DateJumpFeature.JumpTo(today)
    }
}


; ═══════════════════════════════════════════════════════════════════════════
;  横切 · 美观
; ═══════════════════════════════════════════════════════════════════════════

class ThemeFeature {
    static Next() => ThemeService.Next()
    static LoadFromConfig() => ThemeService.LoadFromConfig()
}


class FontFeature {
    static NextFont() => FontService.NextFont()
    static BiggerSize() => FontService.BiggerSize()
    static SmallerSize() => FontService.SmallerSize()
    static LoadFromConfig() => FontService.LoadFromConfig()
}


; ─── BackdropFeature：带背景图的主题（星空）───
; 背景图不是「全局贴一张」，而是主题自带的属性：ThemeService.Themes 里带 bg 字段的
; 主题（目前只有「星空」）才铺图，切到别的主题自动撤掉、回到纯底色。
; 文字浮在图上、图铺满整个编辑区（终端式，非相框式）。
class BackdropFeature {
    static _lastW := 0
    static _lastH := 0
    static _applied := false  ; 当前是否已铺图（启动期窗口尺寸是 0，此时为 false）
    static _bgPath := ""      ; 当前主题生效的背景图路径（空 = 该主题没有背景图）
    static _bgAlpha := 60     ; 当前生效的遮罩不透明度（0-100）

    static _pending := false  ; 已排入一次延迟铺图（防抖合并中）
    static _doneX := 0        ; 上一次真正铺图用的矩形：同尺寸的 WM_SIZE 直接跳过
    static _doneY := 0
    static _doneW := 0
    static _doneH := 0

    ; ⚠ 必须与组合根 OnSize 里 ed.Move 的矩形完全一致，否则图层会与编辑区错位
    static _Rect(winW, winH) {
        if SearchFeature.IsVisible()
            return {x: 8, y: 72, w: winW - 16, h: winH - 110}
        return {x: 8, y: 32, w: winW - 16, h: winH - 70}
    }

    static Init(g) {
        BackdropService.Attach(g)
        ; 换主题 = 换背景图：带 bg 的主题铺图，其余撤图。没有开关 —— 想关就切主题，
        ; 这也正是「往 Themes 里加一行就是一套新主题」的原设计。
        EventBus.On("Theme.Changed", (*) => this.Refresh())
    }

    ; 按当前主题刷新「图路径 + 遮罩色 + 不透明度」缓存。配置优先于主题自带，
    ; 这样不动源码也能换图 / 调压暗程度：
    ;   [Appearance] BackdropImage   —— 非空则覆盖主题的 bg
    ;   [Appearance] BackdropOpacity —— >0 则覆盖主题的 bgAlpha
    static _Sync() {
        t := ThemeService.Themes[ThemeService.GetCurrent()]
        hasBg := (IsObject(t) && t.HasProp("bg"))

        p := ConfigService.Read("Appearance", "BackdropImage")
        if (p = "" && hasBg)
            p := t.bg
        this._bgPath := p
        BackdropService.SetImage(p)

        a := ConfigService.ReadInt("Appearance", "BackdropOpacity", 0)
        if (a <= 0)
            a := hasBg ? t.bgAlpha : 60
        this._bgAlpha := a

        ; 缩放模式：主题写了 bgFit 就按它来（竖版人物图得用 contain，否则上下会被裁掉），
        ; 没写的（含「星空」等老主题）一律 cover —— 铺图行为分毫不变。
        BackdropService.SetFit(hasBg && t.HasProp("bgFit") ? t.bgFit : "cover")

        ; 遮罩色取主题编辑区底色，图的色调就跟着主题走（图缺失时它就是那块纯底色）
        BackdropService.SetMask(hasBg ? t.edBg : "", this._bgAlpha)
    }

    static Refresh() {
        this._Sync()
        this._Apply()
    }

    ; 窗口尺寸变化：记下尺寸，已铺图则按新尺寸重铺
    static Layout(winW, winH) {
        this._lastW := winW
        this._lastH := winH
        ; 启动时窗口尚未 Show，尺寸仍是 0，此时不铺；首次拿到有效尺寸后补一次，
        ; 否则图会一直不出来。
        if !this._applied {
            if (this._bgPath != "" && BackdropService.HasImage())
                this._Apply()
            return
        }
        ; ⚠ 拉伸窗口时 WM_SIZE 每秒触发几十次，而每次都重做整张合成 —— 2400 宽的图
        ;   逐级对折 + HALFTONE 缩放本机要几十毫秒，绘制队列被塞满，编辑区文字跟着
        ;   反复重画，看上去就是「文字时隐时无」。这里改成防抖：先记下尺寸，停手
        ;   80ms 后才铺一次；拖动过程中背景停在上一帧，不再与文字抢绘制。
        this._ScheduleRender()
    }

    ; 把 80ms 内的连续尺寸变化合并成一次铺图（拖窗口时每秒几十次 WM_SIZE 只干一次活）
    static _ScheduleRender() {
        if this._pending
            return
        this._pending := true
        SetTimer(() => this._RenderNow(), -80)
    }

    ; 真正铺图。矩形与上次相同就不重做合成（同尺寸的 WM_SIZE 是空转）。
    ; force = true 用于换主题 —— 那时尺寸可能没变，但图换了，必须重铺。
    static _RenderNow(force := false) {
        this._pending := false
        rect := this._Rect(this._lastW, this._lastH)
        if (!force && (rect.x = this._doneX) && (rect.y = this._doneY)
            && (rect.w = this._doneW) && (rect.h = this._doneH))
            return
        if BackdropService.Render(rect.x, rect.y, rect.w, rect.h) {
            this._doneX := rect.x, this._doneY := rect.y
            this._doneW := rect.w, this._doneH := rect.h
            ; 位图刚换过，而编辑区是 WS_EX_TRANSPARENT（自己不画背景），面上留着的
            ; 还是上一帧的文字 —— 让它重画一次，免得拉伸后出现「文字缺一块」。
            ; 不带 UPDATENOW：走正常消息队列，别在拖动时同步阻塞。
            try DllCall("RedrawWindow", "ptr", State.GetEd(), "ptr", 0, "ptr", 0
                , "uint", 0x0001 | 0x0004)      ; INVALIDATE | ERASE
        }
    }

    ; 按 _bgPath 决定铺图还是撤图：主题没带 bg、图片不存在、窗口还没尺寸 —— 三种都走撤图。
    static _Apply() {
        hwndEd := State.GetEd()
        if !hwndEd
            return
        ; 未显示过的 Gui 窗口 WS_VISIBLE = 0，WinSetExStyle 会匹配不到
        DetectHiddenWindows(true)

        useIt := this._applied := (this._bgPath != "" && BackdropService.HasImage()
            && this._lastW > 1 && this._lastH > 1)

        if useIt {
            BackdropService.SetVisible(true)
            this._RenderNow(true)          ; 换主题 / 首次铺图：立即铺，不走 80ms 防抖
            ; 图铺好之后再开透明，避免出现「编辑区已不画背景、图还没画」的空窗
            WinSetExStyle("+0x20", "ahk_id " . hwndEd)   ; WS_EX_TRANSPARENT
        } else {
            ; 先恢复不透明再撤图，顺序反过来会闪一下白底
            WinSetExStyle("-0x20", "ahk_id " . hwndEd)
            BackdropService.SetVisible(false)
            ; 撤图后清掉尺寸记忆，同尺寸再切回图主题时才会真的重铺
            this._doneW := 0, this._doneH := 0
        }

        try DllCall("RedrawWindow", "ptr", hwndEd, "ptr", 0, "ptr", 0
            , "uint", 0x0001 | 0x0004 | 0x0100)   ; INVALIDATE | ERASE | UPDATENOW
    }
}


; ═══════════════════════════════════════════════════════════════════════════
;  组合根 —— 装配 + 启动
; ═══════════════════════════════════════════════════════════════════════════

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
ConfigService.SetDefault("Appearance", "FontIndex", "1")
ConfigService.SetDefault("Appearance", "FontSizeIndex", "2")
; 背景图：图片路径（留空=不启用）、遮罩不透明度 0-100、开关状态
ConfigService.SetDefault("Appearance", "BackdropImage", "")
ConfigService.SetDefault("Appearance", "BackdropOpacity", "0")
ConfigService.SetDefault("Input", "CapsLockMap", "0")
ConfigService.SetDefault("Paths", "Vault", "")

; ═══ 首次运行：引导用户选择笔记目录 ═══
EnsureVaultConfigured()

; ═══ 确保笔记目录存在 ═══
DirCreate(Config.GetVault())

; ─── 创建主窗口 ───
g := Gui(, Config.AppName)
g.Opt("+AlwaysOnTop +Resize +MinSize450x300")
g.SetFont("s14", "楷体")
g.BackColor := "FFF8E7"

; ─── 顶部控件：字数 + 标签 + 主题标签 ───
stat := g.AddText("x8 y8 w60 h20 Left", "0 字")
stat.SetFont("s10 c9CA3AF", "楷体")

tagCtrl := g.AddText("x72 y8 w190 h20 Left cA89880", "")
tagCtrl.SetFont("s10", "楷体")

themeLabel := g.AddText("x266 y8 w176 h20 Right", "")
themeLabel.SetFont("s10 c3D2B1F", "楷体")

; ─── RichEdit 编辑区 ───
ed := g.AddCustom("ClassRichEdit50W x8 y32 w434 h440 +0x201004")
SendMessage(0x0443, 0, 0xE7F8FF, ed.Hwnd)
ed.SetFont("s14 c3D2B1F", "楷体")
SendMessage(0x0453, 100, 0, ed.Hwnd)

; ─── 搜索条控件（初始隐藏）───
searchBarBg := g.AddText("x8 y32 w220 h32 Background" . SearchFeature.BAR_BG, "")
searchBarBg.SetFont("s1", "楷体")
searchBarBg.Visible := false

searchIcon := g.AddText("x12 y38 w22 h20 Background" . SearchFeature.BAR_BG . " c" . SearchFeature.BAR_DIM, "🔍")
searchIcon.SetFont("s11", "楷体")
searchIcon.Visible := false

searchEdit := g.AddEdit("x36 y36 w130 h24 Background" . SearchFeature.EDIT_BG . " c" . SearchFeature.EDIT_TEXT, "")
searchEdit.SetFont("s12", "楷体")
searchEdit.Visible := false

searchCount := g.AddText("x170 y39 w44 h20 Background" . SearchFeature.BAR_BG . " c" . SearchFeature.BAR_DIM . " Left", "")
searchCount.SetFont("s10", "楷体")
searchCount.Visible := false

; ─── 底部控件：日期 + 提示 ───
dateCtrl := g.AddText("x8 y520 w180 h22 Left cA89880", "")
dateCtrl.SetFont("s10", "楷体")

msgCtrl := g.AddText("x162 y520 w280 h22 Right cA89880", "")
msgCtrl.SetFont("s10", "楷体")

; ─── 注册到 State ───
State.SetGui(g)
State.SetEd(ed.Hwnd)
State.SetStat(stat)
State.SetDateCtrl(dateCtrl)
State.SetMsgCtrl(msgCtrl)
State.SetThemeLabel(themeLabel)
State.SetTagCtrl(tagCtrl)

; ─── 窗口事件 ───
g.OnEvent("Close", (*) => (g.Hide(), true))
g.OnEvent("Size", OnSize)

OnSize(guiObj, MinMax, Width, Height) {
    ; 最小化时 Width/Height 是图标尺寸（实测约 158x26），
    ; 控件按它算会得到负尺寸，直接跳过
    if (MinMax = -1)
        return
    try stat.Move(8, 8, 60, 20)
    try tagCtrl.Move(72, 8, 190, 20)
    try themeLabel.Move(Width - 184, 8, 176, 20)
    SearchFeature.Layout(Width, Height)
    if SearchFeature.IsVisible() {
        try ed.Move(8, 72, Width - 16, Height - 110)
    } else {
        try ed.Move(8, 32, Width - 16, Height - 70)
    }
    try dateCtrl.Move(8, Height - 30, 180, 22)
    try msgCtrl.Move(Width - 288, Height - 30, 280, 22)
    ; 背景图跟着编辑区一起缩放（未开启时内部直接返回，无额外开销）
    BackdropFeature.Layout(Width, Height)
}

; ═══ 挂载 Feature ═══
; 最先挂 —— 它订阅「外部窗口（PowerShell / DeepSeek）要出现了」，
; 得赶在第一次 Alt+C / Alt+X 之前注册好
WindowFeature.Init()
StatusBar.Init(dateCtrl, tagCtrl, msgCtrl)
SearchFeature.Init(searchBarBg, searchIcon, searchEdit, searchCount, stat, themeLabel, ed)
AutoSaveFeature.Init(Config.AutoSaveInterval)
SaveFeature.Init()
CaretFeature.Init()
StatFeature.Init(Config.StatInterval)
TimestampFeature.Init()
PowerShellFeature.Init()
DeepSeekFeature.Init()
BackdropFeature.Init(g)

; ═══ 全局热键（按用户旅程排序）═══
; ① 唤起与关闭
!z::WindowFeature.Toggle()
!+z::{
    SaveFeature.Save()
    ExitApp()
}
!h::ShowHelp()

; ② 输入与编辑
!+c::CapsLockFeature.Toggle()

; ⑤ 组织与管理
!Up::DateSwitchFeature.Switch(-1)
!Down::DateSwitchFeature.Switch(1)
!Home::GoTodayFeature.Go()

; 横切·美观
!t::ThemeFeature.Next()
!+t::FontFeature.NextFont()
!=::FontFeature.BiggerSize()
!-::FontFeature.SmallerSize()

; ═══ 编辑器内热键（按用户旅程排序）═══
#HotIf WinActive("ahk_id " . State.GetGuiHwnd()) && !SearchFeature.IsVisible()
; ② 输入与编辑
$^y::LineEditFeature.DeleteLine()
$^d::LineEditFeature.DuplicateLine()
$^+v::PasteFeature.PastePlain()
$^z::UndoFeature.Undo()
$^+z::UndoFeature.Redo()
$^+Up::LineEditFeature.MoveUp()
$^+Down::LineEditFeature.MoveDown()
Tab::LineEditFeature.Indent()
+Tab::LineEditFeature.Outdent()

; ③ 保存与持久化
$^s::SaveFeature.Save()
$^t::TimestampFeature.Append()
$^h::TimestampFeature.Separator()
$^+h::TimestampFeature.Heading()

; ④ 查看与浏览
$^f::SearchFeature.Show()

; ⑤ 组织与管理
$^g::DateJumpFeature.ShowDialog()
$^+t::TitleFeature.ShowDialog()
#HotIf

; ④ 查看与浏览（搜索栏显示时）
#HotIf WinActive("ahk_id " . State.GetGuiHwnd()) && SearchFeature.IsVisible()
Enter::SearchFeature.Next()
+Enter::SearchFeature.Prev()
Esc::SearchFeature.Hide()
#HotIf

; ═══ 启动 ═══
LoadFeature.Load()
TimestampFeature.CheckAndAppend()
StatusBar.RefreshTag()

ThemeFeature.LoadFromConfig()
FontFeature.LoadFromConfig()
CapsLockFeature.LoadFromConfig()
; 背景图不必在这里初始化：ThemeService.Apply 会 Emit "Theme.Changed"，
; 而 BackdropFeature 在 Init 时就挂上了这个事件 —— 启动与换主题都自动重铺。

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
    SetTimer(() => tip.Destroy(), -1500)
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

    text := ""
        . "【窗口】`n"
        . "   Alt+Z            呼出 / 隐藏`n"
        . "   Alt+Shift+Z      保存并退出`n"
        . "   Alt+H            显示本帮助`n"
        . "`n"
        . "【外观】`n"
        . "   Alt+T            切换主题（含带背景图的「星空」）`n"
        . "   Shift+Alt+T      切换字体`n"
        . "   Alt+=            调大字号`n"
        . "   Alt+-            调小字号`n"
        . "                      （外观设置自动保存）`n"
        . "`n"
        . "【输入增强】`n"
        . "   Alt+Shift+C      切换 CapsLock 键盘映射`n"
        . "                      （开启后 CapsLock+H/J/K/L = 方向键）`n"
        . "   Alt+C            唤出 / 隐藏 PowerShell（笔记自动让位）`n"
        . "   Alt+X            呼出 / 隐藏 DeepSeek 网页（笔记自动让位）`n"
        . "`n"
        . "【搜索】`n"
        . "   Ctrl+F           打开搜索栏`n"
        . "   Enter            下一个匹配`n"
        . "   Shift+Enter      上一个匹配`n"
        . "   Esc              关闭搜索栏`n"
        . "`n"
        . "【保存】`n"
        . "   Ctrl+S           手动保存`n"
        . "`n"
        . "【日期与标签】`n"
        . "   Alt+↑            前一天`n"
        . "   Alt+↓            后一天`n"
        . "   Alt+Home         回到今天`n"
        . "   Ctrl+G           搜索跳转（日期 / 标签）`n"
        . "   Ctrl+Shift+T     为当前日期设置标签`n"
        . "`n"
        . "【编辑】`n"
        . "   Ctrl+Z           撤销`n"
        . "   Ctrl+Shift+Z     重做`n"
        . "   Ctrl+Y           删除当前行`n"
        . "   Ctrl+D           复制当前行到下方`n"
        . "   Ctrl+Shift+↑     上移当前行`n"
        . "   Ctrl+Shift+↓     下移当前行`n"
        . "   Tab              增加缩进（4 空格）`n"
        . "   Shift+Tab        减少缩进`n"
        . "   Ctrl+Shift+V     粘贴为纯文本`n"
        . "`n"
        . "【分段】`n"
        . "   Ctrl+T           追加时间戳`n"
        . "   Ctrl+H           插入分隔线`n"
        . "   Ctrl+Shift+H     插入 ## 分段标题`n"
        . "`n"
        . "—————————————————————————`n"
        . "   " . Config.AppName . " v" . Config.Version . "`n"
        . "   当前笔记目录：`n"
        . "   " . Config.GetVault() . "`n"
        . "   按 ESC 或点关闭按钮关闭"

    help.AddText("x20 y15 w400", text)
    help.Show("w440 h920")

    HotIfWinActive(Config.AppName . " · 快捷键")
    Hotkey("Esc", (*) => help.Destroy())
    HotIf()
}
