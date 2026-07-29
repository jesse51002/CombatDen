import { fileURLToPath } from 'node:url';

import { defineConfig } from 'vitest/config';

// Kept separate from vite.config.ts (the APP build) so the two never constrain
// each other — the app's dev-server pinning has nothing to do with how the
// units are exercised.
//
// jsdom, not node: the runtime's fallback ladder is defined in terms of
// `localStorage`, and the asset warmer / icon probe in terms of `Image`. Testing
// the ladder against a hand-rolled storage stub would be testing the stub.
export default defineConfig({
  resolve: {
    alias: {
      // The app's tests import from `theme-react` exactly as app CODE does.
      // Without this alias the bare specifier resolves through package.json's
      // `exports` to `dist/`, so `npm run test` fails on a fresh clone with
      // "Failed to resolve entry for package" until someone happens to have
      // run a build first — and, worse, a stale `dist/` would silently test
      // the LAST build instead of the working tree.
      'theme-react': fileURLToPath(new URL('./src/lib/index.ts', import.meta.url)),
    },
  },
  test: {
    environment: 'jsdom',
    include: ['src/**/__tests__/**/*.test.ts', 'src/**/__tests__/**/*.test.tsx'],
    setupFiles: ['src/lib/__tests__/setup.ts'],
  },
});
