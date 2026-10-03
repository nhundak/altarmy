import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'

// `npm run dev` serves on :5173 and proxies /api to `altarmy-profit serve` on :8600.
export default defineConfig({
  plugins: [react()],
  // One bundle is fine at this size (Firebase is loaded lazily).
  build: { chunkSizeWarningLimit: 1000 },
  server: { proxy: { '/api': 'http://127.0.0.1:8600' } },
  test: { environment: 'jsdom', setupFiles: ['./src/test/setup.ts'] },
})
