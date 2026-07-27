// The bootstrap gate. Ports the CALL SITE of
// ../../ThemeFlutter/lib/customization_runtime.dart's `initialize` — i.e. the
// `FutureBuilder` in ../../../CRM/lib/features/.../live_theme_preview_tab.dart,
// which awaits the runtime before it lets the preview render.
//
// IT IS NOT A CONTEXT VALUE CARRIER. The store is a module singleton, exactly
// as `get_it` is on the Flutter side, so the theme does NOT flow down through
// React context — every hook reads the singleton via `useSyncExternalStore`.
// That is what lets the non-hook resolvers (`themeColor`, `themeText`, …) work
// identically outside a component, which a token module needs.
//
// So this component does exactly two things: kick the bootstrap, and hold the
// tree back until it has settled.

import type { ReactNode } from 'react';
import { useEffect } from 'react';

import type { InitializeThemeOptions } from '../runtime';
import { initializeTheme } from '../runtime';

import { useThemeReady } from './hooks';

export interface ThemeProviderProps extends InitializeThemeOptions {
  children: ReactNode;
  /**
   * Rendered while the bootstrap is in flight. Defaults to nothing.
   *
   * Keep it cheap and unbranded: it is on screen for one network round trip at
   * most, and only on a visitor's FIRST load — after that the localStorage
   * last-good copy is adopted before the fetch even starts.
   */
  fallback?: ReactNode;
}

/** No-slot default. A module constant so the effect's deps stay stable. */
const NO_KEYS: readonly string[] = Object.freeze([]);

export function ThemeProvider({
  children,
  fallback = null,
  appId,
  designId,
  themeBaseUrl,
  livePreview = false,
  expectedColors = NO_KEYS,
  expectedImages = NO_KEYS,
  expectedFonts = NO_KEYS,
  expectedText = NO_KEYS,
  expectedIcons = NO_KEYS,
}: ThemeProviderProps) {
  const ready = useThemeReady();

  useEffect(() => {
    // `initializeTheme` memoises its promise, so a re-run (a caller passing
    // fresh array literals every render, a StrictMode double-mount, a second
    // provider in the tree) is a cheap no-op rather than a second fetch.
    void initializeTheme({
      appId,
      designId,
      livePreview,
      expectedColors,
      expectedImages,
      expectedFonts,
      expectedText,
      expectedIcons,
      ...(themeBaseUrl === undefined ? {} : { themeBaseUrl }),
    });
  }, [
    appId,
    designId,
    themeBaseUrl,
    livePreview,
    expectedColors,
    expectedImages,
    expectedFonts,
    expectedText,
    expectedIcons,
  ]);

  return <>{ready ? children : fallback}</>;
}
