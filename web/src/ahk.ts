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

/** 主题对象 —— 与 ThemeService.Themes 的字段一一对应 */
export interface Theme {
  name: string
  win: string
  edBg: string
  text: string
  dim: string
}

/** AHK 推主题：__sevenwork.applyTheme({name, win, edBg, text, dim}) */
export function applyTheme(t: Theme): void {
  const r = document.documentElement.style
  r.setProperty('--sw-bg', '#' + t.edBg)
  r.setProperty('--sw-bg-alt', '#' + t.win)
  r.setProperty('--sw-fg', '#' + t.text)
  r.setProperty('--sw-dim', '#' + t.dim)
  // 代码块 / 选区需要一个比正文底再深（或再浅）一档的颜色，主题里没给，
  // 按背景明暗推：暗底就往浅走，亮底就往深走。别直接复用 win —— 那个是标题栏色。
  const dark = luminance(t.edBg) < 128
  r.setProperty('--sw-code-bg', dark ? shift(t.edBg, 12) : shift(t.edBg, -8))
  r.setProperty('--sw-select', hexToRgba(t.dim || t.text, 0.26))
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

/** 相对亮度（sRGB 近似），只用来判明暗，不用于精确对比度 */
function luminance(hex: string): number {
  const [r, g, b] = parseHex(hex)
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
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
