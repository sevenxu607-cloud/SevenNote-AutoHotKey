import { createApp } from 'vue'
import App from './App.vue'
import { applyTheme } from './ahk'
import { reveal, reset, fxStats } from './fx/reveal'
import './style.css'
import './editor.css'

/* 材质预览：npm run dev 或截图验证时加 ?style=glass 直接看琉璃，不必起 AHK。
   真机上由 applyTheme() 按主题条目的 style 字段设置，这里只是预览入口。 */
const styleParam = new URLSearchParams(location.search).get('style')
if (styleParam) document.documentElement.dataset.style = styleParam

// AHK 换主题时（Alt+T）用 WebHostService.Eval 推过来：
//   window.__sevenwork && window.__sevenwork.applyTheme({...})
// 走 window 而不是模块导入，是因为 Eval 的字符串碰不到模块作用域。
// ⚠ 挂在 createApp 之前：AHK 可能在页面 onMounted 之后立刻推一次。
;(window as unknown as Record<string, unknown>).__sevenwork = { applyTheme }

// 呼出编排：AHK 侧 Show() 之后调 __swfx.reveal()，Hide() 之前调 __swfx.reset()。
// 走 window 的理由同上 —— Eval 的字符串碰不到模块作用域。
;(window as unknown as Record<string, unknown>).__swfx = {
  reveal,
  reset,
  stats: fxStats,
}

/* ═══════════════════════════════════════════════════════════════════════
   材质层（S0 定型后从 lab 移植）—— ① 光雾 + ⑥ specular
   · 光雾节点在这里注入，不写进 Vue 模板：自检页 / 笔记页 / 将来的面板
     共享同一层底，写模板里就得抄四遍。
   · 节点**常驻**，开关交给 CSS —— flat 主题下 .sw-aurora 是 display:none，
     一点模糊成本都不付（见 glass.css）。
   · 颜色归 CSS 的 --sw-aur-*（JS 不认色值），位置 / 尺寸 / 节奏归这里。
   ⚠ 光团必须是**独立的圆**：一个元素铺 N 层 radial-gradient 会平均成一片
     均匀暗青（S0 的病根，详见 glass.css 顶部那段）。
   ⚠ v2.13 整体收小一档（72→54 / 30→26）：光团越大、blur 一抹越均匀，
     去色之后就没有任何东西能撑起「雾」的形状了。收小 + 浓度更陡（见 glass.css
     的 radial-gradient）才读得出「一团光在板后面」，而不是「整屏被提亮了一点点」。
     尺寸三级是有意的：大团在角上=远、中团=中景、aur-5 那团最小最亮=近，
     三档叠起来才有景深 —— 玻璃「透」的错觉就从这来。
   ═══════════════════════════════════════════════════════════════════════ */
const ORBS: Record<string, string>[] = [
  { '--c': 'var(--sw-aur-1)', width: '46vmin', height: '46vmin', left: '-10vmin', top: '-14vmin', '--dur': '44s', '--dx': '5vmin', '--dy': '4vmin' },
  { '--c': 'var(--sw-aur-2)', width: '40vmin', height: '40vmin', right: '-12vmin', top: '-8vmin', opacity: '0.75', '--dur': '58s', '--delay': '-11s', '--dx': '-6vmin', '--dy': '5vmin' },
  { '--c': 'var(--sw-aur-3)', width: '38vmin', height: '38vmin', right: '-4vmin', bottom: '-14vmin', '--dur': '51s', '--delay': '-23s', '--dx': '4vmin', '--dy': '-6vmin' },
  { '--c': 'var(--sw-aur-4)', width: '34vmin', height: '34vmin', left: '-6vmin', bottom: '-16vmin', opacity: '0.7', '--dur': '66s', '--delay': '-31s', '--dx': '-5vmin', '--dy': '-4vmin' },
  { '--c': 'var(--sw-aur-5)', width: '28vmin', height: '28vmin', left: '44%', top: '0%', opacity: '0.9', '--dur': '72s', '--delay': '-16s', '--dx': '3vmin', '--dy': '7vmin' },
]

const aurora = document.createElement('div')
aurora.className = 'sw-aurora'
for (const orb of ORBS) {
  const el = document.createElement('span')
  el.className = 'sw-orb'
  for (const [k, v] of Object.entries(orb)) el.style.setProperty(k, v)
  aurora.append(el)
}
document.body.prepend(aurora)

/* specular：鼠标划过「板」时板面亮一块，坐标写成百分比、按**元素自身**尺寸取。
   用事件委托而不是逐个绑定 —— 将来的面板 / 对话框会长出新板子，逐个绑会漏。
   ⚠ 每帧最多算一次 getBoundingClientRect：pointermove 是高频事件，逐次算会强制
     布局、拖窗口时掉帧。 */
let specPending: PointerEvent | null = null
let specRaf = 0

document.addEventListener(
  'pointermove',
  (e) => {
    if (!(e.target as Element | null)?.closest?.('.sw-plate')) return
    specPending = e
    if (specRaf) return
    specRaf = requestAnimationFrame(() => {
      specRaf = 0
      const ev = specPending
      specPending = null
      const el = (ev?.target as Element | null)?.closest?.('.sw-plate') as HTMLElement | null
      if (!ev || !el) return
      const r = el.getBoundingClientRect()
      el.style.setProperty('--spec-x', `${((ev.clientX - r.left) / r.width) * 100}%`)
      el.style.setProperty('--spec-y', `${((ev.clientY - r.top) / r.height) * 100}%`)
    })
  },
  { passive: true },
)

createApp(App).mount('#app')
