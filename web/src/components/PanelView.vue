<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import {
  isHosted,
  ahkCall,
  applyTheme,
  applySettings,
  fetchPanel,
  type PanelData,
  type PanelRow,
  type Theme,
} from '../ahk'

/* ═══════════════════════════════════════════════════════════════════════
   工作台面板（Alt+S）—— 原 WorkBenchUI 的 WebView2 版

   · 平台只给数据（rows = 「全部热键」视图 + 各模块，各自带热键与可选的
     设置声明），这个组件只负责「摆」。加模块、改布局都不用来这里改。
   · 整份数据一次取完，切页是纯前端行为；只有「保存 / 浏览」会回 AHK 一趟。
   · 原生版换主题要关窗重开（30+ 个控件逐块上色比重建还慢），这里换主题
     只换 CSS 变量，**停在哪页保持不变**。
   ═══════════════════════════════════════════════════════════════════════ */

const hosted = isHosted()

const data = ref<PanelData | null>(null)
const currentId = ref('')
/** 当前页设置字段的编辑值：field.key → 值（与 spec.fields 一一对应） */
const vals = ref<Record<string, string>>({})
const status = ref('')
const statusKind = ref<'dim' | 'ok' | 'err' | 'warn'>('dim')
const saveText = ref('保存设置')
const busy = ref(false)

const rows = computed<PanelRow[]>(() => data.value?.rows ?? [])
const cur = computed<PanelRow | null>(
  () => rows.value.find((r) => r.id === currentId.value) ?? rows.value[0] ?? null,
)

/* ── 浏览器预览的示例数据 ─────────────────────────────────────────────
   `npm run dev` 里没有 hostObjects。留一份最小的样子，调样式时不必每次起 AHK。
   数值刻意写得像真的（条数、失败态、folder 字段都覆盖到）。 */
const MOCK: PanelData = {
  app: 'SevenWork',
  version: 'dev',
  vault: 'D:\\Notes',
  total: 4,
  modules: 1,
  focus: '',
  rows: [
    {
      id: '__all',
      kind: 'view',
      name: '全部热键',
      desc: '所有模块的热键汇总 · 按分组排列',
      count: 4,
      failed: false,
      groups: [
        {
          name: '平台',
          items: [
            { key: 'Alt+S', label: '工作台面板（帮助 + 设置）' },
            { key: 'Alt+T', label: '循环切换界面主题' },
          ],
        },
        { name: '窗口', items: [{ key: 'Alt+Z', label: '呼出 / 隐藏' }] },
        { name: '日期与标签', items: [{ key: 'Alt+↑', label: '前一天' }] },
      ],
      spec: null,
    },
    {
      id: 'Folders',
      kind: 'module',
      name: '文件夹',
      desc: '三个槽位指向的目录 · Alt+1…3',
      count: 1,
      failed: false,
      hotkeys: [{ key: 'Alt+1', label: '呼出 / 隐藏槽位 1 的文件夹' }],
      spec: {
        title: '文件夹槽位',
        hint: '热键固定，指向哪个目录可以随时换；留空表示该槽位未启用。',
        hasApply: true,
        fields: [
          { key: 'Slot1', label: 'Alt+1 →', kind: 'folder', value: 'D:\\Work', placeholder: '' },
          { key: 'Slot2', label: 'Alt+2 →', kind: 'folder', value: '', placeholder: '未启用' },
        ],
      },
    },
  ],
}


/* ── 数据 ───────────────────────────────────────────────────────────── */
function pickValues(row: PanelRow | null) {
  const out: Record<string, string> = {}
  for (const f of row?.spec?.fields ?? []) out[f.key] = f.value ?? ''
  vals.value = out
}

function setStatus(text: string, kind: typeof statusKind.value = 'dim') {
  status.value = text
  statusKind.value = kind
}

/** 切页：鼠标点 / 上下键 / AHK 的 goto 都走这里 —— 只留一条路径就不会有半更新状态 */
function goto(id: string) {
  if (!id || id === currentId.value) return
  currentId.value = id
  pickValues(cur.value)
  setStatus('', 'dim')
}

