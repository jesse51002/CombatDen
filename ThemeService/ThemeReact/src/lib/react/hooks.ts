// The React bindings over the store. No Dart counterpart file: in Flutter the
// equivalent is `ListenableBuilder(listenable: ThemeRuntime.changes)` wrapped
// around the tree, and the resolvers in ../../ThemeFlutter/lib/theme/*.dart are
// then called directly inside `build`.
//
// Each hook below is exactly "subscribe to the store, then call the matching
// resolver from ../theme/resolvers.ts". The resolvers stay usable outside React
// (a token module, an imperative canvas draw); these just add the re-render.

import { useEffect, useSyncExternalStore } from 'react';

import type { ColorMode } from '../models/colorMode';
import type { ThemeConfig } from '../models/themeConfig';
import { getThemeSnapshot, subscribeTheme } from '../store/locator';
import type { ThemeSnapshot } from '../store/themeStore';
import type { Rgba } from '../theme/color';
import { loadFontFamily } from '../theme/fontLoader';
import {
  themeColor,
  themeDesignName,
  themeFontFamily,
  themeIconUrl,
  themeImageSrc,
  themeMode,
  themePaletteEntry,
  themeText,
  themeToken,
} from '../theme/resolvers';

/**
 * The whole store snapshot, re-rendering on every theme change.
 *
 * `getThemeSnapshot` returns a CACHED reference — a fresh object literal per
 * call makes `useSyncExternalStore` throw "The result of getSnapshot should be
 * cached" and then loop forever. The third argument is the server snapshot:
 * the same function, because the pre-bootstrap snapshot is a frozen constant
 * and is exactly what an SSR render should see.
 */
export function useThemeSnapshot(): ThemeSnapshot {
  return useSyncExternalStore(subscribeTheme, getThemeSnapshot, getThemeSnapshot);
}

/**
 * Subscribes the caller to theme changes without reading the snapshot — for the
 * hooks below, which re-render on a change but read their value through the
 * plain resolver so the resolver stays the single lookup implementation.
 */
function useThemeChanges(): void {
  useThemeSnapshot();
}

/** The loaded theme, or `null` when nothing has loaded. */
export function useThemeConfig(): ThemeConfig | null {
  return useThemeSnapshot().config;
}

/** Whether the bootstrap has settled. What `<ThemeProvider>` gates on. */
export function useThemeReady(): boolean {
  return useThemeSnapshot().isReady;
}

/** The active design's id and human name, for marking a style in a picker. */
export function useActiveDesign(): { id: string | null; name: string | null } {
  const snapshot = useThemeSnapshot();
  const name = snapshot.config?.designName ?? '';
  return { id: snapshot.activeDesignId, name: name === '' ? null : name };
}

export interface ThemeColorQuery {
  /** A `ThemeDerivation` key, for a pre-computed variant of the slot. */
  derivation?: string;
  /** Returned whenever the slot, the derivation, or the theme itself is absent. */
  fallback: Rgba;
}

/** A colour slot, optionally one of its seven derivations. */
export function useThemeColor(slot: string, { derivation, fallback }: ThemeColorQuery): Rgba {
  useThemeChanges();
  return themeColor(slot, fallback, derivation);
}

/** An entry on the flat palette — the orphan tokens (`card`/`popup`/`divider`). */
export function useThemePaletteEntry(key: string, fallback: Rgba): Rgba {
  useThemeChanges();
  return themePaletteEntry(key, fallback);
}

/** Any palette ROLE key, checking the flat palette then the typed colours. */
export function useThemeToken(key: string, fallback: Rgba): Rgba {
  useThemeChanges();
  return themeToken(key, fallback);
}

/** The loaded theme's light/dark mode. */
export function useThemeMode(fallback: ColorMode = 'dark'): ColorMode {
  useThemeChanges();
  return themeMode(fallback);
}

/** Brand-rewritten copy for a text slot. */
export function useThemeText(slot: string, fallback: string): string {
  useThemeChanges();
  return themeText(slot, fallback);
}

/** The loaded theme's design name (e.g. "Apex MMA"). */
export function useThemeDesignName(fallback = ''): string {
  useThemeChanges();
  return themeDesignName(fallback);
}

/**
 * The Google Fonts family for a font slot, ALSO injecting its stylesheet.
 *
 * The injection is the web's replacement for `GoogleFonts.getFont`, which
 * fetches the family itself. Doing it here rather than making every call site
 * remember `loadFontFamily` is the difference between a themed font and a
 * silent fall-through to system-ui.
 */
export function useThemeFontFamily(slot: string, fallback: string): string {
  useThemeChanges();
  const family = themeFontFamily(slot, fallback);
  useEffect(() => {
    loadFontFamily(family);
  }, [family]);
  return family;
}

/**
 * The absolute URL for an image slot, or `fallback`. Prefer `<ThemedImage>`,
 * which additionally degrades when the resolved URL itself 404s.
 */
export function useThemeImageSrc(slot: string, fallback = ''): string {
  useThemeChanges();
  return themeImageSrc(slot, fallback);
}

/** The absolute SVG URL for an icon slot, or `null`. */
export function useThemeIconUrl(slot: string): string | null {
  useThemeChanges();
  return themeIconUrl(slot);
}
