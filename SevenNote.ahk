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
;
;  依赖：pandoc.exe（软依赖，未安装则 MD 降级为纯文本）
; ═══════════════════════════════════════════════════════════════════════════


; ═══════════════════════════════════════════════════════════════════════════
;  KERNEL 骨架层
; ═══════════════════════════════════════════════════════════════════════════

class Config {
    static AppName := "SevenNote"
    static Version := "1.9"

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
    static AutoSaveInterval := 120000
    static StatInterval := 500
    static TimestampInterval := 60
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
        {name: "纸白",   win: "FAFAFA", edBg: "FFFFFF", text: "333333", dim: "999999"}
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

        if !this._loading
            this.SaveToConfig()

        EventBus.Emit("Theme.Changed", {name: t.name, idx: this._current})
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
        hbm := this._Compose(w, h)
        if !hbm
            return false

        ; STM_SETIMAGE(0x0172) / wParam = IMAGE_BITMAP(0)
        ; SS_BITMAP 控件会自行销毁上一张位图，这里不必手动 DeleteObject
        SendMessage(0x0172, 0, hbm, this._picCtrl.Hwnd)
        return true
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
    static _Compose(w, h) {
        hdcScreen := DllCall("GetDC", "ptr", 0, "ptr")
        hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcScreen, "ptr")
        hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcScreen, "int", w, "int", h, "ptr")
        oldMem := DllCall("SelectObject", "ptr", hdcMem, "ptr", hbm, "ptr")

        ; ① 原图 → 目标尺寸（HALFTONE 比默认的 COLORONCOLOR 平滑）
        hdcSrc := DllCall("CreateCompatibleDC", "ptr", hdcScreen, "ptr")
        oldSrc := DllCall("SelectObject", "ptr", hdcSrc, "ptr", this._srcBmp, "ptr")
        DllCall("SetStretchBltMode", "ptr", hdcMem, "int", 4)      ; HALFTONE
        DllCall("SetBrushOrgEx", "ptr", hdcMem, "int", 0, "int", 0, "ptr", 0)
        DllCall("StretchBlt", "ptr", hdcMem, "int", 0, "int", 0, "int", w, "int", h
            , "ptr", hdcSrc, "int", 0, "int", 0, "int", this._srcW, "int", this._srcH
            , "uint", 0x00CC0020)                                  ; SRCCOPY
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
        EventBus.On("Backdrop.Toggled",   (d) => this.SetMsg(d.on ? "✓ 背景图：开" : "✓ 背景图：关"))
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
    static _RememberPosition(hwnd) {
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
    ; 末尾补一次 WinRestore，覆盖“在最小化状态下呼出”的情形。
    ;
    ; ⚠ 尺寸不硬设 —— 本机 150% 缩放（A_ScreenDPI = 144）下 Gui 控件坐标会按 DPI 放大 1.5 倍，
    ;   窗口最小尺寸由控件固有尺寸决定，Config.WinW/WinH 是「逻辑单位」而 WinMove 收「物理像素」。
    ;   实测把 450x550 直接传给 WinMove：宽被 +MinSize450x300（物理 675x450）拒绝，
    ;   高却通过了，结果窗口被压矮（881 → 550）。故尺寸交给 AHK 按 DPI 自行决定。
    static _PlaceWindow(g, ghwnd) {
        g.Show()
        WinRestore("ahk_id " . ghwnd)

        rect := State.GetHiddenRect()
        if State.HasHiddenRect() && this.IsUsableRect(rect.x, rect.y, rect.w, rect.h) {
            ; 记忆里存的是物理像素（WinGetPos 读到的），与 WinMove 同一单位，可直接还原
            WinMove(rect.x, rect.y, rect.w, rect.h, "ahk_id " . ghwnd)
            return
        }

        State.ClearHiddenRect()
        this._MoveToDefault(ghwnd)
    }

    ; 移到默认落点。必须先 Show 再量窗口，因为尺寸由 AHK 按 DPI 决定，Show 之前无从得知
    static _MoveToDefault(ghwnd) {
        try
            WinGetPos(&_, &_, &winW, &winH, "ahk_id " . ghwnd)
        catch
            return
        rect := this._DefaultRect(winW, winH)
        WinMove(rect.x, rect.y, , , "ahk_id " . ghwnd)
    }

    ; 默认落点坐标：右侧偏上，右边距 220px，并保证不出屏。
    ; ⚠ 横坐标必须按窗口的「实际」尺寸算 —— A_ScreenWidth 是物理像素，而窗口实际宽含
    ;   DPI 放大后的控件与边框（本机约 697），远大于逻辑值 Config.WinW = 450；
    ;   拿 Config.WinW 去算会让窗口右边缘探出屏幕 27px。
    static _DefaultRect(winW, winH) {
        posX := A_ScreenWidth - winW - 220
        posY := (A_ScreenHeight - winH) // 3
        if (posX < 10)
            posX := 10
        if (posY < 10)
            posY := 10
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

        if (WinActive("ahk_id " . hwnd)) {
            WinHide("ahk_id " . hwnd)
            return
        }

        this._ShowAndFocus(hwnd)
    }

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
        WinShow("ahk_id " . hwnd)
        WinActivate("ahk_id " . hwnd)
        try {
            WinSetAlwaysOnTop("On", "ahk_id " . hwnd)
        }
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

        try {
            command := "$Host.UI.RawUI.WindowTitle = '" . this._windowTitle . "'"
            Run('"' . this._powershellPath . '" -NoLogo -NoExit -Command "' . command . '"', this._StartDir())
        } catch as err {
            MsgBox("启动 PowerShell 失败：`n" . err.Message, "SevenNote", "Icon!")
            return
        }

        deadline := A_TickCount + 15000
        while (A_TickCount < deadline) {
            hwnd := this._FindPowerShellHwnd()
            if (hwnd != 0) {
                this._ShowAndFocus(hwnd)
                return
            }
            Sleep(150)
        }

        hwnd := this._FindPowerShellHwnd()
        if (hwnd != 0) {
            this._ShowAndFocus(hwnd)
        } else {
            MsgBox("PowerShell 已启动，但未能找到它的窗口。", "SevenNote", "Icon!")
        }
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


; ─── BackdropFeature：背景图开关与布局同步 ───
; 终端式背景图：文字直接浮在图上、图铺满整个编辑区（非相框式）。
; 开关状态存配置；窗口尺寸变化时由组合根的 OnSize 调 Layout 重新铺图。
class BackdropFeature {
    static _on := false
    static _lastW := 0
    static _lastH := 0
    static _applied := false

    static IsOn() => this._on

    ; ⚠ 必须与组合根 OnSize 里 ed.Move 的矩形完全一致，否则图层会与编辑区错位
    static _Rect(winW, winH) {
        if SearchFeature.IsVisible()
            return {x: 8, y: 72, w: winW - 16, h: winH - 110}
        return {x: 8, y: 32, w: winW - 16, h: winH - 70}
    }

    static Init(g) {
        BackdropService.Attach(g)
        ; 换主题时遮罩色要跟着主题底色走，需要重新合成
        EventBus.On("Theme.Changed", (*) => this.Refresh())
    }

    ; 开关：Alt+B
    static Toggle() {
        ; 先把配置里的路径灌进 Service 再判断，否则 _imgPath 还是空串、必然误判
        BackdropService.SetImage(ConfigService.Read("Appearance", "BackdropImage"))
        if !BackdropService.HasImage() {
            EventBus.Emit("Error.Occurred"
                , {msg: "未配置背景图：请在 _config.ini 里填 [Appearance] BackdropImage"})
            return
        }
        this._on := !this._on
        this._Apply()
        ConfigService.Write("Appearance", "BackdropOn", this._on ? 1 : 0)
    }

    static Refresh() {
        if this._on
            this._Apply()
    }

    ; 窗口尺寸变化：记下尺寸，开启状态下重新合成铺满
    static Layout(winW, winH) {
        this._lastW := winW
        this._lastH := winH
        if !this._on
            return
        ; 启动时窗口尚未 Show，_Apply 会因尺寸为 0 而只把 _on 置真、不发图层；
        ; 这里首次拿到有效尺寸后补一次完整应用，否则图会一直不显示。
        if !this._applied {
            this._Apply()
            return
        }
        rect := this._Rect(winW, winH)
        BackdropService.Render(rect.x, rect.y, rect.w, rect.h)
    }

    static _Apply() {
        hwndEd := State.GetEd()
        if !hwndEd
            return
        ; 未显示过的 Gui 窗口 WS_VISIBLE = 0，WinSetExStyle 会匹配不到
        DetectHiddenWindows(true)

        useIt := this._on && BackdropService.HasImage()
            && this._lastW > 1 && this._lastH > 1
        this._applied := useIt

        if useIt {
            ; 遮罩色取当前主题的编辑区底色，让图与主题色调一致
            t := ThemeService.Themes[ThemeService.GetCurrent()]
            BackdropService.SetMask(t.edBg
                , ConfigService.ReadInt("Appearance", "BackdropOpacity", 80))
            BackdropService.SetImage(ConfigService.Read("Appearance", "BackdropImage"))
            BackdropService.SetVisible(true)
            this.Layout(this._lastW, this._lastH)
            ; 图铺好之后再开透明，避免出现「编辑区已不画背景、图还没画」的空窗
            WinSetExStyle("+0x20", "ahk_id " . hwndEd)   ; WS_EX_TRANSPARENT
        } else {
            ; 先恢复不透明再撤图，顺序反过来会闪一下白底
            WinSetExStyle("-0x20", "ahk_id " . hwndEd)
            BackdropService.SetVisible(false)
        }

        try DllCall("RedrawWindow", "ptr", hwndEd, "ptr", 0, "ptr", 0
            , "uint", 0x0001 | 0x0004 | 0x0100)   ; INVALIDATE | ERASE | UPDATENOW
        EventBus.Emit("Backdrop.Toggled", {on: useIt})
    }

    static LoadFromConfig() {
        if !ConfigService.ReadInt("Appearance", "BackdropOn", 0)
            return
        ; 同上：必须先 SetImage，_imgPath 才会有值
        BackdropService.SetImage(ConfigService.Read("Appearance", "BackdropImage"))
        if !BackdropService.HasImage()
            return
        this._on := true
        this._Apply()
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
ConfigService.SetDefault("Appearance", "BackdropOpacity", "80")
ConfigService.SetDefault("Appearance", "BackdropOn", "0")
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
StatusBar.Init(dateCtrl, tagCtrl, msgCtrl)
SearchFeature.Init(searchBarBg, searchIcon, searchEdit, searchCount, stat, themeLabel, ed)
AutoSaveFeature.Init(Config.AutoSaveInterval)
SaveFeature.Init()
CaretFeature.Init()
StatFeature.Init(Config.StatInterval)
TimestampFeature.Init()
PowerShellFeature.Init()
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
!b::BackdropFeature.Toggle()
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
; 背景图放最后：它要按当前主题的编辑区底色合成遮罩色
BackdropFeature.LoadFromConfig()

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
        . "   Alt+B            背景图 开 / 关`n"
        . "   Alt+T            切换主题`n"
        . "   Shift+Alt+T      切换字体`n"
        . "   Alt+=            调大字号`n"
        . "   Alt+-            调小字号`n"
        . "                      （外观设置自动保存）`n"
        . "`n"
        . "【输入增强】`n"
        . "   Alt+Shift+C      切换 CapsLock 键盘映射`n"
        . "   Alt+C            唤出 / 隐藏 PowerShell`n"
        . "                      （开启后 CapsLock+H/J/K/L = 方向键）`n"
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