/**
 * 拉一次全量。first = 首屏：按 AHK 给的 focus 定位（ShowHelp(id) 记下的目标页），
 * 否则保留当前页 —— 保存后回读不该把用户甩回第一页。
 */
async function load(first = false) {
  let d: PanelData | null = null
  if (hosted) {
    try {
      d = await fetchPanel()
    } catch (e) {
      setStatus('读取面板数据失败：' + String(e), 'err')
      return
    }
  } else {
    d = MOCK
  }
  if (!d) {
    setStatus('AHK 没有返回面板数据（见 .logs\\_error.log）', 'err')
    return
  }
  data.value = d

  const want = first ? d.focus : currentId.value
  const hit = d.rows.find((r) => r.id === want)
  currentId.value = (hit ?? d.rows[0])?.id ?? ''
  pickValues(cur.value)
  saveText.value = '保存设置'
  busy.value = false
}

/* ── 保存：三段反馈（保存设置 → 保存中… → ✓ / ✗）──────────────────────
   ⚠ 值按 fields 的声明顺序送，applySettings 负责补满 8 个槽位 ——
     AHK 侧是固定 8 个形参（原因见 PanelHostBridge.ahk 里 PanelHostApply 上方）。 */
async function save() {
  const row = cur.value
  if (!row?.spec?.hasApply || busy.value) return
  const values = (row.spec.fields ?? []).map((f) => vals.value[f.key] ?? '')

  busy.value = true
  saveText.value = '保存中…'

  try {
    if (!hosted) {
      setStatus('（浏览器预览）不落盘：' + values.filter(Boolean).join(' · '), 'ok')
      saveText.value = '✓ 已保存'
      return
    }
    const r = await applySettings(row.id, values)
    if (r === 'ok') {
      // 回读：模块可能在 apply 里把值规整过（去尾斜杠 / 空串归一），
      // 不回读的话输入框里还是用户刚敲的原始样子。
      await load()
      setStatus('✓ 已保存，下次按热键即生效', 'ok')
      saveText.value = '✓ 已保存'
    } else {
      setStatus('保存失败：' + r.replace(/^err:/, ''), 'err')
      saveText.value = '✗ 失败'
    }
  } catch (e) {
    setStatus('保存失败：' + String(e), 'err')
    saveText.value = '✗ 失败'
  } finally {
    busy.value = false
    setTimeout(() => {
      saveText.value = '保存设置'
    }, 1200)
  }
}

/* ── 浏览文件夹：交给 AHK 的 DirSelect（网页 <input type=file> 拿不到目录路径）*/
async function browse(fieldKey: string) {
  if (!hosted) {
    setStatus('（浏览器预览）选不了文件夹', 'warn')
    return
  }
  setStatus('正在选择文件夹…', 'dim')
  try {
    const sel = await ahkCall<string>('browse', vals.value[fieldKey] ?? '')
    if (!sel) {
      setStatus('已取消，输入框保持原值', 'dim')
      return
    }
    vals.value[fieldKey] = sel
    // 只回填输入框，很多人会以为已经生效了 —— 明确说一句
    setStatus('已选择，记得点「保存设置」', 'warn')
  } catch (e) {
    setStatus('打不开文件夹选择框：' + String(e), 'err')
  }
}

function closePanel() {
  if (hosted) ahkCall('close').catch(() => {})
}

/* ── 键盘上下切页（照原生 ListView 的习惯）────────────────────────────
   ⚠ 焦点在输入框里时不抢键：那里上下键该走光标 / 补全。 */
function onKeydown(e: KeyboardEvent) {
  const t = e.target as HTMLElement | null
  if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA')) return
  const i = rows.value.findIndex((r) => r.id === currentId.value)
  if (i < 0) return
  if (e.key === 'ArrowDown' && i + 1 < rows.value.length) {
    e.preventDefault()
    goto(rows.value[i + 1].id)
  } else if (e.key === 'ArrowUp' && i > 0) {
    e.preventDefault()
    goto(rows.value[i - 1].id)
  }
}

