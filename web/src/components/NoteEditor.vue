<script setup lang="ts">
/* ═══════════════════════════════════════════════════════════════════════
   Milkdown 编辑器封装
   · 只做「Markdown 进、Markdown 出」，不认识笔记存储、不认识 AHK 文件名
   · 图片粘贴 / 拖入由 upload 插件接管，uploader 里换成自己的落盘逻辑
   ═══════════════════════════════════════════════════════════════════════ */
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { Editor, rootCtx, defaultValueCtx } from '@milkdown/kit/core'
import { commonmark } from '@milkdown/kit/preset/commonmark'
import { gfm } from '@milkdown/kit/preset/gfm'
import { listener, listenerCtx } from '@milkdown/kit/plugin/listener'
import { history } from '@milkdown/kit/plugin/history'
import { upload, uploadConfig } from '@milkdown/kit/plugin/upload'
import { dropCursor } from '@milkdown/kit/prose/dropcursor'
import { gapCursor } from '@milkdown/kit/prose/gapcursor'
import { getMarkdown, replaceAll, $prose } from '@milkdown/kit/utils'
import { storeImage, toDisplayMarkdown, toDisplayUrl, toStoredMarkdown } from '../ahk'
import '@milkdown/kit/prose/gapcursor/style/gapcursor.css'

const props = defineProps<{ modelValue?: string }>()
const emit = defineEmits<{
  (e: 'update:modelValue', v: string): void
  (e: 'ready'): void
}>()

const host = ref<HTMLDivElement>()
let editor: Editor | null = null
let disposed = false
// 上一次 emit 出去的「存储态」markdown。拿它做比较而不是 listener 给的 prev ——
// prev 是显示态（图片 src 带 vault.local 前缀），跟存储态永远不相等，
// 那样每次敲键都会 emit 一遍，App.vue 的存盘也跟着白跑。
let lastStored = props.modelValue ?? ''

onMounted(async () => {
  const mark = (s: string) => { ;(window as any).__noteStage = s }
  mark('mount')
  if (!host.value) return
  const el = host.value
  mark('make')
  const builder = Editor.make()
    .config((ctx) => {
      ctx.set(rootCtx, el)
      // 进来的 markdown 是存储态（./_assets/…），渲染前换成可加载的 URL
      ctx.set(defaultValueCtx, toDisplayMarkdown(props.modelValue ?? ''))

      // 内容变化回吐 markdown（Milkdown 内部有节流，不用自己 debounce）
      ctx.get(listenerCtx).markdownUpdated((_, md) => {
        const stored = toStoredMarkdown(md)
        if (stored === lastStored) return
        lastStored = stored
        emit('update:modelValue', stored)
      })

      // 图片粘贴 / 拖入：不交给默认 uploader（它只会转 base64 内联），
      // 换成我们的 storeImage —— WebView2 里落盘成文件，浏览器里才内联。
      ctx.update(uploadConfig.key, (prev) => ({
        ...prev,
        uploader: async (files, schema) => {
          const nodes = []
          for (const f of Array.from(files)) {
            if (!f.type.startsWith('image/')) continue
            // AHK 回的是 ./_assets/…（可移植），节点 src 得是能加载的 URL
            const src = toDisplayUrl(await storeImage(f))
            nodes.push(schema.nodes.image.create({ src, alt: f.name || 'image' }))
          }
          return nodes
        },
      }))
    })
    .use(commonmark)
    .use(gfm)
    .use(listener)
    .use(history)
    .use($prose(() => dropCursor()))
    .use($prose(() => gapCursor()))
    .use(upload)
  mark('built')
  let created: any
  try {
    created = await Promise.race([
      builder.create(),
      new Promise<never>((_, rej) => setTimeout(() => rej(new Error('create timeout 10s')), 10000)),
    ])
  } catch (e: any) {
    mark('create-fail: ' + String(e) + ' @@ ' + String(e?.stack).slice(0, 500))
    throw e
  }
  mark('created')

  // 卸载与创建赛跑：组件可能在 await 期间就被销毁了
  if (disposed) {
    created.destroy()
    return
  }
  editor = created
  mark('ready')
  emit('ready')
})

onBeforeUnmount(() => {
  disposed = true
  editor?.destroy()
  editor = null
})

defineExpose({
  getMarkdown(): string {
    if (!editor) return props.modelValue ?? ''
    // 出编辑器就转回存储态 —— 这才是能写进 .md 的那一版
    return toStoredMarkdown(editor.action(getMarkdown()) as unknown as string)
  },

  /**
   * 整体换文档：载入笔记 / 切日期都走这里。
   * 只靠 props 换不动 —— defaultValueCtx 只在创建时读一次。
   *
   * flush = true 重建 EditorState，连带清掉撤销栈：换的是另一篇笔记，
   * 让它还能 Ctrl+Z 回上一篇的内容是错的。返回 false 表示编辑器还没建好，
   * 调用方需要先挂起来、等 ready 再灌。
   */
  setMarkdown(md: string): string {
    if (!editor) return 'no-editor'
    // ⚠ 必须先写 lastStored：markdownUpdated 是同步触发的，晚一步就会把旧值 emit 回去
    lastStored = md
    try {
      editor.action(replaceAll(toDisplayMarkdown(md), true))
      return 'ok'
    } catch (e) {
      return 'ERR ' + String(e)
    }
  },
})
</script>

<template>
  <div ref="host" class="sw-editor" />
</template>
