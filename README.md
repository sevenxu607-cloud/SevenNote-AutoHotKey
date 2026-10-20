# SevenWork-AutoHotKey
Lightweight daily scratchpad for Windows (AHK v2): RichEdit editing, dual RTF storage, Pandoc → Markdown, Obsidian inbox. One hotkey, auto-save, image support, date tags.
# SevenWork

> 一键唤起的 Windows 本地速记工具 —— 富文本编辑 + 双 RTF 存储 + Markdown 输出
> 为 Obsidian 收件箱场景设计，走到哪记到哪，图文并茂、无感保存、标签管理
>
> 📄 **只想快速了解？** 看 [`docs/PROJECT-OVERVIEW.md`](./docs/PROJECT-OVERVIEW.md) —— 一页纸全景（定位 / 规模 / 欠账 / 限制）
> 🔧 **想看技术实现？** 看 [`docs/PROJECT-IMPLEMENTATION.md`](./docs/PROJECT-IMPLEMENTATION.md) —— 15 个技术块（RichEdit / GDI / Dwm / Launcher 契约…）
> 🧭 **想看工作台化路线？** 看 [`docs/WORKBENCH-PLAN.md`](./docs/WORKBENCH-PLAN.md) —— 三张归属表 + Phase 0–6

![version](https://img.shields.io/badge/version-2.4.4-blue)
![platform](https://img.shields.io/badge/platform-Windows%2010%2F11%20x64-lightgrey)
![language](https://img.shields.io/badge/language-AutoHotkey%20v2-green)
![license](https://img.shields.io/badge/license-MIT-orange)

## 界面预览

### 主界面
![主界面](./docs/screenshots/main.png)

### 帮助页面
![帮助页面](./docs/screenshots/help.png)

### 检索页面
![检索页面](./docs/screenshots/search.png)

### 日期跳转
![日期跳转](./docs/screenshots/date-jump.png)

### 主题字体切换
![主题字体切换](./docs/screenshots/theme-font.png)

### 在 Obsidian 中回顾
![Obsidian 回顾](./docs/screenshots/obsidian.png)

---

## ✨ 为什么用 SevenWork

### 痛点

你是否有过这些体验：

- 想记点什么，**打开笔记软件要 3~5 秒**，灵感已经跑了
- 记录时想**加粗重点、插张图、标个颜色**，结果只有纯文本
- 记完的笔记**散落在时间线里**，一个月后完全想不起哪天记过什么
- 已有的笔记软件要么**太重**（100MB 内存起步），要么**太轻**（不支持富文本）
- 同步到 Obsidian 时**图片链接全丢**，格式乱成一团

### SevenWork 的答案

| 你的需求 | SevenWork 的做法 |
| --- | --- |
| **秒级唤起** | 全局热键 `Alt+Z`，100ms 内呼出/隐藏，不打断工作流 |
| **富文本编辑** | 基于 RichEdit：加粗、颜色、字体、内嵌图片，一个不少 |
| **图片随手粘** | `Ctrl+V` 直接粘图，自动存 PNG，自动生成 Markdown 链接 |
| **能一眼找到** | 每天一个标签，写在文件名里：`2026-09-20-机器学习.md` |
| **和 Obsidian 无缝** | 自动生成 `.md` + `_assets/日期/` 图片目录，Obsidian 直接读 |
| **不丢数据** | 定时 / 隐藏 / 切日期 / 粘贴 自动保存，空笔记不落盘 |
| **轻量不打扰** | 单 EXE ~250MB（含 Pandoc），运行内存 ~10MB，纯 Windows 原生 |

---

## 🎯 核心特性

### 🪶 极致轻量

- **启动 < 100ms**：双击即用，不拖累系统
- **内存 ~10MB**：常驻后台无感
- **单文件分发**：`SevenWork.exe` 一个文件，无需安装
- **零依赖运行**：EXE 版内置 Pandoc，用户无需装任何东西

### 📝 富文本编辑

- 加粗、斜体、颜色、字体大小，随时切换
- **`Ctrl+V` 直接粘图**，自动存到 `_assets/日期/`
- **`Ctrl+Shift+V` 粘贴纯文本**，剥离外部格式
- **Tab 缩进不丢字符格式**（很多编辑器做不到这点）

### 💾 双格式归档

保存时同时输出两种格式，各取所需：

```
936 RTF（GBK）   → WPS / Word / 写字板 打开都正常
65001 RTF（UTF-8） → 给 Pandoc 转 Markdown
最终产物：
  .rtf  富文本母版（保真）
  .md   Markdown 译本（便携）
  _assets/日期/  图片附件
```

### 🏷️ 标签系统

**标签写在文件名里**，黑曜石里见名知意：

```
无标签：  2026-09-20.md
有标签：  2026-09-20-机器学习.md
```

- `Ctrl+Shift+T` 一键设标签
- 顶部状态栏常驻显示：`🏷 机器学习`
- `Ctrl+G` 统一搜索日期 / 标签，双击跳转

### 🗓️ 日期管理

- `Alt+↑ / Alt+↓` 前后一天
- `Alt+Home` 一键回今天
- **状态栏显示星期**：`📅 2026-09-20 周日`
- **切日期自动定位到开头**（不是末尾）
- **空笔记不落盘**：Vault 永远干净

### 🎨 5 套主题 + 7 种字体

- **主题**：纯米黄 / 护眼绿 / 纸白 / **星空** / **金克斯**
- **字体**：楷体 / 华文行楷 / 华文新魏 / 方正舒体 / 仿宋 / 微软雅黑 / 黑体
- **字号**：12 / 14 / 16 / 18 / 20 pt
- **`Alt+T` 切主题，`Alt+Shift+T` 切字体，`Alt+=/-` 调字号**
- 全部自动记忆，重启保留
- 最后两套是**背景图主题**：切到它们，一张图片铺满编辑区，文字**直接浮在图上**
- 两套都走「**暗图 + 亮字**」：图不动明暗（只把压在字下的最亮处滚降一点），窗框 / 标题栏 /
  状态栏一起转深，人物（星空是星云）铺满编辑区

### 🖼 背景图主题（星空 / 金克斯）

**背景图不是全局开关，而是与其它 3 套并列的第 4、5 套主题。** `Alt+T` 轮到它们时，一张图片
铺满编辑区，文字**直接浮在图上**（终端式，不是相框式）。

- 切到带图的主题就铺图，切到其它 3 套会**自动撤掉图**、回到纯色底 —— 想关背景图就切主题
- 两套都用**等比铺满**（cover）：只裁不压，铺进近方形的编辑区不会被压扁。竖版人物图
  （0.676）和编辑区（0.917）比例差得远，靠**烘焙时先裁好再铺**，而不是运行时用
  `bgFit: "contain"` 把它缩进中间 —— 那样两侧会留一大条底色、人物显小
- 两套都走「**暗图 + 亮字**」，这不是偏好，是量出来的：
  - 「星空」星云均亮只有 28；「金克斯」原图均亮 **75**。两者都远低于亮字那条线
    （背景 ≤ 118），**本来就该配亮字，根本不需要提亮**。正文取近白 `#F5F9FF` / `#EAF2FF`，
    次级文字 `#9FAABC` / `#93AACB`
  - 「金克斯」只有一处例外：脸、手和那片白雾亮到 254，亮字压上去会糊。所以烘焙时把
    **最亮的 15% 滚降**（`V > 116` 的部分线性压到 152），暗部一个像素都不动 ——
    全图均亮度 75.1 → **74.9**，看上去就是原图本身，而亮度 >118 的像素从 20.5% 降到 9.1%
- ⚠️ **上一版走过的弯路**：为了迁就「深色字」，把这张图整体抬亮到均亮 170 ——
  结果整张图"蒙了层灰"、和原图完全不像。**提亮不等于清晰，它是把原图洗白。**
  暗图就该配亮字。混白（加法提亮）更糟：实测把最彩 5% 像素的饱和度从 45.8% 砍到 26%
- 配色取自图本身：星空取全图均色 `#181C25` → `#0D0F14`；金克斯取冷调（`B > R`），
  窗框 / 编辑区 / 搜索条 `#0B1624`（比图的暗部再蓝一档），正文 `#EAF2FF`、次级 `#93AACB` ——
  四个色压在同一色族里，窗口、标题栏、编辑区一起转深，没有色块割裂感
- 标题栏**整块取主题色**：`win` 的加权亮度 < 128 就开 immersive dark mode（Win10 只有这一档），
  Win11 上再进一步 —— 用 `DWMWA_CAPTION_COLOR / TEXT_COLOR / BORDER_COLOR`(35/36/34) 把标题栏
  底色染成 `win`、标题文字染成 `text`、外框同 `win`。实测标题栏像素精确等于 `#0B1624`，
  和窗框连成一体
- **编辑区滚动条也跟着主题**：滚动条画在**非客户区**、由系统主题上色，深色主题下原来会留一条
  亮白竖条压在暗底上（浅色主题下则相反）。`ThemeService._SetScrollBarTheme` 把编辑区窗口主题
  设成 `DarkMode_Explorer` / `Explorer` 即随主题明暗 —— 实测滚动条区域的像素均亮度 **40**
  （编辑区 75，同档暗）、**亮像素 0 个**
- **上下滑动时不再频闪**：主窗口开了 `WS_EX_COMPOSITED`（`+E0x02000000`）离屏双缓冲 ——
  编辑区 RichEdit 自身不带双缓冲，滚动时会先擦一遍客户区再画文字，那一帧空档正是「滑动时
  略微频闪」的来源；合成重绘后父子控件的绘制顺序由系统统一保证
- 改窗口大小、切主题、开搜索栏都会按编辑区的新位置重新铺图
- 图片缺失时自动降级为纯色底（`edBg`），文字照样读得清

想再加一套**别的图**当主题（极光、雪原……）？见
[开发指南 → 添加带背景图的主题](#添加带背景图的主题)，配 `tools\pick-theme-colors.ps1` 一键取色。

**换图 / 调浓淡**都改**主题自己**：`ThemeService.Themes` 里那一条的 `bg`（图路径）与
`bgAlpha`（遮罩不透明度 0-100；遮罩色取该主题 `edBg`，暗主题压暗、亮主题加白纱）。
不设全局开关 —— 多套图主题才能各调各的（换图后**重启程序**才生效，位图有缓存）。

### ⌨️ 输入增强

- `CapsLock+H/J/K/L` = 方向键（`Alt+Shift+C` 开关）
- 写长文时手不离主键区
- 可选，不影响正常 CapsLock 使用

---

## 🚀 快速开始

### 方式 A：使用 EXE（推荐普通用户）

1. 从 [Releases](../../releases) 下载 `SevenWork.zip`（约 40MB，解压后得到 SevenWork.exe）
2. 放到任意非系统盘目录（如 `D:\tools\`）
3. **关闭杀毒软件**（AHK 编译的 EXE 常被误报）
4. 双击运行
5. 首次弹框 → **选择笔记存储目录**（如 `D:\我的笔记\SevenWork`）
6. 按 `Alt+Z` 呼出 → 开始使用

### 方式 B：使用源码（推荐开发者）

1. 安装 [AutoHotkey v2](https://www.autohotkey.com/)
2. 安装 [Pandoc](https://mirrors.lzu.edu.cn/)（国内镜像，选 `x86_64` 版）
3. 把整个项目目录放任意位置，双击根目录的 `SevenWork.ahk`（极简启动器，运行代码统一在 `src/`）
4. 首次运行会弹框让你选笔记目录

仓库里的其它东西：

| 路径 | 用途 |
| --- | --- |
| `SevenWork.ahk` | 根目录启动器：把入口转给 `src\`，并保持 `A_ScriptDir` 指向项目根 |
| `src\SevenWork.ahk` | 组合根：装配 + 启动 |
| `src\WorkBench\` | 平台层：Kernel / 热键路由 / 模块登记 / 统一帮助 / 伙伴协调 |
| `src\modules\SevenNote\` | 笔记模块：7 个 Service + `StatusBar` + 18 个 Feature + 模块生命周期 |
| `src\modules\Launcher\` | 外部程序模块：`PeerLayoutService` + PowerShell / DeepSeek Feature + 模块生命周期 |
| `src\modules\KeysInput\` | 键位模块：`CapsLockFeature` + 模块生命周期 + `Alt+Shift+C` |
| `docs\legacy\SevenNote.v2.4.3.ahk` | Phase 2 拆分前的单文件快照（只作对照，不参与运行） |
| `tools\` | 开发辅助脚本，如 `pick-theme-colors.ps1` 从壁纸取主题配色 |
| `docs\screenshots\` | README 配图 |
| `docs\` | 项目文档：`DEVLOG.md`（开发日志）、`PROJECT-OVERVIEW.md`（一页纸全景）、`PROJECT-IMPLEMENTATION.md`（技术清单）、`WORKBENCH-PLAN.md`（工作台化路线） |
| `.clinerules\` | 架构约定与踩坑记录（`05-theme-image.md` 是「看图生成主题」的配方 + 偏好） |

---

## ⌨️ 快捷键一览

### 全局热键（任何程序中都生效）

| 热键 | 功能 |
| --- | --- |
| `Alt+Z` | 呼出 / 隐藏 |
| `Alt+Shift+Z` | 保存并退出 |
| `Alt+C` | 呼出 / 隐藏 PowerShell，笔记窗口自动与它上下对齐成规整一列 |
| `Alt+X` | 呼出 / 隐藏 DeepSeek 网页（**独立 profile 的普通 Edge 窗口**，标签栏与工具栏齐全，窗口内可直接浏览网页），同样自动与笔记对齐 |
| `Alt+S` | 显示快捷键帮助 |
| `Alt+↑ / Alt+↓` | 前一天 / 后一天 |
| `Alt+Home` | 回到今天 |
| `Alt+T` | 切换主题（含两套背景图主题「星空 / 金克斯」） |
| `Shift+Alt+T` | 切换字体 |
| `Alt+= / Alt+-` | 调大 / 调小字号 |
| `Alt+Shift+C` | 切换 CapsLock 键盘映射 |

### 编辑器内热键（窗口激活时）

| 热键 | 功能 |
| --- | --- |
| `Ctrl+S` | 手动保存 |
| `Ctrl+Z / Ctrl+Shift+Z` | 撤销 / 重做 |
| `Ctrl+Y` | 删除当前行 |
| `Ctrl+D` | 复制当前行到下方 |
| `Ctrl+Shift+↑ / ↓` | 上移 / 下移当前行 |
| `Tab / Shift+Tab` | 增加 / 减少缩进（不丢格式） |
| `Ctrl+Shift+V` | 粘贴为纯文本 |
| `Ctrl+T` | 手动追加时间戳（v2.4 起不再自动加） |
| `Ctrl+H` | 插入按编辑区宽度动态生成的分隔线 |
| `Ctrl+Shift+H` | 插入 `## 分段` 标题 |
| `Ctrl+F` | 打开搜索栏 |
| `Ctrl+G` | 搜索跳转（日期 / 标签） |
| `Ctrl+Shift+T` | 为当前日期设置标签 |

### 搜索栏内

| 热键 | 功能 |
| --- | --- |
| `Enter / Shift+Enter` | 下一个 / 上一个匹配 |
| `Esc` | 关闭搜索栏 |

---

## 📁 文件结构

### Vault 目录（你的笔记）

```
你的Vault/
├── 2026-09-20.rtf                富文本母版
├── 2026-09-20.md                 Markdown 译本
├── 2026-09-20-机器学习.rtf        带标签的富文本
├── 2026-09-20-机器学习.md         带标签的 Markdown
├── _assets/                      ★ 图片统一收纳
│   ├── 2026-09-20/
│   │   └── image1.png
│   └── 2026-09-19/
│       └── image2.png
└── _tmp/                         pandoc 临时目录（自动清理）
```

### 配置目录（AppData）

程序用**两个**目录，故意分开：

```
C:\Users\<用户名>\AppData\Roaming\SevenWork\
└── pandoc.exe                    内嵌的 Pandoc（仅 EXE 版，100+MB，跨版本共用一份）

C:\Users\<用户名>\AppData\Roaming\SevenWork-Dev\
├── _config.ini                   配置（几百字节）
└── _error.log                    出错日志（仅编译版；只在真出错时才出现，超 512KB 自动轮转）
```

⚠️ **开发版（未编译）的报错日志不在这里**，而是落在**项目根的 `.logs\_error.log`**
（`Config.LogPath` 按 `A_IsCompiled` 分流）—— 开发时一眼就能翻，`.gitignore` 已忽略
`.logs/`；编译后 exe 可能在桌面 / U 盘 / `Program Files`，那里要么脏用户目录、要么
没有写权限，所以仍回 AppData。项目目录不可写时会退回 AppData 再记一次。

⚠️ **`SevenWork-Dev` 是开发版的配置目录**（`Config.ConfigPath`）。`_config.ini` 存的是
使用者状态（主题 / 字体 / Vault 路径），按版本隔离更安全：两版并存时各改各的、不互相覆盖。
`pandoc.exe` 太大、又不随版本变，所以留在 `SevenWork\` 共用 —— 源码里
`Config.PandocPath` 与 `Config.ConfigPath` 指向不同目录**不是笔误**。

⚠️ **`_config.ini` 里可能残留不再被读取的键**（历史版本留下的，例如 `[Appearance]`
`BackdropOn`）。程序只读 `ConfigService.SetDefault` 里声明过的键，多余的键既不读也不报错，
删不删都行 —— **别因为某个键在代码里搜不到就当成"漏接线"**。

⚠️ **配置在进程内被缓存**（v2.4.2 起）：`ConfigService.Read` 读一次就记住，之后不再碰磁盘 ——
`Config.GetVault()` 在单次保存里就要被调 6 次以上（`FindRtf` / `DefaultRtfPath` / `FindMd` /
`DefaultMdPath` / `TempDir` / `AssetsDir`），每次都读盘不值当。代价是**运行期手改
`_config.ini` 不会立刻生效，改完请重启程序**（程序自己写配置的路径会同步缓存，
所以主题 / 字体这类在程序内切换的照旧即改即用）。

### 笔记内容示例

```markdown
# 📅 2026-09-20 速记

🕐 09:15
今天开会讨论了三件事：
- 项目进度
- 人员安排
- 下周计划

![](./_assets/2026-09-20/image1.png)

🕐 14:30
下午想到一个点子……
```

---

## 🔧 技术特色

### 架构：四层 + 组合根

```
┌─────────────────────────────────────────────────────┐
│ FEATURE  功能层（21 项，按用户旅程排列）             │
│  · Feature 之间零调用，通过 EventBus 通信            │
│  · 可插拔：删除任一 Feature 不影响其他               │
├─────────────────────────────────────────────────────┤
│ SERVICE  服务层（8 项，纯能力）                     │
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

### 三个核心设计决策

**1. 用 `EM_STREAMOUT/EM_STREAMIN` 直读直写 RTF**

不碰剪贴板（剪贴板是程序间共享资源，用它做进程内私有通道会引发并发竞争）。所有保存/加载都走 Win32 消息，稳定、无副作用。

**2. 用 Pandoc 转换 RTF → Markdown**

不自研解析器（原版 150 行自研解析器脆弱，依赖隐式约定）。Pandoc 成熟稳定，图片位置按 RTF 结构精确提取。

**3. 双 RTF 输出（936 + 65001）**

RichEdit 只输出非标编码，Pandoc/Word 认的标准不同——**三方各有死结**。只能每次保存输出两份 RTF，各给一方。

### 代码与数据分离

| 类别 | 位置 | 备份 |
| --- | --- | --- |
| **代码** | `SevenWork.exe`（放哪都行） | ❌ 不需 |
| **笔记数据** | Vault 目录（用户选的） | ✅ **只需备份这个** |
| **程序配置** | `%AppData%\SevenWork-Dev\_config.ini`（发布版为 `%AppData%\SevenWork\`） | ⚠️ 可选 |
| **内嵌 Pandoc** | `%AppData%\SevenWork\pandoc.exe` | ❌ 自动释放 |

**备份策略**：只拷 Vault 目录，其他丢了都能重建。

---

## ❓ 常见问题

### Q1：双击 `.ahk` 报"此应用无法在你的电脑上运行"

装的是 **AutoHotkey v1**（不是 v2），或装了 **ARM64 版**。

**修复**：
1. 卸载现有 AutoHotkey
2. 下载 x64 版：`https://www.autohotkey.com/download/ahk-v2.exe`
3. 安装后重试

**验证**：托盘图标右键 → About → 版本必须是 v2.0.x

### Q2：保存时报"此应用无法在你的电脑上运行"

`%AppData%\SevenWork\pandoc.exe` 是**坏文件**（0KB / ARM64 / 损坏）。

**修复**：
1. Win+R → `%AppData%\SevenWork` → 回车
2. **删除** `pandoc.exe`
3. 下载 x86_64 版 pandoc，放到该目录
4. 重启 SevenWork

**临时方案**：删掉 `pandoc.exe` 不装 → 保存降级为纯文本 `.md`，笔记不丢。

### Q3：粘贴图片后 `.md` 里没有图片

Pandoc 不可用，走了降级路径。

**排查**：cmd 运行 `"%AppData%\SevenWork\pandoc.exe" --version`：
- 显示版本号 → pandoc OK，可能是图片是 OLE 对象（从 Word 复制的）→ 改用 `Win+Shift+S` 截图后粘贴
- 报错 / 找不到 → 装 x64 版 pandoc

### Q4：`.rtf` 文件全篇带下划线

**32 位编译**导致的（加载了 32 位 `msftedit.dll`）。

**修复**：用 **64 位 Unicode** 重新编译。

### Q5：找不到 Vault 路径

- `Alt+S` → 帮助窗口底部显示"当前笔记目录"
- 或看 `%AppData%\SevenWork-Dev\_config.ini` 里的 `Vault=`（发布版路径为 `%AppData%\SevenWork\`）

**换 Vault**：编辑 `_config.ini` 改 `Vault=`，或删这行重启让程序弹框重选。

### Q6：改了主题/字体，重启后没保存

`%AppData%\SevenWork-Dev\_config.ini`（发布版为 `%AppData%\SevenWork\`）没有写权限或被占用。

**修复**：
1. 关闭 SevenWork
2. 删除 `_config.ini`
3. 重开 → 重新设置

### Q7：如何备份

**只备份 Vault 目录**（如 `D:\我的笔记\SevenWork\`）——包含所有 `.rtf` / `.md` / `_assets`。

配置和内嵌 pandoc 丢了都能重建，不重要。

---

## 🛠️ 开发指南

### 添加新功能

**核心原则**：不动 Kernel / Service，只加 Feature。

**步骤**：
1. 在 FEATURE 层加一个类
2. 把热键加到所属模块的 `GetHotkeys()`（平台热键归 `WorkBench.GetHotkeys()`；
   注册与 `Alt+S` 帮助共用这份数据 —— 写一次，两处同时生效）
3. 通过 `EventBus.Emit` 通知结果

**示例**：加"导出 HTML"

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

在所属模块的 `GetHotkeys()` 里加一行（例如笔记模块的 `Ctrl+E` 导出）：

```ahk
{ctx: "editor", key: "$^e", group: "保存", line: "   Ctrl+E           导出 HTML"
    , fn: (*) => ExportFeature.ExportHtml()},
```

`group` 取 `WorkBenchUI._GroupOrder` 里的组名之一（平台 / 窗口 / 外观 / 输入增强 /
搜索 / 保存 / 日期与标签 / 编辑 / 分段）。新组不在表里也没关系，会按首次出现顺序
自动追加到帮助末尾 —— 不用改显示函数。

**完成**，不需要改任何其他 Feature，也不用再去帮助窗口里补文本：
`HotkeyRouter` 注册与 `WorkBenchUI` 帮助读的是同一份模块数据。

### 添加新主题

`ThemeService.Themes` 数组加一行：

```ahk
{name: "暗夜黑", win: "1E1E1E", edBg: "252526", text: "D4D4D4", dim: "808080"},
```

加完 `Alt+T` 自动循环到新主题。

### 添加带背景图的主题

「星空」不是特例，也不是全局开关 —— 它只是 `Themes` 数组里唯一带 `bg` 的普通成员。
所以**再添一套图主题，做法就是给数组再加一个带 `bg` 的对象**，别处一律不用改：
切到它就铺图，切走就撤图，窗口、标题栏、搜索条一起跟着变。

> **出图前先看 `.clinerules\05-theme-image.md`** —— 那是「看图生成主题」的配方 + 已固化的偏好
> （主体完整、保留原图明暗、饱和一丝不掉、文字可读让位于画面观感）。本章的参数与实测经验都在，
> 但**最短路径在那张清单里**。

#### 第 1 步：量出这张图的颜色

别凭感觉配。编辑区的底色同时被当作遮罩色，跟图差得远就会压成灰蒙蒙一片。
仓库里带了个小脚本，直接给答案：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\pick-theme-colors.ps1 `
    -Image "D:\Pictures\你的图.png" -Name "极光"
```

它把图缩到 256px 宽后统计明暗分布，输出可直接粘贴的条目：

```
mean colour : #171C25   luma 27.5
luma p10/p50/p90 : 12.4 / 24.2 / 46.8
crop note   : wider than the editor area -> cover scaling trims the left/right edges.
darkness    : the image is DARK -> bgAlpha 0 (no dimming), matching Windows Terminal.

Paste into ThemeService.Themes:

    {name: "极光", win: "0D0F14", edBg: "0D0F14", text: "F5F9FF", dim: "9FAABC"
        , bg: "D:\Pictures\你的图.png"
        , bgAlpha: 0}
```

`win` / `edBg` = 图的全图均色压暗到 55%。**现有星空主题正是这么来的**（均色 `#171C25` → `#0D0F14`），
可以用它自测脚本是否正常：`-Image "...\2026-10-14_星空-灰色2.png"` 应当输出 `win: "0D0F14"`。
`-Name` 可以直接写中文。

> 脚本只给**暗图**那一套（暗窗框 + 近白字）。图算下来偏亮就别照抄 ——
> 亮图要反着配「浅窗框 + 取自图色相的深字」，见下面第 4 步。

#### 第 2 步：粘进 `ThemeService.Themes`

```ahk
{name: "极光", win: "0D0F14", edBg: "0D0F14", text: "F5F9FF", dim: "9FAABC"
    , bg: "D:\Pictures\你的图.png"
    , bgAlpha: 0}
```

**完成。** `Alt+T` 自动循环到它；铺图、撤图、窗口记忆全部自动生效。

#### 第 3 步（可选）：竖版图别用 `contain`，裁好再铺

图主题默认按 **cover** 铺：等比放大到刚好盖满编辑区，多出来的边裁掉。

编辑区大体近方（**实测 443x483 ≈ 0.917**，随窗口变），而竖版人物图常见 0.676 ——
比例差这么多，三条路里只有最后一条好看：

| 做法 | 结果 |
| --- | --- |
| `bgFit: "contain"`（整图缩进） | 两侧留一大条 `edBg` 底色，人物缩在中间、显小 |
| 直接 cover（铺满） | 上下裁掉 26%，常常切到头 |
| ✅ **烘焙时先裁成 0.917 再铺 cover** | 铺满、无留边，裁哪一块由你定（专挑人物） |

所以正解是**在第 1 步之前多一道工序**：用 `tools\rebake-backdrop.ps1` 的
`-CropX / -CropW / -CropY` 把人物裁出来（顺手把碍事的成片亮块裁出框外），
输出图本身就是 0.917 —— 运行时 cover 即铺满，一个像素不浪费。

- **`bgFit` 仍是可选字段**：不写就是 `cover`（星空一直是它，行为分毫不变）。
- **只有两个值**：`"cover"`（默认）/ `"contain"`；写别的当 `cover` 处理。
- **`contain` 必须铺底色**：留边若不管，露出来的是 GDI 从未初始化过的位图内存（花屏 / 黑块）。
  `BackdropService._Compose` 已内置 `FillRect` 铺底，且**只在 contain 时执行**，cover 不碰。

> **⚠ 窗口拉伸时编辑区文字时隐时无，是「铺图时机」的问题，不是图的问题。**
> 背景层是**兄弟 Static 控件**、编辑区带 `WS_EX_TRANSPARENT` —— 背景层每重画一次，
> 编辑区的文字就被连带作废一次。而拖动窗口时 `WM_SIZE` 每秒来几十次，若每次都重跑
> 一遍「2400px 源图 → HALFTONE 多级对折 → 十万字富文本重排」，几十毫秒一次的合成会灌满
> 绘制队列，表现就是**文字闪**。`BackdropFeature` 为此做了两件事：`_ScheduleRender()`
> 用 `SetTimer(…, -80)` 把一串 `WM_SIZE` **合并成一次**渲染；`_RenderNow()` 再比一次矩形，
> 与上次相同就**直接跳过**，只有真重铺过才 `RedrawWindow(ed, INVALIDATE|ERASE)` 让文字补上。
> 实测 1361x1084 窗口连打 40 次 resize：总耗时 **392ms**（每次 10ms；逐帧重铺会是秒级），
> 且 resize 前后截图**逐像素完全一致**。切换主题走 `_Apply` → `_RenderNow(true)`，
> **绕过防抖、立即生效**。

> **⚠ 重新烘焙后必须重启程序才看得见新图。** `BackdropService.LoadSource()` 把解码后的位图
> **缓存在 `_srcBmp`**（惰性、只做一次），文件换了但路径没变时**不会重读** ——
> 验证新烘的图要重启 `SevenWork.ahk`，别对着旧画面怀疑烘焙没生效。

#### 第 4 步（可选）：图偏亮就只滚降亮部 —— **绝不要整体提亮**

**先量图，再决定动不动它。** 量的是**亮部**（`tools\pick-theme-colors.ps1` 给均色与
luma p10/p50/p90；12x12 网格的 p90 能把成片亮块钉到具体位置）——亮字怕的不是暗，是压在
字下面的亮块。判据就一条：**背景亮度 ≤ 118** 时，近白文字（`#F5F9FF`）的对比度才够 4.5:1。

| 图的情况 | 怎么办 |
| --- | --- |
| 均亮 ≤ 90、亮区零星 | **什么都不用做** —— 原图直出就是最好看的 |
| 亮区成片（脸、灯光、白墙） | 只把**亮部滚降**：`V > Knee` 的部分线性压到 `HiMax` |
| 整张图就亮（均亮 ≥ 130） | 那才轮到「亮图 + 深字」，见本节末尾 |

**滚降怎么算**（`rebake-backdrop.ps1` 的 `-Knee` / `-HiMax`）：

```
V' = V                                                  (V ≤ Knee，原样不动)
V' = Knee + (V - Knee) × (HiMax - Knee) / (255 - Knee)   (V > Knee，线性滚降)
```

算完**每通道乘同一个系数 `V'/V`** —— 这一步是关键：`S = 1 - min/max` 对等比缩放**不变**，
所以压亮部不会把颜色洗灰。**混白才是灰的根源**：加法提亮把彩色稀释掉，实测最彩 5% 像素的
饱和度 45.8% → 26%，整张图就"蒙了层灰"。

金克斯的实测账（`-CropX 0.00 -CropW 1.00 -CropY 0.00 -Knee 138 -HiMax 200`）：

| 指标 | 原图（同一裁剪区） | 滚降后 | 上一版（`-Knee 116 -HiMax 152`） |
| --- | --- | --- | --- |
| 均亮度 | 83.9 | **79.6** | 74.8 |
| 亮部 p95 | 214 | **177** | ≈141 |
| 亮度 > 118 的像素占比 | 17.06% | **16.11%** | 9.8% |
| 最彩 5% 像素的饱和度 | 42.2% | **44.1%** | 48.6% |

（上一版那列取自 `CropW 0.85` 的裁剪区，只作量级参考。）

**判据看「亮部 p95」**：214 → 177 —— 最亮的那 5% 被压低 37 级，白雾不再糊住字；
而 `S` 一丝不掉（等比缩放不动 `S`，实测 44.1% 甚至略高于原图 42.2%）。
`Knee` 抬得越高亮部回来越多（116 → 138），代价是均亮度降得稍多（83.9 → 79.6），
换来的是「高亮恢复」；`HiMax` 决定压到哪一档（152 → 200，越高压得越轻）。
**想让亮部几乎原样**就把 `Knee` 往 200 抬、`HiMax` 留 255 附近 —— 代价是文字可读性，按需取舍。

烘图三步（都由 `tools\rebake-backdrop.ps1` 一次跑完）：

1. **裁**：`-CropX / -CropW / -CropY` 挑人物、躲开成片亮块，比例对齐编辑区 0.917。
   ⚠️ 换高清源（5897x8719）。别拿 2000x2300 的版本凑合 —— 缩到编辑区只剩 3 倍余量，
   锐化后更容易发糊
2. **缩 + 色调**：降到 2400x2617，再按上面的曲线在 V 空间等比缩放。`-Lift` 提暗部、
   `-Knee`+`-HiMax` 压亮部，**默认全关（`Lift 0` / `Knee 255`）= 原图直出**
3. **unsharp mask（半径 4、强度 0.9）**：要在**成品尺寸**上锐化。半径按
   `源图宽 ÷ 显示宽` 放大（2400 宽的图缩到 665 宽的编辑区，半径 4 落到屏上约 1.1px），
   半径按 1px 做等于白做

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\rebake-backdrop.ps1 `
    -Src "D:\...\金克斯竖版.png" -Dst "D:\...\金克斯主题.png" `
    -CropX 0.00 -CropW 1.00 -CropY 0.00 -OutRatio 0.917 -Knee 138 -HiMax 200
```

> **`-CropW` 决定人物多大**：它是「取原图多宽的一块」，**越小 = 裁得越窄 = 人物被放得越大**。
> 同一张金克斯：`0.72` 是 1.39× 大特写（脸顶到框边）、`0.85` 是 1.18× 近景、
> `1.00` 才是**原图大小**（完整半身）。想「人物小一点」就**把 `CropW` 往 1.0 抬** ——
> 这是唯一的杠杆（上限 1.0，再大要同时调 `-CropY` 才不越界）；`cover` 在运行时
> 只会按编辑区比例再裁一刀，**不可能把人物变小**。

**验一遍**：量成品图的「>118 占比」（应明显低于原图）和**均亮度**（应与原图只差零点几）
—— 均亮度差得多，说明你压过头了，图已经不是原图。

> **反过来，图偏亮也别急着提亮去配深字。** 深字要背景 ≥ 128，暗图（均亮 30）得整体抬亮
> 4 倍，抬完必成灰白、氛围全丢 —— **那正是上一版金克斯翻车的那条路**。真要走
> 「亮图 + 深字」，图得**本来就是亮的**（均亮 ≥ 130）：`text` 取**图的色相**的深色（冷调图
> 走蓝黑 `#12172B`，比纯黑贴图）、`dim` 用同族中间调、`win` 取图均色推到浅色档。

配字色时**标题栏会自动跟着翻**：`win` 亮度 < 128 就开 immersive dark mode（深底白字），
≥ 128 就关掉（浅底黑字）—— 不用手工处理。Win11（build 22000+）上还会更进一步，用
`DWMWA_CAPTION_COLOR / TEXT_COLOR / BORDER_COLOR`(35/36/34) 把标题栏**整块染成主题色**
（底色 `win`、标题文字 `text`、外框 `win`），所以标题栏和窗框是一块布，不会跳出主题。
⚠ Win10 没有这三个属性，`DllCall` 静默失败、退回系统配色 —— 代码里不必写版本判断。

**配色从图里长出来。** 走哪一档由图定，色相也由图定：

- `text`（正文）：亮字走近白，但**带上图的色相** —— 冷调图用 `#EAF2FF`（偏蓝的白）而非纯白
- `dim`（次级文字）：同族的浅中间调 `#93AACB`
- `win`（窗框）：图的暗部档 —— 均色 × 0.55 再**偏图的色相一档**（金克斯走 `#0B1624`，蓝压过红）
- `edBg`（编辑区底色 / 搜索条）：与 `win` 同值；图是 cover 铺满的，它只在图片缺失时露出来

四个色压在同一色族里，窗框和图片才是一体的，不会像贴了张相框。

#### 六个必须守住的点

| 点 | 为什么 |
| --- | --- |
| **`bg` 与 `bgAlpha` 必须成对写** | `BackdropFeature._Sync()` 见主题带 `bg` 就会读 `t.bgAlpha`；只写 `bg` 会抛「属性不存在」 |
| **新主题追加到数组末尾** | `ThemeIndex` 存的是**数组下标**，插在中间会把老用户当前的主题顶掉 |
| **删主题必须迁移下标** | 删掉中间一套，**其后所有元素的下标全往前挪** —— 老用户的 `ThemeIndex` 于是指向另一套主题，指向末尾的还会**越界**（本机实测老配置是 `8`，新表只剩 5 套）。`ThemeService._MigrateIndex` 按下表映射，并用 `[Appearance] ThemeSchema` 打标记、**只跑一次**（同一个数字在新旧语义下含义不同 —— 新表 4 = 星空、旧表 4 = 薄荷绿，跑两遍会把用户刚选的主题又改掉）；且必须**把新下标写回配置**：`Apply` 在 `_loading` 期间不落盘，不写回的话下次启动又拿旧值去走越界兜底 |
| **`edBg` 兼作遮罩色 / 留边色，必须和图的明暗同档** | `BackdropService.SetMask` 拿 `edBg` 当遮罩色、`_Compose` 拿它铺 `contain` 留边。两套图主题都走暗色，`edBg` 也在暗档；图暗却配亮 `edBg`，整张图会发灰、留边像贴了张纸条 |
| **`bgAlpha = 0` 时字色要配图，别配习惯** | 图不压不抬时文字直接压在图上：暗图配 `text` 近白（`#F5F9FF` / `#EAF2FF`）且**带图的色相**、`dim` 不低于 `#93AACB`；图真亮（均亮 ≥ 130）才走深色字（取自图色相的 `#12172B`） |
| **竖版 / 人物图别写 `bgFit: "contain"`，改成烘焙时裁好** | contain 会把人物缩进中间、两侧留一大条底色。用 `rebake-backdrop.ps1` 的 `-CropX/-CropW/-CropY` 裁成编辑区比例（0.917）再铺 cover。见上面第 3 步 |
| **换图 / 调浓淡都改主题自己** | 图与浓淡（`bg` / `bgAlpha`）只写在 `Themes` 条目上，没有全局开关 —— 多套图主题才能各调各的（早先那对 `[Appearance] BackdropImage` / `BackdropOpacity` 已删） |

> **数组元素之间的逗号别漏**。给 `Themes` 追加新条目时，前一条结尾补上 `},` ——
> 漏了逗号不是「少一个元素」那么温柔，AHK 会报 `(946) : ==> Unexpected "{"`
> 并弹一个标题为脚本名（`SevenWork.ahk`）的错误框，窗口再也出不来。

标题栏**自动取主题色**，不必手工处理：`ThemeService._SetDarkTitleBar` 先按 `win` 的加权亮度
是否小于 128 决定 immersive dark mode，再用 Win11 的 `DWMWA_CAPTION_COLOR / TEXT_COLOR /
BORDER_COLOR`(35/36/34) 把标题栏底色 / 标题文字 / 外框分别染成 `win` / `text` / `win`。
（Win10 上后三个属性不存在 → `DllCall` 静默失败，退回系统配色。）

#### 图片本身怎么选

- **比例**：编辑区近方形（**实测 443x483 ≈ 0.917**，随窗口变化），脚本会提示裁切方向。
  16:10 横图做 cover 缩放要裁掉左右两边，主体别贴边；**竖图 / 人物图先用
  `-CropX/-CropW/-CropY` 裁到 0.917**（见上面第 3 步），否则 cover 会把人物上下裁掉。
- **大小**：不低于 `1400 x 1400`。缩图走**逐级对折 + HALFTONE**，大图缩下来不会发毛；
  但源图比目标还小就是放大，一样糊。
- **格式**：`.png` / `.jpg` / `.bmp` 均可（GDI+ 解码）。
- **内容**：大片的**纯白**最要命 —— 亮字压上去会糊，要么裁出框外、要么用 `-Knee` 滚降。
  大片纯黑反倒没事（它就是"暗图"的极端）。

#### 想调图的浓淡

`bgAlpha`（**每套主题各一个**）是**遮罩不透明度**，
遮罩色取该主题的 `edBg` —— 两套图主题的 `edBg` 都在暗档，所以加遮罩 = **压暗**：

- **暗色 `edBg`**（星空 `#0D0F14` / 金克斯 `#0B1624`）：加遮罩 = **压暗**，值越大图越暗、
  浅色文字越清楚
- ⚠️ 遮罩是**按色混合**、不是等比缩放 —— 它会减饱和。想调暗**优先改烘焙的 `-Knee`**
  （V 空间等比缩放，不减饱和），遮罩只当临时手段

```ahk
; 调这一套主题自带的浓淡
, bgAlpha: 20
```

```ahk
; 再添一套图主题的完整示例（暗图 + 亮字，裁剪与滚降都烘进图片，见上面第 3、4 步）
{name: "雪原", win: "0A1420", edBg: "0A1420", text: "EAF2FF", dim: "93AACB"
    , bg: "D:\Pictures\snow-baked.png"
    , bgAlpha: 0}
```

> `tools\pick-theme-colors.ps1` 只出**暗图**那一套（`win` = 均色 × 0.55 + 近白字）。
> 图真亮（均亮 ≥ 130）才需要反着配「浅窗框 + 取自图色相的深字」，见上面第 4 步末尾。

### 添加呼出外部窗口的功能（窗口自动适配）

`Alt+C` 呼出终端时，笔记窗口会自动退场、让出上半屏、与终端上下拼成一列 —— 这**不是为终端写死的**。
凡是「呼出一个外部窗口」的功能（资源管理器、Obsidian、浏览器、另一个编辑器…），都走同一份
**伴生窗口适配契约**（peer docking）：发布方只管广播三个生命周期事件，
`WindowFeature` 负责笔记窗口的让位 / 记忆 / 失败兜底；真正搬窗口由平台协调器
广播的 `SevenNote.Move` / `Launcher.Move` 执行，各模块只搬自己的窗口。

#### 机制：三个生命周期事件 + 两个 Move 事件

```
发布方（你的 Feature）                    订阅方（WindowFeature）
  ── Launcher.Preparing ───────────────▶  笔记窗口退场（只在显示着时才收；仅首次）
  ── 启动外部程序 / 轮询等它露面 ──────▶
  ── Launcher.Opened {hwnd,x,y,w,h} ───▶  相撞才摆位、否则原地还回来（仅首次）
  ── Launcher.Failed ──────────────────▶  把刚才退场的笔记窗口还回来

平台 PeerCoordinator（只算几何）          执行方
  ── SevenNote.Move {hwnd,x,y,w,h} ────▶  WindowFeature._OnNoteMove()
  ── Launcher.Move  {hwnd,x,y,w,h} ────▶  LauncherModule._OnMove()
```

| 事件 | 何时发 | 带什么 | 反应 |
| --- | --- | --- | --- |
| `Launcher.Preparing` | 确定要启动了，**在外部窗口露面之前** | 无 | `_CollapseForLauncher()` 收起自己 —— **仅首次**，已适配过就什么都不做 |
| `Launcher.Opened` | 外部窗口已落位 | `{hwnd, x, y, w, h}` —— **真实**窗口矩形 | `_OnLauncherOpened()` → `_AdaptToPeer()`：与笔记原来待的地方**相撞才**摆位，否则原样还回来 —— 随后**冻结**，此后不再联动 |
| `Launcher.Failed` | 最终没起来 | 无 | `_RestoreAfterFailedLauncher()` 把自己还回来 |
| `SevenNote.Move` | 平台算出堆叠落点 | 物理外框 `{hwnd, x, y, w, h}` | `WindowFeature._OnNoteMove()` 搬笔记窗口 |
| `Launcher.Move` | 平台算出伙伴下移 | 物理外框 `{hwnd, x, y, w, h}` | `LauncherModule._OnMove()` 搬终端 / 浏览器窗口 |

> **Phase 5b**：旧的 `Peer.*` 桥接已移除。生命周期归 `Launcher.*`，执行路径归两个
> Move 事件；`PeerCoordinator` 只算几何，不跨模块 `WinMove`。

> **为什么"先收再摆"**：把「搬窗口」和「露面」拆成两件事。`Show()` 本来就支持**隐藏态下算好位置、
> 最后一次性露面**（见 `_PlaceWindow`）；若窗口已显示着去搬，平移会连着控件重排一起被看见 ——
> 观感就是「飘一下」。
>
> **⚠ 只在第一次**：这一整套（退场 → 摆位 → 露面）只在笔记窗口**还没有自己的格局**时跑一次。
> 跑完就置位 `WindowFeature._docked`，此后伙伴怎么呼出隐藏，笔记都一个坐标都不改 —— 位置尺寸
> 归用户自己管。而"要不要适配"看的是**相不相撞**：笔记原来待的地方与伙伴窗口有重叠才摆，
> 不重叠就原样还回来。于是「笔记放左边、终端在右下」这种各占一角的用法，从第一次起就互不打扰。
> 退出程序重开才会重置这一次（`_docked` 与位置记忆一样是纯内存的，不落盘）。

#### 接入步骤

仓库里有两个现成的参考实现，都带完整注释，可直接对照：

| 参考 | 起什么 | 特殊在哪 |
| --- | --- | --- |
| `PowerShellFeature`（`Alt+C`） | 本机 PowerShell 终端 | 靠窗口标题认窗；**位置与宽度**由 `_PlaceLikeDeepSeek()` 对齐到与 DeepSeek / 笔记窗口同一处（只改宽，**高度仍归 Windows Terminal profile**） |
| `DeepSeekFeature`（`Alt+X`） | DeepSeek 网页（普通 Edge 窗口 + 专用 profile） | 得「自己认窗 + 自己定尺寸位置」，多出来的两处坑见下表与实例二 |

骨架长这样（`PowerShellFeature` 的简化版）：

```ahk
class MyWindowFeature {
    static Open() {
        ; ① 确定能起来之后才发 —— 早退分支不能白收一次笔记窗口
        EventBus.Emit("Launcher.Preparing")

        try {
            Run('"D:\我的程序\app.exe"')     ; ⚠ 第三个参数别传 "Hide"，见下表
        } catch {
            EventBus.Emit("Launcher.Failed")      ; ④ 起不来就还回去
            return
        }

        ; ② 等它的窗口出现（轮询要密：每档间隔都会叠进「按了没反应」的那段空白）
        deadline := A_TickCount + 15000
        while (A_TickCount < deadline) {
            if (hwnd := this._FindIt()) {
                WinShow("ahk_id " . hwnd)
                WinActivate("ahk_id " . hwnd)
                EventBus.Emit("Launcher.Opened", this._Rect(hwnd))   ; ③ 广播真实矩形
                WinActivate("ahk_id " . hwnd)                        ; 广播是同步的，还回前台
                return
            }
            Sleep(20)
        }
        EventBus.Emit("Launcher.Failed")          ; ④ 等满超时也算失败
    }
}
```

**完成。** `WindowFeature` / `LauncherModule` 的订阅都无需改 —— 生命周期事件负责让位、
堆叠、失败兜底与位置记忆，`SevenNote.Move` / `Launcher.Move` 负责真正搬窗口，
且第一次之后就不再打扰用户摆好的格局（见上文「⚠ 只在第一次」）。

#### 必须守住的点

| 点 | 为什么 |
| --- | --- |
| **`Launcher.Opened` 必须带真实矩形** | 内部要按「可见边界」换算（`_InvisibleFrame` 用 `DwmGetWindowAttribute` 量），自己拼坐标拼不准 —— 窗口矩形比肉眼看到的多一圈不可见边框（本机实测左 −9 / 右 9 / 下 9） |
| **读矩形前开 `DetectHiddenWindows`** | 刚 `WinShow` 出来的窗口 `WS_VISIBLE` 可能仍是 `0`，此时 `WinGetPos` / `WinMove` **直接抛错**（默认忽略隐藏窗口）。用完恢复原值 `A_DetectHiddenWindows` |
| **`Launcher.Failed` 一定要有** | 少了它就是「按一下热键，屏幕上什么都不剩」—— 笔记窗口被收走却没还回来。`Run` 抛错和等满超时**两条**路径都要发 |
| **别给 `Run` 传第三参数 `"Hide"`** | 隐藏启动会绕过系统把程序委派给现代宿主的机制，程序退回默认宿主（实测：Windows Terminal 变 conhost，`120x50` + `#012456` 经典蓝）。**要藏就由笔记窗口让位，别去动对方的窗口** |
| **发布方别自己去摆笔记窗口** | 几何算法在 `PeerCoordinator.PlanStack()`，状态与位置记忆（`_StackWithPeer` / `_RememberPosition` / `_preStackRect`）在 `WindowFeature`。发布方越界改坐标会和记忆打架 |
| **`EventBus.Emit` 是同步的** | 广播那一行返回时笔记窗口已经露面了，而 `Show()` 末尾会激活自己、抢走前台。以你的窗口为主角的话，广播后要 `WinActivate` 还给它 |
| **`Launcher.Opened` 的 `hwnd` 不用你清理** | 每次呼出都重记一份；伙伴被关掉后 `_StackWithPeer` 开头有 `WinExist` 存活性检查，会自行退回记忆位置 |
| **`SevenNote.Move` / `Launcher.Move` 载荷必须是物理外框** | 这两个事件直接喂给 `WinMove`；`PlanStack` 已把「可见边界」补上不可见边框换算好了，订阅方不要再自行换算 |
| **一套机制同时只服务一个伙伴** | `_peerRect` 是单值。将来若要「同时呼出 A 和 B 各占一边」，得先把它升级成列表 —— 那是重构，不是加一行 |
| **窗口认不出来？给它的进程做个记号** | 终端能靠标题认（`SevenWork PowerShell`），浏览器**不能** —— 页面标题归网页管、还会随会话变，用户的日常浏览器里也常开着同一个站点，标题一模一样。`DeepSeekFeature` 的做法是 `--user-data-dir` 指一个**专用 profile**，让 Chromium 起一条独立进程树，之后按 PID 认窗 |
| **切换判定不能只看 `WinActive`** | `WinHide` 之后 `GetForegroundWindow` **仍指着那个隐藏窗口**（本机实测 1.2s 后依然如此），于是判定成「在前台 → 再藏一次」，**再也呼不出来**。要写成 `可见 && 在前台`（两个参考实现里都有 `_IsVisible`） |
| **`WinShow` 之后补一句 `WinRestore`** | 窗口被 `WinHide` 藏起来后，宿主可能把自己标记成「最小化」—— Chromium 实测必现：再呼出时 `iconic=1`、`rect` 停在 `-32000,-32000 237x39` 的停放位。而 `WinShow` **不解除最小化**，用户看到的就是「窗口没回来」 |

#### 摆放策略在哪改

当前算法是**上下堆叠**（笔记在上、伙伴在下，同宽左对齐），分两层：

- **几何**：`PeerCoordinator.PlanStack()` 算落点，并由 `_PublishMoves()` 广播
  `SevenNote.Move` / `Launcher.Move`；
- **状态与底稿**：`WindowFeature._StackWithPeer()` 判断 `_docked` / `_preStackRect`，
  真正 `WinMove` 由两个 Move 事件的订阅方执行。

1. 伙伴已在屏幕下半区 → 它**原地不动**，笔记窗口填它上方的空间
2. 伙伴贴着屏幕顶部 → 把它**下移**到底边贴工作区底（只挪位置、尺寸一字不动），腾出上半屏
3. 两条都不成立（屏幕太矮、两窗叠不下）→ 返回 `false`，笔记窗口退回记忆位置 / 默认落点

要改成**左右并排**（比如浏览器更适合放右边），改 `PlanStack()` 的算式与 Move 事件载荷即可 ——
发布方那三个生命周期事件的代码一行不用动。
间距与边距调 `Config.DockGap` / `Config.DockMargin` 即可，不必碰算法。

**⚠ 它只在首次适配时被叫到** —— 而且只在 `_AdaptToPeer` 判定「笔记原来待的地方与伙伴相撞」时才会走。
所以想调整**要不要动、什么时候动**，改的是 `_AdaptToPeer` 里的 `_RectsOverlap` 判断与
`_FreezeDocked` 的冻结时机（`_docked` / `_CurrentRect` / `_RectsOverlap` 三个工具方法就在它旁边）。

#### 实例二：`Alt+X` 唤 DeepSeek（浏览器）

浏览器比终端多两件事要处理，`DeepSeekFeature` 是完整答案：

1. **认窗**：用 `--new-window <url>` 让 Edge 开出一扇**普通浏览器窗口**（标签栏、工具栏齐全，
   窗口内可以直接浏览网页；早先用 `--app` 求桌面应用观感，实测不划算 —— 理由见「关键坑点」表），
   再配 `--user-data-dir` 指向
   `Config.AppDataDir\_deepseek-profile`。**专用 profile** 换来两样东西 —— 不往用户自己的
   收藏夹 / 历史 / 扩展里掺东西，以及一条独立进程树（窗口可按 PID 唯一定位，不受用户日常
   浏览器里那些同标题窗口干扰）。PID 记在 `_deepseek.pid`，笔记程序重启后据此认回窗口。
   首次需要在它的 profile 里登录一次 DeepSeek，之后就记住了。

   ⚠ 这一步有两个本机实测踩到的坑（v2.1.1 修好，改这块代码前先读）：

   - **别只认「第一个」新进程**：用户自己的浏览器一直在跑，随时会冒出**没有应用窗口**的
     新渲染进程。启动后若只取第一个新 PID 去配窗口，一旦它排在真正那个前面就会**整段
     超时** —— 实测卡满 8 秒后弹「浏览器已启动，但未能找到它的窗口」，而窗口其实早开好了：
     只是没被摆位、PID 也没记下来，于是**下次再按又拉起一个新的，旧窗口永远隐藏不掉**。
     要遍历**全部**新 PID 逐个试（`_NewPidsSince`）。
   - **`_TopWindowOf` 不能要求窗口「可见」**：窗口被 `WinHide` 藏着时，那依然是我们自己
     那扇窗。要求可见的话，**重启程序后就认不回一个正被藏着的窗口**，又去拉一个新的。
     写法是优先取可见的，都没有则退回找到的第一个 —— 这就是 `relax` 参数，平时的「认回」
     调用传 `true`。

   顺便说清「认窗」的两级兜底：进程内 `_hwnd` 缓存 → `_deepseek.pid` → 都没有才重新拉起。
   所以**只在真正拉新窗口时**才走上面那段 PID 轮询。
   ⚠ 那段轮询自己还有一层兜底：Chromium 是**单实例**，`_deepseek.pid` 里的老进程若还活着
   （用户只关了窗口、没退进程 —— 普通窗口模式下这是常态），启动就**不会**产生新进程，
   只认「新 PID」会一路空等到超时弹框。故同时按老 PID 认窗（`_Launch` 里 `knownPid` 那段）。
2. **尺寸位置**：两个伙伴各有各的「谁来管」——
   - **浏览器**：尺寸由 `--window-size` 在启动时定下，位置它自己不记（每次都在 Chromium 的
     默认点），所以露面前由 `_PlaceLikeTerminal()` 摆到位。
   - **终端**：尺寸归 Windows Terminal 的 profile，位置由 WT 的 `initialPosition` 决定 ——
     而那份值可能早就过时。本机实测：任务栏改成自动隐藏后工作区变成 2560x1600，终端却仍落在
     `1803,540`（底边 1560，离工作区底 40px = 当年任务栏的高度），而 DeepSeek 按公式落在
     `1801,580`（贴底）—— 两个伙伴并排高矮不齐。`PowerShellFeature._PlaceLikeDeepSeek()`
     把终端的位置也按同一公式校正。

   两处落点公式相同：**右侧贴工作区右缘（离缘 `Config.PlaceRight`）、底边贴工作区底**，
   于是 `Alt+C` 与 `Alt+X` 两种堆叠观感一致。终端那一步**位置与宽度一起统一**（见下），
   高度仍归 Windows Terminal 的 profile —— 宽度不统一，左缘就会错开一大截。

   ⚠ **左缘对齐靠「宽度统一」，不是靠位置公式**：终端那一步原先「只挪位置、尺寸一个不动」，
   于是两个伙伴都按**右缘**贴屏幕摆、宽度却各是各的 —— 用户 WT profile 实测 **744x1020**、
   DeepSeek 目标 770：右缘齐（2545），**左缘差 26px**（终端可见 `1810..2536` vs DeepSeek
   `1784..2538`），堆叠处左边露出一条底色，看着就是「终端比别人窄一点、缺口在左边」。
   现在终端按**同一个目标宽**摆（只改宽，高度仍归 profile），三条边才全齐。

   ⚠ **目标宽 = Edge 自己会稳定停住的那个值（本机 772），别追着 `--window-size` 改**：
   `--window-size` 收的是**内容区**尺寸，Edge 套到外框上还会补一圈调整边框，而它重新套用的
   时机在窗口 show/restore **之后**，晚于摆位那一刻 —— 所以 `_PlaceLikeTerminal()` 摆完位置
   尺寸后，会在 350 / 950 / 1550 / 2150ms **各复核一次**实际外框，量到与目标不符就按目标重摆。
   ⚠ 复核必须**多轮**：Edge 只在露面后套用一次，`WinMove` 之后并不会被持续校正
   （实测稳定窗口上改过的尺寸能保持 2 秒以上不变）。
   实测（后台每 200ms 量一次的时间线）：60~80ms 窗口刚出现、1000ms 落到目标位，此后稳定。

   ⚠ **试过「把宽度请求砍小 2 去补那圈边框」，没用** —— 用临时 profile 开探针窗口实测：
   请求 506 / 512 逻辑像素（= 759 / 768 物理）**外框都落在 773**，宽度会被**吸附**；高度却准
   （680 → 1020）。所以别再跟它抢，**以它自己稳定停住的宽度为目标**：本机 SevenWork profile
   上是 **772**，写进 `_TargetW()` 默认值，终端也按 772 摆 —— `_CheckSize` 的复核才收敛
   （否则每轮都判「不符 → 重摆 → Edge 又套回去」来回弹）。

   实测终态（2026-10-16）：笔记窗口 / 终端 / DeepSeek 三者外框**同为 772 宽**、x 同为 `1773`，
   可见边界**左 `1782` / 右 `2536` / 底 `1591` 完全一致**；笔记窗口底边 `574` 到伙伴顶边
   `580` 正好 **6px**，即 `Config.DockGap`。

   ⚠ **窗口模式换代时，改了命令行不算数**：Chromium 单实例复用 —— profile 进程只要活着，
   后到的命令行就只被当成「在已有实例里开个地址」，窗口类型仍由**最先那次启动**决定。
   实测从 `--app` 升级到 `--new-window` 后，老进程（`--app` 启动的那个）一直活着，按
   `Alt+X` 照旧得到应用窗口；更麻烦的是 `Toggle()` 会先把老窗口认回来，**根本走不到
   `_Launch()`**。解法是落盘一个模式标记 `_deepseek.mode`：本版启动的实例写 `window`，
   `_FindBrowserHwnd()` 开头就校验它，不符就当「没有窗口」→ 转去 `_Launch()` →
   `_RetireLegacyInstance()` 先 `WM_CLOSE` 再强杀，清干净了再按新模式重开。
   ⚠ 老实例的识别**别只信 `_deepseek.pid`**（可能落后，也可能指向已退出的进程）—— 用 WMI
   按命令行里的 profile 路径全库筛才全（实测该 profile 下有 **9** 个同族进程：主进程 +
   crashpad / gpu / renderer…），WMI 拿不到时退回只认 pid 文件那一个。
   实测：退掉老实例后新起 `msedge.exe --new-window https://chat.deepseek.com/ ...`，一次
   到位；连按 3 次 `Alt+X` 隐藏 / 显示切换正常、PID 不变、不弹「找不到窗口」；程序重启后
   再按 `Alt+X` 认回同一扇窗口，不新开。

   > 同公式的两个实现（`_PlaceLikeTerminal` / `_PlaceLikeDeepSeek`）现在共用**一份**代码：
   > 落点算式与「可摆性闸」都在 `PeerLayoutService`（`CornerRect` / `TargetW` / `TargetH` /
   > `IsPlaceable` / `RectOf`）里，两个 Feature 各调一次 —— 不再需要「改一处同步另一处」。

可配置项（`_config.ini`，都可留空走默认）：

```ini
[Paths]
BrowserPath=C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe
DeepSeekW=772
DeepSeekH=1020
```

- `BrowserPath` 留空时按 Edge → Chrome 顺序自动探测，换 Chromium 系浏览器不用改代码。
- `DeepSeekW` / `DeepSeekH` 是**物理像素**目标尺寸，默认 `772x1020`。772 不是「照 WT profile
  推算」的，而是**实测 Edge 自己会稳定停住的外框宽**（本机 150% 缩放下请求 `513x680` 逻辑
  像素落到 772）—— 终端也按这个宽摆，三者左 / 右 / 底三条边才全齐。
  ⚠ 历史三步：写 `744` 时比终端实测窄 26px（左缘错开一大截）；改 `770` 后与终端齐，却比
  Edge 实际稳定停留的 772 窄 2px，复核每轮都判「不符」重摆。**以 Edge 实测值为准。**
  换机器 / 换缩放要重定：先 `WinGetPos` 量一次外框，再改这两个值。
- ⚠ `--window-size` 收的是**逻辑像素**，而 `WinMove` / `WinGetPos` 认**物理像素**。
  本机 150% 缩放（`A_ScreenDPI = 144`）下传 `513x680` 得到 `772x1020`，所以代码里按
  `目标物理值 × 96 ÷ A_ScreenDPI` 反算，别写死。⚠ 这只对**高度**可靠：宽度实测会被 Edge
  **吸附**到它自己的值（探针：请求 506 / 512 都落 773），宽度以 772 这个实测值为准。

#### 设计思考：为什么「呼出 + 窗口自适应」这么贵

> 这一节不是操作指南，是一份**成本账** —— 给将来想再挂一个外挂窗口的人（包括我自己）一个判断依据。
> 数据取自 2026-10-17 单体版 `SevenWork.ahk` 的实测统计（拆分后代码位置变了，成本量级不变）。

**先把两件事分开**：

| | 代码量 | 与 AHK 的关系 |
| --- | --- | --- |
| **呼出 / 收起 / 认回**（`Run` + 认窗 + `WinActivate` + 置顶） | ~30 行 | ✅ 天生贴合：AHK 就是干这个的 |
| **窗口匹配 + 笔记自适应**（上文整套契约） | **~960 行** | ⚠️ 硬凑：在脚本层手写窗口管理 |

**这 960 行的去处**：

| 模块 | 约行数 |
| --- | --- |
| `PeerLayoutService`（落点公式 + 可摆性闸） | 68 |
| `WindowFeature` 伴生段（让位 / 状态机 / 堆叠算法） | 441 |
| `PowerShellFeature`（认窗 + 摆位） | 221 |
| `DeepSeekFeature` 摆位 / 复核段 | 231 |
| **合计** | **961（代码 543 / 注释 333，注释占 35%）** |

—— 占全文 4313 行的 **22%**。两个快捷键背后，是这个项目最重的一处。

**真正的算法只有一处**：`_StackWithPeer`（约 199 行；把笔记摆到伙伴正上方、同宽、按可见边界对齐）。其余 ~760 行都不是算法：

| 类别 | 约 | 为什么省不掉 |
| --- | --- | --- |
| **认窗** | 250 行 | Chromium / Windows Terminal 都是**单实例复用**（窗口可能属于老进程）；同一 profile 可能开着几扇窗；WT 的标题要等 PowerShell 进程 ~0.7s 才设好；换窗口模式还得先退老实例 |
| **守闸** | 120 行 | AHK v2 对隐藏 / 最小化窗口的 `WinMove` / `WinGetPos` **直接抛错**，默认动作是弹模态框 → 整个程序停摆（v2.4.1 的连打卡死即此类） |
| **尺寸复核** | 80 行 | Edge 在 show/restore **之后**才重新套用 `--window-size`，且不通知任何人 → 只能 350 / 950 / 1550 / 2150ms 四轮事后核对 |
| **摆位** | 90 行 | DWM 的 9px 不可见边框、按可见边界对齐、屏幕塞不下的兜底 |
| **状态机** | 220 行 | `_docked` / `_stacked` / `_preStackRect` +「只适配一次」+ 堆叠态隐藏不覆盖记忆 |

**根因不在 AHK 的「能力」，在它的「模型」**：

1. **窗口 API 是「无状态的一次性动词」** —— `WinMove(x, y, w, h, "ahk_id " . hwnd)` 是一个动作、不返回任何对象；外部程序开的窗口在 AHK 眼里**永远只是一个 hwnd 数字**（只有自己 `Gui()` 建的窗口才有对象）。所以「记住它是我的伙伴 / 它现在在哪 / 它变了我得知道」三件事全靠手搭：持久句柄 + 观察者 + 状态机。
2. **没有窗口事件，只能用定时器轮询** —— 实测 `SetWinEventHook` / `RegisterShellHookWindow` / `WM_WINDOWPOSCHANGED` / `OnMessage` **0 处**，`SetTimer` **8 处**。Windows 本身**是**会通知「某窗口被移动 / 缩放 / 销毁」的（`SetWinEventHook` 的 `EVENT_OBJECT_LOCATIONCHANGE` 等），但接它要 `DllCall` 处理 Win32 回调（回调里不能做重活、要防重入、生命周期难管）—— **成本 ≥ 轮询**，于是自然滑向「多量几次」：`_WatchSize` 四轮猜时机、`_docked` 自己记状态。

> **一句话**：AHK 是很好的**遥控器**，这里却让它兼任了**舞台监督** —— 遥控器按一下就够；舞台监督得记住每个演员此刻站在哪、什么时候自己挪了位置、谁先上台谁后上台。上文「只适配一次」的取舍正长在这块土壤上：没有事件通知、又只认第一次，第二个上台的伙伴就没人看了。

**所以本质上，这一块写的是一个「只服务三个窗口的专用平铺窗口管理器」**。FancyZones / Komorebi / GlazeWM 做的是同一件事（C++ / Rust，独立产品，几千行起），这里砍到 543 行、只做「一列堆叠」。定位清楚以后成本就合理了：**贵不是因为写错了，而是「让三个窗口看起来像一个应用」本来就是窗口管理器的活。**

**三条路（按「贴合 AHK 哲学」排序）**：

| 路 | 形态 | 代码量 | 代价 |
| --- | --- | --- | --- |
| **约定式**（最贴 AHK） | 笔记与伙伴各占一个**固定矩形**，`WinMove` 到常量、不记状态 | ~100–150 行 | 失去「笔记随便摆都能拼上」 |
| **现状**（通用自适应） | 认窗 + 追变化 + 按冲突算位置 | 543 行 | 已在付；并需容忍 `_docked` 那类状态机取舍 |
| **交给现成窗管器** | 装 FancyZones / Komorebi，三窗固定到 zone，本程序只管呼出 | ~30 行 | 要装额外软件；「呼出即就位」要另配；笔记窗口（AHK Gui）也得纳入 zone |

**能复用到什么程度**：

| 层 | 复用度 | 说明 |
| --- | --- | --- |
| **契约层** | **100%，零改动** | 三个生命周期事件 + 两个 Move 事件；让位 / 记忆 / 兜底全在 `WindowFeature`，新伙伴照上文骨架抄 |
| **机制层** | 复用 | `PeerLayoutService` 的落点公式与可摆性闸、`_CheckSize` 多轮复核（**只在「每次新建窗口」的伙伴上需要**） |
| **伙伴个性层** | **不能复用，必须逐个实测** | 认窗方式、尺寸谁管、会不会吸附、几何记在哪 —— 每换一个伙伴就是一次实验 |

**边际成本判据**：接新伙伴 ≈ 「实测一次脾气」+ 30~80 行适配，不是重写 300 行。
**但**：`_peerRect`（`WindowFeature` 1834 行）是**单值**、`_docked`（1851 行）一旦置位就冻结，所以「**一次只呼出一个伙伴**」的用法现在就能接第 3、4 个；要「三窗同屏」则必须先重构（`_peerRect` → 伙伴集合、`_StackWithPeer` → 能排三格的布局器、`_docked` → 按伙伴身份记忆）。**一句话：加伙伴是「填参数」，加布局是「改引擎」。**

**已经用上的「降维打击」：把不确定性移出运行期**

两个伙伴各有各的脾气（浏览器不记位置、Edge 吸附宽度、WT 的 `initialPosition` 可能过时），摆位代码只是在**事后纠正**它们。换个思路 —— **把配置提前对齐，让纠正无事可做**：

```
Windows Terminal 的 settings.json
%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json

    "initialPosition": "1814,540",   ← 改成 "1773,580"
    "initialCols": 48,               ← 改成 50
    "initialRows": 33,               ← 不动：33 行 = 1020 物理 = TargetH
```

- 三个数字都是**物理像素**（2026-10-17 实读；现值 `1814,540` 与终端落点逐字一致，底边 `540+1020=1560` 正是「任务栏还显示」时代的工作区底 `1600−40`）。⚠ 上文别处写的 `1803` 是更早的记录，以这次实读的 `1814` 为准。
- `1773 / 580` = `CornerRect(772,1020)` 的结果；`50 列`由「48 列 → 744 物理」与「每列 15 物理」（WT 默认 Cascadia Mono 12pt，字格 10×20 逻辑 = 15×30 物理 @150%）反算：`(772 − 24) ÷ 15 = 49.87 → 50`（外框 ≈774，与 Edge 自己那 2px 取整误差同级）。
- ⚠ 改完**新开**终端才生效；任务栏改回「一直显示」或换缩放后要重算。

效果：终端从「先按 profile 露一脸（左缘差 28px）→ 约 1 秒后归位」变成**诞生即在位**，`_PlaceLikeDeepSeek` 退化为「移到相同坐标」= 零可见移动。**这是本仓库第一个「用配置换掉算法」的例子。**

**一条方法论（顺手记下，比上面所有数字都值钱）**

**「这个判断每次运行都会得到同一个答案吗？」** 是 → 挪出运行期；否 → 留运行期但**必须有兜底**。

| 形态 | 例 |
| --- | --- |
| **烘焙进资源** | 图片的裁剪与色调烘进 PNG、`bgAlpha 0` → 运行期只铺图，零判断 |
| **固化进配置** | `Config.PlaceRight` / `DockGap`、`Themes` 静态数组、WT profile 的 `initialPosition` |
| **改成手动** | v2.4 砍掉「自动补时间戳」（删 `FindLastTimestamp` / `Config.TimestampInterval`）→ `Ctrl+T` 手动 |

反向判据：答案取决于**人的审美或机器环境**（`-CropW` 主体大小、配色、屏幕缩放）→ 只能由人在准备期定，**别让运行期去猜** —— 「为配深字把暗图整体提亮」那次翻车，本质就是把准备期的判断塞给了运行期思维。

**后续可做（todolist，都不急、按需触发）**

| # | 事项 | 成本 | 触发条件 |
| --- | --- | --- | --- |
| 1 | 验证 Obsidian 是否记住窗口几何（`WinMove` → 关 → 重开 → `WinGetPos` 比对） | 5 分钟、零代码 | 下次开 Obsidian |
| 2 | 接 Obsidian 窗口：发三事件 + `obsidian://` 认窗 + `Alt+O`（常驻单实例、**没有漂移问题**，估算 ~30 行） | ~30 行 | 想要 |
| 3 | 修 `_docked` 顺序敏感（第二个伙伴不触发重排）+ `_CheckSize` 重摆后补 `_BroadcastRect` | ~30 行 | 想要两个伙伴都自动重排 |
| 4 | `_BroadcastRect` / `_CheckSize` 在两处 Feature 各有一份（2487 / 3026），照 v2.4.3 先例上收到 Service | ~0（纯搬运） | 接第 3 个伙伴之前 |
| 5 | 三窗同屏：`_peerRect` → 伙伴集合 + 通用布局器 + `_docked` 按伙伴记忆 | 150~250 行 | **仅当**要同屏三窗 |
| 6 | 主题流水线补 `-Report`：自动验收（亮部 p95 / 饱和 p95 / 12×12 网格 p90）并推荐 `-Knee`/`-HiMax`，输出**带逗号可粘贴**的 `Themes` 条目 | ~1 小时 | 下一张主题图之前 |

> 提醒：`tools\pick-theme-colors.ps1` 与 `tools\rebake-backdrop.ps1` 是**独立 CLI**，脱离本程序也能单跑 —— 主题这条线的可复用性来自「重活全部外包成外部工具、AHK 只编排」，与窗口那条线（能力长在 `WindowFeature` 里、只能靠契约复用）是两种形态。**想让某个能力被复用，先把它隔成一个可单跑的工具。**

### 关键坑点（踩过的坑）

> AHK v2 **语言级**的坑，权威表在 [`.clinerules/03-ahk-v2.md`](.clinerules/03-ahk-v2.md) ——
> 那里更全（多了 `Gui` 不能做变量名、`<=` 遇空串抛错、`WinMove` 与 `Gui.Move` 的单位差、
> `Show("Hide")` 后 `WinGetPos` 读不到窗口、最小化窗口 `IsWindowVisible` 仍是 1 等），
> 此处只留与**本应用行为**直接相关、且上文没讲到的几条。

| 坑 | 说明 |
| --- | --- |
| **`--app` 应用窗口不值得用，改开普通窗口** | 早先用 `--app=<url>` 让 Edge 开「应用窗口」图的是桌面应用观感，实测两头不占：Edge 155 起 app 窗口**照样自带地址栏**（UIA 查到 `view_1017`「地址和搜索栏」，换全新 `--user-data-dir` 亦然，是产品行为），却**没有标签栏** —— 既不像应用，也不算好用的浏览器。改用 `--new-window <url>` 开**普通窗口**：标签栏与完整工具栏都在，窗口内能直接浏览网页（实测窗口标题带「和另外 1 个页面」= 多标签、以及「Microsoft Edge」后缀，app 窗口两者皆无）。认窗逻辑一行不用改（普通窗口 class 同为 `Chrome_WidgetWin_1`，仍按专用 profile 的 PID 认）。⚠ 外框尺寸别指望 `--window-size`：实测宽度请求会被 Edge **吸附**到它自己的值（探针：请求 506 / 512 逻辑都落 773），高度却准（680 → 1020）；本机 SevenWork profile 上稳定在 **772**，目标宽就以这个实测值为准 —— 见上文「目标宽」一节 |
| **换了窗口模式必须退掉老实例** | Chromium 单实例复用会让「最先那次启动」的窗口类型沿用到该进程结束 —— 老实例还活着，改了命令行也白改（实测从 `--app` 升级后按 `Alt+X` 仍开应用窗口）。更隐蔽的是 `Toggle()` 会**先把老窗口认回来**，于是根本走不到 `_Launch()`。故落盘模式标记 `_deepseek.mode` 做升级清理：`_FindBrowserHwnd()` 开头就校验它，不符即当「没有窗口」，再由 `_RetireLegacyInstance()` 先 `WM_CLOSE` 后强杀。⚠ 老实例的识别别只信 `_deepseek.pid`（可能落后或指向已退出进程），用 WMI 按命令行里的 profile 路径筛才全（实测该 profile 下有 9 个同族进程：主进程 + crashpad / gpu / renderer…） |
| **异步定时器会去操作一个已经藏起来的窗口** | AHK v2 的 `WinMove` / `WinGetPos` / `WinActivate` **默认忽略隐藏窗口**，对 `WinHide` 过的窗口直接抛 `Target window not found` —— 表现是弹**模态框**、整个脚本卡死（之后 `Alt+X` / `Alt+C` 全无反应，那框还留在屏幕上）。实测路径很具体：`Alt+X` 呼出 `_PlaceLikeTerminal()` 会排 350 / 950 / 1550 / 2150ms 四轮尺寸复核（`_CheckSize`），用户在 350ms 内再按一次 `Alt+X` 把窗口藏了 → 定时器照跑 → `_CheckSize` 读到尺寸不符 → `_PlaceTarget` → **`WinMove` 对隐藏窗口抛错**。修法两条：① `_CheckSize` 里加 `IsWindowVisible` 检查，**不可见就直接返回、且不再排下一轮**（用户收起了就不该再管它）；② `_PlaceTarget` / `_PlaceLikeDeepSeek` 这类「摆位」函数开头统一加闸：`DetectHiddenWindows(false)` + `WinExist` + `!IsIconic`，不满足即 `return`。⚠ 同文件的 `_CheckSize` / `_BroadcastRect` 本来就写了 `DetectHiddenWindows` + `try/finally` 守卫，**只有摆位这条路漏了** —— 凡是「异步回调里碰窗口」的地方都要过同一道闸。实测 `Alt+X`×3 @200ms + `Alt+C`×2 @200ms 暴力连打，模态框 **0** 个 |
| **未捕获异常默认弹模态框，把程序卡死** | AHK v2 对未处理异常的默认动作是 `MsgBox` + 停摆（热键全无反应、框还留在屏幕上）。而 `SetTimer` 回调里的代码**没有外层 try** —— 任一处漏 try，都能让整个程序失去响应（v2.4.1 的 `Alt+C` / `Alt+X` 连打卡死就是这一类）。v2.4.2 起注册了 `OnError`（写 `_error.log` 后继续跑）兜住事故，`#Warn VarUnset` 也从 MsgBox 改成 `OutputDebug`。⚠ **事件总线是另一条路**：v2.4.5 之前 `EventBus.Emit` 对订阅者只有裸 `try fn(data)`、没有 `catch`，异常被**静默吞掉**（不到 `OnError`、不进日志 —— 比崩溃更难查）；现在逐订阅者 `try`/`catch` 并汇聚写日志，见变更日志 v2.4.5。⚠ **但兜底只保证「程序不倒」，不保证「逻辑做对了」** —— 异步回调里碰窗口 / 控件前，仍须自己过一遍「还在不在」的闸 |

---

## 📦 分发给他人

### 打包步骤

1. **准备 pandoc**：下载 `pandoc-x.x.x-windows-x86_64.zip`，解压得到 `pandoc.exe`（约 223MB）
2. **改源码**：`FileInstall` 那行的源路径改成本机 pandoc 实际路径（**必须一行**）
   - 源码里写死的是作者机器的路径（`C:\Users\Seven\AppData\Local\Pandoc\pandoc.exe`）
   - ⚠ **只想运行源码、不编译的话不必改** —— `FileInstall` 只在编译期被 Ahk2Exe 读取，
     源码运行完全不经过它（改从 `%AppData%\SevenWork\pandoc.exe` 或系统 PATH 里找 pandoc）
   - ⚠ 不改就编译会直接失败：Ahk2Exe 找不到源文件
3. **编译**：
   - 右键根目录的 `SevenWork.ahk` → Compile Script
   - **Base File 必须选 `Unicode 64-bit`**（不要选 32 位 / ARM64）
   - 编译时**看输出有没有 `Embedding: ...pandoc.exe`**
4. **验证**：编译后的 EXE 应该 **250MB 左右**；右键属性 → 详细信息 → 体系结构 = **x64**
5. **自己先测**：删 `%AppData%\SevenWork\pandoc.exe` → 双击新 EXE → 看释放出的是 223MB → 保存图片进 `_assets/`
6. **压缩成 ZIP 分发**：用**网盘**传输，**别用微信/QQ 直发 exe**（会重编码损坏）

### 对方使用

1. 解压 ZIP 到任意目录
2. **关闭杀毒软件**（临时）
3. 双击 `SevenWork.exe`
4. 首次运行弹框 → 选笔记目录
5. `Alt+Z` 开始使用

### 注意事项

| 事项 | 说明 |
| --- | --- |
| 不要放 `C:\Program Files\` | 需要管理员权限 |
| 传输方式 | 网盘 / ZIP，不要微信直发 |
| 杀毒软件 | 需临时关闭或加白名单 |
| 首次运行慢 | 释放 pandoc，第二次起正常 |

---

## 📋 版本历史

| 版本 | 日期 | 变化 |
| --- | --- | --- |
| **v2.5** | 2026-10-20 | **模块流水线修通：加模块从「改三处」降到「改两处」**。原先加一个模块要在组合根手写三步（三个 `XxxModule.Init()`）+ 两处 `Start()`，而且那三个 `Init()` **一个 `try` 都没有** —— 任一模块初始化抛错，会静默带走它后面的模块**以及** `HotkeyRouter.RegisterAll()` 整段热键注册，表现成「按什么都没反应」而 `_error.log` 干干净净。现在：① `ModuleRegistry.InitAll()` 遍历登记表逐个 `try`，失败记 `_failed` + 写 `_error.log`（模块 id / 名称 / 文件行号），**其余模块照常启动**；② 新增 `StartAll()`，只在热键就位后跑「对外可见」动作（加载笔记 / 恢复配置 / CapsLock 映射）——`Init` 与 `Start` 的分工是**真实约束**而非过度设计：`Start` 若早于热键注册，窗口先露面而 `Alt+Z` 还没就位，按下去就是「没反应」；③ `HotkeyRouter.RegisterAll()` 跳过 `_failed` 里的模块（坏模块的热键按了只会复现同一个错）。组合根 11 行手写调用缩成 3 行遍历，加模块只需 `#Include` + `Register` 相邻两行。**探针验收**（塞两个假模块：`ProbeBad` 故意抛错 + `ProbeGood` 正常）：`failedCount=1`、`ProbeGood.IsFailed=0`、`ProbeGood._started=1`、`date=[2026-10-20]`（笔记真的加载了）、`Hotkey("!+q")` 抛 `Nonexistent hotkey`（坏模块热键未注册）、`Hotkey("!+w")` 与真实 `Hotkey("!z")` 返回同类（好模块热键已注册）、stderr 为空、进程正常退出 |
| **v2.4** | 2026-10-16 | 两项精简：①**时间戳一律手动** —— 删掉「启动时无戳就自动补一个」与「切日期时距上一戳 ≥60 分钟再补一个」两条自动路径，连带 `EditorService` 的 `FindLastTimestamp` / `FindLastTimestampInText` / `DiffMinutes`、`Config.TimestampInterval`、以及为自动模式兜底的「保存前剥掉空戳」`StripIfEmpty` 一并删除；`Ctrl+T` 手动路径不变。实测切到一个**空的新日期**，编辑区里只有日期头、没有 `🕐 HH:mm`（旧版此处必有一个）。②**主题精简 8 套 → 5 套**：删掉天空蓝 / 薄荷绿 / 高雅灰，留下纯米黄 / 护眼绿 / 纸白 / 星空 / 金克斯（两套浅色底 + 一套中性白 + 两套图主题）。⚠ 删主题会让**其后元素的下标整体前挪** —— 老用户的 `ThemeIndex` 会指向另一套主题、指向末尾的还会越界兜底，故新增 `ThemeService._MigrateIndex`（旧→新映射表 + `[Appearance] ThemeSchema=2` 一次性标记 + 把新下标写回配置）。实测本机老配置 `ThemeIndex=8` 启动后自动变 **5**，**主题仍是金克斯、背景图照旧**；再按 `Alt+T` 循环得 `1→2→3→4→5`，正好 5 套 |
| **v2.4.5** | 2026-10-20 | **事件总线不再吞异常**：`EventBus.Emit` 原先对每个订阅者只有一句 `try fn(data)`、没有 `catch` —— 订阅者抛出的异常被静默吃掉，既到不了 `OnError`、也不进 `_error.log`，表现成「某个副作用没发生」而日志干干净净（`Theme.Changed` 触发时若 `BackdropFeature.Refresh` 抛错，状态栏照常刷新、背景图没换，查不出任何线索）。现在：① 异常逐个捕获且**互相隔离** —— 一个订阅者抛错，同一事件后面的订阅者照常执行（不能改成裸调用让异常透出去：`Theme.Changed` 有 3 个订阅者，前一个抛了后两个就再也不跑，比静默更糟）；② 循环结束后把本轮异常汇聚成**一条**写日志（`事件名 + 订阅者第 N 个 + 消息 + 文件/行`），同一事件不重复写盘；③ Kernel 不直接引用 `LogError`（`.clinerules/02` 严禁反向依赖），改由组合根 `EventBus.SetErrorSink(LogError)` **注入**，没注入时退回 `OutputDebug`。⚠ **第一版修法是坏的**：`this._sink(msg)` 这种写法治不了 —— AHK v2 的 `obj.prop(args)` 走**方法查找**，属性里存的 `Func` 不会被调用，实测抛 `Too many parameters passed to function`，再被自己的 `try` 吞掉，等于「修了等于没修」；必须先把 sink 取到局部变量 `sink := this._sink` 再调。**只有探针抓得到**（`local-var-call-ok` vs `prop-call-threw`）。验收：故意抛错的订阅者排第 2 位，第 3 位仍执行、`_error.log` 出现 `事件订阅者异常：Probe.Test / 订阅者第 2 个：probe deliberate failure / 文件 … 行`、stderr 为空、进程正常退出 |
| **v2.4.4** | 2026-10-20 | 修好「删掉一大片空行后画面不跟手」的**体感**问题（v2.4.3 那套机制没改，只调触发频率 + 补一道守卫）：① **巡检 500ms → 150ms** —— 探针实测发现滑条一直是**实时**的（末 120 字删掉后 `nMax` 5082→4746、`nPos` 4363→4027 当场变对），真正滞后的是画面：`EM_GETSCROLLPOS` 的 y 停在 4368、**差 341px**，闲置 500ms 也不自愈，所以旧版要等半秒才「啪」地跳一次。改成 150ms 后真机实测 **27ms 仍脱节（`firstVis=32`）、180ms 已修（`firstVis=12`）**。② **补 `SIF_TRACKPOS` 拖动守卫** —— `GetScrollInfo` 一直请求这个字段却从没读过；现在 `nTrackPos ≠ nPos` 即判定「正在拖滑块」直接返回，把「拖不动」的防线从「事后发现脱节」提前到「事前识别拖动」。③ 顺带否掉几个看似可行的轻量替代：`EM_GETLINECOUNT` / `EM_GETFIRSTVISIBLELINE` / 单独 `WM_VSCROLL(SB_ENDSCROLL)` 实测**全部无效**（drift 341 原地不动），只有 `EM_SETSCROLLPOS` 能归零；成本实测 200 次强制重排 484ms（2.4ms/次）、1000 次 `GetScrollInfo` 0ms —— 巡检频率可以放心提高。**与背景图 / `WS_EX_COMPOSITED` 无关** |
| **v2.4.3** | 2026-10-17 | 一轮**去重与仓库卫生**，不改功能语义：① **两处重复的布局算法收拢成一份** —— `Alt+C` 终端与 `Alt+X` DeepSeek 都要摆到右下角同一列（离工作区右缘 `Config.PlaceRight`、底边贴工作区底、宽取 `[Paths] DeepSeekW`），原先因为「Feature 之间不许互相调用」而在 `PowerShellFeature._PlaceLikeDeepSeek` / `DeepSeekFeature._PlaceTarget` 里**各留一份**（注释写着「两处要同步改」），连同「隐藏 / 最小化闸」（`WinExist` + `!IsIconic`）与「读外框广播 `Peer.Placed`」一起上收到新增 Service **`PeerLayoutService`**（`IsPlaceable` / `TargetW` / `TargetH` / `CornerRect` / `RectOf`）—— 两个 Feature 各调一次，改一处即可。⚠ 这是**纯搬运**，落点数值与守卫语义一字未改：实测 `CornerRect(772,1020)` = `1773,580`（与工作区算术一致），`IsPlaceable` 对「可见 / 隐藏 / 不存在」三种窗口分别 `1 / 0 / 0`，`RectOf` 隐藏窗口也能读到外框；真机 A/B 对照（旧版 vs 新版）终端与笔记窗口外框**逐项相同**（`1182,387 515x680` / `1182,7 515x382`）。② **删掉全局背景图覆盖键** —— `[Appearance] BackdropImage` / `BackdropOpacity` 是**全局覆盖**，一旦写上会盖掉**所有**带 `bg` 的主题（多套图主题并存时没法定制各自的浓淡），现予删除：图的路径与浓淡只写在主题自己的 `bg` / `bgAlpha` 上。实测五套主题轮切，图主题 `_bgPath` 指向各自图片、无图主题为空且 `bgAlpha` 走兜底 `60`。③ `StatFeature.Tick`（500ms 常驻计时器）补上窗口可见性守卫 —— 窗口收起 / 最小化时不再白读编辑区长度，写法与 `AutoSaveFeature.Tick` 对齐。④ 仓库卫生：新增 `.gitignore`（演示测试产物 `user-journey-report.html` / `results.tsv` / `trace.log` 不再入库），已跟踪的报告文件 `git rm --cached` 出库 |
| **v2.4.2** | 2026-10-16 | 一轮**健壮性与非功能性**补强，四项改动都不改功能语义：① **补全局异常兜底** —— 原先全库 `OnError` 定义 **0 处**，AHK v2 对未捕获异常默认动作是**弹模态框**，一弹脚本就停摆（热键全无反应、框还挂在屏幕上），项目在 v2 迁移期连踩三次（`JSON.Stringify` 未赋值 / `Gui` 当变量名 / 空串比较）。现在注册 `OnError(OnScriptError)`：异常写 `%AppData%\SevenWork-Dev\_error.log`（带文件 / 行 / 调用栈，超 512KB 自动轮转）后 **`return 1` 继续跑** —— 单个 Feature 出错不再拖垮整个程序；同因把 `#Warn VarUnset` 的动作从默认 MsgBox 改成 `OutputDebug`（VS Code 的 AHK++ 调试器仍看得到，但不再拦路）。② **砍掉保存链路上最贵的一步** —— `PandocService.IsAvailable()` 每次调用都要 `RunWait` 起一个 conhost + 一个 200MB 的 `pandoc --version` 进程，而它的触发点是 `Window.BeforeHide → Save`（**每次 `Alt+Z` 隐藏都跑**）加 120s 自动保存；现在探测到「可用」就永久缓存（只有探测不到才重试，用户中途装好 pandoc 不必重启）。③ **`ConfigService` 加进程内读缓存** —— `IniRead` 没有内部缓存，而 `Config.GetVault()` 在单次保存里至少被调 6 次（`FindRtf` / `DefaultRtfPath` / `FindMd` / `DefaultMdPath` / `TempDir` / `AssetsDir`），`RenameWithTag` 的双扩展名循环里还要翻倍；写入时同步缓存、`Init` 时清空（沙箱注入新路径不会读到旧值）。⚠ 代价：**运行期手改 `_config.ini` 不再被读到，改配置请重启程序**。④ **两处明细优化** —— `NoteStoreService.ListAllTags` 原先用冒泡（1000 篇笔记约 50 万次 `StrCompare`，解释器里数百 ms）换成内置 `Sort`（C 层，O(n log n)），排序键用「日期 + TAB + 6 位下标」以保住「同一天多条（`2026-09-19-a.md` / `-b.md`）不串位」与稳定性；`SetTimer` 回调统一过一遍「窗口还在不在」守卫（`StatFeature.Tick` / `AutoSaveFeature.Tick` 本就有，本轮给 `StatusBar` 的 2s 清屏、`SearchFeature` 的 300ms 回焦、`ShowStartupTip` 的 1.5s 关闭补上）—— 回调里异常同样会弹模态框，而这三处原先都是裸的 |
| **v2.4.1** | 2026-10-16 | 两处修整：① **`Alt+C` / `Alt+X` 快速切换不再弹模态框卡死** —— 根因是**异步定时器去摆一个已经藏起来的窗口**：`Alt+X` 呼出后排下的四轮尺寸复核（350/950/1550/2150ms）照跑，而 `WinMove` / `WinGetPos` 在 AHK v2 里默认忽略隐藏窗口、对 `WinHide` 过的窗口直接抛 `Target window not found`，模态框一弹整个脚本就卡住（热键全无反应、框留在屏幕上）。修法两条：`_CheckSize` 加 `IsWindowVisible` 检查（不可见即返回、**且不再排下一轮复核**）；`_PlaceTarget` / `_PlaceLikeDeepSeek` 开头补 `WinExist` + `!IsIconic` 守卫（同文件的 `_CheckSize` / `_BroadcastRect` 本就有这道闸，只有摆位这条路漏了）。实测 `Alt+X`×3 @200ms + `Alt+C`×2 @200ms 暴力连打，模态框 **0** 个。② **终端宽度与其他两个统一** —— 早先终端那一步「只挪位置、尺寸一个不动」，于是两个伙伴都按右缘摆、宽度各是各的（用户 WT profile 实测 **744** vs 目标 770）：右缘齐、**左缘差 26px**，堆叠处左边露出一条底色（终端可见 `1810..2536` / DeepSeek `1784..2538`）—— 就是「终端比别人窄一点、缺口在左边」。现在终端按**同一目标宽**摆（只改宽、高度仍归 profile）。目标宽同时从 **770 改为 772**：实测 `--window-size` 的宽度**会被 Edge 吸附**（临时 profile 探针：请求 506 / 512 逻辑都落 773；高度 680 → 1020 却准），砍请求值补边框没用 —— 以 Edge 自己稳定停住的 772 为目标，`_CheckSize` 复核才收敛（否则每轮判「不符 → 重摆 → Edge 又套回去」来回弹）。实测终态三者外框同为 **772**、x 同为 `1773`，可见边界左 **1782** / 右 **2536** / 底 **1591** 完全一致，笔记窗口底边 574 到伙伴顶边 580 正好 6px = `DockGap` |
| **v2.3.3** | 2026-10-16 | `Alt+X` 改为**带完整浏览器功能的普通窗口**，放弃 `--app` 应用窗口：实测 app 窗口「有地址栏、无标签栏」，既不像桌面应用也不算好用的浏览器 —— 改用 `--new-window <url>` 后窗口内可直接浏览网页（实测标题带上「和另外 1 个页面」= 多标签、以及「Microsoft Edge」后缀，app 窗口两者皆无）。顺带补三处健壮性：① **升级时必须退掉老实例** —— 这是最隐蔽的一处：Chromium 单实例复用让「最先那次启动」的窗口类型沿用到该进程结束，实测那个 `--app` 进程一直活着（用户只关了窗口、没退进程），改了命令行也照旧开应用窗口；而且 `Toggle()` 会**先把老窗口认回来**、根本走不到 `_Launch()`。故新增落盘模式标记 `_deepseek.mode`（本版写 `window`，缺失/不符 = 老实例）+ `_FindBrowserHwnd()` 开头的模式校验 + `_RetireLegacyInstance()`（先 `WM_CLOSE` 后 `ProcessClose`）；老实例识别用 WMI 按命令行里的 profile 路径全库筛（实测 **9** 个：主进程 + crashpad / gpu / renderer…），不再只信可能落后的 `_deepseek.pid`，WMI 拿不到时退回那一支。② **Chromium 单实例复用进程** —— 用户只关了窗口没退进程时二次启动不产生新进程，原来只认新 PID 会空等 15 秒弹「找不到窗口」（实测二次启动后新窗口仍属老进程 14452），现按 `_deepseek.pid` 里的老 PID 兜底认窗。③ **同 profile 可能同时开着多扇窗**（实测二次启动后同 PID 下有 3 扇），`_TopWindowOf` 改为**优先取尺寸等于目标**的那扇，而非「第一个可见的」。实测终态：老实例退掉后新起 `msedge.exe --new-window https://chat.deepseek.com/ ...`，窗口 `1775,580 772x1020`（与终端左缘 / 底边严格相同，右缘差 2px 系 Edge 外框取整）；连按 3 次 `Alt+X` 隐藏 / 显示切换正常、PID 不变、不弹错误框；程序重启后再按 `Alt+X` 认回同一扇窗口、不新开。另修 `tests\user_journey_driver.ahk` 引用已删除的 `Config.WinW/WinH` 导致的演示脚本启动失败 |
| **v2.3.2** | 2026-10-16 | 三处观感修整：①**终端与 `Alt+X` 的 DeepSeek 窗口真正对齐** —— 先把 DeepSeek 的目标宽从「照 WT profile 推算」的 `744` 改成终端 `WinGetPos` **实测**的 `770x1020`（`--window-size` 收的是**内容区**、Edge 套到外框还差一截：按 770 请求落在 768，比终端窄 2px），再在摆位后于 350/950/1550/2150ms **各复核一次**实际外框并重摆（Edge 重新套用 `--window-size` 的时机在窗口 show/restore **之后**，晚于第一次复核；实测它**不是**持续校正）。三方终态一致：`1775,580 770x1020`，左缘 / 右缘 / 底边 / 宽高全同。②**编辑区滚动条跟随主题**：滚动条画在非客户区、归系统主题上色，深色主题下原来是一条刺眼的亮白竖条 → `ThemeService._SetScrollBarTheme` 把编辑区窗口主题设成 `DarkMode_Explorer` / `Explorer`，实测滚动条区域像素均亮度 **40**（编辑区 75、同档暗）、**亮像素 0 个**。③**滑动时不再频闪**：主窗口开 `WS_EX_COMPOSITED`（`+E0x02000000`）离屏双缓冲 —— 编辑区 RichEdit 自身不带双缓冲，滚动时会先擦客户区再画文字，那一帧空档就是频闪的来源 |
| **v2.3.1** | 2026-10-16 | `Alt+C` 终端的呼出位置**对齐到 DeepSeek 同一处**：WT 的 `initialPosition` 是任务栏还显示时定的 `1814,540`（底边 1560，离工作区底 40px），而 DeepSeek 按公式落 `1801,580`（贴底）—— 两个伙伴并排高矮不齐。新增 `PowerShellFeature._PlaceLikeDeepSeek()`（与 `_PlaceLikeTerminal` 同一公式：右侧贴工作区右缘 `Config.PlaceRight`、底边贴工作区底），**只挪位置、尺寸一个不动**。实测终端落到 `1801,580`，与 DeepSeek 同列。另订正「`--app` 开出无地址栏窗口」的过时描述：实测 Edge 155 起 **app 窗口自带地址栏**（UIA 查到 `view_1017`「地址和搜索栏」、无标签栏；换全新 profile 启动亦然，是产品行为）—— 副作用挺好，`Alt+X` 呼出的窗口能直接输网址当**轻量浏览器**用 |
| **v2.3** | 2026-10-16 | 修好**背景图主题下编辑区文字随窗口拉伸「时隐时无」**：`BackdropFeature.Layout` 原来每次 `WM_SIZE` 都重铺一遍 2400px 源图（HALFTONE 多级对折，几十毫秒），拖动窗口时每秒几十次会灌满绘制队列、连带作废编辑区文字 → 改为 `_ScheduleRender()`（`SetTimer -80` 抖动合并）+ `_RenderNow()`（同矩形直接跳过，真重铺过才 `RedrawWindow(ed, INVALIDATE\|ERASE)`），切换主题走 `_Apply → _RenderNow(true)` 绕过防抖。实测 1361x1084 连打 40 次 resize 共 **392ms**、resize 前后截图**逐像素一致**。「金克斯」按「高亮恢复 + 人物别太大」重烘：`-CropW 0.72 → 1.00`（人物从 1.39× 特写改回**原图大小**的完整半身）、`-Knee 116 → 138`、`-HiMax 152 → 200` —— 亮部 p95 从 ≈141 抬回 **177**（原图 214），饱和度一丝不掉（42.2% → **44.1%**），代价是均亮度 83.9 → **79.6** |
| **v2.2** | 2026-10-16 | 主题扩到 **8 套**，末尾两套为**背景图主题**，**都是「暗图 + 亮字」**（遮罩 0，裁剪与色调全烘进图片）：①「星空」星云均亮 28；②「金克斯」人物图均亮 75 —— **本来就该配亮字，根本不需要提亮**，只把压在字下的最亮 15%（脸 / 手 / 白雾）在 V 空间线性滚降（`-Knee 116 -HiMax 152`）：均亮度 75.1 → **74.9**、最彩 5% 像素饱和度 45.8% → **45.1%**，图就是原图本身，而亮度 >118 的像素从 20.5% 降到 9.1%。流程沉淀成 `tools\rebake-backdrop.ps1`：**按编辑区比例 0.917 裁**（`-CropX/-CropW/-CropY` —— 竖版人物图靠它占满整块，不再用 `bgFit: "contain"`）→ 缩到 2400 宽 → V 空间色调（`-Lift` 提暗部 / `-Knee`+`-HiMax` 压亮部，**默认全关 = 原图直出**）→ 成品尺寸 unsharp。配色**取图的色相**：金克斯窗框 / 编辑区 / 搜索条 `#0B1624`、正文 `#EAF2FF`、次级文字 `#93AACB`。⚠️ 反面教训：曾为迁就深色字把这张图整体抬到均亮 170，整图"蒙了层灰"、与原图完全不像 —— **提亮 ≠ 清晰，它是把原图洗白**；混白（加法提亮）还会把饱和度从 45.8% 砍到 26% |
| **v2.1.1** | 2026-10-16 | 修好 `Alt+X` 的「认窗」链路两处隐患：①拉新窗口时原来只认**第一个**新进程，用户自己的 Edge 恰好在跑、一有新渲染进程排在前面就整段超时（实测卡 8 秒后弹「找不到窗口」，之后的按法还会不停开新窗口、旧窗口永远隐藏不掉）→ 改为遍历**全部**新进程，命中即用；②`_TopWindowOf` 原来要求窗口「可见」，导致**重启程序后认不回一个正被藏着的窗口**（又去拉新的）→ 改为优先取可见的、都没有则退回第一个（`relax`） |
| **v2.1** | 2026-10-16 | 伴生窗口适配**只在首次跑一次**：笔记原来待的地方与伙伴窗口相撞才摆位，不撞就原样不动；适配完冻结，之后 `Alt+C` / `Alt+X` 再怎么呼出隐藏，笔记的尺寸位置都归用户自己管（`WindowFeature._docked`，不落盘，重启即重来一次） |
| v2.0 | 2026-10-16 | 新增 `Alt+X` 呼出 / 隐藏 DeepSeek 网页（专用 profile 的 Edge 应用窗口），窗口自动与笔记对齐；`Alt+C` 的窗口适配机制泛化为 `Peer.*` 通用契约，并修好「隐藏后再按呼不出来」 |
| v1.9 | 2026-09-20 | 修复 pandoc 打包 0KB 问题；`PandocService` 加文件有效性校验（>1MB） |
| v1.8 | 2026-09-20 | 状态栏日期后显示星期（`📅 2026-09-20 周日`） |
| v1.7 | 2026-09-19 | assets 统一收纳到 `_assets/日期/`；切日期光标到开头 |
| v1.6 | 2026-09-19 | 路径分离（统一自用/分发）；首次运行引导；Pandoc 双路径；代码数据分离 |
| v1.5 | 2026-09-19 | 修复启动/切日期时标签不显示；搜索框加宽；标签字号固定 |
| v1.4 | 2026-09-19 | 标签顶部持久显示；窗口最小尺寸限制 |
| v1.3 | 2026-09-19 | 修复搜索计数；修复搜索栏关闭后编辑区全选 |
| v1.2 | 2026-09-19 | 标签系统（文件名带标签）；统一搜索跳转（Ctrl+G）；返回当天（Alt+Home） |
| v1.1 | 2026-09-19 | 空笔记不落盘；先查后存；Tab 缩进不丢格式 |
| v1.0 | 2026-09-18 | 首次发布：30 项热键 / 6 套主题 / 7 种字体 |

---

## ⚠️ 已知限制

| 限制 | 说明 |
| --- | --- |
| 仅 Windows | AHK v2 只支持 Windows |
| Pandoc 软依赖 | 未装则 MD 无格式、无图片链接（笔记不丢） |
| 不支持跨日期全文搜索 | 搜索只在当前笔记内 |
| 无云同步 | 用 OneDrive / 坚果云替代 |
| 标签单字段 | 每个日期一个标签，不支持多标签 |
| 改配置要重启 | `_config.ini` 在进程内被缓存（v2.4.2 起），运行期手改不生效 |
| 搜索缓存的脏标记不完美 | 搜索条开着时点回编辑区打字，只有**字数变化**才会重算匹配（等长替换测不出来，罕见边缘） |
| **第二个伙伴不触发笔记重排** | `_docked` 只认「第一次适配」：一个伙伴已在场时，第二个伙伴呼出后笔记不会重新让位（即便相撞）。详见「设计思考 → 后续可做」第 3 条 |

---

## 📄 License

MIT License — 详见 [LICENSE](LICENSE) 文件。

---

## 🙏 致谢

- [AutoHotkey v2](https://www.autohotkey.com/) — 强大的 Windows 自动化脚本语言
- [Pandoc](https://pandoc.org/) — 通用文档转换器
- [Obsidian](https://obsidian.md/) — 本地 Markdown 笔记软件
- [RichEdit 消息参考（MSDN）](https://learn.microsoft.com/en-us/windows/win32/controls/rich-edit-controls)