import { fileURLToPath } from 'node:url';

import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// The LIBRARY build. Emits both:
//   dist/theme-react.js       ES module, for bundler consumers
//   dist/theme-react.umd.js   UMD global `ThemeReact`, so the bundler-less
//                             LandingPage (React via CDN + Babel standalone,
//                             see ../../LandingPage/CLAUDE.md) can just
//                             <script src=...> it.
//
// Types are NOT emitted here — `npm run build:types` runs tsc against
// tsconfig.lib.json, which already declares `emitDeclarationOnly` into
// dist/types. vite-plugin-dts would only wrap that same compiler while adding
// a dependency (and, as of 4.5.4, a transitive advisory) for nothing.
//
// React is external in BOTH formats: the UMD consumer already has React and
// ReactDOM on window, and bundling a second copy would break hooks.
//
// emptyOutDir is false because `npm run build` runs the app build first
// (which owns dist/app) and this one writes alongside it.
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist',
    emptyOutDir: false,
    sourcemap: true,
    lib: {
      entry: fileURLToPath(new URL('./src/lib/index.ts', import.meta.url)),
      name: 'ThemeReact',
      formats: ['es', 'umd'],
      fileName: (format) => (format === 'umd' ? 'theme-react.umd.js' : 'theme-react.js'),
    },
    rollupOptions: {
      external: ['react', 'react-dom', 'react/jsx-runtime'],
      output: {
        globals: {
          react: 'React',
          'react-dom': 'ReactDOM',
          'react/jsx-runtime': 'jsxRuntime',
        },
      },
    },
  },
});
