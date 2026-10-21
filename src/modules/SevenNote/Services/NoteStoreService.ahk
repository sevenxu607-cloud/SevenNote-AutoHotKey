#Requires AutoHotkey v2.0
; ======================================================================
;  NoteStoreService
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

; ─── NoteStoreService：笔记仓库管理员 ───
class NoteStoreService {
    ; ─── 路径拼接 ───
    ; rootDir 只给探针 / 测试覆写根目录用（别让测试往真实笔记库里写文件）；
    ; 生产留空即 Config.GetVault()。二参数版本与 PandocService / NoteImageService 共用，
    ; 保证「文件落在哪」和「markdown 里怎么写」永远出自同一处。
    static AssetsDir(date, rootDir := "") => (rootDir != "" ? rootDir : Config.GetVault()) . "\_assets\" . date

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

    ; ─── 路径拼接：rtf / md 两条只此一处（无标签时的默认名，与带标签名同目录同名式）───
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

    ; 把字符串数组拼成「行分隔列表」—— 内置 Sort 收的是字符串，不是数组
    static _JoinLines(arr) {
        s := ""
        for i, v in arr
            s .= (i = 1 ? "" : "`n") . v
        return s
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
        ; 按日期倒序。原先用冒泡（O(n²)）—— 1000 篇笔记要约 50 万次 StrCompare，
        ; 在 AHK 解释器里是数百 ms 级；换成内置 Sort（C 层实现，O(n log n)）。
        ; 排序键 = 「日期 + TAB + 6 位下标」：
        ;   · 日期在前 = 主序，等价于原先的「按 date 比较」；
        ;   · TAB(0x09) 比任何日期字符都小，同一天的多条（2026-09-19-a.md /
        ;     2026-09-19-b.md 这类）不会互相串位；
        ;   · 下标后缀保证键唯一，顺带让同一天的多条保持目录枚举顺序（排序稳定）。
        ; 选项 "CR"：C = 区分大小写 → 纯字典序（日期是 `YYYY-MM-DD`，字典序即时间序，
        ;           也避开系统区域设置的自然排序，结果只取决于字节）；
        ;          R = 降序。
        n := result.Length
        if (n > 1) {
            byKey := Map()
            keys := []
            for i, item in result {
                k := item.date . "`t" . Format("{:06}", i)
                byKey[k] := item
                keys.Push(k)
            }
            result := []
            for k in StrSplit(Sort(this._JoinLines(keys), "CR"), "`n")
                result.Push(byKey[k])
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
