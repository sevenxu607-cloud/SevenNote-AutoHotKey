#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════
;  JsText —— AHK 字符串 ↔ JS 字符串字面量 / JSON 字符串
; ═══════════════════════════════════════════════════════════════════════
;  纯能力：只收字符串、返回字符串，不读 Config / State、不发 EventBus。
;
;  为什么单独抽出来：WebView2 的 ExecuteScriptAsync 有两个硬约束，缺一个就
;  「静默什么都不发生」，而且两次踩的都是同一个地方 ——
;    ① 送进去的 JS 必须是合法的 ES 源码。笔记正文里随手一个换行 / 引号 / 反斜杠
;       都会破坏字面量；更阴的是 **NUL**：AHK v2 的 StrReplace 把 Chr(0) 当终止符
;       （实测 StrReplace("a" Chr(0) "b", Chr(0), "X") 原样返回），所以**不能**靠
;       StrReplace 链做转义，只能逐字符重建。
;    ② 拿回来的结果是被 JSON 编码过的字符串（外层带引号、内部 \" \\ \n \uXXXX），
;       不解码就会把 `\n` 两个字面字符原样写进 .md。
; ═══════════════════════════════════════════════════════════════════════

class JsText {
    ; ─── AHK 字符串 → 可直接嵌进 JS 的字符串字面量（含外层引号）───
    ; 只对 4 类字符做转义：引号、反斜杠、控制字符（含 NUL）、U+2028/2029
    ; （后两个在 ES 里是行终止符，出现在字面量里会语法错）。
    ; 其余字符原样透传 —— 中文直接进源码即可，ExecuteScriptAsync 走 BSTR。
    static Escape(s) {
        s := "" . s
        out := Chr(34)
        n := StrLen(s)
        i := 1
        while (i <= n) {
            ; ⚠ Ord() 在 v2 只收一个字符（没有 v1 的下标形式），先取再 Ord
            ch := SubStr(s, i, 1)
            code := Ord(ch)
            if (code = 34) {
                out .= "\" . Chr(34)
            } else if (code = 92) {
                out .= "\\"
            } else if (code < 0x20) {
                ; \n \r \t 用短形式，其余（含 NUL）一律 \u00XX
                if (code = 10)
                    out .= "\n"
                else if (code = 13)
                    out .= "\r"
                else if (code = 9)
                    out .= "\t"
                else
                    out .= Format("\u{:04x}", code)
            } else if (code = 0x2028 || code = 0x2029) {
                out .= Format("\u{:04x}", code)
            } else {
                out .= ch
            }
            i++
        }
        return out . Chr(34)
    }

    ; ─── JSON 字符串（ExecuteScriptAsync 的原样返回）→ AHK 字符串 ───
    ; raw 形如 `"第一行\n第二行"`；不是这个形状（null / 数字 / 对象）时原样返回，
    ; 由调用方判断。未知转义按「丢掉反斜杠、保留字符」处理 —— JSON 规范里
    ; 非法转义本身就是错误输入，这里宁可多留一个字也不要吞掉正文。
    static Unquote(raw) {
        raw := "" . raw
        if (StrLen(raw) < 2)
            return raw
        if (SubStr(raw, 1, 1) != Chr(34) || SubStr(raw, -1) != Chr(34))
            return raw

        s := SubStr(raw, 2, StrLen(raw) - 2)
        n := StrLen(s)
        ; 无转义时直接返回，省掉逐字符循环（绝大多数短结果是这种）
        if !InStr(s, Chr(92))
            return s

        out := ""
        i := 1
        while (i <= n) {
            ch := SubStr(s, i, 1)
            if (ch != Chr(92)) {
                out .= ch
                i++
                continue
            }
            i++
            if (i > n) {
                out .= ch
                break
            }
            esc := SubStr(s, i, 1)
            i++
            if (esc = Chr(34))
                out .= Chr(34)
            else if (esc = Chr(92))
                out .= Chr(92)
            else if (esc = "/")
                out .= "/"
            else if (esc = "b")
                out .= Chr(8)
            else if (esc = "f")
                out .= Chr(12)
            else if (esc = "n")
                out .= Chr(10)
            else if (esc = "r")
                out .= Chr(13)
            else if (esc = "t")
                out .= Chr(9)
            else if (esc = "u") {
                hex := SubStr(s, i, 4)
                if (StrLen(hex) < 4) {
                    out .= esc
                    continue
                }
                i += 4
                ; 代理对：\uD83D\uDE00 由 JS 侧保证成对出现，逐个 Chr 拼即可
                ; （AHK v2 内部就是 UTF-16）。
                out .= Chr(Integer("0x" . hex))
            } else {
                out .= esc
            }
        }
        return out
    }
}
