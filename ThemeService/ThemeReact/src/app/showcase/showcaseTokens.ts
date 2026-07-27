// Ports ../../../../../CRM/lib/showcase/showcase_tokens.dart (`ShowcaseTokens`).
//
// THE SECOND TOKEN SYSTEM. This is a live-resolved mirror of the MEMBER app's
// `DesignConstants` — the phone's own design language — and it is NOT the admin
// chrome's token set. The two share token NAMES with different VALUES:
// `radiusBig` is **32** here and **12** in ../tokens/adminTokens.ts. They live
// in separate modules and separate CSS-variable namespaces (`--sc-*` here,
// `--gw-*` / `--adm-*` there) and neither may import the other; eslint.config.js
// Gates 2a/2b are the enforcement. Never "unify" them.
//
// Everything brandable resolves LIVE through the library's NON-HOOK resolvers
// (`themeColor`, `themePaletteEntry`, `themeFontFamily`) — they exist precisely
// so a token module can read the theme from outside a component, which is what
// lets this file be a plain module rather than a hook. The hardcoded values are
// CombatDen's verbatim fallbacks, used only when nothing has loaded.
//
// The output is `showcaseCssVars`, the ~67 `--sc-*` custom properties
// ./ShowcaseThemeVars.tsx writes onto ONE element. Every showcase `.module.css`
// reads `var(--sc-…)` and nothing else, so a theme switch re-skins all seven
// screens by rewriting variables on that single element.
//
// TWO PORTING RULES THIS FILE OBEYS, both from ../../../CLAUDE.md:
//
//   * `letterSpacing` ports as **px**, never `em`. Flutter's letterSpacing is an
//     absolute logical-pixel value that does not scale with font size; CSS `em`
//     does. `h1` is `letterSpacing: -0.02` at 24px → `-0.02px`. Writing
//     `-0.02em` would be `-0.48px`, ~24x tighter.
//   * No numeric `line-height` anywhere. Flutter leaves `height:` unset in this
//     whole ramp, which means the font's own metrics — CSS `line-height: normal`.
//     Every type shorthand below therefore spells `/normal` explicitly.

import type { CSSProperties } from 'react';
import type { Rgba, ThemeSnapshot } from 'theme-react';
import {
  ThemeDerivation,
  alphaBlend,
  fontStack,
  hslLightness,
  rgba,
  themeColor,
  themeFontFamily,
  themePaletteEntry,
  toCss,
  withAlpha,
} from 'theme-react';

import {
  SLOT_ACCENT,
  SLOT_BACKGROUND,
  SLOT_FONT_BODY,
  SLOT_FONT_DISPLAY,
  SLOT_PRIMARY,
  SLOT_TEXT,
} from './showcaseSlots';

// ---------------------------------------------------------------------------
// CombatDen verbatim fallbacks — used only when no theme loads.
// ---------------------------------------------------------------------------

/** `Color(0xFFFF6C2D)`. */
const FALLBACK_PRIMARY: Rgba = rgba(0xff, 0x6c, 0x2d);
/** `Color(0xFF121619)`. */
const FALLBACK_BACKGROUND: Rgba = rgba(0x12, 0x16, 0x19);
/** `Color(0xFFF4F3EE)`. */
const FALLBACK_TEXT: Rgba = rgba(0xf4, 0xf3, 0xee);
/** `Color(0xFFE1B75C)`. Kept for parity; `accent` is the only reader. */
const FALLBACK_ACCENT: Rgba = rgba(0xe1, 0xb7, 0x5c);
/** `_fallbackFontFamily`. */
export const FALLBACK_FONT_FAMILY = 'Jura';

/** Opaque white — the base of `_liveSurfaceFallback`'s `Colors.white`. */
const WHITE: Rgba = rgba(0xff, 0xff, 0xff);

