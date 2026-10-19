#Requires AutoHotkey v2.0
; ======================================================================
;  EditorService + RichEdit stream callbacks
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

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

    ; ─── 内容变短后，把 RichEdit 的内部滚动位置对齐回 SCROLLINFO ───（v2.4.4）
    ; 现象（用户报的「删掉末尾几行空行，画面不跟着变，拖一下滚动条才一次性闪回」）：
    ;   · 删除后 SCROLLINFO 已经重算对了 —— nMax / nPos 都是新值，滚动条滑块当场变长；
    ;   · 但 EM_GETFIRSTVISIBLELINE 和画面都停在删除前 —— 内容已短、视口没动；
    ;   · 唯 WM_VSCROLL 能修，WM_SIZE / 重绘 / EM_SCROLLCARET 都不能。
    ; 实测（40 行正文 + 末尾 5 个空行，150% 缩放）：
    ;   删除后   fv=19  nPos=502  nMax=1476   scrollPt.y=684   画面像素只变 0.04%
    ;   写回后   fv=13  nPos=501  nMax=1476   scrollPt.y=501   画面重绘 9.9%
    ; 做法：EM_SETSCROLLPOS 只把 SCROLLINFO 里**已经算好**的 nPos 交给 RichEdit，
    ;      它会据此重算行布局并重绘；滚动位置本身不动（前后都在底部）。
    ; 注意：EM_GETSCROLLPOS 读到的像素位置仍是旧值（684 = 多算了 5 行 × 36px），
    ;      所以不能用它往回写——必须用 nPos。但反过来，**它正好可以当「是否脱节」的探针**：
    ;      scrollPt.y 与 nPos 对不上，就说明行布局还停在旧内容上。
    ; ⚠ 只在真的脱节时动手：若两者一致（正常滚动 / 正常编辑），直接返回。
    ;   无条件写回虽然实测不重绘，但**用户正拖滚动条时会把它弹回去**，
    ;   表现就是「滑条经常拖不动」——必须靠这道守卫挡掉。
    static SyncScrollAfterShrink(hwnd) {
        si := Buffer(28, 0)
        NumPut("uint", 28, si, 0)        ; cbSize
        NumPut("uint", 0x17, si, 4)      ; SIF_RANGE | SIF_PAGE | SIF_POS | SIF_TRACKPOS
        if !DllCall("GetScrollInfo", "ptr", hwnd, "int", 1, "ptr", si, "int")   ; SB_VERT
            return
        npos := NumGet(si, 20, "int")
        nmax := NumGet(si, 12, "int")
        npage := NumGet(si, 16, "int")

        ; ① 脱节检测：内部渲染用的像素位置 vs SCROLLINFO 的逻辑位置
        cur := Buffer(8, 0)
        DllCall("SendMessageW", "ptr", hwnd, "uint", 0x04DD, "uptr", 0, "ptr", cur, "ptr")   ; EM_GETSCROLLPOS
        py := NumGet(cur, 4, "int")
        if (Abs(py - npos) <= 2)
            return      ; 已同步 —— 别打扰用户正常的滚动/编辑

        ; ② 删除后 nPos 可能比 max-page 多 1（实测 502 对 501）。钳到上界之后，
        ;    结果与「拖一下滚动条」逐像素一致（DIFF 0.0374 -> 0.0000）。
        if (nmax > npage && npos > nmax - npage)
            npos := nmax - npage
        pt := Buffer(8, 0)
        NumPut("int", 0, pt, 0)         ; x
        NumPut("int", npos, pt, 4)      ; y = nPos
        DllCall("SendMessageW", "ptr", hwnd, "uint", 0x04DE, "uptr", 0, "ptr", pt, "ptr")   ; EM_SETSCROLLPOS
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

    static AppendTimestamp(hwnd) {
        text := this.GetText(hwnd)
        trimmed := RTrim(text, "`t`r`n")
        if (StrLen(trimmed) < StrLen(text))
            this.SetText(hwnd, trimmed)
        this.MoveCaretToEnd(hwnd)
        now := FormatTime(, "HH:mm")
        this.InsertText(hwnd, "`n`n" . this.CLOCK . " " . now . "`n")
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

    ; 新建日期 / 切到空日期时写给编辑区的日期头。
    ; ⚠ 只能从这里取 —— 原先这段字符串在 LoadFeature / DateJumpFeature / DateSwitchFeature
    ;   各写一遍（3 份），任一处与上面 IsEmptyNote 的剥离串脱钩，空笔记就会因「剥不干净」
    ;   被判成非空，于是空笔记照样落盘。
    static EmptyNoteHeader(date) => "# 📅 " . date . " 速记`n"
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
