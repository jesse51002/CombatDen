// The context-free resolvers. Ports, in one file, the five static Dart classes
// ../../ThemeFlutter/lib/theme/{theme_color,theme_image,theme_font,theme_text,
// theme_icon}.dart — each of which is a private-constructor class holding two
// or three statics, i.e. a namespace. TypeScript spells a namespace as exported
// functions, so keeping the five apart would leave five one-function files.
//
// THE ONE INVARIANT, and it is why every one of these takes a `fallback`:
// A RESOLVER NEVER THROWS. Every path degrades — no store registered (nothing
// bootstrapped yet, or a test), nothing loaded (offline first visit), the slot
// absent, the slot present but empty/unparseable — all return the caller's
// fallback. Call sites are consequently written flat, with no guards.

import type { ColorMode } from '../models/colorMode';
import { themeStoreOrNull } from '../store/locator';

import type { Rgba } from './color';

/**
 * Resolves a colour slot. With no `derivation`, the base colour; with one (e.g.
 * `ThemeDerivation.card`), that pre-computed variant from
 * `colors[slot].derivations`. Ports `ThemeColor.color`.
 */
export function themeColor(
  slot: string,
  fallback: Rgba,
  derivation?: string | undefined,
): Rgba {
  const value = themeStoreOrNull()?.current?.colors[slot];
  if (value === undefined) return fallback;
  if (derivation === undefined) return value.color ?? fallback;
  return value.derivations[derivation] ?? fallback;
}

/**
 * Looks up an entry on the flat `color_set.palette` — every
 * `<slot>_<derivation>` pair the service pre-computes plus the shared surface
 * tokens (`card`, `popup`, `divider`). Ports `ThemeColor.paletteEntry`.
 *
 * For a base-slot + derivation pair prefer `themeColor(slot, fb, derivation)`,
 * which goes through the typed slot map; use this only for the orphan tokens
 * that have no base slot.
 */
export function themePaletteEntry(key: string, fallback: Rgba): Rgba {
  return themeStoreOrNull()?.current?.palette[key] ?? fallback;
}

/**
 * Resolves an arbitrary palette ROLE key, checking BOTH stores: the flat
 * palette (derived/shared tokens like `primary_third`, `card`) and the typed
 * colors map (base roles like `primary`, `accent`). Ports `ThemeColor.token`.
 *
 * This is the resolver for keys whose store is not known up front. For known
 * base slots use `themeColor`; for known orphan tokens use `themePaletteEntry`.
 */
export function themeToken(key: string, fallback: Rgba): Rgba {
  const config = themeStoreOrNull()?.current;
  if (!config) return fallback;
  return config.palette[key] ?? config.colors[key]?.color ?? fallback;
}

/** The loaded theme's light/dark mode. Ports `ThemeColor.mode`. */
export function themeMode(fallback: ColorMode = 'dark'): ColorMode {
  return themeStoreOrNull()?.current?.colorMode ?? fallback;
}

/**
 * The absolute URL for an image slot, or `fallback` when no theme applies to it
 * (nothing bootstrapped, nothing loaded, slot absent, or empty URL). Ports
 * `ThemeImage.image` — minus the provider, which is a `src` string on the web.
 *
 * The runtime deliberately does NOT own a fallback image: white-label tenants
 * keep their default assets bundled in their own build, so the theme is a pure
 * live override. Wrap in `<ThemedImage>` to also degrade when the resolved URL
 * itself 404s — the analogue of Dart's `FallbackImageProvider`.
 */
export function themeImageSrc(slot: string, fallback = ''): string {
  const store = themeStoreOrNull();
  const raw = store?.current?.images[slot] ?? '';
  if (raw === '') return fallback;
  return store?.resolveImageUrl(raw) ?? fallback;
}

/**
 * The absolute SVG URL for an icon slot, or `null` when no theme applies.
 * Ports `ThemeIcon.svgUrl`.
 */
export function themeIconUrl(slot: string): string | null {
  const store = themeStoreOrNull();
  const raw = store?.current?.icons[slot] ?? '';
  if (raw === '') return null;
  return store?.resolveImageUrl(raw) ?? null;
}

/**
 * The resolved Google Fonts family for a font slot. Ports `ThemeFont.style`'s
 * lookup half — the delivery half is `loadFontFamily` in ./fontLoader.ts,
 * because a browser needs the `@font-face` CSS injected before the family name
 * means anything, where Flutter's `google_fonts` package fetches on demand.
 */
export function themeFontFamily(slot: string, fallback: string): string {
  const family = themeStoreOrNull()?.current?.fonts[slot] ?? '';
  return family === '' ? fallback : family;
}

/**
 * Brand-rewritten copy for a text slot (e.g. `class_booked_headline` →
 * "You're in."). Ports `ThemeText.value`.
 */
export function themeText(slot: string, fallback: string): string {
  const value = themeStoreOrNull()?.current?.texts[slot] ?? '';
  return value === '' ? fallback : value;
}

/**
 * The loaded theme's design name (e.g. "Apex MMA") — a top-level field, not a
 * text slot. Distinct from the app/brand name (`ThemeConfig.displayName`),
 * which is stable across an app's designs. Ports `ThemeText.designName`.
 */
export function themeDesignName(fallback = ''): string {
  const name = themeStoreOrNull()?.current?.designName ?? '';
  return name === '' ? fallback : name;
}