onMounted(async () => {
  window.addEventListener('keydown', onKeydown)

  // AHK 侧面板已经开着时再按 Alt+S（或某个模块请求「打开我这一页」）：
  // ShowHelp 会 Eval('__swpanel.goto(id)')。挂在这里而不是模板里 ——
  // Eval 的字符串碰不到模块作用域（同 main.ts 的 __sevenwork）。
  ;(window as any).__swpanel = { goto }

  // 主题：AHK 推送优先，拿不到就用 CSS 里的默认值（npm run dev 时走这条）
  if (hosted) {
    try {
      const raw = await ahkCall<string>('getTheme')
      if (raw) applyTheme(JSON.parse(raw) as Theme)
    } catch {
      /* 主题是锦上添花，拿不到不该挡住面板 */
    }
  }

  await load(true)
})
</script>

<template>
  <div class="panel">
    <!-- ═══ 左：导航 ═══ 名称 / 条数两列 —— 后端一个数字也能告诉用户「这页有多少内容」 -->
    <aside class="pnav sw-plate">
      <div class="pbrand">
        <span class="pdot" />
        <span class="papp">{{ data?.app ?? 'SevenWork' }}</span>
        <span class="pver">v{{ data?.version ?? '?' }}</span>
      </div>

      <nav class="plist">
        <button
          v-for="row in rows"
          :key="row.id"
          class="pitem"
          :class="{ on: row.id === cur?.id, bad: row.failed }"
          @click="goto(row.id)"
        >
          <span class="pitem-name">
            <span v-if="row.kind === 'view'" class="pmark">≡</span>{{ row.name }}
          </span>
          <span class="pitem-count">{{ row.count }}</span>
        </button>
      </nav>

      <div class="pfoot">
        {{ data?.modules ?? 0 }} 个模块 · 共 {{ data?.total ?? 0 }} 条热键
      </div>
    </aside>

    <!-- ═══ 右：内容 ═══ -->
    <section class="pmain sw-plate">
      <header class="phead">
        <h1>{{ cur?.name ?? '工作台' }}</h1>
        <p class="sub">{{ cur?.desc }}</p>
      </header>

      <div class="pbody">
        <!-- 视图页按分组；模块页平铺（模块通常只占 1~2 组，再分组只会把两行字拆成三块） -->
        <template v-if="cur?.kind === 'view'">
          <section v-for="g in cur.groups ?? []" :key="g.name" class="pgroup">
            <div class="pglabel">{{ g.name }}</div>
            <div v-for="(hk, i) in g.items" :key="g.name + '-' + i" class="prow">
              <code class="pkey">{{ hk.key }}</code>
              <span class="plabel">{{ hk.label }}</span>
              <span v-if="hk.note" class="pnote">{{ hk.note }}</span>
            </div>
          </section>
        </template>

        <template v-else>
          <p v-if="cur?.failed" class="pwarn">
            该模块启动失败，热键一条都没注册。详情见 .logs\_error.log，修复后重启程序即可
            —— 其它模块不受影响。
          </p>
          <p v-else-if="!(cur?.hotkeys ?? []).length" class="pempty">（该模块没有热键）</p>
          <div v-for="(hk, i) in cur?.hotkeys ?? []" :key="i" class="prow">
            <code class="pkey">{{ hk.key }}</code>
            <span class="plabel">{{ hk.label }}</span>
            <span v-if="hk.note" class="pnote">{{ hk.note }}</span>
          </div>
        </template>

        <!-- 设置区：模块自己声明才有（平台只认 {label, kind, value}，不认识业务名词）-->
        <section v-if="cur?.spec" class="pspec">
          <div class="psptitle">{{ cur.spec.title }}</div>
          <p class="psphint">{{ cur.spec.hint }}</p>
          <div v-for="f in cur.spec.fields ?? []" :key="f.key" class="pfield">
            <label class="pf-label">{{ f.label }}</label>
            <input
              v-model="vals[f.key]"
              class="sw-input pf-input"
              :placeholder="f.placeholder"
              spellcheck="false"
              @keydown.enter="save"
            />
            <button
              v-if="f.kind === 'folder'"
              class="sw-btn sw-btn--ghost pf-browse"
              @click="browse(f.key)"
            >
              浏览…
            </button>
          </div>
        </section>
        <p v-else-if="cur?.kind === 'module' && !cur?.failed" class="pempty">
          该模块没有可调设置 —— 参数是写死的（或由它自己的窗口管），上面的热键随时可用。
        </p>
      </div>

      <!-- 底栏：状态 + 笔记目录 + 操作。没有它，按钮就「浮在空气里」 -->
      <footer class="pfoot2">
        <span class="pstatus" :class="statusKind">{{ status }}</span>
        <span class="pvault" :title="data?.vault">{{ data?.vault }}</span>
        <button
          v-if="cur?.spec?.hasApply"
          class="sw-btn sw-btn--primary"
          :disabled="busy"
          @click="save"
        >
          {{ saveText }}
        </button>
        <button class="sw-btn sw-btn--ghost" @click="closePanel">关闭</button>
      </footer>
    </section>
  </div>