// ---------------------------------------------------------------------------
// HSL, the two functions Flutter hands `ShowcaseTokens` for free.
// ---------------------------------------------------------------------------
//
// `hslLightness` (the read) is exported by the library. The WRITE half —
// `HSLColor.fromColor(c).withLightness(l).toColor()`, which `_darkPrimaryFallback`
// needs — has no counterpart there, because nothing in the runtime re-lights a
// colour. It is ported here rather than pushed into the library: the library is
// the app-agnostic runtime and this is one app's fallback maths.

/** Flutter's `HSLColor.fromColor(c).hue`, in degrees. */
function hslHue(color: Rgba): number {
  const r = color.r / 0xff;
  const g = color.g / 0xff;
  const b = color.b / 0xff;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const delta = max - min;
  if (delta === 0 || max === 0) return 0;
  // Dart's `%` on doubles is always non-negative; JS's keeps the dividend's
  // sign, so the red branch needs the extra wrap to match `(x) % 6` in Dart.
  const hue =
    max === r
      ? 60 * (((((g - b) / delta) % 6) + 6) % 6)
      : max === g
        ? 60 * ((b - r) / delta + 2)
        : 60 * ((r - g) / delta + 4);
  return Number.isNaN(hue) ? 0 : hue;
}

/** Flutter's `HSLColor.fromColor(c).saturation`. */
function hslSaturation(color: Rgba): number {
  const r = color.r / 0xff;
  const g = color.g / 0xff;
  const b = color.b / 0xff;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const lightness = (max + min) / 2;
  if (lightness === 1) return 0;
  const raw = (max - min) / (1 - Math.abs(2 * lightness - 1));
  // Pure black divides 0 by 0. Dart's `clampDouble` maps NaN to its MAX, and
  // the value is multiplied by a zero chroma either way — match it anyway.
  if (Number.isNaN(raw)) return 1;
  return raw < 0 ? 0 : raw > 1 ? 1 : raw;
}

/**
 * Flutter's `HSLColor.fromColor(c).withLightness(l).toColor()` — the exact
 * chroma/secondary/match reconstruction `HSLColor.toColor` performs, so a
 * ported fallback lands on the same byte values as the Dart original.
 */
function withHslLightness(color: Rgba, lightness: number): Rgba {
  const l = lightness < 0 ? 0 : lightness > 1 ? 1 : lightness;
  const hue = hslHue(color);
  const saturation = hslSaturation(color);
  const chroma = (1 - Math.abs(2 * l - 1)) * saturation;
  const secondary = chroma * (1 - Math.abs(((hue / 60) % 2) - 1));
  const match = l - chroma / 2;
  let r: number;
  let g: number;
  let b: number;
  if (hue < 60) {
    [r, g, b] = [chroma, secondary, 0];
  } else if (hue < 120) {
    [r, g, b] = [secondary, chroma, 0];
  } else if (hue < 180) {
    [r, g, b] = [0, chroma, secondary];
  } else if (hue < 240) {
    [r, g, b] = [0, secondary, chroma];
  } else if (hue < 300) {
    [r, g, b] = [secondary, 0, chroma];
  } else {
    [r, g, b] = [chroma, 0, secondary];
  }
  return rgba((r + match) * 0xff, (g + match) * 0xff, (b + match) * 0xff, color.a);
}

// ---------------------------------------------------------------------------
// Brand colours (resolved live)
// ---------------------------------------------------------------------------

export function primaryColor(): Rgba {
  return themeColor(SLOT_PRIMARY, FALLBACK_PRIMARY);
}

export function backgroundColor(): Rgba {
  return themeColor(SLOT_BACKGROUND, FALLBACK_BACKGROUND);
}

export function text(): Rgba {
  return themeColor(SLOT_TEXT, FALLBACK_TEXT);
}

/** Selection / active-state accent. */
export function accent(): Rgba {
  return themeColor(SLOT_ACCENT, FALLBACK_ACCENT);
}

// ---------------------------------------------------------------------------
// Derived tokens
// ---------------------------------------------------------------------------

export function primaryColor50(): Rgba {
  return themeColor(SLOT_PRIMARY, withAlpha(FALLBACK_PRIMARY, 0.5), ThemeDerivation.third);
}

