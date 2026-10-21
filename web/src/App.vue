<script setup lang="ts">
import { ref, onMounted } from 'vue'
import NoteEditor from './components/NoteEditor.vue'
import GlassLab from './components/GlassLab.vue'
import PanelView from './components/PanelView.vue'
import PromptView from './components/PromptView.vue'
import { isHosted, ahkCall, applyTheme, type Theme } from './ahk'

/* ── 页面切换：现在是五个视图，模块化路由留到 S3 ─────────────────── */
// 支持 ?view=note 直达 —— 真机验证与将来从 AHK 唤起特定页面都用得上
// ?view=lab：材质样板（S0），浏览器里单独验收「琉璃」观感，不接 AHK
// ?view=panel：工作台面板（Alt+S），数据全部来自 AHK 的 PanelHostBridge
// ?view=prompts：提示词库（Alt+P），数据来自 Text 模块的 HostBridge
const _q = new URLSearchParams(location.search).get('view')
const view = ref<'self' | 'note' | 'lab' | 'panel' | 'prompts'>(
  _q === 'note'
    ? 'note'
    : _q === 'lab'
      ? 'lab'
      : _q === 'panel'
        ? 'panel'
        : _q === 'prompts'
          ? 'prompts'
          : 'self',
)

/* ── 自检页 ─────────────────────────────────────────────────────── */
const hosted = isHosted()
const pong = ref('—')
const ver = ref('—')
const themeName = ref('—')
const err = ref('')
const text = ref('')

/* ── 笔记页 ─────────────────────────────────────────────────────── */
// 演示内容：把 gfm 的能力一次点齐，构建后一眼能看出哪块没渲染
const DEMO_MD = [
  '# 笔记编辑器',
  '',
  'Milkdown 在 SevenWork 里的第一次落地。**粗体**、*斜体*、`行内代码` 全走 Markdown 原生语法。',
  '',
  '## 验证清单',
  '',
  '- [x] 直接敲 Markdown，实时格式化',
  '- [ ] 粘贴截图（Ctrl+V 贴一张图试试）',
  '- [ ] 拖一张图片进来',
  '',
  '> 图片在 WebView2 里落盘成正文件，Markdown 只留相对路径；',
  '> 浏览器预览模式退回内联 data URL，方便单独调样式。',
  '',
  '```ts',
  'const src = await storeImage(file)',
  '```',
  '',
  '| 能力 | 来源 |',
  '| --- | --- |',
  '| 表格 | GFM |',
  '| 任务列表 | GFM |',
  '| 代码块 | CommonMark |',
  '',
  '---',
  '',
  '正文到此。',
].join('\n')

const noteMd = ref(DEMO_MD)

/* ── 宿主（AHK）入口 ───────────────────────────────────────────────
   AHK 用 WebHostService.Eval('window.__swnote.setMarkdown("…")') 灌内容。
   Eval 和组件的 onMounted 谁先到不确定：编辑器没建好时先把值挂起来，
   @ready 之后补灌 —— 否则第一次载入会静默丢掉（画面还是演示内容）。 */
const editorRef = ref<any>()
let pendingMd = ''

function onEditorReady() {
  if (!pendingMd) return
  const md = pendingMd
  pendingMd = ''
  try {
    editorRef.value?.setMarkdown(md)
  } catch (e) {
    ;(window as any).__swnoteLastError = 'ready: ' + String(e)
  }
}

function setMarkdown(md: string): string {
  // ⚠ 必须有返回值：AHK 侧用 ExecuteScriptAsync 收结果，undefined 序列化成字符串
  //   "null"，Eval 就判成失败，整次灌入看起来没执行。
  // ⚠ 异常也要自己兜住并转成字符串 —— 抛出去的异常同样变成 "null"，
  //   只剩「脚本返回 null」这句，查不出到底是哪一步坏的。
  try {
    noteMd.value = md
    const r = String(editorRef.value?.setMarkdown(md))
    if (r !== 'ok') {
      pendingMd = md
      return 'pending:' + r
    }
    return 'ok'
  } catch (e) {
    return 'ERR ' + String(e)
  }
}

/* ── 编辑器内快捷键（v2.9：从 AHK 的 editor 上下文搬进来）──────────────
   这几条都要在光标处插字，前端拿 ProseMirror 的 transaction 一次就够；
   从前在 AHK 里对着 RichEdit 算偏移，既不准，还得维护两套状态。
   ⚠ Ctrl+S / Ctrl+G / Ctrl+Shift+T 不在这里 —— 那三条由 AHK 的 editor 上下文
     热键拦下（要碰文件与对话框），前端抢走反而打不通。
   ⚠ 监听用捕获阶段：ProseMirror 自己会处理 Tab 等键，冒泡阶段轮不到我们。 */
