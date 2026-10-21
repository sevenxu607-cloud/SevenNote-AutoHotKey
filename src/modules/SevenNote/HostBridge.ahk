#Requires AutoHotkey v2.0
; ======================================================================
;  HostBridge.ahk
;  笔记模块暴露给前端（WebView2）的宿主对象。
;
;  前端用法：chrome.webview.hostObjects.ahk.<方法>(…)  见 web/src/ahk.ts
;  AHK 侧注册：WebHostService.Bind("ahk", NoteHostHandlers())
;
;  ⚠ 这里是**顶层函数**不是类静态方法：AddHostObjectToScript 走 IDispatch，
;    类静态方法不在实例上、调用时抛「对象不支持此属性或方法」。S2b 用顶层
;    函数验证通过，照这个来。
;  ⚠ 方法名必须与 ahk.ts 里的字符串逐个对齐 —— 拼错不报错，只是前端抛
;    「AHK 未提供方法：xxx」，而 storeImage 会把这条 catch 掉、静默退回 base64。
;  ⚠ 返回值一律**字符串**：对象 / 数字要额外实现接口，字符串最省事，前端自己解析。
; ======================================================================

NoteHostPing() => "pong"
NoteHostVersion() => A_AhkVersion

; 语义色板 → JSON。前端 JSON.parse 后 applyTheme 一次设全 --sw-*。
; v2.9 起随主题上收一起扩到 9 个语义色：从前只给 4 个（name/win/edBg/text/dim），
; --sw-accent / --sw-border 一直用 CSS 里的浅色默认值 —— 深色主题下那两个颜色是
; 米黄系的，压在深底上既不像强调色也不像分隔线。
;
; ⚠ 字段顺序 / 名字与 web/src/ahk.ts 的 Theme 接口逐个对齐，改一边必须改另一边。
; ⚠ 有中文（主题名），引号 / 反斜杠必须过 JsText.Escape —— 手拼 JSON 只在这一处。
NoteHostThemeJson() {
    p := ThemeService.Palette()
    return '{'
        . '"name":'    . JsText.Escape(p.name)   . ','
        . '"win":'     . JsText.Escape(p.win)    . ','
        . '"edBg":'    . JsText.Escape(p.edBg)   . ','
        . '"text":'    . JsText.Escape(p.text)   . ','
        . '"dim":'     . JsText.Escape(p.dim)    . ','
        . '"accent":'  . JsText.Escape(p.accent) . ','
        . '"border":'  . JsText.Escape(p.border) . ','
        . '"codeBg":'  . JsText.Escape(p.codeBg) . ','
        . '"dark":'    . (p.dark ? "true" : "false") . ','
        . '"bg":'      . JsText.Escape(p.bg)     . ','
        . '"bgAlpha":' . p.bgAlpha
        . '}'
}

NoteHostTheme() {
    return NoteHostThemeJson()
}

; 粘贴的图片落盘：base64 → <vault>\_assets\<日期>\sw_*.png，返回 ./_assets/… 相对路径。
; 失败返回空串 —— 前端据此回退成内联 data URL，不会让整次粘贴失败。
NoteHostSaveImage(b64, ext := "png") {
    try {
        rel := NoteImageService.SaveBase64(b64, ext, State.GetDate(), Config.GetVault())
        return rel
    } catch as e {
        LogError("图片落盘失败：" . e.Message)
        return ""
    }
}

; 交给 WebHostService.Bind 的方法表
NoteHostHandlers() {
    return {
        ping:      NoteHostPing,
        version:   NoteHostVersion,
        getTheme:  NoteHostTheme,
        saveImage: NoteHostSaveImage
    }
}
