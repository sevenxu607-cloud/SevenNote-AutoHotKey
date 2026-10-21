import { createApp } from 'vue'
import App from './App.vue'
import { applyTheme } from './ahk'
import './style.css'
import './editor.css'

// AHK 换主题时（Alt+T）用 WebHostService.Eval 推过来：
//   window.__sevenwork && window.__sevenwork.applyTheme({...})
// 走 window 而不是模块导入，是因为 Eval 的字符串碰不到模块作用域。
// ⚠ 挂在 createApp 之前：AHK 可能在页面 onMounted 之后立刻推一次。
;(window as unknown as Record<string, unknown>).__sevenwork = { applyTheme }

createApp(App).mount('#app')