export function darkPrimary(): Rgba {
  return themeColor(SLOT_PRIMARY, darkPrimaryFallback(), ThemeDerivation.dark);
}

/** `_darkPrimaryFallback`: the fallback primary re-lit to 42% of its lightness. */
function darkPrimaryFallback(): Rgba {
  return withHslLightness(FALLBACK_PRIMARY, hslLightness(FALLBACK_PRIMARY) * 0.42);
}

export function primaryCard(): Rgba {
  return themeColor(SLOT_PRIMARY, withAlpha(FALLBACK_PRIMARY, 0.09), ThemeDerivation.card);
}

export function primaryButtonText(): Rgba {
  return themeColor(SLOT_PRIMARY, FALLBACK_TEXT, ThemeDerivation.regularText);
}

export function text2nd(): Rgba {
  return themeColor(SLOT_TEXT, withAlpha(FALLBACK_TEXT, 0.75), ThemeDerivation.second);
}

export function text3rd(): Rgba {
  return themeColor(SLOT_TEXT, withAlpha(FALLBACK_TEXT, 0.5), ThemeDerivation.third);
}

export function card(): Rgba {
  return themePaletteEntry('card', liveSurfaceFallback());
}

export function popup(): Rgba {
  return themePaletteEntry('popup', alphaBlend(liveSurfaceFallback(), backgroundColor()));
}

export function divider(): Rgba {
  return themePaletteEntry('divider', dividerFallback());
}

/**
 * `_liveSurfaceFallback`. Note it reads the LIVE `backgroundColor()`, not the
 * hardcoded fallback: a theme that ships `background` but no `card` still gets
 * a surface tuned to its own canvas. The alpha ramp is verbatim —
 * `0.06 + 0.5 * (lightness / 0.9)` — and `rgba()` clamps it at the top end.
 */
function liveSurfaceFallback(): Rgba {
  const l = hslLightness(backgroundColor());
  return withAlpha(WHITE, 0.06 + 0.5 * (l / 0.9));
}

/**
 * `divider`'s fallback: the live ink at an alpha that rises with how light the
 * canvas is, clamped to `[0.10, 0.22]`.
 */
function dividerFallback(): Rgba {
  const raw = 0.1 + 0.1 * hslLightness(backgroundColor());
  const alpha = raw < 0.1 ? 0.1 : raw > 0.22 ? 0.22 : raw;
  return withAlpha(text(), alpha);
}

// ---------------------------------------------------------------------------
// Status / semantic colours (NOT brandable)
// ---------------------------------------------------------------------------

export const HYPERLINK: Rgba = rgba(0x83, 0xc7, 0xff);
export const GOOD_GREEN: Rgba = rgba(0x74, 0xf3, 0x94);
export const OK_YELLOW: Rgba = rgba(0xcc, 0xce, 0x44);
export const BAD_RED: Rgba = rgba(0xf9, 0x4a, 0x4d);

// ---------------------------------------------------------------------------
// Layout / sizing. Plain numbers in logical px — the member app's scale, which
// is NOT the admin chrome's (radiusBig 32 here vs 12 there).
// ---------------------------------------------------------------------------

export const SC = Object.freeze({
  radiusBig: 32,
  radiusSmall: 16,
  radiusCircle: 1000,

  paddingBig: 32,
  paddingSmall: 16,

  spacingBig: 32,
  spacingLarge: 16,
  spacingMedium: 8,
  spacingSmall: 4,
  spacingTiny: 2,

  buttonBorder: 2,
  /**
   * Flutter's variable-icon-font weight AXIS, not a CSS length. It has no
   * direct CSS analogue (the showcase draws hand-built SVG glyphs, as
   * ../widgets/icons.tsx does for the chrome), so it is published unitless and
   * used as a STROKE width: 300/200 = 1.5px on a 24px glyph box.
   */
  iconWeight: 300,
  buttonBorderSize: 3,
  screenHorizontalPadding: 16,

  // Icon sizes (T-shirt scale, 16 + 4x).
  iconSizeXs: 16,
  iconSizeSm: 20,
  iconSizeMd: 24,
  iconSizeLg: 28,
  iconSizeXl: 32,
  iconSize2xl: 36,

  pillHeightSm: 24,
  pillHeightMd: 30,
  dividerThickness: 1,
});

