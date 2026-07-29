// Ports ../../ThemeFlutter/lib/customization_runtime.dart (`ThemeRuntime`).
//
// The one entry point a host needs: DI wiring, the network fetch and the
// localStorage last-good are all handled inside. The host never sees the
// locator, the client, or the store.
//
// App-agnostic: the only app-specific inputs are `appId` / `designId` and the
// expected slot ids. Dart holds these as static members on a private-constructor
// class; TypeScript spells the same namespace as exported functions.

import { ThemeApiClient } from './api/client';
import type { ThemeStylesPageQuery } from './api/client';
import type { ThemeStylesPage } from './models/themeStylesPage';
import { clearThemeStore, isThemeReady, registerThemeStore, themeStoreOrNull } from './store/locator';
import type { ThemeStoreOptions } from './store/themeStore';
import { ThemeStore } from './store/themeStore';

export interface InitializeThemeOptions extends ThemeStoreOptions {
  /** The ThemeService app whose catalog to load (e.g. `combatden`). */
  appId: string;
  /** The design to load before any sticky selection is found. */
  designId: string;
  /** Override the ThemeService base URL. Defaults per ./config.ts. */
  themeBaseUrl?: string;
}

/**
 * Memoised so a StrictMode double-mount, or two providers in one tree, boot the
 * runtime once instead of firing two identical startup fetches.
 *
 * This is also what ThemeFlutter does structurally — `getIt.isRegistered` gates
 * the wiring, so a second `initialize` with a DIFFERENT appId is ignored there
 * too. Use `resetThemeRuntime()` to genuinely start over.
 */
let bootstrap: Promise<void> | null = null;

/**
 * Boots the runtime: builds the client + store, registers them, and runs the
 * fallback ladder (localStorage last-good ► network ► defaults). Awaiting it
 * means the resolvers are branded from the first frame after.
 *
 * `livePreview` is accepted and DOES NOTHING on the web. In Flutter it swaps
 * the image provider for a RAM-only one so repeated admin-preview reloads do
 * not pile up disk-cache files; a browser has one HTTP cache and no API to opt
 * an image out of it. The flag stays on the signature so a call site ports over
 * from Flutter without a signature mismatch, and because cache-busting — the
 * part that actually matters — is server-side either way: every asset URL
 * carries a content-hash `?v=` token that changes only when the bytes change.
 *
 * Never throws.
 */
export function initializeTheme(options: InitializeThemeOptions): Promise<void> {
  bootstrap ??= (() => {
    const { appId, designId, themeBaseUrl, ...storeOptions } = options;
    const client = new ThemeApiClient(appId, designId, themeBaseUrl);
    const store = new ThemeStore(client, storeOptions);
    registerThemeStore(store);
    return store.initialize();
  })();
  return bootstrap;
}

/**
 * Tears the runtime fully down: forgets the memoised bootstrap AND drops the
 * registered store, so the next `initializeTheme` genuinely re-boots and every
 * resolver returns its caller's fallback in the meantime.
 *
 * The two halves are deliberately ONE call. Clearing either alone leaves the
 * runtime wedged — a cleared store with a live bootstrap promise can never
 * register again, and a cleared promise with a live store double-fetches.
 */
export function resetThemeRuntime(): void {
  bootstrap = null;
  clearThemeStore();
}

/** Whether `initializeTheme` has settled. Ports `ThemeRuntime.isReady`. */
export function themeIsReady(): boolean {
  return isThemeReady();
}

/** The design currently loaded. Ports `ThemeRuntime.activeDesignId`. */
export function activeDesignId(): string | null {
  return themeStoreOrNull()?.activeDesignId ?? null;
}

/**
 * Switches the live style. Returns whether the switch took effect; never
 * throws, and on failure the current theme is left completely intact.
 * Ports `ThemeRuntime.selectDesign`.
 */
export function selectDesign(designId: string): Promise<boolean> {
  const store = themeStoreOrNull();
  if (!store) return Promise.resolve(false);
  return store.selectDesign(designId);
}

/**
 * One page of the app's selectable styles. Ports
 * `ThemeRuntime.fetchStylesPage`. Rejects when nothing is bootstrapped.
 */
export function fetchStylesPage(query: ThemeStylesPageQuery = {}): Promise<ThemeStylesPage> {
  const store = themeStoreOrNull();
  if (!store) {
    return Promise.reject(new Error('theme-react: no theme runtime; call initializeTheme first'));
  }
  return store.fetchStylesPage(query);
}

/** Absolutises a raw slot URL against the configured ThemeService base. */
export function resolveImageUrl(raw: string): string {
  return themeStoreOrNull()?.resolveImageUrl(raw) ?? raw;
}

/**
 * The same functions grouped as one object, so a call site ports across from
 * Dart verbatim (`ThemeRuntime.initialize(...)`, `ThemeRuntime.selectDesign(id)`).
 *
 * The individual named exports above are the preferred form in JS — they
 * tree-shake, this object cannot — so both exist. Dart's `isReady` /
 * `activeDesignId` are getters and are functions here; that is the only shape
 * difference.
 */
export const ThemeRuntime = Object.freeze({
  initialize: initializeTheme,
  isReady: themeIsReady,
  activeDesignId,
  selectDesign,
  fetchStylesPage,
  resolveImageUrl,
  reset: resetThemeRuntime,
});
