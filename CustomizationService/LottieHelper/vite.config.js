import { defineConfig } from 'vite';

// Relative base so the built dist/ opens from any path (incl. file://).
export default defineConfig({
  base: './',
  build: { outDir: 'dist', emptyOutDir: true },
});