</template>

<style scoped>
/* ═══ 骨架 ═══════════════════════════════════════════════════════════
   两块「板」，中间留缝，四周留边 —— 板外留边才有玻璃感（满窗均匀柔光 =
   又变回一块深色主题，这是 S1 踩过的坑）。
   材质（背景 / 模糊 / 边框 / 反光）归 glass.css，这里只摆结构。 */
.panel {
  height: 100%;
  box-sizing: border-box;
  padding: 14px;
  display: grid;
  grid-template-columns: 216px minmax(0, 1fr);
  gap: 14px;
}

.pnav,
.pmain {
  min-height: 0;
  overflow: hidden;
  border-radius: var(--sw-radius-lg, 14px);
  /* 兜底底色：glass 主题下由 glass.css 的 rgba + backdrop-filter 盖掉
     （specificity 0,2,1 > 这里的 0,2,0）。非 glass / npm run dev 时靠它分层。 */
  background: var(--sw-bg-alt);
}

.pnav {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 16px 12px 12px;
}

.pmain {
  display: flex;
  flex-direction: column;
}

/* ═══ 左：品牌 + 导航 ═══════════════════════════════════════════════ */
.pbrand {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 6px;
  font-size: 13px;
  font-weight: 600;
}

.pdot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--sw-accent);
  flex: none;
}

