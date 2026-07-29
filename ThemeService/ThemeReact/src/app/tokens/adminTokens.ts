// Ports ../../../../../CRM/lib/core/constants/design_constants.dart —
// the LIGHT half only.
//
// WHY LIGHT ONLY: `DesignConstants` resolves every colour through
// `themeController.isDark`, so the CRM ships both palettes. The standalone
// theme browser is deliberately light-only (see ../../../../../CRM/CLAUDE.md),
// so the `_d*` constants and the getter indirection have nothing to resolve
// here — the `_l*` values are ported as plain constants and the dark palette is
// out of scope by design, not by omission.
//
// The values below are the CRM's, byte for byte: `_lBackground`, `_lSurface`,
// `_lText`, `_lText2nd`, `_lText3rd`, `_lLine`, `_lPrimary`, `_lAccentDark`,
// `_lCardShadow`, `_lButtonShadow`, the spacing/radius/icon scale, the nav
// dims, and the Geist type ramp.
//
// This is the ADMIN chrome's token system. The landing page's own `GW` tokens
// live in ./gw.ts (`--gw-*`); the showcase island's tokens are a third system
// that must never meet either (eslint.config.js Gates 2a/2b).

/**
 * `Color.fromARGB(a, r, g, b)` ported as a CSS `rgba()` string — the alpha is
 * a 0-255 byte in Dart and a 0-1 fraction in CSS.
 */
function argb(a: number, r: number, g: number, b: number): string {
  return `rgba(${r},${g},${b},${round(a / 255)})`;
}

/** Two decimal places, so the emitted strings stay readable. */
function round(value: number): number {
  return Math.round(value * 100) / 100;
}

export const ADM = {
  // ── Ground / surfaces / ink ramp (the daylit control desk). ──
  /** `_lBackground` — the page ground. */
  ground: '#F3F5F8',
  /** `_lSurface`, and with it `surface` / `card` (a card IS the surface). */
  surface: '#FFFFFF',
  /** `_lText` — the ink. */
  ink: '#16181D',
  /** `_lText2nd` — muted copy. */
  text2nd: '#565B66',
  /** `_lText3rd` — faintest ink; NON-TEXT roles only (placeholder glyphs). */
  text3rd: '#878D99',
  /** `_lLine` = `Color.fromARGB(23, 20, 22, 30)` — the ink at ~9%. */
  line: argb(23, 20, 22, 30),
  /** `_lLineSoft` = `Color.fromARGB(15, 20, 22, 30)` — the ink at ~6%. */
  lineSoft: argb(15, 20, 22, 30),

  // ── Accent — the single brand blue + its gradient partner. ──
  /** `_lPrimary` — "sapphire". */
  sapphire: '#2A67BD',
  /** `_lAccentDark` — the gradient's bottom stop. */
  accentDark: '#1F5099',
  /** `onAccent` in light mode: `_lSurface`. The label on a sapphire fill. */
  onAccent: '#FFFFFF',

  // ── Elevation. Soft, layered, diffuse, faintly blue. ──
  /** `_lCardShadow` — two layers. */
  cardShadow: `0 1px 2px ${argb(13, 20, 22, 40)}, 0 18px 30px -10px ${argb(31, 20, 22, 50)}`,
  /** `_lButtonShadow` — the sapphire CTA lift. */
  buttonShadow: `0 1px 2px ${argb(82, 15, 45, 95)}, 0 8px 22px -6px ${argb(128, 30, 80, 160)}`,
  /** `_lControlShadow` — the neutral lift under a small control. */
  controlShadow: `0 1px 2px ${argb(13, 20, 22, 40)}`,

  // ── The preview phone's device body. Deliberately NOT on the ink ramp: a
  // device should read as a real phone, so light mode paints it near-black.
  /** `deviceBody` in light mode: `_lText`. */
  deviceBody: '#16181D',
  /** `deviceShadow` in light mode: `_lText` at 25%. */
  deviceShadow: 'rgba(22,24,29,0.25)',

  // ── Design values (theme-independent in the CRM too). ──
  radiusBig: 12,
  radiusSmall: 8,
  /** Rounder corner for object cards (landing card cells ≈ 22px). */
  radiusCard: 20,

  paddingBig: 32,
  paddingSmall: 16,

  spacingBig: 32,
  spacingLarge: 16,
  spacingMedium: 8,
  spacingSmall: 4,
  spacingTiny: 2,

  /** `buttonBorder` — the outline button's stroke. */
  buttonBorder: 2,
  /** `buttonBorderSize` — the heavier active-card stroke. */
  buttonBorderSize: 3,
  /**
   * `iconWeight` — Material Symbols' variable weight axis. Ported as the SVG
   * stroke width of ../widgets/icons.tsx, scaled to the 24px glyph box.
   */
  iconWeight: 300,

  // Icon sizes — same Big→Tiny cadence as spacing. Medium (20) is the default.
  iconSizeBig: 32,
  iconSizeLarge: 24,
  iconSizeMedium: 20,
  iconSizeSmall: 18,
  iconSizeTiny: 16,

  /** Two lines of h2, so every card's title block is the same height. */
  rewardCardTitleHeight: 42,
  /** A glyph-scale box, deliberately distinct from `iconSize*`. */
  spinnerSizeLarge: 32,

  // Landing-style top nav (LandingPage/hifi/chrome.jsx GWNav).
  navHeight: 68,
  navMaxWidth: 1180,
  /** Below this the nav collapses to a hamburger (ds.jsx `MOBILE_Q`). */
  navMobileBreakpoint: 768,
  navMenuButtonSize: 42,

  // ── Type. Geist, the landing page's typeface (ds.jsx `sans`). ──
  /**
   * `baseFont` = `GoogleFonts.geist(...)`. The web equivalent is the family
   * NAME plus a `loadFontFamily` injection — see ../App.tsx.
   */
  fontFamily: 'Geist',

  /**
   * The type ramp. `letterSpacing` is an ABSOLUTE pixel value in Flutter and
   * does not scale with font size, so every entry here ports to `px` and never
   * `em` (see ../../../CLAUDE.md, "Two things that will bite"). The one
   * legitimate proportional case is the library card's category label.
   */
  type: {
    /** H1 — bold, 24. */
    h1: { size: 24, weight: 700, tracking: -0.6 },
    /** H2 — semibold, 16. */
    h2: { size: 16, weight: 600, tracking: -0.2 },
    /** H3 — semibold, 13. */
    h3: { size: 13, weight: 600, tracking: 0 },
    /** Paragraph — regular, 12. */
    p: { size: 12, weight: 400, tracking: 0.03 },
    /** `pBig` — paragraph at 16 (the filter pills' label). */
    pBig: { size: 16, weight: 400, tracking: 0.03 },
    /** `pSmall` — paragraph at 11. */
    pSmall: { size: 11, weight: 400, tracking: 0.03 },
    /** `pSmallBold` — `pSmall` at w700 (the "Active" pill). */
    pSmallBold: { size: 11, weight: 700, tracking: 0.03 },
  },
} as const;
