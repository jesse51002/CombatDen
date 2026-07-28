// The inspector's reading of a `ThemeConfig` — pure, no React, no DOM.
//
// No Dart counterpart: the Flutter side has no artifact inspector. What it
// ports instead is an ATTITUDE from ../showcase/ — the resolvers hand back
// whatever the theme happens to carry, and the surface decides what an absent
// slot looks like. Here that decision is "say it was not produced", so every
// list below is built from the EXPECTED slot manifest rather than from the
// payload's own keys: a theme missing `giftbox` must show a gap, not a shorter
// grid, or the page quietly under-reports what the pipeline owes.
//
// Everything here is a pure function of the config so the whole reading is
// testable without a browser (see ./__tests__/artifactModel.test.ts).

import type { Rgba, ThemeConfig } from 'theme-react';
import { alphaBlend, rgba, ThemeDerivation } from 'theme-react';

import {
  EXPECTED_COLORS,
  EXPECTED_FONTS,
  EXPECTED_ICONS,
  EXPECTED_IMAGES,
  EXPECTED_TEXT,
} from '../showcase/showcaseSlots';

/**
 * The seven derivations in the order the wire and `ThemeDerivation` state them.
 *
 * Deliberately the CONTRACT order, not a tonal sort: two roles read side by
 * side on this page, and a per-role sort would put `dark` under `light` on one
 * and not the other, which is exactly the comparison the ladder exists for.
 */
export const DERIVATION_ORDER: readonly string[] = Object.freeze([
  ThemeDerivation.second,
  ThemeDerivation.third,
  ThemeDerivation.card,
  ThemeDerivation.popup,
  ThemeDerivation.dark,
  ThemeDerivation.light,
  ThemeDerivation.regularText,
]);

/**
 * The palette keys that belong to no colour slot — the shared surface tokens
 * the service ships alongside the `<slot>_<derivation>` pairs. Listed so the
 * manifest can name them as a group rather than leaving them as leftovers.
 */
export const SHARED_PALETTE_KEYS: readonly string[] = Object.freeze([
  'card',
  'popup',
  'divider',
]);

/** Drawn under every translucent specimen, and behind every asset plate. */
const FALLBACK_BACKGROUND: Rgba = rgba(22, 24, 29, 1);
/** The ink written on a light specimen — the chrome's own, never pure black. */
const DARK_INK: Rgba = rgba(22, 24, 29, 1);
/** The ink written on a dark specimen. */
const LIGHT_INK: Rgba = rgba(255, 255, 255, 1);

export interface DerivationView {
  readonly key: string;
  /** `null` when the pipeline produced no value for this derivation. */
  readonly color: Rgba | null;
}

export interface RoleView {
  readonly slot: string;
  /** The pipeline's name for the colour, e.g. "Red Corner". */
  readonly displayName: string;
  /** The pipeline's written purpose for the colour. The point of this page. */
  readonly description: string;
  readonly color: Rgba | null;
  readonly derivations: readonly DerivationView[];
  /**
   * The role's own `regular_text` derivation — the colour the pipeline picked
   * for words painted ON this one. Used to label the role's field, which is
   * both the honest label colour and a demonstration of the derivation.
   */
  readonly onColor: Rgba | null;
}

export interface PaletteEntry {
  readonly key: string;
  readonly color: Rgba;
}

export interface PaletteGroup {
  readonly label: string;
  readonly entries: readonly PaletteEntry[];
}

export interface SlotView<T> {
  readonly slot: string;
  /** `null` when the slot is absent from the payload. */
  readonly value: T | null;
}

export interface ArtifactCounts {
  readonly roles: number;
  readonly derivations: number;
  readonly paletteTokens: number;
  readonly images: number;
  readonly fonts: number;
  readonly texts: number;
  readonly icons: number;
}

