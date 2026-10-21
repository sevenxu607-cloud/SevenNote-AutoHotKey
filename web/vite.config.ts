import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  // 关键：WebView2 通过 https://app.local/ 映射加载，资源用相对路径，换 hostName 不用改构建
  base: './',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    // WebView2 Runtime 155 ≈ Edge 155，保守取 chrome110 保证兼容
    target: 'chrome110',
    assetsInlineLimit: 0,
    rollupOptions: {
      output: {
        // 固定文件名：dist 入库，避免每次构建产出不同 hash 把 git 弄脏
        entryFileNames: 'assets/[name].js',
        chunkFileNames: 'assets/[name].js',
        assetFileNames: 'assets/[name].[ext]',
      },
    },
  },
  server: { port: 5173, strictPort: true },
})