function onKeydown(e: KeyboardEvent) {
  if (view.value !== 'note') return
  const el = editorRef.value
  if (!el) return
  const k = e.key.toLowerCase()

  // Ctrl+T：追加时间戳（另起一段，前面空一行，与旧版排版一致）
  if (e.ctrlKey && !e.altKey && !e.shiftKey && k === 't') {
    e.preventDefault()
    const now = new Date()
    const hh = String(now.getHours()).padStart(2, '0')
    const mm = String(now.getMinutes()).padStart(2, '0')
    el.insertText(`\n\n🕐 ${hh}:${mm}\n`)
    return
  }
  // Ctrl+H：动态分隔线
  if (e.ctrlKey && !e.altKey && !e.shiftKey && k === 'h') {
    e.preventDefault()
    el.insertText('\n\n---\n\n')
    return
  }
  // Ctrl+Shift+H：分段标题
  if (e.ctrlKey && !e.altKey && e.shiftKey && k === 'h') {
    e.preventDefault()
    el.insertText('\n\n## 新分段\n\n')
    return
  }
  // Tab：缩进四空格（与旧 RichEdit 版一致；Markdown 里缩进就是空格）
  if (!e.ctrlKey && !e.altKey && e.key === 'Tab') {
    e.preventDefault()
    el.insertText('    ')
  }
}

onMounted(() => {
  // 宿主入口只挂一次；重新导航页面会重建，不需要额外清理
  // ⚠ 未捕获的 Promise 拒绝在 WebView2 里完全静默（不写 console、不弹窗），
  //   而编辑器的 create() 是异步的 —— 它抛了就等于「DOM 出来了但变量是 null」
  window.addEventListener('unhandledrejection', (e: any) => {
    ;(window as any).__noteStage = 'reject: ' + String(e?.reason)
  })
  window.addEventListener('keydown', onKeydown, true)
  ;(window as any).__swnote = {
    setMarkdown,
    getMarkdown: () => editorRef.value?.getMarkdown() ?? noteMd.value,
    getChars: () => noteMd.value.length,
    // 临时诊断：ref 到底绑上没有、expose 出来的是不是我们要的那几个方法
    diag: () => {
      const r: any = editorRef.value
      return JSON.stringify({
        hasRef: !!r,
        keys: r ? Object.keys(r) : [],
        setMarkdown: typeof r?.setMarkdown,
        getMarkdown: typeof r?.getMarkdown,
        noteLen: noteMd.value.length,
        pending: pendingMd.length,
        dom: !!document.querySelector('.ProseMirror'),
        stage: (window as any).__noteStage ?? '(none)',
      })
    },
  }
})

onMounted(async () => {
  if (!hosted) {
    err.value = '浏览器预览模式：未注入 hostObjects，数据为占位'
    return
  }
  try {
    pong.value = String(await ahkCall('ping'))
    ver.value = String(await ahkCall('version'))
    const raw = await ahkCall<string>('getTheme')
    if (raw) {
      const t = JSON.parse(raw) as Theme
      applyTheme(t)
      themeName.value = t.name
    }
  } catch (e) {
    err.value = String(e)
  }
})
</script>

<template>
  <!-- 材质样板独立成页：它自带全屏底（光雾 + 霜），不套 .shell 骨架 -->
  <GlassLab v-if="view === 'lab'" />
  <!-- 工作台面板同理：自己整页布局（两块玻璃板 + 底栏），不套 .shell -->
  <PanelView v-else-if="view === 'panel'" />
  <!-- 提示词库：整页列表（搜索 + 条目 + 状态行），也不套 .shell -->
  <PromptView v-else-if="view === 'prompts'" />
  <div v-else class="shell" :class="{ solo: view === 'note' }">
    <aside v-if="view !== 'note'" class="side">
      <div class="brand">
        <span class="dot" />SevenWork
      </div>
      <nav>
        <a class="nav" :class="{ on: view === 'self' }" @click="view = 'self'">底座自检</a>
        <a class="nav" :class="{ on: view === 'note' }" @click="view = 'note'">笔记</a>
        <a class="nav off">提示词</a>
        <a class="nav off">文件夹</a>
      </nav>
      <div class="foot">v0.2 · S2a 编辑器</div>
    </aside>

    <main v-if="view === 'self'" class="main">
      <header>
        <h1>前端底座</h1>
        <p class="sub">Vue 3 + Vite · 通过 https://app.local/ 加载</p>
      </header>

      <section class="cards">
        <div class="card">
          <div class="k">AHK 版本</div>
          <div class="v">{{ ver }}</div>
        </div>
        <div class="card">
          <div class="k">hostObjects 应答</div>
          <div class="v">{{ pong }}</div>
        </div>
        <div class="card">
          <div class="k">主题</div>
          <div class="v">{{ themeName }}</div>
        </div>
      </section>

      <p v-if="err" class="warn">{{ err }}</p>

      <section class="probe">
        <div class="k">输入法 / 键盘探针</div>
        <textarea
          v-model="text"
          rows="3"
          placeholder="在这里打几个中文，检查候选框位置与上屏；再按一次 Esc 看是否被吞"
        />
        <div class="hint">已输入 {{ text.length }} 字</div>
      </section>
    </main>

    <!-- 纯编辑器：**不设题头** —— 标题由笔记正文第一行（`📅 日期 速记`）承担，
         窗口标题已是 SevenNote；再挂一块「笔记 / Milkdown · …」只会把正文挤下去，
         说明文字还会在小窗口里折成两行。字数放底部状态行，对应原生版 StatusBar 的位置。 -->
    <main v-else class="main note">
      <div class="note-body">
        <!-- v-model 是单向回吐：编辑器是唯一真源，不反向覆写它 -->
        <NoteEditor ref="editorRef" v-model="noteMd" @ready="onEditorReady" />
      </div>
      <div class="note-foot">{{ noteMd.length }} 字</div>
    </main>
  </div>