export interface Inspection {
  readonly appId: string;
  readonly displayName: string;
  readonly designName: string;
  readonly colorMode: 'light' | 'dark';
  /** The theme's own ground. Every specimen plate is painted with it. */
  readonly background: Rgba;
  readonly roles: readonly RoleView[];
  readonly paletteGroups: readonly PaletteGroup[];
  readonly images: readonly SlotView<string>[];
  readonly fonts: readonly SlotView<string>[];
  readonly texts: readonly SlotView<string>[];
  readonly icons: readonly SlotView<string>[];
  readonly counts: ArtifactCounts;
}

/** `#rrggbb`, or `#rrggbbaa` when the colour is translucent. */
export function hexOf(color: Rgba): string {
  const body = `#${byteHex(color.r)}${byteHex(color.g)}${byteHex(color.b)}`;
  return color.a >= 1 ? body : `${body}${byteHex(Math.round(color.a * 255))}`;
}

function byteHex(value: number): string {
  return Math.max(0, Math.min(255, Math.round(value))).toString(16).padStart(2, '0');
}

/**
 * WCAG relative luminance (sRGB), ignoring alpha — composite first with
 * `over()` if the colour is translucent.
 */
export function relativeLuminance(color: Rgba): number {
  return (
    0.2126 * channelLuminance(color.r) +
    0.7152 * channelLuminance(color.g) +
    0.0722 * channelLuminance(color.b)
  );
}

