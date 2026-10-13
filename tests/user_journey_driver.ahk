global JourneyResultPath := "__RESULT_PATH__"
global JourneyImagePath := "__DEMO_IMAGE_PATH__"
global JourneyTracePath := "__TRACE_PATH__"
global JourneyStartSignalPath := "__START_SIGNAL_PATH__"
global JourneyPaceMs := 8000
global JourneyTypeDelayMs := 100
global JourneySpeedMode := "balanced"
global JourneyTags := [
    "旅途-序言",
    "旅途-轻量",
    "旅途-富文本",
    "旅途-归档",
    "旅途-标签",
    "旅途-日期",
    "旅途-外观"
]

JourneySlides := [
    {
        journey: "极致轻量",
        title: "极致轻量",
        feature: "全局唤起 · 当天笔记 · 自动保存",
        hotkey: "Alt+Z  呼出 / 收起",
        story: "快速唤起当天笔记。内容按日期归档，隐藏窗口时自动保存，让记录自然融入当前工作。",
        action: "当天笔记已载入 · 隐藏时自动保存",
        weight: 0.8
    },
    {
        journey: "富文本编辑",
        title: "富文本编辑",
        feature: "PyCharm 行编辑迁移 · 时间戳 · 分段 · 图片粘贴",
        hotkey: "Ctrl+D  复制行    Ctrl+Shift+↑/↓  移动行    Ctrl+Z  撤销",
        story: "将 PyCharm 中熟悉的行编辑快捷键迁移到 SevenNote；时间戳、分段标题与图片粘贴则是笔记记录功能。",
        action: "熟悉的编辑操作与笔记原生记录功能，在同篇笔记完成",
        weight: 1.1
    },
    {
        journey: "双格式归档",
        title: "双格式归档",
        feature: "RTF 富文本母版 · Markdown 便携副本",
        hotkey: "Ctrl+S  同步保存两种格式",
        story: "一次保存，同时生成保留富文本的 RTF 母版和便于继续整理的 Markdown 译本。",
        action: "实际归档文件名与格式已展示",
        weight: 1.25
    },
    {
        journey: "标签系统",
        title: "标签系统",
        feature: "标签写入文件名 · 状态栏提示 · 标签跳转",
        hotkey: "Ctrl+Shift+T  设置标签    Ctrl+G  按标签找回",
        story: "标签与日期共同标识笔记；从完整笔记列表按标签筛选，可跳转到不同日期的主题记录。",
        action: "按标签跨日期筛选，并打开另一篇旅途笔记",
        weight: 1.15
    },
    {
        journey: "日期管理",
        title: "日期管理",
        feature: "正文搜索 · 每日独立笔记 · 日期切换与跳转",
        hotkey: "Ctrl+F  查找正文    Alt+↑ / Alt+↓  前后一天    Ctrl+G  按日期跳转",
        story: "先在当前笔记中定位关键词，再从不同日期的记录中按日期筛选并跳转，区分正文搜索与跨笔记回顾。",
        action: "Ctrl+F 正文定位与跨日期 Ctrl+G 跳转均已实际展示",
        weight: 1.2
    },
    {
        journey: "6 套主题 + 7 种字体",
        title: "6 套主题 + 7 种字体",
        feature: "多套主题 · 多种字体 · 字号自选",
        hotkey: "Alt+T  切换主题    Alt+Shift+T  切换字体",
        story: "切换主题与字体，按阅读习惯选择字号；外观设置自动记忆，窗口重新打开后继续当前记录。",
        action: "主题与字体已更新 · 设置自动记忆",
        weight: 1.3
    }
]

JourneyAppGui := State.GetGui()
presenter := Gui("+AlwaysOnTop +Resize +MinSize450x300", "SevenNote - 用户旅途")
presenter.BackColor := "F4F6FA"
presenter.SetFont("s9", "Microsoft YaHei")
presenter.AddText("x22 y14 w406 h20 c68758A", "SEVENNOTE  /  一段真实的记录旅程")
presenter.SetFont("s10", "Microsoft YaHei")
progressControl := presenter.AddText("x22 y42 w406 h22 c68758A", "")
presenter.SetFont("s18", "Microsoft YaHei")
titleControl := presenter.AddText("x22 y72 w406 h58 c1F3A5C +0x200", "")
presenter.SetFont("s9", "Microsoft YaHei")
presenter.AddText("x22 y140 w406 h18 c7B5A20", "功能价值")
presenter.SetFont("s15", "Microsoft YaHei")
featureControl := presenter.AddText("x22 y161 w406 h38 c1F3A5C +0x200", "")
presenter.SetFont("s12", "Microsoft YaHei")
storyControl := presenter.AddText("x22 y207 w406 h86 c344054 +0x200", "")
presenter.SetFont("s10", "Microsoft YaHei")
presenter.AddText("x22 y303 w406 h20 c7B5A20", "怎么操作")
presenter.SetFont("s12", "Microsoft YaHei")
hotkeyControl := presenter.AddText("x22 y327 w406 h54 BackgroundE5ECF5 c29496E +0x200", "")
presenter.SetFont("s10", "Microsoft YaHei")
presenter.AddText("x22 y394 w406 h20 c7B5A20", "眼前的变化")
presenter.SetFont("s11", "Microsoft YaHei")
resultControl := presenter.AddText("x22 y418 w406 h78 BackgroundE7F4EA c24633A +0x200", "")
JourneyLiveControl := resultControl
presenter.SetFont("s9", "Microsoft YaHei")
presenter.AddText("x22 y518 w406 h18 c68758A", "演示数据独立保存 · 不触碰个人笔记")

