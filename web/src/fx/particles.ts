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
const SPRITE = 32

let canvas: HTMLCanvasElement | null = null
let ctx2d: CanvasRenderingContext2D | null = null
let spriteCool: HTMLCanvasElement | null = null
let spriteWarm: HTMLCanvasElement | null = null
let raf = 0
let running = false
let lastMs = 0

/** 预渲染一枚柔边光点。每帧现算 createRadialGradient 是 160 次/帧，太贵。 */
function makeSprite(rgb: string): HTMLCanvasElement {
  const s = document.createElement('canvas')
  s.width = SPRITE
  s.height = SPRITE
  const c = s.getContext('2d')
  if (!c) return s
  const g = c.createRadialGradient(SPRITE / 2, SPRITE / 2, 0, SPRITE / 2, SPRITE / 2, SPRITE / 2)
  g.addColorStop(0, `rgba(${rgb},1)`)
  g.addColorStop(0.35, `rgba(${rgb},0.55)`)
  g.addColorStop(1, `rgba(${rgb},0)`)
  c.fillStyle = g
  c.beginPath()
  c.arc(SPRITE / 2, SPRITE / 2, SPRITE / 2, 0, Math.PI * 2)
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
      size: 6 + Math.random() * 16,
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
      const a = t < 0.12 ? t / 0.12 : 1 - (t - 0.12) / 0.88
      const s = gr.size * dpr * (1 - t * 0.25)
      g.globalAlpha = Math.max(0, a) * 0.85
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