function channelLuminance(value: number): number {
  const c = Math.max(0, Math.min(255, value)) / 255;
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

/** WCAG contrast ratio, 1–21. */
export function contrastRatio(a: Rgba, b: Rgba): number {
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  const [hi, lo] = la >= lb ? [la, lb] : [lb, la];
  return (hi + 0.05) / (lo + 0.05);
}

/**
 * The readable ink for a caption written on an arbitrary generated colour —
 * whichever of white / the chrome's near-black contrasts better.
 *
 * Contrast RATIO rather than HSL lightness on purpose: lightness calls a
 * saturated yellow (`hsl(50 100% 50%)`) "mid" and hands it white text at 1.9:1,
 * where luminance correctly reads it as bright and hands it ink at 12:1. Only
 * used where the pipeline gave us nothing better — a role's own `regular_text`
 * derivation always wins, because that is the colour it was computed to be.
 */
export function readableInk(color: Rgba): Rgba {
  return contrastRatio(LIGHT_INK, color) >= contrastRatio(DARK_INK, color)
    ? LIGHT_INK
    : DARK_INK;
}

/**
 * Composites a (possibly translucent) generated colour over the theme's own
 * ground, which is what the member app paints it on.
 *
 * Load-bearing for honesty, not polish: `primary_card` is the brand colour at
 * 12.6% alpha. Drawn straight onto this page's near-white chrome it renders a
 * pale tint that exists nowhere in the product; drawn over the theme's black
 * ground it renders the dim panel a member actually sees.
 */
export function over(color: Rgba, background: Rgba): Rgba {
  return alphaBlend(color, background);
}

/** A palette key, then the typed colour map — the resolvers' own ladder. */
function tokenOf(config: ThemeConfig, key: string, fallback: Rgba): Rgba {
  return config.palette[key] ?? config.colors[key]?.color ?? fallback;
}

/** Builds the whole reading. Never throws; every absence becomes a `null`. */
export function buildInspection(config: ThemeConfig): Inspection {
  const background = tokenOf(config, 'background', FALLBACK_BACKGROUND);
  const roles = EXPECTED_COLORS.map((slot) => roleView(config, slot));
  const images = slotViews(EXPECTED_IMAGES, config.images);
  const fonts = slotViews(EXPECTED_FONTS, config.fonts);
  const texts = slotViews(EXPECTED_TEXT, config.texts);
  const icons = slotViews(EXPECTED_ICONS, config.icons);

  return {
    appId: config.app,
    displayName: config.displayName,
    designName: config.designName,
    colorMode: config.colorMode,
    background,
    roles,
    paletteGroups: groupPalette(config.palette),
    images,
    fonts,
    texts,
    icons,
    counts: {
      roles: roles.filter((role) => role.color !== null).length,
      derivations: roles.reduce(
        (total, role) => total + role.derivations.filter((d) => d.color !== null).length,
        0,
      ),
      paletteTokens: Object.keys(config.palette).length,
      images: present(images),
      fonts: present(fonts),
      texts: present(texts),
      icons: present(icons),
    },
  };
}

function present<T>(views: readonly SlotView<T>[]): number {
  return views.filter((view) => view.value !== null).length;
}

function roleView(config: ThemeConfig, slot: string): RoleView {
  const value = config.colors[slot];
  return {
    slot,
    displayName: value?.displayName ?? '',
    description: value?.description ?? '',
    color: value?.color ?? null,
    onColor: value?.derivations[ThemeDerivation.regularText] ?? null,
    derivations: DERIVATION_ORDER.map((key) => ({
      key,
      color: value?.derivations[key] ?? null,
    })),
  };
}

function slotViews(
  slots: readonly string[],
  source: Readonly<Record<string, string>>,
): readonly SlotView<string>[] {
  return slots.map((slot) => {
    const value = source[slot];
    return { slot, value: value === undefined || value === '' ? null : value };
  });
}

/**
 * The flat palette, ordered as `<role>` + its seven `<role>_<derivation>` keys,
 * then the shared surface tokens, then anything the service added that this
 * client does not know about.
 *
 * That last group is the point of doing this by subtraction rather than by a
 * fixed key list: a new token appearing on the wire shows up on the page as a
 * new token, instead of being silently dropped by a client that was built
 * before it existed.
 */
export function groupPalette(palette: Readonly<Record<string, Rgba>>): readonly PaletteGroup[] {
  const groups: PaletteGroup[] = [];
  const claimed = new Set<string>();

  for (const slot of EXPECTED_COLORS) {
    const keys = [slot, ...DERIVATION_ORDER.map((derivation) => `${slot}_${derivation}`)];
    const entries = collect(palette, keys, claimed);
    if (entries.length > 0) groups.push({ label: slot, entries });
  }

  const shared = collect(palette, SHARED_PALETTE_KEYS, claimed);
  if (shared.length > 0) groups.push({ label: 'shared', entries: shared });

  const rest = Object.keys(palette)
    .filter((key) => !claimed.has(key))
    .sort();
  const extra = collect(palette, rest, claimed);
  if (extra.length > 0) groups.push({ label: 'other', entries: extra });

  return groups;
}

function collect(
  palette: Readonly<Record<string, Rgba>>,
  keys: readonly string[],
  claimed: Set<string>,
): PaletteEntry[] {
  const entries: PaletteEntry[] = [];
  for (const key of keys) {
    const color = palette[key];
    if (color === undefined || claimed.has(key)) continue;
    claimed.add(key);
    entries.push({ key, color });
  }
  return entries;
}

export interface SpectrumBand {
  readonly role: string;
  readonly key: string;
  readonly color: Rgba;
}

/**
 * Every produced derivation, flattened in role order — the masthead band.
 *
 * Base colours are deliberately EXCLUDED: the band's claim is "seven variants
 * per role, computed", and the four bases are already the four fields below it.
 * Translucent values arrive composited over the theme's ground, so the band
 * shows rendered colour rather than a swatch that only exists in the payload.
 */
export function spectrumBands(
  roles: readonly RoleView[],
  background: Rgba,
): readonly SpectrumBand[] {
  const bands: SpectrumBand[] = [];
  for (const role of roles) {
    for (const derivation of role.derivations) {
      if (derivation.color === null) continue;
      bands.push({
        role: role.slot,
        key: derivation.key,
        color: over(derivation.color, background),
      });
    }
  }
  return bands;
}
