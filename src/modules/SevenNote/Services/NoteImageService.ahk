#Requires AutoHotkey v2.0
; ═══════════════════════════════════════════════════════════════════════
;  NoteImageService —— 把 WebView2 粘贴进来的图片落盘
; ═══════════════════════════════════════════════════════════════════════
;  为什么要有它：图片内联成 data: URL 写进 markdown，一张 2400x2617 的截图
;  让笔记从 356 字符涨到 12,814,138 字符（实测，见 _spike/webview2/RESULTS.md）。
;  粘贴必须把字节交回 AHK 落盘，markdown 里只留路径。
;
;  落点与引用口径跟 PandocService._FixMarkdown **同一套**：
;    文件      <vault>\_assets\<date>\<name>.<ext>
;    markdown  ./_assets/<date>/<name>.<ext>
;  两处必须同式 —— 否则「RTF 转出来的图」和「粘贴进来的图」躺在同一个目录里
;  却写成两种路径，用户把 Markdown 副本拿到 Typora 里会有一半图打不开。
;
;  命名用 `sw_<HHmmss>_<nn>.<ext>`，**不占用** Pandoc 的 image1 / image2 序号：
;  重新保存时 Pandoc 会从 1 重新导出 media，撞名就把用户粘进去的图覆盖掉。
;
;  ⚠ 失败一律返回 ""，不抛错、不写日志 —— 日志归属由调用方（Feature）决定。
; ═══════════════════════════════════════════════════════════════════════
class NoteImageService {
    ; ─── base64 → 文件，返回可写进 markdown 的相对路径 ───
    ; b64    纯 base64 或完整 data: URL（两者都收，省得前端还要剥前缀）
    ; ext    扩展名，含不含点都行；空 / 非法 → png
    ; date   落哪个日期的 _assets 子目录；空 → 今天
    ; rootDir 只给测试 / 探针覆写根目录用，生产留空 = Config.GetVault()
    static SaveBase64(b64, ext := "png", date := "", rootDir := "") {
        if (b64 = "")
            return ""
        if (date = "")
            date := FormatTime(, "yyyy-MM-dd")
        ext := this._NormExt(ext)

        dec := this._Decode(b64)
        if !IsObject(dec)
            return ""

        dir := NoteStoreService.AssetsDir(date, rootDir)
        NoteStoreService.EnsureDir(dir)
        if !DirExist(dir)
            return ""

        name := this._NewName(dir, ext)
        if (name = "")
            return ""

        try {
            ; RawWrite 直接写字节，编码参数不起作用 —— 但 FileOpen 仍要带 "w"
            f := FileOpen(dir . "\" . name, "w")
            f.RawWrite(dec.buf, dec.size)
            f.Close()
        } catch {
            return ""
        }
        return "./_assets/" . date . "/" . name
    }

    ; ─── 扩展名归一 ───
    ; image/jpeg 经前端 extOf 出来是 "jpg"，但别处可能传 "jpeg" / ".PNG" / "svg+xml"
    static _NormExt(ext) {
        ext := RegExReplace(StrLower(LTrim(Trim(ext), ".")), "[^a-z0-9]")
        if (ext = "")
            return "png"
        if (ext = "jpeg")
            return "jpg"
        return ext
    }

    ; ─── 同一秒内多张图：sw_HHmmss_01 / _02 ... ───
    ; 用存在性判重而不是计数器 —— 计数器是进程内的，重启归零就会覆盖上一次的图
    static _NewName(dir, ext) {
        stamp := FormatTime(, "HHmmss")
        Loop 99 {
            cand := "sw_" . stamp . "_" . Format("{:02}", A_Index) . "." . ext
            if !FileExist(dir . "\" . cand)
                return cand
        }
        ; 99 张同秒（批量拖入）—— 落到 TickCount，仍然唯一
        return "sw_" . A_TickCount . "." . ext
    }

    ; ─── base64 解码 ───
    ; 返回 {buf, size}；失败返回 0（调用方用 IsObject 判）
    ; ⚠ AHK v2 没有内置 base64 —— 借 crypt32 的 CryptStringToBinaryW，
    ;   比纯 AHK 逐字节循环快两个数量级（5 MB 图实测 8ms 级）。
    static _Decode(b64) {
        s := RegExReplace(b64, "\s")
        s := RegExReplace(s, "^data:[^,]*,", "")
        if (s = "")
            return 0

        size := 0
        if !DllCall("crypt32\CryptStringToBinaryW", "Str", s, "UInt", 0
            , "UInt", 0x1, "Ptr", 0, "UInt*", &size, "Ptr", 0, "Ptr", 0)
            return 0
        if (size = 0)
            return 0

        buf := Buffer(size, 0)
        if !DllCall("crypt32\CryptStringToBinaryW", "Str", s, "UInt", 0
            , "UInt", 0x1, "Ptr", buf, "UInt*", &size, "Ptr", 0, "Ptr", 0)
            return 0
        return {buf: buf, size: size}
    }
}
