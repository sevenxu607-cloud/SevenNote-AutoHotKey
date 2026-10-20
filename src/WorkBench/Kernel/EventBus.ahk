#Requires AutoHotkey v2.0
; WorkBench/Kernel/EventBus.ahk
; Moved from SevenNote.ahk (Phase 1). Implementation unchanged.

class EventBus {
    static handlers := Map()

    ; 错误上报出口。Kernel 不认识 LogError / Config（.clinerules/02 严禁反向依赖），
    ; 所以由组合根在启动早期 SetErrorSink(LogError) **注入**；没注入时退回 OutputDebug。
    ; ⚠ 这是「Kernel 只加不改」的加法例外：Emit 签名与调用方式都没变，
    ;   只在订阅者出错时多写一条日志（v2.4.5）。
    static _sink := ""

    static SetErrorSink(fn) => this._sink := fn

    static On(event, fn) {
        if !this.handlers.Has(event)
            this.handlers[event] := []
        this.handlers[event].Push(fn)
    }

    ; 逐个订阅者执行，**异常互相隔离**：一个订阅者抛错，后面的照常跑。
    ; 这一点不能省 —— Theme.Changed 有 3 个订阅者（StatusBar / BackdropFeature /
    ; SearchFeature），若让异常直接透出去，前一个抛了后两个就再也不执行，
    ; 表现为「界面颜色没跟上」而错误本身又没人看见。
    ; 异常先攒着、循环结束后只上报一条：同一事件不重复写盘。
    ; 序号就是注册顺序（数组下标），日志里按它数第几个订阅者即可定位。
    static Emit(event, data := "") {
        if !this.handlers.Has(event)
            return
        errors := ""
        for idx, fn in this.handlers[event] {
            try {
                fn(data)
            } catch as e {
                ; v2.4.5 之前这里是裸 `try fn(data)`：异常被静默吞掉，
                ; 到不了 OnError、也不进 _error.log —— 查「按了没反应」时全无线索。
                errors .= "    订阅者第 " . idx . " 个：" . e.Message
                    . "`n      文件  " . e.File . "   行  " . e.Line . "`n"
            }
        }
        if (errors != "")
            this._Report("事件订阅者异常：" . event . "`n" . errors)
    }

    ; 上报出口自己绝不能抛：它跑在 catch 里，再抛就回到 OnError，
    ; 而同一条错误会被记两次、极端情况下还会递归。全程 try。
    ; ⚠ 必须先把 sink 取到局部变量再调用 —— AHK v2 里 `obj.prop(args)` 走的是
    ;   **方法查找**，属性里存的 Func 不会被调用，实测报
    ;   `Too many parameters passed to function`；那个异常又会被下面的 try 吞掉，
    ;   等于「修了等于没修」（v2.4.5 第一版就是这么翻车的，探针才抓到）。
    static _Report(msg) {
        sink := this._sink
        if IsObject(sink) {
            try {
                sink(msg)
                return
            }
        }
        try OutputDebug("EventBus —— " . msg)
    }
}
