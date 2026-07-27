import { defineConfig } from 'vitest/config';

// Kept separate from vite.config.ts (the APP build) so the two never constrain
// each other — the app's `resolve.alias` and dev-server pinning have nothing to
// do with how the library's units are exercised.
//
// jsdom, not node: the runtime's fallback ladder is defined in terms of
// `localStorage`, and the asset warmer / icon probe in terms of `Image`. Testing
// the ladder against a hand-rolled storage stub would be testing the stub.
export default defineConfig({
  test: {
    environment: 'jsdom',
    include: ['src/**/__tests__/**/*.test.ts', 'src/**/__tests__/**/*.test.tsx'],
    setupFiles: ['src/lib/__tests__/setup.ts'],
  },
});
