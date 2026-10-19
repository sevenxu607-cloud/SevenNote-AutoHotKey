#Requires AutoHotkey v2.0
; ======================================================================
;  BackdropService
;  Moved verbatim from SevenNote.ahk (Phase 2); behavior unchanged.
; ======================================================================

; ─── BackdropService：背景图能力（位图合成 + 层级铺设）───
; 纯能力：不读配置、不管开关、不发事件，只负责「把一张图铺到编辑区背后的控件上」。
;
; 技术路线（除 ※ 那条外，均经独立 spike 脚本实测确认，非推测）：
;   · RichEdit 无法真正透明 —— 给编辑区加 WS_EX_TRANSPARENT，让它绘制时跳过自身背景，
;     由 z-order 更低的同级兄弟控件（承载图片的 Static）先画出的图透上来；
;   · 子类化 WM_ERASEBKGND 自绘也无效 —— 图会被 RichEdit 在 WM_PAINT 内重填背景盖掉；
;   · WS_EX_TRANSPARENT 实测不影响鼠标命中与键盘输入，真实滚轮滚动无残影，
;     被其他窗口遮挡再露出也能正常恢复。
;
; ※ 父窗口 WS_EX_COMPOSITED 与编辑区透明的相容性：**有条件，别当绝对禁令**
;   · ebd95ac（背景图首版，Alt+B 时代、样式由 WinSetExStyle 设）的 spike 实测是
;     「父窗口加 WS_EX_COMPOSITED → 只剩图、文字全丢」，当时据此写下「绝不能加」；
;   · 但 v2.3.2（e81c03c）为消除滚动频闪，在组合根的 g.Opt 里加了 +E0x02000000 ——
;     这条禁令两天后就被违反，且没留下任何复测记录（该提交只提频闪）。
;   · 当前两者**同时存在**，日常使用未见文字丢失；但**没有一条正向判据证明过**：
;     那一轮的验收是「resize 前后截图逐像素一致」—— 文字若本来就丢，前后也一致，
;     照样「通过」。一致性不等于正确性。
;   ⚠ 动到任一侧（父窗口 COMPOSITED / 编辑区透明）都要复测两条，且用**存在性判据**：
;     ① 切带背景图的主题、编辑区打满字 → 截图里近白像素应达数万级（证明文字还在）；
;        不要拿「前后截图一致」当判据 —— 它只证明没变化，证明不了文字在。
;     ② 拖动窗口 40 次 → 不应出现上下滑动频闪（E0x02000000 正是为它加的）。
;
; ⚠ 两个 API 细节：
;   · 扩展样式必须在 Show() 之前设置；
;   · 样式开关走 BackdropFeature._SetEdTransparent 的 DllCall，不用 AHK 的 WinSetExStyle ——
;     后者在窗口**最小化**时会抛「(6) 句柄无效。」（原因见该方法的注释）。
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
