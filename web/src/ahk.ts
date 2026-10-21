/* ═══════════════════════════════════════════════════════════════════════
   AHK 桥 —— 前端唯一允许碰宿主的入口
   · hostObjects：AHK 用 AddHostObjectToScript("ahk", {...}) 注册，
     JS 侧 chrome.webview.hostObjects.ahk.<method>() 返回 Promise
   · 拿不到 chrome.webview 时（普通浏览器里跑 vite dev）全部降级为假数据，
     这样 `npm run dev` 也能调样式，不必每次都起 AHK
   ═══════════════════════════════════════════════════════════════════════ */

export interface AhkBridge {
  ping(): Promise<string>
  version(): Promise<string>
  getTheme(): Promise<string>
}

type ChromeWebView = {
  hostObjects?: Record<string, any>
  postMessage(msg: unknown): void
  addEventListener(type: string, cb: (e: MessageEvent) => void): void
}

export function webview(): ChromeWebView | null {
  const wv = (window as any).chrome?.webview
  return wv ?? null
}

/** 是否真的跑在 WebView2 里（而不是 npm run dev 的浏览器） */
export function isHosted(): boolean {
  return !!webview()?.hostObjects?.ahk
}

export function bridge(): Record<string, any> | null {
  return webview()?.hostObjects?.ahk ?? null
}

/** 调 AHK 侧方法；AHK 函数返回值会被包成 Promise */
export async function ahkCall<T = string>(method: string, ...args: unknown[]): Promise<T> {
  const b = bridge()
  if (!b) throw new Error('hostObjects 未注入（不在 WebView2 里）')
  const fn = b[method]
  if (typeof fn !== 'function') throw new Error(`AHK 未提供方法：${method}`)
  return (await fn(...args)) as T
}

/**
 * 语义色板 —— 与 AHK 侧 ThemeService.Palette() 的字段一一对应。
 * 名字沿用 --sw-* 的语义，AHK 一次算全再推过来（派生规则只写在一处）。
 */
export interface Theme {
  name: string
  win: string // 窗口底 / 标题栏   → --sw-bg-alt
  edBg: string // 内容底           → --sw-bg
  text: string // 正文             → --sw-fg
  dim: string // 次要文字          → --sw-dim
  accent?: string // 强调色        → --sw-accent
  border?: string // 分隔线        → --sw-border
  codeBg?: string // 代码块 / 列表底 → --sw-code-bg
  dark?: boolean // 是否深色（AHK 判，避免两边公式不一致）
  bg?: string // 背景图绝对路径（P3 背景图主题用，当前不消费）
  bgAlpha?: number // 背景图遮罩 0-100（P3）
}

/** AHK 推主题：__sevenwork.applyTheme({name, win, edBg, text, dim, accent, ...}) */
export function applyTheme(t: Theme): void {
  const r = document.documentElement.style
  const hex = (v: string) => (v.startsWith('#') ? v : '#' + v)

  r.setProperty('--sw-bg', hex(t.edBg))
  r.setProperty('--sw-bg-alt', hex(t.win))
  r.setProperty('--sw-fg', hex(t.text))
  r.setProperty('--sw-dim', hex(t.dim))

  // accent / border / codeBg / dark 全部由 AHK 的 ThemeService.Palette() 派生后推来。
  // 从前这几个前端自己算（border 干脆一直用 CSS 里那支米黄 #d8cdb0）—— 深色主题下
  // 既不像分隔线也不像强调色。派生只写一处，网页与 AHK 窗口才对得上。
  // 缺字段时退回本地推导：`npm run dev` 在浏览器里跑，没有 AHK 推值。
  const dark = t.dark ?? luminance(t.edBg) < 128
  r.setProperty('--sw-accent', hex(t.accent ?? (dark ? '7FB4D8' : '4A7C9E')))
  r.setProperty('--sw-border', hex(t.border ?? (dark ? shift(t.edBg, 12) : shift(t.edBg, -14))))
  r.setProperty('--sw-code-bg', hex(t.codeBg ?? (dark ? shift(t.edBg, 12) : shift(t.edBg, -8))))
  r.setProperty('--sw-select', hexToRgba(t.accent ?? t.dim, 0.26))
  document.documentElement.dataset.theme = t.name
}

/* ── 颜色小工具（主题推下来的是 6 位 hex，不带 #）───────────────────── */

function parseHex(hex: string): [number, number, number] {
  const h = hex.replace('#', '')
  return [
    parseInt(h.slice(0, 2), 16) || 0,
    parseInt(h.slice(2, 4), 16) || 0,
    parseInt(h.slice(4, 6), 16) || 0,
  ]
}

