/* ═══════════════════════════════════════════════════════════════════════
   冰晶粒子 —— 呼出时迸发一次，600ms 后彻底停帧
   · 用 Canvas2D 而不是 WebGL：160 个粒子走预渲染精灵 + drawImage，
     单帧 <1ms；上 WebGL 要多写 150 行着色器，收益只在 1000+ 粒子时才有
   · 空闲 CPU = 0：最后一帧画完立刻 cancelAnimationFrame 并移除 canvas
   · 关闭动画（prefers-reduced-motion）时一次都不启动
   ═══════════════════════════════════════════════════════════════════════ */

export type FxStats = {
  particles: number
  running: boolean
  lastMs: number
}

type Grain = {
  angle: number
  r0: number // 起始半径（相对最大半径）
  r1: number // 聚拢半径
  size: number
  warm: boolean // true = 靛紫，false = 冰青
  phase: number
}

const MAX = 160
// 48 而不是 32：六角冰晶要画 6 条主线 + 12 根短枝，32px 上全糊成一团白点。
// 预渲染 sprite 的开销是一次性的，drawImage 的成本只跟**目标尺寸**有关。
const SPRITE = 48

let canvas: HTMLCanvasElement | null = null
let ctx2d: CanvasRenderingContext2D | null = null
let spriteCool: HTMLCanvasElement | null = null
let spriteWarm: HTMLCanvasElement | null = null
let raf = 0
let running = false
let lastMs = 0

/**
 * 预渲染一枚**六角冰晶**（柔光晕 + 六条辐条 + 二级短枝）。
 *
 * 原来是一枚圆形径向渐变光点 —— 160 个圆点一起炸开，观感是「灰尘」不是「冰」。
 * 冰晶的关键是**有棱**：中心亮核之外必须有放射状的硬边，才读得出「晶体」；
 * 短枝（±60°、距心 55%）是雪晶的标志性结构，缺了就只是六角星。
 *
 * 每帧现算 createRadialGradient 是 160 次/帧，太贵 —— 所以只画一次、之后 drawImage。
 */
function makeSprite(rgb: string): HTMLCanvasElement {
  const s = document.createElement('canvas')
  s.width = SPRITE
  s.height = SPRITE
  const c = s.getContext('2d')
  if (!c) return s

  const k = SPRITE / 2
  const R = SPRITE / 2 - 1.5

  // ① 柔光晕：让冰晶溶进背景，而不是硬贴在玻璃上
  const g = c.createRadialGradient(k, k, 0, k, k, R)
  g.addColorStop(0, `rgba(${rgb},0.95)`)
  g.addColorStop(0.42, `rgba(${rgb},0.3)`)
  g.addColorStop(1, `rgba(${rgb},0)`)
  c.fillStyle = g
  c.beginPath()
  c.arc(k, k, R, 0, Math.PI * 2)
  c.fill()

  // ② 棱：主线 + 短枝。lineCap round + 1.1 宽，在 48px 上刚好不糊
  c.strokeStyle = `rgba(${rgb},0.9)`
  c.lineWidth = 1.1
  c.lineCap = 'round'
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI * 2
    const dx = Math.cos(a)
    const dy = Math.sin(a)

    c.beginPath()
    c.moveTo(k, k)
    c.lineTo(k + dx * R * 0.84, k + dy * R * 0.84)
    c.stroke()

    const bx = k + dx * R * 0.55
    const by = k + dy * R * 0.55
    for (const side of [-1, 1]) {
      const a2 = a + side * (Math.PI / 3)
      c.beginPath()
      c.moveTo(bx, by)
      c.lineTo(bx + Math.cos(a2) * R * 0.24, by + Math.sin(a2) * R * 0.24)
      c.stroke()
    }
  }

  // ③ 亮核：最后点一颗，压住六条线的交汇点（否则中心发灰）
  c.fillStyle = `rgba(255,255,255,0.95)`
  c.beginPath()
  c.arc(k, k, 1.6, 0, Math.PI * 2)
  c.fill()

  return s
}

