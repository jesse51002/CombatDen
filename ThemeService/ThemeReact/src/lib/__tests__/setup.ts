// Vitest setup. NOT a test file (the runner's `include` is `*.test.ts`).
//
// Node 26 ships its own `globalThis.localStorage`, and it is a getter that
// returns `undefined` unless the process was started with `--localstorage-file`.
// Vitest's jsdom environment copies the jsdom window onto `globalThis`, but
// Node's built-in getter wins — so `window.localStorage` is `undefined` under
// the runner even though jsdom implements it. That is an environment collision,
// not a runtime bug: in a real browser `window.localStorage` is the real store,
// which is exactly what ../store/persistence.ts reads.
//
// Installing a spec-shaped in-memory Storage here keeps the persistence tests
// testing the real code path (`window.localStorage`) instead of a stub injected
// into the library.

class MemoryStorage implements Storage {
  private entries = new Map<string, string>();

  get length(): number {
    return this.entries.size;
  }

  key(index: number): string | null {
    return [...this.entries.keys()][index] ?? null;
  }

  getItem(key: string): string | null {
    return this.entries.get(key) ?? null;
  }

  setItem(key: string, value: string): void {
    this.entries.set(key, String(value));
  }

  removeItem(key: string): void {
    this.entries.delete(key);
  }

  clear(): void {
    this.entries.clear();
  }
}

if (typeof window !== 'undefined' && !window.localStorage) {
  Object.defineProperty(window, 'localStorage', {
    value: new MemoryStorage(),
    configurable: true,
    writable: true,
  });
}
