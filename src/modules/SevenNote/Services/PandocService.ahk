#Requires AutoHotkey v2.0
; ======================================================================
;  PandocService
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

; ─── PandocService：RTF → Markdown ───
; 【v1.9 关键修复】
;   · GetCmd / IsAvailable 加文件大小检查（> 1MB 才用）
;   · 避免 0KB 坏 pandoc 阻塞系统 PATH 里的好 pandoc
class PandocService {
    ; 探测过一次「可用」就永久记住。pandoc 是本程序自带的（或系统装的），
    ; 运行期间不会凭空消失 —— 而每次探测都要 RunWait 起一个 conhost + 一个 200MB 的
    ; pandoc 进程（实测几十到几百 ms，冷启动更久）。而探测点在保存链路上：
    ; Window.BeforeHide → Save → IsAvailable，也就是**每次 Alt+Z 隐藏都跑一次**，
    ; 外加 120s 自动保存。只有「探测不到」才每次都重试，好让用户中途装好 pandoc
    ; 之后不必重启程序。
    static _availCache := false

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
        if this._availCache
            return true
        ; 优先 AppData 打包版（必须大小 > 1MB）
        p := Config.PandocPath
        if this._IsValidPandoc(p) {
            try {
                code := RunWait(A_ComSpec . ' /c "' . p
                    . '" --version >nul 2>&1', , "Hide")
                if (code = 0)
                    return this._availCache := true
            } catch {
            }
        }
        ; 退化系统 PATH
        try {
            code := RunWait(A_ComSpec . " /c pandoc --version >nul 2>&1", , "Hide")
            if (code = 0)
                return this._availCache := true
        } catch {
        }
        return false
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