function ensureCanvas(): HTMLCanvasElement {
  if (canvas && canvas.isConnected) return canvas
  const c = document.createElement('canvas')
  c.id = 'sw-fx'
  // z-index 5：压在内容之上、Toast(60) 之下；pointer-events:none 保证不挡点击
  c.style.cssText =
    'position:fixed;inset:0;width:100%;height:100%;pointer-events:none;z-index:5'
  document.body.appendChild(c)
  canvas = c
  ctx2d = c.getContext('2d')
  return c
}

function resize(c: HTMLCanvasElement): number {
  const dpr = Math.min(window.devicePixelRatio || 1, 2)
  const w = Math.floor(window.innerWidth * dpr)
  const h = Math.floor(window.innerHeight * dpr)
  if (c.width !== w || c.height !== h) {
    c.width = w
    c.height = h
  }
  return dpr
}

function cleanup(): void {
  if (!canvas) return
  if (ctx2d) ctx2d.clearRect(0, 0, canvas.width, canvas.height)
  canvas.remove()
  canvas = null
  ctx2d = null
}

/** 迸发一次。ms 是总时长；重复调用会打断上一次。 */
export function burst(ms = 620): void {
  if (window.matchMedia?.('(prefers-reduced-motion: reduce)')?.matches) return
  const c = ensureCanvas()
  const g = ctx2d
  if (!g) return

  const dpr = resize(c)
  const W = c.width
  const H = c.height
  const cx = W / 2
  const cy = H / 2
  const maxR = Math.hypot(W, H) / 2

  spriteCool ??= makeSprite('190,245,255')
  spriteWarm ??= makeSprite('190,180,255')
  const cool = spriteCool
  const warm = spriteWarm

  const grains: Grain[] = []
  for (let i = 0; i < MAX; i++) {
    grains.push({
      // 均匀铺满一圈，再加一点抖动 —— 纯随机会结团，看着像脏点
      angle: (i / MAX) * Math.PI * 2 + Math.random() * 0.07,
      r0: 0.72 + Math.random() * 0.36,
      r1: 0.06 + Math.random() * 0.2,
      // 14~36：48px 上画的六棱缩到 6px 就只剩一个白点，冰晶等于白做
      size: 14 + Math.random() * 22,
      warm: Math.random() < 0.22,
      phase: Math.random(),
    })
  }

  cancelAnimationFrame(raf)
  const t0 = performance.now()
  running = true

  const frame = (now: number) => {
    const t = Math.min(1, (now - t0) / ms)
    g.clearRect(0, 0, W, H)
    g.globalCompositeOperation = 'lighter'

    for (const gr of grains) {
      // 前 55%：从外圈向中心聚拢；后 45%：向外炸开成细屑
      const k =
        t < 0.55
          ? gr.r0 + (gr.r1 - gr.r0) * (t / 0.55)
          : gr.r1 + (0.42 + gr.phase * 0.5) * ((t - 0.55) / 0.45)
      const r = k * maxR
      const x = cx + Math.cos(gr.angle) * r
      const y = cy + Math.sin(gr.angle) * r * 0.82
      // 用 phase 把 160 颗的生死错开：原来的 a 只跟全局 t 走，整片冰晶会在
      // 同一瞬间一起淡到 0，看着像"关灯"而不是"雾散"
      const tp = Math.min(1, Math.max(0, t + (gr.phase - 0.5) * 0.18))
      const a = tp < 0.12 ? tp / 0.12 : 1 - (tp - 0.12) / 0.88
      const s = gr.size * dpr * (1 - t * 0.25)
      g.globalAlpha = Math.max(0, a) * 0.8
      g.drawImage(gr.warm ? warm : cool, x - s / 2, y - s / 2, s, s)
    }

    g.globalAlpha = 1
    g.globalCompositeOperation = 'source-over'

    if (t < 1) {
      raf = requestAnimationFrame(frame)
      return
    }
    running = false
    lastMs = performance.now() - t0
    cleanup()
  }

  raf = requestAnimationFrame(frame)
}

/** 收起时用：立即停帧并抹掉画布，别让上一轮残留半帧 */
export function resetParticles(): void {
  cancelAnimationFrame(raf)
  running = false
  cleanup()
}

export function stats(): FxStats {
  return { particles: MAX, running, lastMs: Math.round(lastMs) }
}