</template>

<style scoped>
.shell {
  display: grid;
  grid-template-columns: 232px 1fr;
  height: 100%;
}

/* 笔记视图是「纯编辑器」：侧栏退场，整块客户区交给 Milkdown。
   ⚠ 不写这条的话 grid 仍留着 232px 空列 —— 右边全空，看着像编辑器没铺满。 */
.shell.solo {
  grid-template-columns: 1fr;
}

.side {
  background: var(--sw-bg-alt);
  border-right: 1px solid var(--sw-border);
  padding: 20px 16px;
  display: flex;
  flex-direction: column;
  gap: 18px;
}

.brand {
  display: flex;
  align-items: center;
  gap: 8px;
  font-weight: 600;
  letter-spacing: 0.02em;
}

.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--sw-accent);
}

nav {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.nav {
  padding: 7px 10px;
  border-radius: 6px;
  color: var(--sw-fg);
  cursor: default;
  font-size: 13px;
}

.nav.on {
  background: var(--sw-bg);
  font-weight: 600;
}

.foot {
  margin-top: auto;
  font-size: 12px;
  color: var(--sw-dim);
}

.main {
  padding: 24px 28px;
  overflow: auto;
}

h1 {
  margin: 0 0 4px;
  font-size: 22px;
  font-weight: 600;
}

.sub {
  margin: 0 0 22px;
  color: var(--sw-dim);
  font-size: 13px;
}

.cards {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 12px;
  margin-bottom: 20px;
}

.card {
  background: var(--sw-bg-alt);
  border: 1px solid var(--sw-border);
  border-radius: var(--sw-radius);
  padding: 12px 14px;
}

.k {
  font-size: 12px;
  color: var(--sw-dim);
  margin-bottom: 4px;
}

.v {
  font-size: 15px;
  font-weight: 600;
  word-break: break-all;
}

.warn {
  color: var(--sw-fg);
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid var(--sw-border);
  border-radius: var(--sw-radius);
  padding: 8px 12px;
  font-size: 13px;
}

.probe {
  border: 1px solid var(--sw-border);
  border-radius: var(--sw-radius);
  padding: 14px;
}

textarea {
  width: 100%;
  margin-top: 8px;
  padding: 8px 10px;
  border: 1px solid var(--sw-border);
  border-radius: 6px;
  background: var(--sw-bg);
  color: var(--sw-fg);
  font: inherit;
  resize: vertical;
}

textarea:focus {
  outline: 2px solid var(--sw-accent);
  outline-offset: -1px;
}

.hint {
  margin-top: 6px;
  font-size: 12px;
  color: var(--sw-dim);
}

/* ── 笔记页：编辑器自己滚，外层不滚 ─────────────────────────────── */
.main.note {
  padding: 0;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  min-height: 0;
}

.note-body {
  flex: 1 1 auto;
  min-height: 0;
}

/* 底部状态行：对应原生版 `StatusBar` 的位置（原来显示日期 / 星期 / 标签）。
   现在只留字数 —— 其余信息 AHK 侧没有往前端推，别在这儿假装有。 */
.note-foot {
  flex: none;
  padding: 6px 22px;
  font-size: 12px;
  color: var(--sw-dim);
  border-top: 1px solid var(--sw-border);
  background: var(--sw-bg-alt);
}

.nav {
  cursor: pointer;
}

.nav.off {
  opacity: 0.45;
  cursor: default;
}

.nav:hover:not(.off):not(.on) {
  background: var(--sw-bg-alt);
}
</style>