.papp {
  flex: 1;
  letter-spacing: 0.02em;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pver {
  flex: none;
  font-size: 11px;
  font-weight: 400;
  color: var(--sw-dim);
}

.plist {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.pitem {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  padding: 7px 10px;
  border: 1px solid transparent;
  border-radius: 8px;
  background: transparent;
  color: var(--sw-fg);
  font: inherit;
  font-size: 13px;
  text-align: left;
  cursor: pointer;
  transition:
    background 140ms ease,
    border-color 140ms ease;
}

.pitem:hover {
  background: var(--sw-bg);
}

.pitem.on {
  background: var(--sw-bg);
  border-color: var(--sw-border);
  font-weight: 600;
}

/* 启动失败的模块：仍占一行，但名字偏红 —— 与「(失败)」两字一起提示 */
.pitem.bad .pitem-name {
  color: #e4877f;
}

.pitem-name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pitem-count {
  flex: none;
  font-size: 11px;
  color: var(--sw-dim);
  font-variant-numeric: tabular-nums;
}

.pmark {
  margin-right: 6px;
  opacity: 0.8;
}

.pfoot {
  flex: none;
  padding: 8px 6px 0;
  border-top: 1px solid var(--sw-border);
  font-size: 11px;
  color: var(--sw-dim);
}

/* ═══ 右：页眉 / 正文 ═══════════════════════════════════════════════
   页眉回答「我在哪一页」，副标题回答「这一页是干什么的」。拆两级而不是挤成
   一行 —— 一行里两种字号层级就没了（.clinerules/02「面板布局」）。 */
.phead {
  flex: none;
  padding: 18px 22px 12px;
  border-bottom: 1px solid var(--sw-border);
}

.phead h1 {
  margin: 0 0 3px;
  font-size: 18px;
  font-weight: 600;
}

.phead .sub {
  margin: 0;
  font-size: 12px;
  color: var(--sw-dim);
}

.pbody {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  padding: 14px 22px 18px;
}

.pgroup + .pgroup {
  margin-top: 16px;
}

.pglabel {
  margin-bottom: 6px;
  padding-left: 2px;
  font-size: 11px;
  letter-spacing: 0.08em;
  color: var(--sw-dim);
}

/* 一条热键：键名 / 说明两栏。键名定宽 —— 说明从左边缘对齐才扫得快 */
.prow {
  display: flex;
  align-items: baseline;
  gap: 12px;
  padding: 6px 10px;
  border-radius: 8px;
}

.prow:hover {
  background: var(--sw-bg);
}

.pkey {
  flex: none;
  min-width: 118px;
  font-family: ui-monospace, Consolas, 'Courier New', monospace;
  font-size: 12px;
  color: var(--sw-accent);
}

.plabel {
  flex: 1;
  min-width: 0;
  font-size: 13px;
}

.pnote {
  flex: none;
  font-size: 11px;
  color: var(--sw-dim);
}

.pwarn {
  margin: 0 0 14px;
  padding: 10px 12px;
  border: 1px solid rgba(228, 135, 127, 0.28);
  border-radius: 8px;
  background: rgba(180, 70, 60, 0.16);
  color: #e8a9a2;
  font-size: 12px;
  line-height: 1.7;
}

.pempty {
  margin: 0 0 12px;
  color: var(--sw-dim);
  font-size: 12px;
  line-height: 1.7;
}

/* ═══ 设置区 ═══════════════════════════════════════════════════════ */
.pspec {
  margin-top: 20px;
  padding-top: 16px;
  border-top: 1px solid var(--sw-border);
}

.psptitle {
  margin-bottom: 4px;
  font-size: 14px;
  font-weight: 600;
}

.psphint {
  margin: 0 0 12px;
  color: var(--sw-dim);
  font-size: 12px;
  line-height: 1.7;
}

.pfield {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 8px;
}

.pf-label {
  flex: none;
  width: 96px;
  color: var(--sw-dim);
  font-size: 12px;
}

/* 路径用等宽字体：比例字体下 "l" 与 "1"、"/" 与 "\" 几乎分不清 */
.pf-input {
  flex: 1;
  min-width: 0;
  font-family: ui-monospace, Consolas, 'Courier New', monospace;
  font-size: 12px;
}

.pf-browse {
  flex: none;
}

/* ═══ 底栏 ═══════════════════════════════════════════════════════════
   状态 + 笔记目录 + 按钮一条带子收住页尾；没有它按钮就「浮在空气里」。 */
.pfoot2 {
  flex: none;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 22px;
  border-top: 1px solid var(--sw-border);
  background: rgba(0, 0, 0, 0.16);
}

/* 语义三态：绿 = 成、红 = 败、琥珀 = 提醒。弱了就等于没反馈 */
.pstatus {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12px;
  font-weight: 600;
  color: var(--sw-dim);
}

.pstatus.ok {
  color: #6be39a;
}

.pstatus.err {
  color: #ff8b80;
}

.pstatus.warn {
  color: #f2c46b;
}

.pvault {
  flex: none;
  max-width: 40%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--sw-dim);
  font-size: 11px;
}

/* 保存中 / 保存完成时禁用，防止连点两次写两遍 */
.pfoot2 button:disabled {
  opacity: 0.55;
  cursor: default;
}
</style>
