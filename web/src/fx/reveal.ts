/* ═══════════════════════════════════════════════════════════════════════
   呼出编排 —— AHK 侧唯一需要认识的两个函数
   · reveal()：Show() 之后调，播 480ms 入场 + 一次粒子迸发
   · reset() ：Hide() **之前**调。⚠ 不调的话，隐藏期间动画已经跑完，
     下次 Show() 第一帧会闪一下完整画面（实测过，很显眼）
   · 两个都要幂等：连按热键时后一次能干净覆盖前一次
   ═══════════════════════════════════════════════════════════════════════ */

import { burst, resetParticles, stats as particleStats, type FxStats } from './particles'

const REVEAL_MS = 480
const TAIL_MS = 340

let timer = 0

export function reveal(): string {
  const h = document.documentElement
  // flat 主题没有入场动画 —— 直接返回，别白加类
  if (!h.dataset.style || h.dataset.style === 'flat') return 'skip:flat'

  h.classList.remove('sw-revealing')
  // ⚠ 强制回流：同一帧里 remove→add 不会重播动画，第二次呼出会"没反应"
  void h.offsetWidth
  h.classList.add('sw-revealing')

  window.clearTimeout(timer)
  timer = window.setTimeout(() => h.classList.remove('sw-revealing'), REVEAL_MS + TAIL_MS)

  burst(REVEAL_MS + 140)
  return 'ok'
}

export function reset(): string {
  window.clearTimeout(timer)
  document.documentElement.classList.remove('sw-revealing')
  resetParticles()
  return 'ok'
}

export function fxStats(): FxStats & { revealing: boolean; style: string } {
  return {
    ...particleStats(),
    revealing: document.documentElement.classList.contains('sw-revealing'),
    style: document.documentElement.dataset.style ?? 'flat',
  }
}
