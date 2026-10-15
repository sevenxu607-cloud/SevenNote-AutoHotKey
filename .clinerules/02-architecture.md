# 02 · 架构约定（四层 + 组合根）

## 铁律

```
┌─────────────────────────────────────────────────────┐
│ FEATURE  功能层（18 项，按用户旅程排列）             │
│  · Feature 之间零调用，通过 EventBus 通信            │
│  · 可插拔：删除任一 Feature 不影响其他               │
├─────────────────────────────────────────────────────┤
│ SERVICE  服务层（6 项，纯能力）                     │
│  · 无业务、无时间、无理由                            │
│  · 被多个 Feature 共用                              │
├─────────────────────────────────────────────────────┤
│ KERNEL   骨架层（4 项）                             │
│  · 生命周期 / 状态 / 事件 / 配置                     │
│  · 冻结，只加不改                                    │
├─────────────────────────────────────────────────────┤
│ 表示层：StatusBar  ·  组合根：装配 + 启动            │
└─────────────────────────────────────────────────────┘

依赖方向：Feature → Service → Kernel → OS（严禁反向）
```

## 改动原则

1. **不动 Kernel / Service，只加 Feature。**
2. Feature 之间**零调用**，一律通过 `EventBus.Emit` 通信。
3. 可插拔：删除任一 Feature 不得影响其他 Feature。
4. 依赖方向**严禁反向**（Kernel 不许调 Service，Service 不许调 Feature）。

## 加新功能的标准步骤

1. 在 FEATURE 层新增一个 class
2. 在组合根注册热键
3. 通过 `EventBus.Emit` 通知结果

参考实现（README「开发指南」原文）：

```ahk
class ExportFeature {
    static ExportHtml() {
        hwnd := State.GetEd()
        rtfPath := NoteStoreService.RtfPath(State.GetDate())
        htmlPath := NoteStoreService.TempDir() . "\export.html"
        cmd := '"' . Config.PandocPath . '" "' . rtfPath . '" -o "' . htmlPath . '"'
        RunWait(A_ComSpec . ' /c "' . cmd . '"', , "Hide")
        Run(htmlPath)
    }
}
```

组合根加一行即可：`!e::ExportFeature.ExportHtml()` —— 不需要改任何其他 Feature。

## 加新主题

`ThemeService.Themes` 数组加一行：

```ahk
{name: "暗夜黑", win: "1E1E1E", edBg: "252526", text: "D4D4D4", dim: "808080"},
```

加完 `Alt+T` 自动循环到新主题，无需改别处。

### 带背景图的主题

多一组可选字段：`bg`（图片绝对路径）、`bgAlpha`（压暗遮罩 0-100）。

```ahk
{name: "极光", win: "0D0F14", edBg: "0D0F14", text: "F5F9FF", dim: "9FAABC"
    , bg: "D:\Pictures\your-wall.png"
    , bgAlpha: 0}
```

- **`bg` / `bgAlpha` 必须成对**：`BackdropFeature._Sync()` 见 `bg` 就读 `t.bgAlpha`，
  缺了会抛「属性不存在」。
- **只能追加到数组末尾**：`ThemeIndex` 存下标，插中间会顶掉老用户当前的主题。
- **配色从图取**，用 `tools\pick-theme-colors.ps1`（`win` = 图均色 × 0.55；
  星空主题即均色 `#171C25` → `#0D0F14`）。`edBg` 兼作压暗遮罩色，偏离图色会发灰。
- **`BackdropImage` 是全局覆盖**，会盖掉所有带 `bg` 的主题 → 多套图主题并存时别设它。

完整步骤、图片规格与压暗三法见 README「开发指南 → 添加带背景图的主题」。