// ---------------------------------------------------------------------------
// Typography
// ---------------------------------------------------------------------------

/** The resolved Google Fonts family for a font slot. */
export function displayFontFamily(): string {
  return themeFontFamily(SLOT_FONT_DISPLAY, FALLBACK_FONT_FAMILY);
}

export function bodyFontFamily(): string {
  return themeFontFamily(SLOT_FONT_BODY, FALLBACK_FONT_FAMILY);
}

/**
 * One rung of the ramp as a CSS `font` shorthand.
 *
 * `/normal` is the load-bearing part: Flutter leaves `height:` unset across the
 * whole ramp, so every one of these lines at the font's own metrics. Spelling
 * it out also means the shorthand cannot inherit a stray numeric line-height
 * from an ancestor.
 */
function typeShorthand(weight: number, sizePx: number, stack: string): string {
  return `${String(weight)} ${String(sizePx)}px/normal ${stack}`;
}

/** Flutter's absolute `letterSpacing`, in px. See the header. */
function letterSpacing(value: number): string {
  return `${String(value)}px`;
}

// ---------------------------------------------------------------------------
// The CSS variables
// ---------------------------------------------------------------------------

/** The `--sc-*` custom properties, ready for a `style` prop. */
export type ShowcaseCssVars = Readonly<Record<string, string>>;

/**
 * Every `--sc-*` variable the showcase island reads, resolved from whatever is
 * loaded right now.
 *
 * `theme` is not decoration. The resolvers read the module-singleton store,
 * which React cannot see — passing the snapshot is what makes this call a
 * function of the loaded theme for React's (and the React Compiler's
 * auto-memoisation's) purposes, so a `selectDesign` actually recomputes it. It
 * is also genuinely read, for the light/dark canvas flag.
 *
 * `displayFamily` / `bodyFamily` come in already resolved because the CALLER
 * must also have injected their `@font-face` stylesheets (`loadFontFamily`) —
 * a family name with no stylesheet behind it silently renders as system-ui.
 */
