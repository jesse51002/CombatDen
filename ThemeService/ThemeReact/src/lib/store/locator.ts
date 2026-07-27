// Ports ../../ThemeFlutter/lib/service_locator.dart.
//
// Dart needs `get_it` because a Flutter app has no module-level mutable state
// worth the name; an ES module IS a singleton, so the locator is just this
// file's top-level binding. Same job either way: the context-free resolvers
// (`themeColor`, `themeImageSrc`, …) must reach the loaded store from anywhere,
// including from outside a React component.
//
// App code never touches this — bootstrap via `initializeTheme` (../runtime.ts).

import type { ThemeSnapshot, ThemeStore } from './themeStore';
import { EMPTY_THEME_SNAPSHOT } from './themeStore';

let store: ThemeStore | null = null;

/** Fired when the STORE ITSELF is swapped, as opposed to its contents changing. */
const registrationListeners = new Set<() => void>();

/** The registered store, or `null` before bootstrap. Every resolver's guard. */
export function themeStoreOrNull(): ThemeStore | null {
  return store;
}

/** Registers the store built by `initializeTheme`. Internal. */
export function registerThemeStore(next: ThemeStore): void {
  store = next;
  for (const listener of [...registrationListeners]) listener();
}

/**
 * Drops the registered store, returning the locator to its pre-bootstrap state;
 * every resolver goes back to returning its caller's fallback.
 *
 * Internal — call `resetThemeRuntime()` (../runtime.ts) instead. Clearing the
 * store WITHOUT clearing the memoised bootstrap promise leaves the runtime
 * permanently dead: the next `initializeTheme` would hand back the settled old
 * promise and never register a store again.
 */
export function clearThemeStore(): void {
  store = null;
  for (const listener of [...registrationListeners]) listener();
}

/** Whether `initializeTheme` has settled. Ports `ThemeRuntime.isReady`. */
export function isThemeReady(): boolean {
  return store?.getSnapshot().isReady ?? false;
}

/**
 * The active snapshot — the store's cached one, or the frozen empty one before
 * bootstrap (the SAME constant a freshly-built store starts on, so registering
 * one changes no reference until it actually loads something). Always a stable
 * reference between changes, which is the `useSyncExternalStore` contract.
 */
export function getThemeSnapshot(): ThemeSnapshot {
  return store?.getSnapshot() ?? EMPTY_THEME_SNAPSHOT;
}

/**
 * Subscribes to theme changes across the bootstrap boundary.
 *
 * A component can mount BEFORE any store exists (that is the normal case — the
 * provider's children render on the very first paint), so this cannot simply
 * forward to `store.subscribe`. It tracks store registration too, and re-points
 * the caller's listener at whatever store is current.
 */
export function subscribeTheme(listener: () => void): () => void {
  let unsubscribeStore = store?.subscribe(listener) ?? null;
  const onRegistration = (): void => {
    unsubscribeStore?.();
    unsubscribeStore = store?.subscribe(listener) ?? null;
    listener();
  };
  registrationListeners.add(onRegistration);
  return () => {
    registrationListeners.delete(onRegistration);
    unsubscribeStore?.();
  };
}
