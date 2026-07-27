import { fileURLToPath } from 'node:url';

import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// The APP build (the standalone theme browser). The LIBRARY build is a
// separate config — see vite.lib.config.ts.
//
// The dev/preview port is pinned to 8080 on purpose and MUST NOT be changed
// casually: FastApiBackend's CORS allowlist (../../FastApiBackend/src/core/
// config.py) contains 8081 / 8082 / 3000 / 8080 but NOT Vite's default 5173,
// so `GET /api/v1/theme/showcase-defaults` fails CORS on any other port.
// Pinning here is what keeps this a zero-backend-change frontend.
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      // The app consumes the library through its public entry, exactly as an
      // outside consumer would — so a missing export fails here, not in prod.
      'theme-react': fileURLToPath(new URL('./src/lib/index.ts', import.meta.url)),
    },
  },
  server: { port: 8080, strictPort: true },
  preview: { port: 8080, strictPort: true },
  build: {
    outDir: 'dist/app',
    emptyOutDir: true,
  },
});
