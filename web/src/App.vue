<script setup lang="ts">
import { ref, onMounted } from 'vue'
import NoteEditor from './components/NoteEditor.vue'
import { isHosted, ahkCall, applyTheme, type Theme } from './ahk'

/* ── 页面切换：现在是两个视图，模块化路由留到 S3 ─────────────────── */
// 支持 ?view=note 直达 —— 真机验证与将来从 AHK 唤起特定页面都用得上
const view = ref<'self' | 'note'>(
  new URLSearchParams(location.search).get('view') === 'note' ? 'note' : 'self',
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
const saved = ref('')

function save() {
  // S2a 只是「证明编辑器能产出 markdown」，真正落盘要等 S2b 接 AHK
  localStorage.setItem('sevenwork.note.preview', noteMd.value)
  saved.value = `已暂存 ${new Date().toLocaleTimeString()}`
}

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
  <div class="shell">
    <aside class="side">
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

    <main v-else class="main note">
      <header class="note-head">
        <div>
          <h1>笔记</h1>
          <p class="sub">Milkdown · 输入即 Markdown · 图片粘贴自动落盘</p>
        </div>
        <div class="note-act">
          <span class="dim">{{ noteMd.length }} 字符</span>
          <button @click="save">暂存</button>
        </div>
      </header>
      <div class="note-body">
        <!-- v-model 是单向回吐：编辑器是唯一真源，不反向覆写它 -->
        <NoteEditor v-model="noteMd" />
      </div>
      <div v-if="saved" class="note-foot">{{ saved }}</div>
    </main>
  </div>
</template>

<style scoped>
.shell {
  display: grid;
  grid-template-columns: 232px 1fr;
  height: 100%;
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
  color: #b45309;
  background: #fef3c7;
  border: 1px solid #fcd34d;
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

.note-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  padding: 18px 22px 12px;
  border-bottom: 1px solid var(--sw-border);
  flex: none;
}

.note-head h1 {
  font-size: 18px;
  margin: 0 0 2px;
}

.note-head .sub {
  margin: 0;
  font-size: 12px;
}

.note-act {
  display: flex;
  align-items: center;
  gap: 10px;
  flex: none;
}

.note-act button {
  padding: 5px 14px;
  border: 1px solid var(--sw-border);
  border-radius: 6px;
  background: var(--sw-bg-alt);
  color: var(--sw-fg);
  font: inherit;
  font-size: 13px;
  cursor: pointer;
}

.note-act button:hover {
  border-color: var(--sw-accent);
  color: var(--sw-accent);
}

.dim {
  font-size: 12px;
  color: var(--sw-dim);
}

.note-body {
  flex: 1 1 auto;
  min-height: 0;
}

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