export function showcaseCssVars(
  theme: ThemeSnapshot,
  displayFamily: string,
  bodyFamily: string,
): ShowcaseCssVars {
  const bodyStack = fontStack(bodyFamily);
  const displayStack = fontStack(displayFamily);
  const px = (value: number): string => `${String(value)}px`;

  return {
    // --- Canvas ---
    // `ShowcaseTokens.isLightCanvas`, as a value CSS can branch on and as the
    // `color-scheme` the phone screen should render form controls in.
    '--sc-canvas': theme.config?.colorMode === 'light' ? 'light' : 'dark',

    // --- Brand colours ---
    '--sc-primary': toCss(primaryColor()),
    '--sc-background': toCss(backgroundColor()),
    '--sc-text': toCss(text()),
    '--sc-accent': toCss(accent()),

    // --- Derived ---
    '--sc-primary-50': toCss(primaryColor50()),
    '--sc-primary-dark': toCss(darkPrimary()),
    '--sc-primary-card': toCss(primaryCard()),
    '--sc-primary-button-text': toCss(primaryButtonText()),
    '--sc-text-2nd': toCss(text2nd()),
    '--sc-text-3rd': toCss(text3rd()),
    '--sc-card': toCss(card()),
    '--sc-popup': toCss(popup()),
    '--sc-divider': toCss(divider()),

    // --- Status / semantic (never brandable) ---
    '--sc-hyperlink': toCss(HYPERLINK),
    '--sc-good-green': toCss(GOOD_GREEN),
    '--sc-ok-yellow': toCss(OK_YELLOW),
    '--sc-bad-red': toCss(BAD_RED),

    // --- Fonts ---
    '--sc-font-body': bodyStack,
    '--sc-font-display': displayStack,

    // --- Radii ---
    '--sc-radius-big': px(SC.radiusBig),
    '--sc-radius-small': px(SC.radiusSmall),
    '--sc-radius-circle': px(SC.radiusCircle),

    // --- Padding / spacing ---
    '--sc-padding-big': px(SC.paddingBig),
    '--sc-padding-small': px(SC.paddingSmall),
    '--sc-spacing-big': px(SC.spacingBig),
    '--sc-spacing-large': px(SC.spacingLarge),
    '--sc-spacing-medium': px(SC.spacingMedium),
    '--sc-spacing-small': px(SC.spacingSmall),
    '--sc-spacing-tiny': px(SC.spacingTiny),
    '--sc-screen-padding-x': px(SC.screenHorizontalPadding),

    // --- Borders ---
    '--sc-button-border': px(SC.buttonBorder),
    '--sc-button-border-size': px(SC.buttonBorderSize),
    '--sc-divider-thickness': px(SC.dividerThickness),

    // --- Icons ---
    '--sc-icon-weight': String(SC.iconWeight),
    '--sc-icon-xs': px(SC.iconSizeXs),
    '--sc-icon-sm': px(SC.iconSizeSm),
    '--sc-icon-md': px(SC.iconSizeMd),
    '--sc-icon-lg': px(SC.iconSizeLg),
    '--sc-icon-xl': px(SC.iconSizeXl),
    '--sc-icon-2xl': px(SC.iconSize2xl),

    // --- Pills ---
    '--sc-pill-height-sm': px(SC.pillHeightSm),
    '--sc-pill-height-md': px(SC.pillHeightMd),

    // --- Type ramp (body slot) ---
    '--sc-type-h1': typeShorthand(700, 24, bodyStack),
    '--sc-type-h1-ls': letterSpacing(-0.02),
    '--sc-type-h1-regular': typeShorthand(500, 24, bodyStack),
    '--sc-type-h1-regular-ls': letterSpacing(-0.02),
    '--sc-type-h2': typeShorthand(600, 16, bodyStack),
    '--sc-type-h2-ls': letterSpacing(0),
    '--sc-type-h2-regular': typeShorthand(400, 16, bodyStack),
    '--sc-type-h2-regular-ls': letterSpacing(0.03),
    '--sc-type-h2-bold': typeShorthand(700, 16, bodyStack),
    '--sc-type-h2-bold-ls': letterSpacing(0),
    '--sc-type-h3': typeShorthand(600, 13, bodyStack),
    '--sc-type-h3-ls': letterSpacing(0),
    '--sc-type-p': typeShorthand(400, 12, bodyStack),
    '--sc-type-p-ls': letterSpacing(0.03),
    '--sc-type-p-big': typeShorthand(400, 16, bodyStack),
    '--sc-type-p-big-ls': letterSpacing(0.03),
    '--sc-type-p-small': typeShorthand(400, 11, bodyStack),
    '--sc-type-p-small-ls': letterSpacing(0.03),

    // --- Hero numerals (display slot; no letterSpacing in Dart) ---
    '--sc-type-big1': typeShorthand(600, 160, displayStack),
    '--sc-type-big1-ls': 'normal',
    '--sc-type-big1-5': typeShorthand(600, 64, displayStack),
    '--sc-type-big1-5-ls': 'normal',
    '--sc-type-big2': typeShorthand(600, 32, displayStack),
    '--sc-type-big2-ls': 'normal',
  };
}

/**
 * The vars as a React `style` value. React's `CSSProperties` has no index
 * signature for custom properties, so the cast is unavoidable — it is made
 * exactly once, here.
 */
export function showcaseStyle(vars: ShowcaseCssVars, extra?: CSSProperties): CSSProperties {
  return { ...vars, ...extra } as unknown as CSSProperties;
}
