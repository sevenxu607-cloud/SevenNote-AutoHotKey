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

; 主题 → JSON（前端 JSON.parse 后 applyTheme）。
; 主题名里有中文，直接拼进 JSON 是合法的，但引号 / 反斜杠必须转义。
NoteHostTheme() {
    t := ThemeService.Themes[ThemeService.GetCurrent()]
    return '{'
        . '"name":' . JsText.Escape(t.name) . ','
        . '"win":'   . JsText.Escape(t.win)   . ','
        . '"edBg":'  . JsText.Escape(t.edBg)  . ','
        . '"text":'  . JsText.Escape(t.text)  . ','
        . '"dim":'   . JsText.Escape(t.dim)
        . '}'
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