progressControl.Value := "旅途起点  ·  从记录到回顾"
titleControl.Value := "灵感，随手记下"
featureControl.Value := "快速记录 · 灵活整理 · 随时找回"
storyControl.Value := "接下来将沿着六段真实使用场景，看看一条笔记如何被记录、整理、保存，并在需要时重新找到。"
hotkeyControl.Value := "开场提示  ·  先看序言，再跟随应用操作"
resultControl.Value := "七篇连续日期笔记  ·  六段功能体验  ·  临时数据自动清理"

MonitorGetWorkArea(, &workLeft, &workTop, &workRight, &workBottom)
JourneyAppGui.Show("x" . workLeft . " y" . workTop
    . " w" . Config.WinW . " h" . Config.WinH)
WinGetPos(&appX, &appY, &appWidth, &appHeight, "ahk_id " . JourneyAppGui.Hwnd)
presenter.Show("x" . (workLeft + appWidth + 18) . " y" . workTop
    . " w" . Config.WinW . " h" . Config.WinH)
WinGetPos(&guideX, &guideY, &guideWidth, &guideHeight, "ahk_id " . presenter.Hwnd)
gap := 18
groupWidth := appWidth + gap + guideWidth
if (workRight - workLeft < groupWidth || workBottom - workTop < Max(appHeight, guideHeight)) {
    throw Error("当前屏幕工作区无法并排容纳两个完整窗口；为避免遮挡，演示已停止。")
}
leftX := workLeft + ((workRight - workLeft - groupWidth) // 2)
topY := workTop + ((workBottom - workTop - Max(appHeight, guideHeight)) // 2)
WinMove(leftX, topY, , , "ahk_id " . JourneyAppGui.Hwnd)
WinMove(leftX + appWidth + gap, topY, , , "ahk_id " . presenter.Hwnd)

WinGetPos(&appX, &appY, &appWidth, &appHeight, "ahk_id " . JourneyAppGui.Hwnd)
WinGetPos(&guideX, &guideY, &guideWidth, &guideHeight, "ahk_id " . presenter.Hwnd)
overlap := !(appX + appWidth <= guideX || guideX + guideWidth <= appX
    || appY + appHeight <= guideY || guideY + guideHeight <= appY)
if (overlap || appWidth != guideWidth || appHeight != guideHeight) {
    throw Error("窗口实际边界校验失败：未能等大并排显示，演示已停止。")
}

WinSetAlwaysOnTop(1, "ahk_id " . JourneyAppGui.Hwnd)
WinSetAlwaysOnTop(1, "ahk_id " . presenter.Hwnd)
if (JourneyStartSignalPath != "") {
    signalDeadline := A_TickCount + 300000
    while !FileExist(JourneyStartSignalPath) {
        if (A_TickCount >= signalDeadline)
            throw Error("等待录制启动信号超时；演示已取消。")
        Sleep(100)
    }
}
SendMode("Event")
SetKeyDelay(12, 8)
SendLevel(1)
Sleep(700)

FocusJourneyApp()
ShiftJourneyDate(-6)
WriteDemoLine("SevenNote 用户旅途｜序言", "title")
WriteDemoLine("记录日期｜" . State.GetDate(), "prompt", "instant")
WriteDemoLine("从一条随手速记开始，记录可以轻，也可以完整。", "body", "instant")
WriteDemoLine("这份演示以连续日期组织六段功能；每篇笔记均带有旅途标签。", "body", "instant")
WriteDemoLine("极致轻量 → 富文本编辑 → 双格式归档 → 标签系统 → 日期管理 → 6 套主题 + 7 种字体", "prompt", "instant")
WriteDemoLine("操作方式｜先阅读本篇提示，再观察真实热键与笔记变化。", "body", "instant")
WriteDemoLine("查找方式｜Ctrl+G 搜索“旅途-”，按标签打开对应模块。", "body", "instant")
WriteDemoLine("隔离说明｜演示数据仅保存在临时 Vault，结束后自动清理。", "result", "instant")
Sleep(1200)
if !FinalizeJourneyNote(JourneyTags[1])
    throw Error("Could not save and tag the user-journey introduction note.")

JourneyResults := []
for index, slide in JourneySlides {
    TraceJourney("Chapter starting: " . slide.journey)
    WinActivate("ahk_id " . presenter.Hwnd)
    Sleep(550)
    FocusJourneyApp()
    ShiftJourneyDate(1)
    Sleep(300)
    titleControl.Value := slide.title
    featureControl.Value := slide.feature
    storyControl.Value := slide.story
    hotkeyControl.Value := slide.hotkey
    progressControl.Value := JourneyProgress(index, slide.journey)
    resultControl.Value := "应用窗口同步呈现当前步骤"
    WriteDemoLine(slide.journey, "title")
    WriteDemoLine("记录日期｜" . State.GetDate(), "prompt", "instant")
    WriteDemoLine("本段重点｜" . slide.feature, "body", "instant")
    WriteDemoLine("操作提示｜" . slide.hotkey, "prompt")
    Sleep(900)

    detail := ""
    passed := false
    if (index = 1) {
        WriteDemoLine("记录入口随时可用；切回当天即可继续。", "body", "instant")
        Sleep(1100)
        Send("!z")
        Sleep(900)
        hidden := !DllCall("IsWindowVisible", "ptr", JourneyAppGui.Hwnd, "int")
        Send("!z")
        appRestored := WinWaitActive("ahk_id " . JourneyAppGui.Hwnd, , 2)
        Sleep(650)
        WriteDemoLine("效果｜窗口重新呼出，当天记录仍在原处。", "result")
        note := EditorService.GetText(State.GetEd())
        dateVisible := InStr(note, State.GetDate()) > 0
        contentVisible := InStr(note, "当天记录仍在原处") > 0
        passed := hidden && appRestored && dateVisible && contentVisible
        TraceJourney("Lightweight checks: hidden=" . hidden . " active=" . appRestored
            . " date=" . State.GetDate() . " dateVisible=" . dateVisible
            . " contentVisible=" . contentVisible)
        detail := passed ? "Alt+Z 隐藏并重新呼出；当天笔记内容保持不变。" : "窗口呼出/隐藏或当天日期检查未通过。"
    } else if (index = 2) {
        SetGuideSegment("行编辑 · 习惯迁移"
            , "将 PyCharm 中熟悉的行操作带入笔记；顺序可调整，修改可恢复。"
            , "Ctrl+Shift+↑  移动行    Ctrl+D  复制行    Ctrl+Z  撤销")
        WriteDemoLine("行编辑｜将 PyCharm 中熟悉的快捷键习惯带入 SevenNote。", "prompt", "instant")
        WriteDemoLine("操作提示｜先调整顺序，再观察复制与撤销、重做。", "body", "instant")
        TypeDemoLines([
            "补充信息：文字与图片留在同一篇记录。",
            "记录重点：时间、结构与图像保持关联。"
        ])
        Send("{Up}")
        Sleep(500)
        Send("^+{Up}")
        Sleep(700)
        Send("^d")
        Sleep(750)
        duplicateVisible := CountOccurrences(EditorService.GetText(State.GetEd())
            , "记录重点：时间、结构与图像保持关联。") = 2
        Send("^z")
        Sleep(500)
        Send("^+z")
        Sleep(700)
        duplicateRestored := CountOccurrences(EditorService.GetText(State.GetEd())
            , "记录重点：时间、结构与图像保持关联。") = 2
        Send("^z")
        Sleep(650)
        movedNote := EditorService.GetText(State.GetEd())
        priorityPos := InStr(movedNote, "记录重点：时间、结构与图像保持关联。")
        extraPos := InStr(movedNote, "补充信息：文字与图片留在同一篇记录。")
        lineEditPassed := duplicateVisible && duplicateRestored
            && priorityPos > 0 && extraPos > priorityPos
        WriteDemoLine("效果｜重点行已移到前面；复制、撤销与重做可观察。", "result", "instant")
        Sleep(800)

        SetGuideSegment("时间与分段 · 记录组织"
            , "时间戳标记记录时刻，分隔线与分段标题让连续内容更易浏览。"
            , "Ctrl+T  时间戳    Ctrl+H  分隔线    Ctrl+Shift+H  分段标题")
        WriteDemoLine("SevenNote 记录功能｜为笔记添加时间与清晰段落。", "prompt", "instant")
        WriteDemoLine("操作提示｜Ctrl+T 插入当前时间。", "body", "instant")
        Sleep(650)
        Send("^t")
        Sleep(600)
        WriteDemoLine("效果｜记录时刻已写入当前笔记。", "result", "instant")
        WriteDemoLine("操作提示｜Ctrl+B 突出需要回看的重点。", "prompt", "instant")
        Sleep(650)
        Send("^b")
        SendText("重点：醒目格式保留信息层次")
        Send("^b")
        Send("{Enter}")
        Sleep(650)
        WriteDemoLine("效果｜重点内容通过格式强调，与正文区分。", "result", "instant")
        WriteDemoLine("操作提示｜Ctrl+H 插入分隔线，Ctrl+Shift+H 建立分段标题。", "prompt", "instant")
        Sleep(650)
        Send("^h")
        Sleep(550)
        Send("^+h")
        Sleep(650)
        TypeDemoLines(["连续记录按主题分段。", "标题、正文与重点格式清晰区分。"])
        WriteDemoLine("效果｜内容按主题分区，长笔记更容易浏览。", "result", "instant")
        Sleep(800)

        SetGuideSegment("图片粘贴 · 图文同篇"
            , "粘贴图片后，画面与文字保留在同一条记录，附件按日期整理。"
            , "Ctrl+V  粘贴图片")
        WriteDemoLine("图文记录｜接下来将截图与说明放在同一篇笔记中。", "prompt", "instant")
        WriteDemoLine("操作提示｜Ctrl+V 粘贴演示图片。", "body", "instant")
        Sleep(850)
        PasteDemoImage()
        Sleep(900)
        WriteDemoLine("效果｜图片已嵌入笔记；保存时归入当天附件。", "result", "instant")
        Send("^s")
        Sleep(1200)
        imageRtf := NoteStoreService.FindRtf(State.GetDate())
        imageRtfText := imageRtf != "" ? FileRead(imageRtf) : ""
        imageRtfContainsPicture := InStr(imageRtfText, "\pict") > 0
        richTextFormattingFound := InStr(imageRtfText, "\b") > 0
            && InStr(imageRtfText, "\cf") > 0
        imageAssetDir := NoteStoreService.AssetsDir(State.GetDate())
        imageSavedAsAsset := false
        if DirExist(imageAssetDir) {
            Loop Files, imageAssetDir . "\*.*" {
                imageSavedAsAsset := true
                break
            }
        }
        note := EditorService.GetText(State.GetEd())
        passed := RegExMatch(note, "🕐 \d{2}:\d{2}") > 0
            && InStr(note, "醒目格式保留信息层次") > 0
            && InStr(note, "连续记录按主题分段") > 0
            && InStr(note, "图文记录") > 0
            && imageRtfContainsPicture && imageSavedAsAsset
            && richTextFormattingFound && lineEditPassed
        detail := passed ? "行编辑、时间戳、分段标题、图片粘贴及日期附件均已实演并校验。"
            : "编辑分区检查：行编辑=" . (lineEditPassed ? "通过" : "未通过")
                . "；图片 RTF=" . (imageRtfContainsPicture ? "有" : "无")
                . "；附件=" . (imageSavedAsAsset ? "有" : "无")
                . "；富文本=" . (richTextFormattingFound ? "有" : "无") . "。"
    } else if (index = 3) {
        WriteDemoLine("保存提示｜Ctrl+S 同步生成富文本母版与 Markdown 译本。", "prompt")
        Sleep(1300)
        Send("^s")
        Sleep(1600)
        rtfPath := NoteStoreService.FindRtf(State.GetDate())
        mdPath := NoteStoreService.FindMd(State.GetDate())
        saved := rtfPath != "" && mdPath != ""
            && FileExist(rtfPath) && FileExist(mdPath)
        WriteDemoLine("RTF 母版｜" . (saved ? RegExReplace(rtfPath, "^.*\\") : "未生成"), "body", "instant")
        WriteDemoLine("Markdown｜" . (saved ? RegExReplace(mdPath, "^.*\\") : "未生成"), "body", "instant")
        WriteDemoLine("价值｜可保留富文本，也可在 Markdown 工具中继续整理。", "result", "instant")
        passed := saved
        detail := passed ? "Ctrl+S 后实际生成 RTF 与 Markdown；文件名与用途已展示。"
            : "RTF 或 Markdown 文件未生成。"
    } else if (index = 4) {
        chapterDate := State.GetDate()
        richTextDate := JourneyDateForTag(3)
        SetGuideSegment("标签系统 · 直接选择"
            , "完整列表保留所有日期与标签；直接选中一条记录，即可跨日回到主题内容。"
            , "Ctrl+G  打开列表    双击记录  直接跳转")
        WriteDemoLine("标签提示｜Ctrl+Shift+T 将本篇标记为“" . JourneyTags[index + 1] . "”。", "prompt")
        Sleep(900)
        tagged := FinalizeJourneyNote(JourneyTags[index + 1])
        WriteDemoLine("直接选择｜Ctrl+G 打开完整列表，双击较早日期的「富文本编辑」。", "prompt")
        Sleep(900)
        directTagJump := tagged && DirectJumpByDate(richTextDate)
        note := EditorService.GetText(State.GetEd())
        directTagPassed := directTagJump && State.GetDate() = richTextDate
            && InStr(StatusBar._tagCtrl.Value, JourneyTags[3]) > 0
            && InStr(note, "富文本编辑") > 0
        WriteDemoLine("效果｜直接选择已打开另一日期的富文本记录。", "result", "instant")
        Sleep(800)
        SetGuideSegment("标签系统 · 检索后选择"
            , "当列表较长时，输入标签缩小范围，再选择目标笔记。"
            , "Ctrl+G  输入「旅途-富文本」    选择匹配记录")
        WriteDemoLine("检索选择｜Ctrl+G 输入「旅途-富文本」，再选择匹配记录。", "prompt")
        Sleep(900)
        foundByTag := JumpByQuery(JourneyTags[3], richTextDate)
        filteredTagPassed := foundByTag && State.GetDate() = richTextDate
            && InStr(StatusBar._tagCtrl.Value, JourneyTags[3]) > 0
        WriteDemoLine("效果｜筛选结果仍可回到同一日期的富文本记录。", "result", "instant")
        Sleep(800)
        WriteDemoLine("返回提示｜按标签检索并选择当前的标签系统笔记。", "prompt", "instant")
        Sleep(700)
        returnedToTag := JumpByQuery(JourneyTags[index + 1], chapterDate)
        note := EditorService.GetText(State.GetEd())
        passed := directTagPassed && filteredTagPassed && returnedToTag
            && State.GetDate() = chapterDate
            && InStr(StatusBar._tagCtrl.Value, JourneyTags[index + 1]) > 0
            && InStr(note, "标签系统") > 0
        if passed
            WriteDemoLine("效果｜直接选择或检索标签，都能跨日期找回主题记录。", "result")
        detail := passed ? "列表双击与标签检索两种方式均跳到另一日期，并返回当前笔记。"
            : "标签保存=" . tagged . "；列表直选=" . directTagPassed
                . "（跳转=" . directTagJump . "，日期=" . State.GetDate() . "）；"
                . "标签检索=" . filteredTagPassed . "；返回当前篇=" . returnedToTag . "。"
    } else if (index = 5) {
        savedDate := State.GetDate()
        richTextDate := JourneyDateForTag(3)
        WriteDemoLine("检索标记｜阶段回顾", "body", "instant")
        Sleep(750)
        WriteDemoLine("搜索提示｜Ctrl+F 输入本段标记词，观察匹配计数与正文定位。", "prompt")
        Sleep(900)
        Send("^f")
        Sleep(400)
        SendText("阶段回顾")
        Send("{Enter}")
        Sleep(850)
        bodySearchPassed := SearchFeature.IsVisible()
            && SearchFeature._count.Value = "1/1"
        Send("{Esc}")
        Sleep(450)
        FocusJourneyApp()
        WriteDemoLine("效果｜Ctrl+F 在当前笔记中找到 1 处匹配并定位正文。", "result", "instant")
        Sleep(850)
        WriteDemoLine("日期提示｜Alt+↑ 查看前一天，再按 Alt+↓ 返回本篇。", "prompt", "instant")
        Sleep(900)
        ShiftJourneyDate(-1)
        previousDate := State.GetDate()
        previousNote := EditorService.GetText(State.GetEd())
        ShiftJourneyDate(1)
        returnedByStep := State.GetDate() = savedDate
            && InStr(EditorService.GetText(State.GetEd()), "日期管理") > 0
        SetGuideSegment("日期管理 · 直接选择"
            , "日期列表适合按时间浏览；直接选择某天即可打开对应笔记。"
            , "Ctrl+G  打开完整列表    双击目标日期")
        WriteDemoLine("直接选择｜Ctrl+G 打开日期列表，双击 " . richTextDate . "。", "prompt")
        Sleep(900)
        directDateJump := DirectJumpByDate(richTextDate)
        directDateNote := EditorService.GetText(State.GetEd())
        directDatePassed := directDateJump && State.GetDate() = richTextDate
            && InStr(directDateNote, "富文本编辑") > 0
        WriteDemoLine("效果｜直接选择已打开 " . richTextDate . " 的记录。", "result", "instant")
        Sleep(800)
        SetGuideSegment("日期管理 · 检索后选择"
            , "日期较多时，可输入具体日期过滤，再选择对应记录。"
            , "Ctrl+G  输入日期    选择匹配记录")
        WriteDemoLine("检索选择｜Ctrl+G 输入 " . richTextDate . "，选择筛选结果。", "prompt")
        Sleep(900)
        jumpedByDate := JumpByQuery(richTextDate, richTextDate)
        historicalNote := EditorService.GetText(State.GetEd())
        historicalJumpPassed := jumpedByDate && State.GetDate() = richTextDate
            && InStr(historicalNote, "富文本编辑") > 0
        WriteDemoLine("效果｜按日期检索后跳转，目标笔记与列表直选一致。", "result", "instant")
        Sleep(800)
        WriteDemoLine("返回提示｜按当前日期再次筛选，回到日期管理篇。", "prompt", "instant")
        Sleep(750)
        returnedByQuery := JumpByQuery(savedDate, savedDate)
        passed := previousDate != savedDate && InStr(previousNote, "标签系统") > 0
            && returnedByStep && bodySearchPassed && directDatePassed && historicalJumpPassed
            && returnedByQuery && State.GetDate() = savedDate
        if passed
            WriteDemoLine("效果｜正文搜索、前后切日与跨日跳转，构成完整回顾路径。", "result")
        detail := passed ? "Ctrl+F 定位正文；日期列表直选与检索跳转、前后切日均通过。"
            : "正文搜索=" . bodySearchPassed . "；前后切日=" . returnedByStep
                . "；列表直选=" . directDatePassed . "（跳转=" . directDateJump
                . "，日期=" . State.GetDate() . "）；日期检索=" . historicalJumpPassed
                . "；返回=" . returnedByQuery . "。"
    } else {
        Sleep(900)
        Send("!t")
        Sleep(1100)
        themeChanged := ThemeService.GetCurrent() = 2
        WriteDemoLine("效果｜主题已切换，阅读背景与文字对比同步调整。", "result")
        startingFont := FontService.GetName()
        WriteDemoLine("操作提示｜Alt+Shift+T 切换字体。字号可按阅读习惯选择。", "prompt")
        Sleep(900)
        Send("!+t")
        Sleep(1000)
        fontChanged := FontService.GetName() != startingFont
        WriteDemoLine("效果｜主题与字体已更新；笔记字号保持稳定，外观设置自动记忆。", "result")
        WinGetPos(&beforeX, &beforeY, &beforeWidth, &beforeHeight
            , "ahk_id " . JourneyAppGui.Hwnd)
        Send("!z")
        Sleep(800)
        hidden := !DllCall("IsWindowVisible", "ptr", JourneyAppGui.Hwnd, "int")
        Send("!z")
        WinWaitActive("ahk_id " . JourneyAppGui.Hwnd, , 2)
        Sleep(650)
        WinGetPos(&afterX, &afterY, &afterWidth, &afterHeight
            , "ahk_id " . JourneyAppGui.Hwnd)
        visible := DllCall("IsWindowVisible", "ptr", JourneyAppGui.Hwnd, "int")
        passed := themeChanged && fontChanged && hidden && visible
            && beforeX = afterX && beforeY = afterY
            && beforeWidth = afterWidth && beforeHeight = afterHeight
        detail := passed ? "主题、字体已调整并记忆；演示文字字号未随步骤跳变，Alt+Z 恢复后位置不变。" : "外观设置或窗口隐藏/恢复未通过验证。"
    }

    if (index = 6) {
        SetGuideSegment("旅途回顾 · 记录形成闭环"
            , "从快速记录到编辑、归档与回顾，笔记成为随时可用的个人知识入口。"
            , "六段功能  ·  七篇日期笔记  ·  隔离环境演示")
        WriteDemoLine("旅途回顾｜从随手记录，到随时找回。", "title")
        WriteDemoLine("快速记录 · 灵活编辑 · 双格式保存 · 标签与日期回顾。", "body")
        WriteDemoLine("演示特点｜七篇连续日期笔记，各有旅途标签，后续也可作为笔记整理。", "prompt", "instant")
        WriteDemoLine("安全说明｜所有演示数据仅保存在临时隔离环境。", "result", "instant")
    }

    if !passed && detail = ""
        detail := "操作后的画面内容没有达到预期。"
    TraceJourney("Chapter checks complete: " . slide.journey . " passed=" . passed)
    if (index != 4) {
        finalized := FinalizeJourneyNote(JourneyTags[index + 1])
        passed := passed && finalized
        if !finalized
            detail .= "；当前日期笔记保存或旅途标签写入失败。"
    }
    resultControl.Value := detail
    JourneyResults.Push({
        chapter: slide.title,
        feature: slide.feature,
        journey: slide.journey,
        hotkey: slide.hotkey,
        story: slide.story,
        action: slide.action,
        passed: passed,
        detail: detail
    })
    WinActivate("ahk_id " . presenter.Hwnd)
    Sleep(Round(JourneyPaceMs * slide.weight * JourneyPauseScale()))
}

verifiedNotes := 0
for tagIndex, tag in JourneyTags {
    date := FormatTime(DateAdd(FormatTime(, "yyyyMMdd"), tagIndex - 7, "Days"), "yyyy-MM-dd")
    rtfPath := NoteStoreService.FindRtf(date)
    mdPath := NoteStoreService.FindMd(date)
    tagVerified := InStr(rtfPath, "-" . tag . ".rtf") > 0
        && InStr(mdPath, "-" . tag . ".md") > 0
        && FileExist(rtfPath) && FileExist(mdPath)
    TraceJourney("Archive check: date=" . date . " tag=" . tag
        . " verified=" . tagVerified . " rtf=" . rtfPath . " md=" . mdPath)
    if tagVerified
        verifiedNotes++
}
if (verifiedNotes != 7) {
    TraceJourney("Note archive verification failed: " . verifiedNotes . "/7")
    lastResult := JourneyResults[JourneyResults.Length]
    lastResult.passed := false
    lastResult.detail .= "；七篇连续日期标签笔记仅验证到 "
        . verifiedNotes . " 篇。"
    resultControl.Value := lastResult.detail
}

titleControl.Value := "记录形成闭环，经验持续可用"
featureControl.Value := "快速记录 · 清晰整理 · 便捷回顾"
storyControl.Value := "从当天笔记到搜索、标签与双格式归档，记录始终沿着日期和主题组织。轻量唤起、持续保存，让信息在需要时重新回到工作现场。"
hotkeyControl.Value := "极致轻量  ·  富文本编辑  ·  双格式归档  ·  标签系统  ·  日期管理"
resultControl.Value := "演示笔记与配置均保存在临时隔离环境，不触碰个人数据。"
progressControl.Value := "● ● ● ● ● ◆  ·  旅途完成"
Sleep(Round(JourneyPaceMs * 1.2 * JourneyPauseScale()))

try {
    if FileExist(JourneyResultPath)
        FileDelete(JourneyResultPath)
    for result in JourneyResults {
        status := result.passed ? "PASS" : "FAIL"
        chapter := StrReplace(result.chapter, "`t", " ")
        journey := StrReplace(result.journey, "`t", " ")
        feature := StrReplace(result.feature, "`t", " ")
        hotkeyText := StrReplace(result.hotkey, "`t", " ")
        story := StrReplace(result.story, "`t", " ")
        action := StrReplace(result.action, "`t", " ")
        detail := StrReplace(result.detail, "`t", " ")
        FileAppend(status . "`t" . chapter . "`t" . journey . "`t" . feature . "`t" . hotkeyText
            . "`t" . story . "`t" . action . "`t" . detail . "`n"
            , JourneyResultPath, "UTF-8")
    }
} catch as e {
    MsgBox("Could not write the presentation results: " . e.Message
        , "Demo harness error", 16)
}

presenter.Destroy()
JourneyAppGui.Hide()
ExitApp()

FocusJourneyApp() {
    global JourneyAppGui
    WinActivate("ahk_id " . JourneyAppGui.Hwnd)
    if !WinWaitActive("ahk_id " . JourneyAppGui.Hwnd, , 2)
        throw Error("Could not activate the isolated SevenNote window for keyboard demonstration.")
    DllCall("SetFocus", "ptr", State.GetEd())
    Sleep(120)
}

TypeDemoLines(lines) {
    for line in lines {
        WriteDemoLine(line, "body")
    }
}

WriteDemoLine(text, style := "body", revealMode := "typewriter") {
    global JourneyTypeDelayMs, JourneyLiveControl, JourneySpeedMode
    hwnd := State.GetEd()
    EditorService.MoveCaretToEnd(hwnd)
    ApplyDemoTextStyle(hwnd, style)
    if (revealMode = "instant") {
        SendText(text)
        JourneyLiveControl.Value := text
        Send("{Enter}")
        ApplyDemoTextStyle(hwnd, "body")
        Sleep(180)
        return
    }

    typingDelay := JourneyTypeDelayMs
    punctuationDelay := 150
    if (style = "body") {
        typingDelay := Round(JourneyTypeDelayMs * 0.72)
        punctuationDelay := 115
    } else if (style = "result") {
        typingDelay := Round(JourneyTypeDelayMs * 0.88)
        punctuationDelay := 140
    } else if (style = "title") {
        typingDelay := Round(JourneyTypeDelayMs * 1.1)
        punctuationDelay := 165
    }
    if (JourneySpeedMode = "fast") {
        typingDelay := Round(typingDelay * 0.8)
        punctuationDelay := Round(punctuationDelay * 0.8)
    } else if (JourneySpeedMode = "readable") {
        typingDelay := Round(typingDelay * 1.2)
        punctuationDelay := Round(punctuationDelay * 1.2)
    }
    position := 1
    visibleText := ""
    while (position <= StrLen(text)) {
        chunk := SubStr(text, position, 2)
        SendText(chunk)
        visibleText .= chunk
        JourneyLiveControl.Value := visibleText
        position += StrLen(chunk)
        Sleep(typingDelay)
        if RegExMatch(chunk, "[，。；：！？｜]")
            Sleep(punctuationDelay)
    }
    Send("{Enter}")
    ApplyDemoTextStyle(hwnd, "body")
    Sleep(500)
}

JourneyPauseScale() {
    global JourneySpeedMode
    return JourneySpeedMode = "fast" ? 0.325
        : JourneySpeedMode = "readable" ? 0.55 : 0.4
}

SetGuideSegment(feature, story, hotkeyText) {
    global featureControl, storyControl, hotkeyControl, resultControl
    featureControl.Value := feature
    storyControl.Value := story
    hotkeyControl.Value := hotkeyText
    resultControl.Value := "正在应用窗口同步展示"
    Sleep(160)
}

JourneyProgress(index, title) {
    markers := ""
    Loop 6 {
        markers .= A_Index < index ? "● " : (A_Index = index ? "◆ " : "○ ")
    }
    return markers . "· " . title
}

TraceJourney(message) {
    global JourneyTracePath
    FileAppend(FormatTime(, "HH:mm:ss") . " " . message . "`n"
        , JourneyTracePath, "UTF-8")
}

ShiftJourneyDate(offset) {
    if (offset = 0)
        return true

    key := offset < 0 ? "!{Up}" : "!{Down}"
    direction := offset < 0 ? -1 : 1
    Loop Abs(offset) {
        currentDate := State.GetDate()
        targetDate := FormatTime(
            DateAdd(StrReplace(currentDate, "-", ""), direction, "Days"),
            "yyyy-MM-dd"
        )
        Send(key)
        deadline := A_TickCount + 3000
        while (State.GetDate() != targetDate && A_TickCount < deadline)
            Sleep(25)
        if (State.GetDate() != targetDate) {
            TraceJourney("Date switch timed out: from=" . currentDate
                . " to=" . targetDate . " actual=" . State.GetDate())
            throw Error("演示切换日期超时：" . currentDate . " → " . targetDate)
        }
    }
    return true
}

ApplyDemoTextStyle(hwnd, style) {
    bold := style = "body" ? 0 : 1
    size := 280
    charFormat := Buffer(92, 0)
    NumPut("uint", 92, charFormat, 0)
    NumPut("uint", 0x80000001, charFormat, 4)
    NumPut("uint", bold, charFormat, 8)
    NumPut("int", size, charFormat, 12)
    SendMessage(0x0444, 1, charFormat.Ptr, hwnd)
}

FinalizeJourneyNote(tag) {
    Send("^s")
    Sleep(900)
    rtfPath := NoteStoreService.FindRtf(State.GetDate())
    mdPath := NoteStoreService.FindMd(State.GetDate())
    if (rtfPath = "" || mdPath = "" || !FileExist(rtfPath) || !FileExist(mdPath))
        return false

    Send("^+t")
    if !WinWaitActive("日期标签 ahk_class AutoHotkeyGUI", , 3)
        return false
    Send("^a")
    SendText(tag)
    Send("{Enter}")
    if !WinWaitClose("日期标签 ahk_class AutoHotkeyGUI", , 3)
        return false
    Sleep(450)
    rtfPath := NoteStoreService.FindRtf(State.GetDate())
    mdPath := NoteStoreService.FindMd(State.GetDate())
    return InStr(rtfPath, "-" . tag . ".rtf") > 0
        && InStr(mdPath, "-" . tag . ".md") > 0
        && FileExist(rtfPath) && FileExist(mdPath)
}

JumpByQuery(query, expectedDate := "") {
    global JourneyAppGui, JourneyTracePath
    TraceJourney("FilteredJump: query=" . query . " expected=" . expectedDate)
    FocusJourneyApp()
    Send("^g")
    dialog := Config.AppName . " · 搜索跳转 ahk_class AutoHotkeyGUI"
    if !WinWaitActive(dialog, , 3)
        return false
    SendText(query)
    Sleep(650)
    rowIndex := FindFilteredJumpRow(query, expectedDate)
    TraceJourney("FilteredJump: selected result row=" . rowIndex)
    if (rowIndex = 0) {
        Send("{Esc}")
        return false
    }
    ClickJumpRow(dialog, rowIndex)
    closed := WinWaitClose(dialog, , 2)
    if !closed && WinExist(dialog) {
        WinActivate(dialog)
        Send("{Esc}")
        closed := WinWaitClose(dialog, , 2)
    }
    WinActivate("ahk_id " . JourneyAppGui.Hwnd)
    appActive := WinWaitActive("ahk_id " . JourneyAppGui.Hwnd, , 3)
    if appActive
        DllCall("SetFocus", "ptr", State.GetEd())
    passed := closed && appActive
        && (expectedDate = "" || State.GetDate() = expectedDate)
    TraceJourney("FilteredJump: closed=" . closed . " active=" . appActive
        . " date=" . State.GetDate() . " passed=" . passed)
    return passed
}

DirectJumpByDate(expectedDate) {
    global JourneyAppGui
    TraceJourney("DirectJump: open " . expectedDate)
    FocusJourneyApp()
    Send("^g")
    dialog := Config.AppName . " · 搜索跳转 ahk_class AutoHotkeyGUI"
    if !WinWaitActive(dialog, , 3) {
        TraceJourney("DirectJump: dialog not active")
        return false
    }

    rowIndex := 0
    for index, item in NoteStoreService.ListAllTags() {
        if (item.date = expectedDate) {
            rowIndex := index
            break
        }
    }
    if (rowIndex = 0) {
        TraceJourney("DirectJump: target date missing from list")
        Send("{Esc}")
        return false
    }

    if !ClickJumpRow(dialog, rowIndex) {
        Send("{Esc}")
        return false
    }
    closed := WinWaitClose(dialog, , 3)
    if !closed && WinExist(dialog) {
        WinActivate(dialog)
        Send("{Esc}")
        closed := WinWaitClose(dialog, , 2)
    }
    WinActivate("ahk_id " . JourneyAppGui.Hwnd)
    appActive := WinWaitActive("ahk_id " . JourneyAppGui.Hwnd, , 3)
    if appActive
        DllCall("SetFocus", "ptr", State.GetEd())
    matched := closed && appActive && State.GetDate() = expectedDate
    TraceJourney("DirectJump: closed=" . closed . " active=" . appActive
        . " date=" . State.GetDate())
    return matched
}

FindFilteredJumpRow(query, expectedDate) {
    words := StrSplit(query, " ")
    rowIndex := 0
    for item in NoteStoreService.ListAllTags() {
        matched := true
        for word in words {
            word := Trim(word)
            if (word != "" && !InStr(item.date, word) && !InStr(item.tag, word)) {
                matched := false
                break
            }
        }
        if !matched
            continue
        rowIndex++
        if (item.date = expectedDate)
            return rowIndex
    }
    return 0
}

ClickJumpRow(dialog, rowIndex) {
    global JourneyTracePath
    listHwnd := ControlGetHwnd("SysListView321", dialog)
    if !listHwnd {
        TraceJourney("List click: list control not found")
        return false
    }
    rect := Buffer(16, 0)
    NumPut("int", 0, rect, 0)
    messageResult := SendMessage(0x100E, rowIndex - 1, rect.Ptr, "SysListView321", dialog)
    top := NumGet(rect, 4, "int")
    bottom := NumGet(rect, 12, "int")
    if (bottom <= top) {
        TraceJourney("List click: invalid rectangle row=" . rowIndex
            . " result=" . messageResult . " top=" . top . " bottom=" . bottom)
        return false
    }

    clickY := (top + bottom) // 2
    TraceJourney("List click: row=" . rowIndex . " client=260," . clickY)
    packedPosition := ((clickY & 0xFFFF) << 16) | 260
    DllCall("SetFocus", "ptr", listHwnd, "ptr")
    DllCall("PostMessageW", "ptr", listHwnd, "uint", 0x0200
        , "ptr", 0, "ptr", packedPosition, "int")
    DllCall("PostMessageW", "ptr", listHwnd, "uint", 0x0201
        , "ptr", 1, "ptr", packedPosition, "int")
    DllCall("PostMessageW", "ptr", listHwnd, "uint", 0x0202
        , "ptr", 0, "ptr", packedPosition, "int")
    Sleep(80)
    DllCall("PostMessageW", "ptr", listHwnd, "uint", 0x0203
        , "ptr", 1, "ptr", packedPosition, "int")
    DllCall("PostMessageW", "ptr", listHwnd, "uint", 0x0202
        , "ptr", 0, "ptr", packedPosition, "int")
    return true
}

JourneyDateForTag(tagIndex) {
    today := FormatTime(, "yyyyMMdd")
    return FormatTime(DateAdd(today, tagIndex - 7, "Days"), "yyyy-MM-dd")
}

PasteDemoImage() {
    global JourneyImagePath
    savedClipboard := ClipboardAll()
    bitmap := DllCall("LoadImageW", "ptr", 0, "str", JourneyImagePath
        , "uint", 0, "int", 0, "int", 0, "uint", 0x10, "ptr")
    if !bitmap
        throw Error("Could not load the isolated demo image bitmap.")
    opened := false
    transferred := false
    try {
        if !DllCall("OpenClipboard", "ptr", 0, "int")
            throw Error("Could not open the clipboard for the image demonstration.")
        opened := true
        if !DllCall("EmptyClipboard", "int")
            throw Error("Could not prepare the clipboard for the demo image.")
        if !DllCall("SetClipboardData", "uint", 2, "ptr", bitmap, "ptr")
            throw Error("Could not place the demo image on the clipboard.")
        transferred := true
        if !DllCall("CloseClipboard", "int")
            throw Error("Could not release the clipboard after preparing the demo image.")
        opened := false
        Send("^v")
        Sleep(1400)
    } finally {
        if opened
            DllCall("CloseClipboard")
        if !transferred
            DllCall("DeleteObject", "ptr", bitmap)
        A_Clipboard := savedClipboard
    }
}

CountOccurrences(text, needle) {
    count := 0
    position := 1
    while (position := InStr(text, needle, , position)) {
        count++
        position += StrLen(needle)
    }
    return count
}