function toHex(rgb: [number, number, number]): string {
  return (
    '#' +
    rgb
      .map((v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0'))
      .join('')
  )
}

/**
 * 相对亮度（Rec.601 加权），只用来判明暗，不用于精确对比度。
 * ⚠ 系数与 AHK 侧 ThemeService.IsDark / UiPaint.IsDark 必须完全一致 ——
 *   两边对同一主题判出不同明暗，就会出现「网页深、标题栏浅」。
 */
function luminance(hex: string): number {
  const [r, g, b] = parseHex(hex)
  return 0.299 * r + 0.587 * g + 0.114 * b
}

/** 整体加减同一档亮度 */
function shift(hex: string, delta: number): string {
  const [r, g, b] = parseHex(hex)
  return toHex([r + delta, g + delta, b + delta])
}

function hexToRgba(hex: string, alpha: number): string {
  const [r, g, b] = parseHex(hex)
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}

/* ═══════════════════════════════════════════════════════════════════════
   图片落盘
   WebView2 里交给 AHK（saveImage(base64, ext) → 相对路径）；
   浏览器预览里内联 data URL —— 让 `npm run dev` 也能验粘贴，不必起 AHK。
   ═══════════════════════════════════════════════════════════════════════ */

/** Uint8Array → base64。分块拼，别一次性 spread —— 5 MB 图会爆调用栈 */
function bytesToBase64(bytes: Uint8Array): string {
  let out = ''
  const step = 0x8000
  for (let i = 0; i < bytes.length; i += step) {
    out += String.fromCharCode(...bytes.subarray(i, i + step))
  }
  return btoa(out)
}

function extOf(file: File): string {
  const m = /^image\/([a-z0-9]+)/i.exec(file.type)
  if (!m) return 'png'
  return m[1].toLowerCase() === 'jpeg' ? 'jpg' : m[1].toLowerCase()
}

export async function storeImage(file: File): Promise<string> {
  const b64 = bytesToBase64(new Uint8Array(await file.arrayBuffer()))
  if (isHosted()) {
    try {
      return await ahkCall<string>('saveImage', b64, extOf(file))
    } catch {
      // AHK 侧还没实现 saveImage 时退回内联 —— 别让整次粘贴失败
    }
  }
  return `data:${file.type || 'image/png'};base64,${b64}`
}

/* ═══════════════════════════════════════════════════════════════════════
   路径双态：存盘要可移植，显示要能加载
   · markdown 里写 ./_assets/<日期>/x.png —— 与 PandocService._FixMarkdown 同式，
     用户把 Markdown 副本拿到 Typora / VS Code 里，图片照样找得到；
   · 但页面运行在 https://app.local，相对路径会被解析成 app.local/_assets/... → 404。
   · AHK 侧把 vault 额外挂成 vault.local（WebHostService.MapHost），
     显示时加前缀、落盘时剥掉，两边各得其所。
   · 浏览器预览（npm run dev）里没有 vault.local，图片会 404 —— 但那时
     storeImage 走的是 data URL 分支，压根不会产生相对路径，碰不到这个坑。
   ═══════════════════════════════════════════════════════════════════════ */

export const VAULT_HOST = 'vault.local'
const VAULT_BASE = `https://${VAULT_HOST}/`

/** 相对路径 → 可显示的 URL；已经带协议的原样返回 */
export function toDisplayUrl(src: string): string {
  if (/^(https?:|data:|blob:)/i.test(src)) return src
  return VAULT_BASE + src.replace(/^\.\//, '').replace(/^\/+/, '')
}

/**
 * markdown 里的图片相对路径 → 显示 URL。
 * 只动 `![alt](src)`，普通链接 `[t](u)` 不碰。
 * ⚠ 不支持 `![a](x.png "标题")` 这种带 title 的写法 —— 本项目不产生它。
 */
export function toDisplayMarkdown(md: string): string {
  return md.replace(
    /(!\[[^\]]*\]\()([^)\s]+)(\))/g,
    (_m, head: string, src: string, tail: string) => head + toDisplayUrl(src) + tail,
  )
}

/** 反向：显示 URL → 相对路径。落盘的 markdown 必须是这一版 */
export function toStoredMarkdown(md: string): string {
  return md.replace(
    /(!\[[^\]]*\]\()https:\/\/vault\.local\/([^)\s]+)(\))/g,
    '$1./$2$3',
  )
}
